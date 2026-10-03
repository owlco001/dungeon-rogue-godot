extends SceneTree
## Verifies 巴顿 (whirlwind AoE) and 墨菲 (orb chain) auto-weapons get kills.
## Run: xvfb-run godot --rendering-driver opengl3 --audio-driver Dummy \
##      --path <project> --script res://test/capture_weapons.gd

const OUT := "user://shot_v01"

var main: Node


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	Engine.max_physics_steps_per_frame = 32
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


func _dismiss_levelups() -> void:
	for i in range(6):
		if main.hud.is_levelup_open():
			main.hud._on_upgrade_btn("attack")
			await _wait(0.4)
		else:
			break


func _test_char(cid: String, tag: String) -> void:
	main._on_character_chosen(cid)
	main.player.max_hp = 99999.0
	main.player.hp = 99999.0
	await _wait(2.0)
	await _shot(tag + "_start")
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 60000:
		_dismiss_levelups()
		if main.kills >= 3:
			break
		await process_frame
	_dismiss_levelups()
	await _shot(tag + "_combat")
	print(tag, " kills: ", main.kills, " level: ", main.player.level)


func _run() -> void:
	_watchdog()
	await _wait(1.0)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _wait(1.0)
	await _test_char("batong", "12_batong")
	# fresh run for mofei
	main.queue_free()
	await _wait(1.0)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _wait(1.0)
	await _test_char("mofei", "13_mofei")
	print("WEAPONS_DONE")
	quit()


func _watchdog() -> void:
	await _wait(240.0)
	print("WATCHDOG_TIMEOUT")
	quit()
