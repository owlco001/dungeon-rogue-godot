extends CharacterBody2D
## Boss: big single-sprite brute in group "enemies" (duck-typed for weapons).
## Skills: ground slam (red-circle telegraph), charge dash, summon (final boss).
## Emits hp_changed for the HUD boss bar, died(enemy) like Enemy.

signal died(enemy: Node2D)
signal hp_changed(hp: float, max_hp: float)

class Telegraph extends Node2D:
	var radius := 130.0
	var t := 0.0
	var duration := 1.0
	func _process(d: float) -> void:
		t += d
		queue_redraw()
		if t >= duration + 0.2:
			queue_free()
	func _draw() -> void:
		var k := clampf(t / duration, 0.0, 1.0)
		draw_circle(Vector2.ZERO, radius, Color(1.0, 0.2, 0.2, 0.10 + 0.18 * k))
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(1.0, 0.25, 0.25, 0.45 + 0.55 * k), 5.0)

var boss_def := {}
var boss_name := "Boss"
var hp := 1000.0
var max_hp := 1000.0
var speed := 55.0
var dmg := 25.0
var dead := false
var elite := false
var is_boss := true
var can_summon := false

var _player: Node2D = null
var _game: Node = null
var _sprite: Sprite2D = null
var _slam_t := 3.0
var _charge_t := 7.0
var _summon_t := 10.0
var _telegraph_t := 0.0
var _charge_dir := Vector2.ZERO
var _dashing := 0.0
var _touch_cd := 0.0
var _flash_t := 0.0
var _wobble := 0.0
var _squash_t := 0.0
var _slow_t := 0.0
var _windup_t := 0.0
var _windup_pos := Vector2.ZERO
var _dust: CPUParticles2D = null
var _base_scale := 1.0


func setup(p_def: Dictionary, p_pos: Vector2) -> void:
	boss_def = p_def
	position = p_pos
	Sfx.play("boss_roar")


func _ready() -> void:
	add_to_group("enemies")
	boss_name = String(boss_def["name"])
	max_hp = float(boss_def["hp"])
	hp = max_hp
	dmg = float(boss_def["dmg"])
	speed = float(boss_def["speed"])
	can_summon = bool(boss_def.get("final", false))
	_sprite = Sprite2D.new()
	_sprite.texture = load(String(boss_def["tex"])) as Texture2D
	_base_scale = float(boss_def.get("scale", 1.0))
	_sprite.scale = Vector2.ONE * _base_scale
	add_child(_sprite)
	# 脚下扬尘
	_dust = CPUParticles2D.new()
	_dust.amount = 16
	_dust.lifetime = 0.5
	_dust.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	_dust.emission_sphere_radius = 30.0
	_dust.direction = Vector2(0, -1)
	_dust.spread = 60.0
	_dust.initial_velocity_min = 30.0
	_dust.initial_velocity_max = 70.0
	_dust.gravity = Vector2(0, -30)
	_dust.scale_amount_min = 3.0
	_dust.scale_amount_max = 6.0
	_dust.color = Color(0.6, 0.55, 0.5, 0.4)
	_dust.position = Vector2(0, 60)
	_dust.emitting = false
	add_child(_dust)
	var cs := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 70.0
	cs.shape = circle
	add_child(cs)
	collision_layer = 2
	collision_mask = 4
	_player = get_tree().get_first_node_in_group("player") as Node2D
	_game = get_tree().get_first_node_in_group("game")
	hp_changed.emit(hp, max_hp)


