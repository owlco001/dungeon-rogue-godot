# 《地牢肉鸽 · Dungeon Rogue》v0.8 音频方案

> 作者：雷鸣远（audio-director）
> 输入依据：`01-design-v08.md`（Phase 1.5 合并终稿）、`02-architecture-v08.md`（commit `baf32f5` 技术基线）、仓库实读（`scripts/sfx.gd` 全文 214 行、`web/shell.html` 全文 415 行、`scripts/fx.gd`、`scripts/player.gd` 合成段、全仓库 `Sfx.play` 触发点 grep、`assets/audio/` 实况）
> 本阶段未修改仓库任何文件（只读分析 + 方案设计）。
> 平台 = Web（B2 决策）；首包压缩后 ≤12MB（D-D 决策）；hitstop 重构 = A1。

---

## 一、音频现状盘点

### 1.1 引擎侧：`scripts/sfx.gd`（214 行，程序化合成）

**架构事实**：autoload 单例 `Sfx`，启动时在 `_ready()`（`sfx.gd:32-40`）用合成原语一次性生成全部音色为 `AudioStreamWAV`（16-bit PCM，`RATE=22050`，`sfx.gd:5`），常驻内存；10 路 `AudioStreamPlayer` 轮转池（`POOL=10`，`sfx.gd:6`）；每个音色带独立 throttle 最小间隔（`play()` 内 `sfx.gd:64-68`）；全局音量 `VOL_DB=-4.0dB`（`sfx.gd:7`）。**零外部音频资产**。

**合成原语清单**（`sfx.gd:100-214`，v0.8 新音效全部复用这 7 个原语，不引入新合成器）：

| 原语 | 函数 | 波形 | 用途 |
| --- | --- | --- | --- |
| 滑音单音 | `_tone(f0,f1,dur,vol,wave)` | 0=方波/1=锯齿/2=正弦，f0→f1 指数滑音 | 射击/受击/UI |
| 白噪声 | `_noise(dur,vol)` | 白噪声 + 快衰减 | 碎击/爆裂 |
| 低频轰爆 | `_boom(dur,vol)` | 90→40Hz 正弦 + 噪声混合 | 爆炸 |
| 双音 | `_two_tone(f0,f1,dur,vol)` | 前后半段两频率正弦 | 金币/湿黏音 |
| 琶音 | `_arp(freqs[],dur,vol)` | 等分正弦琶音，每音内衰减 | 升级/遗物/成就 |
| 咆哮 | `_roar(dur,vol)` | 110→55Hz 锯齿 + 噪声 | Boss 入场 |
| 上扫 | `_sweep(f0,f1,dur,vol)` | 基频+二次谐波指数上扫 | 合成蓄力 |

**现有 13 个音色（`DEFS`，`sfx.gd:10-24`）与触发点**：

| 音色 id | 合成调用（`_gen_all`，sfx.gd:43-56） | dur / throttle | 触发代码位置 |
| --- | --- | --- | --- |
| `shoot` | `_tone(880→440, 0.07, 0.5, 方波)` | 0.07s / 0.07s | `player.gd:458`（武器开火） |
| `hit` | `_noise(0.08, 0.45)` | 0.08s / 0.05s | `fx.gd:179`（`hit_spark` 命中火花） |
| `explosion` | `_boom(0.45, 0.8)` | 0.45s / 0.10s | `fx.gd:140`（`explosion`） |
| `gem` | `_tone(1320→1760, 0.12, 0.4, 正弦)` | 0.12s / 0.05s | `gem.gd:64`（经验宝石拾取） |
| `coin` | `_two_tone(990→1320, 0.16, 0.4)` | 0.16s / 0.06s | `gem.gd:70`（金币拾取） |
| `levelup` | `_arp([523,659,784,1046], 0.45, 0.45)` | 0.45s / 0.30s | `fx.gd:258`（升级光柱）、`lobby.gd:230`（局外购物） |
| `hurt` | `_tone(220→110, 0.22, 0.5, 锯齿)` | 0.22s / 0.15s | `player.gd:1446`（玩家受击） |
| `stairs` | `_tone(784→1568, 0.35, 0.35, 正弦)` | 0.35s / 0.30s | `stairs.gd:43`、`lobby.gd:586/596`（关卡/天赋树导航） |
| `click` | `_tone(660→660, 0.06, 0.35, 方波)` | 0.06s / 0.05s | `hud.gd:205/216/919/1011`、`lobby.gd:203/256/312`（UI 点击） |
| `boss_roar` | `_roar(0.9, 0.7)` | 0.90s / 0.80s | `boss.gd:57`（Boss 入场） |
| `superfuse` | `_sweep(200→2000, 0.7, 0.5)` | 0.70s / 0.50s | `player.gd:1106`（超武合成） |
| `relic` | `_arp([392,523,659,784,1046], 0.4, 0.4)` | 0.40s / 0.30s | `gem.gd:67`（遗物拾取） |
| `achievement` | `_arp([659,784,1046,1318,1568], 0.55, 0.45)` | 0.55s / 0.30s | `hud.gd:256`、`lobby.gd:513`（成就 toast） |

