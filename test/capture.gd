extends SceneTree
## Visual capture harness: loads main scene, simulates input, saves viewport PNGs.
## Run: godot --rendering-driver opengl3 --audio-driver Dummy --path <project> --script res://test/capture.gd

const OUT := "/tmp/godot_cap"

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var inst: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(inst)
	_run.call_deferred()

func _shot(name: String) -> void:
	await process_frame
	await process_frame
	var img: Image = root.get_texture().get_image()
	img.save_png(OUT + "/" + name + ".png")
	print("shot: ", name)

func _hold(action: String, secs: float) -> void:
	Input.action_press(action)
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < int(secs * 1000.0):
		await process_frame
	Input.action_release(action)

func _wait(secs: float) -> void:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < int(secs * 1000.0):
		await process_frame

func _run() -> void:
	await _wait(2.0)
	await _shot("01_idle_initial")

	await _hold("move_right", 1.6)
	await _shot("02_walk_right")
	await _wait(0.6)
	await _shot("03_idle_right")

	await _hold("move_down", 1.4)
	await _shot("04_walk_down")
	await _wait(0.6)
	await _shot("05_idle_down")

	await _hold("move_left", 1.4)
	await _shot("06_walk_left")
	await _wait(0.6)
	await _shot("07_idle_left")

	await _hold("move_up", 1.4)
	await _shot("08_walk_up")
	await _wait(0.6)
	await _shot("09_idle_up")

	Input.action_press("attack")
	await _wait(0.25)
	await _shot("10_attack")
	Input.action_release("attack")
	await _wait(0.8)
	await _shot("11_after_attack")

	print("CAPTURE_DONE")
	quit()
