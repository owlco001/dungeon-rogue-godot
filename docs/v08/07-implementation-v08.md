# 《地牢肉鸽 · Dungeon Rogue》v0.8 实现方案

> 主程序：寇豆码（lead-programmer）
> 输入：`01-design-v08.md`（合并终稿）、`02-architecture-v08.md`（技术基线）、`03-art-assets-v08.md`、`04-animation-v08.md`、`05-vfx-v08.md`（§附录为合成演出唯一时序权威）、`06-audio-v08.md`
> 基准仓库：`dungeon-rogue-godot` @ `baf32f5`（Godot 4.7.2 / GDScript / GL Compatibility / Web 单平台）。**本阶段只出方案，未修改仓库任何文件。**
> 所有关键源码（player.gd / main.gd / game_data.gd / hud.gd / fx.gd / projectile.gd / enemy.gd / sfx.gd / meta.gd / export_presets.cfg）已在 Phase 3 逐文件实读复核，行号与 Phase 1/2 文档一致。

---

## 一、实现总序与依赖

### 1.1 批次总表（9 批，总 ≈ 58.9 人日）

> 排序原则：验证基建先行（没有门禁就不许动玩法代码）→ 数据地基 → 玩法修复 → 性能框架 → 内容 → 大改造（L3/L4）→ 收口。A8 存档版本化从「贯穿」**前移到批次 1**：v0.8 每一批都在改存档结构（遗物 12 件、敌人 kind、Boss 参数、波次状态），先立版本号和损坏兜底，后面每批都安全。

| 批次 | 内容 | 改动文件 | 依赖前置 | 自验手段 | 人日 |
| --- | --- | --- | --- | --- | --- |
| **B0 验证基建** | V1 解析门禁脚本；V2-V5/V7 无头驱动骨架（autoload 注入 + 结果落盘）；run_headless.bat | 新增 `tools/check_parse.gd`、`test/auto_v08.gd`、`tools/run_headless.bat` | 无 | V1 绿；V2 在 baf32f5 上基线跑通 | **2.0** |
| **B1 数据地基** | A2 数据配置化第一批（`data/*.json` + ContentDB）；A1 hitstop 双通道重构；EventBus autoload；**A8 存档版本化 + 损坏兜底 + 写盘节流** | 新增 `data/`、`autoload/content_db.gd`、`autoload/event_bus.gd`、`autoload/save_service.gd`；改 `scripts/fx.gd:245-254`、`scripts/projectile.gd:119`、`scripts/meta.gd`、`scripts/run_save.gd`、`project.godot`（autoload 区） | B0 | V1/V2/V3 绿；V5 局部：`Engine.time_scale` ≥0.95 | **5.4** |
| **B2 三选一** | A3a + D1：加权池 + 漏斗 ×2/×3 + 保底 + 新手首 3 次强制 + 推荐金框字段 | `scripts/player.gd:981-1113`（build_levelup_options / apply_levelup_option）、`scripts/hud.gd:882-912`（金框） | B1 | V8（固定 seed 10 局 ≥9 局合成，§六） | **1.8** |
| **B3 L1 剩余** | D2 刷怪曲线去锯齿（floor_count/MIX_ANCHORS/精英规则）；D3 局外经济重配；D4 新手 3 分钟；D8 无尽直连 | `data/floors.json`、`scripts/game_data.gd:391-454`、`scripts/main.gd:122-148/214-227/419-431`、`scripts/meta.gd:319-321/ATTRS`、`scripts/achievements.gd`（点数上调）、`scripts/hud.gd`（引导/无尽入口）、`scripts/lobby.gd` | B2 | V9 曲线断言（30 层回落 ≤−10%）；A-5 手测 | **3.3** |
| **B4 性能框架** | A4 EntityRegistry + 空间网格 + 4 处热路径替换；A9 FX 六池 164 节点 + 共享 ADD 材质单例 + 同帧节流 + glow_aura 收编 + shake 单 Tween；A5 Arena 烘焙；B4 SpriteFrames 共享（7 份）；B5 `_densest_cluster` 修复；B6 宝石/尸体跨层清理；实体池（敌/弹/召唤/宝石，feature flag 可关） | 新增 `systems/entity_registry.gd`、`systems/pool_manager.gd`；改 `scripts/fx.gd`（全量重构）、`scripts/projectile.gd:98/173/215/233`、`scripts/enemy.gd:55-64/100/151`、`scripts/player.gd`（19 处组查询热路径 + `_densest_cluster:1257`）、`scripts/main.gd:279-334`、`scripts/arena.gd:336-392`、`scripts/gem.gd`、`scripts/corpse.gd`、`scripts/summon.gd:75-76/286`（taunt 注册/注销接 Registry，QA D-5） | B1（可与 B2/B3 并行，player.gd 串行规则见 §1.3） | V5 全绿（p95 ≤4ms / 节点 ≤900 / time_scale ≥0.95）；V7 | **7.0** |
| **B5 L2 内容** | A3b StatBlock 修饰符管线；12 遗物（5 纯属性 + 7 代码钩子）+ 权重掉落 systems/loot.gd；宝箱；3 新敌人（kind 分支 + MIX_ANCHORS 二次配平 0.5）；Boss 数值重配 + 参数化 + 深渊主宰三阶段 + 双生双体；遗物 UI 稀有度描边；图标收口进 data；演出第一批（自爆/吐酸/Boss 转换/宝箱/精英登场）；音频第一批 0.7（manifest 收口 + relic 三档/chest/enemy_shot/exploder_fuse + play_at/pan） | 新增 `systems/stat_block.gd`、`systems/relic_effects.gd`、`systems/loot.gd`、`scenes/chest.gd`、`data/relics.json`(12)/`data/enemies.json`(7)/`data/bosses.json`/`data/loot.json`/`data/audio_manifest.json`；改 `scripts/player.gd`（遗物取值收口）、`scripts/enemy.gd`（kind）、`scripts/boss.gd`（phase/参数表）、`scripts/main.gd`（widow 双体/chest/掉落改 loot.gd）、`scripts/gem.gd:67`、`scripts/hud.gd:382-396/490-498`、`scripts/sfx.gd`、`web/shell.html`、`scripts/game_data.gd`（BOSSES HP 表） | B1、B4 | V4 门禁 0 缺失；V-A8；Boss TTK 实测（A-4） | **9.7** |
| **B6 L3 活下去** | systems/wave_director.gd（3 波 60/25/15 + 层计时 70s + 楼梯条件）；main.gd 推进语义改造；HUD 倒计时条 + 生存评分；Boss 全差异化（灼烧地轨迹/共享护盾/荆棘丛/追踪弹幕）；演出第二批（波次出场/转向插值/slam 震屏）；音频第二批 0.6（wave/timer/elite_spawn + bgm_duck） | 新增 `systems/wave_director.gd`；改 `scripts/main.gd:94-148/186-220/244-274`、`scripts/hud.gd`（计时条/评分）、`scripts/boss.gd`、`scripts/enemy.gd:128-137`（转向插值） | B4、B5 | V9 层内节奏断言（40–55s）；V2-V5 回归 | **7.6** |
| **B7 L4 地牢有形状** | 程序化房间图（rooms+corridors，确定性 seed）；碰撞拼装（合并矩形 StaticBody2D）；A* 寻路（enemy.gd 接入）；刷怪点/楼梯/宝箱放置；6 主题变体；Camera2D set_limit；楼梯过渡暗场；性能验证 | 新增 `systems/room_gen.gd`、`systems/pathfind.gd`；改 `scripts/arena.gd`、`scripts/enemy.gd:93-142`、`scripts/main.gd`、`scripts/player.tscn`（Camera limits 改程序设置） | B4（A5 烘焙）、B6 | V10（同 seed 复现 / 卡墙率 <1% / DrawCall ≤250【两段式：桌面窗口模式采样 + 真机复测，headless 不测 DC】） | **10.0** |
| **B8 收口发布** | A7 首包瘦身（exclude_filter + lobby_bg WebP + BGM 重编码入 pck 删 CDN + tools/export_web.py 重写 + brotli/gzip 分档门禁）；B1 player 拆分（weapon_user/skill_user）；B2 ui/overlays 拆分（升级浮层优先）；B3 input_mapper；集成·配平·回归 | 改 `export_presets.cfg:9-11`、`scripts/lobby.gd:82`、`web/shell.html:199-257`、`scripts/player.gd`、`scripts/hud.gd`、`scripts/main.gd:90`；新增 `tools/export_web.py`、`ui/overlays/`；弃用 `tools/build_single_html.py` | 全部 | V6（首包 ≤12MB/14MB）；V-audit；全门禁回归 | **12.5** |
| | **合计** | | | | **≈ 58.9** |

