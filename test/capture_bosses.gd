extends SceneTree
## Boss 素材验证：加载 + 体量 + 三阶段贴图切换
## 关键点：boss.gd _enter_phase 用 tex_key = "tex"+str(p) 切贴图，
##这条链断了三阶段 Boss 视觉上就没有变化（数值变了但看着一样）。
## Run: xvfb-run -a godot --rendering-driver opengl3 --audio-driver Dummy --path . --script res://test/capture_bosses.gd

const OUT := "/tmp/bossshot"
const BOSSES := ["colossus", "batking", "forgemaster", "widow_a", "widow_b",
	"thorntyrant", "mohei_phase1", "mohei_phase2", "mohei_phase3"]

var fails := 0


func _check(name: String, cond: bool, info := "") -> void:
	if cond:
		print("PASS ", name, " | ", info)
	else:
		fails += 1
		print("FAIL ", name, " | ", info)


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	_run.call_deferred()


func _wait(secs: float) -> void:
	var s := Time.get_ticks_msec()
	while Time.get_ticks_msec() - s < int(secs * 1000.0):
		await process_frame


func _run() -> void:
	# 1) 全部贴图能加载且尺寸统一
	for b in BOSSES:
		var p := "res://assets/sprites/bosses/boss_%s.png" % b
		var tex := load(p) as Texture2D if ResourceLoader.exists(p) else null
		var ok := tex != null and tex.get_width() == 640 and tex.get_height() == 640
		_check("boss load " + b, ok, "" if tex == null else "%dx%d" % [tex.get_width(), tex.get_height()])

	# 2) 三阶段墨骸必须逐阶段不同（贴图不能雷同，否则阶段切换视觉无变化）
	var t1 := _to_rgba(load("res://assets/sprites/bosses/boss_mohei_phase1.png") as Texture2D)
	var t2 := _to_rgba(load("res://assets/sprites/bosses/boss_mohei_phase2.png") as Texture2D)
	var t3 := _to_rgba(load("res://assets/sprites/bosses/boss_mohei_phase3.png") as Texture2D)
	var d12 := _img_diff(t1, t2)
	var d23 := _img_diff(t2, t3)
	var d13 := _img_diff(t1, t3)
	_check("mohei phase1!=phase2", d12 > 0.02, "差异 %.1f%%" % (d12 * 100.0))
	_check("mohei phase2!=phase3", d23 > 0.02, "差异 %.1f%%" % (d23 * 100.0))
	_check("mohei phase1!=phase3", d13 > 0.04, "差异 %.1f%%" % (d13 * 100.0))
	# 明度必须递增（阶段越高视觉越亮=威胁升级）
	var l1 := _lum(t1)
	var l2 := _lum(t2)
	var l3 := _lum(t3)
	_check("mohei 明度递增", l1 < l2 and l2 < l3, "%.3f -> %.3f -> %.3f" % [l1, l2, l3])

	# 3) 双生亡语者 A/B 必须明显不同（同体= 分身才有意义）
	var wa := _to_rgba(load("res://assets/sprites/bosses/boss_widow_a.png") as Texture2D)
	var wb := _to_rgba(load("res://assets/sprites/bosses/boss_widow_b.png") as Texture2D)
	var dw := _img_diff(wa, wb)
	_check("widow A!=B", dw > 0.02, "差异 %.1f%%" % (dw * 100.0))

	# 4) 场景内实摆：按游戏里的方式贴（底部对齐 + 居中）
	var tp := "res://assets/tiles/corridor/tile_corridor_floor_a.png"
	var tex0: Texture2D = load(tp) if ResourceLoader.exists(tp) else null
	if tex0 != null:
		for i in range(8):
			for j in range(4):
				var s := Sprite2D.new()
				s.texture = tex0
				s.scale = Vector2(2.0, 2.0)
				s.position = Vector2(i * 384, j * 288)
				root.add_child(s)
	var cell := 330.0
	for i in range(BOSSES.size()):
		var tex := load("res://assets/sprites/bosses/boss_%s.png" % BOSSES[i]) as Texture2D
		var sp := Sprite2D.new()
		sp.texture = tex
		sp.position = Vector2(280 + (i % 3) * cell * 2.0, 200 + (i / 3) * cell * 2.0)
		root.add_child(sp)
	await _wait(0.8)
	var img := root.get_texture().get_image()
	img.save_png(OUT + "/all.png")
	print("截图: ", OUT)
	print("RESULT: ", "PASS" if fails == 0 else "FAIL(%d)" % fails)
	quit(0 if fails == 0 else 1)


## 统一转 RGBA8，避免读到非 8bit 格式时 get_data 偏移算错
func _to_rgba(tex: Texture2D) -> Image:
	var im := tex.get_image()
	if im.is_compressed():
		im.decompress()
	if im.get_format() != Image.FORMAT_RGBA8:
		im.convert(Image.FORMAT_RGBA8)
	return im


## 两图差异度：alpha 交集内 RGB 平均绝对差，归一到 0~1
## 用 get_data() 批量读，不用 get_pixel 逐点—— 640x640 逐点调41 万次会卡到超时，
## 导致结果被跳过、断言变成假通过。
func _img_diff(a: Image, b: Image) -> float:
	if a.get_width() != b.get_width() or a.get_height() != b.get_height():
		return 1.0
	var da := a.get_data()
	var db := b.get_data()
	var total := 0.0
	var n := 0
	var i := 0
	while i < da.size():
		var aa := da[i + 3]
		var ba := db[i + 3]
		if aa > 102 and ba > 102:
			total += absf(da[i] - db[i]) + absf(da[i + 1] - db[i + 1]) + absf(da[i + 2] - db[i + 2])
			n += 1
		i += 4
	if n == 0:
		return 1.0
	return total / float(n) / 3.0 / 255.0


## alpha>0.4 区域的平均明度（同样走 get_data 批量读）
func _lum(im: Image) -> float:
	var d := im.get_data()
	var total := 0.0
	var n := 0
	var i := 0
	while i < d.size():
		if d[i + 3] > 102:
			total += (d[i] + d[i + 1] + d[i + 2]) / 3.0
			n += 1
		i += 4
	return total / max(n, 1) / 255.0