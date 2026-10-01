# 《地牢肉鸽》v0.8 技术架构基线

> 作者：柯桥良（tech-architect）
> 基准版本：仓库 `owlco001/dungeon-rogue-godot` @ commit `baf32f5`（单提交，历史已压扁），Godot 4.7.2 / GDScript / GL Compatibility
> 本文档所有结论均基于**实际读码**与**本机 Godot 4.7 无头实测**；凡未验证的推断均标注「推测」。
> 本阶段未修改仓库任何文件（无头压测在 `C:/tmp/dr-hl` 的副本中进行，原仓库仅在导入缓存 `.godot/`（已被 .gitignore 忽略）之外零改动）。

---

## 0. 结论摘要（30 秒版）

1. **引擎选型无需讨论**：Godot 4.7 已成事实，本报告只做平台选型。**主推：继续以 Web 为 v0.8 主平台**，Steam-PC 作为 v0.8.5 的第二落点（几乎零额外成本），移动端原生延后到 v0.9+（加权分 3.90 / 3.60 / 2.35，见 §2）。
2. **最致命的不是代码规模，而是"每次命中把全服时间放慢到 5%"**：`FX.hitstop`（`scripts/fx.gd:245-254`）把 `Engine.time_scale` 压到 0.05，而 `projectile.gd:119` 在**每一次非暴击命中**时都调用它。无头实测确认：战斗中 `Engine.time_scale` 最低降到 **0.050**（见 §1.2-T3）。这是 v0.8「同屏更多怪」目标下的第一杀手。
3. **首包体积有 4 倍优化空间**：线上实测 `dungeon-rogue-v07.wasm` = 37.7MB、`.pck` = 13.5MB、BGM 1.65MB，**且 R2 未开启任何压缩**（实测无 `Content-Encoding`）。合计约 **52.9MB**；叠加 `.pck` 里约 **11.1MB 从未被代码引用的死资产**（`assets/ella` 9.9MB 等），压缩 + 剔除后首包可降到 **12MB 量级**。
4. **v0.8 的内容扩张需求与当前架构正面冲突**：三选一超武合成不可达的根因是四条共同锁死链（RC-1 选池算法 `player.gd:1052` / RC-2 池序偏置 / RC-3 合成自锁 `player.gd:999` / RC-4 升级预算放大器，详见 §1.1 最终口径；本人初版对 `passives.has` 的指认已被交叉复核修正）。19 武器 × 19 超武的合成体系需要"被动可稳定获取与练满"，这要求把"属性/词条计算"从硬编码改造成**数据驱动的修饰符管线**——但选择器修正（A3a，0.3 人日）与管线（A3b，2.5 人日）已解耦，后者不再阻塞 v0.8。
5. **可以立即自动化**：本机 Godot 4.7 无头验证链路已跑通（真实入口 + autoload 驱动，见 §6），现有 `test/smoke.gd` 已失效（`try_attack()` 不存在、断言过期），需要重建验证集而不是修它。

> **【交叉验证备注 · Phase 3 口径对齐】** 本报告初版 §0-4 / §1.1 对三选一锁死的根因指认（"`player.gd:1022` 的 `passives.has` 锁死 pnews 池"）**经复核予以修正**：正确行号为 `:1029`（槽位门）与 `:1031`（去重过滤），且它们不是主因。最终采纳 01-design-v08.md 终稿 §1.1 的四条根因链 **RC-1 选池算法主锁（`player.gd:1052`）/ RC-2 pnews 先于 pups 的偏置锁 / RC-3 合成自锁（`player.gd:999`）/ RC-4 升级预算放大器（`player.gd:1005-1013` + `WEAPON_MAX_LV=8`，42~48 次升级 > 一局 32 次）**，并以 `_trace.py` 32 步镜像模拟为决定性证据（`pnews` 恒 12 项、从未为空）。据此排期调整：**A3 拆分为 A3a（选择器修正，0.3 人日，阻塞）+ A3b（StatBlock 管线，2.5 人日，非阻塞随 L2）**，阻塞路径 16.5 → 14.3 人日。详见 §1.1 最终口径、§5 排期表、§4.7 接口对齐、§7-H3。两份文档自此为程序实现的唯一口径。

---

## 1. 现网体检（技术债清单）

> 严重度：P0 = 直接阻塞 v0.8 目标；P1 = 强烈建议在 v0.8 内解决；P2 = 可延后但需记录。

### 1.1 单体脚本风险

**[P1] `player.gd` 1520 行，至少承担 7 类不相关职责**

| 职责 | 证据（行号） | 说明 |
|---|---|---|
| 移动/动画/朝向 | `player.gd:132` `_physics_process`，`_anim_walk` 等 | 纯表现 |
| 武器执行器 | `_tick_weapons`（:389）、`_wstats`（:274）、`match String(s["kind"])` | **19 种武器全走一个 match** |
| 被动/遗物数值 | `_cd_mult`（:208）、`_gold_mult`（:241）、`_recalc`（:246）、`take_damage`（:1443） | 遗物硬编码在 4 个函数里（见 §1.3） |
| 技能系统 | `_tick_skills`（:1162）、`_start_arrow_rain`（:1208）、`_cast_stomp`（:1274）、`_cast_soul_drain`（:1300）、`_cast_holy_shield`（:1359）、`_meteor_rain`（:1382） | 7 个技能的**伤害数值全部硬编码在函数体内**，`GameData.SKILLS` 表里没有 dmg 字段 |
| 环绕物/光环视觉 | `_tick_aura_visual`（:749）、`_tick_orbit`（:884） | 每帧对每个武器调一次 `_wstats` |
| 升级三选一 | `build_levelup_options`（:981-1066） | **v0.8 主题所在，见下** |
| 拾取/金币/经验 | `gain_gold` / `gain_xp` / `gain_relic` | |

**拆分优先级**（按 v0.8 改动面倒推）：
1. **最高**：`build_levelup_options` + 被动/遗物数值（因为 v0.8 主题"构筑能成型"必须动这里，动了就必须先抽出来，否则改完更乱）
2. 次高：武器执行器（`_tick_weapons` 的 match → 每武器一个执行器对象）
3. 可延后：移动/动画保持原地

**升级三选一锁死问题——最终口径（Phase 3 对齐，含对本人初版的修正）**：

> **修正声明**：本报告初版将锁死主因指认为"`player.gd:1022-1027` 的 `pnews` 池被 `if not passives.has(pid)` 锁死"。经逐行复核，**该引用行号错误、且优先级误判，现予修正并采纳创意总监终稿（01-design-v08.md §1.1）的四条根因链**。
>
> 复核后的事实（行号以 commit `baf32f5` 实读为准）：
> - `player.gd:1022` 实际是 `wnews`（新武器）的 desc 拼接行，**并无 `has` 判断**；
> - `if not passives.has(pid)` 实际位于 **`player.gd:1031`**，外层还有 `if passives.size() < GameData.PASSIVE_SLOTS:`（**:1029**）——它的作用是"未持有才入池"的去重过滤，**不是锁**；
> - **RC-1 选池算法主锁**（`player.gd:1052`）：`pools := [synth, wnews, wups, snew, sups, pnews, pups]` + 按索引轮转的取样循环（`:1056-1065`）——i=0 轮就按池序取满 3 个，`pnews/pups` 排在第 6/7 位，**被动只能竞争第 3 个槽位**；
> - **RC-2 pnews 先于 pups 的偏置锁**（同 `:1052` 池序）：新被动优先于被动升级，把 6 个槽位吃满低级被动后 `:1029` 槽位门才关闭，而把特定被动练到 Lv5 的期望代价被极大抬高；
> - **RC-3 合成自锁**（`player.gd:999`）：`if int(passives.get(need_p, 0)) < GameData.PASSIVE_MAX_LV: continue` —— `synth` 池要求"对应被动 Lv5"，而被动受 RC-1/RC-2 压制 → 循环依赖；
> - **RC-4 升级预算放大器**（`player.gd:1005-1013` + `game_data.gd:33 WEAPON_MAX_LV=8`）：6 把武器拉满需 42~48 次升级 > 一局 32 次升级（01 终稿 §3.2：Lv.33/32 次）→ `wups` 全局恒非空，持续占据前两槽。
>
> 决定性证据（采纳创意总监 `_trace.py` 32 步镜像模拟）：`pnews` 从第 1 次升级起恒为 12 项、从未为空；随机玩家第 9 次升级即可看到 `new_passive`。若 `has()` 真是锁，它一次都不会出现。
>
> **架构侧保留的一条边界提醒**（不改变上述结论）：`:1029` 的 6 槽上限是一个真实存在的硬门。RC-1/RC-2 修复后被动获取率会大幅上升，6 槽 vs 12 被动将立即成为**新的瓶颈点**。因此 A3a（选择器修正）是止血，A3b（StatBlock 词条化，被动从"槽位持有"变为"可叠加词条"）才是根治，两者最终仍需汇合——这也是把 A3b 保留在"强烈建议"而非"可延后"的原因。