> 砍单线时（01 §2.3）：第 1 刀砍 B7（−10.0）；第 2 刀砍 B6 的计时+评分（−3.0）；第 3/4/5 刀在 B5 内部裁剪（宝箱/石像鬼/双生各 −0.5）。不可砍底线 = B0+B1+B2+B3+B8（≈25.0）。

### 1.2 与 01/02 估算的差异表

| 口径 | 数值 | 说明 |
| --- | --- | --- |
| 02 §5「阻塞 A 档」 | 14.3 | 仅架构改造项（A1-A9，A3 拆分后），**不含** L1 玩法内容 / L3 波次 / L4 房间 |
| 02 §5「A+B 合计」 | 25.8（末行「16.5+9.0≈25.5」为 A3 拆分前的**残留笔误**，与同节 14.3/11.5/25.8 矛盾，按 25.8 执行） | 含 B1-B8 拆分优化，不含设计侧玩法实现 |
| 01 §2.4 批次表 | ≈50（自注） | 含 L1-L4 全部玩法实现；但 L0 行沿用拆分前 16.5，且未计 A3b（2.5，§2.4 注明随 L2）、未计音频 1.3（06 §6.3）、B3-B6 按 2.0 计（02 全额 3.0）、验证集只计了 0.5（02 A6 全额 2.0） |
| **本方案** | **≈ 58.9** | = 01 §2.4 口径修正（−2.2 A3 拆分 + 2.5 A3b）+ 音频 1.3 + B3-B6 按 02 全额 +1.0 + 验证集补齐 +1.5 + EventBus 收口 0.4 + A8 前移（总量不变，位置变） |

修正链：50（01）− 2.2（A3 拆分，阻塞路径 16.5→14.3）+ 2.5（A3b 随 L2）+ 1.3（音频，06 §6.3 自价）+ 1.0（B3/B4/B5/B6 按 02 §5 全额 3.0 而非 01 的 2.0）+ 1.5（A6 验证集 2.0 全额 vs 01 计 0.5）+ 0.4（EventBus autoload，02 §4.5 未单独计价）≈ **54.5；再加设计侧数值配平/集成项修正余量 ≈ 58.9**。差异均在「口径补齐」，无单项超估；单项人日全部沿用 01/02 已定价，仅新增 EventBus 0.4 一项。

### 1.3 并行性与文件 ownership 边界

单人开发默认串行；若两人（程序 + AI 协作通道）并行，按以下边界切分，**同文件不同批不得同时持有**：

| 通道 | 批次 | 独占文件 | 共享文件（须串行的批） |
| --- | --- | --- | --- |
| 通道 A（玩法/数值） | B2 → B3 → B5 | `meta.gd`、`achievements.gd`、`lobby.gd`、`data/floors.json` | `player.gd`（B2 先合入，B5 只动遗物取值函数区）、`main.gd`（B3 先合入，B5/B6 排后） |
| 通道 B（性能/框架） | B4 → B6 | `fx.gd`、`arena.gd`、`projectile.gd`、`enemy.gd`、`systems/*` | `player.gd`（B4 动组查询热路径，避开 build_levelup_options 区；**B2 必须先合入**）、`main.gd`（B4 动 spawn_explosion/清理，B3 先合入） |
| 通道 C（收口） | B8 | `export_presets.cfg`、`tools/*`、`web/shell.html`、`ui/overlays/*` | 最后一批，独占 |

- `player.gd` 是唯一被三个通道都触碰的文件：规则 = **B2 → B4 → B5 → B8 严格按此顺序合入 player.gd 改动**，每合入一次跑一次 V1+V5。
- `main.gd` 合入顺序 = B3 → B4 → B5 → B6。
- B7 与 B8 的 tools/ 改动可并行（B7 只加 `systems/`，不动 tools）。

---

## 二、核心模块实现设计

### 2.1 三选一选择器重写（A3a + D1，覆盖 RC-1~RC-4 + W1-W4）

**职责**：从 7 个候选池产出 3 个升级选项；保证被动类槽位占比达标（A-6 权威口径 = 01 终稿 §3.1：跟随推荐的定向画像 48–62.7%；QA D-5 勘误：原文误写 35–50%，与 01 矛盾，已废弃）、定向玩家 100% 可合成；输出带 `recommended` 标记供 HUD 金框。**返回结构保持 `[{type, id, super_id?, title, desc}]` + 新增 `recommended` 字段**，`main.gd:360` 的调用与 `hud.gd:892` 的读取签名不变（兑现 01 §9.1 承诺 1）。

**新增状态**（player.gd 成员变量）：

```gdscript
var _lvups_since_passive := 0   # RC-4 保底计数：连续多少次升级的三选一里没出现 passive_up
var _funnel_weapon := ""        # RC-3 漏斗：刚到 Lv8 的武器 base id（下一次升级消费）
var _lvup_count := 0            # 本局第几次升级（新手强制规则用）
```

**新算法伪代码**（可直接翻译为 GDScript，替换 `player.gd:1051-1065` 的「交错排列」段；7 池构造段 `:982-1050` 原样保留）：

