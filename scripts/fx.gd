class_name FX
extends RefCounted
## Static combat-juice helpers: explosions, hit sparks, damage numbers,
## screen shake, hitstop, levelup beam, soft glow (refined bloom-like aura).
## Glow uses a smooth radial gradient + additive blend: no grain.
## v0.8 B4（A9）：六池对象池（Glow 64 / Label 64 / Ring 8 / Spark 16 /
## Explosion 8 / Rise 4 = 164 节点）预建于 FXPool 根节点下，acquire→配置→
## tween→release，不再每次命中新建节点；同帧 glow/spark/label 各节流 ≤6。

static var _glow_tex: Texture2D = null
static var _glow_ring_tex: Texture2D = null
static var _add_mat: CanvasItemMaterial = null


static func _glow_texture() -> Texture2D:
	# perfectly smooth radial falloff: hot core -> soft edge -> transparent
	if _glow_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.25, Color(1, 1, 1, 0.85))
		g.add_point(0.55, Color(1, 1, 1, 0.32))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 128
		t.height = 128
		_glow_tex = t
	return _glow_tex


static func _glow_ring_texture() -> Texture2D:
	# soft ring: transparent center, bright band at ~62% radius, soft outer edge
	if _glow_ring_tex == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.45, 0.62, 0.8, 1.0])
		g.colors = PackedColorArray([
			Color(1, 1, 1, 0), Color(1, 1, 1, 0), Color(1, 1, 1, 0.95),
			Color(1, 1, 1, 0.3), Color(1, 1, 1, 0)])
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 256
		t.height = 256
		_glow_ring_tex = t
	return _glow_ring_tex


## 共享 ADD 混合材质单例（v0.8：原实现每次调用新建材质，DrawCall 预算的前提）
static func _additive_mat() -> CanvasItemMaterial:
	if _add_mat == null:
		_add_mat = CanvasItemMaterial.new()
		_add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _add_mat


# ---------------- 对象池（A9） ----------------
const POOL_SIZE := {"glow": 64, "label": 64, "ring": 8, "spark": 16, "boom": 8, "rise": 4}
static var _pool_root: Node2D = null
static var _free := {"glow": [], "label": [], "ring": [], "spark": [], "boom": [], "rise": []}
static var _busy := {}  # instance_id -> kind
static var _throttle_frame := -1
static var _throttle_counts := {}


static func _ensure_pool(tree: SceneTree) -> void:
	if _pool_root != null and is_instance_valid(_pool_root):
		return
	_pool_root = Node2D.new()
	_pool_root.name = "FXPool"
	tree.root.add_child(_pool_root)
	for k in _free.keys():
		_free[k] = []
	_busy.clear()
	for i in range(POOL_SIZE["glow"]):
		_free["glow"].append(_make_glow_sprite())
	for i in range(POOL_SIZE["label"]):
		_free["label"].append(_make_label())
	for i in range(POOL_SIZE["ring"]):
		_free["ring"].append(_make_ring())
	for i in range(POOL_SIZE["spark"]):
		_free["spark"].append(_make_spark())
	for i in range(POOL_SIZE["boom"]):
		_free["boom"].append(_make_boom())
	for i in range(POOL_SIZE["rise"]):
		_free["rise"].append(_make_rise())


static func _acquire(kind: String, tree: SceneTree) -> Node:
	_ensure_pool(tree)
	var arr: Array = _free[kind]
	while not arr.is_empty():
		var n: Node = arr.pop_back()
		if is_instance_valid(n):
			_busy[n.get_instance_id()] = kind
			return n
	return null  # 池空 → 调用方按降级策略跳过该视觉