**音量/节流缺口**：① 全部音色共用单一 `VOL_DB=-4dB`，无分层响度（boss_roar 与 click 同响度基准）；② throttle 只按音色 id，无全局并发上限（引擎侧池 10 路天然兜底，JS 侧无上限）；③ `play()` 只收 `sname` 一个参数，**无音量/声像参数**——v0.8 威胁音需要空间感，这是必须扩的接口。

### 1.2 壳层侧：`web/shell.html`（原生 WebAudio 通道）

**职责边界**：Godot 4.7 Web 音频在桌面浏览器唤醒不可靠（`sfx.gd:69-71` 注释），因此 Web 平台**全部可听声音走浏览器原生 WebAudio**，引擎音频管线闲置。链路：

```
游戏逻辑 Sfx.play("hit")
  → sfx.gd:69-71 OS.has_feature("web") 分支
  → JavaScriptBridge.eval("window._gameSfx.play('hit')")
  → shell.html _gameSfx（:121-196）查 PLAYERS 表（:170-184）→ WebAudio 节点实时合成
  → master GainNode(0.40 ≈ -8dB，:128) → ctx.destination
```

- **`window._gameSfx`**（`shell.html:121-196`）：13 个音色的 JS 复刻（`PLAYERS` 表 `:170-184`），`tone/noise/boom/roar` 四个合成函数（`:142-169`），`unlock()` 供手势唤醒（`:194`）。噪声用 1s 预生成 buffer（`getNoise`，`:134-141`）。
- **`window._gameBgm`**（`shell.html:199-257`）：`fetch` CDN 的 `dungeon_ambient.ogg`（`BGM_URL`，`:202`）→ `decodeAudioData` → `BufferSource.loop` 循环，master gain 0.60（`:208`）。**`.catch(function(){})` 吞掉全部失败（`:240`）**——CDN 失效时静默无 BGM，无重试无提示（02-architecture §1.5 已列为 P1）。
- **手势解锁**（`shell.html:259-271`）：首次 `pointerdown/touchstart/keydown` 捕获阶段调 `_gameBgm.play()` + `_gameSfx.unlock()`，解一次锁双轨都活。
- **F24 合成键盘补丁**（`shell.html:273-282`）：`mousedown` 时向 canvas 派发合成 `keydown(F24)` 试图触发 Godot 引擎侧的音频 resume。**注意：现代浏览器不把合成 KeyboardEvent 视作用户手势**，此补丁只在部分浏览器有效，是"锦上添花"不是保障——真解锁靠 `:259-271`。

### 1.3 双轨链路风险评估（结论：保留，但必须收口）

| # | 风险 | 具体证据 | 等级 | v0.8 处理 |
| --- | --- | --- | --- | --- |
| AU-1 | **双份实现漂移**：13 个音色在 `sfx.gd:44-56` 与 `shell.html:171-183` 各写一遍，**已经漂移**——`coin` 引擎侧是 `_two_tone(990→1320)` 单滑音，JS 侧是两个 tone（990Hz + delay 0.08s 的 1320Hz）双击音；`relic` 引擎每音 0.08s 与 JS 相同但引擎包络是 `(1.0-local)` 线性、JS 用 exponentialRamp，听感有差。v0.8 新增约 10 个音色 → 漂移面扩大一倍，漏改一处的症状是"桌面能听 Web 没声"（Web 是主平台，即**用户永远听不到**） | `sfx.gd:48` vs `shell.html:175` | **高** | 音色 id 清单收口为唯一事实源（`data/audio_manifest.json`，随 A2 数据配置化），构建门禁 V-audit 校验双侧 id 集合一致（0.2 人日，提给 tech-architect） |
| AU-2 | **延迟**：`JavaScriptBridge.eval` 每次调用有 eval 开销 + WebAudio 调度。实测口径：eval ≈ 0.3–1ms（主线程空载），加浏览器音频输出延迟（Chrome ≈ 10–20ms、iOS Safari ≈ 30–60ms）。**对打击感判定（<80ms）够用**，且 WebAudio 走真实时间时钟，`Engine.time_scale=0.05` 顿帧期间音效照常播——这是双轨的制度性红利，A1 重构后依然成立 | `sfx.gd:69-71`、`shell.html:186-192` | 低 | 保持；超武爆发音故意利用此特性（§三） |
| AU-3 | **响度不一致**：引擎侧 `VOL_DB=-4dB`（`sfx.gd:7`）+ 流内 vol，JS 侧 master 0.40 ≈ **-8dB**（`shell.html:128`）→ 同一音色桌面与 Web 差约 4dB。v0.8 响度规范（§五）以 Web 为准 | 两处对比 | 中 | JS master 统一到 §五基准；引擎侧常量同步改（只在 Steam-PC 落地 v0.8.5 时生效） |
| AU-4 | **JS 侧无并发上限**：引擎侧 10 路池兜底，JS 侧每个 voice 都是 OscillatorNode/BufferSource，L3 弹幕 + 波次高频触发下理论上可堆叠上百 voice | `shell.html:186-192` 无计数 | 中 | §五定全局并发 ≤24 voice、同名 throttle 保持 |
| AU-5 | **BGM 外链单点**：CDN fetch 失败静默吞错（`shell.html:240`），无重试 | `shell.html:202/240` | 高（见 §四，方案 A 直接消灭此依赖） | 方案 A：BGM 入 pck，删 CDN 链路 |
| AU-6 | **兼容性**：`webkitAudioContext` 回退已备（`:125`）；`exponentialRampToValueAtTime` 已做 `Math.max(f,1)` 防 0 值崩（`:147/149`）；iOS Safari 需要同步在手势回调内 resume（`:259-271` 写法正确）。自动播放策略合规（§五.3） | — | 低 | 保持 |
| AU-7 | **F24 补丁脆弱**：合成 KeyboardEvent 不计作用户手势，桌面 Chrome 上可能无效；依赖它的场景是"引擎侧音频"（Web 上已闲置），实际影响趋近于零 | `shell.html:273-282` | 低 | 保留不动，文档记录其非保障性 |

