extends SceneTree
## 装备栏详情弹窗位置验证：点第 1 个武器槽，弹窗应出现在槽位右侧而非屏幕中央。
## Run: xvfb-run godot --rendering-driver opengl3 --audio-driver Dummy --path <project> --script res://test/capture_slot_tooltip.gd

const OUT := "/tmp/slot_verify"


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
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _wait(4.0)
	var hud: Node = main.get_node("HUD")
	print("weapons_data size=", hud._weapons_data.size(), " slots=", hud._weapon_slots.size())
	# 模拟点击第 1 个武器槽
	var btn: Button = hud._weapon_slots[0]["btn"]
	print("slot0 global rect=", btn.get_global_rect())
	hud._show_detail("weapon", 0, btn)
	await _wait(0.5)
	print("panel pos=", hud._detail_panel.position, " size=", hud._detail_panel.get_combined_minimum_size())
	await _shot("tooltip_anchored")
	# 再点一个遗物槽（第三行），验证纵向钳制
	if hud._relic_slots.size() > 0:
		var rbtn: Button = hud._relic_slots[0]["btn"]
		hud._show_detail("relic", 0, rbtn)
		await _wait(0.5)
		print("relic panel pos=", hud._detail_panel.position)
		await _shot("tooltip_relic")
	print("DONE")
	quit()
