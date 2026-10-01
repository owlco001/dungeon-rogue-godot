# -*- coding: utf-8 -*-
def hpm(f): return 1.0+0.22*(min(f,60)-1)
BASE={"slime":30,"bat":16,"skeleton":24,"brute":80}
XP={"slime":2,"bat":2,"skeleton":4,"brute":10}          # 保持 v0.7 不变
MIX={1:{"slime":.70,"bat":.30},10:{"slime":.40,"bat":.25,"skeleton":.25,"brute":.10},
     20:{"slime":.30,"bat":.20,"skeleton":.33,"brute":.17},30:{"slime":.22,"bat":.18,"skeleton":.37,"brute":.23}}
def mix(f):
    ks=sorted(MIX)
    if f in MIX: return dict(MIX[f])
    lo=max(k for k in ks if k<=f); hi=min(k for k in ks if k>=f); t=(f-lo)/(hi-lo)
    return {k: MIX[lo].get(k,0)+(MIX[hi].get(k,0)-MIX[lo].get(k,0))*t for k in set(MIX[lo])|set(MIX[hi])}
ELITE_M=2.0
def n_of(f): return max(6,min(46,int(round(6+1.35*(f-1)))))
rows=[]; tk=0; tx=0
for f in range(1,31):
    if f%5==0: rows.append((f,-1,0,0,0)); continue
    m=mix(f); n=n_of(f)
    a={k:int(round(n*w)) for k,w in m.items()}
    while sum(a.values())<n: a[max(m,key=lambda k:m[k])]+=1
    while sum(a.values())>n: a[max(a,key=lambda x:a[x])]-=1
    hp=sum(BASE[k]*v for k,v in a.items())*hpm(f); ne=0; ex=0
    if f%3==0:
        k=max([x for x in a if a[x]>0],key=lambda x:BASE[x]); ne=min(2,a[k])
        hp+=ne*BASE[k]*(ELITE_M-1)*hpm(f); ex=ne*XP[k]*4
    xp=sum(XP[k]*v for k,v in a.items())+ex
    rows.append((f,n,ne,int(hp),xp)); tk+=n; tx+=xp
prev=None;bad=[]
for r in rows:
    if r[1]==-1: continue
    if prev is not None and r[3]<prev: bad.append((r[0],round(100*(r[3]-prev)/prev)))
    prev=r[3]
tot=tx+40*6; lv=1; t=tot
while t>=6+(lv-1)*5: t-=6+(lv-1)*5; lv+=1
print("v0.8 终版：总怪=%d 总XP(怪)=%d +Boss240 = %d → Lv.%d（%d 次升级）"%(tk,tx,tot,lv,lv-1))
print("最大回落:",min([b[1] for b in bad]) if bad else 0,"%  回落层:",bad)
print("首通金币 = 怪%.0f + Boss 600 + 通关 400 = %.0f"%(tk*0.9,tk*0.9+1000))
print("死在10层金币 ≈ %.0f"%(sum(r[1] for r in rows if r[1]!=-1 and r[0]<10)*0.9+120))
print()
print("层  只数 精英  层总HP   XP")
prev=None
for r in rows:
    if r[1]==-1: print(" %2d   BOSS"%r[0]); continue
    print(" %2d  %3d  %2d   %6d  %4d %s"%(r[0],r[1],r[2],r[3],r[4],"" if prev is None or r[3]>=prev else "<%d%%"%(100*(r[3]-prev)/prev))); prev=r[3]
