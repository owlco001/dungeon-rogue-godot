class_name Meta
extends RefCounted
## 局外成长：存档 / 天赋树 / 永久属性 / 解锁
## 存档位置 user://savegame.cfg (ConfigFile)，Web 版走 IndexedDB 持久化。
## 所有数值先按 DESIGN.md §8，没有的按"每级 4-8% 别超模"估算。

const SAVE_PATH := "user://savegame.cfg"

# ---------- 天赋 ----------
# per: 每级数值(百分比填小数)；kind: mult/add/special；cost: 基础价，升级价=base*(lv+1)
const TALENTS := {
	# 战斗系
	"sharp":   {"school": "combat", "name": "锋利", "desc": "攻击 +%d%%", "max": 5, "cost": 120, "per": 0.04},
	"critinst":{"school": "combat", "name": "弱点洞悉", "desc": "暴击率 +%d%%", "max": 5, "cost": 120, "per": 0.02},
	"swift":   {"school": "combat", "name": "疾风", "desc": "攻速 +%d%%", "max": 5, "cost": 120, "per": 0.03},
	"warmaster":{"school": "combat", "name": "武器大师", "desc": "武器伤害 +%d%%", "max": 5, "cost": 150, "per": 0.04},
	"undying": {"school": "combat", "name": "不死意志", "desc": "每局复活一次(50%血)", "max": 1, "cost": 2000, "per": 0.0},
	# 生存系
	"vitality":{"school": "survival", "name": "体魄", "desc": "血量上限 +%d", "max": 5, "cost": 120, "per": 10.0},
	"ironwall":{"school": "survival", "name": "铁壁", "desc": "护甲 +%d", "max": 5, "cost": 120, "per": 1.0},
	"regen":   {"school": "survival", "name": "再生", "desc": "每秒回血 +%.1f", "max": 5, "cost": 120, "per": 0.5},
	"tough":   {"school": "survival", "name": "坚韧", "desc": "受伤 -%d%%", "max": 5, "cost": 150, "per": 0.02},
	"magnetbody":{"school": "survival", "name": "磁石体质", "desc": "全屏自动拾取", "max": 1, "cost": 2000, "per": 0.0},
	# 贪婪系
	"scholar": {"school": "greed", "name": "好学", "desc": "经验 +%d%%", "max": 5, "cost": 100, "per": 0.05},
	"greed":   {"school": "greed", "name": "贪金", "desc": "金币 +%d%%", "max": 5, "cost": 100, "per": 0.05},
	"nimble":  {"school": "greed", "name": "灵手", "desc": "拾取范围 +%d%%", "max": 5, "cost": 100, "per": 0.08},
	"lucky":   {"school": "greed", "name": "鸿运", "desc": "暴击伤害 +%d%%", "max": 5, "cost": 150, "per": 0.06},
	"versatile":{"school": "greed", "name": "多才多艺", "desc": "武器槽 +1", "max": 1, "cost": 2000, "per": 0.0},
}
const TALENT_ORDER := ["sharp", "critinst", "swift", "warmaster", "undying",
	"vitality", "ironwall", "regen", "tough", "magnetbody",
	"scholar", "greed", "nimble", "lucky", "versatile"]
const SCHOOLS := {
	"combat": {"name": "战斗系", "color": Color(1.0, 0.45, 0.35)},
	"survival": {"name": "生存系", "color": Color(0.45, 0.9, 0.5)},
	"greed": {"name": "贪婪系", "color": Color(1.0, 0.85, 0.3)},
}
const SCHOOL_ORDER := ["combat", "survival", "greed"]

# ---------- 永久属性升级（§8.1，每项 20 级，价格递增） ----------
const ATTRS := {
	"atk":  {"name": "强壮", "desc": "攻击 +%d%%", "max": 20, "cost": 60, "per": 0.02},
	"hp":   {"name": "生命", "desc": "血量上限 +%d", "max": 20, "cost": 60, "per": 6.0},
	"spd":  {"name": "神速", "desc": "移速 +%d%%", "max": 20, "cost": 50, "per": 0.01},
	"pick": {"name": "搜刮", "desc": "拾取范围 +%d%%", "max": 20, "cost": 50, "per": 0.03},
	"exp":  {"name": "睿智", "desc": "经验 +%d%%", "max": 20, "cost": 80, "per": 0.02},
}
const ATTR_ORDER := ["atk", "hp", "spd", "pick", "exp"]

