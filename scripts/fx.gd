class_name FX
extends RefCounted
## Static combat-juice helpers: explosions, hit sparks, damage numbers,
## screen shake, hitstop, levelup beam, soft glow (refined bloom-like aura).
## Glow uses a smooth radial gradient + additive blend: no grain.
## Particles are CPU-based (web-safe) and kept subtle next to glow.

static var _glow_tex: Texture2D = null
static var _glow_ring_tex: Texture2D = null


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


static func glow_ring(parent: Node, pos: Vector2, ring_radius: float, color: Color, duration: float = 0.45, z: int = 5) -> void:
	# one-shot soft ring flash hugging a radius (e.g. whirlwind blade arc)
	var sp := Sprite2D.new()
	sp.texture = _glow_ring_texture()
	sp.material = _additive_mat()
	sp.modulate = Color(color.r, color.g, color.b, color.a)
	sp.global_position = pos
	sp.z_index = z
	var s := (ring_radius / 0.62 * 2.0) / 256.0
	sp.scale = Vector2.ONE * s
	parent.add_child(sp)
	var tw := sp.create_tween()
	tw.set_parallel(true)
	tw.tween_property(sp, "scale", Vector2.ONE * s * 1.15, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(sp, "modulate:a", 0.0, duration)
	tw.chain().tween_callback(sp.queue_free)


static func glow(parent: Node, pos: Vector2, size: float, color: Color, duration: float = 0.35, z: int = 5, always: bool = false) -> void:
	# one-shot soft glow flash: expands slightly and fades
	var sp := Sprite2D.new()
	sp.texture = _glow_texture()
	sp.material = _additive_mat()
	sp.modulate = Color(color.r, color.g, color.b, color.a)
	sp.global_position = pos
	sp.z_index = z
	if always:
		sp.process_mode = Node.PROCESS_MODE_ALWAYS
	var s := size / 128.0
	sp.scale = Vector2.ONE * s
	parent.add_child(sp)
	var tw := sp.create_tween()
	tw.set_parallel(true)
	tw.tween_property(sp, "scale", Vector2.ONE * s * 1.35, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(sp, "modulate:a", 0.0, duration)
	tw.chain().tween_callback(sp.queue_free)


static func glow_aura(parent: Node, pos: Vector2, size: float, color: Color, z: int = 4) -> Sprite2D:
	# persistent breathing glow; caller must queue_free it
	var sp := Sprite2D.new()
	sp.texture = _glow_texture()
	sp.material = _additive_mat()
	sp.modulate = Color(color.r, color.g, color.b, color.a)
	sp.global_position = pos
	sp.z_index = z
	parent.add_child(sp)
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
	tw.tween_property(sp, "scale", Vector2.ONE * s * 1.12, 0.8).set_trans(Tween.TRANS_SINE)
	tw.tween_property(sp, "scale", Vector2.ONE * s * 0.94, 0.8).set_trans(Tween.TRANS_SINE)

class Ring extends Node2D:
	var radius := 60.0
	var max_radius := 120.0
	var t := 0.0
	var duration := 0.35
	var tint := Color(1, 0.8, 0.4)
	var width := 8.0
	func _process(d: float) -> void:
		t += d
		queue_redraw()
		if t >= duration:
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
	# expanding ring
	var ring := Ring.new()
	ring.radius = radius * 0.5
	ring.max_radius = radius * 1.15
	ring.tint = tint
	ring.global_position = pos
	ring.z_index = 6
	parent.add_child(ring)
	# spark particles (reduced: glow carries the effect now)
	var sparks := CPUParticles2D.new()
	sparks.amount = 14
	sparks.lifetime = 0.5
	sparks.one_shot = true
	sparks.explosiveness = 0.85
	sparks.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	sparks.emission_sphere_radius = radius * 0.3
	sparks.direction = Vector2(0, -1)
	sparks.spread = 180.0
	sparks.initial_velocity_min = 150.0
	sparks.initial_velocity_max = 380.0
	sparks.gravity = Vector2(0, 200)
	sparks.damping_min = 60.0
	sparks.damping_max = 120.0
	sparks.scale_amount_min = 2.5
	sparks.scale_amount_max = 5.5
	sparks.color = tint
	sparks.global_position = pos
	sparks.z_index = 6
	parent.add_child(sparks)
	sparks.emitting = true
	# small screen shake
	shake(parent, 6.0)


static func hit_spark(parent: Node2D, pos: Vector2, tint: Color = Color(1, 0.9, 0.6)) -> void:
	Sfx.play("hit")
	# soft glow flash on every hit + a few sparks
	glow(parent, pos, 56.0, Color(tint.r, tint.g, tint.b, 0.75), 0.22, 6)
	var sparks := CPUParticles2D.new()
	sparks.amount = 8
	sparks.lifetime = 0.3
	sparks.one_shot = true
	sparks.explosiveness = 0.9
	sparks.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	sparks.emission_sphere_radius = 6.0
	sparks.direction = Vector2(0, -1)
	sparks.spread = 180.0
	sparks.initial_velocity_min = 80.0
	sparks.initial_velocity_max = 220.0
	sparks.gravity = Vector2(0, 150)
	sparks.scale_amount_min = 2.0
	sparks.scale_amount_max = 4.0
	sparks.color = tint
	sparks.global_position = pos
	sparks.z_index = 6
	parent.add_child(sparks)
	sparks.emitting = true


static func damage_number(parent: Node2D, pos: Vector2, amount: float, is_crit: bool) -> void:
	var lbl := Label.new()
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
	lbl.global_position = pos + Vector2(randf_range(-10, 10), -20)
	lbl.z_index = 10
	parent.add_child(lbl)
	var tw := lbl.create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "global_position:y", lbl.global_position.y - 50.0, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.6).set_delay(0.2)
	tw.chain().tween_callback(lbl.queue_free)


static func shake(parent: Node, strength: float = 8.0) -> void:
	var cam := parent.get_tree().get_first_node_in_group("camera") as Camera2D
	if cam == null:
		# fallback: find Camera2D under player
		var p := parent.get_tree().get_first_node_in_group("player")
		if p != null:
			cam = p.get_node_or_null("Camera2D") as Camera2D
	if cam == null:
		return
	var tw := cam.create_tween()
	var base := cam.offset
	for i in range(3):
		var off := Vector2(randf_range(-strength, strength), randf_range(-strength, strength))
		tw.tween_property(cam, "offset", base + off, 0.04)
	tw.tween_property(cam, "offset", base, 0.06)


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
	var beam := Sprite2D.new()
	beam.texture = load("res://assets/sprites/fx/fx_levelup.png") as Texture2D
	beam.modulate = Color(1.0, 0.95, 0.7, 0.9)
	beam.material = _additive_mat()
	beam.global_position = pos
	beam.z_index = 6
	beam.process_mode = Node.PROCESS_MODE_ALWAYS
	parent.add_child(beam)
	var tw := beam.create_tween()
	tw.set_parallel(true)
	tw.tween_property(beam, "scale", Vector2(1.4, 2.0), 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(beam, "modulate:a", 0.0, 0.8).set_delay(0.3)
	tw.chain().tween_callback(beam.queue_free)
	# rising particles
	var rise := CPUParticles2D.new()
	rise.amount = 30
	rise.lifetime = 0.9
	rise.one_shot = true
	rise.explosiveness = 0.7
	rise.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	rise.emission_sphere_radius = 25.0
	rise.direction = Vector2(0, -1)
	rise.spread = 25.0
	rise.initial_velocity_min = 120.0
	rise.initial_velocity_max = 260.0
	rise.gravity = Vector2(0, -80)
	rise.scale_amount_min = 3.0
	rise.scale_amount_max = 6.0
	rise.color = Color(1.0, 0.9, 0.5, 0.85)
	rise.global_position = pos
	rise.z_index = 6
	rise.process_mode = Node.PROCESS_MODE_ALWAYS
	parent.add_child(rise)
	rise.emitting = true


static func _additive_mat() -> CanvasItemMaterial:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return m
