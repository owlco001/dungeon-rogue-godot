class_name StatBlock
extends RefCounted
## v0.8 A3b StatBlock：属性收敛层。遗物的纯属性效果走 data/relics.json 的 mods
## （乘区连乘），替代散落在 player 各 _xxx_mult 函数里的硬编码分支；
## 稀有度描边色为 UI 唯一口径（普通蓝/稀有紫/传说金）。

## owned 遗物对某乘区键的连乘结果（无 mods 时为 1.0）
static func relic_mult(owned: Array, key: String, relics_table: Dictionary) -> float:
	var m := 1.0
	for rid in owned:
		var def: Dictionary = relics_table.get(rid, {})
		var mods: Dictionary = def.get("mods", {})
		if mods.has(key):
			m *= float(mods[key])
	return m


static func rarity_color(rarity: String) -> Color:
	match rarity:
		"传说":
			return Color("F0C060")
		"稀有":
			return Color("A96FD9")
		_:
			return Color("6FB7D6")
