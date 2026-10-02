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
		"v5h":
			await _v5h()
		"v8":
			await _v8()
		"v9":
			_v9()
		"v7":
			await _v7()
		"v5":
			await _v5()
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
	var cdb := root.get_node_or_null("ContentDB")
	var wsum := 0
	if cdb != null:
		var w: Dictionary = cdb.call("table", "levelup").get("weights", {})
		for k in w.keys():
			wsum += int(w[k])
	_check("B1 ContentDB levelup weights", cdb != null and wsum == 100, "sum=%d" % wsum)
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

# ---- V5 局部（B1）：hitstop 双通道契约 ----
func _v5h() -> void:
	Engine.time_scale = 1.0
	var fx = load("res://scripts/fx.gd")  # 运行时加载：fx.gd 引用 Sfx autoload，不能进驱动的早期编译图
	fx.hitstop(self, 0.05)
	_check("V5H A micro-freeze 0.35", absf(Engine.time_scale - 0.35) < 0.01, "ts=%s" % str(Engine.time_scale))
	await _wait(0.25)
	_check("V5H A restored >=0.95", Engine.time_scale >= 0.95, "ts=%s" % str(Engine.time_scale))
	# 冷却：0.15s 窗口内第二次触发被丢弃 → 总冻结时长不叠加
	fx.hitstop(self, 0.05)
	await _wait(0.02)
	fx.hitstop(self, 0.05)
	await _wait(0.12)
	_check("V5H A cooldown no-stack", Engine.time_scale >= 0.95, "ts=%s" % str(Engine.time_scale))
	# 演出通道：独占 0.05，期间打击通道静默，结束后恢复
	fx.hitstop(self, 0.3, true)
	_check("V5H B cine 0.05", absf(Engine.time_scale - 0.05) < 0.01, "ts=%s" % str(Engine.time_scale))
	fx.hitstop(self, 0.05)
	_check("V5H A silent during B", absf(Engine.time_scale - 0.05) < 0.01, "ts=%s" % str(Engine.time_scale))
	await _wait(0.5)
	_check("V5H B restored >=0.95", Engine.time_scale >= 0.95, "ts=%s" % str(Engine.time_scale))

# ---- V8 合成判据（A-1/A-6）：固定 seed 10 局 × 33 次升级，定向策略跟随推荐/焦点武器 ----
func _v8() -> void:
	Lang.set_lang("zh")
	var inst: Node = load("res://scenes/lobby.tscn").instantiate()
	root.add_child(inst)
	await _wait(1.0)
	var tab := _find_btn(inst, ["出战", "Battle"])
	if tab == null:
		_check("V8 entry", false, "no fight tab")
		return
	tab.pressed.emit()
	await _wait(0.5)
	var btn := _find_btn(inst, ["开始战斗", "Start"])
	if btn == null:
		_check("V8 entry", false, "no start btn")
		return
	btn.pressed.emit()
	var player: Node = null
	for i in range(50):
		await _wait(0.1)
		player = get_first_node_in_group("player")
		if player != null:
			break
	_check("V8 entry", player != null)
	if player == null:
		return
	var skills0: Array = (player.get("skills") as Array).duplicate(true)
	var synth_runs := 0
	var offered := {}
	var offered_total := 0
	for run in range(10):
		seed(4200 + run)
		player.set("weapons", [{"id": "bow", "lv": 1, "cd_t": 0.0}])
		player.set("passives", {})
		player.set("skills", skills0.duplicate(true))
		player.set("_lvup_count", 0)
		player.set("_lvups_since_passive", 0)
		player.set("_funnel_weapon", "")
		player.call("_recalc")
		var got_super := false
		for step in range(33):
			var opts: Array = player.call("build_levelup_options")
			if opts.is_empty():
				break
			for o in opts:
				var t := String(o["type"])
				offered[t] = int(offered.get(t, 0)) + 1
				offered_total += 1
			var pick: Dictionary = _v8_pick(player, opts)
			player.call("apply_levelup_option", pick)
			for w in player.get("weapons"):
				if GameData.is_super(String(w["id"])):
					got_super = true
			if got_super:
				break
		if got_super:
			synth_runs += 1
		var wtxt := ""
		for w in player.get("weapons"):
			wtxt += "%s:%d " % [String(w["id"]), int(w["lv"])]
		print("V8 run %d super=%s weapons=[%s] passives=%s" % [run, str(got_super), wtxt, str(player.get("passives"))])
	_check("V8 synth runs >=9/10", synth_runs >= 9, "synth_runs=%d" % synth_runs)
	var pshare := 0.0
	if offered_total > 0:
		pshare = float(int(offered.get("new_passive", 0)) + int(offered.get("passive_up", 0))) / float(offered_total)
	_check("V8 passive share 48-62.7%", pshare >= 0.48 and pshare <= 0.627,
		"share=%.3f total=%d dist=%s" % [pshare, offered_total, str(offered)])

