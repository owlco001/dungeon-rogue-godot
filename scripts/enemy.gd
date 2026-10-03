extends CharacterBody2D
class_name Enemy
## Top-down enemy: chases the player with a hop gait (no chess-piece sliding),
## deals contact damage, dies to player weapons. Elites: hp x8, scale x1.3,
## pulsing gold glow, drop relics.

signal died(enemy: Enemy)

const PoolManager := preload("res://systems/pool_manager.gd")
# 敌人帧同样是 384px 画布；地砖源图 192px 映射到 48px 世界单位。
const ART_SCALE := 0.25
const DEATH_SQUASH := Vector2(1.15, 0.45)

var enemy_id := "slime"
# v0.8 B4：SpriteFrames 按兵种共享（原实现每只怪新建一份，7 份重复构建）
static var _frames_cache := {}


static func _shared_frames(eid: String) -> SpriteFrames:
	if _frames_cache.has(eid):
		return _frames_cache[eid]
	var sf := SpriteFrames.new()
	sf.add_animation("idle")
	sf.set_animation_speed("idle", 7.0)
	sf.set_animation_loop("idle", true)
	for i in range(2):
		var p := "res://assets/sprites/enemies/enemy_%s_idle_%02d.png" % [eid, i]
		sf.add_frame("idle", load(p) as Texture2D)
	# v0.8.17：移动帧（enemy_<eid>_move_00/01）；缺失则不建 move 动画，调用方回退 idle
	if ResourceLoader.exists("res://assets/sprites/enemies/enemy_%s_move_00.png" % eid):
		sf.add_animation("move")
		sf.set_animation_speed("move", 7.0)
		sf.set_animation_loop("move", true)
		for i in range(2):
			var mp := "res://assets/sprites/enemies/enemy_%s_move_%02d.png" % [eid, i]
			if ResourceLoader.exists(mp):
				sf.add_frame("move", load(mp) as Texture2D)
	_frames_cache[eid] = sf
	return sf

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
var kind := "melee"
var _dmg_taken := 1.0
var _shoot_t := 0.0
var _fuse_t := -1.0
var _blast_dmg := 0.0
var _dir_smooth := Vector2.ZERO
# L4 寻路（注：无头驱动编译图认不出新 class_name，全部走 preload/字面量）
const PathfindScript := preload("res://systems/pathfind.gd")
var pf_grid := PackedByteArray()
var pf_gw := 32
var pf_gh := 24
var pf_cell := 50.0
var _path := PackedVector2Array()
var _path_i := 0
var _repath_t := 0.0
var _los_clear := true
var _los_t := 0.0
var _stuck_t := 0.0
var _path_mode := false
var _rescue := false

# v0.3 状态：眩晕 / 减速 / 中毒 / 虚弱 / 诅咒
var stun_t := 0.0
var slow_t := 0.0
var terrain_speed_mult := 1.0  # v0.8.5 地形移速倍率（main 写入，飞行怪免疫）
var terrain_id := ""
var poison_t := 0.0
var poison_dps := 0.0
var weaken_t := 0.0
var curse_t := 0.0
var curse_dps := 0.0

var _player: Node2D = null
var _knock := Vector2.ZERO
var _knock_t := 0.0
var _flash_t := 0.0
var _punch := 1.0
var _wobble := 0.0
var _elite_t := 0.0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D


## v0.8.17：按速度切换 move/idle（无 move 动画的怪保持 idle）
func _update_move_anim() -> void:
	var want_anim := "move" if velocity.length() > 25.0 else "idle"
	if want_anim != sprite.animation and sprite.sprite_frames.has_animation(want_anim):
		sprite.play(want_anim)


func _ready() -> void:
	spawn_init()


