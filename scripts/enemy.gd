extends CharacterBody2D
class_name Enemy
## Top-down enemy: chases the player with a hop gait (no chess-piece sliding),
## deals contact damage, dies to player weapons. Elites: hp x8, scale x1.3,
## pulsing gold glow, drop relics.

signal died(enemy: Enemy)

var enemy_id := "slime"
var hp := 30.0
var max_hp := 30.0
var speed := 85.0
var dmg := 10.0
var xp_value := 2
var dead := false
var hp_mult := 1.0
var dmg_mult := 1.0
var touch_cd := 0.0
var base_scale := 1.0
var fly := false
var elite := false
var is_boss := false

# v0.3 状态：眩晕 / 减速 / 中毒 / 虚弱 / 诅咒
var stun_t := 0.0
var slow_t := 0.0
var poison_t := 0.0
var poison_dps := 0.0
var weaken_t := 0.0
var curse_t := 0.0
var curse_dps := 0.0

var _player: Node2D = null
var _knock := Vector2.ZERO
var _knock_t := 0.0
var _flash_t := 0.0
var _wobble := 0.0
var _elite_t := 0.0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	add_to_group("enemies")
	var def: Dictionary = GameData.ENEMIES[enemy_id]
	hp = float(def["hp"]) * hp_mult
	if elite:
		hp *= 8.0
	max_hp = hp
	speed = float(def["speed"])
	dmg = float(def["dmg"]) * dmg_mult
	xp_value = int(def["xp"]) * (5 if elite else 1)
	base_scale = float(def["scale"]) * (1.3 if elite else 1.0)
	fly = bool(def.get("fly", false))
	var sf := SpriteFrames.new()
	sf.add_animation("idle")
	sf.set_animation_speed("idle", 7.0)
	sf.set_animation_loop("idle", true)
	for i in range(2):
		var p := "res://assets/sprites/enemies/enemy_%s_idle_%02d.png" % [enemy_id, i]
		sf.add_frame("idle", load(p) as Texture2D)
	sprite.frames = sf
	sprite.scale = Vector2.ONE * base_scale
	sprite.play("idle")
	_player = get_tree().get_first_node_in_group("player") as Node2D
	_wobble = randf() * TAU


func _physics_process(delta: float) -> void:
	if dead or _player == null or not is_instance_valid(_player):
		return
	if touch_cd > 0.0:
		touch_cd -= delta
	if _flash_t > 0.0:
		_flash_t -= delta
	# v0.3 dot 计时
	_tick_dots(delta)
	# elite gold pulse (combined with hit flash)
	if elite:
		_elite_t += delta
		var pulse := 0.5 + 0.5 * sin(_elite_t * 6.0)
		if _flash_t > 0.0:
			var k := clampf(_flash_t / 0.1, 0.0, 1.0)
			sprite.modulate = Color(1.0 + 2.5 * k, 1.0 + 2.5 * k, 0.6 + 1.6 * pulse)
		else:
			sprite.modulate = Color(1.0 + 0.45 * pulse, 1.0 + 0.35 * pulse, 0.55)
	elif _flash_t > 0.0:
		var k := clampf(_flash_t / 0.1, 0.0, 1.0)
		sprite.modulate = Color(1.0 + 2.5 * k, 1.0 + 2.5 * k, 1.0 + 2.5 * k)
	else:
		sprite.modulate = Color.WHITE

	var to: Vector2 = _player.global_position - global_position
	var dist := to.length()
	var dir := to.normalized() if dist > 1.0 else Vector2.ZERO
	_wobble += delta * 3.0
	var side := dir.rotated(PI * 0.5) * sin(_wobble) * 0.35

	# 嘲讽：400px 内有嘲讽召唤物则优先攻击它
	var target := _pick_target()
	if target != _player:
		to = target.global_position - global_position
		dist = to.length()
		dir = to.normalized() if dist > 1.0 else Vector2.ZERO

	if stun_t > 0.0:
		# 眩晕：原地发抖，不移动不攻击
		stun_t -= delta
		velocity = Vector2.ZERO
		move_and_slide()
		sprite.rotation = sin(_wobble * 30.0) * 0.15
		return
	sprite.rotation = 0.0

	var spd := speed * (0.5 if slow_t > 0.0 else 1.0)
	if slow_t > 0.0:
		slow_t -= delta
		# 减速染色
		sprite.modulate = Color(0.7, 0.85, 1.2) if _flash_t <= 0.0 and not elite else sprite.modulate

	if _knock_t > 0.0:
		_knock_t -= delta
		velocity = _knock
	else:
		velocity = (dir + side).normalized() * spd
	move_and_slide()

	sprite.flip_h = dir.x < 0.0
	if fly:
		# bat hover: gentle sine bob, no ground hop
		sprite.position.y = -18.0 + sin(_wobble * 2.2) * 6.0
		sprite.scale = Vector2.ONE * base_scale * (1.0 + 0.04 * sin(_wobble * 4.0))
	else:
		# ground hop: squash & stretch so it reads as moving, not sliding
		var hop := absf(sin(_wobble * 2.0))
		sprite.position.y = -10.0 - hop * 7.0
		sprite.scale = Vector2(base_scale * (1.0 - 0.06 * hop), base_scale * (1.0 + 0.09 * hop))

	if dist < 54.0 and touch_cd <= 0.0 and target.has_method("take_damage"):
		var hit_dmg := dmg * (0.7 if weaken_t > 0.0 else 1.0)
		target.take_damage(hit_dmg, dir, 1.0, self)
		touch_cd = 0.8
	if weaken_t > 0.0:
		weaken_t -= delta


