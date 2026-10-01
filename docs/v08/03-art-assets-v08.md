# 《地牢肉鸽 · Dungeon Rogue》v0.8 美术资产规格清单

> 作者：甄塑之（art-model-director）
> 依据：本地仓库 `C:/Users/owlco/WorkBuddy/2026-10-02-05-18-37/dungeon-rogue-godot`（commit baf32f5，只读实盘）+ `01-design-v08.md`（合并终稿）+ `02-architecture-v08.md`（技术基线）+ `assets/STYLE_GUIDE.md` + `assets/manifest.json`
> 所有尺寸/体积均为本机逐文件实测（PNG 头解析 + 文件字节数），非估算值均已标注。
> 本阶段未修改仓库任何文件（只读分析）。

---

## 〇、结论摘要（30 秒版）

1. **v0.8 美术侧确认零新增**。12 遗物图标、3 种新敌人精灵（6 帧文件）、Boss 分化贴图（mohei_phase2/3、widow_b）、宝箱贴图全部已就绪且符合规格，**全部"接线即用"，无需任何 rembg/归一化后处理**（它们已是 `postprocess_assets.py` 管线的最终产物）。
2. **体积预算可以过 12MB 硬线，且有两处好消息**：实测确认 `assets/enemy/`（440KB，slime 原始帧）与 `assets/art/lobby/divider_gold.png`（757KB）**均为零引用死资产**——后者修正了设计终稿 §9.2"divider 在用"的假设。死资产合计 **≈12.3MB**（比柯桥良口径的 11.1MB 还多 1.2MB）。
3. **大厅背景 ≤700KB 有宽裕解**：`lobby_bg.png` 实测 832×1248 RGB / 1,131,454B，转 **WebP lossy q80** 预计 150–250KB（Godot 4.7 原生支持），比 700KB 硬线留 3 倍余量；不需要降分辨率。
4. **遗物 UI 零贴图缺口**：3 格栏、稀有度描边（蓝紫金）、tooltip 全部可用现有代码画法（`StyleBoxFlat`）实现，色值直接取 `STYLE_GUIDE.md` 固定调色板（§三 给出具体色值）；唯一命名瑕疵是 `icon_relic_berserk.png` 实际服务 `wardrum` 遗物，数据表沿用该路径即可，不建议改名（避免动仓库）。

---

## 一、资产盘点核对（v0.8 接线相关，实盘清单）

### 1.1 目录级体积总表（实测字节数）

| 目录/文件 | 实测体积 | 接线状态 | v0.8 处置 |
| --- | --- | --- | --- |
| `assets/sprites/` | 2,145,723 B (2.15MB) | **核心在用** | 全保留 |
| `assets/art/lobby/` | 1,890,660 B (1.89MB) | lobby_bg 在用；divider_gold **零引用** | bg 转 WebP；divider 剔除 |
| `assets/audio/bgm/dungeon_ambient.ogg` | 1,693,463 B (1.69MB) | 代码零引用（shell.html CDN 另拉一份） | 移出 pck（A7 二选一） |
| `assets/ella/` | 9,890,814 B (9.89MB) | 零引用（角色源图） | exclude_filter 剔除 |
| `assets/preview/` | 723,487 B (0.72MB) | 零引用 | 剔除 |
| `assets/enemy/` | 440,287 B (0.44MB) | **零引用**（slime-01~12 原始帧；现用 `sprites/enemies/`） | **剔除（本文新发现）** |
| `assets/pilot/` | 360,276 B (0.36MB) | 零引用 | 剔除 |
| `assets/fonts/hud-subset.ttf` | 210,832 B (0.21MB) | 在用 | 保留 |
| `assets/icons/` | 212,186 B (0.21MB) | 在用（relics 12 + skills 8 + passives 12） | 保留 |
| `assets/tiles/` | 307,540 B (0.31MB) | 在用（6 主题 × 7 张 + decals 6 + decor 2） | 保留 |
| `assets/manifest.json` | 101,951 B (0.10MB) | 零引用 | 剔除 |
| `assets/STYLE_GUIDE.md` | 4KB | 零引用 | exclude_filter 剔除（源文件归档保留） |

