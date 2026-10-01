extends SceneTree
## i18n capture: -- en | zh. Lobby (top + fight tab) and battle HUD screenshots.
## Run: xvfb-run godot --rendering-driver opengl3 --audio-driver Dummy --path . --script res://test/capture_i18n.gd -- en

const OUT := "/tmp/i18n_cap"

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var args := OS.get_cmdline_user_args()
	var lang := "zh"
	if args.size() > 0:
		lang = String(args[0])
	Lang.set_lang(lang)
	print("LANG=", Lang.current())
	# unit checks
	print("T1: ", Lang.t("地牢肉鸽"))
	print("T2: ", Lang.t("第%d层·%s") % [3, Lang.t("寒冰洞窟")])
	print("T3: ", Lang.t("无尽Boss:深渊主宰·墨骸"))
	print("T4: ", Lang.t("加特林·3轮"))
	print("T5: ", Lang.t("金币 128"))
	root.size = Vector2i(390, 844)
	var inst: Node = load("res://scenes/lobby.tscn").instantiate()
	root.add_child(inst)
	_run.call_deferred(lang)

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

func _find_btn(node: Node, texts: Array) -> Button:
	if node is Button:
		for t in texts:
			if String(t) in node.text:
				return node
	for c in node.get_children():
		var r := _find_btn(c, texts)
		if r != null:
			return r
	return null

func _run(lang: String) -> void:
	await _wait(1.2)
	await _shot("lobby_" + lang)
	var lobby := root.get_child(-1)
	var tab := _find_btn(lobby, ["Battle", "出战"])
	if tab != null:
		tab.pressed.emit()
		await _wait(0.8)
		await _shot("lobby_fight_" + lang)
	var btn := _find_btn(lobby, ["开始", "Start"])
	if btn != null:
		btn.pressed.emit()
		await _wait(2.5)
		await _shot("battle_" + lang)
	else:
		print("NO START BTN")
	quit()