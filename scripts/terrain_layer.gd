extends Node2D
## 地形视觉层（v0.8.5）：按 TerrainGen 的格子簇逐格绘制不规则色块 + 主题细节。
## 颜色按地形种类区分；熔岩/虚空带呼吸脉动（10Hz 重绘，其余主题静态）。

var patches: Array = []
var theme := "corridor"
var _time := 0.0
var _pulse_t := 0.0

const CELL := 50.0
const TEX_SPAN := 120.0  # 贴图覆盖 2.4 格的世界跨度（UV 按世界坐标取样，跨格无缝）
const FADE_W := 10.0  # v0.8.15：地形/地板交界柔化宽度（px）
var _textures := {}


func _ready() -> void:
	# v0.8.7：Agnes 地形贴图（draw_polygon 带 UV 采样，需开启纹理重复）
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	for kind in ["rubble", "lava", "ice", "mire", "bramble", "rift"]:
		_textures[kind] = load("res://assets/tiles/terrain/tex_%s.webp" % kind) as Texture2D

const COLORS := {
	"rubble": [Color(0.32, 0.27, 0.22, 0.62), Color(0.55, 0.48, 0.38, 0.80), Color(0.62, 0.55, 0.45, 0.9)],
	"lava": [Color(0.18, 0.05, 0.03, 0.85), Color(1.0, 0.32, 0.05, 0.90), Color(1.0, 0.62, 0.08, 0.95)],
	"ice": [Color(0.55, 0.82, 0.95, 0.40), Color(0.85, 0.97, 1.0, 0.75), Color(1.0, 1.0, 1.0, 0.9)],
	"mire": [Color(0.23, 0.25, 0.11, 0.68), Color(0.45, 0.48, 0.22, 0.80), Color(0.62, 0.66, 0.32, 0.85)],
	"bramble": [Color(0.08, 0.28, 0.12, 0.62), Color(0.25, 0.75, 0.30, 0.85), Color(0.55, 0.95, 0.45, 0.9)],
	"rift": [Color(0.16, 0.05, 0.28, 0.72), Color(0.62, 0.30, 1.0, 0.90), Color(0.85, 0.55, 1.0, 0.95)],
}


func setup(p_patches: Array, p_theme: String) -> void:
	patches = p_patches
	theme = p_theme
	_time = 0.0
	_pulse_t = 0.0
	queue_redraw()


func clear_patches() -> void:
	patches = []
	queue_redraw()


func _process(delta: float) -> void:
	if theme == "forge" or theme == "void":
		_time += delta
		_pulse_t += delta
		if _pulse_t >= 0.1:
			_pulse_t = 0.0
			queue_redraw()


func _rand01(seed_text: String, salt: int) -> float:
	return float(absi(hash(seed_text + ":" + str(salt))) % 1000) / 1000.0


## 旧版圆形色块（v0.8.12 起地砖改用方形格），函数保留以备回滚。
func _blob_points(center: Vector2, cell: Vector2i, kind: String, shrink: float) -> PackedVector2Array:

	var pts := PackedVector2Array()
	var half := CELL * 0.5 - shrink
	var key := "%d:%d:%s" % [cell.x, cell.y, kind]
	for i in range(8):
		var a := TAU * float(i) / 8.0
		var jitter := 0.76 + _rand01(key, i) * 0.48
		var p := center + Vector2(cos(a), sin(a)) * half * jitter
		pts.append(p)
	return pts


func _draw() -> void:
	# 跨 patch 的全地形格集合，用于边界检测
	var all_cells := {}
	for patch in patches:
		for cell_v in patch.get("cells", []):
			all_cells[cell_v] = true
	for patch in patches:
		var kind := String(patch.get("id", "rubble"))
		var cols: Array = COLORS.get(kind, COLORS["rubble"])
		var fill: Color = cols[0]
		var edge: Color = cols[1]
		var accent: Color = cols[2]
		var tex_a := 0.96
		if kind == "lava" or kind == "rift":
			var pulse := 0.5 + 0.5 * sin(_time * 2.6)
			fill.a *= 0.88 + 0.20 * pulse
			accent.a *= 0.70 + 0.30 * pulse
			tex_a *= 0.90 + 0.10 * sin(_time * 2.6)
		var tex: Texture2D = _textures.get(kind, null)
		for cell_v in patch.get("cells", []):
			var cell: Vector2i = cell_v
			var key := "%d:%d:%s" % [cell.x, cell.y, kind]
			# 四边边界检测：邻格无地形则该边需要柔化
			var bN := not all_cells.has(cell + Vector2i(0, -1))
			var bS := not all_cells.has(cell + Vector2i(0, 1))
			var bW := not all_cells.has(cell + Vector2i(-1, 0))
			var bE := not all_cells.has(cell + Vector2i(1, 0))
			# v0.8.12 方形格；v0.8.15 边界边内收 FADE_W，交界处画渐隐条带
			var x0 := float(cell.x) * CELL + (FADE_W if bW else 0.0)
			var y0 := float(cell.y) * CELL + (FADE_W if bN else 0.0)
			var x1 := float(cell.x + 1) * CELL - (FADE_W if bE else 0.0)
			var y1 := float(cell.y + 1) * CELL - (FADE_W if bS else 0.0)
			var rect := Rect2(x0, y0, x1 - x0, y1 - y0)
			draw_rect(rect, fill)
			# Agnes 贴图层：v0.8.15 每格按 hash 旋转/镜像 UV，打破贴图周期重复感
			if tex != null:
				var rot := absi(hash(key + ":rot")) % 4
				var mir := (absi(hash(key + ":mir")) % 2) == 0
				_tex_quad(tex, tex_a, rect, rot, mir)
			# 边界柔化条带（底色 + 贴图双层渐隐）
			var bx := float(cell.x) * CELL
			var by := float(cell.y) * CELL
			if bN:
				_fade_quad(tex, fill, tex_a,
					Vector2(bx, by + FADE_W), Vector2(bx + CELL, by + FADE_W),
					Vector2(bx, by), Vector2(bx + CELL, by))
			if bS:
				_fade_quad(tex, fill, tex_a,
					Vector2(bx + CELL, by + CELL - FADE_W), Vector2(bx, by + CELL - FADE_W),
					Vector2(bx + CELL, by + CELL), Vector2(bx, by + CELL))
			if bW:
				_fade_quad(tex, fill, tex_a,
					Vector2(bx + FADE_W, by + CELL), Vector2(bx + FADE_W, by),
					Vector2(bx, by + CELL), Vector2(bx, by))
			if bE:
				_fade_quad(tex, fill, tex_a,
					Vector2(bx + CELL - FADE_W, by), Vector2(bx + CELL - FADE_W, by + CELL),
					Vector2(bx + CELL, by), Vector2(bx + CELL, by + CELL))
			var center := Vector2((float(cell.x) + 0.5) * CELL, (float(cell.y) + 0.5) * CELL)
			_draw_details(kind, center, cell, edge, accent)


