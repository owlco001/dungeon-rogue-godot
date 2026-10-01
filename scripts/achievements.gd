class_name Achievements
extends RefCounted
## 成就系统 v0.6：19 个成就，奖励天赋点。
## 存档走 Meta（已完成 id -> 完成时间戳）。
## 触发点埋在：Boss击杀 / 通关 / 无尽层数 / 击杀计数 / 超武合成 / 武器获得 / 天赋购买。
## unlock() 成功时：Meta 落盘 + 成就音效 + 待发 toast（HUD/大厅 _process 里 drain_pending 消费）。
## 文案只用 hud-subset.ttf 已有字（完/鉴/奖/✦ 等字缺，避开）。

const DEFS := {
	"first_clear": {"name": "初通深渊", "desc": "第1次通关30层", "points": 3},
	"boss_5":  {"name": "初杀石颅巨像", "desc": "击败5层Boss", "points": 1},
	"boss_10": {"name": "初杀噬影蝠王", "desc": "击败10层Boss", "points": 1},
	"boss_15": {"name": "初杀熔渣铸造者", "desc": "击败15层Boss", "points": 1},
	"boss_20": {"name": "初杀双生亡语者", "desc": "击败20层Boss", "points": 1},
	"boss_25": {"name": "初杀荆棘暴君", "desc": "击败25层Boss", "points": 1},
	"boss_30": {"name": "初杀深渊主宰", "desc": "击败30层大Boss", "points": 1},
	"endless35": {"name": "无尽35层", "desc": "深入无尽35层", "points": 2},
	"endless40": {"name": "无尽40层", "desc": "深入无尽40层", "points": 2},
	"endless50": {"name": "无尽50层", "desc": "深入无尽50层", "points": 2},
	"kill1000": {"name": "千怪斩", "desc": "击杀1000只怪物", "points": 1},
	"kill5000": {"name": "万怪斩", "desc": "击杀5000只怪物", "points": 2},
	"super1":  {"name": "超武初成", "desc": "合成超武x1", "points": 1},
	"super5":  {"name": "超武多成", "desc": "合成超武x5", "points": 2},
	"super19": {"name": "超武大成", "desc": "集齐19超武", "points": 3},
	"arsenal": {"name": "武器全收", "desc": "19武器全获得", "points": 2},
	"master_combat":   {"name": "战斗大师", "desc": "战斗系天赋全满", "points": 2},
	"master_survival": {"name": "生存大师", "desc": "生存系天赋全满", "points": 2},
	"master_greed":    {"name": "贪婪大师", "desc": "贪婪系天赋全满", "points": 2},
}
const ORDER := ["first_clear",
	"boss_5", "boss_10", "boss_15", "boss_20", "boss_25", "boss_30",
	"endless35", "endless40", "endless50",
	"kill1000", "kill5000",
	"super1", "super5", "super19",
	"arsenal",
	"master_combat", "master_survival", "master_greed"]

static var _pending: Array = []


## 尝试解锁成就；首次解锁时发天赋点 + 音效 + toast，返回 true。
static func unlock(aid: String) -> bool:
	if not DEFS.has(aid):
		return false
	if Meta.is_achievement_done(aid):
		return false
	var d: Dictionary = DEFS[aid]
	Meta.grant_achievement(aid, int(d["points"]))
	# 音效在 toast 显示时播放（hud/lobby.show_toast），此处不直接引用 Sfx autoload
	queue_toast(Lang.t("解锁:%s(+%d天赋点)") % [Lang.t(String(d["name"])), int(d["points"])])
	return true


## 天赋购买后调用：检查三系是否全满
static func check_talent_masters() -> void:
	for sid in Meta.SCHOOL_ORDER:
		var full := true
		for tid in Meta.TALENT_ORDER:
			var d: Dictionary = Meta.TALENTS[tid]
			if String(d["school"]) != sid:
				continue
			if Meta.talent_lv(tid) < int(d["max"]):
				full = false
				break
		if full:
			unlock("master_" + sid)


static func queue_toast(text: String) -> void:
	_pending.append(text)


## 取出并清空待发 toast（HUD/大厅每帧调用）
static func drain_pending() -> Array:
	var out: Array = _pending.duplicate()
	_pending.clear()
	return out
