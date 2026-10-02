extends Node2D
## Player projectile: flies (with slight homing), hits enemies, supports
## pierce / chain (墨菲法球) / explosive (霰弹枪), per-hit crit rolls.

var tex_path := ""
var dir := Vector2.RIGHT
var speed := 500.0
var dmg := 20.0
var chains_left := 0
var pierce_left := 0
var explosive_radius := 0.0
var crit_chance := 0.05
var crit_mult := 1.5
var max_dist := 700.0
var knock_mult := 1.0
# v0.3: 回旋斧 / 黑洞吸附 / 分裂小斧
var boomerang := false
var boomerang_returns := 1     # 回旋次数（去程+返程为一次）
var blackhole := false
var split_axe := false
var home: Node2D = null        # 回旋斧的发射者（玩家）
var mini := false              # 分裂小斧：不再分裂

var _traveled := 0.0
var _hit_set := {}
var _sprite: Sprite2D
var _game: Node = null
var _returning := false
var _returns_done := 0
var _spin := 0.0


func setup(p_tex: String, p_pos: Vector2, p_dir: Vector2, p_speed: float,
		p_dmg: float, p_chains: int, p_pierce: int = 0, p_explosive: float = 0.0,
		p_crit_chance: float = 0.05, p_crit_mult: float = 1.5,
		p_max_dist: float = 700.0, p_knock: float = 1.0) -> void:
	tex_path = p_tex
	position = p_pos
	dir = p_dir.normalized()
	speed = p_speed
	dmg = p_dmg
	chains_left = p_chains
	pierce_left = p_pierce
	explosive_radius = p_explosive
	crit_chance = p_crit_chance
	crit_mult = p_crit_mult
	max_dist = p_max_dist
	knock_mult = p_knock


func _ready() -> void:
	_sprite = Sprite2D.new()
	_sprite.texture = load(tex_path) as Texture2D
	_sprite.rotation = dir.angle()
	add_child(_sprite)
	z_index = 4
	_game = get_tree().get_first_node_in_group("game")
	# 辉光 halo（柔和无颗粒，跟随投射物）
	FX.attach_aura(self, 64.0, Color(1.0, 0.8, 0.45, 0.55), 3)
	# 拖尾粒子
	var trail := CPUParticles2D.new()
	trail.amount = 12
	trail.lifetime = 0.35
	trail.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINT
	trail.direction = -dir
	trail.spread = 20.0
	trail.initial_velocity_min = 10.0
	trail.initial_velocity_max = 40.0
	trail.scale_amount_min = 2.0
	trail.scale_amount_max = 4.0
	trail.color = Color(1.0, 0.85, 0.5, 0.5)
	trail.z_index = 3
	add_child(trail)
	trail.emitting = true


func _roll_dmg() -> Array:
	# returns [damage, is_crit]
	if randf() < crit_chance:
		return [dmg * crit_mult, true]
	return [dmg, false]


func _physics_process(delta: float) -> void:
	_apply_homing(delta)
	var step := speed * delta
	global_position += dir * step
	_traveled += step
	if boomerang:
		if _tick_boomerang(delta):
			return
	elif _traveled > max_dist:
		queue_free()
		return
	if boomerang:
		_spin += delta * 14.0
		_sprite.rotation = _spin
	for e in Registry.query_circle(global_position, 34.0):
		if not is_instance_valid(e) or e.dead or _hit_set.has(e.get_instance_id()):
			continue
		if global_position.distance_to(e.global_position) < 34.0:
			_hit_set[e.get_instance_id()] = true
			var rolled: Array = _roll_dmg()
			var final_dmg: float = rolled[0]
			var is_crit: bool = rolled[1]
			e.take_damage(final_dmg, dir, knock_mult)
			if blackhole:
				_blackhole_pull()
			if split_axe and not mini:
				_spawn_mini_axes()
			# 命中火花 + 伤害数字（暴击黄色大字）
			if _game != null:
				FX.hit_spark(_game, global_position)
				FX.damage_number(_game, e.global_position, final_dmg, is_crit)
				if is_crit:
					FX.shake(_game, 10.0)
					FX.glow(_game, global_position, 110.0, Color(1.0, 0.85, 0.25, 0.85), 0.3, 6)
					FX.hitstop(_game.get_tree(), 0.05)
				# v0.8：普通命中不再全局顿帧（白名单制），反馈由白闪+击退+形变承担
			if explosive_radius > 0.0:
				_explode()
				queue_free()
				return
			if chains_left > 0:
				var nxt := _next_chain_target(e)
				if nxt != null:
					chains_left -= 1
					dir = (nxt.global_position - global_position).normalized()
					_sprite.rotation = dir.angle()
					continue
			if boomerang:
				# 回旋斧：命中继续飞（穿透次数内不消失）
				if pierce_left > 0:
					pierce_left -= 1
				continue
			if pierce_left > 0:
				pierce_left -= 1
				continue
			queue_free()
			return


