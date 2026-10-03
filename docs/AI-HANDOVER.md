# AI 交接说明（新对话必读）

> 最后更新：2026-10-03
> 用途：新开对话时，把本文件完整交给 AI，或让AI 先读本文件再干活。
> 本文件是**唯一权威的当前状态来源**，代码与提交历史可能比本文件更新。

---

## 0. 一句话现状

`dungeon-rogue-godot`（Godot 4.7.2，GitHub `owlco001` / Gitee `owlco001`）的**素材补齐工作已完成**：
278 张 PNG 全部落盘、全项目零缺失、引擎零导入错误。**唯一已知遗留问题见 §5。**

---

## 1. 项目 basics

| 项 | 值 |
|---|---|
| 引擎 | Godot **4.7.2.stable**（`4.7.2.stable.official.ed1daf0bf`） |
| 视口 | 1920×1080 |
| 远端 | `https://gitee.com/owlco001/dungeon-rogue-godot.git`（origin） |
| 提交数 | 63（仓库总提交；最近 12 个为素材批次，见 §10） |
| 类型 | 俯视角 roguelike（类 Vampire Survivors） |
| 角色 | 艾拉(aila) 游侠/弓 / 巴顿(batong) 重装肉盾 / 墨菲(mofei) 术士爆发 |

**三角色定位**（`scripts/game_data.gd`）：

| id | 名称 | 定位 | 武器 | 速度 | HP |
|---|---|---|---|---|---|
| `aila` | 艾拉 | 游侠·均衡 | bow | 230 | 100 |
| `batong` | 巴顿 | 重装·肉盾 | whirlwind | 200 | 170 |
| `mofei` | 墨菲 | 术士·爆发 | orb | 215 | 90 |

---

## 2. 素材总账（278 张，零缺失）

| 类别 | 数量 | 目录 | 生成脚本 |
|---|---|---|---|
| 角色 aila | 106 | `assets/sprites/characters/aila/` | `tools/gen_walk_video.py`（视频抽帧） |
| 角色 batong | 28 | `assets/sprites/characters/batong/` | 同上 |
| 角色 mofei | 28 | `assets/sprites/characters/mofei/` | 同上 |
| 杂兵 | 28 | `assets/sprites/enemies/` | `tools/gen_enemies.py` |
| Boss | 9 | `assets/sprites/bosses/` | `tools/gen_bosses.py` |
| 技能特效 | 9 | `assets/sprites/fx/` | `tools/gen_fx.py` |
| 投射物 | 5 | `assets/sprites/fx/projectiles/` | `tools/gen_proj_pickups.py` |
| 拾取物 | 6 | `assets/sprites/pickups/` | `tools/gen_proj_pickups.py` |
| 瓦片 | 38 | `assets/tiles/*`（7 子目录） | `tools/gen_tiles.py` |
| 图标 | 19 | `assets/icons/{skills,relics}/` | `tools/gen_icons.py` |
| 大厅 | 2 | `assets/art/lobby/` | — |

**零缺失验证命令**（新对话先跑这条确认状态）：
```bash
grep -rhoE 'res://assets/[a-zA-Z0-9_/]+\.png' scripts/ | sort -u \
  | while read p; do [ -f "${p#res://}" ] || echo "MISSING $p"; done
# 无输出 = 零缺失
```

---

## 3. 素材命名铁律（踩过坑，务必遵守）

### 3.1 角色朝向：素材侧是 `front`/`back`

`scripts/player.gd` 的 `_tex()` 做了引擎侧→素材侧的映射：

```gdscript
# player.gd:108
if dirn == "down":  d = "front"
elif dirn == "up":  d = "back"
```

所以**素材目录里只应存在 `front`/`back`/`left`/`right`**，不存在 `down`/`up`。

> 历史坑：曾出现 `player.gd` 要 `front`/`back`、`hud.gd` 要 `down_idle_00` 两套约定，
> 导致 batong/mofei 角色**完全不渲染**。已在 `75ad902` 统一为 `front`/`back`。

命名格式：
```
assets/sprites/characters/<cid>/char_<cid>_<front|back|left|right>_<idle|walk>_<NN>.png
```

### 3.2 投射物只需一个朝向

`scripts/projectile.gd` 每帧 `sprite.rotation = dir.angle()`，**方向由代码旋转**。
只需生成朝右单帧，生成双方向是纯浪费。