## 出生初始化（首生由 _ready 调用；池化复用时由生成方在 add_child 后调用）
func spawn_init() -> void:
	add_to_group("enemies")
	Registry.register_enemy(self)
	dead = false
	touch_cd = 0.0
	stun_t = 0.0
	slow_t = 0.0
	terrain_speed_mult = 1.0
	terrain_id = ""
	poison_t = 0.0
	poison_dps = 0.0
	weaken_t = 0.0
	curse_t = 0.0
	curse_dps = 0.0
	_knock_t = 0.0
	_flash_t = 0.0
	_punch = 1.0
	_elite_t = 0.0
	collision_layer = 2
	collision_mask = 4
	visible = true
	var def: Dictionary = GameData.ENEMIES[enemy_id]
	hp = float(def["hp"]) * hp_mult
	if elite:
		hp *= GameData.elite_hp_mult()
	max_hp = hp
	speed = float(def["speed"])
	dmg = float(def["dmg"]) * dmg_mult
	xp_value = int(def["xp"]) * (5 if elite else 1)
	base_scale = float(def["scale"]) * (1.3 if elite else 1.0)
	fly = bool(def.get("fly", false))
	kind = String(def.get("kind", "melee"))
	_dmg_taken = float(def.get("dmg_taken", 1.0))
	_shoot_t = randf() * 2.2
	_fuse_t = -1.0
	_blast_dmg = 28.0 * dmg_mult
	_dir_smooth = Vector2.ZERO
	_path = PackedVector2Array()
	_path_i = 0
	_repath_t = 0.0
	_los_clear = true
	_los_t = randf() * 0.25
	sprite.frames = _shared_frames(enemy_id)
	sprite.scale = Vector2.ONE * ART_SCALE * base_scale
	sprite.modulate = Color.WHITE
	sprite.play("idle")
	_player = get_tree().get_first_node_in_group("player") as Node2D
	_wobble = randf() * TAU


## 池化回收前：断开生成方连接的 died 信号（生成方每次出生重连）
func pool_reset() -> void:
	for c in died.get_connections():
		died.disconnect(c["callable"])


func _release_self() -> void:
	PoolManager.release_or_free("enemy", self)