> 证据：对 `scripts/ scenes/ web/ tools/` 全量 grep `assets/enemy/`、`divider_gold`、`assets/pilot|preview|ella|manifest` 均 0 命中（`divider_gold` 仅命中其自身 `.import` 与 `.git/index`）。

### 1.2 敌人精灵（10 种 × idle 2 帧，全部 64×64 RGBA）

| 文件（`assets/sprites/enemies/`） | 尺寸 | 单帧字节 | 接线状态 | v0.8 判定 |
| --- | --- | --- | --- | --- |
| `enemy_slime_idle_00/01.png` | 64×64 | ~4.6KB | **已接**（`game_data.gd:375-380`） | 直接过 |
| `enemy_bat_idle_00/01.png` | 64×64 | ~2.8KB | 已接 | 直接过 |
| `enemy_skeleton_idle_00/01.png` | 64×64 | ~5.7KB | 已接 | 直接过 |
| `enemy_brute_idle_00/01.png` | 64×64 | ~5.4KB | 已接 | 直接过 |
| `enemy_spitter_idle_00/01.png` | 64×64 | 6,424B | 未接 | **v0.8 接（远程怪）**，即用 |
| `enemy_exploder_idle_00/01.png` | 64×64 | 6,411B | 未接 | **v0.8 接（自爆怪）**，即用 |
| `enemy_gargoyle_idle_00/01.png` | 64×64 | 4,928B | 未接 | **v0.8 接（高甲怪）**，即用 |
| `enemy_frost_idle_00/01.png` | 64×64 | ~8.0KB | 未接 | v0.9 预留（01-design §4.1） |
| `enemy_spider_idle_00/01.png` | 64×64 | ~4.3KB | 未接 | v0.9 预留 |
| `enemy_witchdoctor_idle_00/01.png` | 64×64 | ~6.1KB | 未接 | v0.9 预留 |

**后处理判定**：全部 10 种均已是管线成品（union bbox 归一 + 64px 方形 pad），**不需要再过 `tools/postprocess_assets.py` 或 `tools/normalize_char_size.py`**。接线零转换：`enemy.gd:55-62` 的路径模式 `res://assets/sprites/enemies/enemy_%s_idle_%02d.png` 对新 id 天然生效。

### 1.3 Boss 贴图（9 张，全部 256×256 RGBA）

| 文件（`assets/sprites/bosses/`） | 字节 | 接线状态 | v0.8 判定 |
| --- | --- | --- | --- |
| `boss_colossus.png`（5 层石颅巨像） | 88,152B | 已接（`game_data.gd:331`） | 直接过 |
| `boss_batking.png`（10 层噬影蝠王） | 41,942B | 已接（`:333`） | 直接过 |
| `boss_forgemaster.png`（15 层熔渣铸造者） | 91,889B | 已接（`:335`） | 直接过 |
| `boss_widow_a.png`（20 层双生亡语者·本体） | 73,334B | 已接（`:337`） | 直接过 |
| `boss_thorntyrant.png`（25 层荆棘暴君） | 76,126B | 已接（`:339`） | 直接过 |
| `boss_mohei_phase1.png`（30 层深渊主宰 P1） | 73,963B | 已接（`:341`） | 直接过 |
| `boss_mohei_phase2.png` | 86,087B | **未引用** | **v0.8 接 P2 变身**，即用 |
| `boss_mohei_phase3.png` | 76,581B | **未引用** | **v0.8 接 P3 变身**，即用 |
| `boss_widow_b.png`（双生第二体） | 64,874B | **未引用** | **v0.8 接双体 Boss**，即用 |

三张未接贴图与已接的 mohei_phase1 / widow_a 同源同管线（同 256px、同描边粗细、同调色板），phase 切换只换 `boss.gd` 的 `_sprite.texture`，无需任何对位修正（见 §六）。

### 1.4 拾取物与宝箱（`assets/sprites/pickups/`，全部 48×48 RGBA）