## 嘲讽目标选择：范围内嘲讽召唤物 > 玩家
func _pick_target() -> Node2D:
	var best: Node2D = null
	var best_d := 420.0
	for t in get_tree().get_nodes_in_group("taunt_summons"):
		if not is_instance_valid(t) or bool(t.get("dead")):
			continue
		var d := global_position.distance_to(t.global_position)
		if d < best_d:
			best_d = d
			best = t
	return best if best != null else _player


func _tick_dots(delta: float) -> void:
	if dead:
		return
	if poison_t > 0.0:
		poison_t -= delta
		hp -= poison_dps * delta
		if randf() < delta * 8.0:
			FX.glow(get_tree().get_first_node_in_group("game"), global_position,
				36.0, Color(0.4, 0.9, 0.3, 0.5), 0.2, 5)
	if curse_t > 0.0:
		curse_t -= delta
		hp -= curse_dps * delta
	if hp <= 0.0 and not dead:
		_die()


func apply_poison(dps: float, duration: float) -> void:
	poison_dps = maxf(poison_dps, dps)
	poison_t = maxf(poison_t, duration)


func apply_curse(dps: float, duration: float) -> void:
	curse_dps = maxf(curse_dps, dps)
	curse_t = maxf(curse_t, duration)


func apply_slow(duration: float) -> void:
	slow_t = maxf(slow_t, duration)


func apply_weaken(duration: float) -> void:
	weaken_t = maxf(weaken_t, duration)


func take_damage(amount: float, from_dir: Vector2, knock_mult: float = 1.0, stun: float = 0.0) -> void:
	if dead:
		return
	hp -= amount
	_flash_t = 0.1
	_knock = from_dir * 320.0 * knock_mult
	_knock_t = 0.16
	if stun > 0.0:
		stun_t = maxf(stun_t, stun)
	if hp <= 0.0:
		_die()


func _die() -> void:
	dead = true
	collision_layer = 0
	collision_mask = 0
	# 尸体标记（尸爆用）
	var game := get_tree().get_first_node_in_group("game")
	if game != null and game.has_method("spawn_corpse"):
		game.spawn_corpse(global_position, elite)
	died.emit(self)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(sprite, "scale", Vector2(base_scale * 1.3, base_scale * 0.3), 0.16).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(sprite, "modulate:a", 0.0, 0.3).set_delay(0.1)
	tw.chain().tween_callback(queue_free)