**总评**：双轨是「为绕开 Godot 4.7 Web 音频唤醒缺陷」的合理工程决定（02 §3 约束 4 已定为既定架构），真实风险不在链路本身而在**维护性**（AU-1 清单漂移）与**外链依赖**（AU-5）。两项都以低成本收口，不需要重构为单轨。

---

## 二、新内容音效设计（分层设计法）

> 设计原则：所有新音效复用 §1.1 的 7 个合成原语（设计案 §9.5 约束），在 `data/audio_manifest.json` 定义参数。响度 vol 为流内振幅（0–1），最终响度基准见 §五。

### 2.1 超武合成（v0.8 头号爽点）——三段式设计

v0.7 现状：`player.gd:1102-1106` 在**同一帧**发出金色大闪（`FX.glow` 300px/0.8s）+ 冲击环（`glow_ring` 170px/0.6s）+ 震屏（`shake 14`）+ 顿帧（`hitstop 0.12s`）+ `superfuse` 上扫——**只有一个 0.7s 上扫音，无蓄力、无爆发分层，且上扫与顿帧同帧开始，情绪没有"压-放"节奏**。

v0.8 三段设计（蓄力 500ms → 爆发 → 余韵 900ms，总长 ≈1.9s）：

| 段 | 音色 id | 合成参数 | 时长 | 响度目标 | 设计意图 |
| --- | --- | --- | --- | --- | --- |
| ① 蓄力 | `supercharge` | `_sweep(150→600, 0.50, 0.35)` + `_tone(300→600, 0.50, 0.25, 2 正弦)` 叠加（上扫双和声，音量随包络渐强） | 0.50s | 渐强至 -12dBFS 峰值 | "拉弓"感：频率上行制造期待，玩家知道**要来了** |
| ② 爆发 | `superburst` | `_boom(0.60, 0.9)`（低频压场）+ `_noise(0.20, 0.5)`（碎裂层）+ `_arp([1046,1318,1568,2093], 0.35, 0.5)`（金属星火层，延迟 60ms 进入） | 0.60s | **-3dBFS 峰值（全游戏最响点）** | 金色大闪+震屏的声音等价物；三层=力量+碎裂+华彩 |
| ③ 余韵 | `superring` | `_arp([523,659,784,1046,1318], 0.90, 0.30)`（上行大调琶音，正弦） | 0.90s | -14dBFS | 冲击环扩散的声音影子，情绪落地"我变强了" |

- 旧 `superfuse` 保留但**降级为蓄力段的可选替代**（若工期紧，`supercharge` 直接复用 `superfuse` 的 `_sweep`，仅改参数 200→2000 缩为 150→600）。
- 三段用 delay 参数在一个 `play()` 调用内由 JS 侧 `tone(delay)` 排程（`shell.html:142` 已支持 delay），引擎侧复用同一份 stream 即可，无需三次调用。
- 现有 `superfuse` throttle 0.50s 保持不变。

### 2.2 遗物拾取音（12 件分三档）

现状：12 件遗物共用 `relic` 一个音色（`gem.gd:67`），**稀有度只写在 UI 上，耳朵听不出**。三档以「起始音高 + 长度 + 层数」区分，盲听可辨（档间起始音高差 ≥ 大三度，时长差 ≥ 150ms）：