func _gone() -> bool:
	return false


## 回旋斧：飞到 max_dist 后返程回玩家，完成 returns 次后消失；返回 true 表示已消失
func _tick_boomerang(delta: float) -> bool:
	if not _returning and _traveled >= max_dist:
		_returning = true
	if _returning:
		if home == null or not is_instance_valid(home):
			queue_free()
			return true
		var to: Vector2 = home.global_position - global_position
		if to.length() < 44.0:
			_returns_done += 1
			_hit_set.clear()
			if _returns_done >= boomerang_returns:
				if _game != null:
					FX.glow(_game, global_position, 60.0, Color(1.0, 0.8, 0.4, 0.6), 0.2, 5)
				queue_free()
				return true
			_returning = false
			_traveled = 0.0
		else:
			dir = to.normalized()
	return false


## 黑洞：命中点小范围吸附
func _blackhole_pull() -> void:
	for e in Registry.query_circle(global_position, 130.0):
		if not is_instance_valid(e) or e.dead:
			continue
		var to: Vector2 = global_position - e.global_position
		var d := to.length()
		if d < 130.0 and d > 4.0 and e.has_method("take_damage"):
			# 轻怪吸附（Boss/精英抗性）
			var pull := 260.0 * (0.25 if (bool(e.get("is_boss")) or bool(e.get("elite"))) else 1.0)
			e.global_position += to.normalized() * pull * 0.12
	FX.glow_ring(_game, global_position, 130.0, Color(0.6, 0.3, 1.0, 0.7), 0.35, 5)


## 分裂：命中时分裂出 2 把小斧
func _spawn_mini_axes() -> void:
	for i in range(2):
		var m := Node2D.new()
		m.set_script(load("res://scripts/projectile.gd"))
		var mdir := dir.rotated(randf_range(-0.6, 0.6))
		m.setup(tex_path, global_position, mdir, speed * 0.8, dmg * 0.5,
			0, 1, 0.0, crit_chance, crit_mult, max_dist * 0.6, knock_mult)
		m.boomerang = true
		m.boomerang_returns = 1
		m.mini = true
		m.home = home
		m.scale = Vector2.ONE * 0.6
		_game.add_child(m)
		m.add_to_group("projectiles")


func _explode() -> void:
	if _game == null or not _game.has_method("spawn_explosion"):
		return
	_game.spawn_explosion(global_position, explosive_radius, dmg * 0.6, crit_chance, crit_mult)


func _apply_homing(delta: float) -> void:
	# 回旋斧返程时不追踪
	if boomerang and _returning:
		return
	# gentle steering so fast strafing enemies (bats) stay hittable
	var best: Node2D = Registry.nearest(global_position, 150.0, _hit_set)
	if best == null:
		return
	var want := (best.global_position - global_position).normalized()
	var turn := clampf(wrapf(want.angle() - dir.angle(), -PI, PI), -4.5 * delta, 4.5 * delta)
	dir = Vector2.from_angle(dir.angle() + turn)
	_sprite.rotation = dir.angle()


func _next_chain_target(from_enemy: Node2D) -> Node2D:
	return Registry.nearest(from_enemy.global_position, 240.0, _hit_set)
