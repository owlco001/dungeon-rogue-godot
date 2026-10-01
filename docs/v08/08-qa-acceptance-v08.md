# 《地牢肉鸽 · Dungeon Rogue》v0.8 QA 验收报告（Phase 4：方案审查 + 测试计划）

> 质量监管：严过关（qa-lead）
> 验收对象：**Phase 3《实现方案》（07-implementation-v08.md）**——本阶段仓库仍为 baf32f5 原始状态，未改任何代码，故本报告不含代码缺陷，只含「方案可验收性」与「编码后验收的完整测试计划」。
> 审查基线：01 设计终稿、02 技术基线、03–06 四模块文档（05 §附录为合成演出时序唯一权威）、制作人已裁决 7 项（①金框保留 ②宝箱时序以 05 为准 ③R-7 不做 ④fx_hit_spark 剔除 ⑤supercharge 复用 superfuse 原语 ⑥被动 6 槽保留 ⑦排期 14.3/11.5/25.8）。
> 证据方法：07 全文逐批对照现状代码实读（player.gd / main.gd / fx.gd / sfx.gd / shell.html / meta.gd / run_save.gd / hud.gd / enemy.gd / projectile.gd / boss.gd / gem.gd / summon.gd / game_data.gd / arena.gd / export_presets.cfg / enemy.tscn / assets 目录），全部发现引用文件+行号。

---

## 一、验收条件（从原始需求反推）

编码完成后，v0.8 可交付的验收条件 = 以下五组，全部为可执行判据：

| 组 | 来源 | 条件 |
| --- | --- | --- |
| G1 构筑 | 01 §八 A-1/A-2/A-3/A-6 | 固定 seed 10 局 ≥9 局合成超武；30 层最大回落 ≤−10%；单局 18–25 分钟；被动类槽位占比达标（区间见缺陷 D-5） |
| G2 内容 | A-4/A-5/A-8/A-13 | Boss TTK 区间；首通 ≈1500 金；12 遗物 + 3 敌 + 3 Boss 贴图 + 宝箱全部接线（V4 0 缺失）；README 逐条对齐 |
| G3 节奏 | A-9/A-10 | 层内 40–55s、波次可见、评分正确；6 Boss 不重复 |
| G4 空间 | A-11 | 同 seed 复现、卡墙率 <1%、DrawCall ≤250、节点 ≤900 |
| G5 性能 | A-12 / 02 §3 | V1–V7 全绿 + 30fps 底线 + time_scale ≥0.95 + 首包 ≤12MB（gzip 分档 ≤14MB） |
| G6 演出 | 05 §附录 A.3-5 | 4 条帧差验收（500ms±1 帧 / 同帧 ≤1 帧 / 解除 ≤1 帧 / ducking） |

---

## 二、方案审查结论（07 逐批次审查）

### 2.1 批次级结论

| 批次 | 结论 | 说明 |
| --- | --- | --- |
| B0 验证基建 | ✅ 可验收 | V1 `-s` 纯解析与 02 §6.3-2 已验证限制兼容；run_headless.bat 的 %TEMP% 副本注入方案不污染仓库。V2 判据需按 D-7 修订 |
| B1 数据地基 | ⚠️ 1 处严重 + 2 处一般 | 存档路径错误（D-1）；checksum 被静默丢弃（D-8）；run_save.cfg 兜底未覆盖（D-3） |
| B2 三选一 | ⚠️ 2 处一般 | 伪代码死代码与 01 权重口径偏差（D-6）；A-6 判据区间与模拟数据矛盾（D-5） |
| B3 L1 剩余 | ✅ 可验收 | meta.gd:319-321 / main.gd:122-148/214-227/419-431 引用行号全部实读吻合 |
| B4 性能框架 | ⚠️ 1 处遗漏 | summon.gd 未列入改动文件但 Registry.taunts 必改它（D-2）；其余行号（fx.gd:245-254/297-300/88-98、projectile.gd:98/119/173/215/233、enemy.gd:55-64/100、main.gd:279-334、arena.gd:6-11）全部实读吻合 |
| B5 L2 内容 | ⚠️ 1 处一般 | player_damaged 信号缺攻击者引用，thornmail 无法实现（D-4）；boss 贴图（mohei_phase2/3、widow_b）已实查存在 ✓；gem.gd:67 改造点准确 ✓ |
| B6 L3 活下去 | ✅ 可验收（含 D-7 连带） | wave_director 独立文件 + flag 回退方案满足 01 R-3 的回归风险要求 |
| B7 L4 地牢有形状 | ❌ 1 处严重 | V10 的 DrawCall ≤250 标为「并入 V2 驱动（无头）」不可执行（D-9） |
| B8 收口发布 | ✅ 可验收 | export_presets.cfg:9-11 `exclude_filter=""` 实读吻合；shell.html:199-257 CDN fetch 行号吻合；V6 分档门禁与 02 §1.5/H5 一致；fx_hit_spark.png 零引用已复核 ✓ |