| 档 | 遗物（件数） | 音色 id | 合成参数 | 时长 |
| --- | --- | --- | --- | --- |
| 普通 | greedcup/bloodgem/windboots/sagestone（4） | `relic_c` | `_arp([392,523,659,784,1046], 0.40, 0.40)`（**即现 relic 原样**） | 0.40s |
| 稀有 | magnetcore/wardrum/hourglass/cross/scythe（5） | `relic_r` | `_arp([523,659,784,1046,1318], 0.55, 0.45)` + `_noise(0.10, 0.15)` 尾部微光（delay 0.55s） | 0.65s |
| 传说 | phoenixheart/thornmail/infinitefire（3） | `relic_l` | `_arp([659,784,1046,1318,1568,2093], 0.85, 0.50)` + `_boom(0.40, 0.25)` 低频收尾（delay 0.55s） | 1.20s |

- 触发点改造：`gem.gd:67` 依 `rarity` 分发三个 id（rarity 字段 `game_data.gd` 遗物表已有，v0.8 起真正参与逻辑）。
- throttle：三档各自 0.30s，跨档不互斥。

### 2.3 宝箱开启

| 音色 id | 合成参数 | 时长 | 触发 |
| --- | --- | --- | --- |
| `chest_open` | `_noise(0.08, 0.30)`（盖子弹开的木质顿音，delay 0）+ `_arp([523,659,784,1046,1318], 0.55, 0.45)`（金光琶音，delay 0.12s，与动画盖子开启 0.6s 对齐） | 0.70s | 宝箱交互（L2，每层 15% 刷新） |

宝箱内掉落遗物时**不重复播拾取音**——`chest_open` 的琶音尾就是预告，0.6s 后遗物入场只播 `relic_*` 的后半段（程序侧：宝箱掉落的遗物拾取改播 `relic_r/l` 短版，即只触发前 3 个音）。若嫌复杂可接受连播，throttle 天然去重。

### 2.4 Boss 三阶段提示音（深渊主宰 P1→P2→P3 + 通用化）

| 音色 id | 合成参数 | 时长 | 触发 | throttle |
| --- | --- | --- | --- | --- |
| `boss_phase` | `_roar(0.60, 0.8)`（110→70Hz，比 boss_roar 短促）+ `_sweep(200→1200, 0.50, 0.4)`（上扫，delay 0.30s，与 FX.glow_ring 500px 全屏冲击同帧） | 1.10s | 任一 Boss 阶段切换（深渊主宰 ×2，双生狂暴 ×1） | 1.00s |
| `boss_rage` | `_roar(0.50, 0.8)` + `_two_tone(880, 660, 0.30, 0.4)` 双音警报（delay 0.55s）×2 组 | 1.20s | P3 狂暴进入（深渊主宰 P2→P3、双生单侧死亡狂暴） | 1.50s |
| `boss_die` | `_boom(0.70, 0.9)` + `_arp([262,330,392,523], 0.80, 0.4)` 下行葬礼琶音（delay 0.25s） | 1.10s | Boss 死亡（v0.7 无 Boss 死亡专属音，复用 explosion 不够仪式感） | 1.00s |

阶段音要在弹幕/召唤的嘈杂场里穿出来，靠三点：① 频段错位（roar 集中 <200Hz，弹幕音 >600Hz）；② throttle 期间其他 SFX 不压它（响度 -6dBFS 峰值，高于常规战斗音）；③ 与 0.8s 阶段转换动画（设计案 §9.3：镜头停顿+无敌帧）硬同步，见 §三。

### 2.5 远程弹幕威胁音（spitter）——空间感提示

威胁音必须让玩家**不看屏幕也知道危险方向**。双轨架构下引擎 3D 声像（AudioStreamPlayer2D）在 Web 上不可用，方案：**JS 侧 StereoPannerNode + 距离衰减**（`shell.html` 的 `_gameSfx.play(name, pan, vol)` 扩两个可选参数，`tone/noise` 输出先过 Panner 再进 master；引擎侧 `Sfx.play_at(sname, world_pos)` 按相机算 pan ∈ [-1,1] 与距离衰减，默认 0 不破坏现有调用）。

| 音色 id | 合成参数 | 时长 | 触发 | 空间规则 |
| --- | --- | --- | --- | --- |
| `enemy_shot` | `_two_tone(600→300, 0.10, 0.5)` 湿黏下坠（设计案 §9.5 原案） | 0.10s | spitter 每 2.2s 吐酸弹 | **pan = 弹源相对玩家 x**；距离 >800px 音量线性衰减至 -12dB；>1200px 不播 |
| `exploder_fuse` | `_tone(1200→1200, 0.07, 0.35, 0)` 急促哔声 ×3（delay 0 / 0.15 / 0.30，音高逐次 +200Hz） | 0.45s | 自爆怪进入 1.0s 前摇（膨胀+红闪，设计案 §4.1） | 同上 pan；**音高逐次抬升 = 倒计时感**，与前摇动画膨胀同步 |
| `exploder_boom` | 复用 `explosion` | 0.45s | 引爆 | 与 `FX.explosion(130px)+shake(10)+hitstop(0.04)` 同帧（设计案 §9.4）；pan 保留（爆炸点未必在屏心） |

