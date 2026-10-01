extends SceneTree
## v0.1 flow verification: select -> move 4 dirs -> auto-kill -> level-up ->
## gem pickup -> stairs -> floor 2. Zero script errors expected.
## Run: xvfb-run godot --rendering-driver opengl3 --audio-driver Dummy \
##      --path <project> --script res://test/capture_v01.gd

const OUT := "/home/hatch/workspace/your_files/dungeon-rogue-godot-demo/v01"

var main: Node


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	# keep game-time close to wall-time under slow llvmpipe rendering
	Engine.max_physics_steps_per_frame = 32
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
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


func _hold(action: String, secs: float) -> void:
	Input.action_press(action)
	await _wait(secs)
	Input.action_release(action)


func _watchdog() -> void:
	await _wait(240.0)
	print("WATCHDOG_TIMEOUT")
	quit()


func _dismiss_levelups() -> void:
	for i in range(6):
		if main.hud.is_levelup_open():
			print("levelup open -> choose attack")
			main.hud._on_upgrade_btn("attack")
			await _wait(0.4)
		else:
			break


func _run() -> void:
	_watchdog()
	await _wait(1.5)
	await _shot("01_select")

	# choose 艾拉 (bow), godmode for a stable combat capture
	main._on_character_chosen("aila")
	main.player.max_hp = 99999.0
	main.player.hp = 99999.0
	await _wait(1.0)
	await _shot("02_start")

	await _hold("move_right", 1.2)
	await _shot("03_walk_right")
	await _hold("move_up", 1.2)
	await _shot("04_walk_up")
	await _hold("move_left", 1.2)
	await _shot("05_walk_left")
	await _hold("move_down", 1.2)
	await _shot("06_walk_down")

	# auto-combat: bow kills all floor-1 enemies
	print("combat start, enemies: ", main._enemies_alive())
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 90000:
		_dismiss_levelups()
		if main._enemies_alive() == 0:
			break
		await process_frame
		if int(Time.get_ticks_msec() - t0) % 15000 < 100:
			print("combat tick, enemies left: ", main._enemies_alive())
	await _shot("07_combat")
	_dismiss_levelups()
	print("combat end, enemies: ", main._enemies_alive(), " kills: ", main.kills,
		" level: ", main.player.level, " xp: ", main.player.xp)

	await _wait(1.0)
	print("stairs spawned: ", is_instance_valid(main._stairs))
	await _shot("08_stairs")

	# gem pickup: teleport onto a gem
	var picks: Array = get_nodes_in_group("pickups")
	print("pickups on ground: ", picks.size())
	if picks.size() > 0:
		var xp0: int = main.player.xp
		var gold0: int = main.player.gold
		main.player.global_position = (picks[0] as Node2D).global_position
		await _wait(0.8)
		print("pickup xp: ", xp0, " -> ", main.player.xp, " gold: ", gold0, " -> ", main.player.gold)
	_dismiss_levelups()
	await _shot("09_pickup")

	# go upstairs
	if is_instance_valid(main._stairs):
		main.player.global_position = main._stairs.global_position
		await _wait(1.5)
	print("floor now: ", main.floor_num, " theme: ", main.arena.theme)
	print("hud floor label: ", main.hud._floor_label.text)
	await _shot("10_floor2")

	# walk a bit on floor 2 to show new theme + enemies
	await _hold("move_right", 1.0)
	await _shot("11_floor2_walk")

	print("CAPTURE_DONE")
	quit()