func _physics_process(delta: float) -> void:
	if dead:
		return
	# L4 卡墙救援：深陷碰撞/挤压时传送回最近可达格心（几何边角的最终保险）
	if _rescue and not pf_grid.is_empty():
		_rescue = false
		global_position = PathfindScript.nearest_floor_center(pf_grid, pf_gw, pf_gh,
			global_position, pf_cell)
		_path = PackedVector2Array()
		_path_i = 0
		_repath_t = 0.0
		velocity = Vector2.ZERO
		return
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node2D
		if _player == null:
			return
	if touch_cd > 0.0:
		touch_cd -= delta
	if _flash_t > 0.0:
		_flash_t -= delta
	_punch = move_toward(_punch, 1.0, delta * 1.2)
	# v0.3 dot 计时
	_tick_dots(delta)
	# elite gold pulse (combined with hit flash)
	if elite:
		_elite_t += delta
		var pulse := 0.5 + 0.5 * sin(_elite_t * 6.0)
		if _flash_t > 0.0:
			var k := clampf(_flash_t / 0.08, 0.0, 1.0)
			sprite.modulate = Color(1.0 + 2.5 * k, 1.0 + 2.5 * k, 0.6 + 1.6 * pulse)
		else:
			sprite.modulate = Color(1.0 + 0.45 * pulse, 1.0 + 0.35 * pulse, 0.55)
	elif _flash_t > 0.0:
		var k := clampf(_flash_t / 0.08, 0.0, 1.0)
		sprite.modulate = Color(1.0 + 2.5 * k, 1.0 + 2.5 * k, 1.0 + 2.5 * k)
	else:
		sprite.modulate = Color.WHITE
	# 自爆前摇：红闪脉动覆盖（05 §4.4 警戒红）+ 地面红环随前摇扩散到爆炸半径
	if _fuse_t >= 0.0:
		var fp := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.03)
		sprite.modulate = Color(1.0 + 1.6 * fp, 0.45, 0.4)

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

	# L4：视线检测（0.25s 一次，被墙挡住则走 A*
	_los_t -= delta
	if _los_t <= 0.0:
		_los_t = 0.25
		_los_clear = _ray_clear(target.global_position) if target != null else true
	if stun_t > 0.0:
		# 眩晕：原地发抖，不移动不攻击
		stun_t -= delta
		velocity = Vector2.ZERO
		move_and_slide()
		sprite.rotation = sin(_wobble * 30.0) * 0.15
		_update_move_anim()
		return
	sprite.rotation = 0.0

	var spd := speed * terrain_speed_mult * (0.5 if slow_t > 0.0 else 1.0)
	if slow_t > 0.0:
		slow_t -= delta
		# 减速染色
		sprite.modulate = Color(0.7, 0.85, 1.2) if _flash_t <= 0.0 and not elite else sprite.modulate

	# v0.8 行为分化（01 §4.1）：远程保持距离带并吐酸 / 自爆前摇停步
	var behavior_hold := false
	if kind == "ranged":
		_shoot_t -= delta
		if dist <= 520.0 and _shoot_t <= 0.0 and target != null and _los_clear:
			_shoot_t = 2.2
			_fire_acid(target)
		if dist < 300.0:
			velocity = (-dir + side).normalized() * spd
			behavior_hold = true
		elif dist <= 400.0:
			velocity = dir.rotated(PI * 0.5) * (1.0 if sin(_wobble) >= 0.0 else -1.0) * spd * 0.4
			behavior_hold = true
	elif kind == "exploder":
		if _fuse_t < 0.0 and target == _player and dist < 70.0:
			_fuse_t = 1.0
			EventBus.exploder_fuse_start.emit(global_position)
			if get_parent() != null:
				FX.glow_ring(get_parent(), global_position, 130.0,
					Color(1.0, 0.29, 0.29, 0.7), 1.0, 4)
		if _fuse_t >= 0.0:
			_fuse_t -= delta
			velocity = Vector2.ZERO
			behavior_hold = true
			if _fuse_t < 0.0:
				_explode()
				return

	if _knock_t > 0.0:
		_knock_t -= delta
		velocity = _knock
	elif not behavior_hold:
		# L3 转向插值：方向 slerp 平滑，避免瞬时掉头抖动
		var desired: Vector2
		_path_mode = not pf_grid.is_empty() and not _los_clear and target != null
		if _path_mode:
			if velocity.length() < spd * 0.25:
				_stuck_t += delta
				if _stuck_t > 0.5:
					_stuck_t = 0.0
					_rescue = true
			else:
				_stuck_t = 0.0
			desired = _path_desired(delta, target)
		else:
			_stuck_t = 0.0
			desired = (dir + side).normalized()
		if _dir_smooth == Vector2.ZERO:
			_dir_smooth = desired
		else:
			_dir_smooth = _dir_smooth.slerp(desired, minf(1.0, 8.0 * delta)).normalized()
		velocity = _dir_smooth * spd
	move_and_slide()

	sprite.flip_h = dir.x < 0.0
	_update_move_anim()
	if fly:
		# bat hover: gentle sine bob, no ground hop
		sprite.position.y = -18.0 + sin(_wobble * 2.2) * 6.0
		sprite.scale = Vector2.ONE * ART_SCALE * base_scale * (1.0 + 0.04 * sin(_wobble * 4.0)) * _punch
	else:
		# ground hop: squash & stretch so it reads as moving, not sliding
		var hop := absf(sin(_wobble * 2.0))
		sprite.position.y = -10.0 - hop * 7.0
		sprite.scale = Vector2(base_scale * (1.0 - 0.06 * hop), base_scale * (1.0 + 0.09 * hop)) * ART_SCALE * _punch
	if _fuse_t >= 0.0:
		sprite.scale *= 1.0 + (1.0 - maxf(_fuse_t, 0.0)) * 0.45

	if dist < 54.0 and touch_cd <= 0.0 and kind != "exploder" and target.has_method("take_damage"):
		var hit_dmg := dmg * (0.7 if weaken_t > 0.0 else 1.0)
		target.take_damage(hit_dmg, dir, 1.0, self)
		touch_cd = 0.8
	if weaken_t > 0.0:
		weaken_t -= delta


