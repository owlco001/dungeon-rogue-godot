extends CharacterBody2D
class_name Player
## Playable hero v0.2: 4-direction idle/walk, multi-weapon auto-attacks,
## passives, relics, crit. Movement keeps gait feel (no chess-piece sliding).

signal hp_changed(hp: float, max_hp: float)
signal xp_changed(xp: int, xp_need: int, level: int)
signal gold_changed(gold: int)
signal leveled_up
signal died
signal relics_changed

const ACCEL := 1500.0
const PoolManager := preload("res://systems/pool_manager.gd")
const FRICTION := 1800.0
const BASE_MAGNET_RADIUS := 110.0
const PICKUP_RADIUS := 26.0

var character_id := "aila"
var char_def := {}
var speed := 230.0
var base_speed := 230.0
var base_max_hp := 100.0
var max_hp := 100.0
var hp := 100.0
var level := 1
var xp := 0
var gold := 0
var facing := Vector2.DOWN
var dir_name := "down"
var current_anim := ""
var external_move := Vector2.ZERO

# v0.2 systems
var weapons: Array = []          # [{id, lv, cd_t}]
var passives := {}               # id -> lv
var relics: Array = []           # [relic_id]
var _cross_until_ms := 0
var _cross_aura: Node2D = null
var _cross_aura_t := 0.0
var _punch_start_ms := -1
var _synth_aura: Node2D = null
var external_slow_mult := 1.0  # 荆棘丛区域减速（L3）
# v0.8.5 地形效果（main 每物理帧写入）：移速/加速度/摩擦倍率
var terrain_speed_mult := 1.0
var terrain_accel_mult := 1.0
var terrain_friction_mult := 1.0
var terrain_id := ""
var _relic_tbl_cache: Dictionary = {}
var MAGNET_RADIUS := BASE_MAGNET_RADIUS

# v0.3 systems
var skills: Array = []           # [{id, lv, cd_t, auto}]
# v0.8 三选一选择器状态（07 §2.1）
var _lvups_since_passive := 0    # RC-4 保底计数：连续多少次三选一没出现 passive_up
var _funnel_weapon := ""         # RC-3 漏斗：刚满级的武器 base id（下一次升级消费）
var _lvup_count := 0             # 本局第几次升级（新手强制规则用）
var _shield_hp := 0.0            # 圣盾/虹吸护盾吸收量
var _shield_t := 0.0             # 护盾剩余时间
var _parry_t := 0.0              # 盾击完美格挡窗口
var _parried := false            # 格挡窗口内是否成功格挡
var _riposte := false            # 复仇：下次攻击必暴击
var _aura_node: Node2D = null    # 诅咒光环常驻视觉
var _orbit_nodes := {}           # slot -> Node2D（旋风斧环绕）
var _arrow_rain := {}            # 箭雨进行中状态
var _skill_fx := {}              # 持续技能视觉节点

var _invuln_t := 0.0
var _flash_t := 0.0
var _walk_t := 0.0
var _breathe_t := 0.0
var _dead := false
var _pending_levels := 0
var _revive_used := false
var _revive_talent_used := false
var _regen_t := 0.0

@onready var visual: Node2D = $Visual
@onready var sprite: AnimatedSprite2D = $Visual/AnimatedSprite2D
@onready var dust: CPUParticles2D = $Visual/Dust


func _ready() -> void:
	add_to_group("player")
	char_def = GameData.CHARACTERS[character_id]
	base_speed = float(char_def["speed"])
	base_max_hp = float(char_def["max_hp"])
	speed = base_speed * Meta.bonus_speed_mult()
	max_hp = base_max_hp + Meta.bonus_hp_add()
	hp = max_hp
	add_weapon(String(char_def["weapon"]))
	_build_sprite_frames()
	RelicEffects.attach(self)
	_setup_dust()
	_play("idle_down")
	hp_changed.emit(hp, max_hp)


func heal_full() -> void:
	hp = max_hp
	hp_changed.emit(hp, max_hp)
	xp_changed.emit(xp, GameData.xp_for_level(level), level)
	gold_changed.emit(gold)
	add_skill(GameData.exclusive_skill_of(character_id))


func _tex(cid: String, dirn: String, action: String, frame: int) -> Texture2D:
	var p := "res://assets/sprites/characters/%s/char_%s_%s_%s_%02d.png" % [cid, cid, dirn, action, frame]
	return load(p) as Texture2D


func _add_anim(sf: SpriteFrames, anim_name: String, frames: Array, fps: float) -> void:
	sf.add_animation(anim_name)
	sf.set_animation_speed(anim_name, fps)
	sf.set_animation_loop(anim_name, true)
	for f in frames:
		sf.add_frame(anim_name, f)


func _build_sprite_frames() -> void:
	var sf := SpriteFrames.new()
	for d in ["down", "up", "left", "right"]:
		_add_anim(sf, "idle_" + d, [_tex(character_id, d, "idle", 0)], 2.0)
		var walk: Array = []
		for i in range(4):
			walk.append(_tex(character_id, d, "walk", i))
		_add_anim(sf, "walk_" + d, walk, 9.0)
	sprite.frames = sf


func _setup_dust() -> void:
	dust.amount = 22
	dust.lifetime = 0.45
	dust.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	dust.emission_sphere_radius = 9.0
	dust.direction = Vector2(0, -1)
	dust.spread = 70.0
	dust.initial_velocity_min = 25.0
	dust.initial_velocity_max = 60.0
	dust.gravity = Vector2(0, -40)
	dust.damping_min = 20.0
	dust.damping_max = 60.0
	dust.scale_amount_min = 2.0
	dust.scale_amount_max = 4.5
	dust.color = Color(0.75, 0.7, 0.65, 0.45)
	dust.position = Vector2(0, 50)
	dust.emitting = false


func _physics_process(delta: float) -> void:
	if _dead:
		return
	RelicEffects.tick(delta)
	if _cross_aura_t > 0.0:
		_cross_aura_t -= delta
		if _cross_aura_t <= 0.0 and is_instance_valid(_cross_aura):
			_cross_aura.queue_free()
			_cross_aura = null
	var input_vec := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if external_move.length() > 0.08:
		input_vec = external_move.limit_length(1.0)

	external_slow_mult = move_toward(external_slow_mult, 1.0, 2.0 * delta)
	if input_vec != Vector2.ZERO:
		velocity = velocity.move_toward(
			input_vec * speed * external_slow_mult * terrain_speed_mult,
			ACCEL * terrain_accel_mult * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, FRICTION * terrain_friction_mult * delta)
	move_and_slide()

	if input_vec.length() > 0.1:
		facing = input_vec.normalized()
		if absf(input_vec.x) > absf(input_vec.y):
			dir_name = "right" if input_vec.x > 0.0 else "left"
		else:
			dir_name = "down" if input_vec.y > 0.0 else "up"

	var moving := velocity.length() > 25.0
	_play(("walk_" if moving else "idle_") + dir_name)
	_update_feel(delta, moving)

	_tick_weapons(delta)
	_tick_skills(delta)
	_tick_orbit(delta)
	_tick_aura_visual()
	# 天赋再生（0.5s 一跳，避免每帧刷 HUD）
	var rg := Meta.bonus_regen()
	if rg > 0.0 and hp < max_hp:
		_regen_t += delta
		if _regen_t >= 0.5:
			_regen_t = 0.0
			hp = minf(max_hp, hp + rg * 0.5)
			hp_changed.emit(hp, max_hp)
	if _invuln_t > 0.0:
		_invuln_t -= delta
	if _flash_t > 0.0:
		_flash_t -= delta
		var k := clampf(_flash_t / 0.12, 0.0, 1.0)
		sprite.modulate = Color(1.0 + 2.0 * k, 1.0 + 2.0 * k, 1.0 + 2.0 * k)
	elif _invuln_t > 0.0:
		sprite.modulate.a = 0.45 + 0.35 * sin(_invuln_t * 28.0)
	else:
		sprite.modulate = Color.WHITE


func _play(anim_name: String) -> void:
	if anim_name != current_anim:
		current_anim = anim_name
		sprite.play(anim_name)


func _update_feel(delta: float, moving: bool) -> void:
	var lean := clampf(velocity.x / speed, -1.0, 1.0) * deg_to_rad(3.0)
	visual.rotation = lerpf(visual.rotation, lean, minf(1.0, 12.0 * delta))
	if moving:
		_walk_t += delta
		var bob := sin(_walk_t * 16.0)
		visual.position.y = bob * 3.0
		visual.scale = Vector2(1.0 + 0.018 * bob, 1.0 - 0.018 * bob) * _punch_now()
		dust.emitting = true
	else:
		_breathe_t += delta
		visual.position.y = lerpf(visual.position.y, 0.0, minf(1.0, 10.0 * delta))
		var b := 1.0 + 0.02 * sin(_breathe_t * 2.6)
		visual.scale = visual.scale.lerp(Vector2(2.0 - b, b), minf(1.0, 8.0 * delta))
		dust.emitting = false


# ---------- derived stats ----------
func _dmg_mult() -> float:
	return (1.0 + 0.08 * float(passives.get("attack", 0))) * Meta.bonus_dmg_mult()


func _cd_mult() -> float:
	var m := (1.0 - 0.06 * float(passives.get("aspeed", 0)))
	m *= (1.0 - 0.05 * float(passives.get("cooldown", 0)))
	m *= Meta.bonus_aspeed_mult()
	m *= StatBlock.relic_mult(relics, "cd_mult", _relic_tbl())
	return maxf(m, 0.35)


func _crit_chance() -> float:
	var c := 0.05 + 0.06 * float(passives.get("crit", 0)) + Meta.bonus_crit()
	if _riposte:
		_riposte = false
		return 1.0
	return c


func _crit_mult() -> float:
	return 1.5 + 0.15 * float(passives.get("critdmg", 0)) + Meta.bonus_critdmg()