## 定向策略（对齐 docs/v08/sim 的 ranking）：合成>焦点武器升级>所需被动>其他武器>新武器>新技能
func _v8_pick(player: Node, opts: Array) -> Dictionary:
	var weapons: Array = player.get("weapons")
	var focus := ""
	for w in weapons:
		if not GameData.is_super(String(w["id"])) and int(w["lv"]) < GameData.WEAPON_MAX_LV:
			focus = String(w["id"])
			break
	if focus == "":
		for w in weapons:
			if not GameData.is_super(String(w["id"])):
				focus = String(w["id"])
				break
	var needp := String(player.call("_funnel_passive_of", focus))
	var best: Dictionary = {}
	var best_rank := 99
	for o in opts:
		var t := String(o["type"])
		var oid := String(o["id"])
		var r := 7
		if t == "synthesize":
			r = 0
		elif t == "weapon_up" and oid == focus:
			r = 1
		elif t == "passive_up" and oid == needp:
			r = 2
		elif t == "new_passive" and oid == needp:
			r = 3
		elif t == "weapon_up":
			r = 4
		elif t == "new_weapon" and weapons.size() < 5:
			r = 5
		elif t == "new_skill":
			r = 6
		if r < best_rank:
			best_rank = r
			best = o
	return best

# ---- V9 静态（B3）：刷怪曲线断言（01 §3.2）----
func _v9() -> void:
	_check("V9 count f1=6", GameData.floor_count(1) == 6, "got %d" % GameData.floor_count(1))
	_check("V9 count f29=44", GameData.floor_count(29) == 44, "got %d" % GameData.floor_count(29))
	_check("V9 count f60=46 cap", GameData.floor_count(60) == 46, "got %d" % GameData.floor_count(60))
	var mono := true
	for f in range(2, 61):
		if GameData.floor_count(f) < GameData.floor_count(f - 1):
			mono = false
	_check("V9 count monotonic 1-60", mono)
	var sums_ok := true
	for f in range(1, 31):
		var s := 0
		for k in GameData.floor_comp(f).keys():
			s += int(GameData.floor_comp(f)[k])
		if s != GameData.floor_count(f):
			sums_ok = false
	_check("V9 comp sums == count", sums_ok)
	_check("V9 elite kind f3=slime", GameData.elite_kind_for(3) == "slime", GameData.elite_kind_for(3))
	_check("V9 elite kind f12=brute", GameData.elite_kind_for(12) == "brute", GameData.elite_kind_for(12))
	# 层总等效 HP：相邻非 Boss 层回落不得超过 10%
	var prev := -1.0
	var worst := 0.0
	var worst_f := 0
	for f in range(1, 31):
		if GameData.is_boss_floor(f):
			continue
		var tot := _floor_total_hp(f)
		if prev > 0.0:
			var drop := (tot - prev) / prev
			if drop < worst:
				worst = drop
				worst_f = f
		prev = tot
	_check("V9 hp drop <=10%", worst >= -0.10, "worst=%.3f at f%d" % [worst, worst_f])

func _floor_total_hp(f: int) -> float:
	var comp := GameData.floor_comp(f)
	var sum := 0.0
	for k in comp.keys():
		sum += float(GameData.ENEMIES[k]["hp"]) * float(int(comp[k]))
	if GameData.is_elite_floor(f):
		var asg := GameData.elite_assignment(f)
		for k in asg.keys():
			sum += float(GameData.ENEMIES[k]["hp"]) * (GameData.elite_hp_mult() - 1.0) * float(int(asg[k]))
	return sum * GameData.enemy_hp_mult(f)

