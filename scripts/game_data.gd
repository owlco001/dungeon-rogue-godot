class_name GameData
extends RefCounted
## Static data tables for Dungeon Rogue v0.2
## (characters / weapons+levels / passives / relics / bosses / 30 floors).

const CHARACTERS := {
	"aila": {
		"name": "艾拉", "title": "游侠·均衡", "weapon": "bow",
		"speed": 230.0, "max_hp": 100.0,
		"affinity": ["gun"],
		"desc": "连射弓箭:自动射出箭矢",
	},
	"batong": {
		"name": "巴顿", "title": "重装·肉盾", "weapon": "whirlwind",
		"speed": 200.0, "max_hp": 170.0,
		"affinity": ["melee"],
		"desc": "旋风斧头:周期性范围旋风斩",
	},
	"mofei": {
		"name": "墨菲", "title": "术士·爆发", "weapon": "orb",
		"speed": 215.0, "max_hp": 90.0,
		"affinity": ["necro", "summon"],
		"desc": "魔法法球:弹射法球连锁打击",
	},
}
const CHAR_ORDER := ["aila", "batong", "mofei"]

# 武器 kind: projectile(单发/多重/穿透) / spread(霰弹扇面) / aoe(范围) / chain(弹射)
#   summon(召唤维持) / corpse(引爆尸体) / drain(链式吸取) / aura(诅咒光环)
#   orbit(环绕斧) / arc(扇形盾击) / shock(冲击波) / boomerang(回旋斧)
# school: gun(枪械) / summon(召唤) / necro(死灵) / melee(近战)
# sig: {解锁等级: {效果键: 值}}，按等级升序叠加；"flag" 为 signature 特殊词条
const WEAPON_MAX_LV := 8
const WEAPON_SLOTS := 6
const WEAPONS := {
	"bow": {
		"name": "连射弓箭", "kind": "projectile", "school": "gun", "cd": 0.85, "dmg": 24.0,
		"proj": "proj_arrow", "proj_speed": 560.0, "range": 620.0,
		"count": 1, "pierce": 0, "chain": 0, "explosive": 0.0,
		"sig": {2: {"count": 1}, 4: {"pierce": 1}, 6: {"chain": 1}},
	},
	"dual": {
		"name": "双枪", "kind": "projectile", "school": "gun", "cd": 0.45, "dmg": 14.0,
		"proj": "proj_bullet", "proj_speed": 640.0, "range": 560.0,
		"count": 1, "pierce": 0, "chain": 0, "explosive": 0.0,
		"sig": {2: {"count": 1}, 4: {"cd_mult": 0.8}, 6: {"count": 1}},
	},
	"shotgun": {
		"name": "霰弹枪", "kind": "spread", "school": "gun", "cd": 1.1, "dmg": 10.0,
		"proj": "proj_pellet", "proj_speed": 520.0, "range": 380.0,
		"count": 3, "pierce": 0, "chain": 0, "explosive": 0.0,
		"sig": {2: {"count": 2}, 4: {"explosive": 90.0}, 6: {"explosive": 135.0}},
	},
	"sniper": {
		"name": "狙击枪", "kind": "projectile", "school": "gun", "cd": 1.6, "dmg": 70.0,
		"proj": "proj_sniper", "proj_speed": 900.0, "range": 700.0,
		"count": 1, "pierce": 0, "chain": 0, "explosive": 0.0,
		"sig": {2: {"pierce": 1}, 4: {"critdmg": 0.5}, 6: {"pierce": 2}},
	},
	"gatling": {
		"name": "加特林", "kind": "projectile", "school": "gun", "cd": 0.22, "dmg": 9.0,
		"proj": "proj_mg", "proj_speed": 700.0, "range": 540.0,
		"count": 1, "pierce": 0, "chain": 0, "explosive": 0.0,
		"sig": {2: {"cd_mult": 0.75}, 4: {"chain": 1}, 6: {"chain": 2}},
	},
	"whirlwind": {
		"name": "旋风斧头", "kind": "aoe", "school": "melee", "cd": 1.5, "dmg": 34.0,
		"radius": 150.0, "fx": "fx_whirlwind",
		"sig": {2: {"radius_mult": 1.25}, 4: {"knockback": 1.6}, 6: {"execute": 0.2}},
	},
	"orb": {
		"name": "魔法法球", "kind": "chain", "school": "necro", "cd": 1.2, "dmg": 20.0,
		"proj": "proj_orb", "proj_speed": 460.0, "range": 620.0,
		"count": 1, "pierce": 0, "chain": 2, "explosive": 0.0,
		"sig": {2: {"count": 1}, 4: {"dmg_mult": 1.3}, 6: {"chain": 1}},
	},
	# ---- 召唤流 ----
	"sentry": {
		"name": "哨兵炮塔", "kind": "summon", "school": "summon",
		"cd": 2.5, "dmg": 16.0,
		"proj": "proj_bullet", "proj_speed": 620.0, "range": 520.0,
		"count": 1, "pierce": 0, "chain": 0, "explosive": 0.0,
		"summon": "turret",
		"sig": {2: {"cd_mult": 0.83}, 4: {"flag": "overload"}, 6: {"count": 1}},
	},
	"hound": {
		"name": "猎犬", "kind": "summon", "school": "summon",
		"cd": 3.0, "dmg": 24.0,
		"proj": "", "proj_speed": 0.0, "range": 600.0,
		"count": 1, "pierce": 0, "chain": 0, "explosive": 0.0,
		"summon": "hound",
		"sig": {2: {"count": 1}, 4: {"flag": "split"}, 6: {"flag": "bloodlust"}},
	},
	"skel_warrior": {
		"name": "骷髅战士", "kind": "summon", "school": "summon",
		"cd": 4.0, "dmg": 20.0,
		"proj": "", "proj_speed": 0.0, "range": 600.0,
		"count": 1, "pierce": 0, "chain": 0, "explosive": 0.0,
		"summon": "skeleton_warrior",
		"sig": {2: {"flag": "hp_mult", "flagv": 1.5}, 4: {"flag": "taunt"}, 6: {"flag": "thorns", "flagv": 0.3}},
	},
	"swarm": {
		"name": "蜂群", "kind": "summon", "school": "summon",
		"cd": 2.5, "dmg": 9.0,
		"proj": "", "proj_speed": 0.0, "range": 600.0,
		"count": 3, "pierce": 0, "chain": 0, "explosive": 0.0,
		"radius": 90.0,
		"summon": "bee",
		"sig": {2: {"radius_mult": 1.3}, 4: {"flag": "poison"}, 6: {"flag": "death_blast"}},
	},
	# ---- 死灵流 ----
	"skel_army": {
		"name": "骷髅大军", "kind": "summon", "school": "necro",
		"cd": 5.0, "dmg": 15.0,
		"proj": "", "proj_speed": 0.0, "range": 600.0,
		"count": 4, "pierce": 0, "chain": 0, "explosive": 0.0,
		"radius": 110.0,
		"summon": "skeleton_warrior",
		"sig": {2: {"count": 2}, 4: {"flag": "poison"}, 6: {"flag": "death_blast"}},
	},
	"corpse_blast": {
		"name": "尸爆", "kind": "corpse", "school": "necro",
		"cd": 1.6, "dmg": 70.0,
		"radius": 110.0, "range": 460.0,
		"count": 1, "pierce": 0, "chain": 0, "explosive": 0.0,
		"sig": {2: {"radius_mult": 1.3}, 4: {"flag": "chain_corpse"}, 6: {"flag": "elite_blast"}},
	},
	"life_drain": {
		"name": "生命吸取", "kind": "drain", "school": "necro",
		"cd": 2.2, "dmg": 30.0,
		"range": 500.0,
		"count": 1, "pierce": 0, "chain": 0, "explosive": 0.0,
		"sig": {2: {"chain": 1}, 4: {"flag": "shield_drain"}, 6: {"flag": "execute", "flagv": 0.1}},
	},
	"curse_aura": {
		"name": "诅咒光环", "kind": "aura", "school": "necro",
		"cd": 1.0, "dmg": 14.0,
		"radius": 170.0,
		"count": 1, "pierce": 0, "chain": 0, "explosive": 0.0,
		"sig": {2: {"radius_mult": 1.3}, 4: {"flag": "spread"}, 6: {"flag": "weaken"}},
	},
	# ---- 近战流 ----
	"melee_axe": {
		"name": "旋风斧", "kind": "orbit", "school": "melee",
		"cd": 0.5, "dmg": 26.0,
		"radius": 110.0,
		"count": 1, "pierce": 0, "chain": 0, "explosive": 0.0,
		"proj": "proj_axe",
		"sig": {2: {"count": 1}, 4: {"radius_mult": 1.25}, 6: {"flag": "pull"}},
	},
	"shield_bash": {
		"name": "盾击", "kind": "arc", "school": "melee",
		"cd": 2.6, "dmg": 50.0,
		"radius": 180.0,
		"count": 1, "pierce": 0, "chain": 0, "explosive": 0.0,
		"sig": {2: {"flag": "stun", "flagv": 2.0}, 4: {"flag": "parry"}, 6: {"flag": "riposte"}},
	},
	"warcry": {
		"name": "战吼", "kind": "shock", "school": "melee",
		"cd": 3.8, "dmg": 34.0,
		"radius": 230.0,
		"count": 1, "pierce": 0, "chain": 0, "explosive": 0.0,
		"sig": {2: {"radius_mult": 1.3}, 4: {"flag": "bloodlust_warcry"}, 6: {"count": 2}},
	},
	"flying_axe": {
		"name": "飞斧", "kind": "boomerang", "school": "melee",
		"cd": 1.9, "dmg": 36.0,
		"proj": "proj_axe", "proj_speed": 540.0, "range": 520.0,
		"count": 1, "pierce": 0, "chain": 0, "explosive": 0.0,
		"sig": {2: {"flag": "returns", "flagv": 2}, 4: {"pierce": 1}, 6: {"flag": "split_axe"}},
	},
}
# 16 把通用武器（专武 bow/whirlwind/orb 不进三选一新武器池）
const WEAPON_POOL := ["dual", "shotgun", "sniper", "gatling",
	"sentry", "hound", "skel_warrior", "swarm",
	"skel_army", "corpse_blast", "life_drain", "curse_aura",
	"melee_axe", "shield_bash", "warcry", "flying_axe"]
