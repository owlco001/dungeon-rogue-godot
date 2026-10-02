extends SceneTree

const RG := preload("res://systems/room_gen.gd")
const PF := preload("res://systems/pathfind.gd")
const TG := preload("res://systems/terrain.gd")
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
		"v9d":
			await _v9d()
		"v10":
			await _v10()
		"v11":
			await _v11()
		"v13":
			await _v13()
		"v14":
			await _v14()
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
	var waves_on := bool(ProjectSettings.get_setting("dungeon/waves_enabled", true))
	var expected := 0
	if waves_on:
		# L3 波次制：进场只有第一波（60/25/15 按兵种 round）
		expected = (WaveDirector.split_waves(GameData.floor_comp(1), GameData.elite_assignment(1))[0] as Array).size()
	else:
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
	_check("V9 count f1=10", GameData.floor_count(1) == 10, "got %d" % GameData.floor_count(1))
	_check("V9 count f29=72", GameData.floor_count(29) == 72, "got %d" % GameData.floor_count(29))
	_check("V9 count f60=80 cap", GameData.floor_count(60) == 80, "got %d" % GameData.floor_count(60))
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
	# 团灭时存活数 == reg_n2（波次制下小于整层数）
	_check("V7 enemy pool recycles", ep >= maxi(1, reg_n2), "enemy pool=%d killed=%d" % [ep, reg_n2])
	_check("V7 registry drained", (reg.get("enemies") as Array).is_empty(),
		"left=%d" % (reg.get("enemies") as Array).size())

# ---- V10（B7）：房间复现/连通/寻路 + 实战卡墙率 ----
func _v10() -> void:
	Lang.set_lang("zh")
	var a = RG.new()
	a.generate(12345)
	var b = RG.new()
	b.generate(12345)
	_check("V10 same-seed reproducible", a.grid == b.grid and a.rooms.size() == b.rooms.size())
	# 连通性：中心大厅洪泛填充到全部房间中心
	var seen := {}
	var queue: Array = [Vector2i(RG.GW / 2, RG.GH / 2)]
	seen[queue[0]] = true
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		for dd in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nb: Vector2i = c + dd
			if nb.x < 0 or nb.y < 0 or nb.x >= RG.GW or nb.y >= RG.GH:
				continue
			if not seen.has(nb) and a.pf_grid[nb.y * RG.GW + nb.x] == 0:
				seen[nb] = true
				queue.append(nb)
	var reached := 0
	for r in a.rooms:
		var c := Vector2i(int(r["x"]) + int(r["w"]) / 2, int(r["y"]) + int(r["h"]) / 2)
		if seen.has(c):
			reached += 1
	_check("V10 all rooms connected", reached == a.rooms.size(),
		"reached=%d rooms=%d" % [reached, a.rooms.size()])
	# 寻路存在性：50 对随机地面格
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var floors: Array = []
	for y in range(RG.GH):
		for x in range(RG.GW):
			if a.pf_grid[y * RG.GW + x] == 0:
				floors.append(Vector2i(x, y))
	var ok_paths := 0
	for i in range(50):
		var c1: Vector2i = floors[rng.randi_range(0, floors.size() - 1)]
		var c2: Vector2i = floors[rng.randi_range(0, floors.size() - 1)]
		var path: PackedVector2Array = PF.find_path(a.pf_grid, RG.GW, RG.GH,
			Vector2((float(c1.x) + 0.5) * RG.CELL, (float(c1.y) + 0.5) * RG.CELL),
			Vector2((float(c2.x) + 0.5) * RG.CELL, (float(c2.y) + 0.5) * RG.CELL), RG.CELL)
		if path.size() >= 2:
			ok_paths += 1
	_check("V10 paths exist for 50 pairs", ok_paths == 50, "ok=%d" % ok_paths)
	# 实战卡墙：进第 1 层，额外刷 8 只怪，4s 后须移动或已接近玩家
	var inst: Node = load("res://scenes/lobby.tscn").instantiate()
	root.add_child(inst)
	await _wait(1.0)
	var tab := _find_btn(inst, ["出战", "Battle"])
	if tab == null:
		_check("V10 entry", false)
		return
	tab.pressed.emit()
	await _wait(0.5)
	var btn := _find_btn(inst, ["开始战斗", "Start"])
	if btn == null:
		_check("V10 start", false)
		return
	btn.pressed.emit()
	var main: Node = null
	for i in range(50):
		await _wait(0.1)
		main = get_first_node_in_group("game")
		if main != null:
			break
	if main == null:
		_check("V10 in battle", false)
		return
	await _wait(0.5)
	for i in range(8):
		main.call("_spawn_enemy", "slime", 1.0, 1.0, false)
	await _wait(0.3)
	var snap := {}
	for e in get_nodes_in_group("enemies"):
		snap[e.get_instance_id()] = e.global_position
	await _wait(4.0)
	var pl: Node = get_first_node_in_group("player")
	var stuck := 0
	var checked := 0
	for e in get_nodes_in_group("enemies"):
		if not snap.has(e.get_instance_id()):
			continue
		checked += 1
		var moved: float = e.global_position.distance_to(snap[e.get_instance_id()])
		var near: bool = pl != null and is_instance_valid(pl) \
			and e.global_position.distance_to(pl.global_position) < 220.0
		if moved < 40.0 and not near:
			stuck += 1
	_check("V10 stuck rate < 1%", checked > 0 and stuck == 0,
		"checked=%d stuck=%d" % [checked, stuck])


