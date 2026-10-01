#!/usr/bin/env python3
"""数值审查：模拟 1~30 层玩家期望 DPS vs 敌人 HP/TTK/承伤，找断层。"""
import re, math

SRC = "/home/hatch/workspace/games/dungeon-rogue-godot/scripts/game_data.gd"
txt = open(SRC).read()

def grab_block(name):
    m = re.search(r"const %s := \{(.*?)\n\}" % name, txt, re.S)
    return m.group(1)

def parse_weapons():
    out = {}
    for m in re.finditer(r'"(\w+)": \{\s*"name": "([^"]+)", "kind": "(\w+)", "school": "(\w+)",\s*"cd": ([\d.]+), "dmg": ([\d.]+),(.*?)"sig": \{(.*?)\},', txt, re.S):
        wid, name, kind, school, cd, dmg, rest, sig = m.groups()
        cm = re.search(r'"count": (\d+)', rest)
        count = float(cm.group(1)) if cm else 1.0
        out[wid] = {"name": name, "kind": kind, "cd": float(cd), "dmg": float(dmg),
                    "count": count, "sig": sig}
    return out

def parse_enemies():
    out = {}
    for m in re.finditer(r'"(\w+)": \{"name": "([^"]+)", "hp": ([\d.]+), "speed": [\d.]+, "dmg": ([\d.]+), "xp": (\d+)', txt):
        eid, name, hp, dmg, xp = m.groups()
        out[eid] = {"hp": float(hp), "dmg": float(dmg), "xp": int(xp)}
    return out

def parse_bosses():
    out = {}
    for m in re.finditer(r'(\d+): \{"name": "([^"]+)",.*?"hp": ([\d.]+), "dmg": ([\d.]+)', txt, re.S):
        f, name, hp, dmg = m.groups()
        out[int(f)] = {"name": name, "hp": float(hp), "dmg": float(dmg)}
    return out

WEAPONS = parse_weapons()
ENEMIES = parse_enemies()
BOSSES = parse_bosses()
print("weapons:", len(WEAPONS), "enemies:", len(ENEMIES), "bosses:", sorted(BOSSES))

# 每层怪群（照抄 floor_comp 逻辑）
BASE_COMP = [
    {"slime": 4, "bat": 2},
    {"slime": 3, "bat": 3, "skeleton": 2},
    {"slime": 3, "bat": 3, "skeleton": 3, "brute": 1},
    {"slime": 2, "bat": 4, "skeleton": 4, "brute": 2},
    {"slime": 2, "bat": 4, "skeleton": 5, "brute": 3},
    {"slime": 3, "bat": 3, "skeleton": 4, "brute": 3},
]
def comp(f):
    base = BASE_COMP[(f - 1) % 6]
    growth = (f - 1) // 6
    return {k: v + growth * 2 for k, v in base.items()}

def hp_mult(f): return 1.0 + 0.22 * (f - 1)
def dmg_mult(f): return 1.0 + 0.05 * (min(f,60) - 1)

# ---- 玩家成长模拟 ----
# 每层 1.2 次三选一；40% 新武器(满6槽转升级)/35% 武器升级/25% 被动
# 武器选取顺序模拟：bow(专武) -> dual -> shotgun -> sentry -> melee_axe -> corpse_blast -> ...
PICK_ORDER = ["bow", "dual", "shotgun", "sentry", "melee_axe", "corpse_blast"]
wlv = {"bow": 1}
wpicks = ["bow"]
picks_total = 0
attack_passive = 0  # 被动 attack 等级
aspeed_passive = 0

def weapon_dps(wid, lv):
    w = WEAPONS[wid]
    count, dmg, cd = w["count"], w["dmg"], w["cd"]
    eff = 1.0
    # signature 简化：2级 count+1 类按字面，4/6 级按伤害向折算
    sig = w["sig"]
    if lv >= 2:
        if '"count": 1' in sig and '"count": 2' not in sig.split("4:")[0]:
            pass
        # 粗略：每解锁一级 sig，DPS *1.25（count/穿透/爆炸等综合）
    mult = 1.0
    if lv >= 2: mult *= 1.3
    if lv >= 4: mult *= 1.3
    if lv >= 6: mult *= 1.25
    if lv >= 8: mult *= 1.15
    # 被动/亲和加成
    atk = 1 + 0.08 * attack_passive
    asp = 1 / (1 - min(0.5, 0.06 * aspeed_passive))
    return count * dmg * mult * atk * asp / cd

print(f"\n{'层':>3} {'DPS':>7} {'怪均HP':>8} {'TTK(s)':>7} {'怪均伤':>7} {'玩家血':>7} {'承伤数':>6} 备注")
print("-" * 70)
flags = []
for f in range(1, 31):
    # 本层三选一
    for _ in range(1):  # 1.2 次用概率
        pass
    n_pick = 1.2
    # 用期望分配
    # 新武器
    new_w = 0.40 * n_pick if len(wpicks) < 6 else 0
    # 简化：按期望直接推进等级（确定性模拟）
    # 武器升级总期望次数
    up_exp = (0.35 * n_pick + (0.40 * n_pick if len(wpicks) >= 6 else 0))
    # 分配：先拿新武器（整数化累积）
    picks_total += n_pick
    # 确定性：每层固定拿 1.2 -> 用累积小数
    # 为简单起见用查表式成长曲线（拟合 1.2/层）：
    # 武器槽：第1层1把，每约2层+1把，6层满
    # 这里直接用公式：
    n_weapons = min(6, 1 + (f // 2))
    while len(wpicks) < n_weapons:
        wpicks.append(PICK_ORDER[len(wpicks)])
    # 武器总升级点数 ≈ 累计三选一*0.55 / 武器数
    total_up_pts = picks_total * 0.55
    avg_lv = min(8, 1 + total_up_pts / max(1, len(wpicks)) * 1.6)
    for w in wpicks:
        wlv[w] = min(8, avg_lv)
    attack_passive = min(5, picks_total * 0.25 * 0.5)
    aspeed_passive = min(5, picks_total * 0.25 * 0.3)

    dps = sum(weapon_dps(w, wlv[w]) for w in wpicks)
    c = comp(f)
    tot = sum(c.values())
    avg_hp = sum(ENEMIES[k]["hp"] * v for k, v in c.items()) / tot * hp_mult(f)
    avg_dmg = sum(ENEMIES[k]["dmg"] * v for k, v in c.items()) / tot * dmg_mult(f)
    ttk = avg_hp / (dps * 0.5)
    php = 100 * (1 + 0.15 * min(5, f * 0.12))
    hits = php / avg_dmg
    note = ""
    if f % 5 == 0:
        b = BOSSES[f]
        bttk = b["hp"] / (dps * 0.8)
        note = "BOSS %s TTK %.0fs" % (b["name"][:4], bttk)
        if bttk > 90: flags.append((f, "Boss TTK过长 %.0fs" % bttk)); note += " ←慢"
    if ttk > 4: flags.append((f, "杂兵TTK %.1fs 过长" % ttk)); note += " ←杂兵硬"
    if hits < 6: flags.append((f, "承伤仅%.1f下" % hits)); note += " ←易被秒"
    print(f"{f:>3} {dps:>7.0f} {avg_hp:>8.0f} {ttk:>7.1f} {avg_dmg:>7.1f} {php:>7.0f} {hits:>6.1f} {note}")

print("\n⚠ 断层：")
for f, msg in flags:
    print(f"  第{f}层: {msg}")