# 兼容旧引用
const GUN_ORDER := ["dual", "shotgun", "sniper", "gatling"]

# 被动：12 种，各 5 级
const PASSIVE_MAX_LV := 5
const PASSIVE_SLOTS := 6
const PASSIVES := {
	"attack": {"name": "攻击", "per": 0.08},
	"aspeed": {"name": "攻速", "per": 0.06},
	"crit": {"name": "暴击率", "per": 0.06},
	"hp": {"name": "血量", "per": 0.15},
	"speed": {"name": "移速", "per": 0.06},
	"magnet": {"name": "磁铁", "per": 0.35},
	"cooldown": {"name": "冷却", "per": 0.05},
	"area": {"name": "范围", "per": 0.10},
	"critdmg": {"name": "暴伤", "per": 0.15},
	"armor": {"name": "护甲", "per": 0.04},
	"duration": {"name": "持续时间", "per": 0.10},
	"xp": {"name": "经验", "per": 0.08},
}
const PASSIVE_ORDER := ["attack", "aspeed", "crit", "hp", "speed", "magnet", "cooldown", "area",
	"critdmg", "armor", "duration", "xp"]

# ---------- 超武合成 ----------
# super_id -> {name, weapon(原武器), passive(指定被动), mods(质变)}
# mods 通用键：dmg_mult/count_add/pierce_add/chain_add/explosive_mult/radius_mult/cd_mult/flags
# 扩展键：critdmg_add(暴伤加值) / summon_hp_mult(召唤物血量倍率) / stun_v/execute_v(对应flag数值)
const SUPERWEAPONS := {
	"super_dual": {"name": "死亡绽放", "weapon": "dual", "passive": "aspeed",
		"mods": {"dmg_mult": 1.6, "count_add": 2, "pierce_add": 1, "cd_mult": 0.9}},
	"super_shotgun": {"name": "寂灭轰鸣", "weapon": "shotgun", "passive": "area",
		"mods": {"dmg_mult": 1.4, "count_add": 2, "explosive_mult": 2.0}},
	"super_sniper": {"name": "审判之眼", "weapon": "sniper", "passive": "critdmg",
		"mods": {"dmg_mult": 2.0, "pierce_add": 2, "critdmg_add": 1.0}},
	"super_gatling": {"name": "金属风暴", "weapon": "gatling", "passive": "aspeed",
		"mods": {"dmg_mult": 1.3, "count_add": 1, "chain_add": 2, "cd_mult": 0.5}},
	"super_sentry": {"name": "歼灭矩阵", "weapon": "sentry", "passive": "cooldown",
		"mods": {"dmg_mult": 1.8, "count_add": 1, "cd_mult": 0.6, "flags": ["overload"]}},
	"super_hound": {"name": "兽群狂潮", "weapon": "hound", "passive": "aspeed",
		"mods": {"dmg_mult": 1.5, "count_add": 3, "flags": ["bloodlust", "split"]}},
	"super_skel_warrior": {"name": "不朽军团", "weapon": "skel_warrior", "passive": "hp",
		"mods": {"dmg_mult": 1.4, "count_add": 2, "summon_hp_mult": 2.0,
			"flags": ["taunt", "thorns"], "thorns_v": 0.5}},
	"super_swarm": {"name": "瘟疫风暴", "weapon": "swarm", "passive": "duration",
		"mods": {"dmg_mult": 1.6, "count_add": 6, "radius_mult": 1.5, "flags": ["poison", "death_blast"]}},
	"super_skel_army": {"name": "白骨王座", "weapon": "skel_army", "passive": "duration",
		"mods": {"dmg_mult": 1.6, "count_add": 4, "flags": ["poison", "death_blast"]}},
	"super_corpse_blast": {"name": "亡者国度", "weapon": "corpse_blast", "passive": "area",
		"mods": {"dmg_mult": 2.0, "radius_mult": 1.8, "cd_mult": 0.6, "flags": ["chain_corpse", "elite_blast"]}},
	"super_life_drain": {"name": "灵魂收割", "weapon": "life_drain", "passive": "hp",
		"mods": {"dmg_mult": 1.8, "chain_add": 3, "flags": ["shield_drain", "execute"], "execute_v": 0.2}},
	"super_curse_aura": {"name": "永恒凋零", "weapon": "curse_aura", "passive": "area",
		"mods": {"dmg_mult": 1.7, "radius_mult": 1.6, "flags": ["spread", "weaken"]}},
	"super_melee_axe": {"name": "毁灭风暴", "weapon": "melee_axe", "passive": "area",
		"mods": {"dmg_mult": 1.8, "count_add": 2, "radius_mult": 1.4, "flags": ["pull"]}},
	"super_shield_bash": {"name": "不动壁垒", "weapon": "shield_bash", "passive": "armor",
		"mods": {"dmg_mult": 2.0, "radius_mult": 1.5, "flags": ["stun", "parry", "riposte"], "stun_v": 3.0}},
	"super_warcry": {"name": "战神咆哮", "weapon": "warcry", "passive": "attack",
		"mods": {"dmg_mult": 2.2, "radius_mult": 1.5, "count_add": 2, "flags": ["bloodlust_warcry"]}},
	"super_flying_axe": {"name": "千刃轮舞", "weapon": "flying_axe", "passive": "aspeed",
		"mods": {"dmg_mult": 1.5, "count_add": 2, "pierce_add": 2, "cd_mult": 0.7, "flags": ["split_axe"]}},
	"super_bow": {"name": "万箭齐发", "weapon": "bow", "passive": "aspeed",
		"mods": {"dmg_mult": 1.3, "count_add": 3, "pierce_add": 2, "chain_add": 2}},
	"super_whirlwind": {"name": "开山裂地", "weapon": "whirlwind", "passive": "hp",
		"mods": {"dmg_mult": 2.0, "radius_mult": 1.6, "flags": ["execute"], "execute_v": 0.35, "knockback_v": 2.2}},
	"super_orb": {"name": "湮灭奇点", "weapon": "orb", "passive": "duration",
		"mods": {"dmg_mult": 2.0, "count_add": 2, "chain_add": 3, "flags": ["blackhole"]}},
}