**[P1] `hud.gd` 1030 行，纯代码搭 UI，承担 8 类职责**

证据：`hud.gd:97-110` `_ready` 里连续调用 11 个 `_build_*`。
- 状态栏/血条/经验条：`_build_bars`（:142）、`_build_labels`（:161）
- 装备栏 + 详情弹窗：`_build_equip_bars`（:298）、`_build_detail_panel`（:393）、`_show_detail`（:453）、`_weapon_desc`（:526，又一个 `match kind`）
- Boss 条：`_build_boss_bar`（:574）
- 虚拟摇杆宿主：`_build_joystick`（:589）
- 选人界面：`_build_select_overlay`（:759）
- 升级/死亡/胜利浮层：`_build_levelup_overlay`（:854）、`_build_death_overlay`（:924）、`_build_victory_overlay`（:965）
- 技能栏：`_build_skill_bar`（:616）
- 成就 toast：`_build_toast`（:225）

拆分优先级：**升级三选一浮层必须先拆**（v0.8 要改三选一逻辑，界面和逻辑都埋在 `show_levelup` / `_on_upgrade_btn` / `build_levelup_options` 三个文件位置）；其余可延后。

**[P2] `main.gd` 533 行**：场景编排 + 爆炸结算 + 掉落 + 存档 + 无尽模式，勉强可接受，但 `_on_enemy_died`（:186-220）已经把掉落概率（25% 金币、30% 遗物）写死在代码里，v0.8 掉落调整会被迫改它。

### 1.2 实体/对象池与 GC/实例化压力

**结论：除 `sfx.gd` 的 10 路 AudioStreamPlayer 池（`scripts/sfx.gd:32-39`）外，全工程零对象池。** 所有实体走 `instantiate()` → `add_child()` → `queue_free()` 循环。

| # | 问题 | 证据 | 影响 |
|---|---|---|---|
| T1 | **热路径全量组扫描（O(P×E)）** | `projectile.gd:84` `_physics_process` 里 `get_tree().get_nodes_in_group("enemies")`（:98）；`:208 _apply_homing` 再扫一次（:215）；`:230 _next_chain_target`（:233）；`:172 _blackhole_pull`（:173）。即**每颗子弹每物理帧至少 2 次全量组扫描 + 每次分配一个新 Array** | 同屏 150 弹 × 80 怪 × 60fps = 每秒约 2.9 万次距离判定 + 1.4 万次数组分配。GDScript 在 Web 无 JIT，成本约为桌面的 2-4 倍 |
| T2 | **敌人逐帧组扫描** | `enemy.gd:100` 每物理帧调 `_pick_target()`（:148-158），内部 `get_tree().get_nodes_in_group("taunt_summons")` | 100 怪 × 60fps = 6000 次/秒的组查询（即使场上 0 个嘲讽物也照扫） |
| T3 | **hitstop 时间膨胀（已实测）** | `fx.gd:249` `Engine.time_scale = 0.05`；调用点：`projectile.gd:119`（每次非暴击命中）、`summon.gd:202`（每次召唤物近战）、`fx.gd` 引用点若干 | **实测 `Engine.time_scale` 在战斗中降到 0.050**（§6 表 E1）。割草高频命中下 hitstop 计数永不归零，整个模拟长期以 5% 速度运行。v0.8 同屏翻倍会直接把它变成"游戏变慢"而不是"游戏卡顿" |
| T4 | **每颗子弹 1 个 CPUParticles2D(12 粒) + 1 个光环 Sprite** | `projectile.gd:59` `FX.attach_aura`、`:61-74` trail 粒子；`fx.gd:178-200` `hit_spark` 再建 1 个 8 粒 CPUParticles2D；`fx.gd:203-223` 每次伤害数字 1 个 Label + 1 个 Tween | 终局实测节点数 227 → 1273、ObjectDB 对象 3069 → 5284（§6 表 E1）。CPU 粒子是 Web 上最贵的一类节点 |
| T5 | **每个敌人独立 new 一份 SpriteFrames** | `enemy.gd:55-62` `_ready` 里 `SpriteFrames.new()` + 2 次 `load()` | 4 种敌人 × 2 帧，本可 4 份共享；现在每刷一只怪分配一次资源对象。纹理本身被 ResourceLoader 缓存，故主要是分配开销而非磁盘 IO |
| T6 | **每次特效 new 一个混合材质** | `fx.gd:297-300` `_additive_mat()` 每次 `CanvasItemMaterial.new()` | 材质不同 → Godot 2D 批处理被打断 → draw call 暴涨。这是把"特效多"变成"draw call 多"的直接原因 |
| T7 | **尸体逐帧重绘** | `corpse.gd:19-22` `_process` 每帧 `queue_redraw()`，生命周期 5 秒 | 尸潮时数百个 canvas item 每帧重绘（有 60px 内 ≤3 具的上限保护，`main.gd:279-289`，缓解但不消除） |
| T8 | **宝石无上限、跨层不清理** | `gem.gd:40` 每颗宝石每物理帧独立 `_physics_process`；`main.gd:94-119` `next_floor()` 不清理 `pickups` 组 | `Meta.has_magnet_all()`（磁石体质天赋，`meta.gd:472-474`）会把 MAGNET_RADIUS 拉满 → 全场宝石每帧都参与吸附计算。**推测**：无尽 40 层后可能出现数百颗宝石同时在场 |

**[P1] `arena.gd::_draw()` 的逐砖绘制**：`arena.gd:336-392` 每次重绘执行约 884（地面 34×26）+ 52（侧墙）+ 68（顶/底墙）+ 16 decal + 10 hazard + 4 柱子 ≈ **950+ 个 `draw_texture_rect`**。`StaticBody2D._draw` 的命令列表会被缓存（不会每帧重执行 GDScript），但**每次渲染帧都要走 950+ 次绘制命令提交**，在 GL Compatibility + Web 单线程下是纯浪费。主题切换时 `set_theme`（:85）里还有 `hash("%s:%d:%d" % ...)` 逐砖字符串哈希（:109）——一次性成本，可接受。

### 1.3 数据驱动程度：**加一把武器要改 5 处，加一个遗物要改 5 处**

| 内容类型 | 现状 | 新增 1 条需要改动的地方 |
|---|---|---|
| 武器 | `game_data.gd:35-172` `WEAPONS` 表（数值已配置化 ✓） | ① `WEAPONS` ② `WEAPON_POOL`（:174）③ `player.gd:389 _tick_weapons` 的 `match kind` + 新增 `_do_xxx` 函数 ④ `hud.gd:43-63 WEAPON_ICONS` ⑤ 若有超武则 `SUPERWEAPONS`（:205-245）。**结论：数值可调，但"新机制武器"必须写代码；"同机制新武器"仍要改 4 处** |
| 被动 | `game_data.gd:184-199` | ① `PASSIVES` ② `PASSIVE_ORDER` ③ `player.gd` 内 8 个取值函数（`_dmg_mult`/`_cd_mult`/`_crit_chance`/`_crit_mult`/`_duration_mult`/`_xp_mult`/`_area_mult`/`_recalc`）④ `hud.gd:64-77 PASSIVE_ICONS`。**每加一个被动 = 改 player.gd 的计算函数** |
| 遗物 | 仅 4 件（`game_data.gd:305-327`；README 宣称 12 件，**文档与实现不一致**，已实测 `RELICS=4`） | ① `RELICS` ② `RELIC_ORDER` ③ `player.gd:241 _gold_mult`（`"greedcup" in relics`）④ `:208 _cd_mult`（`"wardrum" in relics`）⑤ `:246 _recalc`（`magnetcore`）⑥ `:1443 take_damage`（`phoenixheart`）。**遗物效果全部 if-else 硬编码在 player.gd 四个函数里** |
| 敌人 | `game_data.gd:375-380` 4 种 | ① `ENEMIES` ② `FLOOR_COMPS`（:391-398）。较健康，但新行为（远程/自爆）需要改 `enemy.gd` |
| 天赋/永久属性 | `meta.gd:11-49` | ① `TALENTS`/`ATTRS` ② `TALENT_ORDER`/`ATTR_ORDER` ③ `meta.gd:407-479` 的 12 个 `bonus_*` 函数。**每加一个天赋要写一个 bonus 函数 + 在 player.gd 接线** |
| 技能 | `game_data.gd:262-292` 只有 cd/icon/desc | 伤害数值硬编码在 `player.gd` 六个 `_cast_*`/`_start_*` 函数（:1208/:1274/:1300/:1359/:1382） |
| 层数/主题 | `game_data.gd:383-398` | 配置化 ✓ |

