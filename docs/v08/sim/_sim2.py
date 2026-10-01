# -*- coding: utf-8 -*-
"""复刻 player.gd::build_levelup_options 的池化轮转算法 + 简化的构筑 DPS 模型"""
import random, copy
random.seed(11)

W={ # id: (kind, cd, dmg, count, pierce, chain, school)
 "bow":("proj",0.85,24,1,0,0,"gun"),"dual":("proj",0.45,14,1,0,0,"gun"),
 "shotgun":("spread",1.1,10,3,0,0,"gun"),"sniper":("proj",1.6,70,1,0,0,"gun"),
 "gatling":("proj",0.22,9,1,0,0,"gun"),"whirlwind":("aoe",1.5,34,1,0,0,"melee"),
 "orb":("chain",1.2,20,1,0,2,"necro"),"sentry":("summon",2.5,16,1,0,0,"summon"),
 "hound":("summon",3.0,24,1,0,0,"summon"),"skel_warrior":("summon",4.0,20,1,0,0,"summon"),
 "swarm":("summon",2.5,9,3,0,0,"summon"),"skel_army":("summon",5.0,15,4,0,0,"necro"),
 "corpse_blast":("corpse",1.6,70,1,0,0,"necro"),"life_drain":("drain",2.2,30,1,0,0,"necro"),
 "curse_aura":("aura",1.0,14,1,0,0,"necro"),"melee_axe":("orbit",0.5,26,1,0,0,"melee"),
 "shield_bash":("arc",2.6,50,1,0,0,"melee"),"warcry":("shock",3.8,34,1,0,0,"melee"),
 "flying_axe":("boomerang",1.9,36,1,0,0,"melee"),
}
SIG={"bow":{2:("count",1),4:("pierce",1),6:("chain",1)},
     "dual":{2:("count",1),4:("cd",0.8),6:("count",1)},
     "shotgun":{2:("count",2),4:("exp",90),6:("exp",135)},
     "sniper":{2:("pierce",1),4:("critdmg",.5),6:("pierce",2)},
     "gatling":{2:("cd",.75),4:("chain",1),6:("chain",2)},
     "orb":{2:("count",1),4:("dmg",1.3),6:("chain",1)},
     "sentry":{2:("cd",.83),6:("count",1)},"hound":{2:("count",1)},
     "swarm":{2:("rad",1.3)},"skel_army":{2:("count",2)},
     "corpse_blast":{2:("rad",1.3)},"life_drain":{2:("chain",1)},
     "curse_aura":{2:("rad",1.3)},"melee_axe":{2:("count",1),4:("rad",1.25)},
     "warcry":{2:("rad",1.3),6:("count",2)},"flying_axe":{4:("pierce",1)}}
SUPER={"super_bow":("bow","aspeed"),"super_dual":("dual","aspeed"),
 "super_shotgun":("shotgun","area"),"super_sniper":("sniper","critdmg"),
 "super_gatling":("gatling","aspeed"),"super_sentry":("sentry","cooldown"),
 "super_hound":("hound","aspeed"),"super_swarm":("swarm","duration"),
 "super_skel_army":("skel_army","duration"),"super_corpse_blast":("corpse_blast","area"),
 "super_life_drain":("life_drain","hp"),"super_curse_aura":("curse_aura","area"),
 "super_melee_axe":("melee_axe","area"),"super_warcry":("warcry","attack"),
 "super_flying_axe":("flying_axe","aspeed"),"super_whirlwind":("whirlwind","hp"),
 "super_orb":("orb","duration")}
SWMOD={"super_bow":(1.3,3,0,2),"super_dual":(1.6,2,1,0),"super_shotgun":(1.4,2,0,0),
 "super_gatling":(1.3,1,0,0),"super_sniper":(2.0,0,2,0),"super_orb":(2.0,2,0,0),
 "super_melee_axe":(1.8,2,0,0),"super_flying_axe":(1.5,2,2,0),"super_warcry":(2.2,2,0,0),
 "super_corpse_blast":(2.0,0,0,0),"super_life_drain":(1.8,0,0,0),"super_curse_aura":(1.7,0,0,0),
 "super_sentry":(1.8,1,0,0),"super_hound":(1.5,3,0,0),"super_swarm":(1.6,6,0,0),
 "super_skel_army":(1.6,4,0,0),"super_whirlwind":(2.0,0,0,0)}