| 文件 | 字节 | 接线状态 |
| --- | --- | --- |
| `chest.png` | 3,440B | **全仓库 0 引用 → v0.8 接宝箱**（01-design §4.2 掉落三源之一） |
| `coin.png` / `gem_s/m/l.png` / `pickup_magnet.png` / `portal_stairs.png` | 2.7–4.4KB | 已接 |

### 1.5 图标（`assets/icons/`，全部 64×64 RGBA）

- `relics/` 12 张全齐（总计 ≈65KB），逐张实测见 §三。
- `skills/` 8 张、`passives/` 12 张已接，不动。

### 1.6 大厅美术（`assets/art/lobby/`）

| 文件 | 实测 | 引用 | 判定 |
| --- | --- | --- | --- |
| `lobby_bg.png` | **832×1248 RGB**（无 alpha），1,131,454B | `lobby.gd:82`，`STRETCH_KEEP_ASPECT_COVERED` 全屏 + 55% 暗罩（`lobby.gd:87-96`） | 在用；压到 ≤700KB 的具体手段见 §四 |
| `divider_gold.png` | 1568×672 RGB，757,625B | **零引用** | **剔除**（修正 01-design §9.2"在用"的假设） |

> 注：`lobby_bg.png` 实测 832×1248，**不是** 01-design §9.2 推测的 2048px。横向 960×640 视口 COVERED 模式下宽边会放大约 1.15 倍，但有 55% 暗罩压着，视觉无损感；**不需要重制或放大**。

---

## 二、12 件遗物的 UI 呈现方案

### 2.1 图标规格核对（12/12 就绪，全部 64×64 RGBA）

| relic id | 名称 | 稀有度 | 图标文件（`assets/icons/relics/`） | 实测 | 现状 |
| --- | --- | --- | --- | --- | --- |
| `greedcup` | 贪婪金杯 | 普通 | `icon_relic_greedcup.png` | 64×64, 5,255B | 已接（`game_data.gd:313`） |
| `bloodgem` | 血珀 | 普通 | `icon_relic_bloodgem.png` | 64×64, 3,855B | 未接 |
| `windboots` | 疾风之靴 | 普通 | `icon_relic_windboots.png` | 64×64, 6,584B | 未接 |
| `sagestone` | 贤者之石 | 普通 | `icon_relic_sagestone.png` | 64×64, 4,815B | 未接 |
| `magnetcore` | 磁铁核心 | 稀有 | `icon_relic_magnetcore.png` | 64×64, 5,888B | 已接（`:308`） |
| `wardrum` | 狂暴战鼓 | 稀有 | `icon_relic_berserk.png` | 64×64, 5,718B | 已接（`:318`，**文件名与 id 不一致，沿用即可**） |
| `hourglass` | 时之沙漏 | 稀有 | `icon_relic_hourglass.png` | 64×64, 6,469B | 未接 |
| `cross` | 圣十字 | 稀有 | `icon_relic_cross.png` | 64×64, 2,454B | 未接 |
| `scythe` | 收割镰刀 | 稀有 | `icon_relic_scythe.png` | 64×64, 4,728B | 未接 |
| `phoenixheart` | 凤凰之心 | 传说 | `icon_relic_phoenixheart.png` | 64×64, 6,440B | 已接（`:323`） |
| `thornmail` | 荆棘之甲 | 传说 | `icon_relic_thornmail.png` | 64×64, 5,288B | 未接 |
| `infinitefire` | 无尽之火 | 传说 | `icon_relic_infinitefire.png` | 64×64, 7,708B | 未接 |

> **wardrum 命名瑕疵处置**：`icon_relic_berserk.png` 文件名与遗物 id `wardrum` 不一致，但 `game_data.gd:318` 已正确映射且画面内容匹配。v0.8 扩表时**继续引用该路径**，不要改文件名（改了就要动仓库 + 重新 import）。此偏离记录在案，v0.9 整理图标目录时可统一。

### 2.2 三格遗物栏 UI：现有实现与缺口