func _physics_process(delta: float) -> void:
	if dead or _player == null or not is_instance_valid(_player):
		return
	if _touch_cd > 0.0:
		_touch_cd -= delta

	_wobble += delta * 2.0
	# idle 呼吸：scale.y 正弦起伏
	var breathe := 1.0 + 0.04 * sin(_wobble * 2.0)
	var target_scale := Vector2(_base_scale * (2.0 - breathe) * 0.5 + _base_scale * 0.5, _base_scale * breathe)
	# 受击 squash
	if _squash_t > 0.0:
		_squash_t -= delta
		var k := clampf(_squash_t / 0.12, 0.0, 1.0)
		target_scale = Vector2(_base_scale * (1.0 + 0.18 * k), _base_scale * (1.0 - 0.22 * k))
	# 攻击前摇：膨胀 + 红闪
	if _windup_t > 0.0:
		_windup_t -= delta
		var wk := 1.0 - _windup_t / 0.4
		target_scale = Vector2.ONE * _base_scale * (1.0 + 0.15 * wk)
		_sprite.modulate = Color(1.0 + 0.8 * wk, 1.0 - 0.4 * wk, 1.0 - 0.4 * wk)
		velocity = Vector2.ZERO
		if _windup_t <= 0.0:
			_do_slam_at(_windup_pos)
	elif _flash_t > 0.0:
		_flash_t -= delta
		var k := clampf(_flash_t / 0.12, 0.0, 1.0)
		_sprite.modulate = Color(1.0 + 2.0 * k, 1.0 + 2.0 * k, 1.0 + 2.0 * k)
	else:
		_sprite.modulate = Color.WHITE
	_sprite.scale = target_scale
	# 移动倾斜 + 扬尘
	var moving := velocity.length() > 20.0
	if moving:
		_sprite.rotation = clampf(velocity.x / 400.0, -0.12, 0.12)
		_dust.emitting = true
	else:
		_sprite.rotation = 0.02 * sin(_wobble)
		_dust.emitting = false

	if _dashing > 0.0:
		_dashing -= delta
		velocity = _charge_dir * 700.0
		var to_p: Vector2 = _player.global_position - global_position
		if to_p.length() < 110.0 and _touch_cd <= 0.0 and _player.has_method("take_damage"):
			_player.take_damage(dmg * 1.2, to_p.normalized(), 1.0, self)
			_touch_cd = 0.8
	elif _telegraph_t > 0.0:
		# charging up: stand still, flash
		_telegraph_t -= delta
		velocity = Vector2.ZERO
		_sprite.modulate = Color(1.0 + 0.6 * absf(sin(_telegraph_t * 20.0)), 1.0, 1.0)
		if _telegraph_t <= 0.0:
			_dashing = 0.65
	elif _windup_t <= 0.0:
		var to: Vector2 = _player.global_position - global_position
		var dist := to.length()
		var spd := speed * (0.5 if _slow_t > 0.0 else 1.0)
		velocity = to.normalized() * spd if dist > 90.0 else Vector2.ZERO
		_sprite.flip_h = to.x < 0.0
		if dist < 110.0 and _touch_cd <= 0.0 and _player.has_method("take_damage"):
			_player.take_damage(dmg, to.normalized(), 1.0, self)
			_touch_cd = 0.8
		_tick_skills(delta * (0.5 if _slow_t > 0.0 else 1.0))
	if _slow_t > 0.0:
		_slow_t -= delta
		# 减速染色
		_sprite.modulate = Color(0.7, 0.85, 1.2) if _flash_t <= 0.0 and _windup_t <= 0.0 and _telegraph_t <= 0.0 else _sprite.modulate
	move_and_slide()


func _tick_skills(delta: float) -> void:
	_slam_t -= delta
	_charge_t -= delta
	if _slam_t <= 0.0:
		_slam_t = 5.0
		# 攻击前摇 0.4s：膨胀+红闪+红辉，然后出砸地
		_windup_t = 0.4
		_windup_pos = _player.global_position
		FX.glow(get_parent(), global_position, 460.0, Color(1.0, 0.25, 0.2, 0.7), 0.4, 4)
		return
	if _charge_t <= 0.0:
		_charge_t = 9.0
		_telegraph_t = 0.6
		_charge_dir = (_player.global_position - global_position).normalized()
		return
	if can_summon:
		_summon_t -= delta
		if _summon_t <= 0.0:
			_summon_t = 12.0
			if _game != null and _game.has_method("spawn_boss_minions"):
				_game.spawn_boss_minions(global_position, 3)


func _do_slam_at(at: Vector2) -> void:
	var tele := Telegraph.new()
	tele.radius = 150.0
	tele.duration = 1.0
	tele.global_position = at
	get_parent().add_child(tele)
	await get_tree().create_timer(1.0).timeout
	if dead:
		return
	if _game != null and _game.has_method("spawn_hazard"):
		_game.spawn_hazard(at, 150.0, dmg * 1.6, self)


func _do_slam() -> void:
	_do_slam_at(_player.global_position)


func take_damage(amount: float, from_dir: Vector2, knock_mult: float = 1.0, stun: float = 0.0) -> void:
	if dead:
		return
	hp = maxf(0.0, hp - amount)
	_flash_t = 0.12
	_squash_t = 0.12
	hp_changed.emit(hp, max_hp)
	if hp <= 0.0:
		_die()


## 时间凝滞用：Boss 也吃减速
func apply_slow(duration: float) -> void:
	_slow_t = maxf(_slow_t, duration)


func _die() -> void:
	dead = true
	collision_layer = 0
	collision_mask = 0
	_dust.emitting = false
	# Boss 也留尸体（尸爆盛宴）
	if _game != null and _game.has_method("spawn_corpse"):
		_game.spawn_corpse(global_position, true)
	died.emit(self)
	# 死亡粒子爆
	var burst := CPUParticles2D.new()
	burst.amount = 40
	burst.lifetime = 0.8
	burst.one_shot = true
	burst.explosiveness = 0.9
	burst.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	burst.emission_sphere_radius = 40.0
	burst.direction = Vector2(0, -1)
	burst.spread = 180.0
	burst.initial_velocity_min = 120.0
	burst.initial_velocity_max = 320.0
	burst.gravity = Vector2(0, 300)
	burst.scale_amount_min = 4.0
	burst.scale_amount_max = 9.0
	burst.color = Color(1.0, 0.45, 0.25, 0.9)
	burst.global_position = global_position
	get_parent().add_child(burst)
	burst.emitting = true
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_sprite, "scale", Vector2(1.6, 0.4), 0.35).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(_sprite, "modulate:a", 0.0, 0.5).set_delay(0.2)
	tw.chain().tween_callback(queue_free)
