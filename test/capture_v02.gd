extends SceneTree
## v0.2 flow verification: new weapon -> weapon upgrade -> elite floor ->
## floor-5 boss fight -> relic pickup -> floor 6. Zero script errors expected.
## Run: xvfb-run godot --rendering-driver opengl3 --audio-driver Dummy \
##      --path <project> --script res://test/capture_v02.gd

const OUT := "user://shot_v02"

var main: Node


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
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
	await _wait(420.0)
	print("WATCHDOG_TIMEOUT")
	quit()


func _choose_option(pred: String) -> bool:
	# pred: "new_weapon" / "weapon_up" / anything
	var hud = main.hud
	var opts: Array = hud.get_levelup_options()
	for i in range(opts.size()):
		if String(opts[i]["type"]) == pred:
			print("choose: ", opts[i]["title"])
			hud._on_upgrade_btn(i)
			return true
	if opts.size() > 0:
		print("choose fallback: ", opts[0]["title"])
		hud._on_upgrade_btn(0)
		return true
	return false


func _dismiss_levelups(pred: String) -> void:
	for i in range(12):
		if main.hud.is_levelup_open():
			_choose_option(pred)
			await _wait(0.3)
		else:
			break


func _settle() -> void:
	# consume any pending level-ups (paused game blocks physics/stairs/gems)
	_dismiss_levelups("new_passive")
	await _wait(0.2)
	_dismiss_levelups("weapon_up")
	await _wait(0.2)


func _kill_all() -> void:
	for e in get_nodes_in_group("enemies"):
		if is_instance_valid(e) and not bool(e.get("dead")):
			e.take_damage(9999999.0, Vector2.UP)


func _goto_stairs() -> bool:
	await _settle()
	for i in range(40):
		if is_instance_valid(main._stairs):
			break
		await _wait(0.25)
	if not is_instance_valid(main._stairs):
		print("ERROR: no stairs appeared")
		return false
	main.player.global_position = main._stairs.global_position
	await _wait(1.2)
	return true


func _clear_and_advance() -> bool:
	_kill_all()
	await _wait(0.6)
	return await _goto_stairs()


func _run() -> void:
	_watchdog()
	await _wait(1.5)
	await _shot("01_select")

	main._on_character_chosen("aila")
	main.player.max_hp = 99999.0
	main.player.hp = 99999.0
	await _wait(1.0)
	await _shot("02_start")

	# real combat for a bit: bow auto-kills
	await _hold("move_right", 2.0)
	print("floor1 enemies: ", main._enemies_alive())

	# force level-ups -> take a NEW WEAPON (dual)
	main.player.gain_xp(60)
	await _wait(0.5)
	await _shot("03_levelup")
	_dismiss_levelups("new_weapon")
	await _wait(0.5)
	print("weapons: ", main.player.weapons.map(func(w): return "%s Lv%d" % [w["id"], w["lv"]]))
	await _shot("04_dual")

	# more xp -> WEAPON UPGRADE
	main.player.gain_xp(120)
	await _wait(0.5)
	_dismiss_levelups("weapon_up")
	await _wait(0.5)
	print("weapons after up: ", main.player.weapons.map(func(w): return "%s Lv%d" % [w["id"], w["lv"]]))
	print("passives: ", main.player.passives)

	# floor 1 -> 2 -> 3 (elite floor)
	await _clear_and_advance()
	print("now floor: ", main.floor_num, " (expect 2)")
	await _clear_and_advance()
	print("now floor: ", main.floor_num, " (expect 3) elite=", GameData.is_elite_floor(main.floor_num))
	var elites := 0
	for e in get_nodes_in_group("enemies"):
		if bool(e.get("elite")):
			elites += 1
	print("elite count on floor 3: ", elites)
	await _wait(1.0)
	await _shot("05_elite")

	# floor 4 -> 5 (boss)
	await _clear_and_advance()
	print("now floor: ", main.floor_num, " (expect 4)")
	await _clear_and_advance()
	print("now floor: ", main.floor_num, " (expect 5) boss=", GameData.is_boss_floor(main.floor_num))
	await _settle()
	await _wait(1.5)
	print("boss ref valid: ", is_instance_valid(main._boss_ref))
	await _shot("06_boss")
	# let the boss show skills (slam ~3s, charge ~7s)
	await _wait(9.0)
	await _shot("07_boss_fight")
	# kill boss -> relic drop
	if is_instance_valid(main._boss_ref):
		main._boss_ref.take_damage(9999999.0, Vector2.UP)
	await _wait(1.5)
	await _shot("08_boss_dead")
	# pick up the relic (settle first: a paused game blocks gem physics)
	await _settle()
	var relic_node: Node2D = null
	for g in get_nodes_in_group("pickups"):
		if g.get("kind") == "relic":
			relic_node = g
	print("relic dropped: ", relic_node != null)
	if relic_node != null:
		main.player.global_position = relic_node.global_position
		await _wait(1.0)
	print("player relics: ", main.player.relics)
	await _shot("09_relic")

	# floor 6
	await _goto_stairs()
	print("now floor: ", main.floor_num, " (expect 6)")
	await _wait(1.0)
	await _shot("10_floor6")

	# victory overlay smoke test (final boss uses the same flow)
	main.floor_num = 30
	main._on_victory()
	await _wait(0.5)
	await _shot("11_victory")

	print("DONE floor=", main.floor_num, " kills=", main.kills, " weapons=",
		main.player.weapons.size(), " relics=", main.player.relics)
	quit()