static func _release(n: Node) -> void:
	if not is_instance_valid(n):
		return
	var id := n.get_instance_id()
	var kind := String(_busy.get(id, ""))
	if kind == "":
		return
	_busy.erase(id)
	if n.has_meta("tw"):
		var tw: Tween = n.get_meta("tw") as Tween
		if tw != null and tw.is_valid():
			tw.kill()
		n.remove_meta("tw")
	if n is CanvasItem:
		(n as CanvasItem).visible = false
	if n is Ring:
		(n as Ring).set_process(false)
	if n is Node2D:
		(n as Node2D).process_mode = Node.PROCESS_MODE_INHERIT
	_free[kind].append(n)


static func _release_later(tree: SceneTree, n: Node, delay: float) -> void:
	await tree.create_timer(delay, true).timeout
	_release(n)


## 同帧节流：glow / spark / label 每帧各最多 6 次（05 §5.2）
static func _throttle_ok(kind: String) -> bool:
	var f := Engine.get_process_frames()
	if f != _throttle_frame:
		_throttle_frame = f
		_throttle_counts.clear()
	var c := int(_throttle_counts.get(kind, 0))
	if c >= 6:
		return false
	_throttle_counts[kind] = c + 1
	return true


## 池水位快照（V5 门禁/调试用）：{kind: [free, busy]}
static func pool_stats() -> Dictionary:
	var out := {}
	for k in POOL_SIZE.keys():
		var busy_n := 0
		for id in _busy.keys():
			if String(_busy[id]) == k:
				busy_n += 1
		out[k] = [_free[k].size(), busy_n]
	return out


## 调试：每个池空闲节点的父节点名（定位池节点被挪用/丢失问题）
static func pool_debug_parents() -> Dictionary:
	var out := {}
	for k in _free.keys():
		var ps := []
		for n in _free[k]:
			if not is_instance_valid(n):
				ps.append("<invalid>")
			elif (n as Node).get_parent() != null:
				ps.append(String((n as Node).get_parent().name))
			else:
				ps.append("<orphan>")
		out[k] = ps
	return out


static func _make_glow_sprite() -> Sprite2D:
	var sp := Sprite2D.new()
	sp.texture = _glow_texture()
	sp.material = _additive_mat()
	sp.visible = false
	_pool_root.add_child(sp)
	return sp


static func _make_label() -> Label:
	var lbl := Label.new()
	lbl.visible = false
	lbl.z_index = 10
	_pool_root.add_child(lbl)
	return lbl


static func _make_ring() -> Ring:
	var r := Ring.new()
	r.visible = false
	r.set_process(false)
	_pool_root.add_child(r)
	return r


static func _particles_base(amount: int, lifetime: float) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.one_shot = true
	p.emitting = false
	p.visible = false
	return p


static func _make_spark() -> CPUParticles2D:
	var p := _particles_base(8, 0.3)
	p.explosiveness = 0.9
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 6.0
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.initial_velocity_min = 80.0
	p.initial_velocity_max = 220.0
	p.gravity = Vector2(0, 150)
	p.scale_amount_min = 2.0
	p.scale_amount_max = 4.0
	p.z_index = 6
	_pool_root.add_child(p)
	return p


static func _make_boom() -> CPUParticles2D:
	var p := _particles_base(14, 0.5)
	p.explosiveness = 0.85
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 10.0
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.initial_velocity_min = 150.0
	p.initial_velocity_max = 380.0
	p.gravity = Vector2(0, 200)
	p.damping_min = 60.0
	p.damping_max = 120.0
	p.scale_amount_min = 2.5
	p.scale_amount_max = 5.5
	p.z_index = 6
	_pool_root.add_child(p)
	return p


static func _make_rise() -> CPUParticles2D:
	var p := _particles_base(30, 0.9)
	p.explosiveness = 0.7
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 25.0
	p.direction = Vector2(0, -1)
	p.spread = 25.0
	p.initial_velocity_min = 120.0
	p.initial_velocity_max = 260.0
	p.gravity = Vector2(0, -80)
	p.scale_amount_min = 3.0
	p.scale_amount_max = 6.0
	p.color = Color(1.0, 0.9, 0.5, 0.85)
	p.z_index = 6
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	_pool_root.add_child(p)
	return p