### 2.2 发现明细（文件+行号证据）

| 编号 | 类型 | 描述 | 证据 |
| --- | --- | --- | --- |
| D-1 | **不兼容** | save_service.gd 伪代码写 `const PATH := "user://save.cfg" # 兼容现 Meta.SAVE_PATH`，但现状实际路径是 `user://savegame.cfg`。照抄 = 旧档全部失联，玩家金币/天赋/解锁/成就全丢，与 A8「保进度」目标正面冲突 | 07 §2.5 代码块 vs `scripts/meta.gd:7`（`SAVE_PATH := "user://savegame.cfg"`） |
| D-2 | **遗漏** | B4 改动文件清单不含 summon.gd，但 `Registry.taunts`（替代 taunt_summons 组）的注册/注销在召唤物侧 | 07 §1.1 B4 行 vs `scripts/summon.gd:75-76`（add_to_group("taunt_summons")）、`:286`（remove_from_group） |
| D-3 | **遗漏** | 存档损坏兜底（.bak/.corrupt）只覆盖 meta 存档；`user://run_save.cfg`（中途存档）无版本化、无兜底——损坏时 continue_run 用默认值静默续档 | 07 §2.5 vs `scripts/run_save.gd:6`（独立 SAVE_PATH）、`scripts/main.gd:463-520`（逐字段 .get 容错无提示） |
| D-4 | **接口矛盾** | EventBus 信号 `player_damaged(amount, from_dir)` 无攻击者引用，而 thornmail「反弹 40% 给攻击者」需要 from；且现状 Boss 调用 take_damage 时第 4 参数 from 传默认 null | 07 §2.2 信号声明 vs `scripts/player.gd:1443`（from 参数）、`scripts/boss.gd:147/163`（仅传 2 参数）、`scripts/enemy.gd:141`（传 4 参数） |
| D-5 | **文档间矛盾** | A-6 判据「被动类槽位占 35–50%」与 01 §3.1 定向玩家模拟数据 48.0–62.7%（均值 53.8%）重叠区不足——V8 用「跟随 recommended」策略（≈定向画像）跑出的占比大概率 >50%，合格实现会被判不合格 | 01 §八 A-6 vs 01 §3.1 验证表 |
| D-6 | **伪代码缺陷** | ① `FUNNEL_MULT_WEAPON=2.0`/`FUNNEL_MULT_PASSIVE=3.0` 两常量定义后从未使用（01 §3.1 的「权重 ×2/×3」被「强制塞槽」静默替代，实际效果强于设计）；② 步骤⑤ `if t=="weapon_up" and _funnel_weapon!="": pass` 是死代码（funnel 已在②消费置空） | 07 §2.1 伪代码 ③⑤ 段 vs 01 §3.1 注释块 |
| D-7 | **判据过期** | V2 门禁「enemies==6（新手首层）」在 B6 波次改造后失效：3 波 60/25/15 拆分下开场波 ≈ round(6×0.6)=4 只 | 07 §六 V2 行 vs 07 §1.1 B6（波次 60/25/15） |
| D-8 | **基线偏离** | 02 §4.6 存档结构含 `checksum: int` 与「checksum 不符→走 .bak」，07 §2.5 静默省略 checksum——「篡改后语法合法」类损坏无法检测，只剩截断/解析失败两类可测 | 02 §4.6 代码块 vs 07 §2.5 全节 |
| D-9 | **门禁不可执行** | V10「DrawCall ≤250」与 05 附录验收「RENDER_TOTAL_DRAW_CALLS_IN_FRAME 采样」被 07 标为无头驱动可测——无头模式无渲染，该监控恒为 0（02 §3 已明示 TIME_DRAW「Web 无头为 0，需真机测」） | 07 §六 V10 行、05 §附录 A.3-5 vs 02 §3 预算表「测量方式」列 |
| D-10 | **数字错误** | FX 六池合计 64+64+8+16+8+4 = **164**，05 §5.2 与 07 §2.3 均写 **188**。节点预算验收将失去基准（多算 24 个，方向安全但数字必须修正） | 05 §5.2 合计行、07 §2.3 第 1 条 |
| D-11 | **遗漏（实现细节）** | 05 权威时间轴 T+900 才替换武器栏图标，但现状合成在 T0 即改 `w["id"]` 且 main.gd `_on_upgrade_chosen` 立刻 `hud.set_weapons`——main.gd:366 需为合成选项做延迟刷新特判，07 改动清单未标注此点，漏做则帧差验收②/演出时序不通过 | 05 §附录 A.2 T+900 行 vs `scripts/player.gd:1086-1091`、`scripts/main.gd:363-368` |
| D-12 | **设计主张不同（不计缺陷）** | 07 用「强制塞槽」替代 01 §3.1 的「权重 ×2/×3」实现漏斗，效果更强且更可测；A-1 判据按 07 口径可执行。要求二选一定案并回写 01/07 之一 | 同 D-6 |
| D-13 | **建议** | `superweapon_synthesized(super_id, pos)` 由 hud.gd emit，pos 需经 `_player_ref` 转手；建议改由 player.gd 在 apply_levelup_option 合成分支 emit（数据源更近、少一次跨层取值） | 07 §2.2 emit 表 vs `scripts/hud.gd:915-920` |