# ---- V11（v0.8.5）：地形生成确定性/合法性 + 实战效果（敌人碎石减速、玩家熔岩烫伤） ----
func _v11() -> void:
	Lang.set_lang("zh")
	var room = RG.new()
	room.generate(12345)
	var center := Vector2(RG.GW * RG.CELL * 0.5, RG.GH * RG.CELL * 0.5)
	var reserved: Array = [center, room.farthest_room_center(center), room.farthest_room_center(center, true)]
	var p1: Array = TG.generate("forge", 2, room.pf_grid, reserved, 6)
	var p2: Array = TG.generate("forge", 2, room.pf_grid, reserved, 6)
	_check("V11 terrain generated", p1.size() >= 3, "patches=%d" % p1.size())
	var keys1 := {}
	for patch in p1:
		for c in patch["cells"]:
			keys1[TG.cell_key(c)] = true
	var keys2 := {}
	for patch in p2:
		for c in patch["cells"]:
			keys2[TG.cell_key(c)] = true
	_check("V11 same-seed reproducible", keys1 == keys2, "cells=%d" % keys1.size())
	var legal := true
	for patch in p1:
		for c in patch["cells"]:
			if room.pf_grid[c.y * RG.GW + c.x] != 0:
				legal = false
			var cp := TG.cell_center(c)
			for r in reserved:
				if cp.distance_to(r) < 135.0:
					legal = false
	_check("V11 cells walkable & reserved-clear", legal)
	# 六主题在开放网格上都能出地形且 id 正确
	var open_grid := PackedByteArray()
	open_grid.resize(RG.GW * RG.GH)
	open_grid.fill(0)
	var ids_ok := true
	for theme in ["corridor", "forge", "ice", "tomb", "thorn", "void"]:
		var ps: Array = TG.generate(theme, 7, open_grid, [center], 5)
		if ps.is_empty() or String(ps[0].get("id", "")) != String(TG.profile_for(theme).get("id", "")):
			ids_ok = false
	_check("V11 six themes produce patches", ids_ok)
	if not p1.is_empty():
		var at: Dictionary = TG.patch_at(p1, p1[0]["center"])
		_check("V11 patch_at hits", String(at.get("id", "")) == "lava")
	# 实战：进第 1 层（回廊=碎石），敌人站碎石上应被写入 0.75 倍速
	var inst: Node = load("res://scenes/lobby.tscn").instantiate()
	root.add_child(inst)
	await _wait(1.0)
	var tab := _find_btn(inst, ["出战", "Battle"])
	if tab == null:
		_check("V11 entry", false, "no fight tab")
		return
	tab.pressed.emit()
	await _wait(0.5)
	var btn := _find_btn(inst, ["开始战斗", "Start"])
	if btn == null:
		_check("V11 start", false, "no start btn")
		return
	btn.pressed.emit()
	var main: Node = null
	for i in range(50):
		await _wait(0.1)
		main = get_first_node_in_group("game")
		if main != null:
			break
	_check("V11 in battle", main != null)
	if main == null:
		return
	await _wait(0.5)
	var patches: Array = main.get("_terrain_patches")
	_check("V11 live patches exist", patches.size() >= 3, "n=%d" % patches.size())
	if patches.is_empty():
		return
	var player := get_first_node_in_group("player")
	main.call("_spawn_enemy", "slime", 1.0, 1.0, false)
	await _wait(0.2)
	var slime: Node = null
	for e in get_nodes_in_group("enemies"):
		slime = e  # 刚刷出的在组内顺序靠后；逐个试站位，找到被写减速的即可
		e.global_position = patches[0]["center"]
		await _wait(0.35)
		if absf(float(e.get("terrain_speed_mult")) - 0.75) < 0.01:
			slime = e
			break
	_check("V11 enemy slowed on rubble", slime != null
		and absf(float(slime.get("terrain_speed_mult")) - 0.75) < 0.01,
		"mult=%s" % str(slime.get("terrain_speed_mult") if slime != null else -1))
	# 玩家熔岩烫伤：清场后切熔炉地形，把玩家放到熔岩块中心
	main.call("_clear_minions")
	await _wait(0.3)
	main.call("_build_terrain", "forge")
	await _wait(0.2)
	var fpatches: Array = main.get("_terrain_patches")
	_check("V11 forge rebuild", not fpatches.is_empty() and String(fpatches[0].get("id", "")) == "lava")
	if fpatches.is_empty() or player == null:
		return
	player.global_position = fpatches[0]["center"]
	player.set("velocity", Vector2.ZERO)
	var hp0 := float(player.get("hp"))
	await _wait(1.3)
	_check("V11 player on lava id", String(player.get("terrain_id")) == "lava",
		"id=%s" % str(player.get("terrain_id")))
	_check("V11 player lava dps", float(player.get("hp")) <= hp0 - 2.0,
		"hp %s -> %s" % [str(hp0), str(player.get("hp"))])