**v0.8 内容目标对架构的直接要求**：必须引入**修饰符（modifier）管线**——把"攻击+8%/级""武器伤害+4%/级""greedcup 金币+30%"统一成 `{stat, op, value, source}` 列表，由单一 `StatBlock` 汇总。否则 v0.8 每加一件遗物/被动/天赋都在 player.gd 上叠 if。

### 1.4 存档健壮性

| # | 问题 | 证据 | 严重度 |
|---|---|---|---|
| S1 | **无版本号字段** | `run_save.gd` 全文 56 行、`meta.gd` 全文无 `version` 键；唯一的迁移标记是 `meta.gd:83 _migrated_v06` + `_do_migration()`（:289-303） | P1。v0.8 要改武器/被动/技能数据结构（如 cd_t、flags），旧存档继续会踩空 |
| S2 | **损坏即静默清零** | `meta.gd:87-96 _ensure()`：`cfg.load()` 返回非 OK 时直接当作"无存档"返回默认值，**不做备份、不提示** | P1。一次写盘中断 = 金币/天赋/解锁全丢 |
| S3 | **高频全量重写** | `meta.gd:160-172 add_gold/spend` 每次金币变动都 `save_data()` 全量重写 ConfigFile；`buy_talent/buy_attr/try_unlock_char/record_*` 同样 | P1（Web 端落到 IndexedDB，每次全量序列化）。局内金币每拾取一次就写盘（`main.gd` 经 `player.gain_gold` → `Meta.add_gold`） |
| S4 | **run 存档含深层结构** | `main.gd:441-459 save_run` 把 `weapons`（含 `cd_t` 浮点）、`passives`、`relics`、`skills` 深拷贝进 ConfigFile；`continue_run`（:463-520）用 `w.get("cd_t", 0.0)` 做字段级容错 | 中。容错已有，但没有"字段版本"概念，靠逐字段 `.get()` 补默认值 |
| S5 | **无校验和/防篡改** | `run_save.gd:18-24` | P2（单机可接受，记录在案） |
| S6 | **clear() 正常工作（实测）** | `run_save.gd:41-43` 用 `DirAccess.remove_absolute("user://run_save.cfg")` | 实测 `after clear(): has_save=false`（§6 表 E1），**不是 bug**，此项排除 |

### 1.5 构建管线与首包体积

**[P0] 线上产物实测（2026-10-02 实测 R2）：**

| 文件 | 大小 | 说明 |
|---|---|---|
| `dungeon-rogue-v07.html` | 15,837 B (15.8KB) | 壳层 |
| `dungeon-rogue-v07.wasm` | **39,514,754 B = 37.7MB** | 未压缩传输，占首包 71% |
| `dungeon-rogue-v07.pck` | **14,203,288 B = 13.5MB** | 未压缩传输 |
| `dungeon_ambient.ogg` | 1,693,463 B = 1.65MB | 由 shell.html 运行时从 R2 拉取 |
| **合计** | **≈ 52.9MB** | 5Mbps 带宽理论下载 ≈ 85 秒 |

关键事实（curl 实测）：请求带 `Accept-Encoding: gzip, br` 时响应**无 `Content-Encoding` 头**，`size_download` 与 `Content-Length` 完全相等 → **R2 上没有开启压缩**。压缩率与硬线的成败关系（与美术侧 03-art-assets-v08.md 对齐）：gzip 下首包估 ≈14MB；**要压到 ≤12MB 硬线需要 brotli + wasm-opt**。若 R2 brotli 不可用（§7-H5 假设），则硬线放宽到 14MB 或追加 wasm-opt 步骤，二选一需在 A7 落地时定案。**仅开启 gzip 就能砍到 ~22MB（4 倍改善），压缩这一步无论如何都要做。**

**[P0] 死资产进包**：`export_presets.cfg:9-11` `export_filter="all_resources"` 且 `exclude_filter=""`。逐目录 grep 全部 `scripts/ scenes/ web/` 后确认以下目录**零引用**：

| 目录/文件 | 体积 | 引用情况 |
|---|---|---|
| `assets/ella/` | 9.89MB | 无任何代码引用（是 `sprites/characters` 的原始源图） |
| `assets/preview/` | 0.72MB | 无引用 |
| `assets/pilot/` | 0.36MB | 无引用 |
| `assets/enemy/` | 0.44MB | **零引用**（美术侧 03 文档新增指认，本报告已复核：`enemy.gd:60` 实际使用 `assets/sprites/enemies/`） |
| `assets/art/lobby/divider_gold.png` | 0.76MB | **零引用**（美术侧指认，已复核；此修正了 01-design §9.2"divider 在用"的假设，建议直接删源文件） |
| `assets/manifest.json` | 0.10MB | 无引用 |
| `assets/STYLE_GUIDE.md` | 4KB | 无引用 |
| `assets/audio/bgm/dungeon_ambient.ogg` | **1.65MB** | **代码零引用**——shell.html 另行从 CDN 下载同一文件。即：这 1.65MB 既躺在 pck 里占体积，又被重复下载一次 |
| 合计死重 | **≈ 12.3MB**（美术侧实测口径，高于本报告初版的 11.1MB） | 注：pck 内嵌的是 Godot 导入后版本，原始体积 ≠ pck 贡献，实际剔除收益以 A7 导出后的 V6 门禁实测为准 |

**[P1] `tools/build_single_html.py` 的具体问题**：
1. **`main()` 会被执行两次**：`build_single_html.py:85` 与 `:89` 存在两个连续的 `if __name__ == "__main__":` 块，第一处直接 `main()`，第二处 `sys.exit(main())` → 每次构建都把 50MB+ 的 base64 编码做两遍。
2. **进度条会卡死在 0%**：单文件方案把 pck 以 base64 字符串内联，`_b64ToBytes`（生成在 :53-59 的 JS）用逐字符 `charCodeAt` 循环解码 13.5MB+ 数据，主线程阻塞数秒，期间 `onProgress` 无法推进。当前线上是"多文件 + 独立 pck/wasm"形态（实测 v07.html 仅 15.8KB），说明**线上实际没有走单文件管线** —— 两条发布路径并存且不一致，属于流程债。
3. **标题默认值过期**：`:44` `title = sys.argv[2] ... else "地牢肉鸽 v0.1"`，忘传参数就发出去一版 v0.1 标题。
4. `tools/numcheck.py:6` 硬编码 `/home/hatch/workspace/...`（原作者的 Linux 绝对路径），在本机不可运行。
5. 无体积门禁、无导出后校验、无 CI。

**[P1] BGM 外链依赖**：`web/shell.html:202` `BGM_URL = 'https://pub-...r2.dev/dungeon_ambient.ogg'`。离线不可用（PWA 关闭，`export_presets.cfg:33` `progressive_web_app/enabled=false`），且 `.catch(function(){})`（:240）吞错，CDN 失效时静默无 BGM。

### 1.6 平台绑定