# ---------------- 特效入口（池化） ----------------
static func glow_ring(parent: Node, pos: Vector2, ring_radius: float, color: Color, duration: float = 0.45, z: int = 5) -> void:
	var sp := _acquire("glow", parent.get_tree()) as Sprite2D
	if sp == null:
		return
	sp.texture = _glow_ring_texture()
	_glow_oneshot(sp, pos, color, z, false, (ring_radius / 0.62 * 2.0) / 256.0, 1.15, duration)


static func glow(parent: Node, pos: Vector2, size: float, color: Color, duration: float = 0.35, z: int = 5, always: bool = false) -> void:
	if not _throttle_ok("glow"):
		return
	var sp := _acquire("glow", parent.get_tree()) as Sprite2D
	if sp == null:
		return
	sp.texture = _glow_texture()
	_glow_oneshot(sp, pos, color, z, always, size / 128.0, 1.35, duration)


static func _glow_oneshot(sp: Sprite2D, pos: Vector2, color: Color, z: int, always: bool,
		s0: float, s1_mult: float, duration: float) -> void:
	sp.modulate = Color(color.r, color.g, color.b, color.a)
	sp.global_position = pos
	sp.z_index = z
	sp.process_mode = Node.PROCESS_MODE_ALWAYS if always else Node.PROCESS_MODE_INHERIT
	sp.scale = Vector2.ONE * s0
	sp.visible = true
	var tw := sp.create_tween()
	sp.set_meta("tw", tw)
	tw.set_parallel(true)
	tw.tween_property(sp, "scale", Vector2.ONE * s0 * s1_mult, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(sp, "modulate:a", 0.0, duration)
	tw.chain().tween_callback(func() -> void: _release(sp))


static func glow_aura(parent: Node, pos: Vector2, size: float, color: Color, z: int = 4) -> Sprite2D:
	# 持续呼吸辉光（收编进 GlowSprite 池）：调用方照旧可 queue_free，
	# 池在 acquire 时以 is_instance_valid 校验并淘汰失效节点
	var sp := _acquire("glow", parent.get_tree()) as Sprite2D
	if sp == null:
		sp = Sprite2D.new()
		sp.texture = _glow_texture()
		sp.material = _additive_mat()
		parent.add_child(sp)
	else:
		_busy.erase(sp.get_instance_id())  # 长期占用，不走 oneshot 回收
		_free["glow"].erase(sp)
	sp.texture = _glow_texture()
	sp.modulate = Color(color.r, color.g, color.b, color.a)
	sp.global_position = pos
	sp.z_index = z
	sp.visible = true
	_breathe(sp, size)
	return sp


static func attach_aura(node: Node2D, size: float, color: Color, z: int = 3) -> Sprite2D:
	# breathing glow as a child at local origin (follows the node); freed with it
	var sp := Sprite2D.new()
	sp.texture = _glow_texture()
	sp.material = _additive_mat()
	sp.modulate = Color(color.r, color.g, color.b, color.a)
	sp.z_index = z
	_breathe(sp, size)
	node.add_child(sp)
	return sp


static func _breathe(sp: Sprite2D, size: float) -> void:
	var s := size / 128.0
	sp.scale = Vector2.ONE * s
	var tw := sp.create_tween().set_loops()
	sp.set_meta("tw", tw)
	tw.tween_property(sp, "scale", Vector2.ONE * s * 1.12, 0.8).set_trans(Tween.TRANS_SINE)
	tw.tween_property(sp, "scale", Vector2.ONE * s * 0.94, 0.8).set_trans(Tween.TRANS_SINE)

class Ring extends Node2D:
	var radius := 60.0
	var max_radius := 120.0
	var t := 0.0
	var duration := 0.35
	var tint := Color(1, 0.8, 0.4)
	var width := 8.0
	var active := false  # 池中待命时为 false，_process 直接返回（防待命节点自杀）
	var on_finish: Callable = Callable()  # 池化时由 FX 注入回收回调
	func _process(d: float) -> void:
		if not active:
			return
		t += d
		queue_redraw()
		if t >= duration:
			active = false
			if on_finish.is_valid():
				on_finish.call(self)
			else:
				queue_free()
	func _draw() -> void:
		var k := clampf(t / duration, 0.0, 1.0)
		var r := lerpf(radius * 0.3, max_radius, k)
		var a := 1.0 - k
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, Color(tint.r, tint.g, tint.b, a), width * (1.0 - k * 0.5))