**抽查通过项（证据确认无误）**：07 对现状代码的全部关键行号引用（player.gd:981-1113 三选一区、:999/:1029/:1031/:1052 根因链、:1443 take_damage、:1472-1483 phoenixheart、:1257 _densest_cluster；fx.gd:245-254 hitstop/:297-300 材质/:88-98 aura；sfx.gd:10-24 DEFS/:43-56 _gen_all/七原语 :100-214 与 manifest 枚举一一对应；shell.html:170-184 PLAYERS/:199-257 CDN；meta.gd:131-151/:160-172/:289-303/:319-321；hud.gd:43-77 图标表/:882-912 金框复用段/:695-696 toast 轮询；boss.gd:173-193 硬编码 CD；game_data.gd:305-327 RELICS=4/:330-343 BOSSES/:375-380 ENEMIES；export_presets.cfg:9-11；enemy.tscn:18 碰撞形状）逐条实读吻合。**07 的行号引用质量合格，可支撑编码验收。**

---

## 三、门禁可执行性审查（编码后每条怎么测）

### 3.1 V 门禁

| 门禁 | 测法 | 自动化等级 | 备注 |
| --- | --- | --- | --- |
| V1 解析 | `$GODOT --headless --path . -s res://tools/check_parse.gd`；脚本只 load() 全部 .gd + autoload 注册表存在性，**禁引任何 autoload 单例**（-s 模式不注入，02 §6.3-2） | 全自动 | 可执行 ✓ |
| V2 启动 | `tools/run_headless.bat`（TEMP 副本注入 AutoTest → 跑 lobby.tscn → 选 aila → 第 1 层）→ 断言 player 存在、0 SCRIPT ERROR、exit 0 | 全自动 | 判据改「开场怪数 ≤ floor_count(1)」（D-7） |
| V3 存档往返 | 同 V2 驱动：save→load 字段全等→clear→has_save=false；**损坏三类用例见 §五**；同时断言落盘耗时 ≤30ms（save_all() 前后 Time.get_ticks_msec） | 全自动 | 补 D-3：run_save.cfg 与 savegame.cfg 两个文件都要跑损坏用例 |
| V4 内容 | `$GODOT --headless --path . -s res://tools/check_content.gd`（纯静态 + ResourceLoader.exists） | 全自动 | 可执行 ✓ |
| V5 压测 | V2 驱动压测分支：60 敌 + 终局 6 武器跑 3s → TIME_PHYSICS_PROCESS p95 ≤4.0ms、node_count ≤900、time_scale ≥0.95、粒子 ≤650（引擎内计数） | 全自动 | 可执行 ✓；**注意与 V8 互斥**（V8 提速时不能同时断言 time_scale） |
| V6 体积 | `python tools/export_web.py --gate` + `curl -H "Accept-Encoding: gzip, br" -D - ...` 校验 Content-Encoding | 全自动 | 可执行 ✓ |
| V7 残留 | 并入 V2/V5：切层后 pickups/corpses 组归零；死亡/通关后 RunSave.has_save()==false | 全自动 | 可执行 ✓ |
| V8 合成判据 | V2 驱动 `--v8-sim`：固定 seed 10 局、跟随 recommended 选卡、Engine.time_scale 提速；断言 ≥9 局合成 ≥1 把；同步记录升级次数与被动占比（不达标归因用） | 全自动 | 提速跑时禁跑 V5/V9 |
| V9 曲线/节奏 | 静态（30 层 floor_count/HP 表回落 ≤−10%）并入 V4；动态层时长 40–55s 断言必须 **real-time 跑**（提速会破坏时长） | 全自动 | 与 V8 提速互斥，分两个 pass |
| V-audit 音频 | `python tools/check_audio.py`：manifest.id 集 == sfx.gd 运行时集 == shell.html PLAYERS.id 集 + 参数 diff | 全自动 | 可执行 ✓ |
| V10（B7 后） | 同 seed 布局哈希比对复现 ✓ 无头可测；卡墙率 1000 次寻路采样 ✓ 无头可测；**DrawCall ≤250 不可无头测** → 改为：本机**桌面带窗口模式**跑 auto_v08 采样 `Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME`（每 60 帧）+ 发布前浏览器真机复测 | 半自动 | **测法必须修订**（D-9） |