# ---- V9d（B6）：波次拆分数学 + 实战波次/计时断言 ----
func _v9d() -> void:
	Lang.set_lang("zh")
	var comp29: Dictionary = GameData.floor_comp(29)
	var waves29: Array = WaveDirector.split_waves(comp29, GameData.elite_assignment(29))
	var total := 0
	var sizes: Array = []
	for wv in waves29:
		sizes.append((wv as Array).size())
		total += (wv as Array).size()
	var count29 := 0
	for k in comp29.keys():
		count29 += int(comp29[k])
	_check("V9d split sums to floor count", total == count29, "total=%d count=%d" % [total, count29])
	_check("V9d wave1 ~= 60%", absf(float(sizes[0]) / float(count29) - 0.6) < 0.08, "w1=%d" % sizes[0])
	_check("V9d wave2 ~= 25%", absf(float(sizes[1]) / float(count29) - 0.25) < 0.08, "w2=%d" % sizes[1])
	_check("V9d wave3 ~= 15%", absf(float(sizes[2]) / float(count29) - 0.15) < 0.08, "w3=%d" % sizes[2])
	# 实战
	var inst: Node = load("res://scenes/lobby.tscn").instantiate()
	root.add_child(inst)
	await _wait(1.0)
	var tab := _find_btn(inst, ["出战", "Battle"])
	_check("V9d entry", tab != null)
	if tab == null:
		return
	tab.pressed.emit()
	await _wait(0.5)
	var btn := _find_btn(inst, ["开始战斗", "Start"])
	_check("V9d start", btn != null)
	if btn == null:
		return
	btn.pressed.emit()
	var main: Node = null
	for i in range(50):
		await _wait(0.1)
		main = get_first_node_in_group("game")
		if main != null:
			break
	_check("V9d in battle", main != null)
	if main == null:
		return
	await _wait(0.5)
	var dir: Node = main.get("_director")
	_check("V9d director active", dir != null and bool(dir.get("active")))
	var w1: int = (WaveDirector.split_waves(GameData.floor_comp(1), GameData.elite_assignment(1))[0] as Array).size()
	# 实战有自动开火，计数允许 ±1 击杀时差
	_check("V9d wave1 spawned", abs(int(main.call("_enemies_alive")) - w1) <= 1,
		"alive=%d want=%d" % [int(main.call("_enemies_alive")), w1])
	dir.call("debug_force_time_up")
	await _wait(0.8)
	_check("V9d stairs on timeout", main.get("_stairs") != null)


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


