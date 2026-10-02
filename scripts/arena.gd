extends StaticBody2D
## Arena v0.7: themed floor (3 variants, hash-picked + per-tile brightness jitter),
## depth walls (lit top edge + dark facade), torch flames with flicker glow,
## ground decals, upgraded pillars, wall-base vignette. Collision unchanged.

const W := 1600.0
const H := 1200.0
const WALL_T := 48.0
const TILE := 48.0
const PILLARS := [Vector2(480, 380), Vector2(1120, 380), Vector2(480, 820), Vector2(1120, 820)]
const PILLAR_R := 42.0
const SPAWN_SAFE_R := 220.0  # 出生点（中心）不撒装饰

const DECAL_NAMES := ["cracks", "rubble", "bones", "blood", "moss"]

var theme := "corridor"
var _floor_texs: Array = []
var _wall_tex: Texture2D
var _side_tex: Texture2D
var _hazard_tex: Texture2D
var _pillar_tex: Texture2D
var _vignette_t: Texture2D  # 上墙：上暗下透
var _vignette_b: Texture2D  # 下墙：上透下暗
var _vignette_l: Texture2D  # 左墙：左暗右透
var _vignette_r: Texture2D  # 右墙：左透右暗
var _decal_texs: Array = []
var _hazard_spots: Array = []
var _floor_pick: PackedByteArray = PackedByteArray()
var _floor_shade: PackedFloat32Array = PackedFloat32Array()
var _decal_spots: Array = []  # {pos, tex, rot, scl}
var _torches: Array = []  # {flame: Sprite2D, glow: Sprite2D, bracket: Sprite2D, phase: float, base: float}
var _torch_wall_spots: Array = []  # 火把附近位置（hazard 避让用）
var _rune_nodes: Array = []
var _time := 0.0
# v0.8 B4 A5 烘焙：静态层（地面/墙/柱/decal/符文）离屏渲染成单张纹理，
# _draw 从 ~950 条绘制命令降为 0（烘焙图由子 Sprite 显示）；未就绪/失败时回退逐砖绘制
var _bake_cache := {}  # theme -> ImageTexture
var _baked_sprite: Sprite2D = null
var _baked_applied := false
var _baking := false
var _is_baker := false


func _ready() -> void:
	collision_layer = 4
	collision_mask = 0
	_add_box(Vector2(W * 0.5, -WALL_T * 0.5), Vector2(W + WALL_T * 2.0, WALL_T))
	_add_box(Vector2(W * 0.5, H + WALL_T * 0.5), Vector2(W + WALL_T * 2.0, WALL_T))
	_add_box(Vector2(-WALL_T * 0.5, H * 0.5), Vector2(WALL_T, H))
	_add_box(Vector2(W + WALL_T * 0.5, H * 0.5), Vector2(WALL_T, H))
	for p in PILLARS:
		var cs := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = PILLAR_R
		cs.shape = circle
		cs.position = p
		add_child(cs)
	# 墙根暗角渐变（程序化，一次生成 4 方向）
	_vignette_t = _make_vignette(Vector2(0.5, 0.0), Vector2(0.5, 1.0), false)
	_vignette_b = _make_vignette(Vector2(0.5, 0.0), Vector2(0.5, 1.0), true)
	_vignette_l = _make_vignette(Vector2(0.0, 0.5), Vector2(1.0, 0.5), false)
	_vignette_r = _make_vignette(Vector2(0.0, 0.5), Vector2(1.0, 0.5), true)
	set_theme(theme)


## 暗角渐变：reverse=false 时起点暗→终点透
func _make_vignette(from: Vector2, to: Vector2, reverse: bool) -> GradientTexture2D:
	var grad := Gradient.new()
	var c0 := Color(0, 0, 0, 0.42)
	var c1 := Color(0, 0, 0, 0.0)
	grad.set_color(0, c1 if reverse else c0)
	grad.set_color(1, c0 if reverse else c1)
	var gtex := GradientTexture2D.new()
	gtex.gradient = grad
	gtex.fill = GradientTexture2D.FILL_LINEAR
	gtex.fill_from = from
	gtex.fill_to = to
	gtex.width = 8
	gtex.height = 64
	return gtex