## 超武 id -> 原武器 id（超武不在 WEAPONS 表里）
static func base_weapon_of(wid: String) -> String:
	if SUPERWEAPONS.has(wid):
		return String(SUPERWEAPONS[wid]["weapon"])
	return wid


static func is_super(wid: String) -> bool:
	return SUPERWEAPONS.has(wid)


# ---------- 技能 ----------
# kind: exclusive(角色专属，开局自带) / utility(通用，三选一获得)
# 每技能 3 级：cd/伤害/范围随级提升
const SKILL_MAX_LV := 3
const SKILLS := {
	"arrow_rain": {"name": "箭雨", "kind": "exclusive", "char": "aila",
		"cd": [18.0, 15.0, 12.0],
		"icon": "res://assets/icons/skills/icon_skill_arrowrain.png",
		"desc": "向最密集怪群降箭5秒"},
	"stomp": {"name": "践踏", "kind": "exclusive", "char": "batong",
		"cd": [16.0, 13.0, 10.0],
		"icon": "res://assets/icons/skills/icon_skill_stomp.png",
		"desc": "范围击退+眩晕2秒"},
	"soul_drain": {"name": "灵魂虹吸", "kind": "exclusive", "char": "mofei",
		"cd": [18.0, 15.0, 12.0],
		"icon": "res://assets/icons/skills/icon_skill_souldrain.png",
		"desc": "范围吸血，血越少伤害越高，回血30%"},
	"blink": {"name": "闪现", "kind": "utility",
		"cd": [12.0, 10.0, 8.0],
		"icon": "res://assets/icons/skills/icon_skill_dash.png",
		"desc": "向移动方向位移260px，无敌0.5秒"},
	"holy_shield": {"name": "圣盾", "kind": "utility",
		"cd": [22.0, 19.0, 16.0],
		"icon": "res://assets/icons/skills/icon_skill_holyshield.png",
		"desc": "获得吸收盾，持续6秒"},
	"meteor": {"name": "陨石术", "kind": "utility",
		"cd": [16.0, 14.0, 12.0],
		"icon": "res://assets/icons/skills/icon_skill_meteor.png",
		"desc": "随机落点8颗陨石轰炸"},
	"time_stop": {"name": "时间凝滞", "kind": "utility",
		"cd": [28.0, 24.0, 20.0],
		"icon": "res://assets/icons/skills/icon_skill_timestop.png",
		"desc": "全场怪物减速50%，持续3秒"},
}
const SKILL_ORDER := ["blink", "holy_shield", "meteor", "time_stop"]


