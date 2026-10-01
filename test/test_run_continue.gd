extends SceneTree
## 测试继续：设置 pending_continue -> 加载 main -> 验证状态恢复
func _initialize() -> void:
	root.size = Vector2i(960, 640)
	# 模拟一个存档
	RunSave.pending_continue = {
		"char_id": "aila",
		"floor_num": 5,
		"hp": 75.0, "max_hp": 120.0,
		"level": 8, "xp": 300,
		"run_gold": 500,
		"kills": 150, "elite_kills": 5, "boss_kills": 1,
		"run_time": 600.0, "endless": false,
		"weapons": [{"id": "bow", "lv": 5, "cd_t": 0.0}],
		"passives": {"attack": 3},
		"relics": ["wardrum"],
		"skills": [{"id": "arrow_rain", "lv": 2, "cd_t": 0.0}],
	}
	var inst: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(inst)
	_run.call_deferred()
func _wait(secs: float) -> void:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < int(secs * 1000.0):
		await process_frame
func _run() -> void:
	await _wait(4.0)
	var main := root.get_child(-1)
	print("floor_num: ", main.floor_num, " (expect 5)")
	print("player level: ", main.player.level, " (expect 8)")
	print("player hp: ", main.player.hp, " (expect 75)")
	print("player weapons: ", main.player.weapons.size(), " (expect 1)")
	print("player relics: ", main.player.relics, " (expect [wardrum])")
	quit()