func _add_box(pos: Vector2, size: Vector2) -> void:
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	cs.shape = rect
	cs.position = pos
	add_child(cs)


class WallsVisual extends Node2D:
	# L4 房间墙体视觉（v0.8.6 主题化）：逐格主题墙砖 + 亮度抖动；
	# 南侧邻地面 → 立面（side 贴图）+ 底边压暗 + 向地面投 10px 影；
	# 北侧邻地面 → 顶部高光。全部命令在一个 canvas item 内（缓存绘制）。
	var rects: Array = []  # grid 缺失时的兜底（合并矩形）
	var grid := PackedByteArray()
	var gw := 32
	var gh := 24
	var cell := 50.0
	var wall_tex: Texture2D = null
	var side_tex: Texture2D = null
	var theme := "corridor"

	func _is_wall(x: int, y: int) -> bool:
		if x < 0 or y < 0 or x >= gw or y >= gh:
			return true
		return grid[y * gw + x] == 1

	func _draw() -> void:
		if grid.is_empty() or wall_tex == null:
			# 兜底：旧平色矩形
			for r in rects:
				var p: Vector2 = r["pos"]
				var s: Vector2 = r["size"]
				var top := Rect2(p - s * 0.5, s)
				draw_rect(top, Color(0.16, 0.14, 0.18, 1.0))
				draw_rect(Rect2(top.position, Vector2(s.x, 6.0)), Color(0.32, 0.28, 0.34, 1.0))
			return
		var side: Texture2D = side_tex if side_tex != null else wall_tex
		for y in range(gh):
			for x in range(gw):
				if grid[y * gw + x] != 1:
					continue
				var rect := Rect2(float(x) * cell, float(y) * cell, cell, cell)
				var h := hash("%s:%d:%d" % [theme, x, y])
				var shade := 0.88 + float(absi(h) % 100) / 100.0 * 0.20
				# 主体：side 砖纹（wall 贴图是横向光带条纹，只能当顶盖用）
				draw_texture_rect(side, rect, false, Color(shade, shade, shade))
				if not _is_wall(x, y - 1):
					# 北侧顶盖：wall 光带压进顶部 12px 成受光斜面 + 高光线
					draw_texture_rect(wall_tex, Rect2(rect.position, Vector2(cell, 12.0)),
						false, Color(shade, shade, shade))
					draw_rect(Rect2(rect.position, Vector2(cell, 2.0)), Color(1, 1, 1, 0.25))
				if not _is_wall(x, y + 1):
					# 南侧立面：下半压暗 + 底边线 + 地面投影
					draw_rect(Rect2(rect.position + Vector2(0, cell * 0.55),
						Vector2(cell, cell * 0.45)), Color(0, 0, 0, 0.18))
					draw_rect(Rect2(rect.position + Vector2(0, cell - 3.0), Vector2(cell, 3.0)),
						Color(0, 0, 0, 0.45))
					draw_rect(Rect2(rect.position + Vector2(0, cell), Vector2(cell, 10.0)),
						Color(0, 0, 0, 0.28))


var _room_wall_shapes: Array = []
var _room_walls_visual: WallsVisual = null


## L4：按房间生成结果建墙（碰撞挂本 StaticBody2D，layer 4 与边框一致）
func build_room_walls(rects: Array, p_grid: PackedByteArray = PackedByteArray()) -> void:
	clear_room_walls()
	var visual_rects: Array = []
	for r in rects:
		var cs := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = r["size"]
		cs.shape = shape
		cs.position = r["pos"]
		add_child(cs)
		_room_wall_shapes.append(cs)
		visual_rects.append(r)
	_room_walls_visual = WallsVisual.new()
	_room_walls_visual.rects = visual_rects
	_room_walls_visual.grid = p_grid
	_room_walls_visual.wall_tex = _wall_tex
	_room_walls_visual.side_tex = _side_tex
	_room_walls_visual.theme = theme
	_room_walls_visual.z_index = 2
	add_child(_room_walls_visual)


func clear_room_walls() -> void:
	for cs in _room_wall_shapes:
		if is_instance_valid(cs):
			cs.queue_free()
	_room_wall_shapes.clear()
	if is_instance_valid(_room_walls_visual):
		_room_walls_visual.queue_free()
		_room_walls_visual = null


