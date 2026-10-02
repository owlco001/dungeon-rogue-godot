extends SceneTree
## 地形截图验证：开局后把玩家传送到各地形块中心逐一截图。
const OUT := "/tmp/terrain_cap"

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	root.size = Vector2i(960, 640)
	var inst: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(inst)
	_run.call_deferred()

func _shot(name: String) -> void:
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(OUT + "/" + name + ".png")
	print("shot: ", name)

func _wait(secs: float) -> void:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < int(secs * 1000.0):
		await process_frame

func _find_btn(node: Node, text: String) -> Button:
	if node is Button and node.text == text:
		return node
	for c in node.get_children():
		var r := _find_btn(c, text)
		if r != null:
			return r
	return null

func _run() -> void:
	await _wait(2.0)
	var btn := _find_btn(root, "开始")
	if btn:
		btn.pressed.emit()
	else:
		print("开始 NOT FOUND")
	await _wait(1.5)
	var main: Node = get_first_node_in_group("game")
	var player: Node = get_first_node_in_group("player")
	if main == null or player == null:
		print("no game/player")
		quit()
		return
	var patches: Array = main.get("_terrain_patches")
	print("floor1 patches: ", patches.size())
	if not patches.is_empty():
		player.global_position = patches[0]["center"]
		await _wait(1.2)
		await _shot("f1_rubble")
	main.call("_build_terrain", "forge")
	await _wait(0.3)
	patches = main.get("_terrain_patches")
	if not patches.is_empty():
		player.global_position = patches[0]["center"]
		await _wait(1.2)
		await _shot("f2_lava")
	main.call("_build_terrain", "ice")
	await _wait(0.3)
	patches = main.get("_terrain_patches")
	if not patches.is_empty():
		player.global_position = patches[0]["center"]
		await _wait(1.2)
		await _shot("f3_ice")
	quit()