POOL=["dual","shotgun","sniper","gatling","sentry","hound","skel_warrior","swarm",
 "skel_army","corpse_blast","life_drain","curse_aura","melee_axe","shield_bash","warcry","flying_axe"]
PASS=["attack","aspeed","crit","hp","speed","magnet","cooldown","area","critdmg","armor","duration","xp"]
WMAX, PMAX, WS, PS = 8,5,6,6

def wstats(w, passives, aff=("gun",)):
    wid,lv=w["id"],w["lv"]; is_sup=wid in SUPER
    if is_sup:
        base=SUPER[wid][0]; lv=8; dm,ca,pa,ch=SWMOD[wid]
    else:
        base=wid; dm,ca,pa,ch=1.0,0,0,0
    kind,cd,dmg,cnt,pr,ch0,school=W[base]
    dmg=dmg*(1+0.12*(lv-1))
    for slv in sorted(SIG.get(base,{})):
        if lv<slv: continue
        k,v=SIG[base][slv]
        if k=="count": cnt+=v
        elif k=="pierce": pr+=v
        elif k=="chain": ch0+=v
        elif k=="cd": cd*=v
        elif k=="dmg": dmg*=v
    cnt+=ca; pr+=pa; ch0+=ch
    dmg*=dm
    am=1+0.10*passives.get("area",0)
    cdm=(1-0.06*passives.get("aspeed",0))*(1-0.05*passives.get("cooldown",0))
    cdm=max(cdm,0.35)
    dmg*= (1+0.08*passives.get("attack",0))
    if school in aff: dmg*=1.15
    # 命中次数系数：穿透/弹射按平均命中 1.6 只折算；aoe/orbit/aura 按 3 只折算
    if kind in ("aoe","orbit","aura","shock","arc","corpse"): tgt=3.0
    else: tgt=1+0.6*(pr+ch0)
    return dmg*cnt*tgt/max(cd*cdm,0.05)

def build_options(weapons,passives,skills):
    synth=[];wups=[];wnews=[];pups=[];pnews=[];snew=[];sups=[]
    for w in weapons:
        wid=w["id"]
        if wid in SUPER or w["lv"]<WMAX: continue
        for sw,(bw,needp) in SUPER.items():
            if bw!=wid: continue
            if passives.get(needp,0)<PMAX: continue
            synth.append(("synthesize",wid,sw))
    for w in weapons:
        if w["lv"]<WMAX and w["id"] not in SUPER:
            wups.append(("weapon_up",w["id"],None))
    if len(weapons)<WS:
        for wid in POOL:
            if not any(x["id"]==wid for x in weapons):
                wnews.append(("new_weapon",wid,None))
    for pid in passives:
        if passives[pid]<PMAX: pups.append(("passive_up",pid,None))
    if len(passives)<PS:
        for pid in PASS:
            if pid not in passives: pnews.append(("new_passive",pid,None))
    has_ut=any(s[0]!="excl" for s in skills)
    if has_ut:
        for s in skills:
            if s[0]!="excl" and s[2]<3: sups.append(("skill_up",s[1],None))
    else:
        for sid in ["blink","holy_shield","meteor","time_stop"]: snew.append(("new_skill",sid,None))
    pools=[synth,wnews,wups,snew,sups,pnews,pups]
    for p in pools: random.shuffle(p)
    opts=[];i=0
    while len(opts)<3:
        added=False
        for p in pools:
            if i<len(p) and len(opts)<3:
                opts.append(p[i]); added=True
        if not added: break
        i+=1
    return opts

def pick(opts,weapons,passives,goal):
    for o in opts:
        if o[0]=="synthesize": return o
    # 目标：先把 goal 指定武器练满，再点其超武所需被动
    for o in opts:
        if o[0]=="weapon_up" and o[1]==goal: return o
    for o in opts:
        if o[0]=="new_weapon" and len(weapons)<4: return o
    needp=[p for sw,(bw,p) in SUPER.items() if bw==goal][0]
    for o in opts:
        if o[0]=="passive_up" and o[1]==needp: return o
    for o in opts:
        if o[0]=="new_passive" and o[1]==needp: return o
    for o in opts:
        if o[0]=="new_skill": return o
    for o in opts:
        if o[0]=="weapon_up": return o
    for o in opts:
        if o[0]=="passive_up": return o
    for o in opts:
        if o[0]=="new_passive": return o
    return opts[0]

