extends SceneTree
## V4 内容门禁（07 §2.4-5）：静态校验全部 data/ 内容表与代码镜像一致性。
## 不引用 autoload 单例（--script 模式安全）；JSON 直读，代码侧走 GameData 静态类。
## 运行：godot --headless --path . --script res://tools/check_content.gd

var _fails: Array[String] = []


func _check(label: String, ok: bool, detail: String = "") -> void:
	print(("PASS V4 " if ok else "FAIL V4 ") + label + ((" | " + detail) if detail != "" else ""))
	if not ok:
		_fails.append(label)


func _json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func _initialize() -> void:
	# ---- 遗物：12 件齐全、字段完整、图标存在、权重按稀有度口径 ----
	var relics := _json("res://data/relics.json")
	_check("relics count == 12", relics.size() == 12, "got %d" % relics.size())
	var weight_by_rarity := {"普通": 10.0, "稀有": 4.0, "传说": 1.5}
	var relic_fields_ok := true
	var relic_weight_ok := true
	for rid in relics.keys():
		var d: Dictionary = relics[rid]
		for f in ["name", "rarity", "icon", "desc", "weight"]:
			if not d.has(f):
				relic_fields_ok = false
		if not FileAccess.file_exists(String(d.get("icon", ""))):
			relic_fields_ok = false
		if absf(float(d.get("weight", 0.0)) - float(weight_by_rarity.get(String(d.get("rarity", "")), -1.0))) > 0.001:
			relic_weight_ok = false
		if not GameData.RELICS.has(rid):
			relic_fields_ok = false
	_check("relics fields+icons+code mirror", relic_fields_ok)
	_check("relics weights by rarity (10/4/1.5)", relic_weight_ok)

	# ---- 敌人：7 种、精灵存在、json 与 GameData.ENEMIES 同值 ----
	var enemies := _json("res://data/enemies.json")
	_check("enemies count == 7", enemies.size() == 7, "got %d" % enemies.size())
	var enemy_ok := true
	for eid in enemies.keys():
		var d: Dictionary = enemies[eid]
		if not FileAccess.file_exists("res://assets/sprites/enemies/enemy_%s_idle_00.png" % eid):
			enemy_ok = false
		var g: Dictionary = GameData.ENEMIES.get(eid, {})
		if g.is_empty():
			enemy_ok = false
			continue
		for f in ["hp", "speed", "dmg"]:
			if absf(float(d.get(f, -1.0)) - float(g.get(f, -2.0))) > 0.001:
				enemy_ok = false
		if int(d.get("xp", -1)) != int(g.get("xp", -2)):
			enemy_ok = false
	_check("enemies sprites+mirror", enemy_ok)

	# ---- Boss：6 只 HP 与 01 §4.3 定版一致 ----
	var bosses := _json("res://data/bosses.json")
	var want_hp := {"5": 2600.0, "10": 6000.0, "15": 11500.0, "20": 15000.0, "25": 19000.0, "30": 28000.0}
	var boss_ok := bosses.size() == 6
	for k in want_hp.keys():
		var d: Dictionary = bosses.get(k, {})
		if absf(float(d.get("hp", -1.0)) - want_hp[k]) > 0.001:
			boss_ok = false
		var g: Dictionary = GameData.BOSSES.get(int(k), {})
		if absf(float(g.get("hp", -1.0)) - want_hp[k]) > 0.001:
			boss_ok = false
	_check("bosses hp table (2600/6000/11500/15000/19000/28000)", boss_ok)

	# ---- 楼层：锚点权重和 == 1 ----
	var floors := _json("res://data/floors.json")
	var anchors: Dictionary = floors.get("mix_anchors", {})
	var anchor_ok := anchors.size() == 4
	for a in anchors.keys():
		var sum := 0.0
		for w in (anchors[a] as Dictionary).values():
			sum += float(w)
		if absf(sum - 1.0) > 0.01:
			anchor_ok = false
	_check("floors mix anchors sum == 1", anchor_ok)

	# ---- 三选一权重：levelup.json weights 和 == 100 ----
	var levelup := _json("res://data/levelup.json")
	var wsum := 0.0
	for v in (levelup.get("weights", {}) as Dictionary).values():
		wsum += float(v)
	_check("levelup base weights sum == 100", absf(wsum - 100.0) < 0.001, "sum=%s" % wsum)

	# ---- 图标表：路径全部存在 ----
	var icons := _json("res://data/icons.json")
	var icon_ok := true
	var icon_n := 0
	for group in ["weapons", "passives"]:
		for p in (icons.get(group, {}) as Dictionary).values():
			icon_n += 1
			if not FileAccess.file_exists(String(p)):
				icon_ok = false
	_check("icons all exist", icon_ok and icon_n >= 31, "n=%d" % icon_n)

	# ---- 音频清单：可解析且 ≥20 音色 ----
	var audio := _json("res://data/audio_manifest.json")
	_check("audio manifest sounds >= 20", (audio.get("sounds", {}) as Dictionary).size() >= 20,
		"got %d" % (audio.get("sounds", {}) as Dictionary).size())

	print("V4 RESULT: ", "PASS" if _fails.is_empty() else "FAIL")
	quit(0 if _fails.is_empty() else 1)
