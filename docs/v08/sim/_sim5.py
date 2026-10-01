# -*- coding: utf-8 -*-
import random, collections
def hpm(f): return 1.0+0.22*(min(f,60)-1)
BASE={"slime":30,"bat":16,"skeleton":24,"brute":80}
XP={"slime":3,"bat":3,"skeleton":5,"brute":14}
MIX={1:{"slime":.70,"bat":.30},10:{"slime":.40,"bat":.25,"skeleton":.25,"brute":.10},
     20:{"slime":.30,"bat":.20,"skeleton":.33,"brute":.17},30:{"slime":.22,"bat":.18,"skeleton":.37,"brute":.23}}
def mix(f):
    ks=sorted(MIX)
    if f in MIX: return dict(MIX[f])
    lo=max([k for k in ks if k<=f]); hi=min([k for k in ks if k>=f]); t=(f-lo)/(hi-lo)
    return {k: MIX[lo].get(k,0)+(MIX[hi].get(k,0)-MIX[lo].get(k,0))*t for k in set(MIX[lo])|set(MIX[hi])}
def target_hp(f):
    v=180*(1.15**(f-1))
    return v*(1.15 if f%3==0 else 1.0)
rows=[];tk=0;tx=0
for f in range(1,31):
    if f%5==0: rows.append((f,"BOSS",0,0,0)); continue
    m=mix(f); avg=sum(BASE[k]*w for k,w in m.items())
    n=max(6,min(48,round(target_hp(f)/(avg*hpm(f)))))
    # 按权重分配只数
    alloc={k:max(0,int(round(n*w))) for k,w in m.items()}
    while sum(alloc.values())<n: alloc[max(m,key=lambda k:m[k])]+=1
    while sum(alloc.values())>n:
        k=max(alloc,key=lambda x:alloc[x]); alloc[k]-=1
    real=sum(BASE[k]*v for k,v in alloc.items())*hpm(f)
    xpv=sum(XP[k]*v for k,v in alloc.items())
    rows.append((f,sum(alloc.values()),int(real),xpv)); tk+=sum(alloc.values()); tx+=xpv
prev=None;bad=[]
print("层  只数  实际层总HP  XP")
for r in rows:
    if r[1]=="BOSS": print(" %2d  BOSS"%r[0]); continue
    if prev is not None and r[2]<prev: bad.append(r[0])
    print(" %2d  %3d   %6d  %4d %s"%(r[0],r[1],r[2],r[3],"<回落" if prev is not None and r[2]<prev else ""))
    prev=r[2]
print("回落层:",bad if bad else "无 ✓")
print("总怪=%d 总XP(怪)=%d  怪金币(45%%x2)=%.0f"%(tk,tx,tk*0.9))
tot=tx+40*6
lv=1;t=tot
while t>=6+(lv-1)*5: t-=6+(lv-1)*5; lv+=1
print("含Boss XP=%d → Lv.%d（%d 次升级）"%(tot,lv,lv-1))
print("首通金币 = 怪%.0f + Boss600 + 通关400 = %.0f"%(tk*0.9,tk*0.9+1000))

# ===== 新三选一权重池 =====
WMAX,PMAX,WS,PS=8,5,6,6
SUPER={"super_bow":("bow","aspeed"),"super_dual":("dual","aspeed"),"super_shotgun":("shotgun","area"),
"super_gatling":("gatling","aspeed"),"super_sniper":("sniper","critdmg"),"super_orb":("orb","duration"),
"super_melee_axe":("melee_axe","area"),"super_flying_axe":("flying_axe","aspeed"),"super_warcry":("warcry","attack"),
"super_corpse_blast":("corpse_blast","area"),"super_life_drain":("life_drain","hp"),"super_curse_aura":("curse_aura","area"),
"super_sentry":("sentry","cooldown"),"super_hound":("hound","aspeed"),"super_swarm":("swarm","duration"),
"super_skel_army":("skel_army","duration"),"super_whirlwind":("whirlwind","hp")}
POOL=["dual","shotgun","sniper","gatling","sentry","hound","skel_warrior","swarm","skel_army","corpse_blast",
"life_drain","curse_aura","melee_axe","shield_bash","warcry","flying_axe"]
PASS=["attack","aspeed","crit","hp","speed","magnet","cooldown","area","critdmg","armor","duration","xp"]
def options(weapons,passives,skills,funnel,miss):
    cands=[]
    synth=[]
    for w in weapons:
        if w["id"] in SUPER or w["lv"]<WMAX: continue
        for sw,(bw,np) in SUPER.items():
            if bw==w["id"] and passives.get(np,0)>=PMAX: synth.append(("synthesize",w["id"],sw))
    if synth: return ([synth[0]]+options_nosynth(weapons,passives,skills,funnel,miss))[:3]
    return options_nosynth(weapons,passives,skills,funnel,miss)