func _duration_mult() -> float:
	return 1.0 + 0.10 * float(passives.get("duration", 0))


func _xp_mult() -> float:
	return (1.0 + 0.08 * float(passives.get("xp", 0))) * Meta.bonus_xp_mult() * StatBlock.relic_mult(relics, "xp_mult", _relic_tbl())


func _area_mult() -> float:
	return 1.0 + 0.10 * float(passives.get("area", 0))


func _gold_mult() -> float:
	return StatBlock.relic_mult(relics, "gold_mult", _relic_tbl()) * Meta.bonus_gold_mult()


func _recalc() -> void:
	speed = base_speed * (1.0 + 0.06 * float(passives.get("speed", 0))) * Meta.bonus_speed_mult() * StatBlock.relic_mult(relics, "speed_mult", _relic_tbl())
	MAGNET_RADIUS = BASE_MAGNET_RADIUS * (1.0 + 0.35 * float(passives.get("magnet", 0))) * Meta.bonus_magnet_mult()
	MAGNET_RADIUS *= StatBlock.relic_mult(relics, "magnet_mult", _relic_tbl())
	if Meta.has_magnet_all():
		MAGNET_RADIUS = 99999.0


# ---------- weapons ----------
func add_weapon(wid: String) -> void:
	if not _weapon_by_id(wid).is_empty():
		return
	weapons.append({"id": wid, "lv": 1, "cd_t": 0.0})
	# v0.6 武器图鉴：集齐 19 把解锁成就
	Meta.add_weapon_codex(GameData.base_weapon_of(wid))
	if Meta.weapon_codex_size() >= 19:
		Achievements.unlock("arsenal")


func _weapon_by_id(wid: String) -> Dictionary:
	for w in weapons:
		if String(w["id"]) == wid:
			return w
	return {}


## effective stats incl. level scaling + signature traits + superweapon mods
func _wstats(w: Dictionary) -> Dictionary:
	var wid := String(w["id"])
	# 超武：按原武器 Lv8 计算再叠 mods
	var mods := {}
	var lv := int(w["lv"])
	var is_super := GameData.is_super(wid)
	if is_super:
		var sw: Dictionary = GameData.SUPERWEAPONS[wid]
		mods = sw.get("mods", {})
		wid = String(sw["weapon"])
		lv = GameData.WEAPON_MAX_LV
	var d: Dictionary = GameData.WEAPONS[wid]
	var s := {
		"kind": String(d["kind"]),
		"school": String(d.get("school", "")),
		"cd": float(d["cd"]) * _cd_mult(),
		"dmg": float(d["dmg"]) * (1.0 + 0.12 * float(lv - 1)) * _dmg_mult(),
		"count": int(d.get("count", 1)),
		"pierce": int(d.get("pierce", 0)),
		"chain": int(d.get("chain", 0)),
		"explosive": float(d.get("explosive", 0.0)),
		"radius": float(d.get("radius", 0.0)) * _area_mult(),
		"range": float(d.get("range", 600.0)),
		"proj": String(d.get("proj", "")),
		"proj_speed": float(d.get("proj_speed", 500.0)),
		"fx": String(d.get("fx", "")),
		"summon": String(d.get("summon", "")),
		"critdmg_bonus": 0.0,
		"knockback": 1.0,
		"execute": 0.0,
		"flags": {},
		"summon_hp_mult": 1.0,
	}
	var sig: Dictionary = d.get("sig", {})
	var lvs := sig.keys()
	lvs.sort()
	for lvk in lvs:
		if lv < int(lvk):
			continue
		var fx: Dictionary = sig[lvk]
		for k in fx.keys():
			match String(k):
				"count":
					s["count"] = int(s["count"]) + int(fx[k])
				"pierce":
					s["pierce"] = int(s["pierce"]) + int(fx[k])
				"chain":
					s["chain"] = int(s["chain"]) + int(fx[k])
				"cd_mult":
					s["cd"] = float(s["cd"]) * float(fx[k])
				"dmg_mult":
					s["dmg"] = float(s["dmg"]) * float(fx[k])
				"radius_mult":
					s["radius"] = float(s["radius"]) * float(fx[k])
				"explosive":
					s["explosive"] = float(fx[k]) * _area_mult()
				"critdmg":
					s["critdmg_bonus"] = float(s["critdmg_bonus"]) + float(fx[k])
				"knockback":
					s["knockback"] = float(fx[k])
				"execute":
					s["execute"] = float(fx[k])
				"flag":
					var fname := String(fx[k])
					var fval = fx.get("flagv", true)
					(s["flags"] as Dictionary)[fname] = fval
	# 超武 mods
	if is_super:
		_apply_mods(s, mods)
	# 流派亲和：对应流派武器伤害 ×1.15
	var school := String(s["school"])
	if school != "":
		var aff: Array = char_def.get("affinity", [])
		if school in aff:
			s["dmg"] = float(s["dmg"]) * 1.15
	return s


func _apply_mods(s: Dictionary, mods: Dictionary) -> void:
	var flags: Dictionary = s["flags"]
	for k in mods.keys():
		var v = mods[k]
		match String(k):
			"dmg_mult":
				s["dmg"] = float(s["dmg"]) * float(v)
			"count_add":
				s["count"] = int(s["count"]) + int(v)
			"pierce_add":
				s["pierce"] = int(s["pierce"]) + int(v)
			"chain_add":
				s["chain"] = int(s["chain"]) + int(v)
			"explosive_mult":
				s["explosive"] = float(s["explosive"]) * float(v)
			"radius_mult":
				s["radius"] = float(s["radius"]) * float(v)
			"cd_mult":
				s["cd"] = float(s["cd"]) * float(v)
			"critdmg_add":
				s["critdmg_bonus"] = float(s["critdmg_bonus"]) + float(v)
			"summon_hp_mult":
				s["summon_hp_mult"] = float(s["summon_hp_mult"]) * float(v)
			"knockback_v":
				s["knockback"] = float(v)
			"stun_v":
				flags["stun"] = float(v)
			"execute_v":
				s["execute"] = float(v)
				flags["execute"] = float(v)
			"thorns_v":
				flags["thorns"] = float(v)
			"flags":
				for fname in v:
					flags[String(fname)] = true


func _tick_weapons(delta: float) -> void:
	for i in range(weapons.size()):
		var w: Dictionary = weapons[i]
		w["cd_t"] = float(w["cd_t"]) - delta
		if float(w["cd_t"]) > 0.0:
			continue
		var s := _wstats(w)
		match String(s["kind"]):
			"projectile", "chain":
				var target := _nearest_enemy(float(s["range"]))
				if target == null:
					continue
				w["cd_t"] = float(s["cd"])
				_fire_projectiles(target, s, 24.0)
			"spread":
				var target := _nearest_enemy(float(s["range"]))
				if target == null:
					continue
				w["cd_t"] = float(s["cd"])
				_fire_projectiles(target, s, 55.0)
			"aoe":
				w["cd_t"] = float(s["cd"])
				_do_whirlwind(s)
			"summon":
				w["cd_t"] = float(s["cd"])
				_tick_summon(i, w, s)
			"corpse":
				w["cd_t"] = float(s["cd"])
				_do_corpse_blast(s)
			"drain":
				var target := _nearest_enemy(float(s["range"]))
				if target == null:
					continue
				w["cd_t"] = float(s["cd"])
				_do_life_drain(target, s)
			"aura":
				w["cd_t"] = float(s["cd"])
				_do_curse_aura(s)
			"arc":
				var target := _nearest_enemy(float(s["radius"]) + 60.0)
				if target == null:
					continue
				w["cd_t"] = float(s["cd"])
				_do_shield_bash(target, s)
			"shock":
				w["cd_t"] = float(s["cd"])
				_do_warcry(w, s)
			"boomerang":
				var target := _nearest_enemy(float(s["range"]))
				if target == null:
					continue
				w["cd_t"] = float(s["cd"])
				_fire_boomerang(target, s)


func _nearest_enemy(max_range: float) -> Node2D:
	var best: Node2D = Registry.nearest(global_position, max_range)
	return best


func _fire_projectiles(target: Node2D, s: Dictionary, spread_deg: float) -> void:
	Sfx.play("shoot")
	var base_dir := (target.global_position - global_position).normalized()
	var n := int(s["count"])
	var crit_mult := _crit_mult() + float(s["critdmg_bonus"])
	for i in range(n):
		var ang := 0.0
		if n > 1:
			ang = deg_to_rad(lerpf(-spread_deg * 0.5, spread_deg * 0.5, float(i) / float(n - 1)))
		var dir := base_dir.rotated(ang)
		var p: Node2D = PoolManager.acquire("projectile", func() -> Node:
			var np := Node2D.new()
			np.set_script(load("res://scripts/projectile.gd"))
			return np)
		p.setup(
			"res://assets/sprites/fx/projectiles/%s.png" % String(s["proj"]),
			global_position + dir * 40.0, dir,
			float(s["proj_speed"]), float(s["dmg"]), int(s["chain"]),
			int(s["pierce"]), float(s["explosive"]),
			_crit_chance(), crit_mult,
			float(s["range"]) + 80.0, float(s["knockback"])
		)
		p.home = self
		get_parent().add_child(p)
		p.add_to_group("projectiles")
		if p.has_meta("pooled_reuse"):
			p.remove_meta("pooled_reuse")
			p.spawn_init()
		if (s["flags"] as Dictionary).has("blackhole"):
			p.blackhole = true