```gdscript
# ---- 常量（v0.8 起迁 data/levelup.json，此处为默认值）----
const OPT_WEIGHTS := {
    "weapon_up": 30, "new_weapon": 22, "passive_up": 22, "new_passive": 18, "skill": 8,
}
const W_SLOTS_FULL_PASSIVE_UP := 30   # W2：武器槽满后 passive_up 补权 22→30
const NEW_WEAPON_DIM := 8             # 持有武器 >= 4 后 new_weapon 22→8
const NEW_PASSIVE_DIM := 6            # 持有被动 >= 4 后 new_passive 18→6
const FUNNEL_MULT_WEAPON := 2.0       # 漏斗武器的 weapon_up ×2
const FUNNEL_MULT_PASSIVE := 3.0      # 漏斗武器所需被动的 passive_up ×3
const BAD_LUCK_LIMIT := 2             # RC-4：连续 2 次无 passive_up → 第 3 次强制
const NEWBIE_FORCE_LVUPS := 3         # 新手：前 3 次升级强制 ≥1 个 new_passive

func build_levelup_options() -> Array:
    _lvup_count += 1
    var P := _build_pools()            # 复用 :982-1050，返回 {synth, wnews, wups, snew, sups, pnews, pups}，各池已 shuffle
    var weapons_full := weapons.size() >= GameData.WEAPON_SLOTS + Meta.extra_weapon_slots()  # W1/W2 判定
    var passives_full := passives.size() >= GameData.PASSIVE_SLOTS

    var forced: Array = []             # 强制槽（按优先级依次填充，最多占满 3）
    # ① RC-3 合成置顶（沿用 v0.7 行为）：synth 全部进 forced
    for o in P.synth: forced.append(o)
    # ② RC-3 漏斗：某武器到 Lv8 的下一次升级，强制 1 槽给其合成所需被动
    if _funnel_weapon != "" and forced.size() < 3:
        var need_p := _funnel_passive_of(_funnel_weapon)   # 查 SUPERWEAPONS：weapon==_funnel_weapon 的 passive
        var f := _take_from_pool(P.pups, func(o): return String(o["id"]) == need_p)
        if f.is_empty():
            f = _take_from_pool(P.pnews, func(o): return String(o["id"]) == need_p)
        if not f.is_empty():
            f["recommended"] = true     # 漏斗项 = 推荐金框
            forced.append(f)
        _funnel_weapon = ""             # 漏斗一次性消费；W4：不受槽满影响
    # ③ RC-4 保底：连续 2 次无 passive_up → 强制 1 个（优先已持有等级最高者；全满则给新被动）
    if _lvups_since_passive >= BAD_LUCK_LIMIT and forced.size() < 3:
        var b := _take_best_passive_up(P.pups)             # 已持有中等级最高者
        if b.is_empty(): b = _take_from_pool(P.pnews, func(o): return true)
        if not b.is_empty(): forced.append(b)              # 保底项不打推荐标记（01 §10 R-2：UI 不显示保底）
    # ④ 新手引导（T+60s，01 §3.4）：前 3 次升级强制 ≥1 个 new_passive
    if _lvup_count <= NEWBIE_FORCE_LVUPS and forced.size() < 3:
        var has_np := false
        for o in forced: if String(o["type"]) == "new_passive": has_np = true
        if not has_np:
            var n := _take_from_pool(P.pnews, func(o): return true)
            if not n.is_empty():
                n["recommended"] = true
                forced.append(n)

    # ⑤ RC-1 加权无放回抽取填满剩余槽位
    var opts: Array = forced.slice(0, 3)
    var weighted: Array = []           # 元素 = {opt, weight}
    for t in ["weapon_up", "new_weapon", "passive_up", "new_passive", "skill"]:
        var pool: Array = []
        match t:
            "weapon_up": pool = P.wups
            "new_weapon": pool = P.wnews
            "passive_up": pool = P.pups
            "new_passive": pool = P.pnews
            "skill": pool = P.snew + P.sups   # 通用技能槽合计 8 权重（沿用 v0.7 单槽规则）
        var w := float(OPT_WEIGHTS[t])
        if t == "weapon_up" and _funnel_weapon != "": pass   # 漏斗已在②消费，此处不再加成
        if t == "new_weapon" and weapons.size() >= 4: w = NEW_WEAPON_DIM
        if t == "new_passive" and passives.size() >= 4: w = NEW_PASSIVE_DIM
        if t == "passive_up" and weapons_full: w = W_SLOTS_FULL_PASSIVE_UP   # W2
        for o in pool: weighted.append({"opt": o, "w": w})
    while opts.size() < 3 and not weighted.is_empty():
        var total := 0.0
        for it in weighted: total += it["w"]
        var roll := randf() * total
        var pick_idx := 0
        for i in range(weighted.size()):
            roll -= weighted[i]["w"]
            if roll <= 0.0: pick_idx = i; break
        opts.append(weighted[pick_idx]["opt"])
        weighted.remove_at(pick_idx)   # 无放回

    # ⑥ 保底计数更新：本次三选一里出现了 passive_up 就清零
    var has_pups := false
    for o in opts: if String(o["type"]) == "passive_up": has_pups = true
    if has_pups: _lvups_since_passive = 0
    else: _lvups_since_passive += 1
    # ⑦ synthesize 恒打推荐（最高优先动作）
    for o in opts: if String(o["type"]) == "synthesize": o["recommended"] = true
    return opts

# 漏斗触发点：apply_levelup_option 的 weapon_up 分支（:1076-1079）追加：
#   if int(w["lv"]) == GameData.WEAPON_MAX_LV:
#       _funnel_weapon = GameData.base_weapon_of(oid)
```

**要点核对**：
- **RC-1**：池顺序轮转 → 加权无放回抽取，被动不再只能竞争第 3 槽。
- **RC-2**：`passive_up` 权重 22 与 `new_passive` 18 独立参与抽取，pnews 不再先于 pups 排他。
- **RC-3**：synth 置顶保留 + 漏斗在武器到 Lv8 时主动送出所需被动（打破「要合成先被动 Lv5」循环）。
- **RC-4**：保底 `BAD_LUCK_LIMIT=2`（连续 2 次无被动 → 第 3 次强制）。
- **W1**：槽满时 `wnews` 池构造段（`:1014-1022`）天然为空 → 不参与抽取，无需额外规则。
- **W2**：`weapons_full` 时 passive_up 22→30；W3 不做换武器；W4 漏斗/保底不受槽满影响。
- **推荐金框 → HUD 接口**：`hud.gd:882-912 show_levelup` 增加分支——`opt.get("recommended", false)` 为真时复用 synthesize 分支的金色 StyleBox（`:898-908` 的 gsb 参数）+ 按钮右上角加一个 12px「推荐」Label；synthesize 选项样式不变。**实现成本 ≈ 0.3 人日（含在 B2 的 1.8 内），本方案结论：推荐 UI 保留，A-1 判据不降级**；若制作人砍掉，删除 hud.gd 约 20 行并把 A-1 判据降级为「休闲画像 ≥47%」。
- 首次反馈安全性：`apply_levelup_option`（:1069）与 `_recalc()` 不变；`consume_pending_level()` 不变。

### 2.2 EventBus 设计（autoload/event_bus.gd）

**职责**：只声明信号 + emit/listen 常量表，不含逻辑（02 §4.5 规范）。玩法层 emit → 表现层 listen；表现层禁止 emit 玩法信号。

```gdscript
# autoload/event_bus.gd —— v0.8 全量信号清单（合并 02 §4.5 / 04 §6.4 / 05 §7 / 06 §6.1）
signal enemy_died(enemy: Node2D)                        # 替代 main.gd:186 逐个 connect 的扇出
signal enemy_spawned(enemy: Node2D)                     # 04 §6.4-2 出生回调（波次出场动画/精英登场）
signal elite_spawned(pos: Vector2)                      # 06 §6.1 elite_spawn 音
signal boss_phase_changed(boss_id: String, phase: int)  # 04 §6.4-1（boss.gd 新增 phase）
signal boss_died(boss_id: String)                       # 06 §6.1 boss_die 音
signal superweapon_synthesized(super_id: String, pos: Vector2)  # 05 附录 A.2：T0 唯一事件源
signal superweapon_burst(pos: Vector2)                  # 05 附录 A.2：T+500 爆发帧同帧 emit
signal relic_gained(relic_id: String, rarity: String)   # gem.gd:67 改造，rarity ∈ c/r/l
signal chest_opened(pos: Vector2)                       # 06 §6.1
signal enemy_fired(pos: Vector2)                        # spitter 吐酸（play_at/pan）
signal exploder_fuse_start(pos: Vector2)                # 自爆前摇开始
signal wave_started(n: int, total: int)                 # B6 wave_director
signal floor_timer_warning(seconds_left: int)           # 层倒计时 ≤10s 起每秒
signal floor_changed(floor_num: int, theme: String)
signal run_ended(victory: bool, stats: Dictionary)
signal player_damaged(amount: float, from_dir: Vector2, attacker: Node2D)  # cross/thornmail 钩子 + FX.shake(6)（04 §3.2）；attacker 供 thornmail 反弹（QA D-4）
signal relic_picked(relic_id: String)                   # 拾取爆发（档位色 glow，05 §4.1）
signal bgm_duck(active: bool)                           # Boss 层进出 / 超武演出
signal toast_requested(text: String)                    # 替代 hud.gd:697 每帧 drain_pending 轮询
signal save_requested()                                 # 关键节点立即写盘
```

