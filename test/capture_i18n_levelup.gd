extends SceneTree
## i18n levelup capture: force the level-up draft UI in EN and print option texts.
const OUT := "/tmp/i18n_cap"

func _initialize() -> void:
	Lang.set_lang("en")
	root.size = Vector2i(960, 640)
	var inst: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(inst)
	_run.call_deferred()

func _wait(secs: float) -> void:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < int(secs * 1000.0):
		await process_frame

func _find_btn(node: Node, text: String) -> Button:
	if node is Button and text in node.text:
		return node
	for c in node.get_children():
		var r := _find_btn(c, text)
		if r != null:
			return r
	return null

func _run() -> void:
	await _wait(2.0)
	var btn := _find_btn(root, "Start")
	if btn != null:
		btn.pressed.emit()
	await _wait(2.0)
	var main = root.get_child(-1)
	var player = main.get("player")
	var hud = main.get("hud")
	var opts: Array = player.build_levelup_options()
	for o in opts:
		print("OPT: ", String(o.get("title", "")), " | ", String(o.get("desc", "")))
	hud.show_levelup(opts)
	await _wait(0.8)
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(OUT + "/levelup_en.png")
	print("shot: levelup_en")
	quit()
