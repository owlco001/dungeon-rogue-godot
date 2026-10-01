extends SceneTree
## 测试中途存档：开局 -> 存档 -> 验证文件存在
func _initialize() -> void:
	root.size = Vector2i(960, 640)
	var inst: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(inst)
	_run.call_deferred()
func _wait(secs: float) -> void:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < int(secs * 1000.0):
		await process_frame
func _find_btn(node: Node, text: String) -> Button:
	if node is Button and node.text == text:
		return node
	for c in node.get_children():
		var r := _find_btn(c, text)
		if r != null:
			return r
	return null
func _run() -> void:
	await _wait(2.0)
	var btn := _find_btn(root, "开始")
	if btn:
		btn.pressed.emit()
		print("game started")
	await _wait(3.0)
	# 点存档按钮
	var save_btn := _find_btn(root, "存档")
	if save_btn:
		print("save button found, pressing")
		# 注意：存档会切换场景，这里只测试 save_run()
		var main := root.get_child(-1)
		var ok: bool = main.save_run()
		print("save_run result: ", ok)
		print("has_save: ", RunSave.has_save())
		print("summary: ", RunSave.summary())
	else:
		print("save button NOT FOUND")
	quit()