static func exclusive_skill_of(char_id: String) -> String:
	for sid in SKILLS.keys():
		var d: Dictionary = SKILLS[sid]
		if String(d["kind"]) == "exclusive" and String(d["char"]) == char_id:
			return String(sid)
	return ""


# 遗物：独立 3 格
const RELIC_SLOTS := 3
const RELICS := {
	"magnetcore": {
		"name": "磁铁核心", "rarity": "稀有",
		"icon": "res://assets/icons/relics/icon_relic_magnetcore.png",
		"desc": "拾取范围翻倍",
	},
	"greedcup": {
		"name": "贪婪金杯", "rarity": "普通",
		"icon": "res://assets/icons/relics/icon_relic_greedcup.png",
		"desc": "金币+30%",
	},
	"wardrum": {
		"name": "狂暴战鼓", "rarity": "稀有",
		"icon": "res://assets/icons/relics/icon_relic_berserk.png",
		"desc": "攻速+25%",
	},
	"phoenixheart": {
		"name": "凤凰之心", "rarity": "传说",
		"icon": "res://assets/icons/relics/icon_relic_phoenixheart.png",
		"desc": "死亡复活一次(50%血)",
	},
}
const RELIC_ORDER := ["magnetcore", "greedcup", "wardrum", "phoenixheart"]