### 3.3 三档宝石是三张独立贴图

`gem_s` / `gem_m` / `gem_l` 必须是**同一张图程序化缩放**得到的（长宽比偏差 <2%），
不是分别生成的三张。

### 3.4 图标命名两个特例

```
wardrum  → icon_relic_berserk.png   （狂暴战鼓）
blink→ icon_skill_dash.png     （闪现）
```
其余严格对齐 `scripts/game_data.gd` 的 key。

---

## 4. 四条独立素材管线（不要混用）

不同素材的**技术要求完全相反**，混用必错。

| 管线 | 适用 | 关键要求 |
|---|---|---|
| **A 视频抽帧** | 角色行走 | 抽帧→ 尺寸 384 |
| **B txt2img+抠图** | 杂兵 / Boss | 白底或黑底生图 → rembg 抠图 → `harmonize()` 归一 |
| **C剪影极简** | 图标 | 粗描边、扁平化；**必须做 40px 缩略图测试** |
| **D 加法混合** | 技能特效 | **黑底不抠图**、必须中性灰、必须稀疏亮线 |

### 4.1管线 B 的核心：`harmonize()`

定义在 `tools/gen_enemies.py`，被杂兵/图标/Boss **全部复用**。作用是把素材归一到角色实测的
饱和/明度区间（饱和 0.185/ 明度 0.241），这是"风格同族"的保障。

它做 5 件事：
1. 饱和归一
2. 明度归一（**统计必须在 `alpha > 60` 掩膜内做**，否则透明区拉低均值导致系数错一半）
3. 高光压缩（`HIGHLIGHT_CAP`）
4. 环境光统一（`AMBIENT` 暖褐 + `AMBIENT_MIX=0.30` 注入暗部）
5. 边缘再压一档饱和

> 洞察：纯色怪物在暗灰墙上"跳"出来的根源是**没落在同一光线环境**，不只是饱和度太高。

配套 `decontaminate()`：剥离黑底抠图残留的暗描边脏边。
**只作用于「紧贴透明外沿 2px 内」的暗像素**，深处暗部不受影响。

### 4.2 管线 D 的核心：加法混合特效

`scripts/fx.gd` 用 `CanvasItemMaterial.BLEND_MODE_ADD`，混合公式：

```
out = bg + src × mod.rgb × mod.a        （系数 1.0，无额外倍率）
```

三个反直觉要求：

1. **黑底不抠图** —— 黑区在加法下= 透明，抠图会破坏柔光衰减，只剩硬边轮廓
2. **必须中性白/灰** —— 代码用 `modulate` 染色，素材带色会变脏（三通道必须完全相等）
3. **必须稀疏亮线而非实心块** —— 加法是逐像素叠加，**亮区只要在空间上连续成片就必然饱和**，与总量无关

**峰值上限公式**（`tools/gen_fx.py` 的 `peak_cap()`）：

```python
cap = (1.0 - BG_LUM) / (max(mod) * mod.a)     # BG_LUM = 0.27（实测地板明度）
```

归一到 1.0 会让最亮通道必然截顶（`shield_slam` 实测撞到 **1.22**），染色被吃掉。
按公式归到 0.77~0.97，最亮通道刚好饱和、其余通道保留色差。

---

## 5.⚠️ 唯一已知遗留问题

**batong 与 mofei 的素材是同一份的副本（像素级 100% 相同）。**

实测：`np.abs(a-b).mean() == 0.00`，`完全相同比例 = 100.0%`。

但 `game_data.gd` 里两者定位截然不同：

| 角色 | 定位 | 武器 | 速度/HP |
|---|---|---|---|
| 巴顿 batong | **重装·肉盾** | 旋风斧 | 200 / **170 HP** |
| 墨菲 mofei | **术士·爆发** | 魔法法球 | 215 / **90 HP** |

现在两个角色都穿同一套黑甲蝠翼，**玩家选谁视觉上没区别** —— 这在肉鸽里是实打实的体验损失。

**建议修法**：按 `game_data.gd` 定位给 batong 单独做一套重装造型（铁甲重盾、宽厚体型、无蝠翼）。
**尚未执行**，等决策。

---

## 6. 验证脚本（每批交付前必须跑）

