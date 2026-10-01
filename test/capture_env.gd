extends SceneTree
## v0.7 地牢环境精细化验证：corridor/forge/void 三套主题，全景+近景。
## Run: xvfb-run godot --rendering-driver opengl3 --audio-driver Dummy --path <project> --script res://test/capture_env.gd

const OUT := "/tmp/env_verify"


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
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < int(secs * 1000.0):
		await process_frame


func _run() -> void:
	Meta.selected_char = "aila"
	for theme in ["corridor", "forge", "void"]:
		var main: Node = load("res://scenes/main.tscn").instantiate()
		root.add_child(main)
		await _wait(1.5)
		main.arena.set_theme(theme)
		await _wait(3.0)
		var cam: Camera2D = main.get_node("Player/Camera2D")
		# 近景：默认视角，玩家出生点附近
		await _shot("env_" + theme + "_close")
		# 全景：拉远
		cam.position_smoothing_enabled = false
		cam.zoom = Vector2(0.55, 0.55)
		cam.global_position = Vector2(800, 600)
		await _wait(0.6)
		await _shot("env_" + theme + "_wide")
		main.queue_free()
		await _wait(0.5)
	print("DONE")
	quit()