static func explosion(parent: Node2D, pos: Vector2, radius: float, tint: Color) -> void:
	Sfx.play("explosion")
	# soft glow core (the star of the show: smooth, no grain)
	glow(parent, pos, radius * 2.6, Color(tint.r, tint.g, tint.b, 0.9), 0.35, 6)
	glow(parent, pos, radius * 1.4, Color(1, 1, 1, 0.85), 0.22, 7)
	# expanding ring（池化）
	var ring := _acquire("ring", parent.get_tree()) as Ring
	if ring != null:
		ring.radius = radius * 0.5
		ring.max_radius = radius * 1.15
		ring.tint = tint
		ring.duration = 0.35
		ring.t = 0.0
		ring.global_position = pos
		ring.z_index = 6
		ring.visible = true
		ring.on_finish = func(r: Node) -> void: _release(r)
		ring.active = true
		ring.set_process(true)
	# spark particles（池化）
	var sparks := _acquire("boom", parent.get_tree()) as CPUParticles2D
	if sparks != null:
		sparks.emission_sphere_radius = radius * 0.3
		sparks.color = tint
		sparks.global_position = pos
		sparks.visible = true
		sparks.restart()
		_release_later(parent.get_tree(), sparks, 0.7)
	# small screen shake
	shake(parent, 6.0)


static func hit_spark(parent: Node2D, pos: Vector2, tint: Color = Color(1, 0.9, 0.6)) -> void:
	Sfx.play("hit")
	# soft glow flash on every hit + a few sparks
	glow(parent, pos, 56.0, Color(tint.r, tint.g, tint.b, 0.75), 0.22, 6)
	if not _throttle_ok("spark"):
		return
	var sparks := _acquire("spark", parent.get_tree()) as CPUParticles2D
	if sparks == null:
		return
	sparks.color = tint
	sparks.global_position = pos
	sparks.visible = true
	sparks.restart()
	_release_later(parent.get_tree(), sparks, 0.45)


static func damage_number(parent: Node2D, pos: Vector2, amount: float, is_crit: bool) -> void:
	if not _throttle_ok("label"):
		return
	var lbl := _acquire("label", parent.get_tree()) as Label
	if lbl == null:
		return
	lbl.text = str(int(amount))
	if is_crit:
		lbl.add_theme_font_size_override("font_size", 34)
		lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
		lbl.add_theme_color_override("font_outline_color", Color(0.4, 0.2, 0))
		lbl.add_theme_constant_override("outline_size", 6)
	else:
		lbl.add_theme_font_size_override("font_size", 20)
		lbl.add_theme_color_override("font_color", Color.WHITE)
		lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		lbl.add_theme_constant_override("outline_size", 4)
	lbl.modulate.a = 1.0
	lbl.global_position = pos + Vector2(randf_range(-10, 10), -20)
	lbl.visible = true
	var tw := lbl.create_tween()
	lbl.set_meta("tw", tw)
	tw.set_parallel(true)
	tw.tween_property(lbl, "global_position:y", lbl.global_position.y - 50.0, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.6).set_delay(0.2)
	tw.chain().tween_callback(func() -> void: _release(lbl))


# ---- shake 单 Tween 合并（04 §3.3）：并发请求取 max，复用同一 Tween ----
static var _shake_tw: Tween = null
static var _shake_str := 0.0
static var _shake_base := Vector2.ZERO
static var _shake_cam: Camera2D = null