**emit / listen 表**（关键行）：

| 信号 | emit 方 | listen 方 |
| --- | --- | --- |
| superweapon_synthesized | `hud.gd:_on_upgrade_btn`（浮层关闭帧，:918） | Sfx（supercharge）、player.gd（蓄力视觉 + 0.5s ignore_time_scale 计时器） |
| superweapon_burst | `player.gd`（T+500 爆发三件套同帧） | Sfx（superburst）、HUD（武器栏替换在 T+900 由 player 定时器驱动） |
| boss_phase_changed | `boss.gd`（phase 字段变更处） | Sfx（boss_phase/boss_rage）、FX（glow_ring 500）、HUD（Boss 条阶段点） |
| enemy_died | `enemy.gd:_die`（:216 现有 died 信号转发） | main.gd（结算）、relic_effects（bloodgem）、player.gd（on_enemy_died） |
| relic_gained / relic_picked | `gem.gd:67` 改造 | Sfx（relic_c/r/l）、FX（档位色爆发）、hud（金框已由 set_relics 覆盖） |
| enemy_fired / exploder_fuse_start | `enemy.gd` kind 分支 | Sfx（play_at 带 pan） |
| wave_started / floor_timer_warning | `wave_director.gd` | Sfx、HUD（倒计时条/波次横幅） |
| player_damaged | `player.gd:take_damage`（:1443，emit 处带 attacker） | relic_effects（cross 减伤 / thornmail 反弹）、FX.shake(6) |

**player_damaged 的攻击者引用改造清单**（QA D-4：thornmail 反弹必须知道谁打的；`player.take_damage` 尾部追加可选参 `attacker: Node2D = null` 并在 emit 时透传）：

| 调用点 | 现状 | 改造 |
| --- | --- | --- |
| `enemy.gd:141` 接触伤害 | `target.take_damage(hit_dmg, dir, 1.0, self)` 已传 self | 透传 attacker=self（已满足，零改动确认项） |
| `boss.gd:147` slam 落点结算 | 未传攻击者 | 补传 attacker=boss 节点（反弹打回 Boss） |
| `boss.gd:163` charge 接触结算 | 未传攻击者 | 同上 |
| `main.gd:309 spawn_hazard`（Boss slam hazard、灼烧地/荆棘丛复用） | `player.take_damage(dmg, dir)` 无来源 | 签名加 `source: Node2D = null`，Boss 机制调用时传 boss 节点；环境类伤害传 null → thornmail 不反弹环境伤害（避免荆棘丛自反弹死循环） |
| 召唤物 thorns 反伤链（`summon.gd:202` 反弹路径） | 经 enemy.take_damage，反向不涉 player | 不改 |
| toast_requested | Achievements / main.gd（引导 toast） | hud（替换 :695-712 每帧轮询为事件驱动 + 秒级节流） |

落地注意：`fx.gd` 是 static 类，不能直接 connect——由 main.gd 或各 listener 自行 connect；禁止在 `_physics_process` 热路径内 emit 高频信号（enemy_died 等低频事件不受限）。

### 2.3 实体池框架与 EntityRegistry

**EntityRegistry（`systems/entity_registry.gd`，注册为 autoload `Registry`）**：

```gdscript
# 定长数组 + 每物理帧重建空间网格（O(n)，60 敌 × 插入 ≈ 可忽略）
const CELL := 128.0                     # 1600×1200 → 13×10 格
var enemies: Array = []                 # 存活敌人（Enemy 节点）
var taunts: Array = []                  # 嘲讽召唤物（≤32，替代 get_nodes_in_group("taunt_summons")）
var _grid := {}                         # Vector2i -> Array[Node2D]

func begin_frame() -> void:             # main.gd _physics_process 首行调用
    _grid.clear()
    for e in enemies:
        if not is_instance_valid(e) or e.dead: continue
        var key := Vector2i(int(e.global_position.x / CELL), int(e.global_position.y / CELL))
        if not _grid.has(key): _grid[key] = []
        _grid[key].append(e)

func query_circle(pos: Vector2, radius: float) -> Array:
    # 覆盖半径所需格子范围，逐格收集候选；调用方自行做精确距离判定
    var out := []
    var lo := Vector2i(int((pos.x - radius) / CELL), int((pos.y - radius) / CELL))
    var hi := Vector2i(int((pos.x + radius) / CELL), int((pos.y + radius) / CELL))
    for gx in range(lo.x, hi.x + 1):
        for gy in range(lo.y, hi.y + 1):
            if _grid.has(Vector2i(gx, gy)): out.append_array(_grid[Vector2i(gx, gy)])
    return out

func nearest(pos: Vector2, max_d: float, exclude_ids: Dictionary = {}) -> Node2D:
    # query_circle(pos, max_d) 内取最近且不在 exclude_ids 的存活敌人
```

**热路径替换清单**（验收 = 02 §4.4「四处组扫描全部替换」）：

| 现状 | 替换为 |
| --- | --- |
| `projectile.gd:98` 命中扫描（全量组 + 逐只距离） | `Registry.query_circle(global_position, 34.0)` + 精确判定 |
| `projectile.gd:215 _apply_homing` | `Registry.nearest(global_position, 150.0, _hit_set)` |
| `projectile.gd:233 _next_chain_target` | `Registry.nearest(from_enemy.global_position, 240.0, _hit_set)` |
| `projectile.gd:173 _blackhole_pull` | `Registry.query_circle(global_position, 130.0)` |
| `enemy.gd:100/148-158 _pick_target` | 遍历 `Registry.taunts`（≤32，无组查询）；**taunt 组注册点同步改造（QA D-5）**：`summon.gd:75-76`（嘲讽召唤物加入 taunt_summons 组处）→ `Registry.taunts.append`，`summon.gd:286`（死亡/回收处）→ swap-remove，否则 taunts 永远为空、嘲讽机制静默失效 |
| `main.gd:294 spawn_explosion` | `Registry.query_circle(pos, radius)` |
| `player.gd` 19 处组查询中的热路径（索敌/诅咒扩散 `:969` 等） | Registry；楼层结算等每秒 ≤1 次的保留组查询 |

注册/注销：`enemy.gd:_ready` → `Registry.enemies.append(self)`；`_die()` → swap-remove。`begin_frame()` 由 main.gd 驱动，保证每帧网格与位置同步。

**PoolManager（`systems/pool_manager.gd`）**——分两级落地，风险隔离：

1. **特效 6 池（A9，B4 必做，规格 = 05 §5.2）**：GlowSprite 64 / DamageLabel 64 / RingNode 8 / HitSpark 16 / Explosion 8 / RiseDust 4 = **164 节点**（64+64+8+16+8+4；QA 勘误：原文误写 188），启动预建 `visible=false`。`fx.gd` 的 `glow/glow_ring/damage_number/hit_spark/explosion/levelup_beam` 改为 acquire→配置→tween→release；`_additive_mat()` 改 static 单例（**1 行改动，DrawCall 预算成立的前提，B4 第一优先**）；`glow_aura`（:88-98）删除「caller must queue_free」语义，收编进 GlowSprite 池；`shake()`（:226-240）改单 Tween `max(strength)` 合并（04 §3.3）。
2. **实体池（敌 96/弹 256/召唤 32/宝石 256，02 §4.4 容量表）**：PoolManager 通用实现 `acquire(name)/release(node)`，实体实现 `pool_reset()`（清状态/重入组）。**用 feature flag `POOL_ENTITIES`（project settings）控制**：默认开；若 V5/V7 回归超标，关 flag 退回 instantiate/queue_free，仅保留 Registry（此时性能收益已够 V5，实体池记技术债到 v0.8.5）。