### 6.0 前提：先导入资源（新沙箱必做）

`.godot/imported/` 不在 git 里，新 clone 后是空的。**不先导入就跑验证会得到假红**：

```bash
godot --headless --path . --import    # 约 1~2 分钟，产出 572 个 .ctex，零错误
```

跳过时的假象：`check_char_anim` 报 `3 PASS / 12 FAIL` + `Unable to open file: res://.godot/imported/...ctex`，
并连带刷 `Parse Error: Identifier "Meta"/"Lang" not declared`（`sfx.gd`）——
**这两个 `class_name` 都在，只是全局类缓存尚未建立，导入后自行消失**。
真实基线永远是 `15 PASS / 0 FAIL`。详见 `docs/ENV-SETUP.md` §5.0。

### 6.1 纯逻辑校验（headless，快）

```bash
godot --headless --path . --script res://test/check_char_anim.gd   # 角色四方向  "15 PASS / 0 FAIL"
godot --headless --path . --script res://test/check_fx.gd          # 特效综合    "63 PASS / 0 FAIL"
godot --headless --path . --script res://test/check_enemy_anim.gd  # 杂兵动画     "ENEMY ANIM RESULT: PASS"（9 项，格式与上面两个不同）
godot --headless --path . --script res://test/check_corridor.gd
python3 tools/check_audio.py                                        # 音频 23 条
```

> 注意：`check_enemy_anim.gd` 的结果行格式与 `check_*.gd` 不同，
> 它的 PASS 逐条打印，最后一行是 `ENEMY ANIM RESULT: PASS`。
> grep 时用`ENEMY ANIM RESULT` 而不是 `=== 结果`。

### 6.2 实机截图验收（xvfb + opengl3）

```bash
xvfb-run -a godot --rendering-driver opengl3 --audio-driver Dummy \
  --path . --script res://test/capture_fx.gd
```

相关：`capture_fx.gd`（特效染色）、`capture_chars.gd`（角色渲染）、
`capture_enemies.gd`、`capture_bosses.gd`、`capture_proj_pickups.gd`、
`verify_idle_breath.gd`（idle 呼吸可见性，含反向验证，4 PASS）

---

## 7. 三个必须知道的验证陷阱

### 陷阱 1：GDScript 图像分析必须用 `get_data()`

```gdscript
var d := img.get_data()   # ✅ 批量读
img.get_pixel(x, y)       # ❌ 640×640 逐点调 41 万次会卡死超时
```

**后果**：结果被跳过 → 断言变成**假通过**。`capture_bosses.gd` 曾因此报出「明度递增 0.001」的假通过。

### 陷阱 2：像素统计会假通过，必须看图

`capture_chars.gd` 曾用「绝对亮度 > 200/255」判角色是否渲染，报出 `96686 像素 OK`，
但截图上 batong/mofei **明明是空白**（透明区也能过亮度阈值）。

**正解**：与**地板基线**做差，统计偏离量。
```gdscript
var base := 0.0  # 先采样角色框外地板横带求基线
if absf(l - base) > 0.10: cnt += 1   # 偏离基线才算角色像素
```

### 陷阱 3：验证判据要考虑「与亮度耦合」的度量

染色度量**必须用相对色差** `(max-min)/max`，不能用绝对色差 `(max-min)`：

| 判据 | shield_slam 实测 | 结论 |
|---|---|---|
| 绝对色差 `<0.06` 判纯白 | 报 46% 纯白 | ❌ 误报 |
| **相对色差** | 0% | ✅ 正确 |

原因：素材暗部（亮度 0.15~0.21）加法混合后只有 0.39，
此时通道差在 8bit 下只剩几个色阶，绝对差必然很小，但人眼仍看得出颜色。

同理，加法混合下**最亮处必然撞顶变白，这是物理正确的**，染色体现在衰减区。
不能用「峰值像素是否有色相」做判据。

### 陷阱 4：`SceneTree` 脚本在 `_init` 里 `await` 会让整段断言静默跳过

```gdscript
func _init() -> void:
    _run()# ❌ 里面有 await 时，后续判定全部不执行
```

**后果**：脚本打印 `=== 结果：0 PASS / 0 FAIL ===` 却**退出码为 0**——
看起来「没有失败」，实际是**一条断言都没跑**。这与陷阱 1 同源，都是「结果被跳过 → 假通过」。

