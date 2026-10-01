extends SceneTree
## Lobby capture: narrow phone viewport, screenshot top bar, press test-sound button, screenshot toast.
## Run: godot --rendering-driver opengl3 --audio-driver Dummy --path <project> --script res://test/capture_lobby.gd

const OUT := "/tmp/lobby_cap"

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	root.size = Vector2i(390, 844)
	var inst: Node = load("res://scenes/lobby.tscn").instantiate()
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

func _find_btn(node: Node, text: String) -> Button:
	if node is Button and text in node.text:
		return node
	for c in node.get_children():
		var r := _find_btn(c, text)
		if r != null:
			return r
	return null

func _run() -> void:
	await _wait(1.0)
	await _shot("lobby_top")
	var lobby := root.get_child(-1)
	var btn := _find_btn(lobby, "试音")
	if btn == null:
		print("TESTBTN: NOT FOUND")
	else:
		print("TESTBTN: found, visible=", btn.visible, " rect=", btn.get_global_rect())
		btn.pressed.emit()
		await _wait(1.2)
		await _shot("lobby_toast")
	print("script errors above (if any) are fatal for this check")
	quit()
