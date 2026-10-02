extends Node2D
## Main v0.2: character select -> multi-weapon auto-combat -> 30 floors with
## elite floors (x3), boss floors (x5), relics, victory at floor 30.

const PlayerScene := preload("res://scenes/player.tscn")
const EnemyScene := preload("res://scenes/enemy.tscn")
const BossScript := preload("res://scripts/boss.gd")
const HudScene := preload("res://scenes/hud.tscn")
const ArenaScript := preload("res://scripts/arena.gd")
const GemScript := preload("res://scripts/gem.gd")
const PoolManager := preload("res://systems/pool_manager.gd")
const StairsScript := preload("res://scripts/stairs.gd")

const ARENA_W := 1600.0
const ARENA_H := 1200.0

var player: Player
var hud: CanvasLayer
var arena: StaticBody2D
var floor_num := 0
var kills := 0
var elite_kills := 0
var boss_kills := 0
var run_time := 0.0
var endless := false
var _started := false
var _elite_hint_shown := false
var _stairs: Area2D = null
var _boss_ref: Node2D = null
var _last_advance_msec := -99999


func _ready() -> void:
	add_to_group("game")
	arena = StaticBody2D.new()
	arena.set_script(ArenaScript)
	arena.name = "Arena"
	add_child(arena)

	hud = HudScene.instantiate()
	hud.name = "HUD"
	add_child(hud)
	hud.character_chosen.connect(_on_character_chosen)
	hud.upgrade_chosen.connect(_on_upgrade_chosen)
	hud.endless_chosen.connect(enter_endless)
	# 从中途存档继续（优先于带角色开局）
	if not RunSave.pending_continue.is_empty():
		var pd: Dictionary = RunSave.pending_continue
		RunSave.pending_continue = {}
		Meta.selected_char = ""  # 避免 _on_character_chosen 抢跑
		continue_run.call_deferred(pd)
	elif Meta.selected_char != "":
		# 从大厅带角色直接开局
		_on_character_chosen.call_deferred(Meta.selected_char)


func _on_character_chosen(char_id: String) -> void:
	if _started:
		return
	if not Meta.is_char_unlocked(char_id):
		return
	_started = true
	# v0.8 D8：大厅无尽直连入口（通关 1 次解锁）
	if Meta.start_endless:
		endless = true
		Meta.start_endless = false
	RunSave.clear()  # 新开局，清除旧的中途存档
	hud.hide_select()
	hud.start_first_run_hints()  # v0.8 D4 新手引导（仅首局）
	player = PlayerScene.instantiate()
	player.character_id = char_id
	player.name = "Player"
	player.position = Vector2(ARENA_W * 0.5, ARENA_H * 0.5)
	add_child(player)
	player.hp_changed.connect(_on_player_hp)
	player.xp_changed.connect(_on_player_xp)
	player.gold_changed.connect(hud.set_gold)
	player.leveled_up.connect(_on_player_leveled)
	player.died.connect(_on_player_died)
	player.relics_changed.connect(_on_relics_changed)
	_on_player_hp(player.hp, player.max_hp)
	_on_player_xp(player.xp, GameData.xp_for_level(player.level), player.level)
	hud.set_gold(0)
	hud.set_kills(0)
	hud.set_relics(player.relics)
	hud.set_weapons(player.weapons)
	hud.set_passives(player.passives)
	hud.bind_player(player)
	hud.set_skills(player.skills)
	next_floor()


func _physics_process(_delta: float) -> void:
	# v0.8 B4：每物理帧首行重建空间网格（EntityRegistry）
	Registry.begin_frame()


func _process(delta: float) -> void:
	if not _started or not is_instance_valid(player):
		return
	run_time += delta
	player.external_move = hud.get_move_vector()


