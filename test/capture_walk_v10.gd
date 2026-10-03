extends SceneTree
## 角色行走动画观感验证（v0.10）
## Run: xvfb-run -a godot --rendering-driver opengl3 --audio-driver Dummy --path . --script res://test/capture_walk_v10.gd
##
## 帧数从素材目录自动探测，不写死。输出：
##   sheet_<dir>.png   —— 各方向接触表（4 方向并排）
##   scene_<dir>.png   —— 游戏场景内实况（1920x1080）
##   all_dirs.png      —— 四方向汇总对比

const OUT := "/tmp/walkshot"
const DIRS := ["right", "front", "back", "left"]


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	_run.call_deferred()


func _count(cid: String, d: String) -> int:
	var n := 0
	for f in DirAccess.get_files_at("res://assets/sprites/characters/%s" % cid):
		if f.ends_with(".import"):
			continue
		if f.begins_with("char_%s_%s_walk_" % [cid, d]) and f.ends_with(".png"):
			n += 1
	return n


func _sheet(cid: String) -> void:
	# 四方向各取 6 帧做并排对比
	var cols := 6
	var cell := 168
	var img := Image.create(cols * cell, DIRS.size() * cell, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.13, 0.13, 0.16, 1.0))
	for r in DIRS.size():
		var d: String = DIRS[r]
		var n := _count(cid, d)
		for c in cols:
			var idx := int(float(c) / max(cols - 1, 1) * max(n - 1, 0))
			var p := "res://assets/sprites/characters/%s/char_%s_%s_walk_%02d.png" % [cid, cid, d, idx]
			if not ResourceLoader.exists(p):
				continue
			var tex: Texture2D = load(p)
			var src: Image = tex.get_image()
			if src == null:
				continue
			src.convert(Image.FORMAT_RGBA8)
			src.resize(cell, cell, Image.INTERPOLATE_LANCZOS)
			img.blend_rect(src, Rect2i(0, 0, cell, cell), Vector2i(c * cell, r * cell))
	img.save_png(OUT + "/all_dirs.png")
	print("sheet: all_dirs.png  frames per dir = ", DIRS.map(func(d): return _count(cid, d)))


func _scene(cid: String) -> void:
	# 直接实例化 player 场景（main.tscn 里的 player 需游戏开始才创建）
	var ps: PackedScene = load("res://scenes/player.tscn")
	var inst := ps.instantiate()
	root.add_child(inst)
	await process_frame
	await process_frame
	await process_frame

	var player: Node = _find_player(inst)
	if player == null:
		print("player not found")
		return
	var sprite: AnimatedSprite2D = _find_sprite(player)
	if sprite == null:
		print("sprite not found")
		return
	print("player sprite found, current anim=", sprite.animation)

	# 逐方向播放并截图
	for d in ["down", "right", "up", "left"]:
		sprite.play("walk_" + d)
		await process_frame
		var t := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t < 260:
			await process_frame
		await process_frame
		var img: Image = root.get_texture().get_image()
		img.save_png(OUT + "/scene_%s.png" % d)
		print("shot: scene_", d, "  anim=", sprite.animation, "  frame=", sprite.frame)


func _find_sprite(n: Node) -> AnimatedSprite2D:
	if n is AnimatedSprite2D:
		return n
	for c in n.get_children():
		var r := _find_sprite(c)
		if r != null:
			return r
	return null


func _find_player(n: Node) -> Node:
	if n.has_method("heal_full") or n.name.to_lower().contains("player"):
		return n
	for c in n.get_children():
		var r := _find_player(c)
		if r != null:
			return r
	return null


func _run() -> void:
	var cid := "aila"
	_sheet(cid)
	await _scene(cid)
	print("DONE")
	quit()
