extends Node2D
## Main v0.2: character select -> multi-weapon auto-combat -> 30 floors with
## elite floors (x3), boss floors (x5), relics, victory at floor 30.

const PlayerScene := preload("res://scenes/player.tscn")
const EnemyScene := preload("res://scenes/enemy.tscn")
const BossScript := preload("res://scripts/boss.gd")
const ChestScript := preload("res://scripts/chest.gd")
const WaveDirectorScript := preload("res://systems/wave_director.gd")
const RoomGenScript := preload("res://systems/room_gen.gd")
const TerrainGenScript := preload("res://systems/terrain.gd")
const TerrainLayerScript := preload("res://scripts/terrain_layer.gd")


class BrambleZone extends Node2D:
	# 荆棘丛（L3）：区域减速 + 周期伤害
	var radius := 130.0
	var tick_dmg := 10.0
	var _t := 0.0
	var _tick := 0.0
	func _ready() -> void:
		FX.glow_ring(get_parent(), global_position, radius * 2.4,
			Color(0.35, 0.9, 0.4, 0.6), 0.4, 4)
	func _process(d: float) -> void:
		_t += d
		_tick -= d
		queue_redraw()
		# v0.8.20：在范围内每帧压住减速（之前 0.5s 脉冲一次、0.225s 就回满，减速断断续续）
		var pl := get_tree().get_first_node_in_group("player") as Node2D
		var inside := pl != null and is_instance_valid(pl) \
				and global_position.distance_to(pl.global_position) <= radius
		if inside:
			pl.set("external_slow_mult", 0.55)
		if _tick <= 0.0:
			_tick = 0.5
			if inside:
				if pl.has_method("take_damage"):
					pl.take_damage(tick_dmg,
						(pl.global_position - global_position).normalized(), 0.5)
		if _t >= 6.0:
			queue_free()
	func _draw() -> void:
		var fade := clampf(1.0 - _t / 6.0, 0.0, 1.0)
		draw_circle(Vector2.ZERO, radius, Color(0.25, 0.75, 0.3, 0.14 + 0.10 * fade))
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 40, Color(0.3, 0.85, 0.35, 0.55 * fade), 4.0)
		for i in range(8):
			var a := TAU * float(i) / 8.0 + _t * 0.6
			draw_line(Vector2.ZERO, Vector2.RIGHT.rotated(a) * radius,
				Color(0.3, 0.8, 0.35, 0.5 * fade), 3.0)
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
var _cine_mod: CanvasModulate = null
var _cine_tween: Tween = null
var _director: WaveDirector = null
var _floor_has_waves := false
var _wave_ui_t := 0.0
var _room = null  # RoomGen 实例（无类型：无头驱动编译图认不出新 class_name）
var _terrain_patches: Array = []  # v0.8.5 地形块（TerrainGen 产出）
var _terrain_layer: Node2D = null
var _terrain_tick_t := 0.0
var _terrain_hints_shown := {}
var _wave_hp_m := 1.0
var _wave_dmg_m := 1.0
var _last_advance_msec := -99999


