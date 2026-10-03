extends SceneTree
## v0.9 角色动画观感验证（艾拉 6 帧 walk，真实 1920x1080 视口）
## Run: xvfb-run godot --rendering-driver opengl3 --audio-driver Dummy --path . --script res://test/capture_walk_v09.gd
##
## 目的：在游戏真实显示条件下判断 6 帧序列的动作幅度是否达标。
## 输出：/tmp/artwork/shots/ 下 contactsheet（4方向x6帧拼贴）+ scene_walk_00..05（场景内实况）

const OUT := "/tmp/artwork/shots"
const AILA := "res://assets/sprites/characters/aila"


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	_run.call_deferred()


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	var img: Image = root.get_texture().get_image()
	img.save_png(OUT + "/" + name + ".png")
	print("shot: ", name)


func _wait(secs: float) -> void:
	var t := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t < int(secs * 1000.0):
		await process_frame


func _on_checker(img: Image, cell: int = 12) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var c := Color(0.10, 0.08, 0.13, 1.0)
			if ((x / cell) + (y / cell)) % 2 == 0:
				c = Color(0.19, 0.15, 0.23, 1.0)
			out.set_pixel(x, y, c)
	out.blend_rect(img, Rect2i(0, 0, w, h), Vector2i(0, 0))
	return out


func _sheet() -> void:
	var dirs := ["down", "left", "right", "up"]
	var cw := 200
	var pad := 6
	var lbl := 16
	var sheet := Image.create(
		pad * 2 + 6 * (cw + pad), pad * 2 + 4 * (cw + lbl + pad), false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.05, 0.04, 0.07, 1.0))
	for di in dirs.size():
		for i in 6:
			var path := "%s/char_aila_%s_walk_%02d.png" % [AILA, dirs[di], i]
			if not ResourceLoader.exists(path):
				print("[MISS] ", path)
				continue
			var img := (load(path) as Texture2D).get_image()
			img.resize(cw, cw, Image.INTERPOLATE_LANCZOS)
			img = _on_checker(img)
			sheet.blend_rect(img, Rect2i(0, 0, cw, cw),
				Vector2i(pad + i * (cw + pad), pad + di * (cw + lbl + pad)))
	sheet.save_png(OUT + "/walk_contactsheet.png")
	print("[OK] contactsheet -> ", OUT, "/walk_contactsheet.png")


func _run() -> void:
	print("视口: ", root.size)
	_sheet()

	# 场景内实况：走6 帧 walk_down
	Meta.selected_char = "aila"
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _wait(2.0)

	var anim := _find_anim(main)
	if anim == null:
		print("[SKIP] 未找到 AnimatedSprite2D")
		quit()
		return

	var cam: Camera2D = main.get_node("Player/Camera2D")
	cam.position_smoothing_enabled = false
	# 拉近到角色，观察动作细节
	cam.zoom = Vector2(1.0, 1.0)
	await _wait(1.0)

	for i in 6:
		if anim.sprite_frames != null and anim.sprite_frames.has_animation("walk_down"):
			anim.animation = "walk_down"
			anim.frame = i
		await _wait(0.12)
		await _shot("scene_walk_%02d.png" % i)

	print("[OK] 场景截帧完成")
	main.queue_free()
	await _wait(0.5)
	quit()


func _find_anim(n: Node) -> AnimatedSprite2D:
	if n is AnimatedSprite2D:
		return n
	for c in n.get_children():
		var r := _find_anim(c)
		if r != null:
			return r
	return null