# ---------- floors ----------
func next_floor() -> void:
	# guard against double-advance (e.g. player standing where new stairs spawn)
	if Time.get_ticks_msec() - _last_advance_msec < 1500:
		return
	_last_advance_msec = Time.get_ticks_msec()
	floor_num += 1
	if endless and floor_num in [35, 40, 45, 50, 55, 60]:
		Achievements.unlock("endless%d" % floor_num)
	if floor_num > GameData.MAX_FLOOR and not endless:
		return
	if is_instance_valid(_stairs):
		_stairs.queue_free()
	_stairs = null
	# v0.8 B4：跨层清理残留宝石与尸体（节点数有界，防长局累积）
	for g in get_tree().get_nodes_in_group("pickups"):
		if is_instance_valid(g):
			g.queue_free()
	for c in get_tree().get_nodes_in_group("corpses"):
		if is_instance_valid(c):
			c.queue_free()
	_boss_ref = null
	hud.hide_boss_bar()
	var fdef: Dictionary = GameData.floor_def(floor_num)
	arena.set_theme(String(fdef["theme"]))
	if GameData.is_boss_floor(floor_num):
		var bdef: Dictionary = GameData.boss_def_for_floor(floor_num)
		hud.set_floor(floor_num, ("无尽Boss:" if endless else "Boss:") + String(bdef["name"]))
	else:
		hud.set_floor(floor_num, ("[无尽] " if endless else "") + String(fdef["name"]))
	player.global_position = Vector2(ARENA_W * 0.5, ARENA_H * 0.5)
	player.velocity = Vector2.ZERO
	_spawn_floor_enemies()
	_update_enemy_label()


func _spawn_floor_enemies() -> void:
	var hp_m := GameData.enemy_hp_mult(floor_num)
	var dmg_m := GameData.enemy_dmg_mult(floor_num)
	if GameData.is_boss_floor(floor_num):
		var bdef: Dictionary = GameData.boss_def_for_floor(floor_num)
		var b := CharacterBody2D.new()
		b.set_script(BossScript)
		b.setup(bdef, Vector2(ARENA_W * 0.5, 320.0))
		b.died.connect(_on_enemy_died)
		b.hp_changed.connect(_on_boss_hp)
		add_child(b)
		_boss_ref = b
		hud.show_boss_bar(String(bdef["name"]))
		# a few minions for company
		var comp := {"slime": 2, "bat": 2}
		for eid in comp.keys():
			for i in range(int(comp[eid])):
				_spawn_enemy(String(eid), hp_m, dmg_m, false)
		return
	var comp: Dictionary = GameData.floor_comp(floor_num)
	# v0.8 精英规则：固定 2 只，按基础 HP 从高到低分配（GameData.elite_assignment）
	var elite_asg: Dictionary = GameData.elite_assignment(floor_num)
	var elite_kind := GameData.elite_kind_for(floor_num)
	for eid in comp.keys():
		var elite_left := int(elite_asg.get(eid, 0))
		for i in range(int(comp[eid])):
			var is_elite := elite_left > 0
			if is_elite:
				elite_left -= 1
			_spawn_enemy(String(eid), hp_m, dmg_m, is_elite)
	# D4：第 3 层首只精英提示（每局一次）
	if floor_num == 3 and elite_kind != "" and not _elite_hint_shown:
		_elite_hint_shown = true
		hud.show_toast(Lang.t("精英会掉落遗物"))


## v0.8 B4：敌人获取（池化复用时补跑 spawn_init，_ready 不会重跑）
func _acquire_enemy() -> Enemy:
	var e: Enemy = PoolManager.acquire("enemy", func() -> Node: return EnemyScene.instantiate()) as Enemy
	return e


func _spawn_enemy(eid: String, hp_m: float, dmg_m: float, is_elite: bool) -> void:
	var e: Enemy = _acquire_enemy()
	e.enemy_id = eid
	e.hp_mult = hp_m
	e.dmg_mult = dmg_m
	e.elite = is_elite
	e.position = _spawn_pos()
	e.died.connect(_on_enemy_died)
	add_child(e)
	if e.has_meta("pooled_reuse"):
		e.remove_meta("pooled_reuse")
		e.spawn_init()


## boss summon helper
func spawn_boss_minions(at: Vector2, count: int) -> void:
	var hp_m := GameData.enemy_hp_mult(floor_num)
	var dmg_m := GameData.enemy_dmg_mult(floor_num)
	var ids := ["slime", "bat", "skeleton"]
	for i in range(count):
		var e: Enemy = _acquire_enemy()
		e.enemy_id = ids[i % ids.size()]
		e.hp_mult = hp_m
		e.dmg_mult = dmg_m
		e.elite = false
		e.position = at + Vector2.RIGHT.rotated(randf() * TAU) * randf_range(120.0, 220.0)
		e.died.connect(_on_enemy_died)
		add_child(e)
		if e.has_meta("pooled_reuse"):
			e.remove_meta("pooled_reuse")
			e.spawn_init()
	_update_enemy_label()


func _spawn_pos() -> Vector2:
	for attempt in range(40):
		var p := Vector2(randf_range(90.0, ARENA_W - 90.0), randf_range(90.0, ARENA_H - 90.0))
		if p.distance_to(player.global_position) > 340.0:
			return p
	return Vector2(200, 200)