### 3.2 05 §附录 4 条帧差验收

| # | 判据 | 测法 | 自动化等级 |
| --- | --- | --- | --- |
| ① | T0 → superburst 起播 500ms ±16.7ms | 引擎内脚本钩子：AutoTest 监听 `superweapon_synthesized` 记 `Time.get_ticks_msec()`（真实时钟，**禁用 engine 时间**——演出 tween 均 ignore_time_scale），监听 superburst 起播帧差值落盘 | 全自动 |
| ② | superburst 与 glow300 起帧差 ≤1 帧 | 同上钩子：emit `superweapon_burst` 同帧抓 FX 池 acquire 日志帧号 | 全自动 |
| ③ | superring 起播与 time_scale 恢复 1.0 帧差 ≤1 帧 | 同上：帧循环采样 `Engine.time_scale` + 音频起播日志 | 全自动 |
| ④ | BGM ducking 正确进/出 | ducking 在 shell.html JS 层，引擎内无法断言 → 浏览器 DevTools 控制台采样 `window._gameBgm` gain 值，或人工听测 | **人工** |

### 3.3 A-1 ~ A-13 逐条测法

| # | 测法 | 自动化 |
| --- | --- | --- |
| A-1 | = V8 | 全自动 |
| A-2 | = V9 静态 | 全自动 |
| A-3 | 3 次人工完整试玩计时（18–25 分钟） | **人工** |
| A-4 | Boss TTK：V2 驱动逐 Boss 层跑，埋点记录 boss spawn→die 真实时长（走位用简单绕圈策略近似），5/10/15 层 25–38s、20/25 层 34–48s、30 层 50–65s；超差时人工复测校准 | 半自动 + 人工复核 |
| A-5 | 首通金币断言（V9 动态局累计 gain_gold）+ buy_attr 前后 Meta.gold 断言 | 全自动 |
| A-6 | V8 内统计（区间按 D-5 裁决结果） | 全自动 |
| A-7 | 5 名新玩家实测 | **人工** |
| A-8 | = V4（0 缺失）+ V2 驱动内逐遗物拾取生效断言（12 件各触发一次效果钩子） | 全自动 |
| A-9 | V9 动态 + 评分公式单测 | 全自动 |
| A-10 | 6 Boss 人工试玩「不互相重复」 | **人工** |
| A-11 | = V10 | 半自动 |
| A-12 | = V1–V7 全绿 | 全自动（除 30fps 真机项） |
| A-13 | README 逐条对照 §1.4 表 | **人工** |

**结论：无法自动化、必须人工的验收项共 9 项**：A-3 单局时长、A-7 新手 5 人、A-10 Boss 差异化、05 帧差④ ducking、发布前三平台真机清单（iPhone Safari / 低端 Android / 桌面 Chrome：30fps、内存、音频解锁、演出手感）、hitstop 打击感与摇杆跟手度（02 §6.4）、06 音频主观听感（enemy_shot 湿黏感等）、A-13 README 对齐、推荐金框视觉可辨识与 R-2 操控感抽查。

---

## 四、测试用例集（编码完成后执行）

自动化等级：A=全自动无头 / B=半自动（桌面带窗口） / C=人工。

### 4.1 三选一与构筑（B2 后跑，对应 V8）

| 用例 ID | 前置 | 步骤 | 预期 | 等级 |
| --- | --- | --- | --- | --- |
| TC-2-01 | 干净存档，固定 seed | 连跑 10 局跟随 recommended | ≥9 局合成 ≥1 把超武 | A |
| TC-2-02 | 同上 | 统计每局被动类槽位占比 | 落在 D-5 裁决区间内 | A |
| TC-2-03 | 人为把 passive_up 候选置空 2 次升级 | 第 3 次升级 | 强制出现 1 个 passive_up（保底，无推荐标记） | A |
| TC-2-04 | 保底触发局 | 检查 HUD 三选一渲染 | 保底项**无**金框（01 R-2） | A |
| TC-2-05 | 武器升到 Lv8 | 下一次升级三选一 | 强制 1 槽为该武器合成所需被动（new_passive 或 passive_up）且带金框；漏斗一次性消费 | A |
| TC-2-06 | 前 3 次升级 | 逐次检查 | 每次三选一 ≥1 个 new_passive 且带金框 | A |
| TC-2-07（W1） | 武器 6 槽满 | 触发升级 | new_weapon 不出现在选项 | A |
| TC-2-08（W2） | 武器槽满 | 触发升级 ×100（统计） | passive_up 出现频率显著高于未满时（22→30 权重生效） | A |
| TC-2-09（W4） | 武器槽满 + 武器刚到 Lv8 | 触发升级 | 漏斗强制项照常出现（不受槽满影响） | A |
| TC-2-10 | 池全空极端（全部满级） | 触发升级 | 返回 <3 项不崩溃，HUD 正常渲染 0–2 项 | A |
| TC-2-11 | 返回结构回归 | 对比 v0.7 调用方 | `main.gd:360`/`hud.gd:892` 读取签名不变，`recommended` 为可选字段 | A |
| TC-2-12 | 金框渲染 | recommended 选项显示 | 复用 synthesize 金色 StyleBox + 「推荐」角标；synthesize 样式不变 | B |

