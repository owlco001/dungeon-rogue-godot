extends SceneTree
## Floating joystick verification: synthetic touch on left half.

const OUT := "/tmp/joy_test"


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	Meta.selected_char = "aila"
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


func _press(pos: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = pos
	Input.parse_input_event(ev)


func _release(pos: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = false
	ev.position = pos
	Input.parse_input_event(ev)


func _motion(pos: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	Input.parse_input_event(ev)


func _run() -> void:
	await _wait(2.5)
	var hud = root.get_node_or_null("Main/HUD")
	print("hud found: ", hud != null)
	await _shot("joy_idle")
	_press(Vector2(300, 450))
	await _wait(0.3)
	_motion(Vector2(370, 450))
	await _wait(0.3)
	if hud != null:
		print("move_vector (expect ~(0.875,0)): ", hud.get_move_vector())
	await _shot("joy_active")
	_release(Vector2(370, 450))
	await _wait(0.3)
	if hud != null:
		print("after release (expect (0,0)): ", hud.get_move_vector())
	await _shot("joy_released")
	print("JOY_TEST_DONE")
	quit()