func _on_enemy_died(e: Node2D) -> void:
	kills += 1
	Meta.add_total_kills(1)
	var tk := Meta.total_kills()
	if tk >= 1000:
		Achievements.unlock("kill1000")
	if tk >= 5000:
		Achievements.unlock("kill5000")
	if bool(e.get("elite")):
		elite_kills += 1
	hud.set_kills(kills)
	if is_instance_valid(player):
		player.on_enemy_died(e)
	var is_boss := bool(e.get("is_boss"))
	if is_boss:
		boss_kills += 1
		Meta.record_boss_kill(floor_num)
		Achievements.unlock(GameData.boss_ach_id(floor_num))
		_spawn_gem(e.global_position, "xp", 40, "")
		_spawn_gem(e.global_position, "gold", 40 * (floor_num / 5), "")
		_drop_relic(e.global_position, true)
		var bdef: Dictionary = GameData.boss_def_for_floor(floor_num)
		if not endless and bool(bdef.get("final", false)):
			_on_victory()
			return
		_clear_minions()
		_spawn_stairs()
		return
	_spawn_gem(e.global_position, "xp", int(e.get("xp_value")), "")
	if randf() < 0.45:
		_spawn_gem(e.global_position, "gold", randi_range(1, 3), "")
	if bool(e.get("elite")):
		_drop_relic(e.global_position, false)
	_update_enemy_label()
	# floor cleared -> stairs appear (deferred one frame so group updates)
	_check_floor_clear.call_deferred()


func _drop_relic(pos: Vector2, guaranteed: bool) -> void:
	if not guaranteed and randf() > 0.30:
		return
	var rid: String = GameData.RELIC_ORDER[randi() % GameData.RELIC_ORDER.size()]
	_spawn_gem(pos, "relic", 0, rid)


func _clear_minions() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and not bool(e.get("dead")) and not bool(e.get("is_boss")):
			e.queue_free()
	_update_enemy_label()


func _spawn_gem(pos: Vector2, kind: String, value: int, relic_id: String) -> void:
	var g: Node2D = PoolManager.acquire("gem", func() -> Node:
		var np := Node2D.new()
		np.set_script(GemScript)
		return np) as Node2D
	g.setup(kind, value, pos, relic_id)
	add_child(g)
	if g.has_meta("pooled_reuse"):
		g.remove_meta("pooled_reuse")
		g.spawn_init()


func _spawn_stairs() -> void:
	if _stairs != null or not _started:
		return
	_stairs = Area2D.new()
	_stairs.set_script(StairsScript)
	# random offset from center: the player is usually standing at the old
	# stairs (= center), a new stairs right under them would retrigger instantly
	var off := Vector2.RIGHT.rotated(randf() * TAU) * randf_range(280.0, 520.0)
	var p := Vector2(ARENA_W * 0.5, ARENA_H * 0.5) + off
	p.x = clampf(p.x, 120.0, ARENA_W - 120.0)
	p.y = clampf(p.y, 120.0, ARENA_H - 120.0)
	_stairs.position = p
	add_child(_stairs)
	hud.set_enemies(0)


func _enemies_alive() -> int:
	var n := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and not bool(e.get("dead")):
			n += 1
	return n


func _update_enemy_label() -> void:
	hud.set_enemies(_enemies_alive())


func _check_floor_clear() -> void:
	if _enemies_alive() == 0 and _stairs == null and _started:
		_spawn_stairs()


# ---------- shared combat visuals ----------
## 尸体标记（尸爆用）
func spawn_corpse(pos: Vector2, elite: bool) -> void:
	# 同一位置尸体太多则跳过（防尸潮卡顿）
	var near := 0
	for c in get_tree().get_nodes_in_group("corpses"):
		if is_instance_valid(c) and pos.distance_to(c.global_position) < 60.0:
			near += 1
	if near >= 3:
		return
	var c := Corpse.new()
	c.setup(pos, elite)
	add_child(c)
## explosion that hurts ENEMIES (shotgun sig, corpse effects...)
func spawn_explosion(pos: Vector2, radius: float, dmg: float,
		crit_chance: float, crit_mult: float, exclude: Node2D = null) -> void:
	_explosion_fx(pos, radius, Color(1.0, 0.75, 0.3))
	for e in Registry.query_circle(pos, radius):
		if not is_instance_valid(e) or bool(e.get("dead")) or e == exclude:
			continue
		var to: Vector2 = e.global_position - pos
		if to.length() <= radius:
			var d := dmg * crit_mult if randf() < crit_chance else dmg
			e.take_damage(d, to.normalized() if to.length() > 1.0 else Vector2.UP)