# ---- V13：流派亲和选秀权重（v0.8.13） ----
# 艾拉单亲和 gun（池 5/19，期望 ~47%）断言 ≥40%；墨菲双亲和 necro+summon
# （池 9/19，期望 ~64%）断言 ≥58%。不实际选取，只统计选秀分布。
func _v13() -> void:
	Lang.set_lang("zh")
	var inst: Node = load("res://scenes/lobby.tscn").instantiate()
	root.add_child(inst)
	await _wait(1.0)
	var tab := _find_btn(inst, ["出战", "Battle"])
	_check("V13 entry", tab != null, "no fight tab")
	if tab == null:
		return
	tab.pressed.emit()
	await _wait(0.5)
	var btn := _find_btn(inst, ["开始战斗", "Start"])
	_check("V13 start", btn != null, "no start btn")
	if btn == null:
		return
	btn.pressed.emit()
	var player: Node = null
	for i in range(50):
		await _wait(0.1)
		player = get_first_node_in_group("player")
		if player != null:
			break
	_check("V13 player", player != null)
	if player == null:
		return
	# 默认角色即艾拉（gun 单亲和）。注意无头环境 Meta 为默认解锁 7 把
	# （gun×4：dual/shotgun/sniper/gatling；summon×1 sentry；necro×1 corpse_blast；
	# melee×1 melee_axe），期望 gun 占比 = 10/13 ≈ 77%
	_v13_measure(player, "ella", ["gun"], 0.70)
	# 切墨菲（necro+summon 双亲和；期望 4/9 ≈ 44%，无加权基线仅 2/7 ≈ 29%）
	player.set("character_id", "mofei")
	player.set("char_def", GameData.CHARACTERS["mofei"])
	_v13_measure(player, "mofei", ["necro", "summon"], 0.38)


func _v13_measure(player: Node, who: String, schools: Array, min_share: float) -> void:
	var skills0: Array = (player.get("skills") as Array).duplicate(true)
	var aff_n := 0
	var total := 0
	var mark_seen := false
	for run in range(20):
		seed(9000 + run)
		for step in range(20):
			player.set("weapons", [{"id": "bow", "lv": 1, "cd_t": 0.0}])
			player.set("passives", {})
			player.set("skills", skills0.duplicate(true))
			player.set("_lvup_count", 99)
			player.set("_lvups_since_passive", 0)
			player.set("_funnel_weapon", "")
			player.call("_recalc")
			var opts: Array = player.call("build_levelup_options")
			if opts.is_empty():
				break
			# 只统计新武器选项：weapon_up 必然是已持有的弓（稀释统计，排除）
			for o in opts:
				if String(o["type"]) != "new_weapon":
					continue
				total += 1
				var wid := String(o["id"])
				var d: Dictionary = GameData.WEAPONS.get(GameData.base_weapon_of(wid), {})
				if String(d.get("school", "")) in schools:
					aff_n += 1
					if String(o["title"]).contains("亲和"):
						mark_seen = true
	var share := 0.0
	if total > 0:
		share = float(aff_n) / float(total)
	_check("V13 %s affinity draft share>=%.2f" % [who, min_share], share >= min_share,
		"share=%.3f n=%d" % [share, total])
	_check("V13 %s affinity mark shown" % who, mark_seen, "title has 亲和")


