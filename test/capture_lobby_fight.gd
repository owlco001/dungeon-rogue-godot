extends SceneTree
const OUT := "/tmp/lobby_fight_cap"
func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	root.size = Vector2i(960, 640)
	var inst: Node = load("res://scenes/lobby.tscn").instantiate()
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
	await _wait(1.5)
	var lobby := root.get_child(-1)
	var btn := _find_btn(lobby, "出战")
	if btn:
		btn.pressed.emit()
		await _wait(1.0)
		await _shot("lobby_fight")
	else:
		print("NOT FOUND")
	quit()