| # | 事实 | 证据 | 评估 |
|---|---|---|---|
| B1 | 虚拟摇杆**无条件**注入主玩法场景（不分平台） | `hud.gd:589-604 _build_joystick` 创建左半屏 `MOUSE_FILTER_STOP` 触区；`main.gd:90` 每帧 `player.external_move = hud.get_move_vector()` —— **核心移动输入依赖 HUD** | 中。桌面上表现为鼠标左键拖动也能移动（`joystick.gd:21-31` 同时响应鼠标），功能正常但语义混杂；移动端则缺少按键/手柄映射 |
| B2 | 竖屏分支写死在 HUD 选人界面 | `hud.gd:770-791` `narrow = vp_size.y > vp_size.x` | 低，但这是唯一一处响应式布局，v0.8 加选人内容时要记得三处同步（横排/竖排/卡片尺寸） |
| B3 | Web 特有分支散布在核心脚本 | `sfx.gd:69-71`（`OS.has_feature("web")` → `JavaScriptBridge.eval`）、`sfx.gd:81-83`、`lobby.gd:35-38`（`?autotest=1` 诊断入口直接发到线上）、`web/shell.html:121-282`（WebAudio 音效/BGM/手势解锁） | 中。方向正确（特性开关），但没有收口到平台层。`lobby.gd:40-46 _autotest()` 是 QA 脚手架，随包发布 |
| B4 | 分辨率 960×640 + `stretch/aspect="expand"` | `project.godot:24-27` | 与摇杆/竖屏分支耦合，改分辨率需回归竖屏布局 |
| B5 | Web 线程关闭 | `export_presets.cfg:24` `variant/thread_support=false` | 单线程约束，见 §3 |

### 1.7 其他

- **死代码**：`scripts/slash.gd`（267 字节）全工程无引用（grep 仅自身）。`lobby.gd:40-46` 的 autotest 分支随包发布。
- **README 与实现漂移**：README 称"12 件遗物分三档"，实测 `GameData.RELICS` 仅 4 件；README 称敌人"喷吐怪"，实际是 `skeleton`（骷髅兵）。
- **`main.gd:320` 在爆炸时 `load()` 贴图**：`_explosion_fx` 里 `load("res://assets/sprites/fx/%s.png" % tex_id)` —— ResourceLoader 有缓存，首次命中磁盘，后续走缓存；建议改 `preload` 常量表（低优先级）。
- **`player.gd:1257 _densest_cluster` 是 O(n²)**（内层循环里再次组查询），仅在箭雨施放时调用（每 12-18 秒一次），造成周期性尖峰。**推测**：这正是"放技能瞬间掉一帧"的来源。

---

## 2. 平台选型建议（必须给结论）

### 2.1 三档对比

| 维度 | 权重 | Web（现状） | Steam-PC | 移动端原生 (iOS/Android) |
|---|---|---|---|---|
| 分发与获客 | 25% | 5（已有 R2 链接，零审核，一条 URL 即可分享） | 3（需 Steam 页面/愿望单/审核周期） | 3（应用商店，但独立游戏曝光一般） |
| 工期与迭代速度 | 25% | 5（现有管线已跑通，v0.8 只需修不换） | 3（新增导出预设 + Steam SDK + 成就/云存档适配） | 1（触控/生命周期/隐私合规/包体优化全面重做） |
| 性能与体验上限 | 15% | 2（单线程、无 JIT、53MB 首包、iOS 内存墙） | 5（无上述任何限制） | 3（受中低端机约束，但比 Web 好） |
| 商业化 | 15% | 2（无内建支付；广告/赞助/ itch.io 打赏） | 5（买断制，用户付费意愿最高） | 4（内购/广告变现成熟，但受买量成本约束） |
| 合规与审核成本 | 10% | 5（几乎为零；若接广告需隐私声明） | 2（Steam 成就/云存档/退款政策/分级问卷） | 1（隐私政策、儿童保护、版号/分级、每平台单独认证） |
| 长期可维护性 | 10% | 3（浏览器兼容矩阵 + 音频 hack 常年维护） | 4（最稳定的目标平台） | 2（双端碎片化最严重） |
| **加权总分** | | **3.90** | **3.60** | **2.35** |

> 打分为 1-5。权重反映"单人 + AI 协作小团队、已有成熟 Web 原型、目标是尽快验证 v0.8 构筑主题"这一前提。

### 2.2 结论

**主推：Web 为主平台，v0.8 只交付 Web 版本；Steam-PC 作为 v0.8.5 / v0.9 的第二落点（同一工程加桌面导出预设，预估 3~5 人日含 Steam 成就与云存档）；移动端原生延后到 v0.9 之后，且届时优先只做 Android。**

理由（三句话）：
1. 分发即优势：这个品类（割草 roguelike）的核心验证指标是"构筑能不能成型、玩家愿不愿意再开一局"，Web 的零门槛分享能让 v0.8 在几天内拿到真实反馈，这是 Steam 愿望单流程给不了的。
2. 工程上 Web 已经是**已验证的交付形态**（线上 v0.7 在跑），v0.8 的钱应该花在 §1.2/§1.3 的架构改造上，而不是花在换平台。
3. Steam-PC 的边际成本极低（同一 Godot 工程 + `gl_compatibility` 渲染器在桌面性能过剩），**但前提是 §3 的性能预算按"Web 低端机"来定** —— 按 Web 标准优化过的游戏在 PC 上只会更顺，反过来不成立。这就是"先 Web 后 Steam"在工程上的正确顺序。

### 2.3 主推方案的代价（不回避）

| 代价 | 量化 | 缓解措施（§4/§5 落实） |
|---|---|---|
| 首包 52.9MB、无压缩 | 移动网络下 ≈ 85s 可交互 | 压缩 + 剔除 12.3MB 死资产 + lobby_bg 转 WebP → gzip 保底 ≈14MB、brotli+wasm-opt 达 ≤12MB（约 4~8 倍改善，分档见 §1.5） |
| 单线程（`export_presets.cfg:24`） | 无法后台加载/解码，加载期 UI 冻结风险 | 保持 pck 多文件形态 + 压缩；避免单文件 base64 方案 |
| GDScript 无 JIT | 热路径成本 2-4× | §1.2 T1/T2 的实体注册表 + 空间网格是**必做项**，不是优化项 |
| 引擎音频在桌面浏览器唤醒不可靠 | 已用 WebAudio 旁路（`sfx.gd:69-71` + `shell.html:121-196`） | 收口到 platform 层；BGM 改为按需从 pck 内加载（同时删掉 CDN 依赖与 pck 里的重复文件） |
| iOS Safari 内存墙（约 400MB） | 内存超限直接被杀 | §3 内存预算 + 特效池化 |
| 无离线/PWA | 刷新即重新下载 | v0.8.5 做 ServiceWorker（`export_presets.cfg:33` 现为关闭，一项配置 + 一个 offline 页） |

---

## 3. 性能预算（按主推平台：Web）

> 目标机型定义：
> - **基准机（必须 60fps）**：桌面 Chrome/Edge，4 核，集成显卡
> - **底线机（必须 ≥30fps）**：iPhone 8 / 骁龙 660 级 Android + Chrome
> - 预算按 **v0.8 目标场景**定义：终局构筑（6 武器含 1 超武 + 2 技能）× 同屏敌人上限