### 4.2 遗物 12 件全接线（B5 后）

| 用例 ID | 前置 | 步骤 | 预期 | 等级 |
| --- | --- | --- | --- | --- |
| TC-5-01~05 | data/relics.json 12 条 | V4 门禁 | icon 路径全部 ResourceLoader.exists；数量断言 12/7 敌/19 武器/19 超武/7 技能 | A |
| TC-5-06 | 逐件拾取（AutoTest 直发 gain_relic） | 纯属性 6 件（greedcup/windboots/sagestone/magnetcore/wardrum/hourglass） | StatBlock 取值与 relics.json mods 精确一致（hourglass=cooldown×0.8）；移除后恢复 | A |
| TC-5-07 | bloodgem | 击杀普通敌/精英/Boss | 回 2/8/8 HP | A |
| TC-5-08 | cross | 受击后 3s 内再受击 | 第二次伤害 ×0.75；3s 后恢复正常 | A |
| TC-5-09 | scythe | 对 HP 30%/31% 敌各打一下 | 前者 ×1.5 | A |
| TC-5-10 | phoenixheart | 致死一击 | 复活 50% 血一次；第二次致死真死 | A |
| TC-5-11 | thornmail | 被敌/自爆弹/Boss slam 击中 | 攻击者受到 40% 反伤（Boss slam 依赖 D-4 修复） | A |
| TC-5-12 | infinitefire | 等待 10s | 最近 5 敌各 −40；再等 10s 再触发 | A |
| TC-5-13 | 掉落三源 | 精英杀 50 次/Boss 10 次/宝箱 30 次 | 45%±带宽容差 / 100% 且 ≥稀有 / 100% 且权重分布符合 loot.json | A |
| TC-5-14 | 槽满 3 件 | 拾取第 4 件 | 转化 50 金，无弹窗（裁决③） | A |
| TC-5-15 | 传说拾取 | HUD | 金色描边 + modulate 脉动（03 §2.3 色值） | B |

### 4.3 合成演出时间轴（05 §附录权威版）

| 用例 ID | 前置 | 步骤 | 预期 | 等级 |
| --- | --- | --- | --- | --- |
| TC-FX-01 | 合成条件达成 | 点选合成 | T0 = 浮层关闭、emit、演出起点三帧合一；T-400 起仅 HUD 脉动不播演出 | A |
| TC-FX-02 | 同上 | 帧差钩子（§3.2①②③） | 500ms±16.7ms；burst 与 glow300 ≤1 帧；superring 与解除 ≤1 帧 | A |
| TC-FX-03 | 同上 | 顿帧期间观察 | 演出 tween 不拖慢（ignore_time_scale 生效）；打击通道静默；玩家仍可移动/开火 | B |
| TC-FX-04 | 同上 | 武器栏 | T0–T+900 显示旧武器，T+900 替换 + 金框脉动（依赖 D-11 特判） | B |
| TC-FX-05 | 同上 | 粒子与 DrawCall | 演出粒子 52 粒；桌面窗口模式 DC 峰值 ≤250（05 附录修订值 ≈234+余量） | B |
| TC-FX-06 | 同上 | ducking（§3.2④） | gain 0.60→0.30→0.60 进出正确 | C |

### 4.4 Boss 三阶段 / 双生（B5/B6 后）

| 用例 ID | 步骤 | 预期 | 等级 |
| --- | --- | --- | --- |
| TC-B-01 | 30 层打到 P1→P2 | T+0 hitstop0.10+无敌+冻结、T+200 换 phase2 贴图、T+400 冲击环、T+800 恢复且 CD 重置；emit boss_phase_changed | A |
| TC-B-02 | P2 存续 | 每 3s 八向弹幕 ≤40 同屏；P3 狂暴 speed×1.4 + 召唤 ×3 | A |
| TC-B-03 | 20 层双生 | 双体各 50% 血、共享血量 HUD 一条；单侧死亡 → 另侧攻速+50%/dmg+30% + phase=99 信号 | A |
| TC-B-04 | 6 Boss TTK | = A-4（§3.3） | A+C |
| TC-B-05 | Boss 层 BGM duck | 进 Boss 层 duck 开、离层释放 | A（事件断言）+C（听感） |

