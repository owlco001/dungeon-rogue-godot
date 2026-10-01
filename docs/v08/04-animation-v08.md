# 《地牢肉鸽》v0.8 动画方案

> 作者：关建帧（animation-director）
> 依据：设计终稿 `01-design-v08.md`、架构基线 `02-architecture-v08.md`、仓库 `dungeon-rogue-godot` @ `baf32f5` 实读代码（player.gd / enemy.gd / boss.gd / fx.gd / slash.gd / shadow.gd / projectile.gd / player.tscn / enemy.tscn / assets/sprites/ 全目录核对）
> 本阶段未修改仓库任何文件。所有现状判断引用文件+函数；所有演出时序精确到帧/毫秒（以 60fps 为基准，1 帧 ≈ 16.7ms）。
> 硬前提：美术**零新增**（帧切片已盘点，见 §1.4）；hitstop 重构（架构 A1）已定，本方案的打击感全部基于「不再全局压 `Engine.time_scale`」的新契约（§3.1）。

---

## 一、动画现状盘点

### 1.1 总体驱动方式：全程序化，无 AnimationPlayer

全项目动画 = **帧切片（AnimatedSprite2D）+ 代码程序化表现（modulate / scale / rotation / Tween / CPUParticles2D）**，没有任何 `.tres` 动画资源、没有 AnimationPlayer 节点。帧资产只有「待机呼吸」级别，所有运动感、打击感、演出全部由代码逐帧计算。这个路线在 Web（GDScript 无 JIT）+ 零新增美术的约束下是正确的，v0.8 **继续沿用，不引入 AnimationPlayer**（取舍理由见 §5.2）。

### 1.2 玩家（player.gd / player.tscn）

| 项 | 实况 | 证据 |
| --- | --- | --- |
| 节点结构 | `Player(CharacterBody2D)` → `Shadow`(Node2D, 程序画椭圆) + `Visual`(Node2D) → `AnimatedSprite2D` + `Dust`(CPUParticles2D 22 粒) + `Camera2D`(limits 写死 1600×1200) | `scenes/player.tscn:15-36`、`scripts/player.gd:61-63` |
| 帧构造 | 运行时 `SpriteFrames.new()`：4 方向 × (idle 1 帧 @2fps 循环 + walk 4 帧 @9fps 循环) = 每角色 20 帧贴图、8 条动画 | `player.gd:102-110 _build_sprite_frames()` |
| 状态切换 | 无状态机对象，`_physics_process` 里按速度阈值直接选 `("walk_"/"idle_") + dir_name`，`_play()` 防重播 | `player.gd:132-153`、`player.gd:180-183 _play()` |
| 方向判定 | 主轴判向（\|x\|>\|y\|），4 向硬切 | `player.gd:145-150` |
| 程序化表现 | 移动倾斜 ±3°（`visual.rotation` lerp 12×delta）；走跑 bob `sin(_walk_t×16)` ±3px + squash/stretch ±1.8%；待机呼吸 2.6Hz ±2%；扬尘开关 | `player.gd:186-200 _update_feel()` |
| 受击表现 | 白闪 0.12s（modulate 1+2k，k=_flash_t/0.12）→ 无敌闪烁 0.7s（alpha 0.45+0.35sin(t×28)）→ 击退 `velocity += from_dir×280×knock_mult` | `player.gd:170-177`、`player.gd:1443-1470 take_damage()` |
| 复活演出 | 无专属演出：回 50% 血 + 无敌 2.0s（凤凰之心/天赋共用分支） | `player.gd:1472-1483` |

**结论**：玩家侧基线健康。缺的只有「攻击方向感」（武器全自动开火，sprite 无任何开火反馈，近战劈砍的 `slash.gd` 是**死代码**，全工程 0 引用——架构 §1.7 证实）和「合成超武」演出分层（现状是 5 个 FX 同帧齐发，见 §3.4）。

### 1.3 敌人（enemy.gd / enemy.tscn）与 Boss（boss.gd）

**普通敌人**：