## 贴图四边形：UV 按世界坐标取样；rot 旋转 90°×rot，mir 水平镜像（去重复）
func _tex_quad(tex: Texture2D, a: float, rect: Rect2, rot: int, mir: bool) -> void:
	var p := PackedVector2Array([rect.position,
		rect.position + Vector2(rect.size.x, 0.0), rect.end,
		rect.position + Vector2(0.0, rect.size.y)])
	var cols := PackedColorArray([Color(1, 1, 1, a), Color(1, 1, 1, a),
		Color(1, 1, 1, a), Color(1, 1, 1, a)])
	var buv := [p[0] / TEX_SPAN, p[1] / TEX_SPAN, p[2] / TEX_SPAN, p[3] / TEX_SPAN]
	var uvs := PackedVector2Array()
	for i in range(4):
		uvs.append(buv[(i + rot) % 4])
	if mir:
		uvs = PackedVector2Array([uvs[1], uvs[0], uvs[3], uvs[2]])
	draw_polygon(p, cols, uvs, tex)


## 边界柔化条带：p_i0/p_i1 内侧（alpha 满）→ p_o0/p_o1 外侧（alpha 0）；底色与贴图各一层
func _fade_quad(tex: Texture2D, fill: Color, a: float,
		p_i0: Vector2, p_i1: Vector2, p_o0: Vector2, p_o1: Vector2) -> void:
	var pts := PackedVector2Array([p_i0, p_i1, p_o1, p_o0])
	var fcols := PackedColorArray([
		Color(fill.r, fill.g, fill.b, fill.a), Color(fill.r, fill.g, fill.b, fill.a),
		Color(fill.r, fill.g, fill.b, 0.0), Color(fill.r, fill.g, fill.b, 0.0)])
	draw_polygon(pts, fcols)
	if tex == null:
		return
	var tcols := PackedColorArray([Color(1, 1, 1, a), Color(1, 1, 1, a),
		Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.0)])
	var uvs := PackedVector2Array([p_i0 / TEX_SPAN, p_i1 / TEX_SPAN, p_o1 / TEX_SPAN, p_o0 / TEX_SPAN])
	draw_polygon(pts, tcols, uvs, tex)


func _draw_details(kind: String, center: Vector2, cell: Vector2i, edge: Color, accent: Color) -> void:
	var key := "%d:%d:%s" % [cell.x, cell.y, kind]
	match kind:
		"rubble", "bramble":
			# v0.8.9：贴图本身已有碎石/荆棘细节，不再叠程序化圆点/线条（真机上像贴纸）
			pass
		"lava":
			var inner := Rect2(center - Vector2(9, 9), Vector2(18, 18))
			draw_rect(inner, Color(1.0, 0.45, 0.06, 0.38 + 0.17 * sin(_time * 2.6)))
			var p := center + Vector2(_rand01(key, 10) - 0.5, _rand01(key, 20) - 0.5) * 22.0
			draw_circle(p, 2.2, accent)
		"ice":
			var off := Vector2(_rand01(key, 10) - 0.5, _rand01(key, 20) - 0.5) * 16.0
			var pts := PackedVector2Array()
			for s in range(4):
				pts.append(center + off + Vector2(-16.0 + 10.0 * float(s),
					(_rand01(key, 30 + s) - 0.5) * 12.0 + 8.0))
			draw_polyline(pts, Color(accent, 0.30), 1.5, true)
		"mire":
			var p := center + Vector2(_rand01(key, 10) - 0.5, _rand01(key, 20) - 0.5) * 28.0
			draw_arc(p, 3.0 + _rand01(key, 30) * 3.5, 0.0, TAU, 12, Color(accent, 0.30), 1.5, true)
		"rift":
			var pulse := 0.5 + 0.5 * sin(_time * 2.6 + float(cell.x + cell.y))
			draw_arc(center, 8.0 + 5.0 * pulse, 0.0, TAU, 20, accent, 2.0, true)
			draw_arc(center, 16.0 + 4.0 * (1.0 - pulse), 0.0, TAU, 24, edge, 1.5, true)
			draw_circle(center, 2.4, accent)
