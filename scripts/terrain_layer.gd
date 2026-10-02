extends Node2D
## 地形视觉层（v0.8.5）：按 TerrainGen 的格子簇逐格绘制不规则色块 + 主题细节。
## 颜色按地形种类区分；熔岩/虚空带呼吸脉动（10Hz 重绘，其余主题静态）。

var patches: Array = []
var theme := "corridor"
var _time := 0.0
var _pulse_t := 0.0

const CELL := 50.0
const TEX_SPAN := 120.0  # 贴图覆盖 2.4 格的世界跨度（UV 按世界坐标取样，跨格无缝）
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
	for patch in patches:
		var kind := String(patch.get("id", "rubble"))
		var cols: Array = COLORS.get(kind, COLORS["rubble"])
		var fill: Color = cols[0]
		var edge: Color = cols[1]
		var accent: Color = cols[2]
		if kind == "lava" or kind == "rift":
			var pulse := 0.5 + 0.5 * sin(_time * 2.6)
			fill.a *= 0.88 + 0.20 * pulse
			accent.a *= 0.70 + 0.30 * pulse
		for cell_v in patch.get("cells", []):
			var cell: Vector2i = cell_v
			var center := Vector2((float(cell.x) + 0.5) * CELL, (float(cell.y) + 0.5) * CELL)
			# v0.8.12：用户指定用方形格（不再用圆形色块），相邻格边对边铺满成整片
			var half := CELL * 0.5
			var rect := Rect2(center - Vector2(half, half), Vector2(CELL, CELL))
			draw_rect(rect, fill)
			# Agnes 贴图层：UV 按世界坐标取样，相邻格图案连续（方形格无描边，自然连成整片）
			var tex: Texture2D = _textures.get(kind, null)
			if tex != null:
				var a := 0.96
				if kind == "lava" or kind == "rift":
					a *= 0.90 + 0.10 * sin(_time * 2.6)
				var corners := PackedVector2Array([rect.position,
					rect.position + Vector2(CELL, 0), rect.end,
					rect.position + Vector2(0, CELL)])
				var pcols := PackedColorArray()
				var uvs := PackedVector2Array()
				for p in corners:
					pcols.append(Color(1, 1, 1, a))
					uvs.append(p / TEX_SPAN)
				draw_polygon(corners, pcols, uvs, tex)
			_draw_details(kind, center, cell, edge, accent)


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
