extends SceneTree
## 角色朝向实机截图：直接实例化 Player，看四个朝向各渲染出什么
##
## 这比读代码更可靠—— _tex() 返回 null 时 SpriteFrames 里会塞进空纹理，
## 引擎可能报 ERROR、可能静默画不出来，只有截图能确认玩家到底看不看得见。
##
## Run: xvfb-run -a godot --rendering-driver opengl3 --audio-driver Dummy \
##       --path . --script res://test/capture_chars.gd

## 2026-10-03 Windows 兼容：原写死 /tmp/charshot，Windows 上不存在该路径，
## save_png 会报 "Can't save PNG at path"。改为读环境变量 CAPTURE_OUT，
## 默认仍用 /tmp/charshot（Linux 沙箱行为不变）。
## 用static var 而非 const：OS.get_environment() 不是常量表达式（4.7 实测报错）。
static var OUT := OS.get_environment("CAPTURE_OUT")
static var OUT_DIR := OUT if OUT != "" else "/tmp/charshot"
const CHARS := ["aila", "batong", "mofei"]
const DIRS := ["down", "up", "left", "right"]


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_run.call_deferred()


func _wait(secs: float) -> void:
	var s := Time.get_ticks_msec()
	while Time.get_ticks_msec() - s < int(secs * 1000.0):
		await process_frame


func _run() -> void:
	# 铺地板
	var tp := "res://assets/tiles/corridor/tile_corridor_floor_a.png"
	if ResourceLoader.exists(tp):
		var t0: Texture2D = load(tp)
		for i in range(6):
			for j in range(4):
				var s := Sprite2D.new()
				s.texture = t0
				s.scale = Vector2(2.0, 2.0)
				s.position = Vector2(i * 384, j * 288)
				root.add_child(s)

	# 每个角色一个 Sprite2D，用它自己的 SpriteFrames（复刻 _build_sprite_frames）
	var marks := []
	for ci in range(CHARS.size()):
		var cid: String = CHARS[ci]
		var sp: AnimatedSprite2D = AnimatedSprite2D.new()
		var sf := SpriteFrames.new()
		for d: String in DIRS:
			var dd: String = d
			if d == "down":
				dd = "front"
			elif d == "up":
				dd = "back"
			# idle 回退 walk 首帧（与 player.gd 一致）
			var p := "res://assets/sprites/characters/%s/char_%s_%s_walk_00.png" % [cid, cid, dd]
			var tex: Texture2D = load(p) as Texture2D if ResourceLoader.exists(p) else null
			print("%s/%s -> %s : %s" % [cid, d, dd, "OK" if tex != null else "NULL(空)"])
			sf.add_animation("idle_" + d)
			sf.set_animation_speed("idle_" + d, 2.0)
			sf.add_frame("idle_" + d, tex)
		sp.frames = sf
		sp.animation = "idle_down"
		sp.position = Vector2(260 + ci * 400, 400)
		root.add_child(sp)
		marks.append(sp)

	await _wait(0.6)
	var img := root.get_texture().get_image()
	img.save_png(OUT_DIR + "/chars.png")
	var data := img.get_data()
	var w := img.get_width()

	# 逐角色判定：与「地板基线」做差，只统计明显偏离地板的像素。
	#
	# 踩过的坑：第一版用绝对亮度 >200/255 判可见，透明区（地板本身均值约 0.29）
	# 在部分区域也能过阈值 -> 报出 96686像素「OK」的假通过，
	# 而截图上 batong/mofei 明明是空白。
	# 正确做法：先采样该格子内的地板基线，再统计偏离基线的像素。
	for ci in range(CHARS.size()):
		var sp: AnimatedSprite2D = marks[ci]
		var cx := int(sp.position.x)
		# 取角色框外的一条横带作为地板基线
		var base := 0.0
		var bn := 0
		for y in range(230, 260):
			for x in range(cx - 150, cx + 150):
				if x < 0 or x >= w:
					continue
				var o := (y * w + x) * 4
				base += (float(data[o]) + float(data[o + 1]) + float(data[o + 2])) / 765.0
				bn += 1
		if bn > 0:
			base /= float(bn)
		var cnt := 0
		for y in range(200, 620):
			for x in range(cx - 150, cx + 150):
				if x < 0 or x >= w:
					continue
				var o := (y * w + x) * 4
				var l := (float(data[o]) + float(data[o + 1]) + float(data[o + 2])) / 765.0
				# 明显偏离地板基线才算角色像素
				if absf(l - base) > 0.10:
					cnt += 1
		var ok := cnt > 2000
		print("%s 朝下(down)偏离地板像素: %d  地板基线=%.3f  %s" % [CHARS[ci], cnt, base, "OK" if ok else "空白!"])

	print("\n截图: ", OUT_DIR)
	quit(0)