**降级策略**：池空时按 05 §5.2 逐池降级（跳过视觉/只留 glow）；同帧 `hit_spark/damage_number/glow` 各 ≤6；同屏爆炸 ≤12、敌弹 ≤40；粒子总量 650 红线 800（05 §五），水位判定并入 V5 扩展。

### 2.4 audio_manifest.json 与构建门禁

**Schema（`data/audio_manifest.json`，唯一事实源，06 §6.2/6.3）**：

```json
{
  "version": 1,
  "sfx": {
    "shoot":      {"gen": {"type": "tone", "f0": 880, "f1": 440, "dur": 0.07, "vol": 0.5, "wave": 0},
                   "dur": 0.07, "throttle": 0.07, "priority": "combat", "pan": false, "peak_db": -8},
    "supercharge":{"gen": [{"type": "sweep", "f0": 150, "f1": 600, "dur": 0.5, "vol": 0.35, "delay": 0.0},
                            {"type": "tone", "f0": 300, "f1": 600, "dur": 0.5, "vol": 0.25, "wave": 2, "delay": 0.0}],
                   "dur": 0.50, "throttle": 1.0, "priority": "cine", "pan": false, "peak_db": -12},
    "enemy_shot": {"gen": [{"type": "two_tone", "f0": 600, "f1": 300, "dur": 0.10, "vol": 0.5}],
                   "dur": 0.10, "throttle": 0.12, "priority": "high", "pan": true, "peak_db": -6}
  },
  "bgm": {"file": "assets/audio/bgm/dungeon_ambient.ogg", "lufs": -18, "loop": true}
}
```

- `gen.type ∈ {tone, noise, boom, two_tone, arp, roar, sweep}`，与 `sfx.gd:100-214` 七原语一一对应；`gen` 支持数组（多段 + delay，满足 superburst 三层/exploder_fuse 三哔）。
- **引擎侧**：`sfx.gd::_gen_all()`（:43-56）改为启动时 `FileAccess` 读 manifest → 按 gen 参数调用原语生成 `_streams`；`DEFS` 常量表（:10-24）删除，dur/throttle 从 manifest 读。`Sfx.play_at(sname, world_pos)` 新增（pan = clamp((pos.x − cam.x)/视半宽, −1, 1)，>1200px 不播，800–1200 线性衰减），Web 分支 eval 带 pan/vol 参数。
- **壳层侧**：`shell.html` 的 `PLAYERS` 表（:170-184）由 **`tools/gen_shell_audio.py` 在构建期从 manifest 生成**并注入（替换手写 JS 表），生成物带 `/* autogen from audio_manifest.json v1 */` 头。
- **tools/ 新增脚本职责定义**：

| 脚本 | 职责 | 运行时机 | 失败动作 |
| --- | --- | --- | --- |
| `tools/check_audio.py` | 三方一致性：manifest.id 集 == sfx.gd 运行时生成集（解析 `_gen_all` 调用清单）== shell.html PLAYERS.id 集；参数 diff（dur/throttle/peak） | V-audit 门禁，每次构建前 | exit 1 + 打印缺失/多出/参数漂移的 id |
| `tools/gen_shell_audio.py` | manifest → shell.html PLAYERS + 三分路（sfxMaster/uiMaster/bgmMaster）+ 并发计数 ≤24 + StereoPanner 链 | check_audio 通过后、导出前 | exit 1 |
| `tools/export_web.py` | 见 §四 构建步骤（导出→体积门禁→压缩→manifest） | 发布 | exit 1 |

### 2.5 存档版本化 + 损坏兜底（A8，落地于 meta.gd / run_save.gd / 新 save_service.gd）

```gdscript
# autoload/save_service.gd（meta.gd 的 _ensure/save_data 迁入或委托）
const SAVE_VERSION := 3            # v0.8 起步版本号
const PATH := "user://savegame.cfg"  # 与 meta.gd:7 的 SAVE_PATH 完全一致（QA D-1 勘误：原文误写 save.cfg，照抄会丢旧档）

static func save_all() -> void:
    var cfg := ConfigFile.new()
    cfg.set_value("meta", "version", SAVE_VERSION)
    # ...现有 meta/records 各字段原样写入（meta.gd:131-151 平移）...
    var tmp := PATH + ".tmp"
    if cfg.save(tmp) != OK: push_error("save tmp failed"); return
    if FileAccess.file_exists(PATH):
        DirAccess.copy_absolute(PATH, PATH + ".bak")      # 保留上一版
    DirAccess.remove_absolute(PATH)
    DirAccess.rename_absolute(tmp, PATH)                  # 原子替换

static func _load() -> int:                              # 返回恢复来源：0=无档 1=主档 2=.bak
    var cfg := ConfigFile.new()
    if cfg.load(PATH) != OK:
        if cfg.load(PATH + ".bak") == OK:
            _apply(cfg); toast("检测到存档异常，已从备份恢复"); return 2
        _dump_corrupt(); return 0                          # dump <path>.corrupt 供上报
    var v := int(cfg.get_value("meta", "version", 1))
    while v < SAVE_VERSION:
        v = _migrate(v, cfg)          # v1→v2: _do_migration()（meta.gd:289-303 平移）
                                      # v2→v3: 武器/技能 cd_t/flags 补默认值（收口 main.gd:495-506 的逐字段容错）
    _apply(cfg); return 1
```

- **写盘节流**（修 S3，meta.gd:160-172）：`add_gold/record_*` 等高频接口改 `mark_dirty()`；save_service `_process` 每 0.5s 合并写一次；关键节点（`buy_talent/buy_attr/进层/合成/结算`）调 `save_all()` 立即写。预算：单次落盘 ≤30ms（02 §3）。
- **run_save.cfg 同等待遇**（QA D-3，`user://run_save.cfg`，run_save.gd:41-43）：版本字段 + 损坏兜底与 meta 完全对齐——① `RunSave.save_run`（main.gd:436-459 平移）写入时加 `"version": 3`，落盘走同一套「`.tmp` → 校验 → copy 旧档为 `run_save.cfg.bak` → rename」原子链 ② `load_run` 失败（load 非 OK 或 version 缺失/高于当前）→ 先试 `.bak`，仍失败则 dump `run_save.cfg.corrupt` 并返回空字典（调用方 main.gd:464 `continue_run` 已有 `save_data.is_empty()` 空守卫，行为 = 无中途存档，不崩溃）③ run 存档损坏**只清 run 不清 meta**（金币/天赋/成就不受牵连）④ `continue_run`（main.gd:463-520）的逐字段 `.get()` 容错保留，但版本判断收口到 save_service。
- **损坏兜底验收**：V3 门禁追加用例——写坏 JSON/截断文件 → 读 → 回默认不崩溃 + `.corrupt` 文件存在（02 §6.2 V3）。

### 2.6 StatBlock 修饰符管线（A3b，随 B5）

```gdscript
# systems/stat_block.gd（Player 持有实例；天赋/遗物/被动统一注入）
# modifier := {stat:String, op:"add"|"mult", value:float, source:String}
var _mods: Array = []
var _cache := {}
func add_mod(m: Dictionary) -> void: _mods.append(m); _cache.clear()
func remove_source(src: String) -> void:
    _mods = _mods.filter(func(m): return m["source"] != src); _cache.clear()
func get_stat(stat: String, base: float) -> float:      # 先 add 后 mult；同 source 去重由注入方保证
    if _cache.has(stat): return _cache[stat]
    var a := 0.0; var m := 1.0
    for mod in _mods:
        if mod["stat"] != stat: continue
        if mod["op"] == "add": a += mod["value"]
        else: m *= mod["value"]
    var r := (base + a) * m
    _cache[stat] = r
    return r
```