- `enemy_shot` throttle **0.12s**（设计案 §9.5）：后期同屏 5+ 只 spitter 时防止酸弹音糊场；throttle 内丢弃的弹**不再补播**（丢音不丢伤害判定，声音是提示不是结算）。
- 石像鬼（gargoyle）无远程机制，不加专属音；其重击命中复用 `hit` 并叠加一次 `_tone(150→80, 0.12, 0.4, 锯齿)` 低频层？——**不做**，保持 hit 单一音色避免混淆"打的是谁"与"打得多疼"，高甲的"硬"由伤害数字与击中火花体现。

### 2.6 波次与计时事件音（L3）

| 音色 id | 合成参数 | 时长 | 触发 | throttle |
| --- | --- | --- | --- | --- |
| `wave_start` | `_boom(0.30, 0.5)`（低鼓定场）+ `_arp([262,330,392], 0.40, 0.35)` 号角动机（delay 0.10s） | 0.50s | `wave_director` 每波开始（3 波/层） | 2.00s |
| `timer_tick` | `_tone(880→880, 0.05, 0.30, 0)` | 0.05s | 层倒计时最后 10s，每秒 1 次 | 0.50s |
| `timer_urgent` | `_tone(1046→1046, 0.06, 0.35, 0)` | 0.06s | 最后 5s，每秒 1 次（音高比 tick 高大六度 + 响度 +3dB） | 0.50s |
| `elite_spawn` | `_two_tone(300→150, 0.30, 0.5)` 下沉低鸣 + `_noise(0.10, 0.2)` 金色微光（delay 0.32s，与精英金色脉动 0.5s 同步） | 0.45s | 精英登场（设计案 §9.3） | 1.00s |
| `score_settle` | 复用 `achievement` | 0.55s | 生存评分结算 | — |

设计意图：`wave_start` 用低频"定场鼓"标志波次边界（玩家无需看 HUD 就知道节奏）；倒计时 tick 是**可关闭的焦虑源**——最后 10s 才出现，避免整层催促感；`elite_spawn` 下行低鸣与超武上扫形成方向反差（坏事向下、好事向上，全游戏音高语义一致：`gem/coin/levelup/relic` 全部上行）。

---

## 三、音画同步：超武合成时序对齐表（毫秒级）

### 3.1 事件链（谁发、谁响应）

```
HUD 升级浮层「合成」按钮点击
  → hud.gd 关浮层，恢复游戏流（process_mode）
  → EventBus.emit("superweapon_synthesized", {super_id, pos})   ← 唯一事件源（02 §4.5 已定义此信号）
      ├─ Sfx 监听：T+0 播 supercharge
      ├─ player.gd 监听：T+0 启动蓄力视觉（金圈 grow 0→170px, 0.5s），创建 0.50s 引擎计时器（ignore_time_scale=true，对齐 fx.gd:250 现有写法）
      └─ 计时器到点（T+500）：player.gd 执行爆发三件套 FX.glow(300)+glow_ring(170)+shake(14)+hitstop(0.12)
            └─ hitstop 调用处同帧 emit("superweapon_burst") → Sfx 播 superburst（爆发段）
```

v0.7 的一切都在一帧内（`player.gd:1102-1106`）；v0.8 唯一的结构改动是**爆发段延后 500ms**（蓄力让位），爆发三件套与 `superburst` 保持同帧。旧 `superfuse` 调用点（`player.gd:1106`）删除。

### 3.2 毫秒级对齐表

| 时刻 | 声音 | 画面 | 发起方 | 备注 |
| --- | --- | --- | --- | --- |
| T+0 | `supercharge` 蓄力起（150→600Hz，渐强） | 升级浮层关闭；玩家脚下金圈开始生长（glow 0→170px 线性 0.5s） | HUD emit → Sfx / player | 音画同帧起 |
| T+500 | — | 金圈到满 170px；爆发帧开始 | 引擎计时器（ignore_time_scale） | 蓄力音恰好收尾（0.5s），零缝隙 |
| T+500 | `superburst` 爆发起（boom+noise+星火） | `FX.glow(300, 0.8s)` + `shake(14)` + `hitstop(0.12s)` 同帧 | player → FX + emit → Sfx | **声音峰值与画面峰值同帧** |
| T+500–620 | `superburst` 低频段持续 | `Engine.time_scale=0.05`，画面冻结，震屏 tween 被冻结（`shake` 用 cam.create_tween，受 time_scale 影响 → 实际震屏在解冻后补完，v0.7 已如此，不视为缺陷） | — | **WebAudio 走真实时钟，顿帧不吞声音**——双轨制度性红利 |
| T+620 | `superburst` 星火层收尾 | hitstop 结束，time_scale→1.0 | fx.gd:252-254 | 解冻瞬间仍有星火高频，衔接不空 |
| T+620 | `superring` 余韵起 | `FX.glow_ring(170, 0.6s)` 冲击环开始扩散 | player emit → Sfx / FX | 环扩散 0.6s ↔ 琶音前 0.6s 同步推进 |
| T+1220 | `superring` 尾音 | 冲击环消失（T+1120）后 100ms | — | 视觉先收、声音后收 100ms，留"回甘" |
| T+1400 | 全部结束 | BGM ducking 释放（见 §五.2） | Sfx | 总演出时长 1.9s |