| 项 | 实况 | 证据 |
| --- | --- | --- |
| 帧构造 | **每只怪在 `_ready` 里 new 一份 SpriteFrames**（10 种敌人 × 每种 2 帧 idle @7fps 循环）——架构 T5 指认的分配浪费 | `enemy.gd:55-64` |
| 状态 | 只有 1 个动画 `idle`。移动感全靠程序化：侧摆 `dir.rotated(90°)×sin(_wobble)×0.35`；地面怪 hop（y=-10-hop×7，squash 1∓0.06/stretch 1+0.09）；飞行怪悬浮 bob（bat：y=-18±6，scale ±4%） | `enemy.gd:96-97`、`:129-137` |
| 朝向 | `sprite.flip_h = dir.x < 0` 硬切 | `enemy.gd:128` |
| 受击 | 白闪 0.1s（modulate 1+2.5k）+ 击退 320×mult 持续 0.16s + 眩晕原地发抖（rotation sin×30×0.15）+ 减速蓝染 (0.7,0.85,1.2) | `enemy.gd:87-91`、`:106-112`、`:119`、`:195-205 take_damage()` |
| 精英 | 金色脉动 `0.5+0.5sin(_elite_t×6)` 常驻 + 与白闪叠加公式 | `enemy.gd:79-86` |
| 死亡 | 无死亡帧：Tween squash 到 (1.3×, 0.3×) 0.16s + alpha 0.3s 淡出 + 尸体节点 | `enemy.gd:208-221 _die()` |

**Boss**（单张 Sprite2D，无帧动画）：

| 项 | 实况 | 证据 |
| --- | --- | --- |
| 待机 | 呼吸 scale.y ±4% @2Hz | `boss.gd:108-111` |
| 移动 | 倾斜 `clamp(velocity.x/400, ±0.12)` + 脚下扬尘 CPUParticles2D 16 粒 | `boss.gd:74-89`、`:133-140` |
| slam 前摇 | 0.4s 膨胀 +15% + 红闪（modulate 1+0.8wk, 1-0.4wk, 1-0.4wk）→ 红圈 Telegraph（draw_circle+draw_arc 1.0s）→ hazard | `boss.gd:117-125`、`:173-182`、`:9-21 Telegraph` |
| charge | 0.6s 蓄力白闪频闪 `1+0.6|sin(t×20)|` → 冲刺 0.65s @700px/s | `boss.gd:149-155`、`:142-148` |
| 受击 | squash 0.12s（+18%×, -22%y）+ 白闪 0.12s（×2.0） | `boss.gd:112-116`、`:213-219 take_damage()` |
| 死亡 | 40 粒橙色爆粒 + Tween scale (1.6, 0.4) 0.35s + 淡出 0.5s | `boss.gd:229-261` |

**结论**：Boss 全部 6 只共用这套程序化表现，只改数值不改演出（设计 P0-5）。`boss_mohei_phase2/3.png`、`boss_widow_b.png`、`chest.png` 三个关键资产已就绪但 0 引用——v0.8 动画的主战场就是让它们「动起来」。

### 1.4 帧资产实况（零新增的盘点结论）

| 目录 | 内容 | 接线状态 |
| --- | --- | --- |
| `characters/{aila,batong,mofei}/` | 每角色 20 帧（4 向 × idle 1 + walk 4） | 3 角色全接 ✓ |
| `enemies/` | 10 种 × 2 帧 idle（slime/bat/skeleton/brute/spitter/exploder/gargoyle/frost/spider/witchdoctor） | 接 4 种；**6 种未接**（§2 覆盖全部 6 种） |
| `bosses/` | 9 张单帧（colossus/batking/forgemaster/thorntyrant/mohei_phase1/2/3/widow_a/widow_b） | 接 6 张；mohei_p2/p3、widow_b 未引用 |
| `pickups/chest.png` | 单帧宝箱 | **0 引用**（§2.4 接线） |
| `fx/` | 15 张特效单帧（levelup/corpse_explosion/stomp_crack 等） | 部分在用 |

**确认：v0.8 动画侧零新增帧资产。** 所有新演出 = 现有单帧/双帧 + 程序化补间（modulate/scale/rotation/Tween/粒子）。无需向美术提任何新帧需求；仅一条备注：mofei 与 aila 同规格齐全，`batong` 缺省检查通过，无缺口。

---

## 二、新接线内容的动画方案

### 2.0 通用原则（6 敌人共用）

1. **2 帧 idle 不够做行为动画，也永远不做**：行为前摇/攻击全部程序化（squash & stretch + rotation + modulate + FX 光效），沿用 `enemy.gd:133-137` 已验证的 hop 语言。每怪每帧动画计算 ≈ 6 次属性赋值 + 2 次 `sin()`，60 只怪 < 0.1ms（依据见 §5.3）。
2. **前摇可读性铁律**：任何「即将造成伤害」的行为必须有 ≥0.4s 的、颜色编码的前摇（红=爆炸、绿=毒性/酸、金=精英、紫红=Boss 阶段）。v0.7 只有 Boss 有此前摇语言（`boss.gd:118-122`），v0.8 把它下放到新敌人。
3. SpriteFrames 每怪 new 的分配问题按架构 B4 修：按 `enemy_id` 静态缓存 10 份共享（动画侧无异议，支持）。

