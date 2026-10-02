extends CharacterBody2D
class_name Summon
## 召唤物 v0.3：哨兵炮塔(定点自动射击) / 猎犬·骷髅战士·蜂群(近战追击索敌)。
## 单帧精灵 + 程序化 juice：y 正弦浮动、移动倾斜、受击 squash。
## flags: overload(超载) / split(死亡分裂) / bloodlust(嗜血) / hp_mult /
##        taunt(嘲讽) / thorns(荆棘) / poison(叠毒) / death_blast(死亡爆炸)

signal died(summon: Summon)

const SUMMON_DEFS := {
	"turret": {"hp": 70.0, "speed": 0.0, "atk_cd": 0.9, "melee_range": 0.0, "fly": false},
	"hound": {"hp": 90.0, "speed": 265.0, "atk_cd": 0.8, "melee_range": 48.0, "fly": false},
	"skeleton_warrior": {"hp": 130.0, "speed": 190.0, "atk_cd": 1.0, "melee_range": 54.0, "fly": false},
	"bee": {"hp": 45.0, "speed": 305.0, "atk_cd": 0.6, "melee_range": 42.0, "fly": true},
}
const TEX_DIR := "res://assets/sprites/summons/summon_%s_idle_%02d.png"

var summon_type := "hound"
var slot := -1          # player.weapons 下标（超武合成后槽位不变，召唤物保留）
var wid := ""           # 武器 id（skel_army 染色区分用）
var mini := false       # 分裂出的小犬：不再分裂
var dead := false

var _player: Node2D = null
var _game: Node = null
var _sprite: Sprite2D = null
var _frames: Array = []
var _frame_t := 0.0
var _frame_i := 0
var _bob_t := 0.0
var _atk_t := 0.0
var _squash_t := 0.0
var _overload_t := 0.0    # 超载计时（每 10s 一轮）
var _overload_on := 0.0   # 超载剩余
var _bl_t := 0.0          # 嗜血剩余
var _follow_off := Vector2.ZERO
var hp := 50.0
var max_hp := 50.0


func setup(p_type: String, p_slot: int, p_wid: String, p_player: Node2D, p_mini: bool = false) -> void:
	summon_type = p_type
	slot = p_slot
	wid = p_wid
	mini = p_mini
	_player = p_player


func _stats() -> Dictionary:
	# 实时从玩家武器槽读属性（升级/超武即时生效）
	if _player != null and _player.has_method("summon_stats"):
		return _player.summon_stats(slot)
	return {}


func _ready() -> void:
	add_to_group("summons")
	_game = get_tree().get_first_node_in_group("game")
	for i in range(2):
		_frames.append(load(TEX_DIR % [summon_type, i]) as Texture2D)
	_sprite = Sprite2D.new()
	_sprite.texture = _frames[0]
	add_child(_sprite)
	# 骷髅大军：骷髅战士精灵染绿紫（尸毒主题）以示区别
	if summon_type == "skeleton_warrior" and wid in ["skel_army", "super_skel_army"]:
		_sprite.modulate = Color(0.62, 1.0, 0.72)
	if mini:
		_sprite.scale = Vector2.ONE * 0.62
	var s := _stats()
	var def: Dictionary = SUMMON_DEFS[summon_type]
	max_hp = float(def["hp"]) * float(s.get("summon_hp_mult", 1.0))
	if mini:
		max_hp *= 0.5
	hp = max_hp
	if bool(s.get("flags", {}).get("taunt", false)):
		add_to_group("taunt_summons")
	_follow_off = Vector2.RIGHT.rotated(randf() * TAU) * randf_range(70.0, 110.0)
	var cs := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 18.0
	cs.shape = circle
	add_child(cs)
	collision_layer = 0
	collision_mask = 0


func _dmg() -> float:
	var s := _stats()
	var mult := 0.7 if summon_type == "bee" else 1.0
	if mini:
		mult *= 0.5
	return float(s.get("dmg", 10.0)) * mult