def run(goal="bow", nup=32, verbose=True):
    weapons=[{"id":"bow","lv":1}]; passives={}; skills=[("excl","arrow_rain",1)]
    log=[]
    for k in range(nup):
        opts=build_options(weapons,passives,skills)
        o=pick(opts,weapons,passives,goal); log.append(o[0])
        if o[0]=="new_weapon": weapons.append({"id":o[1],"lv":1})
        elif o[0]=="weapon_up":
            for w in weapons:
                if w["id"]==o[1]: w["lv"]=min(WMAX,w["lv"]+1)
        elif o[0]=="synthesize":
            for w in weapons:
                if w["id"]==o[1]: w["id"]=o[2]
        elif o[0]=="new_passive": passives[o[1]]=1
        elif o[0]=="passive_up": passives[o[1]]=min(PMAX,passives[o[1]]+1)
        elif o[0]=="new_skill": skills.append(("util",o[1],1))
        elif o[0]=="skill_up":
            for s in skills:
                if s[1]==o[1]: s=(s[0],s[1],min(3,s[2]+1))
        dps=sum(wstats(w,passives) for w in weapons)
        log[-1]=(log[-1],round(dps))
    dps=sum(wstats(w,passives) for w in weapons)
    sup=[w["id"] for w in weapons if w["id"] in SUPER]
    return weapons,passives,skills,dps,sup,log

for goal in ["bow","gatling","whirlwind"]:
    w,p,s,dps,sup,log=run(goal)
    print("=== 目标武器 %s ==="%goal)
    print(" 终局武器:",[(x["id"],x["lv"]) for x in w])
    print(" 终局被动:",p)
    print(" 超武:",sup," 终局DPS=%.0f"%dps)
    from collections import Counter
    print(" 32次升级的选择分布:",Counter([x[0] for x in log]))
    print(" DPS轨迹(每次升级后):",[x[1] for x in log][:32])
    print()

print("\n\n===== 补充：统计「被动/技能/合成」在 32 次升级中【被提供】的次数 =====")
import collections
def run2(policy="meta", nup=32, seed=3):
    random.seed(seed)
    weapons=[{"id":"bow","lv":1}]; passives={}; skills=[("excl","arrow_rain",1)]
    offer=collections.Counter()
    for k in range(nup):
        opts=build_options(weapons,passives,skills)
        for o in opts: offer[o[0]]+=1
        # 政策 meta：优先合成 > 专武升级 > 拿满4把武器 > 超武所需被动 > 通用技能
        goal="bow"; needp=[p for sw,(bw,p) in SUPER.items() if bw==goal][0]
        prio={"synthesize":0,"weapon_up":1 if any(o[0]=="weapon_up" and o[1]==goal for o in opts) else 5,
              "new_weapon":2 if len(weapons)<4 else 6,"new_passive":3 if needp not in passives else 4,
              "passive_up":3 if passives.get(needp,0)<5 else 6,"new_skill":7,"skill_up":8}
        o=sorted(opts,key=lambda x:prio.get(x[0],9))[0]
        if o[0]=="new_weapon": weapons.append({"id":o[1],"lv":1})
        elif o[0]=="weapon_up":
            for w in weapons:
                if w["id"]==o[1]: w["lv"]=min(WMAX,w["lv"]+1)
        elif o[0]=="synthesize":
            for w in weapons:
                if w["id"]==o[1]: w["id"]=o[2]
        elif o[0]=="new_passive": passives[o[1]]=1
        elif o[0]=="passive_up": passives[o[1]]=min(PMAX,passives[o[1]]+1)
        elif o[0]=="new_skill": skills.append(("util",o[1],1))
        elif o[0]=="skill_up":
            for i,s in enumerate(skills):
                if s[1]==o[1]: skills[i]=(s[0],s[1],min(3,s[2]+1))
    return weapons,passives,skills,offer,sum(wstats(w,passives) for w in weapons)

for seed in [3,17,42]:
    w,p,s,offer,dps=run2(seed=seed)
    tot=sum(offer.values())
    print(" seed=%d 终局武器=%s 被动=%s 技能=%s DPS=%.0f"%(seed,[(x['id'],x['lv']) for x in w],p,[x[1]+str(x[2]) for x in s],dps))
    print("   96个选项槽位分布:",dict(offer),"→ 被动占比 %.1f%%"%(100*(offer['new_passive']+offer['passive_up'])/tot))