def options_nosynth(weapons,passives,skills,funnel,miss):
    c=[]
    for w in weapons:
        if w["lv"]<WMAX and w["id"] not in SUPER:
            wt=30*(2.0 if funnel and w["id"]==funnel else 1.0)
            c.append([("weapon_up",w["id"]),wt])
    if len(weapons)<WS:
        for wid in POOL:
            if not any(x["id"]==wid for x in weapons):
                wt=22 if len(weapons)<4 else 8
                c.append([("new_weapon",wid),wt])
    for pid in passives:
        if passives[pid]<PMAX:
            wt=22
            if funnel:
                np=[p for sw,(bw,p) in SUPER.items() if bw==funnel]
                if np and pid==np[0]: wt*=3
            c.append([("passive_up",pid),wt])
    if len(passives)<PS:
        for pid in PASS:
            if pid not in passives: c.append([("new_passive",pid),18 if len(passives)<4 else 6])
    if not any(s[0]=="util" for s in skills):
        for sid in ["blink","holy_shield","meteor","time_stop"]: c.append([("new_skill",sid),8])
    else:
        for s in skills:
            if s[0]=="util" and s[2]<3: c.append([("skill_up",s[1]),8])
    out=[];pool=[x[:] for x in c]
    # 保底：连续 2 次无 passive_up -> 强制塞一个
    forced=None
    if miss>=2 and passives:
        pid=max(passives,key=lambda p:passives[p])
        if passives[pid]<PMAX: forced=("passive_up",pid)
        elif len(passives)<PS: forced=("new_passive",[p for p in PASS if p not in passives][0])
    if forced:
        out.append(forced); pool=[x for x in pool if x[0][:11]!=forced[0] or x[0][1]!=forced[1]]
    while len(out)<3 and pool:
        tot=sum(w for _,w in pool); r=random.random()*tot; acc=0; pick_i=0
        for i,(o,w) in enumerate(pool):
            acc+=w
            if r<=acc: pick_i=i; break
        out.append(pool[pick_i][0]); pool.pop(pick_i)
    return out
def run(nup=33,seed=5):
    random.seed(seed)
    weapons=[{"id":"bow","lv":1}];passives={};skills=[("excl","arrow_rain",1)]
    funnel="bow"; miss=0; offer=collections.Counter(); supers=[]
    for k in range(nup):
        opts=options(weapons,passives,skills,funnel,miss)
        for o in opts: offer[o[0]]+=1
        miss = 0 if any(o[0]=="passive_up" for o in opts) else miss+1
        needp=[p for sw,(bw,p) in SUPER.items() if bw==funnel][0]
        rank={"synthesize":0}
        o=sorted(opts,key=lambda x: rank.get(x[0], 1 if (x[0]=="weapon_up" and x[1]==funnel) else
                                             2 if (x[0]=="passive_up" and x[1]==needp) else
                                             3 if (x[0]=="new_passive" and x[1]==needp) else
                                             4 if x[0]=="weapon_up" else
                                             5 if x[0]=="new_weapon" and len(weapons)<5 else
                                             6 if x[0]=="new_skill" else 7))[0]
        if o[0]=="new_weapon": weapons.append({"id":o[1],"lv":1})
        elif o[0]=="weapon_up":
            for w in weapons:
                if w["id"]==o[1]: w["lv"]=min(WMAX,w["lv"]+1)
        elif o[0]=="synthesize":
            for w in weapons:
                if w["id"]==o[1]: w["id"]=o[2]; supers.append(o[2])
            funnel=[x["id"] for x in weapons if x["lv"]<WMAX and x["id"] not in SUPER]
            funnel=funnel[0] if funnel else None
        elif o[0]=="new_passive": passives[o[1]]=1
        elif o[0]=="passive_up": passives[o[1]]=min(PMAX,passives[o[1]]+1)
        elif o[0]=="new_skill": skills.append(("util",o[1],1))
    return weapons,passives,supers,offer
print("\n=== v0.8 新权重池：33 次升级 ===")
for s in [5,23,77]:
    w,p,sup,offer=run(seed=s)
    tot=sum(offer.values())
    print(" seed=%d 终局武器=%s"%(s,[(x['id'],x['lv']) for x in w]))
    print("        被动=%s  合成超武=%s"%(p,sup))
    print("        99槽位分布=%s → 被动类占比 %.0f%%"%(dict(offer),100*(offer['new_passive']+offer['passive_up'])/tot))