func set_theme(t: String) -> void:
	theme = t
	_baked_applied = false
	if _baked_sprite != null:
		_baked_sprite.visible = false
	_floor_texs.clear()
	for v in ["a", "b", "c"]:
		var tex := load("res://assets/tiles/%s/tile_%s_floor_%s.png" % [t, t, v]) as Texture2D
		if tex == null:
			tex = load("res://assets/tiles/%s/tile_%s_floor.png" % [t, t]) as Texture2D
		_floor_texs.append(tex)
	_wall_tex = load("res://assets/tiles/%s/tile_%s_wall.png" % [t, t]) as Texture2D
	_side_tex = load("res://assets/tiles/%s/tile_%s_side.png" % [t, t]) as Texture2D
	if _side_tex == null:
		_side_tex = _wall_tex
	_hazard_tex = _make_hazard_texture()
	_pillar_tex = load("res://assets/tiles/decor/pillar.png") as Texture2D
	_decal_texs.clear()
	for dn in DECAL_NAMES:
		_decal_texs.append(load("res://assets/tiles/decals/decal_%s.png" % dn) as Texture2D)
	# 每砖变体 + 亮度抖动（确定性 hash）
	var nx := int(W / TILE) + 1
	var ny := int(H / TILE) + 1
	_floor_pick.resize(nx * ny)
	_floor_shade.resize(nx * ny)
	for ix in range(nx):
		for iy in range(ny):
			var h := hash("%s:%d:%d" % [t, ix, iy])
			_floor_pick[ix * ny + iy] = int(abs(h) % 3)
			_floor_shade[ix * ny + iy] = 0.90 + float(abs(h) % 100) / 100.0 * 0.18
	# hazard 散点：远离墙边（200px）和火把位置
	_torch_wall_spots.clear()
	for x in [200.0, 600.0, 1000.0, 1400.0]:
		_torch_wall_spots.append(Vector2(x, 60.0))
		_torch_wall_spots.append(Vector2(x, H - 60.0))
	for y in [300.0, 700.0, 1100.0]:
		_torch_wall_spots.append(Vector2(60.0, y))
		_torch_wall_spots.append(Vector2(W - 60.0, y))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(t)
	_hazard_spots.clear()
	var htries := 0
	while _hazard_spots.size() < 10 and htries < 200:
		htries += 1
		var hpos := Vector2(
			rng.randf_range(200.0, W - 200.0),
			rng.randf_range(200.0, H - 200.0))
		var hbad := false
		for tsp in _torch_wall_spots:
			if hpos.distance_to(tsp) < 120.0:
				hbad = true
				break
		if hbad:
			continue
		_hazard_spots.append(hpos)
	# 装饰散点：避开出生点与柱子
	_decal_spots.clear()
	var drng := RandomNumberGenerator.new()
	drng.seed = hash("decal:" + t)
	var center := Vector2(W * 0.5, H * 0.5)
	var tries := 0
	while _decal_spots.size() < 16 and tries < 200:
		tries += 1
		var pos := Vector2(drng.randf_range(90.0, W - 90.0), drng.randf_range(90.0, H - 90.0))
		if pos.distance_to(center) < SPAWN_SAFE_R:
			continue
		var bad := false
		for p in PILLARS:
			if pos.distance_to(p) < PILLAR_R + 50.0:
				bad = true
				break
		if bad:
			continue
		_decal_spots.append({
			"pos": pos,
			"tex": drng.randi_range(0, _decal_texs.size() - 1),
			"rot": drng.randf_range(0.0, TAU),
			"scl": drng.randf_range(0.75, 1.25),
		})
	_build_torches()
	_build_rune_decals(drng, center)
	# v0.8.6：房间内墙跟随主题换砖（build_room_walls 时用的是上一层贴图）
	if _room_walls_visual != null and is_instance_valid(_room_walls_visual):
		_room_walls_visual.wall_tex = _wall_tex
		_room_walls_visual.side_tex = _side_tex
		_room_walls_visual.theme = theme
		_room_walls_visual.queue_redraw()
	queue_redraw()
	if not _is_baker:
		_request_bake()


