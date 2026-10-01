# -*- coding: utf-8 -*-
"""复刻 game_data.gd + main.gd + player.gd 的关键数值逻辑，做一局 30 层的推演。"""
import random, math
random.seed(7)

ENEMIES = {"slime":{"hp":30,"dmg":10,"xp":2},"bat":{"hp":16,"dmg":8,"xp":2},
           "skeleton":{"hp":24,"dmg":12,"xp":4},"brute":{"hp":80,"dmg":20,"xp":10}}
FLOOR_COMPS=[{"slime":4,"bat":2},{"slime":3,"bat":3,"skeleton":2},
 {"slime":3,"bat":3,"skeleton":3,"brute":1},{"slime":2,"bat":4,"skeleton":4,"brute":2},
 {"slime":2,"bat":4,"skeleton":5,"brute":3},{"slime":3,"bat":3,"skeleton":4,"brute":3}]
BOSSES={5:2600,10:5200,15:9000,20:14000,25:22000,30:32000}
def floor_comp(f):
    base=FLOOR_COMPS[(f-1)%6]; growth=min((f-1)//6,9)
    return {k:v+growth*2 for k,v in base.items()}
def is_boss(f): return f%5==0
def is_elite(f): return f%3==0 and not is_boss(f)
def hp_mult(f): return 1.0+0.22*(min(f,60)-1)
def dmg_mult(f): return 1.0+0.05*(min(f,60)-1)
def xp_for_level(L): return 6+(L-1)*5

total_kills=0; total_xp=0; total_gold=0.0; floors=[]
for f in range(1,31):
    if is_boss(f):
        n=4; xp=40+2*2+2*2; kills=n+1
        eff_hp=BOSSES[f]
    else:
        comp=floor_comp(f); n=sum(comp.values()); kills=n
        xp=sum(ENEMIES[k]["xp"]*v for k,v in comp.items())
        elites=2 if is_elite(f) else 0
        # 前 2 只（dict 顺序 slime,bat...）变精英，xp x5
        order=list(comp.keys()); left=elites
        for k in order:
            if left<=0: break
            take=min(left,comp[k]); xp+=take*ENEMIES[k]["xp"]*4; left-=take
        eff_hp=sum(ENEMIES[k]["hp"]*v for k,v in comp.items())*hp_mult(f)
        if elites: eff_hp+= 2*30*8*hp_mult(f)
    gold=n*0.25*2.0
    floors.append((f,kills,xp,gold,eff_hp))
    total_kills+=kills; total_xp+=xp; total_gold+=gold
print("30层总击杀=%d  总XP=%d  总金币=%.0f"%(total_kills,total_xp,total_gold))
L=1; need=xp_for_level(1); cum=0; lv=1
tmp=total_xp
while tmp>=xp_for_level(lv):
    tmp-=xp_for_level(lv); lv+=1
print("满拾取可达等级 = Lv.%d  → 升级次数 = %d"%(lv,lv-1))
print("各层敌人等效总血量(未含Boss):", [int(x[4]) for x in floors if not is_boss(x[0])])
print("Boss 血量序列:", [BOSSES[f] for f in BOSSES])

# ---- 局外经济 ----
def attr_total(base,lv_from=0,lv_to=20):
    return int(sum(base*1.35**i for i in range(lv_from,lv_to)))
ATTRS={"atk":60,"hp":60,"spd":50,"pick":50,"exp":80}
print("\n局外属性：")
for k,b in ATTRS.items():
    print("  %-5s 前5级=%5d  前10级=%6d  全20级=%8d"%(k,attr_total(b,0,5),attr_total(b,0,10),attr_total(b,0,20)))
print("  全部5项20级合计 = %d 金币"%sum(attr_total(b) for b in ATTRS.values()))
golds=[total_gold*(1+0.05*5), total_gold]
print("  单局金币(裸/贪婪满) = %.0f / %.0f → 买满全部属性需 %.0f 局"%(golds[0],golds[1],sum(attr_total(b) for b in ATTRS.values())/golds[0]))
print("  解锁9把武器(600/把)=5400 → %.1f 局"%(5400/golds[0]))
print("  解锁巴顿800/墨菲2000")

# ---- 天赋点 ----
pts=3+6*1+2*3+1+2+1+2+3+2+2+2+2
need_pts={"combat":5*4+3,"survival":5*4+3,"greed":5*4+3}
print("\n天赋点：可获取总数=%d；三系全满需=%d → 缺口=%d"%(pts,sum(need_pts.values()),sum(need_pts.values())-pts))