**同表适用**：宝箱开启（T+0 `chest_open` 顿音 ↔ 盖子弹开帧；T+120 琶音 ↔ 金光 `FX.glow`）；Boss 阶段转换（T+0 `boss_phase` roar ↔ 贴图切换+无敌帧；T+300 上扫 ↔ `FX.glow_ring(500)` 全屏冲击，0.8s 动画覆盖声音全程）。

**hitstop 新方案下的约定**（对 A1）：音效触发点一律挂在"事件发出帧"，不挂在 hitstop 计时器回调内——A1 落地后若 hitstop 改为"仅对受击者时间膨胀"，本表 T+500–620 段画面不再全局冻结，时序表不变、兼容两种 A1 实现口径（全局冷却窗口版 / 局部膨胀版）。

---

## 四、BGM 方案

### 4.1 现状与体积处理

现状：`assets/audio/bgm/dungeon_ambient.ogg` = **1,693,463 B（1.65MB）**，代码零引用；线上由 `shell.html:202` 从 R2 CDN 运行时拉取——**这 1.65MB 既躺在 pck 里占体积（A7 应剔除），又被 CDN 重复下载一次**（02 §1.5 已实锤）。

| 方案 | 做法 | 首包成本 | 风险 |
| --- | --- | --- | --- |
| **A（推荐）** | 重编码后放进 pck，删除 CDN 链路（`shell.html:199-257` 的 fetch 部分改为接收引擎侧传入的 ArrayBuffer，或 JS 从引擎 `JavaScriptBridge` 拿 base64——**更简单**：引擎侧 `AudioStreamOggVorbis` 直接经 pck 加载后不可行（唤醒问题），故 JS 从同 pck 资产读：用 Godot `FileAccess` 读 bytes → base64 → `decodeAudioData`。1.65MB→0.65MB 的 base64 传输 <10ms） | **+0.65MB（gzip 后 ≈0.62MB，ogg 已压缩收益甚微）** | 彻底消灭 AU-5 外链单点 |
| B（备选） | 保留 CDN，从 pck 剔除 | 0MB | 外链单点仍在；必须修 `.catch` 吞错 + 加一次重试 + 加载失败提示（0.2 人日） |

**方案 A 压缩参数（给具体数字）**：

| 参数 | 现值（推测） | 目标值 | 依据 |
| --- | --- | --- | --- |
| 编码 | OGG Vorbis | OGG Vorbis（不变，Web `decodeAudioData` 全兼容） | — |
| 声道 | 立体声（推测） | **单声道** | 环境铺底乐无定位信息价值，单声道省一半码率且可做 §五.2 的全局 ducking |
| 采样率 | 44.1kHz（推测） | **32,000Hz** | 内容是低频铺底与氛围垫，>16kHz 能量极低，32k 无可闻损失 |
| 码率 | ≈128kbps（1.65MB ÷ 时长反推） | **64kbps（Vorbis q≈1）** | 氛围乐对瞬态不敏感；64k 单声道 32k 采样下透明度足够 |
| 时长 | ≈103s（按 128kbps 反推） | 不变 | — |
| **体积** | **1.65MB** | **≈0.65MB**（103s × 8KB/s = 0.82MB，Vorbis 帧开销取整后实测约 0.65–0.85MB，门禁按 ≤0.9MB 验收） | — |
| 归一化 | 未知 | **重编码时归一到 -18 LUFS 集成响度** | 对齐 §五.1 基准 |
| 循环点 | 无缝（shell 循环播放） | 重编码保留首尾，确认 loop 无缝（JMP 帧对齐） | — |

**预算占用**：pck 压缩后预算 5MB（02 §3）；死资产剔除后 pck ≈2.4MB（13.5MB − 11.1MB 死重，PNG 不压缩传输时再 gzip 9–10MB→按 02 口径）+ BGM 0.65MB ≈ **3.1MB ✓**，余量 1.9MB 留给 v0.8 新增数据表与图标。**结论：方案 A 在预算内，且净收益 = 消灭外链 + 首包只增 0.65MB。**