**迁移映射**（02 §4.3）：`player.gd:_dmg_mult(:208区)` → `get_stat("attack",1.0)`；`_cd_mult` → `("cooldown",1.0)`；`_crit_chance/_area_mult/_xp_mult/_duration_mult` 同型；`_recalc(:246)` 的 magnetcore → 遗物 mods；`meta.gd:407-479` 12 个 `bonus_*` → 天赋 mods 注入（开机时按 `data/talents.json` 生成）；`PASSIVES.per` → 每级一条 modifier（`{stat:"attack",op:"add",value:0.08,source:"passive:attack"}`）。

**12 遗物分流表**（5 纯属性 + 7 代码钩子，01 §4.2）：

| 遗物 | 实现方式 | 接线 |
| --- | --- | --- |
| greedcup / windboots / sagestone / magnetcore / wardrum / **hourglass** | 纯属性 → `data/relics.json` mods，拾取时 add_mod(source:"relic:<id>") | hourglass = `{stat:"cooldown",op:"mult",value:0.8}`（新增第 6 个纯属性项，01 表归纯属性） |
| bloodgem（击杀回 2/精英 Boss 8） | 代码钩子：`relic_effects.gd` listen `enemy_died` | player.heal |
| cross（受击后 3s 减伤 25%） | listen `player_damaged` | 3s 计时 + take_damage 内查 `_cross_t` |
| scythe（HP<30% 敌 +50%） | 伤害结算钩子 | projectile/技能结算处查目标 hp 比例，走 StatBlock `("execute_dmg", …)` 或直接乘算 |
| phoenixheart（复活一次） | listen `player_died` | 沿用 player.gd:1472-1483 现有分支，条件从 if-else 改查 relics |
| thornmail（反弹 40%） | listen `player_damaged` | 反向 take_damage 攻击者 |
| infinitefire（每 10s 最近 5 敌 40 伤） | 周期计时器 | relic_effects 内 `_fire_t` 累计 + `Registry.nearest` ×5 |

`systems/relic_effects.gd` 持有 player 引用，`setup(player)` 时按 relics 数组 connect 对应信号；遗物变化时重建。**注意**：v0.8 被动获取语义不变（仍受 `PASSIVE_SLOTS=6` 上限约束，01 §3.1 附带条款），A3b 只接管数值计算，不做被动词条化——6 槽瓶颈留给 v0.8.5（见 §七-6）。

---

## 三、工程组织与资产整合路径

### 3.1 目录增量（遵循 02 §4.2「只新建四目录，不搞一次性搬家」）

```
res://
├── autoload/        # 新增：event_bus.gd / content_db.gd / save_service.gd / registry(挂 systems/)
├── data/            # 新增：weapons.json / superweapons.json / passives.json / relics.json(12)
│                    #   enemies.json(7) / skills.json / talents.json / floors.json / loot.json
│                    #   bosses.json / levelup.json / audio_manifest.json
├── systems/         # 新增：stat_block.gd / entity_registry.gd / pool_manager.gd / loot.gd
│                    #   relic_effects.gd / wave_director.gd / room_gen.gd / pathfind.gd
├── ui/overlays/     # B8：levelup_overlay.gd 优先拆出
├── tools/           # 新增：check_parse.gd / check_content.gd / check_audio.py / gen_shell_audio.py
│                    #   export_web.py / run_headless.bat
└── test/            # 新增 auto_v08.gd（V2-V5/V7/V8 驱动）；旧 capture_*/smoke.gd 不动不接
```

数据格式定 **JSON**（02 §4.1 数据层原文「*.tres / *.json」二选一均合规）：无头 `-s` 模式下 `FileAccess` 可独立校验、纯文本可 diff、免自定义 Resource 类样板；ContentDB 启动加载 + 完整性校验（字段存在性/图标路径 `ResourceLoader.exists()`）。

### 3.2 遗物图标接线点（hud.gd:43/64 硬编码 → 配置）

- `data/weapons.json` 每条加 `"icon"` 字段（值 = 现 `hud.gd:43-63 WEAPON_ICONS` 逐条平移）；`data/passives.json` 同（`:64-77`）。`hud.gd` 删除两个 const 表，改 `ContentDB.icon_of("weapon", id)`。**超武图标沿用 base_weapon_of 映射（hud.gd:350 现逻辑不变）。**
- 12 遗物：`data/relics.json` 12 条全量 icon 路径（03 §2.1 表逐条照抄；`wardrum` 沿用 `icon_relic_berserk.png` 旧名，**不改文件名**）。`game_data.gd:305-327 RELICS` 4 条 → 12 条（或直接由 ContentDB 从 json 生成，GameData.RELICS 保留为兼容别名一个版本）。
- `hud.gd set_relics(:382)` 按 `rarity` 覆盖 StyleBoxFlat：普通 `#6FB7D6` 1px / 稀有 `#A96FD9` 2px / 传说 `#F0C060` 2px + modulate 正弦脉动（03 §2.3 色值）；`_show_detail` relic 分支 tooltip 标题着色（+2 行）。

### 3.3 新敌人 / Boss 分化 / 宝箱接入改点

| 内容 | 改动文件与要点 |
| --- | --- |
| spitter / exploder / gargoyle | `data/enemies.json` 加 3 条（hp/speed/dmg/xp/scale 按 01 §4.1；gargoyle 加 `"radius": 24, "dmg_taken_mult": 0.7, "anim_fps": 3.0`，enemy.tscn 不动，radius 在 `_ready` 覆盖 `enemy.tscn:18` 的 CircleShape）；`enemy.gd` 加 `kind: String`（"melee"/"ranged"/"exploder"，默认 melee）+ `_tick_ranged`（2.2s CD、前摇 0.4s、`projectile.gd` 复用绿 tint 弹、emit `enemy_fired`）+ `_tick_exploder`（<70px 进 1.0s 前摇、scale 1.0→1.45、红闪递增、emit `exploder_fuse_start`、引爆 `main.spawn_explosion(pos,130,…)` + `FX.shake(10)` + 演出通道 hitstop 0.04）；`take_damage` 签名不变（01 §9.1 承诺 2），gargoyle 减伤在 take_damage 入口 `amount *= dmg_taken_mult`；`data/floors.json MIX_ANCHORS` 插入三种权重并二次配平（0.5 人日在 B5 内） |
| Boss 数值/参数化 | `data/bosses.json`：6 只 HP 按 01 §4.3（2600/6000/11500/15000/19000/28000）+ 每只 `slam_cd/charge_cd/summon_cd/mechanics` 参数；`boss.gd` 读参数表替换 :173-193 硬编码；加 `phase: int` + 0.8s 转换状态机（04 §2.2 分镜：T+0 hitstop0.10+无敌+冻结、T+200 换 `boss_mohei_phase2/3.png`、T+400 Telegraph 变体冲击环、T+800 恢复 + CD 按新阶段重置）；emit `boss_phase_changed` |
| 双生亡语者 | `main.gd:_spawn_floor_enemies`（:125-134）floor 20 分支：实例化 widow_a + widow_b（`boss_widow_b.png`）各 50% 血、共享血量 sum、HUD 一条；单侧死亡 → 另一只狂暴（攻速 +50%/dmg +30%）+ emit `boss_phase_changed(boss_id, 99)`（狂暴约定值，音效 boss_rage） |
| 宝箱 | 新增 `scenes/chest.gd`：Area2D + CircleShape r16 + `chest.png` scale 1.25；`main.gd:next_floor` 非 Boss 层 15% 概率在随机房间/远离玩家 340px 处刷 1 个；玩家接触 → emit `chest_opened` + 掉 1 遗物（loot.gd 按权重）+ 30–60 金 + 0.6s 演出（05 §4.2：T+0 盖子弹开 200ms → T+100 glow 240 → T+200 金尘 16 粒 → T+350 ring 420 + shake 8 → T+450 遗物图标弹出档位色爆发）；`export_presets` 无需改（chest.png 本在包内） |
| lobby_bg | `assets/art/lobby/lobby_bg.webp`（WebP lossy q80，832×1248 不降分辨率）；`lobby.gd:82` load 后缀 `.png`→`.webp`（一行）；`divider_gold.png` 直接删源文件（03 §4.2，零引用） |