# ---------- 解锁 ----------
# 角色：通关层数 或 金币，二选一
const CHAR_UNLOCKS := {
	"aila":   {"free": true},
	"batong": {"floor": 3, "gold": 800},
	"mofei":  {"floor": 5, "gold": 2000},
}
# 武器：默认解锁每流派第一把 + 枪械全系；其余 9 把金币解锁
const WEAPON_UNLOCK_COST := 600
const WEAPON_DEFAULT_UNLOCKED := ["dual", "shotgun", "sniper", "gatling",
	"sentry", "corpse_blast", "melee_axe"]

# ---------- 存档 ----------
static var _loaded := false
static var _gold := 0
static var _talents := {}
static var _attrs := {}
static var _unlocked_chars := ["aila"]
static var _unlocked_weapons: Array = []
static var _max_floor := 0
static var _victories := 0
static var _bosses := []
static var _endless_best_floor := 0
static var _endless_best_score := 0
static var _muted := false
static var selected_char := ""
# v0.6：天赋点货币 / 成就 / 累计击杀 / 武器·超武图鉴 / 旧存档迁移标记
static var _talent_points := 0
static var _achievements := {}
static var _total_kills := 0
static var _weapon_codex: Array = []
static var _super_codex: Array = []
static var _migrated_v06 := false
static var _migration_toast := ""


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	_unlocked_weapons = WEAPON_DEFAULT_UNLOCKED.duplicate()
	var cfg := ConfigFile.new()
	var had_save := cfg.load(SAVE_PATH) == OK
	if not had_save:
		_migrated_v06 = true
		return
	_gold = int(cfg.get_value("meta", "gold", 0))
	_talent_points = int(cfg.get_value("meta", "talent_points", 0))
	_achievements = dict(cfg.get_value("meta", "achievements", {}))
	_migrated_v06 = bool(cfg.get_value("meta", "migrated_v06", false))
	_talents = dict(cfg.get_value("meta", "talents", {}))
	_attrs = dict(cfg.get_value("meta", "attrs", {}))
	_unlocked_chars = Array(cfg.get_value("meta", "unlocked_chars", ["aila"]))
	var uw: Array = Array(cfg.get_value("meta", "unlocked_weapons", []))
	for wid in WEAPON_DEFAULT_UNLOCKED:
		if not uw.has(wid):
			uw.append(wid)
	_unlocked_weapons = uw
	_max_floor = int(cfg.get_value("records", "max_floor", 0))
	_victories = int(cfg.get_value("records", "victories", 0))
	_bosses = Array(cfg.get_value("records", "bosses", []))
	_endless_best_floor = int(cfg.get_value("records", "endless_best_floor", 0))
	_endless_best_score = int(cfg.get_value("records", "endless_best_score", 0))
	_total_kills = int(cfg.get_value("records", "total_kills", 0))
	_weapon_codex = Array(cfg.get_value("records", "weapon_codex", []))
	_super_codex = Array(cfg.get_value("records", "super_codex", []))
	_muted = bool(cfg.get_value("meta", "muted", false))
	# v0.6 迁移：旧存档用金币买过天赋 -> 按原价退金币并发等量天赋点
	if not _migrated_v06:
		var res := _do_migration()
		_migrated_v06 = true
		save_data()
		if int(res["gold"]) > 0 or int(res["points"]) > 0:
			_migration_toast = Lang.t("退回%d金币,发放%d天赋点") % [int(res["gold"]), int(res["points"])]


static func dict(v) -> Dictionary:
	return v if v is Dictionary else {}


static func save_data() -> void:
	_ensure()
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "gold", _gold)
	cfg.set_value("meta", "talent_points", _talent_points)
	cfg.set_value("meta", "achievements", _achievements)
	cfg.set_value("meta", "migrated_v06", _migrated_v06)
	cfg.set_value("meta", "talents", _talents)
	cfg.set_value("meta", "attrs", _attrs)
	cfg.set_value("meta", "unlocked_chars", _unlocked_chars)
	cfg.set_value("meta", "unlocked_weapons", _unlocked_weapons)
	cfg.set_value("records", "max_floor", _max_floor)
	cfg.set_value("records", "victories", _victories)
	cfg.set_value("records", "bosses", _bosses)
	cfg.set_value("records", "endless_best_floor", _endless_best_floor)
	cfg.set_value("records", "endless_best_score", _endless_best_score)
	cfg.set_value("records", "total_kills", _total_kills)
	cfg.set_value("records", "weapon_codex", _weapon_codex)
	cfg.set_value("records", "super_codex", _super_codex)
	cfg.set_value("meta", "muted", _muted)
	cfg.save(SAVE_PATH)


# ---------- 金币 ----------
static func gold() -> int:
	_ensure()
	return _gold