**正解**：沿用 `test/capture_chars.gd` 的既有范式——
```gdscript
func _init() -> void:
    pass# 入口是下面这个
func _initialize() -> void:
    _run.call_deferred()
func _wait(secs: float) -> void:          # 帧等待
    var s := Time.get_ticks_msec()
    while Time.get_ticks_msec() - s < int(secs * 1000.0):
        await process_frame
```

**判据：结果行是 `0 PASS / 0 FAIL` 就当失败处理**，绝不放过。

### 陷阱 5：验证脚本必须做反向验证（证明判据不恒真）

写pixel-diff 类判据时，光看「测到了变化」不够——**全屏闪烁也能测到变化**。
必须加一组**对照组**：把被测变量置为中性值（幅度=0、颜色不变），
断言此时测得差异**恰为 0**。否则判据可能对任何输入都返回 PASS。

参考 `test/verify_idle_breath.gd` 第 4 条判定：
```
[PASS] 反向验证：幅度0时测得无变化  对照组帧间差异=0.0 像素（必须为 0）
```

---

## 8. 环境依赖（脱敏后）

生成脚本已脱敏，路径可配置：

```bash
export DUNGEON_ROOT=/path/to/dungeon-rogue-godot   # 默认用脚本自定位
export AGNES_BIN=/path/to/agnes# 默认读 PATH 里的 agnes
export PAVO_API_KEY=...                           # 由 agnes_client 读取
export DUNGEON_ROOT=/path/to/dungeon-rogue-godot   # 默认用脚本自定位
export PAVO_ROOT=/path/to/pavo                    # 定位 agnes_client（见 ENV-SETUP §3）
export AGNES_BIN=/path/to/agnes# 默认读 PATH 里的 agnes
```

