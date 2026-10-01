extends SceneTree
## Fight screen capture: load main.tscn at phone viewport, screenshot after game starts.
## Run: godot --rendering-driver opengl3 --audio-driver Dummy --path <project> --script res://test/capture_fight.gd

const OUT := "/tmp/fight_cap"

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	# 模拟手机竖屏：stretch=expand 下 viewport 为 960x2079（高>宽）
	root.size = Vector2i(960, 2079)
	var inst: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(inst)
	_run.call_deferred()

func _shot(name: String) -> void:
	await process_frame
	await process_frame
	var img: Image = root.get_texture().get_image()
	img.save_png(OUT + "/" + name + ".png")
	print("shot: ", name)

func _wait(secs: float) -> void:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < int(secs * 1000.0):
		await process_frame

func _run() -> void:
	await _wait(3.0)
	await _shot("fight_full")
	# dump HUD node tree for layout debugging
	var hud := _find_node(root, "HUD")
	if hud:
		_dump(hud, 0)
	print("script errors above (if any) are fatal for this check")
	quit()

func _find_node(n: Node, name: String) -> Node:
	if n.name == name:
		return n
	for c in n.get_children():
		var r := _find_node(c, name)
		if r: return r
	return null

func _dump(n: Node, depth: int) -> void:
	if depth > 3: return
	var info := ""
	if n is Control:
		var c := n as Control
		info = " pos=%s size=%s vis=%s" % [c.position, c.size, c.visible]
	print("  ".repeat(depth) + n.name + " (" + n.get_class() + ")" + info)
	for c in n.get_children():
		_dump(c, depth + 1)