## ---- A5 烘焙：同脚本实例在离屏 SubViewport 里以相同主题重建（散点全确定性，画面一致） ----
func _request_bake() -> void:
	if _bake_cache.has(theme):
		_apply_bake(_bake_cache[theme])
		return
	if _baking or not is_inside_tree():
		return
	_baking = true
	var bake_theme := theme
	var vp := SubViewport.new()
	vp.size = Vector2i(int(W + WALL_T * 2.0), int(H + WALL_T * 2.0))
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.world_2d = World2D.new()
	add_child(vp)
	var baker: StaticBody2D = get_script().new()
	baker.set("_is_baker", true)
	baker.set("theme", bake_theme)
	baker.position = Vector2(WALL_T, WALL_T)
	vp.add_child(baker)
	# baker 的火焰/光晕是动态层，不入烘焙（本体的火把照常燃）
	for tc in baker.get("_torches"):
		(tc["flame"] as CanvasItem).visible = false
		(tc["glow"] as CanvasItem).visible = false
	for i in range(3):
		await get_tree().process_frame
		if not is_instance_valid(self):
			return
		if not is_instance_valid(vp):
			_baking = false
			return
	var img := vp.get_texture().get_image()
	vp.queue_free()
	_baking = false
	# 校验：尺寸正确且中心不透明（headless 哑渲染会给空图 → 放弃烘焙保持逐砖）
	if img == null or img.get_width() != vp.size.x or img.get_height() != vp.size.y:
		return
	if img.get_pixel(vp.size.x / 2, vp.size.y / 2).a < 0.5:
		return
	var tex := ImageTexture.create_from_image(img)
	_bake_cache[bake_theme] = tex
	if theme == bake_theme:
		_apply_bake(tex)


func _apply_bake(tex: ImageTexture) -> void:
	if _baked_sprite == null:
		_baked_sprite = Sprite2D.new()
		_baked_sprite.centered = false
		_baked_sprite.z_index = 0
		add_child(_baked_sprite)
	_baked_sprite.texture = tex
	_baked_sprite.position = Vector2(-WALL_T, -WALL_T)
	_baked_sprite.visible = true
	_baked_applied = true
	# 符文已烘进静态图，隐藏实时符文节点防 ADD 双绘
	for n in _rune_nodes:
		if is_instance_valid(n):
			(n as CanvasItem).visible = false
	queue_redraw()


## 发光符文：黑底 ADD 混合，必须用 Sprite2D（_draw 里换不了混合模式）
func _build_rune_decals(drng: RandomNumberGenerator, center: Vector2) -> void:
	for n in _rune_nodes:
		(n as Node).queue_free()
	_rune_nodes.clear()
	var rune_tex := load("res://assets/tiles/decals/decal_rune.png") as Texture2D
	if rune_tex == null:
		return
	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	var tries := 0
	var placed := 0
	while placed < 3 and tries < 60:
		tries += 1
		var pos := Vector2(drng.randf_range(140.0, W - 140.0), drng.randf_range(140.0, H - 140.0))
		if pos.distance_to(center) < SPAWN_SAFE_R:
			continue
		var bad := false
		for p in PILLARS:
			if pos.distance_to(p) < PILLAR_R + 70.0:
				bad = true
				break
		if bad:
			continue
		var sp := Sprite2D.new()
		sp.texture = rune_tex
		sp.material = add_mat
		sp.modulate = Color(0.75, 0.6, 1.0, 0.5)
		sp.position = pos
		sp.rotation = drng.randf_range(0.0, TAU)
		sp.scale = Vector2.ONE * drng.randf_range(0.9, 1.3)
		sp.z_index = 1
		add_child(sp)
		_rune_nodes.append(sp)
		placed += 1