static func add_gold(n: int) -> void:
	_ensure()
	_gold = maxi(0, _gold + n)
	save_data()


static func spend(n: int) -> bool:
	_ensure()
	if _gold < n:
		return false
	_gold -= n
	save_data()
	return true


# ---------- 天赋（v0.6：改用天赋点购买；金币只用于强化/解锁） ----------
static func talent_lv(tid: String) -> int:
	_ensure()
	return int(_talents.get(tid, 0))


## 天赋点价格：普通天赋 1 点/级；三个质变（max=1）3 点
static func talent_point_cost(tid: String) -> int:
	if talent_lv(tid) >= int(TALENTS[tid]["max"]):
		return 0
	return 3 if int(TALENTS[tid]["max"]) == 1 else 1


static func buy_talent(tid: String) -> bool:
	var d: Dictionary = TALENTS[tid]
	if talent_lv(tid) >= int(d["max"]):
		return false
	if not spend_talent_points(talent_point_cost(tid)):
		return false
	_talents[tid] = talent_lv(tid) + 1
	save_data()
	return true


static func talent_desc(tid: String) -> String:
	var d: Dictionary = TALENTS[tid]
	var per: float = float(d["per"])
	if int(d["max"]) == 1:
		return Lang.t(String(d["desc"]))
	if tid == "regen":
		return Lang.t(String(d["desc"])) % (per * talent_lv(tid))
	if per < 1.0:
		return Lang.t(String(d["desc"])) % int(round(per * 100.0 * talent_lv(tid)))
	return Lang.t(String(d["desc"])) % int(per * talent_lv(tid))


# ---------- 天赋点货币（v0.6：成就/Boss首杀/首次通关发放） ----------
static func talent_points() -> int:
	_ensure()
	return _talent_points


static func add_talent_points(n: int) -> void:
	_ensure()
	_talent_points = maxi(0, _talent_points + n)
	save_data()


static func spend_talent_points(n: int) -> bool:
	_ensure()
	if _talent_points < n:
		return false
	_talent_points -= n
	save_data()
	return true


# ---------- 成就存档（v0.6） ----------
static func is_achievement_done(aid: String) -> bool:
	_ensure()
	return _achievements.has(aid)


static func achievement_time(aid: String) -> int:
	_ensure()
	return int(_achievements.get(aid, 0))


static func grant_achievement(aid: String, points: int) -> void:
	_ensure()
	if _achievements.has(aid):
		return
	_achievements[aid] = int(Time.get_unix_time_from_system())
	_talent_points = maxi(0, _talent_points + points)
	save_data()


# ---------- 累计击杀 / 武器图鉴 / 超武图鉴（v0.6） ----------
static func total_kills() -> int:
	_ensure()
	return _total_kills


## 击杀计数：高频调用不落盘，局结算时随 _bank_run_gold 落盘
static func add_total_kills(n: int) -> void:
	_ensure()
	_total_kills += n


static func add_weapon_codex(wid: String) -> void:
	_ensure()
	if not _weapon_codex.has(wid):
		_weapon_codex.append(wid)


static func weapon_codex_size() -> int:
	_ensure()
	return _weapon_codex.size()


static func add_super_codex(swid: String) -> void:
	_ensure()
	if not _super_codex.has(swid):
		_super_codex.append(swid)


static func super_codex_size() -> int:
	_ensure()
	return _super_codex.size()


# ---------- v0.6 旧存档迁移 ----------
## 旧存档用金币买过天赋：按当时价格（基础价*(lv+1) 累加）退金币，
## 并发等量天赋点（普通每级 1 点、质变 3 点）。返回 {"gold":X,"points":Y}。
static func _do_migration() -> Dictionary:
	var gold_back := 0
	var pts := 0
	for tid in TALENT_ORDER:
		var lv := int(_talents.get(tid, 0))
		if lv <= 0:
			continue
		var base := int(TALENTS[tid]["cost"])
		for i in range(lv):
			gold_back += base * (i + 1)
		pts += lv * (3 if int(TALENTS[tid]["max"]) == 1 else 1)
	_gold += gold_back
	_talent_points += pts
	save_data()
	return {"gold": gold_back, "points": pts}


## 取出并清空迁移提示（大厅 _ready 里消费一次）
static func pop_migration_toast() -> String:
	var t := _migration_toast
	_migration_toast = ""
	return t


# ---------- 属性 ----------
static func attr_lv(aid: String) -> int:
	_ensure()
	return int(_attrs.get(aid, 0))


static func attr_cost(aid: String) -> int:
	var d: Dictionary = ATTRS[aid]
	return int(float(d["cost"]) * pow(1.35, attr_lv(aid)))