| 指标 | 预算 | 测量方式 | 现状 |
|---|---|---|---|
| 目标帧率 | 60fps；**底线 30fps**（低于 30 连续 2 秒判不合格） | 浏览器 DevTools Performance + `Performance.TIME_FPS` | 未测（Web 端）；桌面无头物理耗时可折算，见下 |
| 单帧总预算 | 16.7ms（60fps）/ 33.3ms（底线机 30fps） | — | — |
| └ 逻辑（全部 `_physics_process`） | **≤ 4.0ms**（桌面无头实测基准；Web 端按 2-4× 放大后 ≤ 16ms，故桌面必须 ≤4ms） | `Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)`，无头压测取 p95 | 实测 200 怪 = **4.00ms**、100 怪 = 1.87ms（§6 表 E1）→ **当前已顶到预算线上，v0.8 同屏翻倍即超标** |
| └ 空闲/脚本（全部 `_process`） | ≤ 1.5ms | `Performance.TIME_PROCESS` | 未测 |
| └ 绘制提交 | ≤ 6.0ms | `Performance.TIME_DRAW`（Web 无头为 0，需真机测） | 未测 |
| Draw Call | **≤ 250**（`Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME`） | 引擎内每 60 帧采样一次 | **推测超标**：仅 `arena.gd::_draw()` 就有 950+ 绘制命令（§1.2），叠加 `fx.gd:297` 每特效新材质打断批处理 |
| 同屏敌人 | **常规 ≤ 60，硬上限 80**；Boss 层 ≤ 40 + Boss | 无头压测脚本（§6 V5） | 60 层封顶逻辑已在 `game_data.gd:437-441 floor_comp` + `enemy_hp_mult`（:447）实现 ✓ |
| 活跃节点数 | **≤ 900**（实测 200 怪 = 876） | `get_tree().get_node_count()`（无头） | 终局 9 武器实测 **1273**（超预算 41%） |
| ObjectDB 对象数 | **≤ 3500** | `Performance.OBJECT_COUNT` | 终局实测 **5284**（超预算 51%） |
| 单场景内存（JS+wasm heap） | **≤ 350MB**（iOS Safari 约 400MB 被杀线以下） | 浏览器 `performance.memory` / DevTools Memory | 未测 |
| 常驻纹理 | **≤ 45MB VRAM**（960×640@2x + 图集化） | `Performance.RENDER_VIDEO_MEM_USED` | 未测 |
| 首屏可交互时间（TTI） | **≤ 12s @ 5Mbps**（对应压缩后首包 ≤ 12MB；gzip-only 场景放宽为 ≤ 14MB / ≈14s，见 §1.5 分档） | curl 实测传输体积 + 浏览器 `onProgress` | 现状 **52.9MB 无压缩**（§1.5），5Mbps ≈ 85s |
| └ wasm（压缩后） | ≤ 8MB（gzip-only 按 ≈11MB 评估，达标手段 brotli + wasm-opt） | curl -H "Accept-Encoding: gzip" | 现状 37.7MB 未压缩 |
| └ pck（压缩后） | ≤ 5MB（剔除死资产 + lobby_bg 转 WebP 后，留包资产 ≈3.1MB） | 同上 | 现状 13.5MB 未压缩，其中 ~12.3MB 死资产（原始体积口径） |
| 存档单次落盘 | ≤ 30ms | 无头计时 `save_data()` 前后 | 未测；`meta.gd:160-172` 每次金币变动全量重写，**推测高频拾取时超预算** |
| 每帧 `Sfx.play` 调用 | ≤ 30（现有 throttle 机制已达标） | 代码审查 | 达标（`sfx.gd:59-76`） |

### Godot 4.7 Web 环境的现实约束（写预算时必须考虑）

1. **单线程**：`export_presets.cfg:24` `variant/thread_support=false` → 加载、解码、逻辑全在主线程，"加载不卡 UI"只能靠切小包。
2. **渲染器为 GL Compatibility**（`project.godot:63-64`）：无 compute，2D 批处理依赖"同材质同纹理"，`fx.gd:297` 每次新建 `CanvasItemMaterial` 会直接打断批处理。
3. **GDScript 无 JIT**：Web 上脚本解释执行，成本约为桌面原生 2-4 倍。因此本表的"桌面 4ms 逻辑预算"对应 Web 端 8-16ms，这正是把逻辑预算定得这么紧的原因。
4. **音频必须走 WebAudio 旁路**（`sfx.gd:69-71` 注释明确说明），这是已验证的既定架构，不要试图改回引擎音频。
5. **iOS Safari 内存上限**：约 400MB 后进程被杀，预算必须留 25% 余量。
6. **`Engine.time_scale` 会污染所有计时器**：hitstop（`fx.gd:245-254`）用 `Engine.time_scale=0.05` 实现，影响的不只是动画——所有 `create_timer`（非 ignore_time_scale）与掉落/CD 计时都会被拖慢，这是把"顿帧爽感"变成"全场减速"的机制性原因。

---

## 4. 工程架构建议

### 4.1 目标分层

```
┌─────────────────────────────────────────────────────┐
│ 平台/壳层  platform/   Web 壳、桌面壳、移动壳、PWA     │  ← 唯一允许 OS.has_feature / JavaScriptBridge
├─────────────────────────────────────────────────────┤
│ 表现层     ui/ fx/     HUD、浮层、大厅、特效、摇杆     │  ← 只读状态，只发输入事件
├─────────────────────────────────────────────────────┤
│ 玩法层     gameplay/   Player/Enemy/Summon/Projectile  │  ← 只调 StatBlock/ContentDB，不读 Meta
│                        Arena/楼层推进/掉落            │
├─────────────────────────────────────────────────────┤
│ 系统层     systems/    StatBlock（修饰符管线）        │  ← 纯函数、可单测
│                        CombatResolver  LootTable     │
│                        EntityRegistry（实体注册表）   │
├─────────────────────────────────────────────────────┤
│ 数据层     data/       *.tres / *.json（策划可改）    │  ← 零逻辑，只定义
│            ContentDB（启动加载 + 完整性校验）          │
├─────────────────────────────────────────────────────┤
│ 服务层     autoload/   Sfx  EventBus  SaveService     │
│                        Meta（局外）  Achievements     │
└─────────────────────────────────────────────────────┘
依赖方向：自上而下单向。禁止：表现层直接改玩法状态；玩法层 `OS.has_feature()`；任何层 `get_node("/root/...")`。
```

### 4.2 目录规范（目标态，v0.8 渐进迁移，不搞一次性搬家）

```
res://
├── autoload/              # 仅单例（Sfx / EventBus / SaveService / ContentDB / Meta / Achievements）
├── data/                  # ★ 新增：所有策划数值
│   ├── weapons/           #   <id>.tres：kind/cd/dmg/sig/icon（武器数值 + 图标路径收口于此）
│   ├── superweapons/      #   <id>.tres：weapon/passive/mods
│   ├── passives/          #   <id>.tres：stat/op/per/max
│   ├── relics/            #   <id>.tres：mods[]（磁铁核心 = [{stat:"magnet",op:"mult",value:2.0}]）
│   ├── enemies/           #   <id>.tres：hp/speed/dmg/xp/scale/behavior
│   ├── skills/            #   <id>.tres：cd[]/dmg[]/icon（★ 把硬编码数值收进表）
│   ├── talents/           #   <id>.tres：school/max/cost/mods[]
│   └── floors.tres        #   主题/编队/成长曲线
├── gameplay/
│   ├── player/            #   player.tscn + movement.gd + weapon_user.gd + skill_user.gd + pickup.gd
│   ├── entities/          #   enemy/summon/projectile/gem/corpse
│   ├── arena/             #   arena.gd（含烘焙逻辑）
│   └── run/               #   main.gd + floor_flow.gd + loot.gd
├── systems/
│   ├── stat_block.gd      #   修饰符汇总：{stat,op,value,source} → 最终数值
│   ├── entity_registry.gd #   enemies/projectiles/summons 定长数组 + 空间网格查询
│   ├── combat.gd          #   命中判定/伤害结算（从 main.gd/projectile.gd 收口）
│   └── loot.gd            #   掉落概率表（从 main.gd:214-217 的 randf() 收口）
├── ui/
│   ├── hud/               #   hud.tscn + status_bar.gd + equip_bar.gd + skill_bar.gd
│   ├── overlays/          #   select.gd / levelup.gd / death.gd / victory.gd（★ v0.8 必拆）
│   └── lobby/
├── platform/
│   ├── web/               #   web_audio_sfx.gd、shell.html、joystick 启停开关
│   ├── desktop/           #   （v0.8.5）steam.gd、成就桥
│   └── input_mapper.gd    #   键鼠/触摸统一抽象（摇杆从这里开关）
├── fx/                    #   fx.gd（池化后）
├── tools/                 #   构建与校验脚本（不进包，exclude_filter 排除）
├── test/                  #   自动化验证（§6）
└── scenes/
```

迁移原则：**v0.8 只新建 `data/`、`systems/`、`ui/overlays/`、`platform/` 四个目录**，旧的 `scripts/*.gd` 原地瘦身后逐步搬；一次全量重构是 v0.8 最大的进度风险。

### 4.3 数据配置化契约（"加内容不改代码"的验收标准）

| 新增内容 | v0.8 后允许改动的文件 | 仍需写代码的情况 |
|---|---|---|
| 同机制新武器（如第 20 把枪） | 仅 `data/weapons/<id>.tres` | 无 |
| 新机制武器（如激光） | `data/weapons/*.tres` + 新建一个 `WeaponExecutor` 子类并注册 | ——（允许） |
| 新被动 | 仅 `data/passives/<id>.tres`（`stat/op/per`） | 新增 stat 类型时需扩 `StatBlock` 枚举 |
| 新遗物（到 12 件） | 仅 `data/relics/<id>.tres`（mods 数组） | 质变型遗物（如复活）需挂到明确的 hook 名 |
| 新敌人 | `data/enemies/<id>.tres` + `data/floors.tres` 编队 | 新 AI 行为需写 behavior 类 |
| 新天赋 | `data/talents/<id>.tres`（mods） | 无 |
| 新技能 | `data/skills/<id>.tres`（cd/dmg 数组） | 新技能机制需写 executor |