### 2.1 六种未接敌人的动画需求

设计终稿 §4.1 定 v0.8 接 spitter/exploder/gargoyle 三种，frost/spider/witchdoctor 留 v0.9——但动画方案一次性给全 6 种（后三种按同一模板，v0.9 直接套用），避免二次设计。

| 敌人 | 帧资产 | v0.8 动画方案（全程序化） | 时序/参数 |
| --- | --- | --- | --- |
| **spitter 喷吐怪**（远程，逼横向走位） | 2 帧 idle | ① 吐息前摇 0.4s：sprite 后仰 `rotation ∓0.18`（背向玩家侧）+ squash (1.08, 0.92) + 口部绿色 `FX.glow` 充能（36px→60px，alpha 随前摇线性升）；② 发射帧：前扑 squash (0.92, 1.10) 0.08s 回弹 + 反冲位移 12px；③ 酸弹：`projectile.gd` 绿 tint + 旋转（复用 boomerang 的 `_spin` 逻辑，`projectile.gd:95-97`） | 前摇 0.4s = 弹速 320px/s ÷ 射程 520px ≈ 玩家 1.6s 反应窗的前 1/4，可读且不拖沓 |
| **exploder 自爆怪** | 2 帧 idle | ① 距玩家 <70px 进入 1.0s 前摇：scale 1.0→1.45 分两段（0–0.6s 线性膨胀；0.6–1.0s 高频抖动 ±0.03）；② 红闪频率递增：modulate 红色脉冲间隔 0.15s→0.05s（复用 `boss.gd:118-122` 风格但频率爬升）；③ 引爆：`FX.explosion(pos, 130, 橙红)` + `FX.shake(10)` + hitstop 0.04（白名单事件，§3.1）；④ 若前摇被打断（死亡）：直接爆（保持威慑，不给"拆弹"玩法） | 膨胀幅度 1.45 上限——再大会读成精英。红闪递增是"倒计时"语言 |
| **gargoyle 石像鬼**（高甲坦克） | 2 帧 idle，**帧率降到 3fps**（石化质感，`sf.set_animation_speed("idle", 3.0)`） | ① 入场：从上方 80px 落下 0.3s（`position.y` tween EASE_IN）+ 落地小震 `FX.shake(4)` + 尘土（复用 boss `_dust` 参数减半，8 粒）；② 移动：hop 幅度减半（y -10-3.5，几乎贴地拖行，「重」的语言）；③ 受击白闪缩短到 0.06s 且幅度减半（×1.2 而非 ×2.5）——「打不动」的体感来自反馈变弱，而非数字 | 帧率 3fps 是唯一一处改 SpriteFrames 参数的方案，零成本 |
| **frost**（v0.9 预留） | 2 帧 idle | 常染冰蓝 modulate (0.75, 0.9, 1.15)（复用减速染色 `enemy.gd:119` 的常驻版）；攻击前摇复用 spitter 模板换冰蓝 | 模板 B：远程施法系 |
| **spider**（v0.9 预留） | 2 帧 idle | hop 频率 ×1.8（`_wobble` 步进 3.0→5.4）、幅度 ×0.7——「多而碎」的快速感；不新增任何状态 | 模板 C：贴身骚扰系 |
| **witchdoctor**（v0.9 预留） | 2 帧 idle | 完整复用 spitter 前摇模板（后仰+充能 glow），tint 换紫色；增益目标时给目标一次金色 glow 40px | 模板 B 变体 |

### 2.2 Boss phase2/3 切换（深渊主宰三阶段，mohei_phase1/2/3.png 已就绪）

设计终稿 §9.3 给了 0.8s 总时长与 FX 参数，本方案补齐动画侧的完整状态切换：

**状态机扩展**（boss.gd 现无阶段概念，建议加 `phase: int` + `_transition_t`，复用 `_windup_t` 的停走机制）：

```
[phase1 战斗] --HP≤2/3--> [phase_transition 0.8s] --t 到--> [phase2 战斗]
[phase2 战斗] --HP≤1/3--> [phase_transition 0.8s] --t 到--> [phase3 战斗→狂暴]
```