# Boss：每 5 层一只，30 层最终
const BOSSES := {
	5: {"name": "石颅巨像", "tex": "res://assets/sprites/bosses/boss_colossus.png",
		"hp": 2600.0, "dmg": 25.0, "speed": 55.0, "scale": 1.0},
	10: {"name": "噬影蝠王", "tex": "res://assets/sprites/bosses/boss_batking.png",
		"hp": 5200.0, "dmg": 30.0, "speed": 95.0, "scale": 1.0},
	15: {"name": "熔渣铸造者", "tex": "res://assets/sprites/bosses/boss_forgemaster.png",
		"hp": 9000.0, "dmg": 35.0, "speed": 50.0, "scale": 1.0},
	20: {"name": "双生亡语者", "tex": "res://assets/sprites/bosses/boss_widow_a.png",
		"hp": 14000.0, "dmg": 40.0, "speed": 70.0, "scale": 1.0},
	25: {"name": "荆棘暴君", "tex": "res://assets/sprites/bosses/boss_thorntyrant.png",
		"hp": 22000.0, "dmg": 48.0, "speed": 60.0, "scale": 1.0},
	30: {"name": "深渊主宰·墨骸", "tex": "res://assets/sprites/bosses/boss_mohei_phase1.png",
		"hp": 32000.0, "dmg": 60.0, "speed": 75.0, "scale": 1.0, "final": true},
}