func _physics_process(delta: float) -> void:
	if dead or _player == null or not is_instance_valid(_player):
		return
	var s := _stats()
	var flags: Dictionary = s.get("flags", {})
	var def: Dictionary = SUMMON_DEFS[summon_type]
	_bob_t += delta
	_frame_t += delta
	if _frame_t > 0.25:
		_frame_t = 0.0
		_frame_i = 1 - _frame_i
		_sprite.texture = _frames[_frame_i]
	if _squash_t > 0.0:
		_squash_t -= delta
	# 嗜血：击杀后 5 秒攻速+30%
	var atk_mult := 1.0
	if _bl_t > 0.0:
		_bl_t -= delta
		atk_mult = 1.3
	if _atk_t > 0.0:
		_atk_t -= delta / atk_mult

	if summon_type == "turret":
		_tick_turret(delta, s, flags)
	else:
		_tick_melee(delta, s, flags, def)
	_juice(delta, def)


func _tick_turret(delta: float, s: Dictionary, flags: Dictionary) -> void:
	velocity = Vector2.ZERO
	# 超载：每 10 秒双倍射速 3 秒
	if flags.has("overload"):
		_overload_t += delta
		if _overload_on > 0.0:
			_overload_on -= delta
		elif _overload_t >= 10.0:
			_overload_t = 0.0
			_overload_on = 3.0
			FX.glow(_game, global_position, 90.0, Color(1.0, 0.6, 0.2, 0.8), 0.3, 5)
	if _atk_t > 0.0:
		return
	var target := _nearest_enemy(float(s.get("range", 520.0)))
	if target == null:
		return
	var rate := 2.0 if _overload_on > 0.0 else 1.0
	_atk_t = float(s.get("cd", 0.9)) / rate
	_fire_at(target, s)


func _fire_at(target: Node2D, s: Dictionary) -> void:
	var p := Node2D.new()
	p.set_script(load("res://scripts/projectile.gd"))
	var dir := (target.global_position - global_position).normalized()
	var crit_chance: float = _player._crit_chance() if _player.has_method("_crit_chance") else 0.05
	var crit_mult: float = _player._crit_mult() if _player.has_method("_crit_mult") else 1.5
	p.setup(
		"res://assets/sprites/fx/projectiles/%s.png" % String(s.get("proj", "proj_bullet")),
		global_position + dir * 30.0, dir,
		float(s.get("proj_speed", 600.0)), _dmg(), 0, 0, 0.0,
		crit_chance, crit_mult, float(s.get("range", 520.0)) + 60.0, 1.0)
	_game.add_child(p)
	p.add_to_group("projectiles")
	FX.glow(_game, global_position + dir * 30.0, 40.0, Color(1.0, 0.8, 0.4, 0.6), 0.15, 5)


func _tick_melee(delta: float, s: Dictionary, flags: Dictionary, def: Dictionary) -> void:
	var target := _nearest_enemy(650.0)
	var dest: Vector2
	var want_speed := float(def["speed"])
	if target != null:
		dest = target.global_position
		var d := global_position.distance_to(dest)
		var rng: float = float(def["melee_range"])
		if d <= rng:
			want_speed = 0.0
			_try_melee(target, s, flags, rng)
		elif d < rng + 30.0:
			want_speed *= 0.4
	else:
		# 无怪跟随玩家
		dest = _player.global_position + _follow_off.rotated(0.0)
		if global_position.distance_to(dest) < 40.0:
			want_speed = 0.0
	var dir := (dest - global_position).normalized() if global_position.distance_to(dest) > 4.0 else Vector2.ZERO
	velocity = velocity.move_toward(dir * want_speed, 1400.0 * delta)
	move_and_slide()
	_sprite.flip_h = dir.x < 0.0