func _build_torches() -> void:
	for tc in _torches:
		(tc["flame"] as Node).queue_free()
		(tc["glow"] as Node).queue_free()
		(tc["bracket"] as Node).queue_free()
	_torches.clear()
	var flame_tex := load("res://assets/tiles/decor/flame.png") as Texture2D
	if flame_tex == null:
		return
	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	var spots: Array = []
	for x in [200.0, 600.0, 1000.0, 1400.0]:
		spots.append(Vector2(x, -WALL_T * 0.5))
		spots.append(Vector2(x, H + WALL_T * 0.5))
	for y in [300.0, 700.0, 1100.0]:
		spots.append(Vector2(-WALL_T * 0.5, y))
		spots.append(Vector2(W + WALL_T * 0.5, y))
	var frng := RandomNumberGenerator.new()
	frng.seed = hash("torch:" + theme)
	# 火把托架贴图：程序化生成（深色金属杯）
	var bracket_tex := _make_bracket_texture()
	for sp in spots:
		var is_top: bool = sp.y < 0.0
		var is_bottom: bool = sp.y > H
		var is_left: bool = sp.x < 0.0
		# 火焰：从墙面稍向内偏移，避免被墙体压住
		var flame := Sprite2D.new()
		flame.texture = flame_tex
		flame.material = add_mat
		var fpos: Vector2 = sp + Vector2(0, 6)
		if is_top:
			fpos.y += 10.0  # 顶墙火把往下挪，进可视区
		elif is_bottom:
			fpos.y -= 10.0
		elif is_left:
			fpos.x += 10.0
		else:
			fpos.x -= 10.0
		flame.position = fpos
		flame.scale = Vector2.ONE * 0.75  # 火焰更清晰
		flame.z_index = 4
		add_child(flame)
		# 托架：在火焰下方
		var bracket := Sprite2D.new()
		bracket.texture = bracket_tex
		bracket.position = fpos + Vector2(0, 22)
		bracket.z_index = 3
		add_child(bracket)
		# 光晕：收小，不再淹没火焰
		var glow := Sprite2D.new()
		glow.texture = FX._glow_texture()
		glow.material = add_mat
		glow.modulate = Color(1.0, 0.55, 0.22, 0.30)
		glow.position = fpos + Vector2(0, 4)
		glow.scale = Vector2.ONE * (90.0 / 128.0)
		glow.z_index = 2
		add_child(glow)
		_torches.append({
			"flame": flame, "glow": glow, "bracket": bracket,
			"phase": frng.randf_range(0.0, TAU),
			"base": frng.randf_range(0.9, 1.1),
		})


## Hazard：焦黑裂纹（程序化 48x48，带透明边缘）
func _make_hazard_texture() -> Texture2D:
	var img := Image.create(48, 48, false, Image.FORMAT_RGBA8)
	var hrng := RandomNumberGenerator.new()
	hrng.seed = 12345
	# 中心焦黑，向外渐隐
	for y in range(48):
		for x in range(48):
			var dx := (x - 24.0) / 24.0
			var dy := (y - 24.0) / 24.0
			var d := sqrt(dx * dx + dy * dy)
			if d > 1.0:
				continue
			# 不规则边缘
			var edge := 0.75 + 0.25 * hrng.randf()
			if d > edge:
				continue
			var alpha := (1.0 - d) * 0.85
			# 焦黑带暗红
			var r := 0.25 + 0.15 * hrng.randf()
			var g := 0.08 + 0.05 * hrng.randf()
			var b := 0.06 + 0.04 * hrng.randf()
			img.set_pixel(x, y, Color(r, g, b, alpha))
	# 裂纹：几条暗线
	for i in range(5):
		var ang := hrng.randf_range(0.0, TAU)
		for s in range(6, 22):
			var cx := int(24 + cos(ang) * s + hrng.randf_range(-1.5, 1.5))
			var cy := int(24 + sin(ang) * s + hrng.randf_range(-1.5, 1.5))
			if cx >= 0 and cx < 48 and cy >= 0 and cy < 48:
				img.set_pixel(cx, cy, Color(0.1, 0.05, 0.05, 0.9))
	return ImageTexture.create_from_image(img)


## 火把托架：深色金属杯（程序化 32x32）
func _make_bracket_texture() -> Texture2D:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	# 杯体：梯形深灰
	for y in range(10, 26):
		var w := int(6 + (y - 10) * 0.8)  # 上窄下宽
		for x in range(16 - w / 2, 16 + w / 2):
			if x >= 0 and x < 32:
				var shade: float = 0.25 + 0.1 * (1.0 - abs(x - 16) / 12.0)
				img.set_pixel(x, y, Color(shade, shade, shade + 0.05, 1.0))
	# 杯口高光
	for x in range(10, 22):
		img.set_pixel(x, 10, Color(0.45, 0.45, 0.5, 1.0))
	# 支架杆
	for y in range(26, 32):
		for x in range(14, 18):
			img.set_pixel(x, y, Color(0.2, 0.2, 0.22, 1.0))
	return ImageTexture.create_from_image(img)