static func shake(parent: Node, strength: float = 8.0) -> void:
	var cam := parent.get_tree().get_first_node_in_group("camera") as Camera2D
	if cam == null:
		# fallback: find Camera2D under player
		var p := parent.get_tree().get_first_node_in_group("player")
		if p != null:
			cam = p.get_node_or_null("Camera2D") as Camera2D
	if cam == null:
		return
	if _shake_tw != null and _shake_tw.is_valid() and cam == _shake_cam:
		if strength <= _shake_str:
			return  # 已有更强震屏在跑，合并丢弃
		_shake_tw.kill()
	else:
		_shake_base = cam.offset
	_shake_cam = cam
	_shake_str = strength
	var tw := cam.create_tween()
	_shake_tw = tw
	var base := _shake_base
	for i in range(3):
		var off := Vector2(randf_range(-strength, strength), randf_range(-strength, strength))
		tw.tween_property(cam, "offset", base + off, 0.04)
	tw.tween_property(cam, "offset", base, 0.06)
	tw.tween_callback(func() -> void:
		if _shake_tw == tw:
			_shake_tw = null
			_shake_str = 0.0)


# ---- hitstop 双通道（v0.8 A1 / 05 §7.2 / 04 §3.1）----
# 通道A 打击：暴击/技能命中微顿（time_scale 0.35），全局冷却 0.15s，演出期间静默。
# 通道B 演出（cine=true）：合成/Boss 转换/精英击杀等独占全屏 time_scale 0.05。
static var _hs_gen := 0
static var _hs_cine_until_ms := 0
static var _hs_a_last_ms := 0


static func hitstop(tree: SceneTree, duration: float = 0.03, cine: bool = false) -> void:
	var now := Time.get_ticks_msec()
	if cine:
		_hs_gen += 1
		var gen := _hs_gen
		_hs_cine_until_ms = now + int(duration * 1000.0)
		Engine.time_scale = 0.05
		await tree.create_timer(duration, true, false, true).timeout
		if gen == _hs_gen:
			Engine.time_scale = 1.0
		return
	if now < _hs_cine_until_ms:
		return  # 演出独占期间，打击通道静默
	if now - _hs_a_last_ms < 150:
		return  # 0.15s 全局冷却：窗口内重复触发直接丢弃
	_hs_a_last_ms = now
	_hs_gen += 1
	var agen := _hs_gen
	Engine.time_scale = 0.35
	await tree.create_timer(duration, true, false, true).timeout
	if agen == _hs_gen and Time.get_ticks_msec() >= _hs_cine_until_ms:
		Engine.time_scale = 1.0


static func levelup_beam(parent: Node2D, pos: Vector2) -> void:
	Sfx.play("levelup")
	# light pillar (runs even while paused for upgrade selection)
	glow(parent, pos, 170.0, Color(1.0, 0.9, 0.5, 0.8), 0.9, 5, true)
	var beam := _acquire("glow", parent.get_tree()) as Sprite2D
	if beam != null:
		beam.texture = load("res://assets/sprites/fx/fx_levelup.png") as Texture2D
		beam.modulate = Color(1.0, 0.95, 0.7, 0.9)
		beam.material = _additive_mat()
		beam.global_position = pos
		beam.z_index = 6
		beam.process_mode = Node.PROCESS_MODE_ALWAYS
		beam.scale = Vector2.ONE
		beam.visible = true
		var tw := beam.create_tween()
		beam.set_meta("tw", tw)
		tw.set_parallel(true)
		tw.tween_property(beam, "scale", Vector2(1.4, 2.0), 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(beam, "modulate:a", 0.0, 0.8).set_delay(0.3)
		tw.chain().tween_callback(func() -> void: _release(beam))
	# rising particles（池化）
	var rise := _acquire("rise", parent.get_tree()) as CPUParticles2D
	if rise != null:
		rise.global_position = pos
		rise.visible = true
		rise.restart()
		_release_later(parent.get_tree(), rise, 1.1)