func _ready() -> void:
	add_to_group("game")
	# v0.8.22 伪3D：子节点按 Y 排序（同 z_index 内）。墙按行拆节点、柱子独立节点，
	# 与玩家/怪/掉落同级排序：贴上墙角色盖过墙跟，贴下墙角色被墙盖住。
	y_sort_enabled = true
	arena = StaticBody2D.new()
	arena.set_script(ArenaScript)
	arena.name = "Arena"
	add_child(arena)

	# v0.8.5 地形视觉层：压在地板之上、角色之下。
	# 用 z 0 + 树序保证层级（arena 先加→最下；地形层第二；角色/怪/掉落都是开局后才加→最上）。
	# 注意：z_index 会压倒树序，所以地形层绝不能用 z 1（曾经把它画到角色头上）。
	_terrain_layer = Node2D.new()
	_terrain_layer.set_script(TerrainLayerScript)
	_terrain_layer.name = "TerrainLayer"
	_terrain_layer.z_index = 0
	add_child(_terrain_layer)

	_director = WaveDirectorScript.new()
	_director.name = "WaveDirector"
	add_child(_director)
	_director.spawn_wave.connect(_on_wave_spawn)
	_director.stairs_ready.connect(_on_director_stairs)
	_director.wave_announced.connect(_on_wave_announced)
	_director.tick_warning.connect(_on_director_tick_warning)
	_cine_mod = CanvasModulate.new()
	_cine_mod.name = "CineModulate"
	add_child(_cine_mod)
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
	# 先于 Player 的物理帧同步外部输入，避免摇杆输入晚一帧导致角色看起来不动。
	if _started and is_instance_valid(player):
		player.external_move = hud.get_move_vector()
	# v0.8 B4：每物理帧首行重建空间网格（EntityRegistry）
	Registry.begin_frame()
	# v0.8.5 地形：移速/摩擦逐帧写入，持续伤害 0.5s 结算
	if _started:
		_tick_terrain(_delta)
	# B6/B7：波次计时条 + 生存评分 0.25s 节流刷新
	_wave_ui_t += _delta
	if _wave_ui_t >= 0.25:
		_wave_ui_t = 0.0
		if _started:
			_refresh_wave_hud()


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
	for ch in get_tree().get_nodes_in_group("chests"):
		if is_instance_valid(ch):
			ch.queue_free()
	_boss_ref = null
	if _director != null:
		_director.stop()
	_floor_has_waves = false
	# L4：Boss 层开放竞技场；普通层按 seed 生成房间布局
	if GameData.is_boss_floor(floor_num):
		_room = null
		arena.clear_room_walls()
	else:
		var fdef: Dictionary = GameData.floor_def(floor_num)
		var rseed := absi(hash(String(fdef.get("theme", "dungeon")) + ":" + str(floor_num)))
		_room = RoomGenScript.new()
		_room.generate(rseed)
		arena.build_room_walls(_room.merged_wall_rects(), _room.grid)
	hud.hide_boss_bar()
	var fdef: Dictionary = GameData.floor_def(floor_num)
	arena.set_theme(String(fdef["theme"]))
	_build_terrain(String(fdef["theme"]))
	if GameData.is_boss_floor(floor_num):
		var bdef: Dictionary = GameData.boss_def_for_floor(floor_num)
		hud.set_floor(floor_num, ("无尽Boss:" if endless else "Boss:") + String(bdef["name"]))
	else:
		hud.set_floor(floor_num, ("[无尽] " if endless else "") + String(fdef["name"]))
	player.global_position = Vector2(ARENA_W * 0.5, ARENA_H * 0.5)
	player.velocity = Vector2.ZERO
	_spawn_floor_enemies()
	if GameData.is_boss_floor(floor_num):
		EventBus.bgm_duck.emit(true)
	else:
		EventBus.bgm_duck.emit(false)
	_maybe_spawn_chest()
	_update_enemy_label()


func _spawn_floor_enemies() -> void:
	var hp_m := GameData.enemy_hp_mult(floor_num)
	var dmg_m := GameData.enemy_dmg_mult(floor_num)
	if GameData.is_boss_floor(floor_num):
		var bdef: Dictionary = GameData.boss_def_for_floor(floor_num)
		if bool(bdef.get("twin", false)):
			# 双生亡语者：双体各 50% 血，一死另一狂暴（01 §4.3）
			var half := float(bdef["hp"]) * 0.5
			var da: Dictionary = bdef.duplicate(true)
			da["hp"] = half
			var db: Dictionary = bdef.duplicate(true)
			db["hp"] = half
			db["tex"] = String(bdef.get("tex_b", bdef["tex"]))
			var ba := CharacterBody2D.new()
			ba.set_script(BossScript)
			ba.setup(da, Vector2(ARENA_W * 0.5 - 150.0, 320.0))
			var bb := CharacterBody2D.new()
			bb.set_script(BossScript)
			bb.setup(db, Vector2(ARENA_W * 0.5 + 150.0, 320.0))
			ba.twin_partner = bb
			bb.twin_partner = ba
			# L3：双体共享一个血池（HUD 一条，半血双狂暴）
			var pool := {"hp": float(bdef["hp"]), "max": float(bdef["hp"])}
			ba.shared_pool = pool
			bb.shared_pool = pool
			for b in [ba, bb]:
				b.died.connect(_on_enemy_died)
				b.hp_changed.connect(_on_boss_hp)
				add_child(b)
			_boss_ref = ba
			hud.show_boss_bar(String(bdef["name"]))
		else:
			var b := CharacterBody2D.new()
			b.set_script(BossScript)
			b.setup(bdef, Vector2(ARENA_W * 0.5, 320.0))
			b.died.connect(_on_enemy_died)
			b.hp_changed.connect(_on_boss_hp)
			add_child(b)
			_boss_ref = b
			hud.show_boss_bar(String(bdef["name"]))
		# Boss 层也保持较高场面密度，避免开放竞技场下陪战单位过少
		var comp := {"slime": 3, "bat": 3}
		for eid in comp.keys():
			for i in range(int(comp[eid])):
				_spawn_enemy(String(eid), hp_m, dmg_m, false)
		return
	var comp: Dictionary = GameData.floor_comp(floor_num)
	# v0.8 精英规则：固定 2 只，按基础 HP 从高到低分配（GameData.elite_assignment）
	var elite_asg: Dictionary = GameData.elite_assignment(floor_num)
	var elite_kind := GameData.elite_kind_for(floor_num)
	if _waves_on():
		# L3 波次制：导演按 60/25/15 拆波，第一波立即放出
		_floor_has_waves = true
		_wave_hp_m = hp_m
		_wave_dmg_m = dmg_m
		_director.start_floor(comp, elite_asg)
	else:
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
	e.pf_grid = _room.pf_grid if _room != null else PackedByteArray()
	e.position = _spawn_pos()
	e.died.connect(_on_enemy_died)
	add_child(e)
	if e.has_meta("pooled_reuse"):
		e.remove_meta("pooled_reuse")
		e.spawn_init()
	if is_elite:
		EventBus.elite_spawned.emit(e.position)


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
	if _room != null and is_instance_valid(player):
		return _room.random_floor_cell_far(player.global_position, 340.0)
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
	if is_boss and bool(e.get("is_twin")):
		var partner: Node = e.get("twin_partner")
		if partner != null and is_instance_valid(partner) and not bool(partner.get("dead")):
			# 双生第一体：不掉落不结算，等第二体
			_update_enemy_label()
			return
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
		EventBus.bgm_duck.emit(false)
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
	# v0.8 权重掉落（loot.gd）：精英 45%，Boss 保底稀有+；排除已持有
	if not guaranteed and randf() > 0.45:
		return
	var owned: Array = player.relics if is_instance_valid(player) else []
	var rid := Loot.roll_relic(owned, "稀有" if guaranteed else "")
	if rid == "":
		return
	_spawn_gem(pos, "relic", 0, rid)