现有实现（全部代码绘制，无贴图依赖）：
- 槽位按钮 44×44：`StyleBoxFlat`，bg `Color(0,0,0,0.5)`、圆角 6、描边 1px `Color(0.5,0.5,0.55)`（`hud.gd` `_slot_button()`，约 ：270-284）。
- 图标 40×40 `STRETCH_KEEP_ASPECT_CENTERED`（`hud.gd` `_slot_icon()`，约 ：287-296）。
- 3 格创建于 `_build_equip_bars`（`hud.gd:334-344`），点击走 `_show_detail("relic", ...)`。
- 详情浮层（tooltip）为代码搭建 Panel + 图标 + 名称 + `【稀有度】` + 描述（`hud.gd:490-498`）。

**缺口清单（全部零贴图可解，不需要新资产）**：

| 需求 | 现状 | v0.8 方案 |
| --- | --- | --- |
| 稀有度描边（蓝紫金） | 所有槽位统一灰描边 | `set_relics()` 里按 `GameData.RELICS[rid]["rarity"]` 给 `_slot_button` 的 StyleBoxFlat 覆盖 `border_color` + 2px 宽（参数见 §2.3） |
| 传说槽位呼吸感 | 无 | `modulate` 正弦脉动（复用 `enemy.gd:79-86` 精英金脉动公式），纯代码 |
| tooltip 稀有度着色 | `【稀有】`白字 | `lv_text` 按稀有度加 `add_theme_color_override("font_color", ...)`；详情面板描边同色 |
| 底框/稀有度底板贴图 | 无 | **不需要**：`StyleBoxFlat` 黑底 50% + 彩描边即达 UI 可读性目标，且不增加首包体积 |

### 2.3 蓝紫金三档视觉规范（色值直接取 `STYLE_GUIDE.md` 固定调色板，保证同源）

| 稀有度 | 描边色 | 色值 | 辅助 | 依据 |
| --- | --- | --- | --- | --- |
| 普通 | 蓝（冰） | **`#6FB7D6`** | 描边 1px；tooltip 标题同色 | STYLE_GUIDE §2「冰」 |
| 稀有 | 紫（亡灵） | **`#8E44AD`**；深底上可读性不足时用提亮档 **`#A96FD9`** | 描边 2px；tooltip 标题同色 | STYLE_GUIDE §2「亡灵紫」 |
| 传说 | 金（暖） | **`#F0C060`** | 描边 2px + `modulate` 脉动（振幅 ±10%）；与既有超武金框 `Color(1.0,0.82,0.3)`（`hud.gd` `set_weapons`）同族，肉眼可区分但同语言 | STYLE_GUIDE §2「暖金主光」 |

补充规则：
1. 三档描边均叠在现有 `Color(0,0,0,0.5)` 底上，**不改底色**——保证与武器/被动槽视觉连续。
2. 掉落瞬间（精英/Boss/宝箱出遗物）的拾取光柱颜色同用上述三色，复用 `FX.glow`（黄/紫/蓝 tint），无新贴图。
3. 权重表（10/10/10/10/4/4/4/4/4/1.5/1.5/1.5，01-design §4.2）只影响掉落，不影响 UI；UI 只读 `rarity` 字段。

---

## 三、接线资产的规格表（敌人 / Boss 分化 / 宝箱）

### 3.1 三种新敌人（v0.8 接线）

| id | 贴图（已就绪） | 显示 scale 建议 | 碰撞体建议（CircleShape2D 半径） | 行为锚点 | 出场层 |
| --- | --- | --- | --- | --- | --- |
| `spitter` 喷吐怪 | `enemy_spitter_idle_00/01.png` 64×64 | **1.0**（与 slime 同档） | **22**（沿用 `scenes/enemy.tscn:18` 默认，不改场景） | 吐息口锚点 ≈ `(0,-6)`（贴图头部朝上的俯视口部）；酸弹用 `proj_orb.png` + modulate `#6AB04C`（毒绿），显示尺寸 24px | 8 层起，占比 0.08→0.16 |
| `exploder` 自爆怪 | `enemy_exploder_idle_00/01.png` 64×64 | **1.0** | **22**（爆炸半径 130 是逻辑值，与碰撞体无关；前摇"膨胀"用 sprite scale 1.0→1.35 补间，不加帧） | 引爆判定圆心 = 精灵中心 | 11 层起，0.06→0.12 |
| `gargoyle` 石像鬼 | `enemy_gargoyle_idle_00/01.png` 64×64 | **1.35**（对齐 `brute` 的 1.35 档，`game_data.gd:379`） | **24**（略大于默认，匹配更大体型；受击 ×0.7 是伤害逻辑） | 无特殊锚点 | 17 层起，0.05→0.10 |