**核心机制：StatBlock 修饰符管线**（替代 player.gd 里 8 个取值函数 + 4 处遗物 if-else）：

```gdscript
# systems/stat_block.gd（示意）
# 所有加成统一为 {stat:String, op:"add"|"mult", value:float, source:String}
# 汇总规则：先 add 后 mult；同 source 去重；最终值缓存，脏标记失效
# 迁移映射（旧 → 新）：
#   player.gd:_dmg_mult()      → StatBlock.get("attack")
#   player.gd:_cd_mult()       → StatBlock.get("cooldown")
#   player.gd:_recalc() 的 magnetcore → relic mods
#   meta.gd:bonus_dmg_mult()    → 天赋 mods 注入同一 StatBlock
#   game_data.PASSIVES.per      → 每级生成一条 modifier
```

**这个改造同时解决**：§1.3 的"加内容改 5 处"、`player.gd:1029` 的 6 槽被动上限问题（被动从"槽位持有"变为"可叠加词条"，选择器修正 A3a 落地后该门会成为新瓶颈，词条化是根治）、以及 `meta.gd:407-479` 的 12 个 bonus 函数。

### 4.4 实体查询与对象池规范

**EntityRegistry（替代 `get_nodes_in_group` 热路径）**：
- 三个定长数组 + 空闲栈：`enemies`（容量 96）、`projectiles`（容量 256）、`summons`（容量 32）、`pickups`（容量 256）
- 空间网格：格子 128px，arena 1600×1200 → 13×10 格；提供 `query_circle(pos, radius)` 返回候选（每格平均实体数 ≈ 2）
- 命中/索敌改走注册表；`get_tree().get_nodes_in_group` 仅允许在**每秒 ≤1 次**的非热路径（如楼层结算）使用
- 验收：`projectile.gd:98/:215/:233/:173` 四处组扫描全部替换

**对象池启用范围与容量**：

| 实体 | 池容量 | 理由 |
|---|---|---|
| Projectile | 256 | 终局实测峰值 ~7 存活，但瞬时生成率高 |
| Enemy | 96 | 同屏上限 80 + 余量 |
| Summon | 32 | 上限明确 |
| Gem/金币 | 256 | 磁石天赋下全屏吸附 |
| DamageNumber（Label） | 64 | 用 Label 池替代每条新建（`fx.gd:203`） |
| 光晕 Sprite | 64 | `fx.gd:68 glow` 池化 + **共享一份 ADD 材质**（`fx.gd:297` 必改） |

**FX 全局节流**（新增）：同帧 `hit_spark`/`damage_number`/`glow` 各限 6 次，超出降级为"仅数字"。

### 4.5 事件总线与信号规范

```gdscript
# autoload/event_bus.gd —— 只声明信号，不写逻辑
signal enemy_died(enemy: Node2D)             # 替代 main.gd 逐个 connect
signal floor_changed(floor_num: int, def: Dictionary)
signal run_ended(victory: bool, stats: Dictionary)
signal relic_gained(relic_id: String)
signal superweapon_synthesized(super_id: String)
signal save_requested()
signal toast_requested(text: String)         # 替代 Achievements.queue_toast + hud 轮询 drain_pending()
```

规范：
1. **命名**：过去式 `xxx_happened`/`xxx_died`/`xxx_changed`；信号只带数据参数，不带 Node 引用以外的状态。
2. **方向**：玩法层 emit → 表现层 listen。表现层禁止 emit 玩法信号。
3. **替换现有的轮询**：`hud.gd:695-712 _process` 每帧刷 4 个 Label 的写法，改为事件驱动 + CD 秒级节流；`hud.gd:697` 每帧 `Achievements.drain_pending()` 改为 `toast_requested` 信号。
4. **删除**：`main.gd:90` 每帧把 `hud.get_move_vector()` 塞进 player 的反向依赖（改为 `platform/input_mapper.gd` 直接喂 player）。

### 4.6 存档版本迁移方案

```gdscript
# autoload/save_service.gd
const SAVE_VERSION := 3          # v0.8 起步版本号
# 结构：{ "version": int, "meta": {...}, "run": {...}, "checksum": int }
# 写入：先写 <path>.tmp → 校验 → 原子替换 <path>，同时保留上一版为 <path>.bak
# 读取：version 缺失 → 视为 v1，逐级跑 _migrate_v1_to_v2() / _migrate_v2_to_v3()
# 校验失败（load 报错或 checksum 不符）→ 尝试 .bak → 仍失败则提示玩家"存档损坏已重置"，并 dump 一份 <path>.corrupt 供上报
# 写盘节流：Meta 的金币/击杀类高频数据改为脏标记，0.5s 合并写一次；关键节点（升级/进层/合成）立即写
```

迁移映射（现有数据）：
- `meta.gd` 的 ConfigFile 各 section → `meta` 子字典，字段名不变（读取兼容旧文件）
- `run_save.gd` 的 run section → `run` 子字典 + 新增 `version`
- `meta.gd:119-124 _do_migration()` 保留为 `_migrate_v1_to_v2()` 的一段
- **v0.8 必须新增的迁移点**：`player.gd` 武器/技能的 `cd_t`、`flags` 结构若变化，在 `_migrate_v2_to_v3()` 里补默认值（延续 `main.gd:495-506` 现有的字段级容错思路，但收口到一处）

### 4.7 与创意总监方案（01-design-v08.md）的接口对齐

创意总监的核心改动面是 `player.gd build_levelup_options`、`game_data.gd` 三张常量表、`main.gd` 两处掉落逻辑。架构侧的对齐方式：
1. **`game_data.gd` 三张表迁到 `data/` 目录**是设计改动的前置条件（否则每次调数值都过代码评审），建议作为 v0.8 第一批任务（§5 阻塞项 #1）。
2. **三选一修复与管线的解耦（A3a/A3b）**：RC-1~RC-4 的修复落在 `player.gd:1052-1065` 的池结构/权重与保底逻辑（A3a，0.3 人日，阻塞），**不依赖 StatBlock**；StatBlock（A3b，2.5 人日）只接管"数值如何算"，接管后选择器逻辑不变。两者接口清晰：A3a 输出"选了什么 id/类型"，A3b 定义"该 id 提供哪些 modifier"。唯一交汇点是 12 件遗物——5 件纯属性走 StatBlock、7 件需要代码钩子（与 01 终稿遗物效果表一致），故遗物落地节奏由设计里程碑 L2 驱动，StatBlock 随 L2 同批交付。另请设计侧注意：A3a 落地后 `player.gd:1029` 的 6 槽上限将成为被动获取的新瓶颈，v0.8 的被动获取规则（放宽槽位 / 允许重复获取）需在设计侧定案。
3. **`main.gd` 两处掉落逻辑** → 迁到 `systems/loot.gd` 的掉落表（`data/loot.tres`），让"精英必掉 / Boss 必掉 / 概率"变成配置。改动面小（`main.gd:223-227 _drop_relic`、`:213-217`），建议与数据配置化同批做。

### 4.8 自动化构建与验证脚本的建设顺序

| 序 | 脚本 | 内容 | 人日 | 依赖 |
|---|---|---|---|---|
| 1 | `tools/check_parse.gd` | 全项目 .gd 解析 + autoload 实例化检查（§6 V1） | 0.5 | 无 |
| 2 | `test/auto_v08.gd` + `tools/run_headless.bat` | 真实入口无头驱动（§6 V2-V5），复用本报告已验证的 autoload 驱动模式 | 1.0 | 1 |
| 3 | `tools/check_content.gd` | 数据表完整性：武器 kind 有执行器、超武引用存在、图标路径存在、README 数量一致 | 0.5 | 数据配置化完成 |
| 4 | `tools/export_web.py`（重写 build_single_html.py） | 导出 → 剔除死资产 → 压缩 → 体积门禁 → 产出 manifest | 1.0 | 3 |
| 5 | `Makefile` / `build_all.bat` | 一键：check_parse → auto_v08 → check_content → export_web | 0.5 | 1-4 |

---

## 5. 实施优先级排序（可直接排期）