**phase_transition 0.8s 分镜**（60fps，T0 = HP 跨过阈值那一物理帧）：

| 时刻 | 表现 | 实现 |
| --- | --- | --- |
| T+0ms (F0) | Boss 进入无敌、velocity=0、`_tick_skills` 冻结；`FX.glow_ring(pos, 500, 紫红(0.85,0.3,0.7), 0.6, 6)` + `FX.shake(14)` + hitstop 0.10（白名单事件） | 复用 `boss.gd` 现有停走分支 |
| T+0–200ms | 白闪爬升到全白：modulate (1,1,1)→(3,3,3) 线性（additive 过曝即"白化"） | `_flash` 机制加长版 |
| T+200ms (F12) | **换贴图** `tex = boss_mohei_phase{p+1}.png`（全白遮掩下的单帧切换，玩家看不到跳变） | `_sprite.texture = load(...)` |
| T+200–600ms | scale punch ×1.30→1.00，0.4s，TRANS_QUAD EASE_OUT；modulate 白→常态 | Tween |
| T+400ms (F24) | 地面径向冲击环：复用 `Telegraph` 类改一次性 draw_arc（紫红，0.5s，r 70→320，宽 8→2） | `boss.gd:9-21` 变体 |
| T+800ms | 恢复行动；slam/charge/summon CD 按新阶段参数重置（P3: 3.0/5.0/10.0） | `_tick_skills` 参数表 |

音效 `boss_phase`（roar+sweep 0.6s）在 **T+100ms** 播——避开 F0 的 hitstop 瞬间，落在视觉爬升段。P3 狂暴态追加：呼吸频率 2Hz→4Hz（`_wobble` 步进 ×2）+ modulate 常驻 (1.2, 0.8, 0.8)。

**双生亡语者（widow_a/b）**：widow_b 走 `boss.gd` 同一个场景实例化，零新动画。狂暴态（另一只死后）= 上述狂暴 modulate + 移动倾斜幅度 ×1.5，无新状态。

**其余 4 Boss**：只换技能参数（设计 §4.3），动画不动。唯一例外：熔渣铸造者 slam 留灼烧地——Telegraph 红圈保持 1.0s 后不消失，转为低透明度橙色常驻圆（alpha 0.12）直到灼烧结束，程序化，零新资源。

### 2.3 精英登场演出（0.5s）

现状只有常驻金脉动（`enemy.gd:79-86`）。v0.8 在 `main.gd` 精英生成点补「登场三件套」：

| 时刻 | 表现 |
| --- | --- |
| T+0 | scale 从 0.3 → base_scale×1.3（精英倍率），0.35s，TRANS_BACK EASE_OUT（过冲弹入） |
| T+50ms | `FX.glow_ring(pos, 60, 金(1.0,0.85,0.3), 0.4, 5)` 一次性 |
| T+250ms | 常驻金脉动启动（现有逻辑）；toast「精英会掉落遗物」（新手引导 T+90s 节点共用） |

### 2.4 宝箱开启（0.6s，chest.png 单帧）

单帧宝箱没有"盖子弹开"帧，程序化模拟开箱语言：

| 时刻 | 表现 |
| --- | --- |
| T+0 | 玩家接触（PICKUP_RADIUS 26px 判定复用）；箱子 squash (1.25, 0.75) 0.1s（压扁蓄力） |
| T+100ms | 弹起 (0.85, 1.18) 0.15s 回弹到 1.0——「盖子弹开」的替代语言；**hitstop 0.06（白名单）** + `FX.shake(8)` |
| T+100ms | `FX.glow(pos, 240, 金, 0.5)` + `FX.glow_ring(pos, 140, 金, 0.5)`（复用合成配色 `player.gd:1102-1103`） |
| T+150ms | 遗物图标 Sprite 从箱口 (0,-20) 升到 (0,-56) 并悬停脉动，0.4s TRANS_QUAD EASE_OUT；随后飞向玩家 |
| T+150–450ms | 3–5 颗 `coin.png` 抛物线弹出（Tween 初速 vy=-160、重力 600，落地弹跳 1 次），延迟拾取 0.5s |
| 音效 | 现有 `coin` + `levelup` 叠播（零新音频的兜底方案；音效侧若加 `chest` 专用音色则替换） |

---

## 三、打击感方案

### 3.1 hitstop 新契约（与 A1 重构协同的总纲）