### 4.5 波次 / 计时（L3，B6 后）

| 用例 ID | 步骤 | 预期 | 等级 |
| --- | --- | --- | --- |
| TC-W-01 | 进非 Boss 层 | 3 波 60/25/15 依次刷出；开场怪数 = round(总×0.6)（D-7 修订后的 V2 判据） | A |
| TC-W-02 | 层计时 ≥70s 或清完三波 | 楼梯出现（二条件先到） | A |
| TC-W-03 | 跑 3 层 | 层时长 40–55s（real-time） | A |
| TC-W-04 | 倒计时 ≤10s | 每秒 emit floor_timer_warning + HUD 条 | A |
| TC-W-05 | 死亡/通关结算 | 评分 = 层数×100+击杀+精英×5+Boss×50+剩余HP×0.5 | A |
| TC-W-06 | WAVES_ENABLED=false | 退回「清层出楼梯」旧行为不崩 | A |

### 4.6 程序化房间（L4，B7 后）

| 用例 ID | 步骤 | 预期 | 等级 |
| --- | --- | --- | --- |
| TC-R-01 | 同 seed 跑 3 次 | 布局哈希完全一致 | A |
| TC-R-02 | 10 seed × 100 次寻路采样 | 卡墙率 <1% | A |
| TC-R-03 | 桌面窗口模式 | DrawCall ≤250（D-9 修订测法）；节点 ≤900 | B |
| TC-R-04 | 6 主题各跑 3 层 | 每主题 ≥3 种布局形态；楼梯在最远房、宝箱次远房、刷怪点距玩家 >340px | A |
| TC-R-05 | 敌人 A* 接入 | 有墙地图无穿墙、无卡死；0.5s 重规划降级可用 | A |

### 4.7 存档（B1 后，贯穿回归）

| 用例 ID | 步骤 | 预期 | 等级 |
| --- | --- | --- | --- |
| TC-S-01 | save→load 往返 | 全字段相等（含 weapons cd_t 浮点、passives、relics、skills） | A |
| TC-S-02 | clear→重启 | has_save=false | A |
| TC-S-03 | v0.7 旧档（无 version 键）启动 | 识别为 v1 → 逐级迁移到 v3；_do_migration 平移行为不变 | A |
| TC-S-04 | v2 档缺 cd_t/flags | 补默认值不崩 | A |
| TC-S-05 | 高频 add_gold 1000 次 | 0.5s 合并写；关键节点立即写；单次落盘 ≤30ms | A |
| TC-S-06 | 三个损坏用例（§五 E-1~3） | 见 §五 | A |

---

## 五、边界与异常场景

### 5.1 存档损坏三类（V3 必测，两个文件都要覆盖）

| 编号 | 场景 | 步骤 | 预期 |
| --- | --- | --- | --- |
| E-1 | **截断**：写盘中断 | 保留 savegame.cfg 前 60% 字节 → 启动 | load 非 OK → .bak 恢复 + toast；无 .bak → 回默认 + `.corrupt` dump 存在；不崩溃 |
| E-2 | **篡改**：语法合法但数值非法 | 金币改为 −999999、talents 值改字符串、version 改 99 → 启动 | 语法合法则 load OK——**现状方案（D-8）下此类只能靠字段级防御**：负数钳到 0、非法值回默认、version > SAVE_VERSION 拒载回默认并 dump；若采纳 checksum 则走 .bak |
| E-3 | **版本降级**（高版本档遇旧程序） | version=4 的档 + SAVE_VERSION=3 程序启动 | 拒绝静默迁移：回默认或提示，绝不按 v1 解析（防字段错位） |
| E-4 | run_save.cfg 损坏（D-3） | 截断 run_save.cfg → 大厅点继续 | 不崩溃；有 .bak 恢复；否则丢弃存档回大厅并提示，**不得用默认值静默续档** |

### 5.2 平台与运行时异常