> 人日按"1 人全职工时"估。风险：低 = 常规改动；中 = 涉及存档/数值回归；高 = 可能引入新 bug 需要大量验证。

### A. 阻塞 v0.8（不做完不能发版）

| # | 事项 | 依据 | 人日 | 风险 |
|---|---|---|---|---|
| A1 | **hitstop 重构**：`fx.gd:245-254` 改为"命中瞬间仅对本粒子/受击者做时间膨胀"或"全局 hitstop 加冷却窗口（如 0.15s 内不重复触发）" | §1.2 T3，实测 time_scale=0.05 | **0.5** | 低 |
| A2 | **数据配置化第一批**：`game_data.gd` → `data/`（weapons/passives/relics/skills/enemies/floors/loot）+ ContentDB + 完整性校验 | §1.3、§4.7；创意总监改动面前置 | **3.0** | 中 |
| A3 | **A3a 三选一选择器修正**：覆盖 RC-1（`player.gd:1052` 池序/轮转改加权抽取）、RC-2（pnews/pups 权重偏置）、RC-3（合成置顶引导）、RC-4（保底机制）。**已从原 A3 拆分**：选择器修正不依赖 StatBlock，从关键路径摘出 2.2 人日（Phase 3 对齐结论，与 01 终稿 §3.1 修复方案对齐） | §1.1 最终口径、§4.7；01 终稿根因链 RC-1~4 | **0.3** | 中 |
| A4 | **EntityRegistry + 空间网格**，替换 `projectile.gd:98/:215/:233/:173`、`enemy.gd:100`、`player.gd` 内 19 处组查询中的热路径 | §1.2 T1/T2 | **2.5** | 中 |
| A5 | **Arena 烘焙**：`arena.gd:336-392` 逐砖绘制改为启动时一次性烘焙成单张 ImageTexture（或 TileMap）；`fx.gd:297` 改为共享单例 ADD 材质 | §1.2、§3 Draw Call 预算 | **1.5** | 低 |
| A6 | **自动化验证集 V1-V5**（§6）落地并入一键脚本 | §4.8 | **2.0** | 低 |
| A7 | **首包瘦身 + 压缩**：`export_presets.cfg` 加 `exclude_filter`（ella/preview/pilot/enemy/manifest/STYLE_GUIDE/tools/test，串见 03-art-assets-v08.md §4.2）；删除或按需加载 `assets/audio/bgm/dungeon_ambient.ogg`（与 shell.html 的 CDN 拉取二选一）；删除 `assets/art/lobby/divider_gold.png` 源文件（零引用）；`lobby_bg.png`（1.13MB，832×1248）转 WebP lossy q80（预计 150–250KB，`lobby.gd:82` 改一行后缀，Godot 4.7 原生支持）；R2 侧开启压缩——**gzip 保底（首包 ≈14MB），≤12MB 硬线需 brotli + wasm-opt，不可用则放宽硬线至 14MB（§1.5、§7-H5）**；体积门禁进 A6 的 export 脚本。留包资产合计 ≈3.1MB（美术侧实测口径），pck ≤5MB 预算稳过 | §1.5，实测 52.9MB；美术侧 03 文档 §2.3/§4.2 | **1.5** | 低 |
| A8 | **存档版本化 + 损坏兜底 + 写盘节流**（§4.6） | §1.4 S1/S2/S3 | **1.5** | 中 |
| A9 | **FX 池化 + 全局节流**（伤害数字 Label 池、光晕 Sprite 池、每帧上限） | §1.2 T4/T6；终局节点 1273 / 对象 5284 | **1.5** | 中 |
| | **小计** | | **≈ 14.3 人日** | |

### B. 强烈建议（v0.8 内做，可接受部分顺延到 v0.8.5）

| # | 事项 | 依据 | 人日 | 风险 |
|---|---|---|---|---|
| B0 | **A3b StatBlock 修饰符管线**（自原 A3 拆出，**非阻塞**，随设计里程碑 L2 同批）：收口 player.gd 8 个取值函数 + 4 处遗物 if-else + meta.gd 12 个 bonus 函数；被动词条化（根治 `player.gd:1029` 的 6 槽瓶颈）。12 遗物中 5 件纯属性直接走 StatBlock、7 件需代码钩子（与 01 终稿遗物效果表一致），故交付节奏由 L2 驱动 | §1.3、§4.3、§4.7；01 终稿遗物效果表 | **2.5** | **高**（数值回归量大，必须配 A6 验证集） |
| B1 | `player.gd` 拆分：`weapon_user.gd`（19 武器执行器）+ `skill_user.gd` + 瘦身后的 player | §1.1 | 2.5 | 中 |
| B2 | `ui/overlays/` 拆分（升级三选一浮层优先，选人/死亡/胜利随后） | §1.1；v0.8 要改三选一 | 2.0 | 低 |
| B3 | `platform/input_mapper.gd`：摇杆启停按平台开关；移除 `main.gd:90` 的反向依赖 | §1.6 B1 | 1.5 | 低 |
| B4 | 敌人 SpriteFrames 共享（4 份预生成） | §1.2 T5 | 0.5 | 低 |
| B5 | `_densest_cluster` O(n²) 修复（用 EntityRegistry 网格） | §1.2 | 0.5 | 低 |
| B6 | 宝石/尸体上限与跨层清理 | §1.2 T7/T8 | 0.5 | 低 |
| B7 | PWA / ServiceWorker（离线缓存） | §2.3 | 1.0 | 中 |
| B8 | 补齐 12 遗物 + README 对齐（内容项，与策划共同） | §1.3 / §1.7 | 1.0（架构侧 0.2） | 低 |
| | **小计** | | **≈ 11.5 人日** | |

### 汇总

- **阻塞（A 档）**：14.3 人日（A3a 0.3 已从原 A3 的 2.5 中拆出，2.2 人日移入 B0）
- **强烈建议（B 档，含非阻塞的 B0）**：11.5 人日
- **v0.8 总计 ≈ 25.8 人日**。若排期紧张，B3/B7 可顺延；**最低闭环为 A 全部（14.3）+ B1/B2（4.5）≈ 19 人日**。
- **关键路径缩短说明**：原 A3（2.5 人日，阻塞）拆分后，阻塞路径从 16.5 → 14.3 人日；StatBlock 不再是 v0.8 发版的先决条件，但 A3a 修复选择器后 6 槽上限将成为被动获取的新瓶颈，因此 B0 不宜晚于 L2 里程碑。

### C. 可以延后（v0.9+，记录在案）

| # | 事项 | 依据 | 人日 | 风险 |
|---|---|---|---|---|
| C1 | Steam-PC 导出预设 + 成就/云存档 + 页面素材合规 | §2.2 | 3~5 | 中 |
| C2 | 移动端原生（Android 优先） | §2.2 | 10~15 | 高 |
| C3 | 删除 `slash.gd` 死代码、`lobby.gd:40-46` autotest 分支 | §1.7 | 0.25 | 低 |
| C4 | `tools/numcheck.py:6` 路径参数化、`build_single_html.py` 双 main 修复 | §1.5 | 0.5 | 低 |
| C5 | `main.gd:320` 爆炸贴图 preload 化 | §1.7 | 0.25 | 低 |
| C6 | 存档校验和 + 反作弊 | §1.4 S5 | 1.0 | 低 |
| | **小计** | | **≈ 15~22 人日（延后）** | |

**v0.8 总计：A(16.5) + B(9.0) ≈ 25.5 人日**。若排期紧张，B3/B7 可顺延，最低闭环为 **A 全部 + B1/B2 ≈ 21 人日**。

---

## 6. 验证手段说明（本机 Godot 4.7 无头能力 + 实测结果）

### 6.1 本阶段实测记录（所有数字均来自真实运行）

**测试环境**：`C:/Users/owlco/Desktop/Godot_v4.7-stable_win64.exe`（Godot 4.7.stable），`--headless`，工程副本 `C:/tmp/dr-hl`（原仓库只读）。驱动方式：**真实场景入口（`res://scenes/lobby.tscn`）+ 临时 autoload 驱动脚本**（设置 `Meta.selected_char="aila"` → `change_scene_to_file("res://scenes/main.tscn")` → 采样 `Performance` 监控）。

**表 E1：无头压测结果（桌面 CPU，无渲染）**

