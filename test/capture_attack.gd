extends SceneTree

const OUT := "/tmp/godot_cap"

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var inst: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(inst)
	_run.call_deferred()

func _wait(secs: float) -> void:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < int(secs * 1000.0):
		await process_frame

func _shot(name: String) -> void:
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(OUT + "/" + name + ".png")
	print("shot: ", name)

func _run() -> void:
	await _wait(2.0)
	# face right first
	Input.action_press("move_right")
	await _wait(0.8)
	Input.action_release("move_right")
	await _wait(0.4)
	# attack and capture the swing at several moments
	# attack via real input events (action_press alone won't hit _input)
	var ev := InputEventAction.new()
	ev.action = "attack"
	ev.pressed = true
	Input.parse_input_event(ev)
	await _wait(0.08)
	await _shot("atk_1")
	await _wait(0.08)
	await _shot("atk_2")
	ev = InputEventAction.new()
	ev.action = "attack"
	ev.pressed = false
	Input.parse_input_event(ev)
	await _wait(0.5)
	await _shot("atk_3")
	print("ATTACK_CAP_DONE")
	quit()