# ---------- 无尽模式 ----------
# 封顶方案（DESIGN.md §7）：敌人侧 60 层封顶（hp/dmg/刷怪数不再涨），玩家侧不封顶
# （三选一/XP 照常），防数值膨胀的同时保留构筑成长爽感。
const ENDLESS_CAP_FLOOR := 60
const ENDLESS_BOSS_GROWTH := 1.15  # 每轮回 Boss 属性 +15%
const ENDLESS_GOLD_MULT := 1.5


## 无尽 Boss：6 只循环出场，属性按轮次递增
static func boss_def_for_floor(floor_num: int) -> Dictionary:
	var cycle := (floor_num - 1) / 5  # 第几个 5 层周期（0-based）
	var base_key := ((cycle % 6) + 1) * 5
	var base: Dictionary = BOSSES[base_key]
	var rounds := int(cycle / 6)  # 完整轮回次数
	var g := pow(ENDLESS_BOSS_GROWTH, rounds)
	var d := base.duplicate()
	d["hp"] = float(base["hp"]) * g
	d["dmg"] = float(base["dmg"]) * g
	d["final"] = false
	if rounds > 0:
		d["name"] = String(base["name"]) + "·%d轮" % (rounds + 1)
	return d

## 成就用 Boss id：无尽轮回 Boss 归一到 6 只本体（boss_5/boss_10/.../boss_30）
static func boss_ach_id(floor_num: int) -> String:
	var cycle := (floor_num - 1) / 5
	var base_key := ((cycle % 6) + 1) * 5
	return "boss_%d" % base_key