| 编号 | 场景 | 步骤 | 预期 |
| --- | --- | --- | --- |
| E-5 | AudioContext 被浏览器策略挂起 | 打开页面后不点击直接等 10s → 再首次点击 | 无 JS 异常；首次手势后 BGM/Sfx 正常（shell.html:259-271 手势解锁链保留）；静音开关在挂起态切换不崩 |
| E-6 | CDN/文件缺失 | 断网起服本地打开（B8 后 BGM 入 pck） | BGM 从 pck 加载成功；无 .catch 吞错残留 |
| E-7 | 池耗尽 | 压测下强制 100 次/帧 hit_spark 请求 | 同帧 >6 降级「只留数字/只留 glow」；不 new 节点；帧耗时不劣化 |
| E-8 | 粒子红线 | 构造粒子 >800 | 三级降级触发：黄（拖尾砍半/spark 上限 3/环境粒子关）→ 红（只留 glow、爆炸只留 ring）；**敌弹描边与光晕、自爆红环、slam 警示环、合成演出不降级** |
| E-9 | 敌弹超限 | 同屏 >40 敌弹 | 超出部分只结算伤害无视觉；玩家弹同屏 >40 同规则 |
| E-10 | Registry 一致性 | 敌人死亡 tween 存续期（0.3s）内查询 | begin_frame 过滤 dead ✓；swap-remove 后无野指针引用；USE_REGISTRY=false 回退组查询全绿 |
| E-11 | 极端构筑：槽满 + 保底 + 漏斗叠加 | 6 武器全 Lv8 持有 + 被动 6/6 + 连续 2 次无 passive_up + 某武器刚 Lv8 | 三强制槽按 优先级（synth→漏斗→保底→新手）填充且 ≤3；多余强制项静默丢弃不崩（07 伪代码 `forced.slice(0,3)` 语义，需在实现时确认丢弃顺序 = 优先级序） |
| E-12 | 演出中存档 | T+100–T+900 间触发 save_run | 存档含超武 id（数据 T0 已换），续档不重复播演出、武器栏正确 |
| E-13 | hitstop 与暂停叠加 | 升级浮层（get_tree().paused）期间触发演出通道 | PROCESS_MODE_ALWAYS 节点正常；解除后 time_scale=1.0 无残留（引用计数归零验证） |

---

## 六、性能与兼容验收（预算 6 项）

| # | 预算 | 测法 | 自动化 | 责任 |
| --- | --- | --- | --- | --- |
| P-1 | 30fps 底线（连续 2s 低于判不合格） | 三平台真机 DevTools Performance | **人工** | lead-programmer 出包 / qa-lead 执行 |
| P-2 | 逻辑 p95 ≤4.0ms（60 敌 + 终局 6 武器） | V5 无头 | 自动 | lead-programmer |
| P-3 | DrawCall ≤250 | 桌面窗口模式采样（D-9）+ 浏览器复测 | 半自动 | lead-programmer |
| P-4 | 同屏 ≤60 硬上限 80 | V5 + B6 上限逻辑断言 | 自动 | lead-programmer |
| P-5 | 节点 ≤900 / 对象 ≤3500 | V5（node_count / OBJECT_COUNT） | 自动 | lead-programmer |
| P-6 | 首包 ≤12MB（gzip 分档 ≤14MB）pck ≤5MB | V6 + curl | 自动 | lead-programmer |
| P-7 | time_scale ≥0.95（hitstop 修复） | V5 | 自动 | lead-programmer |
| P-8 | 内存 ≤350MB（iOS 400MB 被杀线） | 真机 Safari performance.memory | **人工** | 同 P-1 |
| P-9 | 存档单次落盘 ≤30ms | V3 计时 | 自动 | lead-programmer |

---

## 七、缺陷清单与风险登记

### 7.1 缺陷（07 方案文档缺陷，编码前必须处理）

