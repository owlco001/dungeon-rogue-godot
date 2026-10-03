extends SceneTree
## 投射物 + 拾取物加载与显示验证
## 目的：文件存在 ≠ 代码能加载。要验证 texture 真能load、尺寸正常、朝向正确（代码按dir.angle旋转）。
## Run: xvfb-run -a godot --rendering-driver opengl3 --audio-driver Dummy --path . --script res://test/capture_proj_pickups.gd

static var OUT := OS.get_environment("CAPTURE_OUT")
static var OUT_DIR := OUT if OUT != "" else "/tmp/projshot"
const PROJ := ["arrow", "axe", "bullet", "meteor", "orb"]
const PICK := ["gem_s", "gem_m", "gem_l", "coin", "chest", "portal_stairs"]

var fails := 0


func _check(name: String, cond: bool, info := "") -> void:
	if cond:
		print("PASS ", name, " | ", info)
	else:
		fails += 1
		print("FAIL ", name, " | ", info)


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_run.call_deferred()


func _wait(secs: float) -> void:
	var s := Time.get_ticks_msec()
	while Time.get_ticks_msec() - s < int(secs * 1000.0):
		await process_frame


func _run() -> void:
	# 1) 全部贴图必须能 load（ResourceLoader 成功 + 尺寸 256 的 power-of-two）
	for n in PROJ:
		var p := "res://assets/sprites/fx/projectiles/proj_%s.png" % n
		var tex := load(p) as Texture2D if ResourceLoader.exists(p) else null
		var ok := tex != null and tex.get_width() == 128 and tex.get_height() == 128
		_check("proj load " + n, ok,
			"" if tex == null else "%dx%d" % [tex.get_width(), tex.get_height()])
	for n in PICK:
		var p := "res://assets/sprites/pickups/%s.png" % n
		var tex := load(p) as Texture2D if ResourceLoader.exists(p) else null
		var ok := tex != null and tex.get_width() == 256 and tex.get_height() == 256
		_check("pickup load " + n, ok,
			"" if tex == null else "%dx%d" % [tex.get_width(), tex.get_height()])

	# 2) 三档宝石必须是同一形状的缩放（长宽比偏差 > 8% 即说明形状不一致）
	var ratios := {}
	for t in ["s", "m", "l"]:
		var tex := load("res://assets/sprites/pickups/gem_%s.png" % t) as Texture2D
		var img := tex.get_image()
		var x0 := img.get_width()
		var x1 := -1
		var y0 := img.get_height()
		var y1 := -1
		for y in range(img.get_height()):
			for x in range(img.get_width()):
				if img.get_pixel(x, y).a > 0.4:
					x0 = min(x0, x)
					x1 = max(x1, x)
					y0 = min(y0, y)
					y1 = max(y1, y)
		if x1 < 0:
			_check("gem ratio " + t, false, "空图")
			continue
		var r := float(x1 - x0 + 1) / float(max(y1 - y0 + 1, 1))
		ratios[t] = r
		print("  gem_%s 主体 %dx%d 长宽比 %.3f" % [t, x1 - x0 + 1, y1 - y0 + 1, r])
	if ratios.size() == 3:
		var rs: Array = ratios.values()
		var base: float = rs[0]
		var dev := 0.0
		for r in rs:
			dev = max(dev, absf(float(r) - base) / base)
		_check("gem 三档形状一致", dev < 0.08, "最大偏差 %.1f%%" % (dev * 100.0))

	# 3) 场景内实摆：投射物按 4 个方向旋转（代码逻辑是 rotation = dir.angle()）
	var tp := "res://assets/tiles/corridor/tile_corridor_floor_a.png"
	var tex0: Texture2D = load(tp) if ResourceLoader.exists(tp) else null
	if tex0 != null:
		for i in range(9):
			for j in range(5):
				var s := Sprite2D.new()
				s.texture = tex0
				s.scale = Vector2(2.0, 2.0)
				s.position = Vector2(i * 384, j * 288)
				root.add_child(s)

	# 投射物：三行，每行一个种类，展示 0° / 45° / 90°（代码会这样转）
	var angles := [0.0, PI * 0.25, PI * 0.5]
	for r in range(PROJ.size()):
		var tex := load("res://assets/sprites/fx/projectiles/proj_%s.png" % PROJ[r]) as Texture2D
		for c in range(3):
			var sp := Sprite2D.new()
			sp.texture = tex
			sp.rotation = angles[c]
			sp.position = Vector2(200 + c * 180, 180 + r * 160)
			root.add_child(sp)
	# 拾取物：底行
	for c in range(PICK.size()):
		var tex := load("res://assets/sprites/pickups/%s.png" % PICK[c]) as Texture2D
		var sp := Sprite2D.new()
		sp.texture = tex
		if PICK[c] == "coin":
			sp.scale = Vector2.ONE * 0.10
		elif PICK[c].begins_with("gem_"):
			sp.scale = Vector2.ONE * 0.25
		else:
			sp.scale = Vector2.ONE * 0.75
		sp.position = Vector2(980 + (c % 3) * 220, 700 + (c / 3) * 220)
		root.add_child(sp)

	await _wait(0.8)
	var img := root.get_texture().get_image()
	img.save_png(OUT_DIR + "/all.png")
	print("截图: ", OUT_DIR)
	print("RESULT: ", "PASS" if fails == 0 else "FAIL(%d)" % fails)
	quit(0 if fails == 0 else 1)