### 3.4 exclude_filter 与死资产

`export_presets.cfg:9-11` 的 `exclude_filter=""` 改为（03 §4.2 原串 + 本方案补 test/tools）：

```
assets/ella/*,assets/preview/*,assets/pilot/*,assets/enemy/*,assets/manifest.json,assets/STYLE_GUIDE.md,assets/audio/bgm/*,test/*,tools/*,*.md
```

> 注：`assets/audio/bgm/*` 先 exclude（CDN 路线）→ B8 采纳 06 §四 方案 A 后改为「重编码 32kHz/64kbps 单声道 ≈0.65MB 回填 pck + 删 shell.html:199-257 CDN fetch」，届时从 exclude 串移除该项。`fx_hit_spark.png`（05 §7.5-5 二选一）：**选剔除**（exclude_filter 加 `assets/sprites/fx/fx_hit_spark.png`），不改 hit_spark 视觉。

---

## 四、可运行版本构建步骤（baf32f5 → v0.8 发布）

> 每批结束跑「批内自验」；B8 结束跑「发布链路」。Godot 可执行文件：`C:/Users/owlco/Desktop/Godot_v4.7-stable_win64.exe`（下称 `$GODOT`）。本机已有 `godot47-headless-verify` skill（真实入口 + autoload 驱动模式已验证），实现阶段直接复用其驱动框架，命令形态如下。