| 阶段 | 同屏敌人 | 节点数 | ObjectDB 对象 | 物理耗时/帧(TIME_PHYSICS_PROCESS) | 备注 |
|---|---|---|---|---|---|
| 基线（默认 6 怪） | 6 | 227 | — | ~0.6ms | |
| 压测 A | 103 | 532 | 3069 | **1.87ms** | 敌人不死（hp×40），纯移动+索敌负载 |
| 压测 B（+3 武器） | 103 | 566 | — | 2.86ms | |
| 压测 C | 203 | 876 | 3073 | **4.00ms** | |
| 终局（9 武器 Lv8） | 203 | **1273** | **5284** | — | 节点超 §3 预算 41%、对象超 51% |
| **hitstop 副作用** | — | — | — | — | **实测 `Engine.time_scale` 最低降到 0.050**（压测 B 阶段） |

**表 E2：能力验证结果**

| 验证项 | 结果 | 证据 |
|---|---|---|
| 无头启动大厅场景 | ✅ 无脚本错误 | `--headless res://scenes/lobby.tscn` 25 秒仅超时杀进程，无 SCRIPT ERROR |
| 无头跑完整战斗流程 | ✅ 选人→进层→刷怪→升级→存档全链路跑通 | E1 各阶段均完成 |
| 存档往返 | ✅ `save_run=true`，`has_save=true`，17 个字段全量恢复（含 4 把武器的 `cd_t` 浮点） | `run_save.gd` 可靠 |
| `RunSave.clear()` | ✅ `has_save=false` | `run_save.gd:41` 的 `remove_absolute` 有效（此前疑点排除） |
| 数据表现值 | WEAPONS=19 / SUPERWEAPONS=19 / PASSIVES=12 / **RELICS=4** / ENEMIES=4 / SKILLS=7 / TALENTS=15 | 与 README 的"12 件遗物"不符 |
| **`test/smoke.gd`** | ❌ **完全失效** | `godot --headless -s res://test/smoke.gd` 实测报错：`Identifier not found: Sfx`（`player.gd:458`，`-s/--script` 模式不注入 autoload）；修复注入后仍报 `FAIL: player node exists`（smoke.gd 未设置 `Meta.selected_char`，而 `main.gd:50-52` 依赖它才生成玩家）；且 `smoke.gd:56` 调用的 `player.try_attack()` **在 player.gd 中不存在**、`:79` 断言 3 只敌人与 `game_data.gd:392` 首层编队 6 只矛盾 |
| `--check-only` / `--script` | ❌ 不可用于本项目（autoload 引用会误报） | 本机已知限制（见 6.3） |

### 6.2 可自动化的最小验证集（v0.8 门禁，对应 §5 A6）

| ID | 名称 | 内容 | 判定标准 | 运行方式 |
|---|---|---|---|---|
| **V1** | 解析门禁 | 遍历 `res://` 全部 `.gd` 逐个 `load()`；检查 autoload 全部实例化成功 | 0 个 parse error；0 个 "does not inherit from Node" | `godot --headless --import && godot --headless -s tools/check_parse.gd`（`-s` 模式对纯解析可靠） |
| **V2** | 启动门禁 | 真实入口 → 选 aila → 进入第 1 层 | player 存在、`enemies==6`、无 SCRIPT ERROR | `godot --headless res://scenes/lobby.tscn` + autoload 驱动（本报告已验证的模式） |
| **V3** | 存档往返 | `save_run()` → `load_run()` → 字段逐一比对（weapons/passives/skills/relics/cd_t/level/floor/endless）→ `clear()` → `has_save()==false`；再做一次"写损坏数据→读→应回退默认且不崩溃" | 全字段相等；损坏用例不崩溃 | 同上，用例内嵌 |
| **V4** | 数值/内容门禁 | 遍历 `data/`：每个 weapon.kind 有注册执行器；每个 superweapon 的 weapon/passive 存在；每个 icon 路径 `ResourceLoader.exists()`；武器/被动/遗物数量与策划表一致 | 0 缺失 | `tools/check_content.gd` |
| **V5** | 压测门禁 | 无头生成 60 只怪 + 终局 6 武器，跑 3 秒 | `TIME_PHYSICS_PROCESS` p95 ≤ 4.0ms（桌面）；`node_count` ≤ 900；`Engine.time_scale` 不低于 0.95（A1 完成后） | 同 V2 驱动 |
| **V6** | 体积门禁 | 导出后读 `.pck` 体积；用 curl 校验 R2 是否返回 `Content-Encoding` | pck ≤ 12MB；压缩后首包 ≤ 12MB | `tools/export_web.py` |
| **V7** | 残留门禁 | 切层后 `pickups`/`corpses` 组计数归零；死亡/通关后 `RunSave.has_save()==false` | 全部归零/false | 并入 V2/V5 |

### 6.3 已知平台限制（写自动化时必须绕开）

1. **`godot --headless --check-only` 会挂起**，不可用。
2. **`godot --headless -s <script>` 不注入 autoload**：任何引用 `Sfx`/`Meta`/`GameData` 的脚本在此模式下报 `Identifier not found`（实测 `player.gd:458`）。因此 **V1 只做纯解析、V2-V7 必须走"真实场景入口 + autoload 驱动"**。
3. 新增资产后必须先跑一次 `--headless --import` 生成 `.import` sidecar，否则 `load()` 返回 null。
4. 退出码：用 `get_tree().quit(exit_code)` 显式退出，进程被 `timeout` 杀掉时 stdout 可能丢失 —— **长跑用例要把结果实时写文件**（本阶段实测：print 缓冲在 SIGTERM 时丢失，已改用 `FileAccess` 逐行落盘）。
5. 本机构建提示：`BUG: Unreferenced static string to 0: servers` 为良性警告，可忽略。

### 6.4 无法自动化的部分（明确列出）

- 真实浏览器帧率 / Draw Call / 内存（需 Chrome DevTools + 真机 Safari），建议 v0.8 发布前做一次人工真机清单：iPhone Safari、低端 Android Chrome、桌面 Chrome 各一遍。
- 手感类：hitstop 改造后的打击感、摇杆跟手度。
- 音频：WebAudio 解锁时机的真实验证（现有 `lobby.gd:40-46 ?autotest=1` 机制可保留到测试包）。

---

## 7. 前提假设与重估触发条件

| # | 假设 | 若不成立 |
|---|---|---|
| H1 | v0.8 是**单平台（Web）发布**，不要求同时出 Steam/移动包 | 若要求三端同步，C1/C2 提前，工作量 +15~20 人日，且 §3 预算要按最差平台重定 |
| H2 | 团队为 1 人 + AI 协作，v0.8 周期按 4~6 周（≈20 人日）规划 | 人力增加可把 B 档全部并入 v0.8 |
| H3 | 三选一/构筑改动的实现载体已按 Phase 3 对齐拆分：**A3a 选择器修正（阻塞，0.3 人日）+ A3b StatBlock 管线（非阻塞，2.5 人日，随 L2）**；本人初版"passives.has 锁死"的指认已被交叉复核修正（见 §1.1 最终口径） | 若 A3a 实现时改动 `build_levelup_options` 以外的入口（如把选择逻辑迁到新模块），需与 B1 的 player.gd 拆分同批评审，避免二次返工 |
| H4 | 现有 19MB 资产中 `assets/ella` 等源文件在别处有备份，从仓库/pck 移除不影响生产 | 若这是唯一副本，改为"移出 repo 但归档"，首包收益不变 |
| H5 | R2 bucket 的压缩可用性分档：gzip 可开启 → 首包 ≈14MB；**≤12MB 硬线需 brotli + wasm-opt**。若 brotli 不可用，硬线放宽到 14MB（美术侧已无可让空间，见 03 文档），或追加 wasm-opt 步骤，A7 落地时定案 | 若 gzip 也无法开启，首包目标放宽到 22MB，TTI 预算相应放宽到 40s |
| H6 | 平台规则类信息（Steam 分成/审核、iOS/Android 商店政策）**会随时间变化**，本报告未展开；进入 C1/C2 阶段时以官方文档为准重新核对 | — |

---

*报告完。证据清单：所有文件行号基于 commit `baf32f5` 的仓库副本 `C:/Users/owlco/WorkBuddy/2026-10-02-05-18-37/dungeon-rogue-godot`；实测数据来自本机 Godot 4.7 无头运行（§6.1）；线上产物体积来自 2026-10-02 对 `pub-6d672ee312244873adb8f72bb964be94.r2.dev` 的 curl 实测。*