func _try_melee(target: Node2D, s: Dictionary, flags: Dictionary, rng: float) -> void:
	if _atk_t > 0.0:
		return
	_atk_t = float(s.get("cd", 0.9))
	var was_alive := not bool(target.get("dead"))
	var crit_chance: float = _player._crit_chance() if _player.has_method("_crit_chance") else 0.05
	var crit_mult: float = _player._crit_mult() if _player.has_method("_crit_mult") else 1.5
	var dmg := _dmg()
	var is_crit := randf() < crit_chance
	if is_crit:
		dmg *= crit_mult
	var dir := (target.global_position - global_position).normalized()
	target.take_damage(dmg, dir, 1.2)
	if flags.has("poison") and target.has_method("apply_poison"):
		target.apply_poison(dmg * 0.5, 3.0)
	FX.hit_spark(_game, target.global_position)
	FX.damage_number(_game, target.global_position, dmg, is_crit)
	# 嗜血：击杀后攻速+30%
	if was_alive and bool(target.get("dead")) and flags.has("bloodlust"):
		_bl_t = 5.0
		FX.glow(_game, global_position, 70.0, Color(1.0, 0.3, 0.3, 0.7), 0.3, 5)


func _nearest_enemy(max_range: float) -> Node2D:
	var best: Node2D = null
	var best_d := max_range
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or bool(e.get("dead")):
			continue
		var d := global_position.distance_to(e.global_position)
		if d < best_d:
			best_d = d
			best = e
	return best


func _juice(delta: float, def: Dictionary) -> void:
	# 程序化 bob：y 正弦浮动 + 移动倾斜；受击 squash
	var fly: bool = bool(def.get("fly", false))
	var amp := 7.0 if fly else 3.5
	var base_y := -14.0 if fly else 0.0
	_sprite.position.y = base_y + sin(_bob_t * 4.2) * amp
	var lean := clampf(velocity.x / 300.0, -1.0, 1.0) * 0.12
	_sprite.rotation = lerpf(_sprite.rotation, lean, minf(1.0, 10.0 * delta))
	var sc := 0.62 if mini else 1.0
	if _squash_t > 0.0:
		var k := _squash_t / 0.12
		_sprite.scale = Vector2(sc * (1.0 + 0.35 * k), sc * (1.0 - 0.3 * k))
	else:
		var b := 1.0 + 0.05 * sin(_bob_t * 4.2)
		_sprite.scale = Vector2(sc * (2.0 - b), sc * b)


func take_damage(amount: float, from_dir: Vector2 = Vector2.ZERO, knock_mult: float = 1.0, from: Node2D = null) -> void:
	if dead:
		return
	hp -= amount
	_squash_t = 0.12
	FX.hit_spark(_game, global_position, Color(0.7, 0.9, 1.0))
	if hp <= 0.0:
		_die(amount, from)


func _die(last_hit: float, from: Node2D) -> void:
	dead = true
	var s := _stats()
	var flags: Dictionary = s.get("flags", {})
	died.emit(self)
	# 死亡爆炸
	if flags.has("death_blast"):
		var radius := float(s.get("radius", 100.0))
		FX.explosion(_game, global_position, radius, Color(0.55, 0.9, 0.4))
		for e in get_tree().get_nodes_in_group("enemies"):
			if not is_instance_valid(e) or bool(e.get("dead")):
				continue
			var to: Vector2 = e.global_position - global_position
			if to.length() <= radius:
				e.take_damage(_dmg() * 2.0, to.normalized() if to.length() > 1.0 else Vector2.UP, 1.5)
	else:
		FX.glow(_game, global_position, 60.0, Color(0.8, 0.8, 0.9, 0.6), 0.25, 5)
	# 分裂：2 只小犬
	if flags.has("split") and not mini and summon_type == "hound":
		for i in range(2):
			var pup := Summon.new()
			pup.setup("hound", slot, wid, _player, true)
			pup.global_position = global_position + Vector2.RIGHT.rotated(randf() * TAU) * 30.0
			_game.add_child(pup)
	# 荆棘：反弹所受伤害给攻击者
	if from != null and is_instance_valid(from) and flags.has("thorns") and from.has_method("take_damage"):
		var ratio := 0.3
		if flags.has("thorns_v"):
			ratio = float(flags["thorns_v"])
		elif not (flags["thorns"] is bool):
			ratio = float(flags["thorns"])
		var dir := (from.global_position - global_position).normalized()
		from.take_damage(last_hit * ratio, dir, 0.5)
	queue_free()


func _exit_tree() -> void:
	remove_from_group("taunt_summons")
