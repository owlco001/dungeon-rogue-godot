extends SceneTree
## v0.8 无头门禁驱动（真实场景入口 + 按钮驱动，同 capture_* 模式）。
## 用法：godot --headless --audio-driver Dummy --path . --script res://test/auto_v08.gd -- <mode>
## mode: v2（启动基线） | v3（存档往返） | v5/v7/v8/v9 后续批次补齐
## 结果逐行写入 res://test/result.txt，退出码 0=全 PASS。

var _lines: Array[String] = []
var _fail := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var mode := "v2"
	if args.size() > 0:
		mode = String(args[0]).to_lower()
	_run.call_deferred(mode)

func _check(cname: String, ok: bool, detail := "") -> void:
	var line := ("PASS " if ok else "FAIL ") + cname + (" | " + detail if detail != "" else "")
	_lines.append(line)
	if not ok:
		_fail += 1
	print(line)

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

func _flush() -> void:
	var f := FileAccess.open("res://test/result.txt", FileAccess.WRITE)
	if f != null:
		for l in _lines:
			f.store_line(l)
		f.close()

func _run(mode: String) -> void:
	match mode:
		"v3":
			await _v3()
		"v3setup":
			_v3setup()
		"v3check":
			_v3check()
		"v2":
			await _v2()
		_:
			_check("MODE", false, "unknown mode " + mode)
	_flush()
	quit(1 if _fail > 0 else 0)

# ---- V2：大厅 → 出战 → 艾拉开局 → 第 1 层基线 ----
func _v2() -> void:
	Lang.set_lang("zh")
	var inst: Node = load("res://scenes/lobby.tscn").instantiate()
	root.add_child(inst)
	await _wait(1.2)
	var tab := _find_btn(inst, ["出战", "Battle"])
	_check("V2 lobby fight tab", tab != null)
	if tab == null:
		return
	tab.pressed.emit()
	await _wait(0.6)
	var btn := _find_btn(inst, ["开始战斗", "Start"])
	_check("V2 start button", btn != null)
	if btn == null:
		return
	btn.pressed.emit()
	var game: Node = null
	for i in range(50):
		await _wait(0.1)
		game = get_first_node_in_group("game")
		if game != null:
			break
	_check("V2 entered battle", game != null)
	if game == null:
		return
	# 敌人数量取最初 0.3s 内的最大值（避开自动攻击击杀干扰）
	var expected := 0
	for k in GameData.floor_comp(1).keys():
		expected += int(GameData.floor_comp(1)[k])
	var max_seen := 0
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 300:
		await process_frame
		max_seen = maxi(max_seen, get_nodes_in_group("enemies").size())
	_check("V2 floor1 enemies", max_seen == expected, "seen=%d expected=%d" % [max_seen, expected])
	var player := get_first_node_in_group("player")
	_check("V2 player exists", player != null)
	if player != null:
		_check("V2 player alive", float(player.get("hp")) > 0.0, "hp=%s" % str(player.get("hp")))
	await _wait(1.0)
	_check("V2 battle stable 1s", get_first_node_in_group("game") != null)

# ---- V3：中途存档往返 + 损坏不崩溃 + .bak 恢复 + 版本门 + Meta 节流/版本 ----
func _v3() -> void:
	RunSave.clear()
	_check("V3 clear -> no save", not RunSave.has_save())
	var data := {"char_id": "aila", "floor_num": 3, "hp": 77.0, "gold": 123, "kills": 45}
	_check("V3 save_run ok", RunSave.save_run(data))
	_check("V3 has_save", RunSave.has_save())
	var back := RunSave.load_run()
	_check("V3 roundtrip floor", int(back.get("floor_num", 0)) == 3)
	_check("V3 roundtrip gold", int(back.get("gold", 0)) == 123)
	_check("V3 roundtrip char", String(back.get("char_id", "")) == "aila")
	# 再存一次（.bak = 上一版 floor 3），写坏主档 → 应从 .bak 恢复 floor 3
	var data2 := {"char_id": "aila", "floor_num": 5, "hp": 10.0, "gold": 999, "kills": 60}
	RunSave.save_run(data2)
	_corrupt_file(OS.get_user_data_dir() + "/run_save.cfg")
	var rec := RunSave.load_run()
	_check("V3 corrupt main -> bak recovery", int(rec.get("floor_num", 0)) == 3, "got floor=%s" % str(rec.get("floor_num")))
	# 无 version 的旧格式档 → 版本门拒绝（bak 已随 clear 清掉）
	RunSave.clear()
	var legacy := ConfigFile.new()
	legacy.set_value("run", "floor_num", 9)
	legacy.save(RunSave.SAVE_PATH)
	_check("V3 no-version -> rejected", RunSave.load_run().is_empty())
	# 写坏文件 → load 返回空、不崩溃
	_corrupt_file(OS.get_user_data_dir() + "/run_save.cfg")
	_check("V3 corrupt -> empty", RunSave.load_run().is_empty())
	RunSave.clear()
	_check("V3 final clear", not RunSave.has_save())
	# Meta：节流写（add_gold 只标脏，0.5s 后 SaveService 合并落盘）
	var g0 := Meta.gold()
	Meta.add_gold(5)
	await _wait(0.8)
	var disk := ConfigFile.new()
	_check("V3 meta throttled flush", disk.load(Meta.SAVE_PATH) == OK and int(disk.get_value("meta", "gold", -1)) == g0 + 5,
		"disk gold=%s want=%d" % [str(disk.get_value("meta", "gold", -1)), g0 + 5])
	_check("V3 meta version stamped", int(disk.get_value("meta", "version", 0)) == 3)
	Meta.save_data_now()
	_check("V3 meta bak exists", FileAccess.file_exists(Meta.SAVE_PATH + ".bak"))
	Meta.add_gold(-5)
	Meta.save_data_now()

func _corrupt_file(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string("###corrupt###\nnot-a-config[[[%%%")
		f.close()

# ---- V3 跨进程：setup 写好 main+bak 后写坏主档；check 在新进程验证从 .bak 恢复 ----
func _v3setup() -> void:
	var dir := OS.get_user_data_dir()
	for suffix in ["", ".bak"]:
		var p: String = dir + "/savegame.cfg" + suffix
		if FileAccess.file_exists(p):
			DirAccess.rename_absolute(p, p + ".v3bak")
	Meta.add_gold(777)
	Meta.save_data_now()
	Meta.save_data_now()
	_corrupt_file(dir + "/savegame.cfg")
	_check("V3SETUP files ready", FileAccess.file_exists(dir + "/savegame.cfg.bak"))

func _v3check() -> void:
	var g := Meta.gold()
	_check("V3 meta bak recovery gold", g == 777, "gold=%d" % g)
	_check("V3 meta recovery toast", Meta.pop_migration_toast() != "")
	# 清理并恢复原存档
	var dir := OS.get_user_data_dir()
	for suffix in ["", ".bak", ".corrupt", ".tmp"]:
		var p: String = dir + "/savegame.cfg" + suffix
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	for suffix in ["", ".bak"]:
		var p: String = dir + "/savegame.cfg" + suffix + ".v3bak"
		if FileAccess.file_exists(p):
			DirAccess.rename_absolute(p, dir + "/savegame.cfg" + suffix)