v0.7 的病根：`fx.gd:245-254` 把 `Engine.time_scale` 压到 0.05，`projectile.gd:119` **每次非暴击命中**都调用 → 割草高频命中下计数永不归零，全场长期 5% 速跑（架构实测 time_scale=0.050）。调用点共 9 处：`projectile.gd:119`、`player.gd:642/799/847/1105/1226/1296/1333/1429/1455`、`summon.gd:202`。

**v0.8 契约（动画侧对程序的唯一要求）**：

1. `FX.hitstop(tree, duration)` **签名不变**，内部加**全局冷却窗口 0.15s**：冷却期内再次调用直接丢弃（不排队、不叠加）。架构 §9.4 已按此口径约定。
2. **白名单制**：普攻命中（`projectile.gd:119`）**从白名单移除**——普通命中的反馈由白闪+击退+局部形变承担（§3.2），不再全局顿帧。白名单仅保留：

| 事件 | hitstop 时长 | 触发点 |
| --- | --- | --- |
| 暴击 | 0.05s | `projectile.gd:116` 暴击分支（现只 shake，补 hitstop） |
| 击杀普通怪 | 0.04s | `enemy.gd:208 _die()`（加一次） |
| 击杀精英/Boss | 0.08s / 0.10s | 同上，按 elite/is_boss 分级 |
| 玩家大招（stomp/meteor/soul_drain） | 0.06s | `player.gd:1296/1429` 保留 |
| 完美格挡 | 0.05s | `player.gd:1455` 保留 |
| 自爆怪引爆 | 0.04s | exploder 引爆点 |
| Boss 阶段转换 | 0.10s | §2.2 |
| **超武合成** | **0.12s（全局最长，唯一"导演级"顿帧）** | `player.gd:1105` 保留 |
| 宝箱开启 | 0.06s | §2.4 |

3. 白名单事件**每秒命中上限 ≈6 次**（0.15s 冷却的自然结果）。最坏情况（割草暴击流）下全局时间损失 ≈ 6×0.05/1s = 30% 慢放感——这是**有意的爽感上限**，且每次都伴随暴击金光，玩家读作「手感」，而不是 v0.7 的无差别全场减速。

### 3.2 命中反馈分层（普攻命中的顿帧替代包）

普通命中 = 以下 5 层同时发生（全部已有代码基础，只调参数）：

| 层 | 现状 | v0.8 参数 | 证据/改动 |
| --- | --- | --- | --- |
| ① 受击白闪 | 0.1s modulate ×2.5 | **0.08s ×2.5**（略提频，补偿失去的顿帧） | `enemy.gd:87-91`，`_flash_t` 0.1→0.08 |
| ② 局部形变 | 无 | 受击瞬间 scale punch ×1.12 → 1.0 回弹 0.1s（叠加在 hop squash 上，`target_scale` 乘法合成） | `enemy.gd:137` 处加一项 |
| ③ 击退 | 320×mult / 0.16s | **320×mult / 0.12s**（更脆更弹） | `enemy.gd:200-201` |
| ④ 命中火花+音效 | `FX.hit_spark`（glow 56px + 8 粒）+ `Sfx.play("hit")` | 不变；A9 节流下每帧 ≤6，超出降级「仅伤害数字」 | `fx.gd:178-200` |
| ⑤ 伤害数字 | Label + tween 0.6s | 不变（暴击 34 号字金色 / 普通 20 号白） | `fx.gd:203-223` |
| ⑥（暴击专属） | shake 10 + 金 glow 110 | **+ hitstop 0.05（进白名单）** | `projectile.gd:115-118` |

**玩家受击**（反向打击感，提示"你被打到了"）：白闪 0.12s + 击退 280 + 无敌闪烁 0.7s + `Sfx.play("hurt")` 全部保留（`player.gd:1443-1470`），追加 `FX.shake(6)`（现状玩家受击无屏震，这是全游戏最该震而没震的一刻）。

### 3.3 屏震参数总表

现状实现：`fx.gd:226-240 shake()` = 3 段随机 offset（各 0.04s）+ 回中 0.06s，总 0.18s。**维持此实现不换系统**，但给程序两条修正：① 同帧多次 shake 会创建多个 Tween 互相打架 → 改为单字段 `max(strength)` 单 Tween；② 震幅按事件分级锁死：