func _clear_minions() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and not bool(e.get("dead")) and not bool(e.get("is_boss")):
			e.queue_free()
	_update_enemy_label()


## v0.8 合成演出聚焦：全屏微暗（05 附录 T0 0.85 → T+1400 复原）
func set_cine_dim(v: float) -> void:
	if _cine_mod == null:
		return
	if _cine_tween != null and _cine_tween.is_valid():
		_cine_tween.kill()
	_cine_tween = create_tween()
	_cine_tween.set_ignore_time_scale(true)
	_cine_tween.tween_property(_cine_mod, "color", Color(v, v, v), 0.15)


## 非 Boss 层 15% 刷宝箱（01 §4.2），位置离出生点 >300px
func _maybe_spawn_chest() -> void:
	if GameData.is_boss_floor(floor_num) or randf() >= 0.15:
		return
	var center := Vector2(ARENA_W * 0.5, ARENA_H * 0.5)
	var pos: Vector2 = _room.farthest_room_center(center, true) if _room != null else _spawn_pos()
	if _room == null:
		for i in range(8):
			if pos.distance_to(center) > 300.0:
				break
			pos = _spawn_pos()
	var chest := Node2D.new()
	chest.set_script(ChestScript)
	chest.position = pos
	add_child(chest)


## 宝箱掉落结算：遗物（权重 roll）+ 30–60 金分 3 颗
func spawn_chest_loot(pos: Vector2) -> void:
	var owned: Array = player.relics if is_instance_valid(player) else []
	var rid := Loot.roll_relic(owned)
	if rid != "":
		_spawn_gem(pos + Vector2(0, -18), "relic", 0, rid)
	var total := randi_range(30, 60)
	var third := total / 3
	for i in range(3):
		var v := third if i < 2 else total - 2 * third
		_spawn_gem(pos + Vector2(randf_range(-44, 44), randf_range(-30, 30)), "gold", v, "")


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


func _spawn_stairs(force_pos: Vector2 = Vector2(-1, -1)) -> void:
	if _stairs != null or not _started:
		return
	if force_pos.x >= 0.0:
		_stairs = Area2D.new()
		_stairs.set_script(StairsScript)
		_stairs.position = force_pos
		add_child(_stairs)
		hud.set_enemies(0)
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


func _waves_on() -> bool:
	return bool(ProjectSettings.get_setting("dungeon/waves_enabled", true))


func _on_wave_spawn(entries: Array) -> void:
	for e in entries:
		_spawn_enemy(String(e["kind"]), _wave_hp_m, _wave_dmg_m, bool(e["elite"]))


func _on_wave_announced(n: int, total: int) -> void:
	EventBus.wave_started.emit(n, total)


func _on_director_tick_warning(sec: int) -> void:
	EventBus.floor_timer_warning.emit(sec)


func _on_director_stairs() -> void:
	# 计时 70s 到期：直接出楼梯（不要求清怪）
	if _started and _stairs == null and not GameData.is_boss_floor(floor_num):
		_spawn_stairs(_room_farthest_pos())


func _refresh_wave_hud() -> void:
	if _floor_has_waves and _director != null and _director.active and _started:
		hud.set_floor_timer(_director.time_left(), WaveDirector.FLOOR_TIME)
	else:
		hud.hide_floor_timer()
	hud.set_score(_run_score())