# ---- V7（B4）：EntityRegistry 与组查询一致性 ----
func _v7() -> void:
	Lang.set_lang("zh")
	var inst: Node = load("res://scenes/lobby.tscn").instantiate()
	root.add_child(inst)
	await _wait(1.0)
	var tab := _find_btn(inst, ["出战", "Battle"])
	if tab == null:
		_check("V7 entry", false, "no fight tab")
		return
	tab.pressed.emit()
	await _wait(0.5)
	var btn := _find_btn(inst, ["开始战斗", "Start"])
	if btn == null:
		_check("V7 entry", false, "no start btn")
		return
	btn.pressed.emit()
	var player: Node = null
	for i in range(50):
		await _wait(0.1)
		player = get_first_node_in_group("player")
		if player != null:
			break
	_check("V7 entry", player != null)
	if player == null:
		return
	await _wait(0.5)
	var reg: Node = root.get_node_or_null("Registry")
	_check("V7 registry exists", reg != null)
	if reg == null:
		return
	# 组里包含死亡补间中的敌人，注册表只记存活——按存活数对比（防战斗时序竞态）
	var group_n := 0
	for e in get_nodes_in_group("enemies"):
		if not bool(e.get("dead")):
			group_n += 1
	var reg_n := (reg.get("enemies") as Array).size()
	_check("V7 registry mirrors group", reg_n == group_n, "registry=%d alive_group=%d" % [reg_n, group_n])
	_check("V7 alive_count", int(reg.call("alive_count")) == group_n,
		"alive=%d group=%d" % [int(reg.call("alive_count")), group_n])
	var all_q: Array = reg.call("query_circle", player.global_position, 5000.0)
	_check("V7 query_circle covers all", all_q.size() == group_n, "q=%d group=%d" % [all_q.size(), group_n])
	var near: Node2D = reg.call("nearest", player.global_position, 5000.0)
	_check("V7 nearest found", near != null)
	# 击杀一只存活敌人后注册表应同步减少（_die 注销 + tree_exited 兜底）
	var victim: Node2D = null
	for e in get_nodes_in_group("enemies"):
		if not bool(e.get("dead")):
			victim = e
			break
	victim.call("take_damage", 99999.0, Vector2.ZERO, 0.0)
	await _wait(0.4)
	var reg_n2 := (reg.get("enemies") as Array).size()
	_check("V7 unregister on death", reg_n2 == reg_n - 1, "after=%d before=%d" % [reg_n2, reg_n])
	# FX 六池：直接触发一次特效调用使池按需预建，再断言 164 节点不超额增长
	var fx = load("res://scripts/fx.gd")
	fx.glow(player.get_parent(), player.global_position, 60.0, Color(1, 1, 1, 0.8), 0.2, 5)
	fx.damage_number(player.get_parent(), player.global_position, 7.0, false)
	await _wait(0.8)
	var pool_root := root.get_node_or_null("FXPool")
	_check("V7 fx pool built", pool_root != null)
	if pool_root != null:
		_check("V7 fx pool size 164", pool_root.get_child_count() == 164,
			"children=%d stats=%s parents=%s" % [pool_root.get_child_count(), str(fx.pool_stats()), str(fx.pool_debug_parents())])

	# 实体池：击杀整层后敌人应回收进池（死亡补间结束）而非全部释放
	for e in get_nodes_in_group("enemies"):
		e.call("take_damage", 99999.0, Vector2.ZERO, 0.0)
	await _wait(1.5)
	var pm = load("res://systems/pool_manager.gd")
	var ep := int(pm.pool_size("enemy"))
	_check("V7 enemy pool recycles", ep >= 4, "enemy pool=%d" % ep)
	_check("V7 registry drained", (reg.get("enemies") as Array).is_empty(),
		"left=%d" % (reg.get("enemies") as Array).size())

# ---- V5（B4）：高压战斗采样——节点/粒子上限 + time_scale 恢复 + 帧时 p95（headless 参考） ----
func _v5() -> void:
	Lang.set_lang("zh")
	var inst: Node = load("res://scenes/lobby.tscn").instantiate()
	root.add_child(inst)
	await _wait(1.0)
	var tab := _find_btn(inst, ["出战", "Battle"])
	if tab == null:
		_check("V5 entry", false, "no fight tab")
		return
	tab.pressed.emit()
	await _wait(0.5)
	var btn := _find_btn(inst, ["开始战斗", "Start"])
	if btn == null:
		_check("V5 entry", false, "no start btn")
		return
	btn.pressed.emit()
	var player: Node = null
	for i in range(50):
		await _wait(0.1)
		player = get_first_node_in_group("player")
		if player != null:
			break
	_check("V5 entry", player != null)
	if player == null:
		return
	player.set("max_hp", 100000.0)
	player.set("hp", 100000.0)
	var game := get_first_node_in_group("game")
	game.set("floor_num", 28)
	game.call("next_floor")  # 第 29 层：44 只怪高压
	await _wait(1.0)
	var nodes_max := 0
	var parts_max := 0
	var slow_frames := 0
	var frames := 0
	var durs: Array = []
	var last_us := Time.get_ticks_usec()
	var t_end := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < t_end:
		await process_frame
		var now_us := Time.get_ticks_usec()
		durs.append(float(now_us - last_us) / 1000.0)
		last_us = now_us
		frames += 1
		nodes_max = maxi(nodes_max, get_node_count())
		if frames % 30 == 0:
			parts_max = maxi(parts_max, _particle_total(root))
		if Engine.time_scale < 0.95:
			slow_frames += 1
	durs.sort()
	var p95 := 0.0
	if not durs.is_empty():
		p95 = float(durs[mini(int(float(durs.size()) * 0.95), durs.size() - 1)])
	_check("V5 nodes <=900", nodes_max <= 900, "max=%d" % nodes_max)
	_check("V5 particles <=800", parts_max <= 800, "max=%d" % parts_max)
	_check("V5 timescale recovered", float(slow_frames) / maxf(1.0, float(frames)) <= 0.2,
		"slow=%d/%d p95=%.2fms(headless参考)" % [slow_frames, frames, p95])

func _particle_total(n: Node) -> int:
	var t := 0
	if n is CPUParticles2D and (n as CPUParticles2D).emitting:
		t += (n as CPUParticles2D).amount
	elif n is GPUParticles2D and (n as GPUParticles2D).emitting:
		t += (n as GPUParticles2D).amount
	for c in n.get_children():
		t += _particle_total(c)
	return t

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