func _do_whirlwind(s: Dictionary) -> void:
	var radius := float(s["radius"])
	var fx := Node2D.new()
	var sp := Sprite2D.new()
	sp.texture = load("res://assets/sprites/fx/%s.png" % String(s["fx"]))
	sp.modulate.a = 0.9
	fx.add_child(sp)
	fx.global_position = global_position
	fx.z_index = 5
	get_parent().add_child(fx)
	# 旋风辉光环（贴着斧弧的能量环）
	FX.glow_ring(get_parent(), global_position, radius * 0.95, Color(0.6, 0.85, 1.0, 0.7), 0.45, 4)
	var target_scale := radius / 64.0
	fx.scale = Vector2.ONE * target_scale * 0.5
	var tw := fx.create_tween()
	tw.set_parallel(true)
	tw.tween_property(fx, "scale", Vector2.ONE * target_scale, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(fx, "rotation", 2.5, 0.45)
	tw.tween_property(sp, "modulate:a", 0.0, 0.45)
	tw.chain().tween_callback(fx.queue_free)
	# 环绕粒子
	var orbit := CPUParticles2D.new()
	orbit.amount = 20
	orbit.lifetime = 0.45
	orbit.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	orbit.emission_sphere_radius = radius * 0.8
	orbit.direction = Vector2(0, -1)
	orbit.spread = 180.0
	orbit.initial_velocity_min = 200.0
	orbit.initial_velocity_max = 350.0
	orbit.gravity = Vector2.ZERO
	orbit.scale_amount_min = 3.0
	orbit.scale_amount_max = 6.0
	orbit.color = Color(0.7, 0.9, 1.0, 0.7)
	orbit.global_position = global_position
	orbit.z_index = 6
	get_parent().add_child(orbit)
	orbit.emitting = true
	# 命中火花 + 伤害数字
	for e in Registry.query_circle(global_position, radius):
		if not is_instance_valid(e) or e.dead:
			continue
		var to: Vector2 = e.global_position - global_position
		if to.length() <= radius:
			var dmg := float(s["dmg"])
			var crit_mult := _crit_mult() + float(s["critdmg_bonus"])
			var is_crit := randf() < _crit_chance()
			if is_crit:
				dmg *= crit_mult
			var exec_hp := float(s["execute"])
			if exec_hp > 0.0 and not bool(e.get("is_boss")) and not bool(e.get("elite")):
				var mhp := float(e.get("max_hp"))
				if mhp > 0.0 and float(e.get("hp")) / mhp < exec_hp:
					e.take_damage(999999.0, to.normalized(), float(s["knockback"]))
					FX.hit_spark(get_parent(), e.global_position, Color(1, 0.3, 0.3))
					FX.damage_number(get_parent(), e.global_position, 999999.0, true)
					continue
			e.take_damage(dmg, to.normalized(), float(s["knockback"]))
			FX.hit_spark(get_parent(), e.global_position)
			FX.damage_number(get_parent(), e.global_position, dmg, is_crit)
			if is_crit:
				FX.shake(get_parent(), 8.0)


# ---------- v0.3 新武器 ----------
func _enemies_alive() -> bool:
	return Registry.alive_count() > 0


func _enemy_near(pos: Vector2, dist: float, exclude := {}) -> Node2D:
	return Registry.nearest(pos, dist, exclude)


func _exec_threshold(s: Dictionary) -> float:
	var flags: Dictionary = s.get("flags", {})
	if flags.has("execute") and not (flags["execute"] is bool):
		return float(flags["execute"])
	return float(s.get("execute", 0.0))


func _deal_hit(e: Node2D, dmg: float, from_dir: Vector2, knock: float, s: Dictionary, stun: float = 0.0) -> void:
	# 通用命中：暴击 roll + 处决 + 飘字 + 火花
	var crit_mult := _crit_mult() + float(s["critdmg_bonus"])
	var is_crit := randf() < _crit_chance()
	var d := dmg * crit_mult if is_crit else dmg
	if "scythe" in relics and float(e.get("hp")) / maxf(1.0, float(e.get("max_hp"))) < 0.3:
		d *= 1.5
	var exec_hp := _exec_threshold(s)
	if exec_hp > 0.0 and not bool(e.get("is_boss")) and not bool(e.get("elite")):
		if float(e.get("hp")) / maxf(1.0, float(e.get("max_hp"))) < exec_hp:
			e.take_damage(999999.0, from_dir, knock, stun)
			FX.hit_spark(get_parent(), e.global_position, Color(1, 0.3, 0.3))
			FX.damage_number(get_parent(), e.global_position, 999999.0, true)
			return
	e.take_damage(d, from_dir, knock, stun)
	FX.hit_spark(get_parent(), e.global_position)
	FX.damage_number(get_parent(), e.global_position, d, is_crit)
	if is_crit:
		FX.shake(get_parent(), 8.0)


## 召唤武器：按 count 维持召唤物数量（死了过 cd 补）
func _tick_summon(slot: int, w: Dictionary, s: Dictionary) -> void:
	var want := int(s["count"])
	var have := 0
	for sm in get_tree().get_nodes_in_group("summons"):
		if is_instance_valid(sm) and int(sm.get("slot")) == slot and not bool(sm.get("dead")) and not bool(sm.get("mini")):
			have += 1
	if have >= want:
		return
	var stype := String(s.get("summon", "hound"))
	var sm := Summon.new()
	sm.setup(stype, slot, GameData.base_weapon_of(String(w["id"])), self)
	get_parent().add_child(sm)
	sm.global_position = global_position + Vector2.RIGHT.rotated(randf() * TAU) * randf_range(60.0, 110.0)
	FX.glow(get_parent(), sm.global_position, 80.0, Color(0.6, 0.9, 1.0, 0.7), 0.35, 5)


## 召唤物实时属性（升级/超武即时生效）
func summon_stats(slot: int) -> Dictionary:
	if slot < 0 or slot >= weapons.size():
		return {}
	var s := _wstats(weapons[slot])
	s["summon_hp_mult"] = float(s.get("summon_hp_mult", 1.0)) * _duration_mult()
	return s


## 尸爆：引爆射程内"附近200px有怪"的尸体
func _do_corpse_blast(s: Dictionary) -> void:
	var flags: Dictionary = s["flags"]
	var radius := float(s["radius"])
	var seed_c: Node2D = null
	for c in get_tree().get_nodes_in_group("corpses"):
		if not is_instance_valid(c):
			continue
		if c.has_meta("detonated"):
			continue
		if global_position.distance_to(c.global_position) > float(s["range"]):
			continue
		if _enemy_near(c.global_position, 200.0) == null:
			continue
		seed_c = c
		break
	if seed_c == null:
		return
	var r := radius * (2.0 if (bool(seed_c.get("elite")) and flags.has("elite_blast")) else 1.0)
	_detonate_corpse(seed_c, r, s, flags)
	FX.hitstop(get_tree(), 0.04)


func _detonate_corpse(c: Node2D, radius: float, s: Dictionary, flags: Dictionary) -> void:
	var pos := c.global_position
	c.set_meta("detonated", true)
	c.queue_free()
	FX.explosion(get_parent(), pos, radius, Color(0.55, 0.95, 0.45))
	for e in Registry.query_circle(pos, radius):
		if not is_instance_valid(e) or bool(e.get("dead")):
			continue
		var to: Vector2 = e.global_position - pos
		if to.length() <= radius:
			_deal_hit(e, float(s["dmg"]), to.normalized() if to.length() > 1.0 else Vector2.UP, 1.6, s)
	if flags.has("chain_corpse"):
		var others: Array = []
		for c2 in get_tree().get_nodes_in_group("corpses"):
			if not is_instance_valid(c2) or c2.has_meta("detonated"):
				continue
			if pos.distance_to(c2.global_position) <= radius:
				others.append(c2)
		for c2 in others:
			if is_instance_valid(c2):
				var r2 := radius * (2.0 if (bool(c2.get("elite")) and flags.has("elite_blast")) else 1.0)
				_detonate_corpse(c2, r2, s, flags)


## 生命吸取：链式伤害，回血 30%（虹吸转护盾 / 处决）
func _do_life_drain(target: Node2D, s: Dictionary) -> void:
	var flags: Dictionary = s["flags"]
	var chain_left := int(s["chain"])
	var visited := {target.get_instance_id(): true}
	var hits: Array = [target]
	var cur := target
	while chain_left > 0:
		var nxt := _enemy_near(cur.global_position, 280.0, visited)
		if nxt == null:
			break
		visited[nxt.get_instance_id()] = true
		hits.append(nxt)
		cur = nxt
		chain_left -= 1
	var total := 0.0
	var line := Line2D.new()
	line.width = 6.0
	line.default_color = Color(0.7, 0.35, 1.0, 0.9)
	line.z_index = 6
	line.add_point(Vector2.ZERO)
	get_parent().add_child(line)
	line.global_position = Vector2.ZERO
	line.add_point(global_position)
	for e in hits:
		if not is_instance_valid(e) or bool(e.get("dead")):
			continue
		var to: Vector2 = e.global_position - global_position
		var dmg := float(s["dmg"])
		var is_crit := randf() < _crit_chance()
		if is_crit:
			dmg *= _crit_mult() + float(s["critdmg_bonus"])
		var exec_hp := _exec_threshold(s)
		if exec_hp > 0.0 and not bool(e.get("is_boss")) and not bool(e.get("elite")):
			if float(e.get("hp")) / maxf(1.0, float(e.get("max_hp"))) < exec_hp:
				e.take_damage(999999.0, to.normalized(), 1.0)
				FX.damage_number(get_parent(), e.global_position, 999999.0, true)
				total += dmg
				line.add_point(e.global_position)
				continue
		e.take_damage(dmg, to.normalized() if to.length() > 1.0 else Vector2.UP, 0.6)
		total += dmg
		FX.hit_spark(get_parent(), e.global_position, Color(0.7, 0.4, 1.0))
		FX.damage_number(get_parent(), e.global_position, dmg, is_crit)
		line.add_point(e.global_position)
	var heal := total * 0.3
	if flags.has("shield_drain"):
		_shield_hp += heal
		_shield_t = maxf(_shield_t, 6.0)
		FX.glow(get_parent(), global_position, 90.0, Color(0.5, 0.85, 1.0, 0.7), 0.3, 5)
	else:
		hp = minf(max_hp, hp + heal)
		hp_changed.emit(hp, max_hp)
	var tw := line.create_tween()
	tw.tween_property(line, "modulate:a", 0.0, 0.3)
	tw.tween_callback(line.queue_free)


## 诅咒光环：tick 伤害 + 叠诅咒 + 虚弱
func _do_curse_aura(s: Dictionary) -> void:
	var flags: Dictionary = s["flags"]
	var radius := float(s["radius"])
	var dmg := float(s["dmg"])
	for e in Registry.query_circle(global_position, radius):
		if not is_instance_valid(e) or bool(e.get("dead")):
			continue
		var to: Vector2 = e.global_position - global_position
		if to.length() > radius:
			continue
		var is_crit := randf() < _crit_chance()
		var d := dmg * (_crit_mult() + float(s["critdmg_bonus"])) if is_crit else dmg
		e.take_damage(d, to.normalized() if to.length() > 1.0 else Vector2.UP, 0.3)
		if e.has_method("apply_curse"):
			e.apply_curse(dmg * 0.6, 3.0)
			FX.glow(get_parent(), e.global_position, 44.0, Color(0.55, 0.25, 0.9, 0.5), 0.25, 5)
		if flags.has("weaken") and e.has_method("apply_weaken"):
			e.apply_weaken(2.5)
		FX.damage_number(get_parent(), e.global_position, d, is_crit)


func _tick_aura_visual() -> void:
	var want := 0.0
	for w in weapons:
		if GameData.base_weapon_of(String(w["id"])) == "curse_aura":
			var s := _wstats(w)
			want = maxf(want, float(s["radius"]) * 2.2)
			break
	if want <= 0.0:
		if is_instance_valid(_aura_node):
			_aura_node.queue_free()
		_aura_node = null
		return
	if not is_instance_valid(_aura_node):
		_aura_node = FX.attach_aura(self, want, Color(0.55, 0.25, 0.9, 0.30), 3)


## 盾击：扇形近战 + 眩晕；完美格挡窗口；复仇必暴
func _do_shield_bash(target: Node2D, s: Dictionary) -> void:
	var flags: Dictionary = s["flags"]
	var radius := float(s["radius"])
	var dir := (target.global_position - global_position).normalized()
	var stun := 1.0
	if flags.has("stun") and not (flags["stun"] is bool):
		stun = float(flags["stun"])
	for e in Registry.query_circle(global_position, radius):
		if not is_instance_valid(e) or bool(e.get("dead")):
			continue
		var to: Vector2 = e.global_position - global_position
		if to.length() > radius:
			continue
		if absf(wrapf(to.angle() - dir.angle(), -PI, PI)) > deg_to_rad(55.0):
			continue
		_deal_hit(e, float(s["dmg"]), dir, 2.2, s, stun)
	# 盾 slam 特效
	var fx := Node2D.new()
	var sp := Sprite2D.new()
	sp.texture = load("res://assets/sprites/fx/fx_shield_slam.png") as Texture2D
	sp.modulate = Color(0.7, 0.9, 1.0, 0.95)
	sp.rotation = dir.angle()
	fx.add_child(sp)
	fx.global_position = global_position + dir * radius * 0.55
	fx.z_index = 6
	get_parent().add_child(fx)
	var tw := fx.create_tween()
	tw.set_parallel(true)
	tw.tween_property(sp, "scale", Vector2(1.6, 1.6), 0.3).from(Vector2(0.5, 0.5))
	tw.tween_property(sp, "modulate:a", 0.0, 0.35)
	tw.chain().tween_callback(fx.queue_free)
	FX.glow_ring(get_parent(), global_position, radius * 0.8, Color(0.6, 0.85, 1.0, 0.8), 0.4, 6)
	FX.shake(get_parent(), 8.0)
	FX.hitstop(get_tree(), 0.05)
	if flags.has("parry"):
		_parry_t = 3.0
		_parried = false


func _has_riposte_weapon() -> bool:
	for w in weapons:
		var s := _wstats(w)
		if (s["flags"] as Dictionary).has("riposte"):
			return true
	return false


## 战吼：多道冲击波 + 击退；嗜血叠攻击
func _do_warcry(w: Dictionary, s: Dictionary) -> void:
	var stacks := int(w.get("blw", 0))
	var dmg := float(s["dmg"]) * (1.0 + 0.1 * stacks)
	_warcry_waves(int(s["count"]), float(s["radius"]), dmg, s)


func _warcry_waves(n: int, radius: float, dmg: float, s: Dictionary) -> void:
	for i in range(n):
		if i > 0:
			await get_tree().create_timer(0.28).timeout
		if _dead:
			return
		for e in Registry.query_circle(global_position, radius):
			if not is_instance_valid(e) or bool(e.get("dead")):
				continue
			var to: Vector2 = e.global_position - global_position
			if to.length() <= radius:
				_deal_hit(e, dmg, to.normalized() if to.length() > 1.0 else Vector2.UP, 2.6, s)
		var fx := Node2D.new()
		var sp := Sprite2D.new()
		sp.texture = load("res://assets/sprites/fx/fx_warcry.png") as Texture2D
		sp.modulate = Color(1.0, 0.75, 0.35, 0.9)
		fx.add_child(sp)
		fx.global_position = global_position
		fx.z_index = 6
		get_parent().add_child(fx)
		var tw := fx.create_tween()
		tw.set_parallel(true)
		tw.tween_property(sp, "scale", Vector2.ONE * radius / 64.0, 0.4).from(Vector2.ONE * 0.4)
		tw.tween_property(sp, "modulate:a", 0.0, 0.45)
		tw.chain().tween_callback(fx.queue_free)
		FX.glow_ring(get_parent(), global_position, radius, Color(1.0, 0.7, 0.3, 0.8), 0.45, 6)
		FX.shake(get_parent(), 10.0)
		FX.hitstop(get_tree(), 0.04)


## 飞斧：回旋斧投射物
func _fire_boomerang(target: Node2D, s: Dictionary) -> void:
	var flags: Dictionary = s["flags"]
	var n := int(s["count"])
	var base_dir := (target.global_position - global_position).normalized()
	var returns := 1
	if flags.has("returns") and not (flags["returns"] is bool):
		returns = int(flags["returns"])
	var crit_mult := _crit_mult() + float(s["critdmg_bonus"])
	for i in range(n):
		var ang := 0.0
		if n > 1:
			ang = deg_to_rad(lerpf(-30.0, 30.0, float(i) / float(n - 1)))
		var dir := base_dir.rotated(ang)
		var p: Node2D = PoolManager.acquire("projectile", func() -> Node:
			var np := Node2D.new()
			np.set_script(load("res://scripts/projectile.gd"))
			return np)
		p.setup(
			"res://assets/sprites/fx/projectiles/%s.png" % String(s["proj"]),
			global_position + dir * 40.0, dir,
			float(s["proj_speed"]), float(s["dmg"]), 0,
			int(s["pierce"]), 0.0,
			_crit_chance(), crit_mult,
			float(s["range"]) + 60.0, 1.4)
		p.boomerang = true
		p.boomerang_returns = returns
		p.blackhole = flags.has("blackhole")
		p.split_axe = flags.has("split_axe")
		p.home = self
		get_parent().add_child(p)
		p.add_to_group("projectiles")
		if p.has_meta("pooled_reuse"):
			p.remove_meta("pooled_reuse")
			p.spawn_init()
	FX.glow(get_parent(), global_position, 90.0, Color(1.0, 0.8, 0.4, 0.7), 0.25, 5)


## 旋风斧：环绕斧刃（常驻节点，每帧旋转 + 接触伤害）
func _tick_orbit(delta: float) -> void:
	var seen := {}
	for i in range(weapons.size()):
		var w: Dictionary = weapons[i]
		if GameData.base_weapon_of(String(w["id"])) != "melee_axe":
			continue
		seen[i] = true
		var s := _wstats(w)
		var node: Node2D = _orbit_nodes.get(i)
		if node == null or not is_instance_valid(node):
			node = Node2D.new()
			node.set_meta("ang", randf() * TAU)
			node.set_meta("hits", {})
			node.set_meta("spin", 0.0)
			add_child(node)
			_orbit_nodes[i] = node
		var count := int(s["count"])
		var radius := float(s["radius"])
		while node.get_child_count() < count:
			var sp := Sprite2D.new()
			sp.texture = load("res://assets/sprites/fx/projectiles/proj_axe.png") as Texture2D
			node.add_child(sp)
		while node.get_child_count() > count:
			node.get_child(node.get_child_count() - 1).queue_free()
		var ang := float(node.get_meta("ang")) + delta * 3.4
		node.set_meta("ang", ang)
		var spin := float(node.get_meta("spin")) + delta * 12.0
		node.set_meta("spin", spin)
		var hits: Dictionary = node.get_meta("hits")
		var now := Time.get_ticks_msec() / 1000.0
		var flags: Dictionary = s["flags"]
		for a in range(count):
			var child := node.get_child(a) as Node2D
			var off := Vector2.RIGHT.rotated(ang + TAU * float(a) / float(count)) * radius
			child.position = off
			child.rotation = spin
			# 接触伤害（每斧每怪 0.45s 一次）
			for e in Registry.query_circle(global_position + off, 40.0):
				if not is_instance_valid(e) or bool(e.get("dead")):
					continue
				var key := "%d_%d" % [a, e.get_instance_id()]
				if e.global_position.distance_to(global_position + off) > 40.0:
					continue
				if now - float(hits.get(key, -9.0)) < 0.45:
					continue
				hits[key] = now
				var to: Vector2 = e.global_position - global_position
				_deal_hit(e, float(s["dmg"]), to.normalized() if to.length() > 1.0 else Vector2.UP, 0.8, s)
			# 吸附轻怪
			if flags.has("pull"):
				for e in Registry.query_circle(global_position, radius * 1.7):
					if not is_instance_valid(e) or bool(e.get("dead")):
						continue
					if bool(e.get("is_boss")) or bool(e.get("elite")):
						continue
					var to: Vector2 = global_position - e.global_position
					if to.length() < radius * 1.7 and to.length() > 30.0:
						e.global_position += to.normalized() * 160.0 * delta
	# 清理已不存在的槽位
	for k in _orbit_nodes.keys():
		if not seen.has(k):
			var n2: Node2D = _orbit_nodes[k]
			if is_instance_valid(n2):
				n2.queue_free()
			_orbit_nodes.erase(k)


## 击杀钩子：战吼嗜血叠层 / 诅咒扩散
func on_enemy_died(e: Node2D) -> void:
	for w in weapons:
		var s := _wstats(w)
		if (s["flags"] as Dictionary).has("bloodlust_warcry"):
			var stacks := int(w.get("blw", 0))
			if stacks < 5:
				w["blw"] = stacks + 1
	var curse_left := 0.0
	if e.get("curse_t") != null:
		curse_left = float(e.get("curse_t"))
	if curse_left > 0.0:
		for w in weapons:
			if GameData.base_weapon_of(String(w["id"])) != "curse_aura":
				continue
			var s := _wstats(w)
			if not (s["flags"] as Dictionary).has("spread"):
				continue
			for e2 in Registry.query_circle(e.global_position, 220.0):
				if not is_instance_valid(e2) or bool(e2.get("dead")) or e2 == e:
					continue
				if e.global_position.distance_to(e2.global_position) <= 220.0 and e2.has_method("apply_curse"):
					e2.apply_curse(float(s["dmg"]) * 0.6, 3.0)
					FX.glow(get_parent(), e2.global_position, 50.0, Color(0.55, 0.25, 0.9, 0.6), 0.3, 5)


# ---------- level-up options ----------
const SCHOOL_NAMES := {"gun": "枪械流", "summon": "召唤流", "necro": "死灵流", "melee": "近战流"}


func build_levelup_options() -> Array:
	_lvup_count += 1
	var synth: Array = []
	var wups: Array = []
	var wnews: Array = []
	var pups: Array = []
	var pnews: Array = []
	var snew: Array = []
	var sups: Array = []
	# 金色合成（最高优先级置顶）：武器 Lv8 + 指定被动 Lv5
	for w in weapons:
		var wid := String(w["id"])
		if GameData.is_super(wid) or int(w["lv"]) < GameData.WEAPON_MAX_LV:
			continue
		for swid in GameData.SUPERWEAPONS.keys():
			var sw: Dictionary = GameData.SUPERWEAPONS[swid]
			if String(sw["weapon"]) != wid:
				continue
			var need_p := String(sw["passive"])
			if int(passives.get(need_p, 0)) < GameData.PASSIVE_MAX_LV:
				continue
			var nm: String = GameData.WEAPONS[wid]["name"]
			synth.append({"type": "synthesize", "id": wid, "super_id": swid,
				"title": Lang.t("合成超武:%s") % Lang.t(String(sw["name"])),
				"desc": "%s Lv8 + %s Lv5" % [Lang.t(nm), Lang.t(String(GameData.PASSIVES[need_p]["name"]))]})
	for w in weapons:
		var wid := String(w["id"])
		var lv := int(w["lv"])
		if lv < GameData.WEAPON_MAX_LV and not GameData.is_super(wid):
			var nm: String = GameData.WEAPONS[GameData.base_weapon_of(wid)]["name"]
			if GameData.is_super(wid):
				nm = String(GameData.SUPERWEAPONS[wid]["name"])
			wups.append({"type": "weapon_up", "id": wid,
				"title": (Lang.t("武器升级:%s") % Lang.t(nm)) + _affinity_mark(wid), "desc": Lang.t("Lv.%d→%d,伤害提升") % [lv, lv + 1]})
	if weapons.size() < GameData.WEAPON_SLOTS + Meta.extra_weapon_slots():
		for wid in GameData.WEAPON_POOL:
			if not Meta.is_weapon_unlocked(wid):
				continue
			if _weapon_by_id(wid).is_empty():
				var d: Dictionary = GameData.WEAPONS[wid]
				wnews.append({"type": "new_weapon", "id": wid,
					"title": (Lang.t("新武器:%s") % Lang.t(String(d["name"]))) + _affinity_mark(wid),
					"desc": Lang.t("%s,自动攻击") % Lang.t(String(SCHOOL_NAMES.get(String(d.get("school", "")), "")))})
	for pid in passives.keys():
		var lv := int(passives[pid])
		if lv < GameData.PASSIVE_MAX_LV:
			pups.append({"type": "passive_up", "id": String(pid),
				"title": Lang.t("被动升级:%s") % Lang.t(String(GameData.PASSIVES[pid]["name"])),
				"desc": "Lv.%d→%d" % [lv, lv + 1]})
	if passives.size() < GameData.PASSIVE_SLOTS:
		for pid in GameData.PASSIVE_ORDER:
			if not passives.has(pid):
				pnews.append({"type": "new_passive", "id": String(pid),
					"title": Lang.t("新被动:%s") % Lang.t(String(GameData.PASSIVES[pid]["name"])), "desc": Lang.t("永久增益")})
	# 技能：通用槽只有一个
	var has_utility := false
	for sk in skills:
		var sid := String(sk["id"])
		var lv := int(sk["lv"])
		var sd: Dictionary = GameData.SKILLS[sid]
		if String(sd["kind"]) == "utility":
			has_utility = true
			if lv < GameData.SKILL_MAX_LV:
				sups.append({"type": "skill_up", "id": sid,
					"title": Lang.t("技能升级:%s") % Lang.t(String(sd["name"])),
					"desc": "Lv.%d→%d" % [lv, lv + 1]})
	if not has_utility:
		for sid in GameData.SKILL_ORDER:
			var sd: Dictionary = GameData.SKILLS[sid]
			snew.append({"type": "new_skill", "id": sid,
				"title": Lang.t("新技能:%s") % Lang.t(String(sd["name"])), "desc": Lang.t(String(sd["desc"]))})
	# ---- v0.8 选择器（07 §2.1）：强制槽（合成/漏斗/保底/新手）+ 加权无放回抽取 ----
	for p in [synth, wnews, wups, snew, sups, pnews, pups]:
		p.shuffle()
	var cfg := ContentDB.table("levelup")
	var weights: Dictionary = cfg.get("weights", {})
	var weapons_full := weapons.size() >= GameData.WEAPON_SLOTS + Meta.extra_weapon_slots()
	var forced: Array = []
	for o in synth:
		forced.append(o)
	# RC-3 漏斗：武器刚满级 → 下一次升级强制 1 槽给其合成所需被动
	if _funnel_weapon != "" and forced.size() < 3:
		var need_p := _funnel_passive_of(_funnel_weapon)
		var f := _take_from_pool(pups, func(o: Dictionary) -> bool: return String(o["id"]) == need_p)
		if f.is_empty():
			f = _take_from_pool(pnews, func(o: Dictionary) -> bool: return String(o["id"]) == need_p)
		if not f.is_empty():
			f["recommended"] = true
			forced.append(f)
		_funnel_weapon = ""
	# RC-4 保底：连续 2 次无 passive_up → 强制 1 个（优先已持有等级最高者）
	if _lvups_since_passive >= int(cfg.get("bad_luck_limit", 2)) and forced.size() < 3:
		var b := _take_best_passive_up(pups)
		if b.is_empty():
			b = _take_from_pool(pnews, func(_o: Dictionary) -> bool: return true)
		if not b.is_empty():
			forced.append(b)
	# 新手引导：前 3 次升级强制 ≥1 个新被动
	if _lvup_count <= int(cfg.get("newbie_force_lvups", 3)) and forced.size() < 3:
		var has_np := false
		for o in forced:
			if String(o["type"]) == "new_passive":
				has_np = true
		if not has_np:
			var n := _take_from_pool(pnews, func(_o: Dictionary) -> bool: return true)
			if not n.is_empty():
				n["recommended"] = true
				forced.append(n)
	var opts: Array = forced.slice(0, 3)
	# 焦点武器（等级最高的未合成武器）：其升级与所需被动享漏斗权重加成（sim 验证口径，常量在 levelup.json）
	var focus_wid := ""
	var focus_lv := -1
	for w in weapons:
		var wid := String(w["id"])
		if GameData.is_super(wid):
			continue
		if int(w["lv"]) > focus_lv:
			focus_lv = int(w["lv"])
			focus_wid = wid
	var focus_needp := _funnel_passive_of(focus_wid) if focus_wid != "" else ""
	# RC-1/RC-2：加权无放回抽取填满剩余槽（被动独立权重，不再只能竞争第 3 槽）
	var weighted: Array = []
	var cats: Array = [[wups, "weapon_up", 30], [wnews, "new_weapon", 22],
		[pups, "passive_up", 22], [pnews, "new_passive", 18],
		[snew, "skill", 8], [sups, "skill", 8]]
	for pair in cats:
		var w := float(weights.get(String(pair[1]), int(pair[2])))
		if String(pair[1]) == "new_weapon" and weapons.size() >= 4:
			w = float(cfg.get("new_weapon_dim", 8))
		if String(pair[1]) == "new_passive" and passives.size() >= 4:
			w = float(cfg.get("new_passive_dim", 6))
		if String(pair[1]) == "passive_up" and weapons_full:
			w = float(cfg.get("slots_full_passive_up", 30))
		var plist: Array = pair[0]
		var ptype := String(pair[1])
		# v0.8.13 流派亲和：只作用于新武器"发现"（new_weapon），按类别均值归一化——
		# 类别总权重不变（不挤占被动/技能槽位），只改变"哪把新武器更常出现"。
		# weapon_up 不加亲和：已持有武器的升级节奏保持原样，避免升级资源被亲和武器吸走、
		# 拖慢超武合成（V8 超武可达率回归验证）。
		var amults: Array = []
		var aavg := 1.0
		if ptype == "new_weapon":
			for o in plist:
				amults.append(_affinity_draft_mult(String(o["id"]), cfg))
			if not amults.is_empty():
				var s := 0.0
				for m in amults:
					s += float(m)
				aavg = s / float(amults.size())
		for i in range(plist.size()):
			var o: Dictionary = plist[i]
			var ew := w
			if ptype == "new_weapon":
				ew *= float(amults[i]) / aavg
			if ptype == "weapon_up" and String(o["id"]) == focus_wid:
				ew *= float(cfg.get("funnel_mult_weapon", 2.0))
			if String(pair[1]) == "passive_up" and String(o["id"]) == focus_needp:
				ew *= float(cfg.get("funnel_mult_passive", 3.0))
			weighted.append({"opt": o, "w": ew})
	while opts.size() < 3 and not weighted.is_empty():
		var total := 0.0
		for it in weighted:
			total += float(it["w"])
		var roll := randf() * total
		var pick_idx := 0
		for i2 in range(weighted.size()):
			roll -= float(weighted[i2]["w"])
			if roll <= 0.0:
				pick_idx = i2
				break
		opts.append(weighted[pick_idx]["opt"])
		weighted.remove_at(pick_idx)
	# 保底计数更新：本次出现 passive_up 清零，否则 +1
	var has_pups := false
	for o in opts:
		if String(o["type"]) == "passive_up":
			has_pups = true
	if has_pups:
		_lvups_since_passive = 0
	else:
		_lvups_since_passive += 1
	for o in opts:
		if String(o["type"]) == "synthesize":
			o["recommended"] = true
	return opts


## 某武器合成所需的被动 id（查 SUPERWEAPONS 反向映射）
func _funnel_passive_of(wid: String) -> String:
	for swid in GameData.SUPERWEAPONS.keys():
		var sw: Dictionary = GameData.SUPERWEAPONS[swid]
		if String(sw["weapon"]) == wid:
			return String(sw["passive"])
	return ""


## v0.8.13 流派亲和选秀权重：武器所属流派在角色亲和内 → 单亲和 ×affinity_mult，
## 双亲和角色各流派 ×affinity_mult_dual；非亲和流派 ×1
func _affinity_draft_mult(wid: String, cfg: Dictionary) -> float:
	var d: Dictionary = GameData.WEAPONS.get(GameData.base_weapon_of(wid), {})
	var school := String(d.get("school", ""))
	if school == "":
		return 1.0
	var aff: Array = char_def.get("affinity", [])
	if not school in aff:
		return 1.0
	if aff.size() > 1:
		return float(cfg.get("affinity_mult_dual", 2.0))
	return float(cfg.get("affinity_mult", 2.5))


## v0.8.14 选秀亲和标记：亲和流派武器标题后加"·亲和"
func _affinity_mark(wid: String) -> String:
	var d: Dictionary = GameData.WEAPONS.get(GameData.base_weapon_of(wid), {})
	var school := String(d.get("school", ""))
	var aff: Array = char_def.get("affinity", [])
	if school != "" and school in aff:
		return Lang.t("·亲和")
	return ""


## 从池中取出第一个满足 pred 的选项（取出即移除）；无则返回空字典
func _take_from_pool(pool: Array, pred: Callable) -> Dictionary:
	for i in range(pool.size()):
		if bool(pred.call(pool[i])):
			var o: Dictionary = pool[i]
			pool.remove_at(i)
			return o
	return {}


## 保底用：取出已持有被动中等级最高者的升级项
func _take_best_passive_up(pups: Array) -> Dictionary:
	var best_i := -1
	var best_lv := -1
	for i in range(pups.size()):
		var lv := int(passives.get(String(pups[i]["id"]), 0))
		if lv > best_lv:
			best_lv = lv
			best_i = i
	if best_i < 0:
		return {}
	var o: Dictionary = pups[best_i]
	pups.remove_at(best_i)
	return o


func apply_levelup_option(opt: Dictionary) -> void:
	consume_pending_level()
	var t := String(opt["type"])
	var oid := String(opt["id"])
	match t:
		"new_weapon":
			add_weapon(oid)
		"weapon_up":
			var w := _weapon_by_id(oid)
			if not w.is_empty():
				w["lv"] = mini(GameData.WEAPON_MAX_LV, int(w["lv"]) + 1)
				if int(w["lv"]) >= GameData.WEAPON_MAX_LV:
					_funnel_weapon = GameData.base_weapon_of(oid)
		"new_passive":
			passives[oid] = 1
			_on_passive_gained(oid)
		"passive_up":
			passives[oid] = mini(GameData.PASSIVE_MAX_LV, int(passives[oid]) + 1)
			_on_passive_gained(oid)
		"synthesize":
			var w := _weapon_by_id(oid)
			if not w.is_empty():
				var swid := String(opt["super_id"])
				w["id"] = swid
				w["lv"] = GameData.WEAPON_MAX_LV
				# v0.6 超武图鉴成就
				Meta.add_super_codex(swid)
				var scn := Meta.super_codex_size()
				if scn >= 1:
					Achievements.unlock("super1")
				if scn >= 5:
					Achievements.unlock("super5")
				if scn >= 19:
					Achievements.unlock("super19")
				# v0.8 合成演出时间轴（05 附录 A.2）：蓄力→爆发→收幕共 1.4s
				_synth_ceremony()
		"new_skill":
			add_skill(oid)
		"skill_up":
			var sk := _skill_by_id(oid)
			if not sk.is_empty():
				sk["lv"] = mini(GameData.SKILL_MAX_LV, int(sk["lv"]) + 1)
	_recalc()


func _on_passive_gained(pid: String) -> void:
	if pid == "hp":
		var lv := int(passives["hp"])
		var new_max := base_max_hp
		for i in range(lv):
			new_max *= 1.15
		var gain := new_max - max_hp
		max_hp = new_max
		hp = minf(max_hp, hp + gain)
		hp_changed.emit(hp, max_hp)


# ---------- 技能 2 槽 ----------
func add_skill(sid: String) -> void:
	for sk in skills:
		if String(sk["id"]) == sid:
			return
	if String(GameData.SKILLS[sid]["kind"]) == "utility":
		for sk in skills:
			if String(GameData.SKILLS[String(sk["id"])]["kind"]) == "utility":
				return
	skills.append({"id": sid, "lv": 1, "cd_t": 2.0, "auto": true})


func _skill_by_id(sid: String) -> Dictionary:
	for sk in skills:
		if String(sk["id"]) == sid:
			return sk
	return {}


func toggle_skill_auto(idx: int) -> void:
	if idx >= 0 and idx < skills.size():
		skills[idx]["auto"] = not bool(skills[idx]["auto"])


func try_cast_skill(idx: int) -> bool:
	if idx < 0 or idx >= skills.size() or _dead:
		return false
	var sk: Dictionary = skills[idx]
	if float(sk["cd_t"]) > 0.0:
		return false
	_cast_skill(sk)
	return true


func _tick_skills(delta: float) -> void:
	for sk in skills:
		sk["cd_t"] = float(sk["cd_t"]) - delta
		if bool(sk["auto"]) and float(sk["cd_t"]) <= 0.0 and not _dead and _enemies_alive():
			_cast_skill(sk)
	if not _arrow_rain.is_empty():
		_tick_arrow_rain(delta)
	if _shield_t > 0.0:
		_shield_t -= delta
		if _shield_t <= 0.0:
			_shield_hp = 0.0
			if _skill_fx.has("holy_shield") and is_instance_valid(_skill_fx["holy_shield"]):
				_skill_fx["holy_shield"].queue_free()
			_skill_fx.erase("holy_shield")
	if _parry_t > 0.0:
		_parry_t -= delta
		if _parry_t <= 0.0:
			if _parried and _has_riposte_weapon():
				_riposte = true
				FX.glow(get_parent(), global_position, 90.0, Color(1.0, 0.85, 0.3, 0.8), 0.4, 6)
			_parried = false


func _cast_skill(sk: Dictionary) -> void:
	var sid := String(sk["id"])
	var lv := int(sk["lv"])
	var cds: Array = GameData.SKILLS[sid]["cd"]
	sk["cd_t"] = float(cds[mini(lv, cds.size()) - 1])
	match sid:
		"arrow_rain":
			_start_arrow_rain(lv)
		"stomp":
			_cast_stomp(lv)
		"soul_drain":
			_cast_soul_drain(lv)
		"blink":
			_cast_blink()
		"holy_shield":
			_cast_holy_shield(lv)
		"meteor":
			_cast_meteor(lv)
		"time_stop":
			_cast_time_stop()


## 箭雨：在最密集怪群降箭 5 秒，每 0.25 秒一支
func _start_arrow_rain(lv: int) -> void:
	var center := _densest_cluster(220.0)
	if center == Vector2.INF:
		center = global_position + Vector2(200, 0)
	_arrow_rain = {"t": 5.0 * _duration_mult(), "tick": 0.0, "lv": lv, "center": center, "dmg": 26.0 * float(lv) * _dmg_mult()}
	var sp := Sprite2D.new()
	sp.texture = load("res://assets/sprites/fx/fx_arrow_rain_zone.png") as Texture2D
	sp.modulate = Color(1.0, 0.9, 0.6, 0.75)
	sp.material = FX._additive_mat()
	sp.global_position = center
	sp.z_index = 4
	var target_s := 220.0 / 64.0
	sp.scale = Vector2.ONE * target_s * 0.5
	get_parent().add_child(sp)
	_arrow_rain["node"] = sp
	var tw := sp.create_tween()
	tw.tween_property(sp, "scale", Vector2.ONE * target_s, 0.3)
	FX.glow(get_parent(), center, 200.0, Color(1.0, 0.85, 0.4, 0.8), 0.5, 5)
	FX.hitstop(get_tree(), 0.04)


func _tick_arrow_rain(delta: float) -> void:
	var node: Node2D = _arrow_rain.get("node")
	if not is_instance_valid(node):
		_arrow_rain = {}
		return
	_arrow_rain["t"] = float(_arrow_rain["t"]) - delta
	_arrow_rain["tick"] = float(_arrow_rain["tick"]) - delta
	var center: Vector2 = _arrow_rain["center"]
	if float(_arrow_rain["tick"]) <= 0.0:
		_arrow_rain["tick"] = 0.25
		var target := _enemy_near(center + Vector2(randf_range(-140, 140), randf_range(-140, 140)), 260.0)
		var aim: Vector2 = target.global_position if target != null else center
		var p: Node2D = PoolManager.acquire("projectile", func() -> Node:
			var np := Node2D.new()
			np.set_script(load("res://scripts/projectile.gd"))
			return np)
		var dmg: float = float(_arrow_rain["dmg"])
		p.setup("res://assets/sprites/fx/projectiles/proj_arrow.png",
			aim + Vector2(randf_range(-30, 30), -320.0), Vector2.DOWN,
			760.0, dmg, 0, 1, 0.0, _crit_chance(), _crit_mult(), 420.0, 0.6)
		p.home = self
		get_parent().add_child(p)
		p.add_to_group("projectiles")
		if p.has_meta("pooled_reuse"):
			p.remove_meta("pooled_reuse")
			p.spawn_init()
		FX.glow(get_parent(), aim, 40.0, Color(1.0, 0.9, 0.5, 0.5), 0.15, 5)
	if float(_arrow_rain["t"]) <= 0.0:
		var tw := node.create_tween()
		tw.tween_property(node, "modulate:a", 0.0, 0.4)
		tw.tween_callback(node.queue_free)
		_arrow_rain = {}


func _densest_cluster(radius: float) -> Vector2:
	# v0.8 B4：空间网格加速（原实现为全量组 O(n²) 扫描）
	var best := Vector2.INF
	var best_n := 0
	for e in Registry.all_enemies():
		var n := 0
		for e2 in Registry.query_circle(e.global_position, radius):
			if is_instance_valid(e2) and not bool(e2.get("dead")) and e.global_position.distance_to(e2.global_position) <= radius:
				n += 1
		if n > best_n:
			best_n = n
			best = e.global_position
	return best


## 践踏：范围击退 + 眩晕 2 秒
func _cast_stomp(lv: int) -> void:
	var radius := 240.0 * (1.0 + 0.15 * float(lv - 1)) * _area_mult()
	var dmg := 70.0 * float(lv) * _dmg_mult()
	for e in Registry.query_circle(global_position, radius):
		if not is_instance_valid(e) or bool(e.get("dead")):
			continue
		var to: Vector2 = e.global_position - global_position
		if to.length() <= radius:
			_deal_hit(e, dmg, to.normalized() if to.length() > 1.0 else Vector2.UP, 3.0, {"critdmg_bonus": 0.0, "execute": 0.0, "flags": {}}, 2.0)
	var sp := Sprite2D.new()
	sp.texture = load("res://assets/sprites/fx/fx_stomp_crack.png") as Texture2D
	sp.modulate = Color(1.0, 0.8, 0.5, 0.95)
	sp.global_position = global_position
	sp.z_index = 6
	get_parent().add_child(sp)
	var tw := sp.create_tween()
	tw.set_parallel(true)
	tw.tween_property(sp, "scale", Vector2.ONE * radius / 64.0, 0.35).from(Vector2.ONE * 0.3)
	tw.tween_property(sp, "modulate:a", 0.0, 0.45)
	tw.chain().tween_callback(sp.queue_free)
	FX.glow_ring(get_parent(), global_position, radius, Color(1.0, 0.75, 0.4, 0.85), 0.45, 6)
	FX.shake(get_parent(), 12.0)
	FX.hitstop(get_tree(), 0.06)


## 灵魂虹吸：范围伤害按已损血量加成，回血 30%
func _cast_soul_drain(lv: int) -> void:
	var radius := 260.0 * _area_mult()
	var missing := 1.0 - hp / maxf(1.0, max_hp)
	var total := 0.0
	for e in Registry.query_circle(global_position, radius):
		if not is_instance_valid(e) or bool(e.get("dead")):
			continue
		var to: Vector2 = e.global_position - global_position
		if to.length() <= radius:
			var dmg := (50.0 + 90.0 * missing) * float(lv) * _dmg_mult()
			var is_crit := randf() < _crit_chance()
			if is_crit:
				dmg *= _crit_mult()
			e.take_damage(dmg, -to.normalized() if to.length() > 1.0 else Vector2.UP, 0.4)
			total += dmg
			FX.hit_spark(get_parent(), e.global_position, Color(0.6, 0.3, 1.0))
			FX.damage_number(get_parent(), e.global_position, dmg, is_crit)
	var heal := total * 0.3
	hp = minf(max_hp, hp + heal)
	hp_changed.emit(hp, max_hp)
	var sp := Sprite2D.new()
	sp.texture = load("res://assets/sprites/fx/fx_soul_orb.png") as Texture2D
	sp.modulate = Color(0.7, 0.4, 1.0, 0.9)
	sp.material = FX._additive_mat()
	sp.global_position = global_position
	sp.z_index = 6
	get_parent().add_child(sp)
	var tw := sp.create_tween()
	tw.set_parallel(true)
	tw.tween_property(sp, "scale", Vector2.ONE * radius / 48.0, 0.5).from(Vector2.ONE * 0.3)
	tw.tween_property(sp, "modulate:a", 0.0, 0.55)
	tw.chain().tween_callback(sp.queue_free)
	FX.glow(get_parent(), global_position, radius * 1.2, Color(0.6, 0.3, 1.0, 0.7), 0.5, 5)
	FX.hitstop(get_tree(), 0.05)


## 闪现：向移动方向位移 260px，无敌 0.5 秒
func _cast_blink() -> void:
	var dir := facing
	if velocity.length() > 30.0:
		dir = velocity.normalized()
	var from := global_position
	global_position += dir * 260.0
	_invuln_t = maxf(_invuln_t, 0.5)
	for pos in [from, global_position]:
		var sp := Sprite2D.new()
		sp.texture = load("res://assets/sprites/fx/fx_dash_ghost.png") as Texture2D
		sp.modulate = Color(0.6, 0.9, 1.0, 0.8)
		sp.material = FX._additive_mat()
		sp.global_position = pos
		sp.z_index = 5
		get_parent().add_child(sp)
		var tw := sp.create_tween()
		tw.tween_property(sp, "modulate:a", 0.0, 0.35)
		tw.tween_callback(sp.queue_free)
	FX.glow(get_parent(), global_position, 100.0, Color(0.6, 0.9, 1.0, 0.7), 0.3, 5)


## 圣盾：吸收盾持续 6 秒
func _cast_holy_shield(lv: int) -> void:
	_shield_hp = 90.0 * float(lv) * _dmg_mult() + max_hp * 0.15
	_shield_t = 6.0 * _duration_mult()
	if _skill_fx.has("holy_shield") and is_instance_valid(_skill_fx["holy_shield"]):
		_skill_fx["holy_shield"].queue_free()
	var sp := Sprite2D.new()
	sp.texture = load("res://assets/sprites/fx/fx_holy_shield.png") as Texture2D
	sp.modulate = Color(0.6, 0.9, 1.0, 0.85)
	sp.material = FX._additive_mat()
	sp.z_index = 5
	add_child(sp)
	_skill_fx["holy_shield"] = sp
	var tw := sp.create_tween().set_loops()
	tw.tween_property(sp, "scale", Vector2(1.15, 1.15), 0.7).from(Vector2(0.6, 0.6))
	tw.tween_property(sp, "scale", Vector2(0.95, 0.95), 0.7)
	FX.glow(get_parent(), global_position, 120.0, Color(0.6, 0.9, 1.0, 0.8), 0.4, 5)


## 陨石术：随机落点 8 颗陨石轰炸
func _cast_meteor(lv: int) -> void:
	_meteor_rain(8, float(lv))


func _meteor_rain(n: int, lv: float) -> void:
	for i in range(n):
		if i > 0:
			await get_tree().create_timer(0.22).timeout
		if _dead:
			return
		var anchor := global_position
		var e := _enemy_near(global_position, 700.0)
		if e != null:
			anchor = e.global_position
		var pos := anchor + Vector2(randf_range(-190, 190), randf_range(-190, 190))
		var dmg := 110.0 * lv * _dmg_mult()
		var game := get_parent()
		# 陨石落下视觉
		var sp := Sprite2D.new()
		sp.texture = load("res://assets/sprites/fx/projectiles/proj_meteor.png") as Texture2D
		sp.global_position = pos + Vector2(-160, -420)
		sp.z_index = 7
		game.add_child(sp)
		var tw := sp.create_tween()
		tw.set_parallel(true)
		tw.tween_property(sp, "global_position", pos, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(sp, "rotation", 5.0, 0.35)
		tw.chain().tween_callback(sp.queue_free)
		tw.chain().tween_callback(func() -> void:
			if is_instance_valid(game) and game.has_method("spawn_explosion"):
				game.spawn_explosion(pos, 130.0 * _area_mult(), dmg, _crit_chance(), _crit_mult()))
		FX.glow(game, pos, 90.0, Color(1.0, 0.5, 0.2, 0.6), 0.35, 5)


## 时间凝滞：全场怪减速 50% 持续 3 秒
func _cast_time_stop() -> void:
	var dur := 3.0 * _duration_mult()
	get_tree().call_group("enemies", "apply_slow", dur)
	var sp := Sprite2D.new()
	sp.texture = load("res://assets/sprites/fx/fx_time_ripple.png") as Texture2D
	sp.modulate = Color(0.5, 0.8, 1.0, 0.8)
	sp.material = FX._additive_mat()
	sp.global_position = global_position
	sp.z_index = 7
	get_parent().add_child(sp)
	var tw := sp.create_tween()
	tw.set_parallel(true)
	tw.tween_property(sp, "scale", Vector2.ONE * 9.0, 0.6).from(Vector2.ONE * 0.5)
	tw.tween_property(sp, "modulate:a", 0.0, 0.7)
	tw.chain().tween_callback(sp.queue_free)
	FX.glow(get_parent(), global_position, 420.0, Color(0.5, 0.8, 1.0, 0.5), 0.6, 5)
	FX.hitstop(get_tree(), 0.06)


## 解除帧 punch：1.25 → 1.0（QUAD 衰减，Time 驱动不受顿帧缩放影响）
func _punch_now() -> float:
	if _punch_start_ms < 0:
		return 1.0
	var k := float(Time.get_ticks_msec() - _punch_start_ms) / 250.0
	if k >= 1.0:
		_punch_start_ms = -1
		return 1.0
	return 1.0 + 0.25 * (1.0 - k) * (1.0 - k)


## v0.8 合成演出（05 附录 A.2 权威时间轴；计时器 ignore_time_scale）
func _synth_ceremony() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var gold := Color(1.0, 0.85, 0.3, 0.9)
	# T0 蓄力：脚下金圈生长 + 全屏微暗聚焦 + supercharge 起
	FX.glow(parent, global_position, 170.0, gold, 0.5, 5)
	EventBus.bgm_duck.emit(true)
	if parent.has_method("set_cine_dim"):
		parent.set_cine_dim(0.85)
	Sfx.play("supercharge")
	await get_tree().create_timer(0.2, true, false, true).timeout
	if not is_inside_tree():
		return
	# T+200 蓄力升尘（近似：脚下金辉）
	FX.glow(parent, global_position + Vector2(0, 20), 90.0, gold, 0.3, 4)
	await get_tree().create_timer(0.3, true, false, true).timeout
	if not is_inside_tree():
		return
	# T+500 爆发帧：superweapon_burst + 双核 glow + 演出顿帧 0.12 + shake(14) 同帧
	EventBus.superweapon_burst.emit(global_position)
	FX.glow(parent, global_position, 300.0, Color(1.0, 0.85, 0.3, 0.95), 0.8, 6)
	FX.glow(parent, global_position, 150.0, Color(1, 1, 1, 0.9), 0.5, 6)
	FX.hitstop(get_tree(), 0.12, true)
	FX.shake(parent, 14.0)
	Sfx.play("superburst")
	await get_tree().create_timer(0.12, true, false, true).timeout
	if not is_inside_tree():
		return
	# T+620 解除帧：superring + punch + 第一重金环 + 冲击碎片
	Sfx.play("superring")
	_punch_start_ms = Time.get_ticks_msec()
	FX.glow_ring(parent, global_position, 500.0, gold, 0.6, 6)
	FX.hit_spark(parent, global_position, gold)
	await get_tree().create_timer(0.09, true, false, true).timeout
	if not is_inside_tree():
		return
	# T+710 / T+800 第二、三重金环
	FX.glow_ring(parent, global_position, 500.0, gold, 0.6, 6)
	await get_tree().create_timer(0.09, true, false, true).timeout
	if not is_inside_tree():
		return
	FX.glow_ring(parent, global_position, 500.0, gold, 0.6, 6)
	await get_tree().create_timer(0.1, true, false, true).timeout
	if not is_inside_tree():
		return
	# T+900 超武金色常驻光环
	if _synth_aura == null or not is_instance_valid(_synth_aura):
		_synth_aura = FX.attach_aura(self, 100.0, Color(1.0, 0.85, 0.3, 0.45))
	# T+1400 收幕：聚焦复原 + BGM 回来
	await get_tree().create_timer(0.5, true, false, true).timeout
	EventBus.bgm_duck.emit(false)
	if is_inside_tree() and is_instance_valid(parent) and parent.has_method("set_cine_dim"):
		parent.set_cine_dim(1.0)


# ---------- relics ----------
func _relic_tbl() -> Dictionary:
	if _relic_tbl_cache.is_empty():
		_relic_tbl_cache = ContentDB.table("relics")
	return _relic_tbl_cache


func gain_relic(rid: String) -> void:
	if rid in relics or relics.size() >= GameData.RELIC_SLOTS:
		gain_gold(50)
		return
	relics.append(rid)
	_recalc()
	relics_changed.emit()
	var rname := String(GameData.RELICS.get(rid, {}).get("rarity", "普通"))
	EventBus.relic_gained.emit(rid, "l" if rname == "传说" else ("r" if rname == "稀有" else "c"))
	EventBus.relic_picked.emit(rid)


# ---------- damage / xp / gold ----------
func take_damage(amount: float, from_dir: Vector2, knock_mult: float = 1.0, from: Node2D = null) -> void:
	if _dead or _invuln_t > 0.0:
		return
	Sfx.play("hurt")
	# 护甲减伤（上限 60%）
	var armor := minf(0.04 * (float(passives.get("armor", 0)) + Meta.bonus_armor()), 0.6)
	amount *= 1.0 - armor
	amount *= Meta.bonus_tough_mult()
	# 圣十字：上次受击后 3 秒窗口内减伤 25%
	if "cross" in relics:
		var now_ms := Time.get_ticks_msec()
		if now_ms < _cross_until_ms:
			amount *= 0.75
		elif not is_instance_valid(_cross_aura):
			_cross_aura = FX.attach_aura(self, 120.0, Color(1, 1, 1, 0.5))
		_cross_until_ms = now_ms + 3000
		_cross_aura_t = 3.0
	# 完美格挡：3 秒窗口内减伤 50% 并反弹
	if _parry_t > 0.0:
		_parried = true
		FX.glow(get_parent(), global_position, 110.0, Color(0.5, 0.8, 1.0, 0.8), 0.25, 6)
		FX.hitstop(get_tree(), 0.05)
		if from != null and is_instance_valid(from) and from.has_method("take_damage"):
			from.take_damage(amount * 1.0, -from_dir, 0.5)
		amount *= 0.5
	# 圣盾/虹吸护盾先吸收
	if _shield_hp > 0.0:
		var absorbed := minf(_shield_hp, amount)
		_shield_hp -= absorbed
		amount -= absorbed
		FX.hit_spark(get_parent(), global_position, Color(0.5, 0.85, 1.0))
		if _shield_hp <= 0.0:
			_shield_t = 0.0
	hp = maxf(0.0, hp - amount)
	_flash_t = 0.12
	_invuln_t = 0.7
	velocity += from_dir * 280.0 * knock_mult
	hp_changed.emit(hp, max_hp)
	EventBus.player_damaged.emit(amount, from_dir, from)
	FX.shake(get_parent(), 6.0)
	if hp <= 0.0:
		var can_phoenix := "phoenixheart" in relics and not _revive_used
		var can_talent := Meta.has_revive() and not _revive_talent_used
		if can_phoenix or can_talent:
			if can_phoenix:
				_revive_used = true
			else:
				_revive_talent_used = true
			hp = max_hp * 0.5
			_invuln_t = 2.0
			hp_changed.emit(hp, max_hp)
			return
		_die()


## v0.8.5 地形持续伤害：走护甲/坚韧/护盾，但不触发无敌帧、击退、受击音与震屏
func take_terrain_damage(amount: float) -> void:
	if _dead or amount <= 0.0:
		return
	var armor := minf(0.04 * (float(passives.get("armor", 0)) + Meta.bonus_armor()), 0.6)
	amount *= 1.0 - armor
	amount *= Meta.bonus_tough_mult()
	if _shield_hp > 0.0:
		var absorbed := minf(_shield_hp, amount)
		_shield_hp -= absorbed
		amount -= absorbed
		if _shield_hp <= 0.0:
			_shield_t = 0.0
	if amount <= 0.0:
		hp_changed.emit(hp, max_hp)
		return
	hp = maxf(0.0, hp - amount)
	_flash_t = maxf(_flash_t, 0.05)
	hp_changed.emit(hp, max_hp)
	if hp <= 0.0:
		var can_phoenix := "phoenixheart" in relics and not _revive_used
		var can_talent := Meta.has_revive() and not _revive_talent_used
		if can_phoenix or can_talent:
			if can_phoenix:
				_revive_used = true
			else:
				_revive_talent_used = true
			hp = max_hp * 0.5
			_invuln_t = 2.0
			hp_changed.emit(hp, max_hp)
			return
		_die()


func gain_xp(n: int) -> void:
	if _dead:
		return
	xp += int(round(float(n) * _xp_mult()))
	var need := GameData.xp_for_level(level)
	while xp >= need:
		xp -= need
		level += 1
		_pending_levels += 1
		need = GameData.xp_for_level(level)
	xp_changed.emit(xp, GameData.xp_for_level(level), level)
	if _pending_levels > 0:
		leveled_up.emit()


func gain_gold(n: int) -> void:
	gold += int(round(float(n) * _gold_mult()))
	gold_changed.emit(gold)


func consume_pending_level() -> void:
	_pending_levels = maxi(0, _pending_levels - 1)


func has_pending_levels() -> bool:
	return _pending_levels > 0


func _die() -> void:
	_dead = true
	died.emit()
	EventBus.player_died.emit()
	var tw := create_tween()
	tw.tween_property(visual, "rotation", deg_to_rad(80), 0.4).set_trans(Tween.TRANS_BACK)
	tw.parallel().tween_property(sprite, "modulate:a", 0.25, 0.4)