> 密钥变量名是 **`PAVO_API_KEY`**（不是 `AGNES_API_KEY`，后者无效）。
> 2026-10-03 实测：设错会报 `MissingApiKey: PAVO_API_KEY environment variable is not set`。
```

生图依赖 `agnes_client` 模块 + 模型 `agnes-image-2.1-flash`。

> ⚠️ **`9235572` 的脱敏漏掉了 `tools/*.py`**（13 处硬编码仓库绝对路径、
> 7 处 `sys.path.insert(0, "/workspace/pavo/...")`、3 处 `Path.home()/"workspace"`）。
> 它们此前只是「巧合可用」。现已统一改为 `tools/agnes_path.py` 解析
> （`PAVO_ROOT` / `AGNES_CLIENT_DIR` / `PYTHONPATH` / 同级目录自动探测，四种方式）。
> **新写生成脚本一律用它，不要再硬编码任何绝对路径。**
> 自检：`grep -rn 'Path\.home()\|/workspace/dungeon-rogue-godot' tools/*.py` 应无输出。

> 仓库内已无任何个人绝对路径或凭据。`docs/v08/02-architecture-v08.md:151`
> 提到的 `/home/hatch/...` 是**历史分析文档里对旧问题的记录**，故意保留。

---

## 9. 所用技能与专家（已打包进仓）

```
.workbuddy/experts/cocos-game-artist/     # 游戏美术师专家包（156K）
├── agents/cocos-game-artist.md
├── skills/game-art-support/
│   ├── SKILL.md
│   ├── references/    # 8 篇：风格控制/提示词包/评审/规格/交付/PPT 等
│   └── scripts/
│       ├── art_asset_tools.py    # 后处理：check/trim/keyout/palette/sheet
│       ├── build_art_ppt.py
│       └── ppt_kit.py
├── .codebuddy-plugin/plugin.json
└── README.md / settings.json
```

**`art_asset_tools.py` 是素材后处理标准工具**，五个子命令：

```bash
python3 .workbuddy/experts/cocos-game-artist/skills/game-art-support/scripts/art_asset_tools.py \
  check  <dir>     # 规格与命名合规校验 + 产出清单
  trim   <dir>     # 批量裁掉透明边
  keyout <img>     # 纯色底 → 透明底
  palette <img># 提取主色板（用于风格锚点）
  sheet  <dir>     # 生成接触表（缩略图测试）
```

---

## 10. 素材批次提交历史（最近 12 个，按时间倒序）

> 仓库共 **63** 个提交，这里只列与素材管线相关的最近 12 个；更早的是玩法/系统迭代。

```
75ad902 fix(chars): 统一角色素材命名为 front/back 约定，修复角色不渲染
78093b4 test: 角色四方向动画验证，暴露 front/back 命名约定冲突
f1508a2 fix(fx): 按 modulate 反算峰值上限 + 实机验证脚本
ef06837 feat(fx): 技能特效 9 张（加法混合管线）
86f2289 feat(bosses): Boss 立绘 9 张（6 Boss + 双生A/B + 墨骸三阶段）
7152473 feat(icons): 技能图标 7 张 + 遗物图标 12 张，零缺失
a5f3deb feat(fx): 投射物 5 张 + 拾取物 6 张，消除运行时 ERROR
6b62a2d feat(enemies): 杂兵素材 7 种 x4 帧 = 28 张，补齐游戏可玩性缺口
c43c061 feat(tiles): 补齐地图瓦片 44 张，场景恢复正常渲染
e503ddd feat(aila): 四方向行走动画改用视频抽帧管线生成
69831ac chore: 清空旧像素素材并升级视口至 1920x1080
```

---

## 11. 建议的下一步（按优先级）

1. **修 batong 素材重复**（§5）—— 唯一已知遗留问题，影响选角体验
2. ~~**补 idle 动画**~~ —— **2026-10-03 实测证伪，暂不需要做**
   原文写「无呼吸/待机动势」，但 `player.gd:261-264` **已有代码层呼吸**：
   ```gdscript
   _breathe_t += delta
   var b := 1.0 + 0.02 * sin(_breathe_t * 2.6)      # ±2%，周期 2.42s
   visual.scale = visual.scale.lerp(Vector2(2.0 - b, b), ...)
   ```
   实机验证（`test/verify_idle_breath.gd`，xvfb + opengl3）：**4 PASS / 0 FAIL**，
   最大帧间差异 33032 像素、变化占比 10.75%，即呼吸**肉眼可见且集中在角色区域**。
   幅度≈14.5px / 角色高 363px = 4.0%，落在可感知区间。
   >素材层 idle 确实仍是 walk_00 副本（已确认），但代码用 scale 缩放补足了动势，
   > **再加 idle 素材帧会造成「双重呼吸」反而更假**。若要重做，应是二选一，不是叠加。
3. **音效设计裁决** —— `superfuse` 已定义但未被调用（实测确认是 23 条里唯一未被引用的）；
   设计文档 `docs/v08/04-animation-v08.md:212`
   要求它应在 **T+120ms（hitstop解除帧）** 起播，代码在 T+500ms 播的是 `superburst`。
   文档标注这是"全方案最重要的一处音画同步修正"。**属音频设计裁决，未擅自改。**
4. **瓦片补齐** —— 现有 38 张，实际可能需要更多地形变体

---

## 12. 给新对话 AI 的行为约定

沿用本轮工作方式，不要偏离：

1. **先读代码再定规格** —— 每批素材生成前先 grep/read 确认路径、尺寸、scale、命名、混合模式。
   本轮所有隐藏约束（投射物旋转、三档宝石独立贴图、图标命名特例、Boss 三阶段切换、朝向映射）
   都是这样发现的。
2. **不猜尺寸** —— 严格按代码实际规格。
3. **每批必跑实机验证** —— 只跑公式验证会漏（本轮特效染色问题公式侧全过、实机才暴露）。
4. **数值异常时先怀疑判据** —— 本轮多次「素材有问题」的结论最后发现是判据写错了。
5. **每阶段提交 git 存档点** —— commit message 写清**为什么**，不只写做了什么。
6. **区分「已确认」与「待定」** —— 不擅自改已确认设计（如音频时间轴属设计裁决）。
7. **破坏性操作前先确认意图。**
8. **报错先分清「环境问题」与「代码问题」** —— 新沙箱首跑必先 `--import`（§6.0）。
   假红长这样：`Unable to open file: res://.godot/imported/...`、
   `Identifier "Meta"/"Lang" not declared`。
   **先排环境、再怀疑代码**，别把导入缺失误判成素材缺失去"修"素材。
   判据：真实基线 `check_char_anim 15 PASS / check_fx 63 PASS / check_enemy_anim PASS`，
   对不上就是环境没配好，不是代码坏了。