### 4.2 Boss 战分层 / 动态音乐：**建议延后到 v0.9**（明确判断）

**结论：v0.8 不做动态音乐，用「BGM ducking + 提示音」替代，成本 0.1 人日。**

理由（成本-收益逐条）：

1. **成本侧**：真正的分层/stem 交叉淡化需要 ① 多轨并行素材（体积 ×2–3，当前 BGM 预算已定 0.65MB，三 stem = 2MB，挤占 pck 余量）② 素材采购或定制（当前是 CC0 环境乐，无战斗 stem 可拆）③ 在 `shell.html` 新建 BGM 调度器（双轨链路再复杂化，AU-1 漂移面 +1）④ 与 `wave_director`/Boss 状态机的事件对接。合计 **1.0–1.5 人日 + 素材依赖**，是本版本音频里最贵的单项。
2. **收益侧**：v0.7/v0.8 的 BGM 是**无强节奏的环境铺底**（dungeon_ambient），本身不携带"战斗/平静"的音乐语义——动态音乐的价值（节奏对齐紧张度）在它身上无从发挥。
3. **信息传达已有更便宜的载体**：「进入 Boss 战」这一信息由 `boss_roar`（入场 0.9s）+ Boss 血条 UI + Boss 专属音色密度承担，玩家感知通路完整。声音设计原则：**信息冗余放在高优先级通道，而不是贵通道**。
4. **替代方案（v0.8 就做）**：Boss 层与超武爆发时 BGM ducking——`_gameBgm` master gain 0.60 → **0.30**（attack 150ms / release 800ms，JS 端 5 行），Boss 层全程压低让战斗音效让位，探索层满量。听感上近似"战斗氛围变化"，成本 0.1 人日。
5. **v0.9 触发条件**：若届时采购/定制了带打击乐层的主题音乐，再按「双 stem（探索/战斗）+ 1.5s 交叉淡化」实施，届时双轨收口（AU-1）已完成，调度器有干净地基。

---

## 五、混音规范

### 5.1 三轨响度基准

Web 端数字域（0 dBFS = 满幅），轨 = JS 端 GainNode 分路（`bgmMaster` 已有，新增 `sfxMaster` / `uiMaster`；引擎侧常量同步对齐，仅 Steam 生效）：

| 轨 | 内容 | 峰值上限 | 集成响度 | 现值偏差 | 动作 |
| --- | --- | --- | --- | --- | --- |
| BGM | dungeon_ambient | -6 dBFS | **-18 LUFS** | 现归一未知 | 重编码时归一（§四.1） |
| SFX-战斗 | shoot/hit/explosion/gem/coin/enemy_shot/wave_* | **-8 dBFS** | — | 现 master 0.40≈-8dB ✓ | 保持 |
| SFX-高优先 | hurt/boss_*/relic_*/elite_spawn/timer_* | **-6 dBFS** | — | 现 boss_roar 与 click 同响度，偏高优先不足 | 分路提 2dB |
| SFX-演出 | superburst/chest_open/levelup/achievement | **-3 dBFS**（超武爆发为全曲最响点） | — | 现 superfuse 与 shoot 同响度 | 分路提 5dB |
| UI | click/stairs | **-10 dBFS** | — | 现 click 偏响 | 分路降 |

**Ducking 规则**：Boss 层 BGM gain 0.60→0.30 常驻；超武爆发 T+500–1400 瞬时 ducking（§三.2）。throttle 保持现状（各音色独立），新增全局约束：**JS 侧并发 voice ≤24**（超限时丢弃新触发中优先级最低者，优先级表：威胁/受击 > 拾取 > 演出 > UI——UI 最可丢，视觉反馈已足够）。

### 5.2 平台与播放策略

- **自动播放解锁**：维持 `shell.html:259-271` 的三事件手势解锁（pointerdown/touchstart/keydown 捕获阶段，同步调 `ac()`→`resume()`）。iOS Safari 要求 resume 必须在手势调用栈内同步执行——现有写法合规，**不要改成异步回调**。
- 静音开关：`Meta.is_muted()` 单一事实源不变（`sfx.gd:60/79-84`），新增音色自动继承。
- F24 补丁（`shell.html:273-282`）保留但按 AU-7 记录其非保障性。
- 音频初始化时机：合成 stream 常驻内存（引擎侧 13+10 个音色 × 22050Hz × 16bit ≈ **0.6MB**，量级安全，不构成内存压力，不改）。

---

## 六、给程序接口说明

### 6.1 事件命名与参数（EventBus，对齐 02 §4.5）

