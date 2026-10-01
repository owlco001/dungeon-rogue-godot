# v0.3 截图验证（新武器/召唤物/超武合成/超武释放/技能/第10层Boss）
extends SceneTree

const OUT := "/home/hatch/workspace/your_files/dungeon-rogue-godot-demo/v03"
var _t0 := 0
var _main: Node = null


func _initialize() -> void:
	_t0 = Time.get_ticks_msec()
	DirAccess.make_dir_recursive_absolute(OUT)
	var packed := load("res://scenes/main.tscn") as PackedScene
	_main = packed.instantiate()
	root.add_child(_main)
	_run.call_deferred()


func _run() -> void:
	await process_frame
	await process_frame
	_main._on_character_chosen("aila")
	await _wait(1.0)
	_check()


func _check() -> void:
	var player := _main.get("player") as Node2D
	var hud := _main.get("hud") as CanvasLayer
	var errs := 0
	# 场景1:新武器战斗 + 召唤物群（清空后配 6 把 v0.3 新武器）
	player.weapons.clear()
	for wid in ["sentry", "hound", "skel_army", "corpse_blast", "melee_axe", "shield_bash"]:
		player.add_weapon(wid)
		(player.weapons[player.weapons.size() - 1] as Dictionary)["lv"] = 8
	player._recalc()
	for i in range(10):
		_main._spawn_enemy("slime", 1.0, 1.0, false)
		_main._spawn_enemy("bat", 1.0, 1.0, false)
	_main._spawn_enemy("brute", 2.0, 1.0, true)
	await _wait(6.0)
	await _unpause()
	await _shot("01_new_weapons_summon_fight")
	print("summons alive: ", get_nodes_in_group("summons").size(),
		" corpses: ", get_nodes_in_group("corpses").size())
	# 场景2:超武合成金色选项（sentry Lv8 + cooldown Lv5）
	player.passives["cooldown"] = 5
	var opts: Array = player.build_levelup_options()
	var has_synth := false
	for o in opts:
		if String(o["type"]) == "synthesize":
			has_synth = true
			break
	print("options types: ", opts.map(func(o: Dictionary) -> String: return String(o["type"])))
	if not has_synth:
		push_error("MISSING synthesize option")
		errs += 1
	hud.show_levelup(opts)
	await _wait(1.2)
	await _shot("02_synthesize_golden_option")
	# 场景3:合成超武并释放（歼灭矩阵）
	var sidx := -1
	for i in range(opts.size()):
		if String(opts[i]["type"]) == "synthesize":
			sidx = i
			break
	if sidx >= 0:
		hud._on_upgrade_btn(sidx)
		await _wait(1.5)
		for i in range(8):
			_main._spawn_enemy("slime", 1.0, 1.0, false)
		await _wait(4.0)
		await _unpause()
		await _shot("03_superweapon_annihilation")
		print("weapon ids: ", player.weapons.map(func(w: Dictionary) -> String: return String(w["id"])))
	else:
		errs += 1
	# 场景4:技能释放（陨石+践踏+闪现连放）
	player.add_skill("meteor")
	player.add_skill("holy_shield")
	var sk0: Dictionary = player.skills[0]
	sk0["lv"] = 3
	player.try_cast_skill(0)  # arrow_rain
	player._cast_meteor(3)
	player._cast_stomp(3)
	await _wait(2.5)
	await _unpause()
	await _shot("04_skills_cast")
	# 场景5:第10层 Boss（先清掉可能卡住的升级暂停）
	await _unpause()
	_main.floor_num = 9
	_main.next_floor()
	await _wait(3.0)
	print("paused=", self.paused, " boss_ref=", _main.get("_boss_ref"))
	await _unpause()
	await _shot("05_floor10_boss")
	await _wait(2.0)
	await _unpause()
	await _shot("06_floor10_boss_fight")
	var bref: Node = _main.get("_boss_ref")
	print("boss alive: ", is_instance_valid(bref) and not bool(bref.get("dead")),
		" enemies: ", get_nodes_in_group("enemies").size())
	print("capture_v03 done, script errors: %d, elapsed %dms" % [errs, Time.get_ticks_msec() - _t0])
	quit(0)


func _unpause() -> void:
	self.paused = false
	var hud := _main.get("hud") as CanvasLayer
	if hud != null:
		var lv_overlay: Control = hud.get("_levelup_overlay")
		if lv_overlay != null:
			lv_overlay.visible = false
	await process_frame


func _wait(sec: float) -> void:
	var start := Time.get_ticks_msec()
	while float(Time.get_ticks_msec() - start) / 1000.0 < sec:
		await process_frame


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	var img := root.get_texture().get_image()
	var path := "%s/%s.png" % [OUT, name]
	var err := img.save_png(path)
	print("saved ", path, " err=", err, " paused=", self.paused)