static func buy_attr(aid: String) -> bool:
	var d: Dictionary = ATTRS[aid]
	if attr_lv(aid) >= int(d["max"]):
		return false
	if not spend(attr_cost(aid)):
		return false
	_attrs[aid] = attr_lv(aid) + 1
	save_data()
	return true


# ---------- 解锁 ----------
static func is_char_unlocked(cid: String) -> bool:
	_ensure()
	return _unlocked_chars.has(cid)


static func char_unlock_desc(cid: String) -> String:
	var d: Dictionary = CHAR_UNLOCKS[cid]
	if bool(d.get("free", false)):
		return Lang.t("初始解锁")
	return Lang.t("通关 %d 层 / %d 金币") % [int(d["floor"]), int(d["gold"])]


static func try_unlock_char(cid: String) -> bool:
	_ensure()
	if is_char_unlocked(cid):
		return true
	var d: Dictionary = CHAR_UNLOCKS[cid]
	if _max_floor >= int(d["floor"]):
		_unlocked_chars.append(cid)
		save_data()
		return true
	if spend(int(d["gold"])):
		_unlocked_chars.append(cid)
		save_data()
		return true
	return false


static func is_weapon_unlocked(wid: String) -> bool:
	_ensure()
	return _unlocked_weapons.has(wid)


static func buy_weapon(wid: String) -> bool:
	_ensure()
	if is_weapon_unlocked(wid):
		return true
	if not spend(WEAPON_UNLOCK_COST):
		return false
	_unlocked_weapons.append(wid)
	save_data()
	return true


# ---------- 战绩 ----------
static func max_floor() -> int:
	_ensure()
	return _max_floor


static func victories() -> int:
	_ensure()
	return _victories


static func record_run(floor: int, victory: bool) -> void:
	_ensure()
	_max_floor = maxi(_max_floor, floor)
	if victory:
		_victories += 1
	save_data()


static func record_boss_kill(floor: int) -> void:
	_ensure()
	if not _bosses.has(floor):
		_bosses.append(floor)
		save_data()


# ---------- 开局加成（player.gd 调用） ----------
static func bonus_dmg_mult() -> float:
	_ensure()
	return 1.0 + 0.04 * talent_lv("sharp") + 0.04 * talent_lv("warmaster") + 0.02 * attr_lv("atk")


static func bonus_hp_add() -> float:
	_ensure()
	return 10.0 * talent_lv("vitality") + 6.0 * attr_lv("hp")


static func bonus_speed_mult() -> float:
	_ensure()
	return 1.0 + 0.01 * attr_lv("spd")


static func bonus_xp_mult() -> float:
	_ensure()
	return 1.0 + 0.05 * talent_lv("scholar") + 0.02 * attr_lv("exp")


static func bonus_gold_mult() -> float:
	_ensure()
	return 1.0 + 0.05 * talent_lv("greed")


static func bonus_magnet_mult() -> float:
	_ensure()
	return 1.0 + 0.08 * talent_lv("nimble") + 0.03 * attr_lv("pick")


static func bonus_crit() -> float:
	_ensure()
	return 0.02 * talent_lv("critinst")


static func bonus_critdmg() -> float:
	_ensure()
	return 0.06 * talent_lv("lucky")


static func bonus_aspeed_mult() -> float:
	_ensure()
	return 1.0 - 0.03 * talent_lv("swift")


static func bonus_armor() -> int:
	_ensure()
	return talent_lv("ironwall")


static func bonus_tough_mult() -> float:
	_ensure()
	return 1.0 - 0.02 * talent_lv("tough")


static func bonus_regen() -> float:
	_ensure()
	return 0.5 * talent_lv("regen")


static func has_revive() -> bool:
	_ensure()
	return talent_lv("undying") > 0


static func has_magnet_all() -> bool:
	_ensure()
	return talent_lv("magnetbody") > 0


static func extra_weapon_slots() -> int:
	_ensure()
	return 1 if talent_lv("versatile") > 0 else 0


# ---------- 无尽纪录 ----------
static func endless_best_floor() -> int:
	_ensure()
	return _endless_best_floor


static func endless_best_score() -> int:
	_ensure()
	return _endless_best_score


static func record_endless(floor: int, score: int) -> void:
	_ensure()
	_endless_best_floor = maxi(_endless_best_floor, floor)
	_endless_best_score = maxi(_endless_best_score, score)
	save_data()


# ---------- 静音 ----------
static func is_muted() -> bool:
	_ensure()
	return _muted


static func set_muted(m: bool) -> void:
	_ensure()
	_muted = m
	save_data()