const ENEMIES := {
	"slime": {"name": "史莱姆", "hp": 30.0, "speed": 85.0, "dmg": 10.0, "xp": 2, "scale": 1.0},
	"bat": {"name": "蝙蝠", "hp": 16.0, "speed": 150.0, "dmg": 8.0, "xp": 2, "scale": 1.0, "fly": true},
	"skeleton": {"name": "骷髅兵", "hp": 24.0, "speed": 105.0, "dmg": 12.0, "xp": 4, "scale": 1.0},
	"brute": {"name": "蛮兽", "hp": 80.0, "speed": 70.0, "dmg": 20.0, "xp": 10, "scale": 1.35},
}

const MAX_FLOOR := 30
const FLOORS := [
	{"theme": "corridor", "name": "地牢回廊"},
	{"theme": "forge", "name": "熔渣熔炉"},
	{"theme": "ice", "name": "寒冰洞窟"},
	{"theme": "tomb", "name": "尸潮墓园"},
	{"theme": "thorn", "name": "荆棘密林"},
	{"theme": "void", "name": "虚空祭坛"},
]
const FLOOR_COMPS := [
	{"slime": 4, "bat": 2},
	{"slime": 3, "bat": 3, "skeleton": 2},
	{"slime": 3, "bat": 3, "skeleton": 3, "brute": 1},
	{"slime": 2, "bat": 4, "skeleton": 4, "brute": 2},
	{"slime": 2, "bat": 4, "skeleton": 5, "brute": 3},
	{"slime": 3, "bat": 3, "skeleton": 4, "brute": 3},
]

const GEM_TEX := {
	"s": "res://assets/sprites/pickups/gem_s.png",
	"m": "res://assets/sprites/pickups/gem_m.png",
	"l": "res://assets/sprites/pickups/gem_l.png",
}
const COIN_TEX := "res://assets/sprites/pickups/coin.png"
const STAIRS_TEX := "res://assets/sprites/pickups/portal_stairs.png"


static func xp_for_level(level: int) -> int:
	return 6 + (level - 1) * 5


## xp value -> gem tier id ("s"/"m"/"l")
static func gem_tier_for_xp(xp: int) -> String:
	if xp >= 8:
		return "l"
	if xp >= 4:
		return "m"
	return "s"


static func floor_def(floor_num: int) -> Dictionary:
	return FLOORS[(floor_num - 1) % FLOORS.size()]


static func is_boss_floor(floor_num: int) -> bool:
	return floor_num % 5 == 0


static func is_elite_floor(floor_num: int) -> bool:
	return floor_num % 3 == 0 and not is_boss_floor(floor_num)


static func floor_comp(floor_num: int) -> Dictionary:
	var base: Dictionary = FLOOR_COMPS[(floor_num - 1) % FLOOR_COMPS.size()]
	# 无尽 60 层后刷怪数封顶（防性能与数值失控）
	var growth := mini(int((floor_num - 1) / FLOOR_COMPS.size()), 9)
	var out := {}
	for k in base.keys():
		out[k] = int(base[k]) + growth * 2
	return out


## stat multiplier for enemies on a given floor
## v0.5 调优：伤害成长 0.08->0.05（原曲线 30 层承伤只剩 3.7 下，后期必被秒）；
## 血量成长 0.22 不变（TTK 0.5~1.4s 健康）。60 层封顶（无尽模式）。
static func enemy_hp_mult(floor_num: int) -> float:
	var f := minf(float(floor_num), 60.0)
	return 1.0 + 0.22 * (f - 1.0)


static func enemy_dmg_mult(floor_num: int) -> float:
	var f := minf(float(floor_num), 60.0)
	return 1.0 + 0.05 * (f - 1.0)