func _process(delta: float) -> void:
	_time += delta
	for tc in _torches:
		var flame := tc["flame"] as Sprite2D
		var glow := tc["glow"] as Sprite2D
		if not is_instance_valid(flame):
			continue
		var ph: float = tc["phase"]
		var base: float = tc["base"]
		var f := 0.86 + 0.14 * sin(_time * 11.0 + ph) * sin(_time * 5.3 + ph * 1.7)
		flame.scale = Vector2.ONE * 0.75 * base * (0.92 + 0.10 * sin(_time * 13.0 + ph))
		glow.modulate.a = 0.30 * f


func _draw() -> void:
	if _baked_applied:
		return  # 静态层已烘焙为单张纹理（_baked_sprite 显示），本层零绘制命令
	if _floor_texs.is_empty() or _floor_texs[0] == null:
		return
	var nx := int(W / TILE) + 1
	var ny := int(H / TILE) + 1
	# 地面：3 变体 hash 拼 + 每砖亮度抖动
	for ix in range(nx):
		for iy in range(ny):
			var vi := int(_floor_pick[ix * ny + iy])
			var sh := _floor_shade[ix * ny + iy]
			var tex: Texture2D = _floor_texs[vi]
			if tex == null:
				tex = _floor_texs[0]
			draw_texture_rect(tex, Rect2(ix * TILE, iy * TILE, TILE, TILE), false,
				Color(sh, sh, sh))
	# 地面装饰 decal
	for d in _decal_spots:
		var dtex: Texture2D = _decal_texs[int(d["tex"])]
		if dtex == null:
			continue
		var sz := dtex.get_size()
		draw_set_transform(d["pos"], float(d["rot"]), Vector2.ONE * float(d["scl"]))
		draw_texture(dtex, -sz * 0.5, Color(1, 1, 1, 0.9))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# hazard 点缀
	for s in _hazard_spots:
		draw_texture_rect(_hazard_tex, Rect2(s.x - TILE * 0.5, s.y - TILE * 0.5, TILE, TILE), false)
	# 墙体（先左右、后上下压住转角）
	var my := int(H / TILE) + 1
	for iy in range(my):
		var y := iy * TILE
		draw_texture_rect(_side_tex, Rect2(-WALL_T, y, WALL_T, TILE), false)
		draw_texture_rect(_side_tex, Rect2(W, y, WALL_T, TILE), false)
	for ix in range(nx):
		var x := ix * TILE
		draw_texture_rect(_wall_tex, Rect2(x, -WALL_T, TILE, WALL_T), false)
		draw_texture_rect(_wall_tex, Rect2(x, H, TILE, WALL_T), false)
	# 墙根暗角（内侧 40px 渐隐）
	draw_texture_rect(_vignette_t, Rect2(0, 0, W, 40), false)
	draw_texture_rect(_vignette_b, Rect2(0, H - 40, W, 40), false)
	draw_texture_rect(_vignette_l, Rect2(0, 0, 40, H), false)
	draw_texture_rect(_vignette_r, Rect2(W - 40, 0, 40, H), false)
	# 柱子：椭圆阴影 + 柱体贴图
	for p in PILLARS:
		draw_set_transform(p + Vector2(8, 14), 0.0, Vector2(1.0, 0.55))
		draw_circle(Vector2.ZERO, PILLAR_R + 8.0, Color(0, 0, 0, 0.45))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if _pillar_tex != null:
			var ps := _pillar_tex.get_size()
			var target := 116.0
			var k := target / maxf(ps.x, ps.y)
			draw_texture_rect(_pillar_tex,
				Rect2(p.x - ps.x * k * 0.5, p.y - ps.y * k * 0.5, ps.x * k, ps.y * k), false)
		else:
			draw_circle(p, PILLAR_R, Color(0.20, 0.18, 0.26))
			draw_circle(p, PILLAR_R * 0.72, Color(0.26, 0.23, 0.33))
