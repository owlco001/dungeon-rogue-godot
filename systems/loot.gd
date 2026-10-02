class_name Loot
extends RefCounted
## v0.8 掉落收口（02 §4.7-3）：遗物按 data/relics.json 权重抽取，
## 排除已持有；min_rarity 给 Boss 保底（至少稀有）。

const RANKS := {"普通": 0, "稀有": 1, "传说": 2}


static func roll_relic(owned: Array, min_rarity: String = "") -> String:
	var tbl: Dictionary = ContentDB.table("relics")
	var min_rank := int(RANKS.get(min_rarity, 0))
	var pool: Array = []
	var total := 0.0
	for rid in tbl.keys():
		if rid in owned:
			continue
		var def: Dictionary = tbl[rid]
		if int(RANKS.get(String(def.get("rarity", "普通")), 0)) < min_rank:
			continue
		var w := float(def.get("weight", 1.0))
		pool.append([rid, w])
		total += w
	if pool.is_empty() or total <= 0.0:
		return ""
	var r := randf() * total
	for pair in pool:
		r -= float(pair[1])
		if r <= 0.0:
			return String(pair[0])
	return String(pool[pool.size() - 1][0])