| 编号 | 描述 | 定级 | 责任角色 | 建议处理 |
| --- | --- | --- | --- | --- |
| D-1 | save_service 路径 user://save.cfg ≠ 现状 user://savegame.cfg，旧档全丢 | **阻断** | lead-programmer | 改为 user://savegame.cfg；version 字段就地迁移 |
| D-9 | DrawCall 类门禁（V10/05 帧差 DC 项）标为无头可测，实际无头恒 0 | **阻断** | lead-programmer（测法）/ qa-lead（复测） | 修订为「桌面窗口模式采样 + 浏览器复测」，写入 07 §六 |
| D-5 | A-6 判据 35–50% 与定向画像 48–62.7% 矛盾，合格实现会被判不合格 | **严重** | game-design-director 裁决 | 二选一：区间改 35–60%，或 V8 改用休闲画像策略 |
| D-4 | player_damaged 信号缺攻击者引用；Boss 调用 take_damage 不传 from → thornmail/scythe 无法实现 | **严重** | lead-programmer | 信号加 `from: Node2D` 参数；boss.gd:147/163 补传 self |
| D-2 | B4 遗漏 summon.gd（taunts 注册/注销） | 严重 | lead-programmer | B4 改动文件清单补 summon.gd:75-76/286 |
| D-3 | run_save.cfg 无版本化与损坏兜底 | 严重 | lead-programmer | run 数据包加 version；兜底对齐 save_service |
| D-7 | V2 判据 enemies==6 在 B6 后失效 | 一般 | lead-programmer | 判据改「开场波 = round(总只数×0.6)」并注明批次 |
| D-10 | FX 六池合计 164 被写成 188 | 一般 | vfx-director（文档）/ lead-programmer（实现按 164） | 修正 05 §5.2 与 07 §2.3 数字 |
| D-11 | main.gd:366 立即 set_weapons 与 T+900 武器栏替换冲突 | 一般 | lead-programmer | 合成选项时 HUD 刷新延迟到演出 T+900 |
| D-8 | 02 的 checksum 设计被 07 静默省略 | 一般 | lead-programmer | 至少补 version 拒载 + 数值钳制（E-2/E-3）；checksum 可记技术债 |
| D-6 | 伪代码死代码（funnel ×2/×3 常量未用 + pass 分支） | 一般 | lead-programmer | 删除死代码；口径按 D-12 定案 |
| D-13 | superweapon_synthesized 由 hud emit 需转手取 pos | 建议 | lead-programmer | 改由 player.gd 合成分支 emit |

### 7.2 风险登记（P0/P1/P2，编码后阶段）

| 编号 | 风险 | 级别 | 责任角色 | 缓解 |
| --- | --- | --- | --- | --- |
| R-A | V8 引擎内结果与 01 Python 模拟（100%/47%）偏差导致 A-1 不达标 | P0 | lead-programmer + game-design-director | V8 同步记录升级次数/跟随率；不达标先查推荐金框跟随率（07 §五 B2 行已有预案） |
| R-B | B6 主循环推进语义改造回归（01 R-3） | P0 | lead-programmer | WAVES_ENABLED flag + 每批 V1+V2+V5 三连 |
| R-C | StatBlock 数值回归（02 B0「高」风险） | P1 | lead-programmer | `_legacy_*` 双路比对 <0.1%（07 §五 B5 行）；12 遗物分两批合入 |
| R-D | B4 六池 + Registry 同时落地，回归面大 | P1 | lead-programmer | 三级 feature flag 独立回退（07 §五 B4 行已备） |
| R-E | brotli 不可用 → 首包分档 | P1 | lead-programmer | gzip ≤14MB / wasm-opt 复测（07 §五 B8 行） |
| R-F | 演出帧差在 time_scale 提速的自动跑中失真 | P1 | qa-lead | 帧差用例强制 real-time；与 V8 提速 pass 分离 |
| R-G | 排期 58.9 人日超 01 的 ≈50 | P2 | team-lead | 已按裁决⑦口径执行；砍单线顺序 07 §1.1 末行兜底 |
| R-H | 池 188→164 修正后节点余量重算 | P2 | vfx-director | 164+实体池仍在 900 内，方向不变 |

---

## 八、验收结论

**结论：有条件通过。**

07《实现方案》总体可验收：9 批次拆分合理、验证基建先行、行号引用经实读抽查**质量合格**（约 40 处关键引用仅 D-1/D-10/D-11 三处失准）、伪代码与现状代码结构兼容（build_levelup_options 七池段 :982-1050 保留 + :1051-1065 替换的切分与现状完全吻合）、feature flag 回退链完整、门禁体系覆盖 01 全部 A 判据。可以在处理完下列条件后开工。

**放行条件（全部满足后才允许 B0 开工）：**

1. **[D-1/阻断]** save_service 存档路径改为 `user://savegame.cfg`（07 §2.5），并确认旧档 version 就地迁移链；
2. **[D-9/阻断]** V10 与帧差 DrawCall 项的测法修订为「桌面窗口模式 + 浏览器复测」，写入 07 §六；
3. **[D-5/严重]** 制作人裁决 A-6 槽位占比区间（改 35–60% 或 V8 改休闲画像策略）；
4. **[D-4/严重]** player_damaged 信号补 `from` 参数 + boss.gd 补传 self；
5. **[D-2/D-3/严重]** B4 清单补 summon.gd；run_save.cfg 纳入版本化与兜底；
6. **[D-7/D-10/一般]** V2 判据按波次修订；FX 池合计修正为 164；
7. D-12（漏斗口径）二选一定案并回写文档。

条件 1–5 为编码前必改；6–7 可随 B0/B2 首批合入时落实。人工验收项 9 项（§三末）已列入发布前清单，责任分配见 §六/§七。

---

*报告完。全部证据基于仓库 baf32f5 实读与 01–07 文档交叉比对；本阶段未修改仓库任何文件。*