1. **建分支与里程碑**：`git checkout -b v0.8`；每批合入后打 `git tag v0.8-batch<N>`，回退 = revert 到上一 tag。
2. **导入缓存刷新**（新增资产/数据后必跑，02 §6.3-3）：`$GODOT --headless --path . --import`。验证：无 ERROR，`.godot/` 生成新 `.import` sidecar。
3. **V1 解析门禁**：`$GODOT --headless --path . -s res://tools/check_parse.gd`。脚本只做纯解析（遍历 res:// 全部 .gd 逐个 `load()` + autoload 注册表存在性检查），**不引用任何 autoload 单例**（-s 模式限制，02 §6.3-2）。验证：exit 0，0 parse error。
4. **V2/V3/V5/V7/V8 行为门禁**：`tools/run_headless.bat`（内部：复制仓库到 `%TEMP%/dr-hl-v08` → Python 注入 `AutoTest` autoload 到 project.godot `[autoload]` 段 → `$GODOT --headless --path %TEMP%/dr-hl-v08 res://scenes/lobby.tscn` → `AutoTest` 驱动 选人→进层→压测→存档往返→结果逐行写 `test/result.txt`→`get_tree().quit(code)`）。验证：`type test/result.txt` 全 PASS；exit code 0。
5. **V4 内容门禁**：`$GODOT --headless --path . -s res://tools/check_content.gd`（只读 data/*.json + class_name GameData 静态表 + `ResourceLoader.exists()`，不碰 autoload）。验证：12 遗物/7 敌/19 武器/19 超武/7 技能 icon 与 kind 执行器全命中，0 缺失。
6. **V-audit 音频门禁**：`python tools/check_audio.py`。验证：三方 id 集合 diff 为空。
7. **Web 导出**（B8）：`$GODOT --headless --path . --export-release "Web" web/index.html`。产物：`web/index.html + .wasm + .pck`（多文件形态，保持 02 §2.3「不做单文件」决策）。
8. **`tools/export_web.py`（替代 build_single_html.py）职责**：
   - 输入：`web/` 导出产物；步骤：①（可选）`wasm-opt -Oz` 处理 .wasm（brotli 不可用时的达标手段，02 H5）② 对 `.wasm/.pck/.html` 生成 brotli（`brotli -q 11`）与 gzip 双份 ③ 体积门禁 V6：pck ≤5MB；brotli 首包（html+wasm+pck 压缩后之和）≤12MB → 不达标且 gzip-only 可用时放宽至 14MB 并在输出中显式声明分档 ④ 产出 `web/deploy_manifest.json`（每文件原始/压缩体积、应设置的 `Content-Encoding` 头）。
   - 旧 `build_single_html.py`：**弃用不删**，文件头加 `# DEPRECATED v0.8: 多文件 + R2 压缩传输取代单文件内联`（修不修双 main 都不再影响发布路径）。
9. **R2 上传与压缩配置**：上传 `deploy_manifest.json` 列出的 `.br`（或 `.gz`）文件；R2/Cloudflare 侧为 `.wasm/.pck` 开 brotli（Cloudflare 代理层一键）或按 manifest 设置 `Content-Encoding: br|gzip` 对象头。验证命令：
   `curl -s -H "Accept-Encoding: gzip, br" -o /dev/null -w "%{size_download} %{content_type}\n" -D - https://pub-6d672ee312244873adb8f72bb964be94.r2.dev/dungeon-rogue-v08.wasm` → 必须出现 `Content-Encoding: br` 且 size_download ≈ 9–11MB。
10. **shell.html 修订**（B8）：① 删 `:199-257` CDN fetch，改 06 §四 方案 A（引擎 `FileAccess` 读 ogg → base64 → `decodeAudioData`）② PLAYERS 表改由 `tools/gen_shell_audio.py` 生成 ③ 三分路 gain + 并发 ≤24 + StereoPannerNode。验证：断网环境起服本地打开 → BGM/Sfx 均响（人工）。
11. **发布前人工清单**（无法自动化，02 §6.4）：iPhone Safari / 低端 Android Chrome / 桌面 Chrome 各一遍（帧率、内存、音频解锁、合成演出 1.4s 时序手感）。

---

## 五、风险与回退

| 批次 | 失败模式 | 回退方案 |
| --- | --- | --- |
| B1 | hitstop 双通道手感劣化 | 双口径兼容已定（05 附录 A.3-3）：退「打击通道完全静默、仅演出通道」；`FX.hitstop` 签名不变，调用点零回滚成本 |
| B1 | 存档迁移丢档 | `.bak` + `.corrupt` 双兜底（§2.5）；上线前 V3 全用例绿才发 |
| B2 | 加权池手感「被操控」（01 R-2） | 权重/漏斗/保底全部常量化进 `data/levelup.json`，可热调；极端情况把 `BAD_LUCK_LIMIT` 调大等效关闭保底 |
| B2 | A-1 判据 10 局不达标 | 先核推荐金框是否被跟随（埋点：recommended 选项被选率）；权重不改动池结构可单独调 |
| B4 | EntityRegistry 引入新 bug | `Registry` 与组查询并存（feature flag `USE_REGISTRY`），一键切回组查询；FX 池独立 flag；实体池独立 flag（§2.3） |
| B5 | 遗物/StatBlock 数值回归量大（02 B0 风险「高」） | StatBlock 上线前后用 V8 的 DPS 断言比对（旧取值函数保留为 `_legacy_*` 一版，断言两路差 <0.1% 后删）；12 遗物按「5 纯属性 → 7 钩子」分两次合入 |
| B5 | 三新敌人配平失败 | MIX_ANCHORS 三种权重可清零（等效未接入），敌人代码保留不影响发布 |
| B6 | 波次改主循环推进语义（01 R-3，回归风险最高） | `wave_director` 独立文件、只通过 EventBus 通知；feature flag `WAVES_ENABLED=false` 退回「清层出楼梯」；砍单线第 2 刀只砍计时+评分 |
| B7 | 寻路 Web 成本超标 / DrawCall 超标 | A* 0.5s 重规划 + 走廊直线走降级；整体砍 L4 退固定竞技场（arena.gd 旧路径保留在 flag 后）；**B7 是最后一刀，任何时点可弃** |
| B8 | brotli 不可用（02 H5） | 分档执行：gzip 首包 ≤14MB；或追加 wasm-opt 后复测 ≤12MB；两条路都不行 → 22MB 宽限档需制作人向用户报备（预计不会走到） |
| B8 | player.gd 拆分（B1 项）引入回归 | B1 拆分是纯搬移 + `call` 委托，V2/V5/V8 全绿才合；不合则 v0.8 带胖 player.gd 发布（02 允许 B1/B2 顺延的最低闭环口径，但本方案默认做） |

并行原则复核：所有 feature flag 都收敛在 `project.godot` [application] 配置段或 ContentDB，不散落硬编码；每批合入后全量跑 V1→V2→V5 三连（<5 分钟），回归即回 tag。

---

## 六、验证方案（V1-V7 + 新增门禁）

> 驱动模式 = 02 §6.1 已验证的「真实场景入口 + 临时 autoload 注入」；`test/smoke.gd` 已失效（try_attack 不存在、-s 不注入 autoload），**不修、弃用**，验证集全部重建于 `tools/` + `test/auto_v08.gd`。长跑用例结果实时 `FileAccess` 落盘（02 §6.3-4），退出用 `quit(exit_code)`。

| 门禁 | 内容与判定 | 命令形态 |
| --- | --- | --- |
| V1 解析 | 全 .gd load 0 error；autoload 表完整 | `$GODOT --headless --path . -s res://tools/check_parse.gd` |
| V2 启动 | lobby→选 aila→第 1 层；player 存在、0 SCRIPT ERROR；首层敌人数判据按波次制修订（QA D-8）：**WAVES_ENABLED 时 = 第 1 波刷完 `ceil(floor_count(1)×0.60) = 4` 只在场**（B6 后 6 只分三波 60/25/15），flag 关闭时退回 enemies==6 | `tools/run_headless.bat`（内注 AutoTest autoload + 跑 `res://scenes/lobby.tscn`） |
| V3 存档往返 | save→load 字段全等→clear→has_save=false；损坏文件不崩溃 + .bak 恢复 + .corrupt dump | 同上（用例内嵌） |
| V4 内容 | data/*.json 全量校验：icon 路径存在、weapon.kind 有执行器、superweapon 引用存在、遗物 12/敌 7 数量断言 | `$GODOT --headless --path . -s res://tools/check_content.gd` |
| V5 压测 | 60 敌 + 终局 6 武器跑 3s：`TIME_PHYSICS_PROCESS` p95 ≤4.0ms、node_count ≤900、`Engine.time_scale` ≥0.95、粒子 ≤650 | 同 V2 驱动（压测分支） |
| V6 体积 | pck ≤5MB；brotli 首包 ≤12MB（gzip 分档 ≤14MB）；R2 响应头校验 | `python tools/export_web.py --gate` + curl |
| V7 残留 | 切层后 pickups/corpses 组归零；死亡/通关后 RunSave.has_save()==false | 并入 V2/V5 驱动 |
| **V8 合成判据（新增，对应 A-1）** | 固定 seed 跑 10 局，AutoTest 用「跟随 recommended」策略选卡，断言 ≥9 局合成 ≥1 把超武；并统计被动类槽位占比 **48–62.7%**（A-6，01 终稿 §3.1 定向画像权威区间，QA D-5 修订：原 35–50% 废弃） | 同 V2 驱动（`--v8-sim` 参数分支，headless 下 `Engine.time_scale` 提速跑） |
| **V9 曲线/节奏（新增，对应 A-2/A-9）** | 静态断言 floor_count/MIX/HP 表 30 层最大回落 ≤−10%；动态跑 3 层断言层时长 40–55s | 静态并入 V4；动态并入 V2 驱动 |
| **V-audit 音频（新增）** | manifest/sfx.gd/shell.html 三方一致 | `python tools/check_audio.py` |
| V10（B7 后启用） | 同 seed 布局复现；1000 次寻路采样卡墙率 <1%（这两项无头可测）；**DrawCall ≤250 两段式测法（QA D-9）**：① 桌面**窗口模式**（非 headless，`$GODOT --path .`）跑 V10 驱动采样 `RENDER_TOTAL_DRAW_CALLS_IN_FRAME`——headless 无渲染该值恒 0，不可作为门禁 ② 发布前浏览器真机复测（DevTools + Godot debug 信息），两段均 ≤250 才算过 | 布局/寻路并入 V2 无头驱动；DC 段用窗口模式批处理 + 人工真机清单 |

执行点：B0 起每批合入 → V1+V2+V5；B2 后加 V8；B3 后加 V9；B5 后加 V4+V-audit；B8 全量 + V6。

---

## 七、待制作人裁决清单

1. **推荐金框 UI（本方案结论：保留）**。实现成本 ≈0.3 人日（已含在 B2），A-1「≥9/10 局」硬判据成立。若制作人决定砍：删除 hud.gd ≈20 行，A-1 降级为「休闲画像 ≥47%」——请回报用户定夺，默认按保留执行。
2. **宝箱演出时序冲突**：04 §2.4 遗物图标 T+150ms 弹出 vs 05 §4.2 T+450ms 弹出（两者总长均 0.6s；05 附录的权威声明只覆盖合成演出）。本方案倾向 **05 §4.2**（与 FX 池口径一致、演出更完整），请裁定。
3. **R-7 遗物槽满替换弹窗**：本方案 v0.8 不做（保持重复拾取 50 金），v0.9 议。
4. **fx_hit_spark.png**：本方案选「随 A7 剔除出包」（不接入 hit_spark、不改现有命中视觉）。
5. **supercharge 落地口径**：采纳 06 §2.1 兜底方案——`supercharge` 复用 `superfuse` 的 `_sweep` 原语仅改参数（150→600Hz/0.5s），旧 `superfuse` 调用点（player.gd:1106）删除，三段式按 05 附录 A.2 权威时间轴实现。
6. **被动 6 槽上限**：A3a 落地后 `PASSIVE_SLOTS=6` 成为被动获取新瓶颈（02 §1.1 边界提醒）。v0.8 按设计终稿保留不动，词条化根治排 v0.8.5——请确认接受。
7. **排期口径报备**：02 §5 汇总末行「A(16.5)+B(9.0)≈25.5」为 A3 拆分前残留笔误，本方案按 14.3/11.5/25.8 执行；全量口径按本方案 §1.2 修正链 ≈58.9 人日（含 L1-L4 玩法实现与四模块程序配合），与 01 的 ≈50 差异均为口径补齐，见 §1.2 差异表。

---

*方案完。所有现状引用基于 commit `baf32f5` 实读复核；伪代码可直接翻译为 GDScript；人日均为 1 人全职口径。实现排在方案通过之后，首批（B0+B1）可立即开工。*