| 事件 | strength | 感受定位 |
| --- | --- | --- |
| 普通暴击 | 6 | 轻叩（v0.7 是 10，偏晕，下调） |
| 玩家受击 | 6 | 新增（§3.2） |
| 精英登场落地 | 4 | §2.3 |
| 石像鬼落地 | 4 | §2.1 |
| 自爆怪引爆 | 10 | 与 `FX.explosion` 内置 6 取 max → 10 |
| stomp / meteor | 12 | `player.gd:1295` 保留 |
| Boss slam 落地 | 10 | 新增（现状 slam 无震） |
| Boss 阶段转换 | 14 | §2.2 |
| 超武合成 | 14 | `player.gd:1104` 保留 |
| 宝箱开启 | 8 | §2.4 |

### 3.4 超武合成演出分镜（爽点 ①，时序精确到 ms）

现状（`player.gd:1101-1106`）：glow 300 + glow_ring 170 + shake 14 + hitstop 0.12 + Sfx **同帧齐发**——五件事挤在 F0，等于没有分镜；且音效在 time_scale=0.05 的顿帧里播（WebAudio 旁路不受 time_scale 影响），音画是脱节的。

**v0.8 分镜（T0 = 玩家在三选一浮层点下「合成」按钮）**：

| 时刻 | 帧 | 表现 | 复用 |
| --- | --- | --- | --- |
| T+0ms | F0 | 升级浮层关闭、游戏恢复；**hitstop 0.12s（全场定格）**；金色 `FX.glow(pos, 300, (1.0,0.85,0.3,0.95), 0.8)` 淡入 | `player.gd:1102/1105` |
| T+16ms | F1 | 金色 `FX.glow_ring(pos, 170→196, 0.6s)` 扩张（EASE_OUT） | `player.gd:1103` |
| T+80ms | F5 | `FX.shake(14)` 起振（0.18s）——定格里镜头先动，解除瞬间的爆发感 | `player.gd:1104` |
| **T+120ms** | F7 | **hitstop 解除，time_scale 回 1.0；`Sfx.play("superfuse")` 此刻起播**——上行琶音精确压在「解除定格」的爆发点上（音效侧升级：现音色 + `_arp` 琶音层） | 音画同步核心改动 |
| T+120–370ms | F7–F22 | 玩家 `Visual` scale punch ×1.25→1.0（0.25s TRANS_QUAD EASE_OUT）+ 金色 modulate (1.3,1.2,0.7) 叠加 0.4s 淡出 | 程序化，零资源 |
| T+200ms | F12 | 金色上升粒子 30 粒（复用 `fx.gd:275-293 levelup_beam` 的 rise 粒子全参数，tint 换金） | `FX.levelup_beam` 抽出粒子段 |
| T+300ms | F18 | HUD 武器栏图标替换 + 金框脉动（HUD 层，Tween 循环） | `hud.gd` 装备栏 |
| T+800ms | — | 全部余晖结束 | — |

节点峰值 +4（glow、ring、rise、1 组 Tween），DrawCall 影响 ≈ +3（见 §5.4 材质共享后）。全程 0.8s，期间玩家照常可操作（浮层已关），演出不打断玩法。

---

## 四、L3 波次 / L4 房间对动画的影响

### 4.1 敌人转向插值（波次高密度下的观感问题）

现状 `flip_h` 硬切（`enemy.gd:128`）在 60 只同屏时会产生大量"集体翻面"的跳变。最小方案（零新状态）：

1. **移动倾斜**：`sprite.rotation = lerp(sprite.rotation, clamp(velocity.x/600, -0.1, 0.1), 12×delta)`——与玩家 lean（`player.gd:187-188`）同参数，群体动势统一。
2. **翻面时机绑 hop**：`flip_h` 的赋值移到 hop 相位的落地帧（`sin(_wobble×2)` 过零点）执行——翻面发生在"离地-落地"的形变瞬间，肉眼不可见。成本：一个 if。
3. 转向不改帧资产、不改状态机，60 怪满屏时每帧增量 ≈ 1 次 lerp + 1 次比较/怪，<0.02ms。

### 4.2 波次刷怪出场动画（三波制的中局成批出现）

设计 §5.1：3 波 60/25/15，第 2/3 波在战斗中成批出现，**不允许瞬移出现**（读作 bug）。最小方案 0.4s：

| 时刻 | 表现 |
| --- | --- |
| T+0 | 敌人节点落位（碰撞即激活，逻辑无延迟——表现与逻辑分离）；地面预告：紫黑 theme 色 `FX.glow(pos, 40, (0.5,0.3,0.8,0.5), 0.35)` |
| T+0–350ms | sprite scale 0.3→base_scale，TRANS_BACK EASE_OUT + modulate.a 0→1（0.25s） |
| T+350ms | 进入正常 idle/hop；金脉动（精英）此后启动 |