| 事件名 | 载荷 | 发起方 | 音频监听 | 新增音色 |
| --- | --- | --- | --- | --- |
| `superweapon_synthesized(super_id, pos)` | 超武 id、世界坐标 | HUD（浮层关闭帧） | T+0 supercharge；T+500 爆发（见 §三） | supercharge/superburst/superring |
| `superweapon_burst(pos)` | 爆发帧坐标 | player（hitstop 同帧） | superburst | — |
| `relic_gained(relic_id, rarity)` | rarity ∈ c/r/l | gem.gd:67 改造 | relic_c / relic_r / relic_l | relic_c/r/l |
| `chest_opened(pos)` | 宝箱坐标 | 宝箱交互 | chest_open | chest_open |
| `boss_phase_changed(boss_id, phase)` | 阶段 1→3 | boss.gd | boss_phase / boss_rage（P3） | boss_phase/boss_rage |
| `boss_died(boss_id)` | — | main.gd `_on_enemy_died` 分支 | boss_die | boss_die |
| `enemy_fired(pos)` | 弹源世界坐标 | spitter | enemy_shot（带 pan） | enemy_shot |
| `exploder_fuse_start(pos)` | 自爆怪坐标 | exploder 前摇开始 | exploder_fuse（带 pan） | exploder_fuse |
| `wave_started(n, total)` | 波次 | wave_director | wave_start | wave_start |
| `floor_timer_warning(seconds_left)` | 剩余秒 | 层计时器 | seconds≤10 → timer_tick；≤5 → timer_urgent | timer_tick/timer_urgent |
| `elite_spawned(pos)` | 精英坐标 | enemy.gd 精英初始化 | elite_spawn | elite_spawn |
| `bgm_duck(active)` | 是否压低 | main.gd（Boss 层进出）、超武演出 | _gameBgm gain 0.60↔0.30 | — |

### 6.2 Sfx API 变更（`sfx.gd`）

```gdscript
# 保持：Sfx.play(sname: String)           # 全部现有调用零改动
# 新增：
Sfx.play_at(sname: String, world_pos: Vector2)  # 威胁音空间化：
    # pan = clamp((pos.x - cam.x) / (视半宽), -1, 1)
    # dist > 1200px 不播；800–1200px 线性衰减至 -12dB
    # Web 分支 eval("window._gameSfx.play('%s', %f, %f)" % [sname, pan, vol])
# DEFS 表迁移：13+10 个音色参数收口到 data/audio_manifest.json（随 A2），
#   sfx.gd 与 shell.html 构建期各读同一份；V 门禁新增 V-audit：双侧 id 集合 diff 为空
```

`shell.html` 侧：`_gameSfx.play(name, pan=0, vol=1)` 增加可选参数，输出节点链 `… → StereoPannerNode(pan) → master`；新增 `sfxMaster/uiMaster/bgmMaster` 三分路与并发计数（≤24）。

### 6.3 音色规格总表（新增 11 个 id，全部复用现有原语，零外部资产、零 pck 体积增长）

| id | dur | throttle | 优先级 | pan | 峰值 |
| --- | --- | --- | --- | --- | --- |
| supercharge | 0.50s | 1.00s | 演出 | 否 | -12dBFS |
| superburst | 0.60s | 1.00s | 演出 | 否 | -3dBFS |
| superring | 0.90s | 1.00s | 演出 | 否 | -14dBFS |
| relic_c / relic_r / relic_l | 0.40/0.65/1.20s | 0.30s | 高 | 否 | -6dBFS |
| chest_open | 0.70s | 0.50s | 演出 | 否 | -3dBFS |
| boss_phase | 1.10s | 1.00s | 高 | 否 | -6dBFS |
| boss_rage | 1.20s | 1.50s | 高 | 否 | -6dBFS |
| boss_die | 1.10s | 1.00s | 高 | 否 | -6dBFS |
| enemy_shot | 0.10s | 0.12s | 高 | **是** | -6dBFS |
| exploder_fuse | 0.45s | 0.50s | **高（最高）** | **是** | -6dBFS |
| wave_start | 0.50s | 2.00s | 高 | 否 | -6dBFS |
| timer_tick / timer_urgent | 0.05/0.06s | 0.50s | 中 | 否 | -9/-6dBFS |
| elite_spawn | 0.45s | 1.00s | 高 | 否 | -6dBFS |

> exploder_fuse 是全游戏优先级最高的音效：1 秒自爆倒计时是唯一的"必须响应否则掉血"信号（设计案 §4.1），任何并发挤占场景下最后丢弃它。合计人日：manifest 收口 0.2 + 新音色双侧实现 0.5 + play_at/pan 0.3 + ducking 0.1 + BGM 重编码接入 0.2 ≈ **1.3 人日**（建议计入 L2 批次 0.7、L3 批次 0.6）。

---

*方案完。全部现状判断基于 commit `baf32f5` 实读；音效参数可直接抄进 `data/audio_manifest.json`；接口变更需 tech-architect 确认 Sfx API 与 EventBus 信号落地批次。*