## hazard that hurts the PLAYER (boss slam)
func spawn_hazard(pos: Vector2, radius: float, dmg: float, source: Node2D = null) -> void:
	_explosion_fx(pos, radius, Color(1.0, 0.3, 0.25))
	if is_instance_valid(player):
		var to: Vector2 = player.global_position - pos
		if to.length() <= radius:
			player.take_damage(dmg, to.normalized() if to.length() > 1.0 else Vector2.UP, 1.0, source)


func _explosion_fx(pos: Vector2, radius: float, tint: Color) -> void:
	var tex_id := "fx_explosion_s"
	if radius > 170.0:
		tex_id = "fx_explosion_l"
	elif radius > 110.0:
		tex_id = "fx_explosion_m"
	var fx := Node2D.new()
	var sp := Sprite2D.new()
	sp.texture = load("res://assets/sprites/fx/%s.png" % tex_id) as Texture2D
	sp.modulate = tint
	fx.add_child(sp)
	fx.global_position = pos
	fx.z_index = 5
	add_child(fx)
	var target_scale := radius / 64.0
	fx.scale = Vector2.ONE * target_scale * 0.4
	var tw := fx.create_tween()
	tw.set_parallel(true)
	tw.tween_property(fx, "scale", Vector2.ONE * target_scale, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(sp, "modulate:a", 0.0, 0.4)
	tw.chain().tween_callback(fx.queue_free)
	# juice: expanding ring + sparks + additive glow + shake
	FX.explosion(self, pos, radius, tint)


# ---------- player signal handlers ----------
func _on_player_hp(hp: float, max_hp: float) -> void:
	hud.set_hp(hp, max_hp, String(GameData.CHARACTERS[player.character_id]["name"]))


func _on_player_xp(xp: int, need: int, level: int) -> void:
	hud.set_xp(xp, need, level)


func _on_relics_changed() -> void:
	hud.set_relics(player.relics)
	hud.set_weapons(player.weapons)
	hud.set_passives(player.passives)


func _on_boss_hp(hp: float, max_hp: float) -> void:
	hud.set_boss_hp(hp, max_hp)


func _on_player_leveled() -> void:
	if is_instance_valid(player):
		FX.levelup_beam(self, player.global_position)
	get_tree().paused = true
	hud.show_levelup(player.build_levelup_options())


func _on_upgrade_chosen(opt: Dictionary) -> void:
	if is_instance_valid(player):
		player.apply_levelup_option(opt)
		hud.set_weapons(player.weapons)
		hud.set_passives(player.passives)
		hud.set_skills(player.skills)
	if is_instance_valid(player) and player.has_pending_levels():
		hud.show_levelup(player.build_levelup_options())
	else:
		get_tree().paused = false


func _on_player_died() -> void:
	_bank_run_gold(false)
	RunSave.clear()  # 死亡，存档作废
	if endless:
		var sc := _endless_score()
		Meta.record_endless(floor_num, sc)
		hud.show_endless_death(floor_num, sc, _last_banked)
	else:
		hud.show_death(_last_banked)
	get_tree().paused = true


func _on_victory() -> void:
	var first_clear := Meta.victories() == 0
	_bank_run_gold(true)
	RunSave.clear()  # 通关，存档作废（无尽模式在 enter_endless 后可重新存）
	if first_clear:
		Achievements.unlock("first_clear")
	get_tree().paused = true
	hud.show_victory(floor_num, kills, run_time, _last_banked)


## 通关后进入无尽：金币已在通关时入库，这里清零重计（×1.5 倍率）
func enter_endless() -> void:
	endless = true
	if is_instance_valid(player):
		player.gold = 0
		player.heal_full()
		hud.set_gold(0)
	_banked = false
	get_tree().paused = false
	hud.hide_victory()
	next_floor()


func _endless_score() -> int:
	var normal := kills - elite_kills - boss_kills
	return floor_num * 100 + normal + elite_kills * 5 + boss_kills * 50


var _banked := false
var _last_banked := 0


func _bank_run_gold(victory: bool) -> void:
	# 单局金币入库 + 战绩（只结算一次）；无尽模式金币 ×1.5
	if _banked:
		return
	_banked = true
	_last_banked = int(player.gold) if is_instance_valid(player) else 0
	if endless:
		_last_banked = int(_last_banked * GameData.ENDLESS_GOLD_MULT)
	if _last_banked > 0:
		Meta.add_gold(_last_banked)
	if victory:
		Meta.add_gold(400)  # v0.8 通关奖励（01 §3.3）
	# v0.8 天赋点按到达层数发放：每 5 层 1 点（01 §3.3）
	Meta.add_talent_points(floor_num / 5)
	Meta.record_run(floor_num, victory)
	Meta.save_data_now()


## ========== 中途存档 ==========

## 保存当前进度。返回是否成功。
func save_run() -> bool:
	if not _started or not is_instance_valid(player):
		return false
	if player.get("_dead"):
		return false
	var data := {
		"char_id": player.character_id,
		"floor_num": floor_num,
		"hp": player.hp,
		"max_hp": player.max_hp,
		"level": player.level,
		"xp": player.xp,
		"run_gold": player.gold,
		"kills": kills,
		"elite_kills": elite_kills,
		"boss_kills": boss_kills,
		"run_time": run_time,
		"endless": endless,
		"weapons": player.weapons.duplicate(true),
		"passives": (player.passives as Dictionary).duplicate(true),
		"relics": player.relics.duplicate(),
		"skills": player.skills.duplicate(true),
	}
	return RunSave.save_run(data)


## 从存档继续。save_data 为 RunSave.load_run() 的结果。
func continue_run(save_data: Dictionary) -> void:
	if _started or save_data.is_empty():
		return
	var char_id := str(save_data.get("char_id", "aila"))
	if not Meta.is_char_unlocked(char_id):
		return
	_started = true
	hud.hide_select()
	player = PlayerScene.instantiate()
	player.character_id = char_id
	player.name = "Player"
	player.position = Vector2(ARENA_W * 0.5, ARENA_H * 0.5)
	add_child(player)
	player.hp_changed.connect(_on_player_hp)
	player.xp_changed.connect(_on_player_xp)
	player.gold_changed.connect(hud.set_gold)
	player.leveled_up.connect(_on_player_leveled)
	player.died.connect(_on_player_died)
	player.relics_changed.connect(_on_relics_changed)
	# 恢复状态
	floor_num = int(save_data.get("floor_num", 1))
	kills = int(save_data.get("kills", 0))
	elite_kills = int(save_data.get("elite_kills", 0))
	boss_kills = int(save_data.get("boss_kills", 0))
	run_time = float(save_data.get("run_time", 0.0))
	endless = bool(save_data.get("endless", false))
	player.max_hp = float(save_data.get("max_hp", 100.0))
	player.hp = minf(float(save_data.get("hp", 100.0)), player.max_hp)
	player.level = int(save_data.get("level", 1))
	player.xp = int(save_data.get("xp", 0))
	player.gold = int(save_data.get("run_gold", 0))
	player.weapons = (save_data.get("weapons", []) as Array).duplicate(true)
	# 容错：补全武器/技能的 cd_t（旧存档可能没有）
	for w in player.weapons:
		if w is Dictionary:
			w["cd_t"] = float(w.get("cd_t", 0.0))
	player.passives = (save_data.get("passives", {}) as Dictionary).duplicate(true)
	player.relics = (save_data.get("relics", []) as Array).duplicate()
	player.skills = (save_data.get("skills", []) as Array).duplicate(true)
	for s in player.skills:
		if s is Dictionary:
			s["cd_t"] = float(s.get("cd_t", 0.0))
			if not s.has("auto"):
				s["auto"] = true
	# 刷新 HUD
	_on_player_hp(player.hp, player.max_hp)
	_on_player_xp(player.xp, GameData.xp_for_level(player.level), player.level)
	hud.set_gold(player.gold)
	hud.set_kills(kills)
	hud.set_relics(player.relics)
	hud.set_weapons(player.weapons)
	hud.set_passives(player.passives)
	hud.bind_player(player)
	hud.set_skills(player.skills)
	hud.show_toast(Lang.t("已读取存档：第%d层") % floor_num)
	# floor_num 已是当前层，next_floor 会 +1，所以先 -1
	floor_num -= 1
	next_floor()


## 保存并返回大厅
func save_and_exit() -> void:
	if save_run():
		hud.show_toast("进度已保存")
	get_tree().paused = false
	_exit_to_lobby()


## 返回大厅（Lobby 场景）
func _exit_to_lobby() -> void:
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")