通用规则（程序侧零新资产接入）：
- `ENEMIES` 表加条目时 `scale` 字段即上表值；`enemy.gd:53` 精英 ×1.3 自动生效。
- 帧数据：2 帧 idle @ 7fps 循环（`enemy.gd:57`），与现有 4 种完全一致，**B4（SpriteFrames 共享）实施时从 4 份扩到 10 份**。

### 3.2 Boss 分化贴图

| 项 | 贴图 | 规格 | 碰撞 | 建议 |
| --- | --- | --- | --- | --- |
| 20 层双生亡语者第二体 | `boss_widow_b.png` | 256×256 RGBA, 64,874B | r=70（沿用 `boss.gd:59-64`） | scale 1.0；与 widow_a 同构，HUD 共享一条血（01-design §5.2），贴图侧无差异处理 |
| 30 层深渊主宰 P2/P3 | `boss_mohei_phase2.png` / `boss_mohei_phase3.png` | 256×256, 86,087B / 76,581B | r=70 不变 | 换阶段只替换 `_sprite.texture`；三张相位贴图同源同尺寸，中心锚点一致，切换无跳动（已逐张实测 256×256） |

### 3.3 宝箱

| 项 | 规格 | 建议 |
| --- | --- | --- |
| 贴图 | `sprites/pickups/chest.png` 48×48 RGBA, 3,440B（已就绪） | 显示 scale **1.25**（48→60px，与地牢物件尺度匹配，略抢眼引导拾取） |
| 触发体 | Area2D + CircleShape2D r=**16**（拾取类，非 CharacterBody，不进 `collision_layer=2`） | 玩家触碰即开箱：掉 1 遗物 + 30–60 金（01-design §4.2） |
| 演出 | 单帧贴图，无拆帧 | 开箱 0.6s：盖子用 sprite 顶部旋转模拟 + `FX.glow` 金光（复用合成大闪参数），01-design §9.3 已排 |
| 命名 | 保持 `pickups/chest.png` | 符合 §3.4 命名规范第 3 条 |

### 3.4 命名规范（沿用 `STYLE_GUIDE.md` §4，v0.8 无一处新文件）

| 类别 | 格式 | 本批涉及 |
| --- | --- | --- |
| 敌人 | `enemy_<id>_idle_<帧号 00/01>.png` | spitter / exploder / gargoyle（+v0.9 三种） |
| Boss | `boss_<id>[_phase<N>].png` | widow_b、mohei_phase2/3 |
| 拾取物 | `<id>.png`（`sprites/pickups/`） | chest |
| 遗物图标 | `icon_relic_<id>.png` | 8 个新条目（wardrum 沿用 `icon_relic_berserk.png` 旧名，见 §2.1） |

---

## 四、体积预算表（首包 ≤12MB 反推）

### 4.1 目标分解（沿用 02-architecture §3：wasm 压缩后 ≤8MB + pck 压缩后 ≤5MB）

### 4.2 逐项目标（现状 → 目标）