## 生存评分（01 §5.1）：层数×100 + 击杀 + 精英×5 + Boss×50 + 剩余HP×0.5
func _run_score() -> int:
	var score := floor_num * 100 + kills + elite_kills * 5 + boss_kills * 50
	if is_instance_valid(player):
		score += int(maxf(0.0, float(player.get("hp"))) * 0.5)
	return score


func _enemies_alive() -> int:
	var n := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and not bool(e.get("dead")):
			n += 1
	return n


func _update_enemy_label() -> void:
	hud.set_enemies(_enemies_alive())


func _check_floor_clear() -> void:
	if _floor_has_waves and _director != null and not _director.all_spawned():
		return
	if _enemies_alive() == 0 and _stairs == null and _started:
		_spawn_stairs(_room_farthest_pos())


func _room_farthest_pos() -> Vector2:
	if _room != null and is_instance_valid(player):
		return _room.farthest_room_center(player.global_position)
	return Vector2(-1, -1)


# ---------- v0.8.5 地形 ----------
func _build_terrain(theme: String) -> void:
	var center := Vector2(ARENA_W * 0.5, ARENA_H * 0.5)
	var reserved: Array = [center]
	var walkable := PackedByteArray()
	var is_boss := GameData.is_boss_floor(floor_num)
	if _room != null:
		walkable = _room.pf_grid
		reserved.append(_room.farthest_room_center(center))
		reserved.append(_room.farthest_room_center(center, true))
	else:
		walkable.resize(32 * 24)
		walkable.fill(0)
		reserved.append(Vector2(ARENA_W * 0.5, 320.0))
	_terrain_patches = TerrainGenScript.generate(theme, floor_num, walkable,
		reserved, 5 if is_boss else 6)
	_terrain_tick_t = 0.0
	_terrain_hints_shown.clear()
	if _terrain_layer != null:
		_terrain_layer.call("setup", _terrain_patches, theme)
	if is_instance_valid(player):
		player.terrain_speed_mult = 1.0
		player.terrain_accel_mult = 1.0
		player.terrain_friction_mult = 1.0
		player.terrain_id = ""


func _terrain_patch_at(pos: Vector2) -> Dictionary:
	return TerrainGenScript.patch_at(_terrain_patches, pos)


func _tick_terrain(delta: float) -> void:
	if _terrain_patches.is_empty() or not is_instance_valid(player):
		return
	var p_patch := _terrain_patch_at(player.global_position)
	player.terrain_speed_mult = float(p_patch.get("player_speed", 1.0))
	player.terrain_accel_mult = float(p_patch.get("player_accel", 1.0))
	player.terrain_friction_mult = float(p_patch.get("player_friction", 1.0))
	player.terrain_id = String(p_patch.get("id", ""))
	if not p_patch.is_empty():
		var tid := String(p_patch.get("id", ""))
		if not _terrain_hints_shown.has(tid):
			_terrain_hints_shown[tid] = true
			hud.show_terrain_hint(String(p_patch.get("hint", "")))
	var enemy_patches := {}
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or bool(e.get("is_boss")) or bool(e.get("dead")):
			continue
		if bool(e.get("fly")):
			e.set("terrain_speed_mult", 1.0)
			e.set("terrain_id", "")
			continue
		var ep := _terrain_patch_at((e as Node2D).global_position)
		enemy_patches[e.get_instance_id()] = ep
		e.set("terrain_speed_mult", float(ep.get("enemy_speed", 1.0)))
		e.set("terrain_id", String(ep.get("id", "")))
	_terrain_tick_t += delta
	if _terrain_tick_t < 0.5:
		return
	var dt := _terrain_tick_t
	_terrain_tick_t = 0.0
	if not p_patch.is_empty():
		var pdps := float(p_patch.get("player_dps", 0.0))
		if pdps > 0.0:
			player.take_terrain_damage(pdps * dt)
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or bool(e.get("is_boss")) or bool(e.get("dead")) \
				or bool(e.get("fly")):
			continue
		var ep: Dictionary = enemy_patches.get(e.get_instance_id(), {})
		if ep.is_empty():
			continue
		var edps := float(ep.get("enemy_dps", 0.0))
		if edps > 0.0 and e.has_method("take_damage"):
			e.take_damage(edps * dt, Vector2.ZERO, 0.0)


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
## 荆棘暴君 L3：荆棘丛召唤（区域减速 + 周期伤害）
func spawn_bramble(at: Vector2, count: int) -> void:
	var dmg := GameData.enemy_dmg_mult(floor_num) * 8.0
	for i in range(count):
		var zone := BrambleZone.new()
		zone.radius = 130.0
		zone.tick_dmg = dmg
		zone.position = at + Vector2.RIGHT.rotated(randf() * TAU) * randf_range(60.0, 260.0)
		add_child(zone)


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
	player._recalc()  # v0.8.20：继续存档后按被动/遗物重算速度与磁吸（之前残留初始值）
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