**与 A9 节流的协同**：第 1 波 27 只（第 29 层峰值）同帧入场时，预告 glow 会被"每帧 ≤6"节流——约定**出场动画中 scale 弹入永远执行、预告 glow 可被节流丢弃**（弹入本身已足够传达"刚出现"）。

### 4.3 房间过渡（L4 程序化房间）

镜头是跟随玩家的（`player.tscn:30-36`，无房间切换镜头），所以过渡用最轻的方案：

1. **踩楼梯**：复用现有楼梯流程，追加 `FX.glow_ring(stairs_pos, 90, 白, 0.3)` + HUD 全屏 ColorRect alpha 0→1（0.25s）→ 清场切层 → 1→0（0.25s）。玩家输入锁定 ≤0.5s。
2. **Camera2D limits**：现状写死 1600×1200（`player.tscn:33-36`）。L4 每层生成后由程序调 `set_limit()` 按房间包围盒设置——**给程序的接口项**，不是动画工作，但若漏掉，L4 的小房间会出现"镜头看穿墙外"的破绽。
3. 房间内**不做**暗角/雾效/门帘动画：预算（§5）不允许，且遮挡视线与割草玩法冲突。

---

## 五、性能预算（动画系统专项）

### 5.1 帧资产与内存

- 全部帧动画 = 玩家 3×20 帧 + 敌人 10×2 + Boss 9 单帧 + 召唤物 4×2 + FX 15 + pickups 7 ≈ **112 张小纹理**，无图集化必要（A5 烘焙后它们是仅剩的散纹理）；VRAM 估算 < 4MB << 45MB 预算（02 §3）。
- **不做任何帧数扩充**：本方案全部演出基于现有帧 + 程序化补间。SpriteFrames 共享（B4）后全程 SpriteFrames 对象 = 10+3+4 份，不再是每怪一份。

### 5.2 AnimationPlayer vs 代码驱动：结论 = 继续全代码驱动

| 方案 | 判定 | 理由 |
| --- | --- | --- |
| AnimationPlayer + .tres | **否** | ① 60 只怪 × 随机相位 × 参数化效果（sin 频率、modulate 混色），时间轴动画无法表达「每怪独立的 `_wobble` 相位」；② Web GDScript 无 JIT，AnimationPlayer 每帧 track 采样 + 属性路径解析不比手写赋值便宜；③ 现有代码驱动已覆盖全部需求且经过 v0.7 验证 |
| 代码驱动（现状） | **是** | Tween 已内建缓动/循环/并行，`modulate/scale/rotation` 逐帧计算可读可控；与 A9 池化兼容 |

唯一约束：**禁止在 `_physics_process` 里 new Tween/材质/粒子节点**——高频路径只做属性赋值；一次性演出（合成/开箱/转换）用"节点级 `create_tween()`"现状模式即可（频率 ≤1 次/事件）。

### 5.3 逻辑开销数字

| 项 | 数值 | 依据 |
| --- | --- | --- |
| 每怪每帧动画计算 | ≈ 6 次属性赋值 + 2 次 sin + 1 次 lerp ≈ **0.0015ms/怪**（GDScript 桌面口径） | 按 02 §6 实测外推：200 怪全逻辑 4.0ms，动画段占比 <8% |
| 60 怪满屏动画段 | **≈ 0.1ms/帧**，占物理预算 4.0ms 的 2.5% | 同上 |
| 白闪命中峰值 | 每帧 ≤6 次（FX 节流），每次 = 1 modulate 赋值 + 复活 1 个 Tween | `fx.gd` A9 口径 |
| 同屏 CPUParticles2D 上限 | **≤ 6 组**（玩家 dust 1 + boss dust 1 + 命中 spark ≤6 节流；出场/合成粒子计入同一预算） | Web 上 CPU 粒子最贵（02 §1.2 T4），合成 rise 30 粒属一次性例外 |
| Tween 存活数 | 每实体 ≤2（hop 无 Tween、死亡 1、出场 1）；全局无需上限（Godot Tween 本身轻量） | 代码审查口径 |

### 5.4 DrawCall 侧（动画相关的两项）