| 资产项 | 现状（实测） | v0.8 目标 | 手段（具体参数） | 净变化 |
| --- | --- | --- | --- | --- |
| `assets/ella/` | 9,890,814B | **0** | `export_presets.cfg` 加 exclude_filter | −9.89MB |
| `assets/preview/` | 723,487B | **0** | 同上 | −0.72MB |
| `assets/enemy/`（slime 原始帧） | 440,287B | **0** | 同上（本文新确认零引用） | −0.44MB |
| `assets/pilot/` | 360,276B | **0** | 同上 | −0.36MB |
| `assets/manifest.json` | 101,951B | **0** | 同上 | −0.10MB |
| `assets/STYLE_GUIDE.md` | 4KB | **0**（源文件归档到 docs） | exclude_filter | −4KB |
| `art/lobby/divider_gold.png` | 757,625B | **0** | **零引用，直接从仓库删除源文件**（比 exclude 更干净；本文新发现） | −0.76MB |
| `art/lobby/lobby_bg.png` | 1,131,454B（832×1248 RGB） | **≤250KB**（硬线 700KB 的 1/3，留 3 倍余量） | 转 **WebP lossy q80**（`cwebp -q 80`）；**保持 832×1248 不降分辨率**（COVERED + 55% 暗罩下无可见损失）；Godot 4.7 原生导入 WebP，import preset 选 "Lossy" quality 80。兜底方案：若必须留 PNG，`pngquant --quality 60-90 256` 预计 400–500KB，同样过 700KB 线 | −0.88MB± |
| `audio/bgm/dungeon_ambient.ogg` | 1,693,463B | **pck 内 0** | 与 shell.html 的 CDN 拉取二选一（A7 既定）：保留 CDN 路线，exclude_filter 掉 pck 内副本 | −1.65MB |
| `assets/sprites/` | 2,145,723B | 2.15MB（不变） | 无（全部在用或 v0.8 接入） | 0 |
| `assets/tiles/` | 307,540B | 0.31MB（不变） | 无 | 0 |
| `assets/icons/` | 212,186B | 0.21MB（不变） | 无（12 遗物图标本就在包内，仅是代码没引用） | 0 |
| `assets/fonts/hud-subset.ttf` | 210,832B | 0.21MB（不变） | 无 | 0 |
| **v0.8 美术新增** | — | **0 字节** | 见 §〇 结论 1 | 0 |

exclude_filter 建议串（一行写入 `export_presets.cfg`）：
```
assets/ella/*,assets/preview/*,assets/pilot/*,assets/enemy/*,assets/manifest.json,assets/STYLE_GUIDE.md,assets/audio/bgm/*
```
（divider_gold 建议直接删文件而非 exclude，避免仓库里继续躺着一块 0.76MB 的孤儿。）

### 4.3 汇总对账

| 口径 | 计算 | 结果 |
| --- | --- | --- |
| 留包资产合计 | sprites 2.15 + tiles 0.31 + icons 0.21 + fonts 0.21 + lobby(WebP) 0.25 ≈ | **3.13MB** |
| pck 预算（02 §3 ≤5MB） | 3.13MB + 场景/脚本/导入元数据余量 ≈ 3.3–3.6MB | ✅ 余量 ≈1.4MB |
| pck 压缩后（gzip，PNG 已压收益小） | ≈ 2.8–3.2MB | ✅ |
| 首包合计（压缩传输） | wasm ≈11MB + pck ≈3MB ≈ **14MB**（gzip）；**brotli 下 wasm ≈9–10MB → 首包 ≈12–13MB** | ⚠️ 见下注 |
| 达标判定 | 若 R2 开 **brotli**（Cloudflare 侧一键）：wasm 37.7MB 压缩率约 72–75% → 9.5–10.5MB + pck 3MB ≈ **12.5–13.5MB**；wasm 侧再配合 `wasm-opt -Oz` / Godot 4.7 的 `debug` 符号剥离可再省 0.5–1MB → **≤12MB 可达** | ✅（附条件） |

> **给柯桥良的对齐注**：按本表，pck 侧（美术可控部分）压到 ≈3MB 没有悬念；12MB 硬线的成败在 **wasm 压缩率**（brotli vs gzip 差 ≈1.5–2MB）。若 brotli 不可用（H5 不成立），建议硬线从 12MB 放宽到 14MB 或对 wasm 追加 `wasm-opt` 处理，美术侧无进一步可让空间（留包资产已全部必要）。
>
> **体积口径校准（2026-10-02 与 tech-architect 复核后补记）**：§4.2 表中"现状"列均为**源文件原始体积**；pck 内嵌的是 Godot 导入后产物（PNG 经 ctex 重编码，与源文件不一定等大），因此"剔除 12.3MB ≠ pck 减 12.3MB"。本表用于目录级取舍决策，**pck 实际收益一律以 A7 导出后的 V6 体积门禁实测为准**（02-architecture §6）。