## V14：超武流派联动 —— 亲和超武伤害 ×1.265（1.15×1.10），非亲和超武不变；合成选项带"·亲和超武"标记
func _v14() -> void:
	Lang.set_lang("zh")
	var inst: Node = load("res://scenes/lobby.tscn").instantiate()
	root.add_child(inst)
	await _wait(1.0)
	var tab := _find_btn(inst, ["出战", "Battle"])
	if tab == null:
		_check("V14 entry", false, "no fight tab")
		return
	tab.pressed.emit()
	await _wait(0.5)
	var btn := _find_btn(inst, ["开始战斗", "Start"])
	if btn == null:
		_check("V14 start", false, "no start btn")
		return
	btn.pressed.emit()
	var player: Node = null
	for i in range(50):
		await _wait(0.1)
		player = get_first_node_in_group("player")
		if player != null:
			break
	_check("V14 player", player != null)
	if player == null:
		return
	var saved: Dictionary = (player.get("char_def") as Dictionary).duplicate()
	var noaff: Dictionary = saved.duplicate()
	noaff["affinity"] = []
	# 亲和超武（super_bow：底武器 bow 为 gun，艾拉亲和）应为 1.15×1.10=1.265
	player.set("char_def", noaff)
	var d0: Dictionary = player.call("_wstats", {"id": "super_bow", "lv": 1, "cd_t": 0.0})
	player.set("char_def", saved)
	var d1: Dictionary = player.call("_wstats", {"id": "super_bow", "lv": 1, "cd_t": 0.0})
	var ratio := float(d1["dmg"]) / float(d0["dmg"])
	_check("V14 affinity super dmg x1.265", abs(ratio - 1.265) < 0.001, "ratio=%.4f" % ratio)
	# 非亲和超武（super_melee_axe）不受影响
	var e0: Dictionary = player.call("_wstats", {"id": "super_melee_axe", "lv": 1, "cd_t": 0.0})
	player.set("char_def", noaff)
	var e1: Dictionary = player.call("_wstats", {"id": "super_melee_axe", "lv": 1, "cd_t": 0.0})
	player.set("char_def", saved)
	var ratio2 := float(e0["dmg"]) / float(e1["dmg"])
	_check("V14 non-affinity super unchanged", abs(ratio2 - 1.0) < 0.001, "ratio=%.4f" % ratio2)
	# 合成选项标记：bow Lv8 + aspeed Lv5 → 合成选项标题带"·亲和超武"
	player.set("weapons", [{"id": "bow", "lv": 8, "cd_t": 0.0}])
	player.set("passives", {"aspeed": 5})
	player.set("skills", [])
	player.set("_lvup_count", 99)
	player.set("_lvups_since_passive", 0)
	player.set("_funnel_weapon", "")
	player.call("_recalc")
	var opts: Array = player.call("build_levelup_options")
	var mark_ok := false
	for o in opts:
		if String(o["type"]) == "synthesize" and String(o["id"]) == "bow":
			if String(o["title"]).contains("亲和超武"):
				mark_ok = true
	_check("V14 synthesize affinity mark", mark_ok, "title has 亲和超武")