1. **`fx.gd:297-300 _additive_mat()` 每次 new CanvasItemMaterial 必须改共享单例**（架构 A5 已列，动画侧背书）：每份独立材质打断 2D 批处理，特效密集帧（合成/自爆/波次入场叠加）实测级影响 30–60 draw call。共享后同帧 glow/ring 全部合批。
2. 动画新增视觉全部是 `modulate/scale`（不换材质、不换纹理）→ **对 DrawCall 零增量**。§2 全部方案 + §3 分镜的 DrawCall 增量合计 ≤5（同屏时的 glow/ring 叠加），在 250 预算内。

---

## 六、给特效 / 程序的接口说明（时序对齐点）

### 6.1 与 hitstop（程序，A1）

- `FX.hitstop(tree, duration)` 签名不变；内部加 0.15s 全局冷却 + 白名单（§3.1 表）。**`projectile.gd:119` 的普攻调用删除**。
- 所有演出时序按「hitstop 只发生在白名单事件」设计；若 A1 实现口径有变（例如完全去掉全局顿帧、只做局部 time_scale），§3.1 白名单事件降级为「白闪 ×2.0 + shake +2」，分镜（§3.4/§2.2）各减 0.12s/0.10s 定格段，其余不变。

### 6.2 与特效（vfx-director）

| 对齐点 | 参数 | 出处 |
| --- | --- | --- |
| 自爆 | `FX.explosion(pos, 130, 橙红)` + shake 10 + hitstop 0.04 | §2.1 = 设计 §9.4 ✓ |
| Boss 阶段转换 | `FX.glow_ring(pos, 500, (0.85,0.3,0.7), 0.6, 6)` + shake 14 + hitstop 0.10 | §2.2 = 设计 §9.4 ✓ |
| 宝箱 | glow 240 + ring 140 金色 | §2.4（设计 §9.4 写"复用合成参数 300/170"，开箱降一档避免与合成撞演出） |
| spitter 充能 | glow 36→60 绿，前摇期内渐亮 | §2.1 |
| FX 节流例外表 | 出场弹入不可节流、预告 glow 可节流；hit_spark/damage_number 按架构 §4.4 每帧 6 | §4.2 |

### 6.3 与音效（audio-director）

| 对齐点 | 时序 |
| --- | --- |
| `superfuse` | **从 F0 移到 T+120ms（hitstop 解除帧）**——这是全方案最重要的一处音画同步修正 |
| `boss_phase` | T+100ms（视觉白化爬升段） |
| `enemy_shot` / `exploder` | 前摇结束的发射/引爆帧（§2.1 时序表） |
| 开箱 | T+100ms（弹起帧），`coin` 拾取音不变 |
| hit 音 | throttle 0.12s 维持（`sfx.gd` 现状） |

### 6.4 与程序（tech-architect / 主程序）

1. boss.gd 加 `phase: int` + `phase_changed(phase)` 信号（进 EventBus，对齐 02 §4.5），特效/音效/HUD 各自监听；转换期 Boss 无敌 + 停 `_tick_skills`。
2. `main.gd` 精英/波次生成点需要暴露出生回调（或 spawn 函数内联 §2.3/§4.2 的入场段）。
3. L4：`Camera2D.set_limit()` 按层调用（§4.3-2）；楼梯过渡的 HUD ColorRect 由 ui 层做。
4. enemy.gd SpriteFrames 按 enemy_id 静态缓存共享（B4，动画侧无异议）。
5. `fx.gd:226 shake()` 改单 Tween max 合并（§3.3）；`_additive_mat()` 共享单例（§5.4）。
6. 命名规范：新增演出节点/函数沿用现有前缀——入场演出 `intro_`（如 `_intro_pop()`）、阶段转换 `_phase_transition()`、宝箱 `_chest_open()`；无新增动画资源文件，故无资源命名增量。

### 6.5 优先级

| 级 | 内容 | 对应爽点 |
| --- | --- | --- |
| P0 | §3.1 hitstop 契约 + §3.2 命中分层 + §3.4 合成分镜 | 爽点 ①（第一次合成）+ 全局手感 |
| P1 | §2.2 Boss 三阶段转换 + §2.1 exploder 前摇 + spitter 前摇 + §2.4 宝箱 | 爽点 ②③④ |
| P2 | §2.3 精英登场 + §4.2 波次出场 + §4.1 转向插值 | 爽点 ②⑤ 的观感保底 |
| P3 | gargoyle 落地/帧率、frost/spider/witchdoctor（v0.9 模板） | 内容完备性 |

---

*方案完。全部现状结论可按 §1 各表行号复核；全部演出参数（时长/幅度/颜色/时序帧）可直接作为程序实现验收值。*