### 4.4 大厅背景 ≤700KB 的验收口径

- 交付物：`assets/art/lobby/lobby_bg.webp`（832×1248，lossy q80，预计 150–250KB）
- 验收：`FileAccess.get_len()` ≤ 716,800B（700KB）；导入后肉眼对比暗罩前后无可见色带（重点查标题金字的暗部过渡）
- `lobby.gd:82` 的 load 路径由 `.png` 改 `.webp`（一行，程序侧）

---

## 五、风格一致性核对（对照 `assets/STYLE_GUIDE.md`）

| 检查项 | STYLE_GUIDE 要求 | 待接线资产实测 | 判定 |
| --- | --- | --- | --- |
| 分辨率规格 | 杂兵 64 / Boss 256 / 图标 64 / 拾取物 48 / 角色 128 / tile 48 | 10 敌人全 64×64；9 Boss 全 256×256；12 遗物图标全 64×64；chest 48×48（§一逐张实测） | ✅ 全合规 |
| 通道 | PNG RGBA 透明背景（tile 除外全幅 RGB） | 敌人/Boss/图标/拾取物全 RGBA；lobby_bg 为全幅 RGB（背景图，允许） | ✅ |
| 画风 | 扁平色块 + 粗描边、暗黑奇幻、无文字 | 12 张遗物图标与既有 4 张同批次生成（manifest v2 批次）；3 张 Boss 贴图与 6 张已接 Boss 同批次 | ✅（同管线同批次，无风格漂移） |
| 俯视/朝向约定 | 3/4 俯角、头顶朝上 | spitter/exploder/gargoyle 均为单方向 idle（敌人无 4 向要求，`enemy.gd` 不翻面，仅 wobble） | ✅ 与现有 4 种敌人呈现方式一致 |
| 调色板 | 固定 8 色 | 酸弹 tint `#6AB04C`（毒）、蓝紫金稀有度 `#6FB7D6/#8E44AD/#F0C060` 全部取自固定调色板 | ✅ |
| 命名 | `<类别>_<id>_<方向>_<动作>_<帧号>` | 唯一偏离：`icon_relic_berserk.png` ↔ id `wardrum`（历史映射已正确） | ⚠️ 记录在案，不改名（§2.1） |
| 遗留风险 | — | `manifest.json` 标 total=164 实列 176 条，且该文件是死资产即将剔除 | 不影响（不入包） |

**结论：待接线资产无一需要返工或重生成。**

---

## 六、给动画 / 特效 / 程序的接口说明（交接帧数据、锚点、切片约定）

### 6.1 给动画导演

| 演出 | 素材基础 | 帧数据 | 锚点/参数 |
| --- | --- | --- | --- |
| 深渊主宰三段变身 | phase1/2/3 三张 256×256 静帧 | **无帧动画**，切换即换 `texture` | 0.8s 内：贴图切换 + `FX.glow_ring(500)` + 无敌帧；切换瞬间无位置/缩放跳动（三张同源同 bbox 归一） |
| 精英登场 | 敌人 2 帧 idle | 无新帧 | `enemy.gd:79-86` 金脉动复用；scale 1.3 弹入 |
| 自爆怪膨胀前摇 | 2 帧 idle | 无新帧 | sprite scale 1.0→1.35 线性 1.0s + 红闪 `modulate`（参考 `boss.gd:118-122` windup 表现） |
| 喷吐怪吐息前摇 | 2 帧 idle | 无新帧 | 0.4s 后仰：rotation ±8° squash（sprite 中心锚点）；吐息口 `(0,-6)` |
| 宝箱开启 | 48×48 单帧 | 无新帧 | 0.6s：scale y 1.0→1.25 弹跳 + `FX.glow` 金光（复用合成大闪参数） |