## 喷吐怪：复用 projectile.gd 的敌对弹（01 §4.1/§9.4）
func _fire_acid(t: Node2D) -> void:
	var game := get_parent()
	if game == null:
		return
	var p: Node2D = PoolManager.acquire("projectile", func() -> Node:
		var np := Node2D.new()
		np.set_script(load("res://scripts/projectile.gd"))
		return np)
	var dir_t: Vector2 = (t.global_position - global_position).normalized()
	p.setup_hostile("res://assets/sprites/fx/projectiles/proj_bullet.png",
		global_position + dir_t * 30.0, dir_t, 320.0, dmg, 520.0)
	p.home = self
	game.add_child(p)
	p.add_to_group("projectiles")
	if p.has_meta("pooled_reuse"):
		p.remove_meta("pooled_reuse")
		p.spawn_init()
	EventBus.enemy_fired.emit(global_position)


## 自爆怪引爆：半径 130，伤害 28×层倍率；爆炸后按正常死亡结算（XP/掉落）
func _explode() -> void:
	if dead:
		return
	var game := get_tree().get_first_node_in_group("game")
	if game != null:
		FX.explosion(game, global_position, 130.0, Color(1.0, 0.45, 0.2))
		FX.shake(game, 10.0)
		FX.hitstop(get_tree(), 0.04)
	if is_instance_valid(_player) \
			and global_position.distance_to(_player.global_position) <= 130.0:
		var d: Vector2 = (_player.global_position - global_position).normalized()
		_player.take_damage(_blast_dmg, d, 1.0, self)
	_die()


## L4：视线射线（只撞墙体 layer 4）
func _ray_clear(to: Vector2) -> bool:
	var params := PhysicsRayQueryParameters2D.create(global_position, to, 4, [get_rid()])
	var hit := get_world_2d().direct_space_state.intersect_ray(params)
	return hit.is_empty()


## L4：A* 路径点跟随（0.5s 重规划）
func _path_desired(delta: float, target: Node2D) -> Vector2:
	_repath_t -= delta
	if _repath_t <= 0.0 or _path_i >= _path.size():
		_repath_t = 0.5
		_path = PathfindScript.find_path(pf_grid, pf_gw, pf_gh,
			global_position, target.global_position, pf_cell)
		_path_i = 1  # index 0 ≈ 自身位置
	if _path_i < _path.size():
		# 严格格心跟随（格 50px、身半径 22：格心线距墙面 25px，跳点拉直会把身体送进墙角）
		while _path_i < _path.size() \
				and global_position.distance_to(_path[_path_i]) < 20.0:
			_path_i += 1
	if _path_i >= _path.size():
		var to: Vector2 = target.global_position - global_position
		return to.normalized() if to.length() > 1.0 else Vector2.ZERO
	var wp: Vector2 = _path[_path_i] - global_position
	return wp.normalized() if wp.length() > 1.0 else Vector2.ZERO


## 嘲讽目标选择：范围内嘲讽召唤物 > 玩家
func _pick_target() -> Node2D:
	var best: Node2D = null
	var best_d := 420.0
	for t in Registry.taunt_list():
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
	hp -= amount * _dmg_taken
	_flash_t = 0.08
	_punch = 1.12
	_knock = from_dir * 320.0 * knock_mult
	_knock_t = 0.12
	if stun > 0.0:
		stun_t = maxf(stun_t, stun)
	if hp <= 0.0:
		_die()


func _die() -> void:
	dead = true
	Registry.unregister_enemy(self)
	collision_layer = 0
	collision_mask = 0
	# 尸体标记（尸爆用）
	var game := get_tree().get_first_node_in_group("game")
	if game != null and game.has_method("spawn_corpse"):
		game.spawn_corpse(global_position, elite)
	died.emit(self)
	EventBus.enemy_died.emit(self)
	# 击杀顿帧（白名单）：普通怪走打击通道，精英走演出通道
	if elite:
		FX.hitstop(get_tree(), 0.08, true)
	else:
		FX.hitstop(get_tree(), 0.04)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(sprite, "scale", ART_SCALE * base_scale * DEATH_SQUASH, 0.16).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(sprite, "modulate:a", 0.0, 0.3).set_delay(0.1)
	tw.chain().tween_callback(_release_self)