通用约定：**本批全部素材为单帧/双帧静态贴图，所有演出靠 scale/rotation/modulate 补间实现，不新增任何帧序列**——这是"零新增"结论在动画侧的落点。

### 6.2 给特效导演

| 特效 | 复用资产/函数 | 参数 |
| --- | --- | --- |
| 酸弹投射物 | `proj_orb.png`（64×64，显示 24px）+ modulate `#6AB04C` | 弹速 320、射程 520；命中 `FX.hit_spark`（绿色 tint） |
| 自爆冲击波 | `FX.explosion(pos, 130.0, 橙红)` | + `FX.shake(10.0)` + hitstop 0.04（受 A1 冷却窗口约束） |
| Boss 阶段转换 | `FX.glow_ring(500.0, 紫红 #8E44AD 系, 0.6, 6)` | + `FX.shake(14.0)` + hitstop 0.10 |
| 宝箱金光 | `FX.glow` | 复用 `player.gd` 合成大闪参数（glow 300 + ring 170 + shake 14） |
| 遗物拾取光柱 | `FX.glow` | tint 按稀有度 `#6FB7D6 / #A96FD9 / #F0C060` |

性能红线（对齐 01-design §9.4 + A9 池化）：弹幕同屏 ≤40、爆炸同屏 ≤12、同帧 `hit_spark/damage_number/glow` 各 ≤6 次；所有特效共用单例 ADD 材质（`fx.gd:297` 必改项），禁止逐特效 new 材质。

### 6.3 给主程序 / 技术架构（接线参数速查）

1. **敌人接线零场景改动**：`game_data.gd` ENEMIES 表加 3 条 + `enemy.gd` 加 `kind` 分支；贴图路径由既有模式 `res://assets/sprites/enemies/enemy_%s_idle_%02d.png` 自动命中。
2. **碰撞**：敌人 CircleShape2D r22（`enemy.tscn:18`）为默认，仅 gargoyle 建 r24（可在 ENEMIES 表加 `radius` 字段，`enemy.tscn` 不动）；Boss r70（`boss.gd:59`）；宝箱 Area2D r16。
3. **锚点**：敌人 AnimatedSprite2D 位于 `(0,-10)`、碰撞圆位于 `(0,16)`（`enemy.tscn:14-18`）——"脚底"≈ 局部 y+16，刷怪/楼梯对位以此为准；Boss Sprite2D 中心锚点、扬尘发射点 `(0,60)`（`boss.gd:44`）。
4. **Boss 换相**：`boss_mohei_phase2/3` 仅替换 `_sprite.texture`，不重建碰撞/不重定位。
5. **大厅背景**：`lobby.gd:82` 路径 `.png` → `.webp`；`divider_gold.png` 删除文件后无需改代码（本来就没人引用）。
6. **遗物 UI**：`hud.gd` `set_relics()` 按 rarity 覆盖 StyleBoxFlat border（色值 §2.3）；tooltip 着色在 `_show_detail` relic 分支加 2 行；`GameData.RELICS` 扩到 12 条时 icon 路径直接抄 §2.1 表。
7. **B4 扩容提醒**：SpriteFrames 共享从 4 份扩到 10 份（含 v0.9 预留的 3 种可以暂不建，只建 v0.8 接线的 3 份 → 共 7 份）。

### 6.4 新增资产最小清单（最终结论）

**v0.8：0 张新增。** 若 v0.9 接入 frost/spider/witchdoctor，同样 0 新增（贴图已就绪）。未来若需要"稀有度角标"贴图（当前 StyleBoxFlat 方案已够用），按此规格补：`top-down 2D game UI icon, small diamond gem, dark fantasy, flat color with bold dark outline, transparent background, no text, centered, single object`，24×24 输出、rembg 后 union bbox 裁剪——**本版本不排**。

---

*本清单全部体积/尺寸为 2026-10-02 对仓库 `baf32f5` 的逐文件实测；引用代码位置均可在仓库对应行号复核。*
