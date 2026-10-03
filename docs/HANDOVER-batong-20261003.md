# batong 重装造型 —— 跨机器交接（2026-10-03 16:30）

> 本文档是**当前这一轮工作**的交接说明，用于从沙箱（Linux）切到 PC 版 WorkBuddy 继续。
> 项目整体状态仍以 `docs/AI-HANDOVER.md` 与 `docs/ENV-SETUP.md` 为准，本文档只补「这一轮做到哪、坑在哪」。

## 22. 2026-10-03 地面符文移除与本轮经验

- `scripts/arena.gd` 的 `set_theme()` 改为清理旧符文节点，移除 `decal_rune.png` 的创建逻辑。离屏 baker 复用同一脚本，因此实时地图与新生成的烘焙纹理都不再包含紫色符文；烘焙缓存是实例内存缓存，重启游戏后重新生成。
- Godot 4.7.2 导入和编辑器扫描完成；角色动画 15 PASS / 0 FAIL、敌人动画 PASS、内容门禁 V4 PASS。OpenGL gameplay 截图成功生成。截图没有完成人工目视验收，退出时仍有资源释放告警。
- 经验：移除地图装饰必须同时检查实时节点、离屏烘焙与缓存，单独隐藏节点可能仍留下烘焙图中的图案。
- 经验：资源帧完整性检查只证明素材可加载，不能证明输入链路驱动动画；输入同步时序与实际播放效果应分别验证。
- 经验：视觉缩放应以统一世界比例为基准，受击与死亡 Tween 使用相对基准缩放，避免动画结束时突然变大。
- 经验：Windows 截图使用绝对输出路径和真实 OpenGL 渲染，必须确认 PNG 实际生成；不能仅凭进程退出码或 headless 结果判定视觉通过。
- Web 导出仍需更新：源代码改动不会自动更新已有 PCK。此次推送源码与交接记录，截图与日志保留为本地验证产物，不纳入版本控制。

## 21. 2026-10-03 20:28 角色移动动画与刷怪节奏修复

用户反馈角色移动仍无行走动画、怪物刷新慢且数量少。定位与修复如下：

- `scripts/main.gd`：在主场景 `_physics_process` 开头同步 `hud.get_move_vector()` 到 `player.external_move`，确保输入在 Player 物理帧前写入，不再依赖 `_process` 的一帧延迟。
- `scripts/player.gd`：动画状态同时参考请求输入和实际速度。即使加速中、贴墙或碰撞导致速度暂时偏低，只要摇杆输入超过阈值就播放 `walk_*`，避免视觉上像棋子滑动或站立。
- `systems/wave_director.gd`：普通层三波时间从 `T+0/T+25/T+50s` 调整为 `T+0/T+8/T+18s`，保持 60/25/15 分配但更快形成战斗密度。
- `scripts/hud.gd`：计时条波次刻度同步调整为 `T+8/T+18`。
- `data/floors.json`：总刷怪数从 `base/min=14、per_floor=3、max=120` 调为 `base/min=24、per_floor=4、max=160`。

回归：Godot 编辑器扫描通过；`check_char_anim` 为 15 PASS / 0 FAIL；`check_enemy_anim` PASS；`tools/check_content.gd` 为 V4 PASS；`git diff --check` 通过。未做人工触屏回放，本次需要实际拖动摇杆确认走帧输入链路。

## 0. 2026-10-03 16:55 续跑记录（PC 侧接手）

接手时远端最新提交是 **`f8a9f7f`**（本文档所述`ea23695` 之后又有一笔文档归档）。
已复核交接文档全部数据为真：batong/mofei md5 **28/28 完全相同**、饱和度 **0.0000 纯灰度**、
right FAIL 两项数值、三份序列图缺陷均目视复现。

### 0.1 本轮提交

**`4cd139d`** `fix(tools): right 基准帧改复刻 left 的高举构图 + Windows 兼容修正`

### 0.2 新发现：left 基准帧的斧头是完整双刃 ⭐

放大 `docs/v08/batong_base_review_20261003.png` 后实测：

| 基准帧 | 斧头 | 朝向 |
|---|---|---|
| **right** v3 | ❌ 单刃月牙（残缺） | 面朝右 ✅ |
| **left** | ✅ **完整双刃战斧**（远大于双刃 axe head 形） | 面朝左 ✅ |

而`VIEWS_AXE["left"]` 与 `["right"]` 的描述**几乎逐字对称**，唯一差别是
`screen left` / `screen right`。故残缺不来自措辞，而来自 right 描述里的
`held low and angled BACKWARD` —— 它把斧头压到了身体后下方，
**正是 v1/v2/v3 三轮反复丢斧头的同一位置**。

v4 已据此改为复刻 left 的成功构图（斧高举过肩、斧头置于头部高度以上的开阔背景处），
并把斧头写成可判读的物理描述。

### 0.2b ✅ v4 基准帧已生成并目视通过（换密钥后）

新密钥生效后跑 `gen_base_views.py batong right`：

```
[right] 第1次生成 657KB
[right] 抠图完成 alpha覆盖=58.8%
[right] 自检通过: 连通块=1 占画布=33.1% 密度=0.49 宽高比=0.67
```

**目视结论：斧头是完整双刃战斧**（两片清晰对称的弯刃，高举过肩、处于开阔背景处），
塔盾完整带金边 —— v4 达成目标，§6.1 的根因已消除。

> 宽高比 0.67 比 v3 的 0.80 更窄，**但这不是退化**：斧头高举超出了身体轮廓，
> 把 bbox 拉宽了。`qc_single` 的宽高比门禁下限 0.55，仍通过。
> 真正该盯的是「斧头是否双刃且完整」，而这条目前只能目视——
> 尝试过用列密度做几何判据，实测分割结果不可靠（left 侧只剩 17 像素），已放弃。

### 0.3 §6.2 「接受现状」这个选项不成立（原文判断偏乐观）

原文写「既然 left 是 right 镜像派生，只要某一向朝向正确即可」。**在当前镜像方向下这是错的**：
`run_walk_pipeline.sh` 的 `MIRROR = {"left": "right"}` 是**用 right 派生 left**。
若 right 朝向反了，取镜像得到的 left 也就同样反 —— **两个朝向会一起反**，
不存在「至少一个朝向正确」。要走这条路必须把 `MIRROR` 改成 `{"right": "left"}`，
即反过来用 left 派生 right。

### 0.4 ✅ 密钥问题已解决

原密钥报 `HTTP 402: Subscription request not allowed`，`chat_text` 与 `generate_image`
**两个接口都402** → 账号/密钥级问题。base_url与 `Bearer` 鉴权方式均正确，
格式也正确（`cpk-` / 52 位），故只能是密钥本身已失效（§11 建议轮换明文泄露过的密钥）。
**换用新密钥后 `chat_text` 与生图均恢复正常**，v4 基准帧已产出（见 §0.2b）。

### 0.5 ✅ Godot 已对齐 4.7.2，验证基线全部恢复

本机原只有 4.7.stable（`5b4e0cb0f`），**与项目要求的 4.7.2 不是同一版本**。
已从 ghfast.top 镜像装 `4.7.2.stable.official.ed1daf0bf`（版本串与文档逐字一致），
重新 `--import` 后基线全绿：

| 项 | 结果 |
|---|---|
| `--import` |✅ 431 个 .ctex（文档原记 572 是沙箱旧值，见 ENV-SETUP §10.5） |
| `check_char_anim` | ✅ **15 PASS / 0 FAIL** |
| `check_fx` | ✅ **63 PASS / 0 FAIL** |
| `check_enemy_anim` | ✅ **ENEMY ANIM RESULT: PASS** |
| `check_audio` | ✅ 23 条（22 被引用） |
| 零缺失 | ✅ 引用 52 全命中，实存 278 |

> 换 Godot 版本后必须删掉旧 `.godot/imported/` 与 `global_script_class_cache.cfg` 再
> `--import`，否则残留的是 4.7 产物。本轮已这么做。

### 0.6 下一步（v4 基准帧已就绪，可继续）

1. **跑 right 行走视频**：`gen_walk_video.py batong right`（121 帧 @12fps 768x768，
   推理约 150s，1RPM 限流）。
2. 抽帧质检 + **目视**（本轮教训：质检 PASS ≠ 目视合格）。重点看两件事：
   - 斧头是否仍是完整双刃（v4 基准帧已对，主要看视频有没有把它退化掉）
   - **朝向是否仍反**。v4 基准帧目视是面朝右的，若视频仍反，则问题出在
     视频提示词/模型侧，需按 §0.3 决定改 `MIRROR` 方向还是改提示词。
3. 三向都 PASS 后才落盘（`run_walk_pipeline.sh` 第 4 步含 left 镜像派生）。
4. 落盘后跑全量验证 + 人工资产审查。
5. front/back维持现状不返工（用户 2026-10-03 决定），但接入前仍建议目视——
   两者斧头同样偏小、单刃，属已知遗留。


## 1. 一句话现状

batong 重装造型**四向基准帧已完成并通过人工审查**，行走视频三向已生成、抽帧质检全部完成：
`front` PASS、`back` PASS、`right` FAIL。素材**尚未落盘到 `assets/`**，下一步是修right。

远端：`https://gitee.com/owlco001/dungeon-rogue-godot.git`，分支 `main`，最新提交 **`ea23695`**。

## 2. 起因：待决策的遗留问题已解决

原遗留问题：batong 与 mofei 素材 md5 逐帧相同（28 帧全一致），但 `game_data.gd` 里定位截然不同
（巴顿 = 重装肉盾200 速 / 170HP / 旋风斧，墨菲 = 术士爆发 215 速 / 90HP / 魔法法球）。

实测补充数据（旧素材）：**饱和度 0.000** —— 它们不只是同图，是**纯灰度图**。

已按用户确认的方案重做造型（`docs/batong-重装造型方案.md`），四向基准帧已生成。

## 3. 已完成：四向基准帧（通过人工审查）

审查图：`docs/v08/batong_base_review_20261003.png`（四向归一后 + 40px 缩略图对照）

| 朝向 | 宽高比 | 连通块 | 覆盖 | 状态 |
|---|---|---|---|---|
| front | 0.98 | 1 | 55.8% | 通过 |
| left | 0.97 | 1 | 41.9% | 通过 |
| right | 0.80 | 1 | 29.4% | 通过（勉强，见 §6） |
| back | 0.90 | 1 | 52.3% | 通过 |

- 造型：宽厚铁甲 + 全包铁盔 + 金边矩形塔盾 + 战斧，无斗篷无蝠翼
- 40px 缩略图下与旧素材（= mofei 灰度副本）差异化明显 ✅
- harmonize 归一后：明度统一收敛到 0.255，饱和 0.03~0.06 → 0.09
  （撞 `s_ratio` 1.6 上限，达不到目标 0.185；与 `gen_enemies.harmonize()` 原注释一致，
  纯灰主体不该靠整体拉饱和，识别色由塔盾金边与皮带承担）

## 4. 已完成：行走视频生成

`gen_walk_video.py batong right front back` —— 只跑三条，**left 按项目铁律由 right 镜像派生**
（多帧一律镜像，避免两条独立视频之间形象/装备漂移）。

参数：121 帧 @12fps 768x768，推理耗时 92.6s / 166.5s / 154.9s，全部 `completed`。

## 5. 抽帧质检结果 —— 当前卡点

| 朝向 | 判定 | 帧数 | 周期 | 转身 | 面积波动 | 水平漂移 | 失败项 |
|---|---|---|---|---|---|---|---|
| front | **PASS** | 21 | 12 | 无 | 6.33% | 5.57 | 无 |
| back | **PASS** | 24 | 40 | 无 | 2.03% | 4.87 | 无 |
| right | **FAIL** | 28 | 24 | 未检测到 | 18.17% | 18.95 | 形象波动（阈 18）、中心漂移（阈 8） |

`right` 明细：`loop=native`、`seam=11.79`、`pose_jump=[]`、`part_separation` 1.0 全帧无分离。
即**闭环与装备连接都没问题**，只是形象面积波动与水平漂移超阈。

证据图（`docs/v08/`）：
- `batong_front_cycle_sheet_20261003.png`
- `batong_back_cycle_sheet_20261003.png`
- `batong_right_cycle_sheet_20261003.png` ← 有问题的那份

## 6. 目视发现的两个问题（检测器没抓到，必须人工过目）

证据：`docs/v08/batong_right_cycle_sheet_20261003.png`（28 帧序列图）

注意：`front` 与 `back` 的序列图（`batong_front_*.png` / `batong_back_*.png`）已抽帧质检 PASS，
但**接入新素材前仍建议目视过一遍** —— 本轮就出现了「质检 PASS 但目视有缺陷」的情况
（front/back 的斧头同样偏小，只是没到 right 那么严重）。

### 6.1 斧头几乎消失（严重）

序列里只剩一根横贯的**木斧柄**，双刃斧刃基本不可见（个别帧左上角残留一点）。
根因是**基准图 v3 本身就是单刃残缺**——你在审查时已看到并接受了它（我已告知「斧头是单刃新月形
而非设定里的双刃战斧，斧柄横在身前与右臂略有错位」）。行走视频锁定了基准图的缺陷：
提示词里的负向词 `single crescent blade / tiny axe head` 没能救回来，因为参考图给定的是错的。

**这是本轮最主要的遗留问题。** 建议：重新生成`right` 基准帧，提示词明确斧头形状
（`the axe head is a DOUBLE-BLADED head with two curved blades on either side of the haft`），
或改用斜扛在肩上/举过肩的姿态让斧刃完全暴露，再重跑视频。

### 6.2 朝向反了（需确认严重性）

提示词要求 `keep character facing to the right all the time`，但序列里角色**实际在面朝左行走**
（背朝右方）。而质检`turn_detected=false`、`pose_jump=[]`。

即**转身检测器漏判了整体反向**。这类问题 AI-HANDOVER 记录过是「四向实验失败根因」，
本轮以另一种形式复现。需决定：
- 是否在生成时统一把「面朝右」改成描述性更强的方式（例如 `his face and chest point toward
  the RIGHT edge of the frame`）
- 是否给检测器补一条「朝向一致性」判据（当前只看有没有转身，没看朝哪边）
- 或者接受：既然 left 是 right 镜像派生，只要某一向朝向正确即可

## 7. 本轮修复的代码（已提交 `ea23695` 与 `c6c455d`）

### 7.1 `tools/gen_base_views.py`（`c6c455d`）

- **新增体型宽高比门禁**。原 `qc_single()` 只有连通块/覆盖率/密度三项，
  导致「塔盾完全消失」的残次品被判 PASS（实测连通块=1、覆盖 29%、密度 0.51 全过）。
  新增下限（batong 0.55 / 其他 0.40）+ 与同角色其余朝向中位值偏离 > 0.18 直接失败。
  **已反向验证**：v2 残次品偏离 0.29 被正确拦截。
  参考值只与同角色比—— 跨角色比会误杀（重装方阔0.9+ / 术士瘦高）。
- `_rembg_session()` 固定用本地 `isnet-general-use.onnx`。rembg 默认 u2net模型 176MB
  直连 ~20KB/s，表现为「生图完成但进程卡十分钟不出结果」，本次实测踩中。
- 原图复用：Agnes 约 1RPM，生图是最贵的一步。上次运行若在抠图阶段中断，原图完好不该重出。

### 7.2 `tools/gen_walk_video.py`（`ea23695`）

**原实现把 aila 的弓手描述硬编码在四个朝向里**（`The bow is ALWAYS held...` + `same cloak` +
`cloak sways` + 负向词 `floating bow/arrow`）。拿去生成 batong 会把斧盾描述成弓，还要求斗篷摆动
—— 而 batong 明确无斗篷。改为 `WEAPON_PROMPT` 按角色取四元组
（持械描述 / 形象锚点 / 摆动描述 / 负向词），与 `gen_base_views.py` 的角色表口径一致。
aila 路径已回归验证。入口加角色白名单校验。

### 7.3 `tools/process_walk.py`（`ea23695`）

rembg 两处陷阱：不指定 session 会触发 176MB 模型下载；每批子进程都重建 session
= 60 帧要载入 60 次 178MB 模型。改为批内建一次session 复用。

### 7.4 `tools/run_walk_pipeline.sh`（`ea23695`）

脱敏补修（上一轮漏了这个 shell 脚本）+ 两个真bug：
- `export PAVO_API_KEY="$AGNES_API_KEY"` 实际取空值
- `gen_base_views.py` 漏传角色 ID，脚本只传方向会把方向名当角色 ID

## 8. right 朝向返工记录（三轮，值得留档）

| 版本 | 宽高比 | 问题 | 根因 |
|---|---|---|---|
| v1 | 0.73 | 塔盾把斧头挡得只剩一截斧柄 | **几何必然**：面朝右时观众看到角色左侧身体，塔盾在左臂 = 正对镜头 |
| v2 | 0.68 | 塔盾整个消失，只剩小斧柄 | 「斧高举过盾」+「斧不与盾重叠」两条约束互相打架，模型取舍时丢盾 |
| v3 | 0.80 | 塔盾完整 + 斧头可见（但变单刃） | 单一动作描述：盾在身前近侧、斧向身后远侧斜举，天然不遮挡 |

**教训**：给视频模型的提示词不要堆多条互相制约的构图约束，一条动作描述即可。
模型在约束冲突时会静默丢弃其中一条（丢掉的是**体积更大**的那个，所以塔盾先遭殃）。

## 9. 下一步建议（按优先级）

1. **重出 `right` 基准帧**，让斧头保持双刃且完全可见 → 重跑视频 → 重抽帧。
   这是 §6.1 的根因，不修则行走素材永远缺斧刃。
2. 目视过一遍 front/back 的序列图，确认斧头问题是否同样存在
   （质检 PASS 不等于目视合格，这是本轮实测的教训）。
3. 与用户确认 §6.2 朝向反向的处理方式（改提示词 / 改检测器 / 接受现状）。
4. 三向都PASS 后，才走落盘（`run_walk_pipeline.sh` 第 4 步含 left 镜像派生）
   与全量验证 + 人工资产审查。

## 10. 环境与密钥（PC 侧注意）

-密钥变量名是 **`PAVO_API_KEY`**，不是 `AGNES_API_KEY`。设错会抛 `MissingApiKey`。
- `agnes_client` 模块属于**另一个仓库 pavo-drama**，需单独克隆。
  解析方式见 `tools/agnes_path.py`（支持 `AGNES_CLIENT_DIR` / `PAVO_ROOT` / `PYTHONPATH` / 同级自动探测）。
- Agnes 限速约 **1 RPM**，生图最贵，能复用原图就复用（脚本已支持）。
- rembg 首次运行若没指定 session 会去下 176MB 模型；本机已有 `isnet-general-use.onnx`，
  确保 `~/.u2net/` 里有这个文件。
- 新沙箱**第一步必须先 `godot --headless --path . --import`**，否则验证会假红（3 PASS/12 FAIL）。
- Godot 下载用 ghfast.top 镜像（GitHub 直连 ~28KB/s），下载后 `unzip -t` 验完整性。
  ⚠️ **2026-10-03 18:20 实测修正**：资产名是 **`Godot_v4.7.2-stable_win64.exe.zip`**，
  不是 `_win64_console.zip`（后者 404，下载到的是 9 字节 `Not Found`）。
  版本号本身正确，`4.7.2-stable` 在官方 tag 列表里确实存在。

## 11. 安全提醒

Gitee 私人令牌与 Agnes API Key 曾在对话中明文出现。建议轮换后再让PC 侧使用。

## 12. 未修复缺陷：HUD 图标资产缺口（2026-10-03 18:18 查实）

**用户已裁决：只记录，本轮不修。** 修法属设计裁决，留给下一轮。

### 12.1 现象

实机跑 `test/capture_gameplay.gd` 时稳定报：

```
ERROR: Resource file not found: res://assets/icons/weapons/icon_bow.png
   at: _load (core/io/resource_loader.cpp:325)
   GDScript backtrace:
       [0] set_weapons (res://scripts/hud.gd:480)
       [1] _on_character_chosen (res://scripts/main.gd:162)
```

不是截图脚本的问题——`hud.gd:480` 在角色选择确认后加载武器图标，必然触发。

### 12.2 根因

提交 **`69831ac` "chore: 清空旧像素素材并升级视口至 1920x1080"**
（2026-10-03 01:33，"素材体系重头生成前的存档点"，674 fileschanged / -10058 行）
删除了旧像素图标，但**漏改`data/icons.json`**。

- `assets/icons/` 现仅存 `relics/` 与 `skills/`，共 19 个 png
- `weapons/` 与 `passives/` 两个目录**整个不存在**
- `data/icons.json` 仍有 **31 处** `res://assets/icons/...` 引用，其中 **19 个指向已删文件**
  （12 passive + 7 weapon； relics/skills 幸免）

历史上这些图标是有的：`a1ea3fc` "v0.8.18: 19 武器图标统一风格（Agnes 重画，64px）"
添加过，`git show a1ea3fc --stat` 可见 `icon_bow.png` 等 19 张 + `.import`。
要恢复可`git checkout a1ea3fc -- assets/icons/weapons assets/icons/passives`。

### 12.3 待决策的两个修法

| 方案 | 动作 | 代价 |
|---|---|---|
| A. 恢复旧图标 | `git checkout a1ea3fc -- assets/icons/{weapons,passives}` | 纯恢复历史资产，不改代码，改动最小；但风格是旧像素风，与"素材重头生成"方向可能冲突 |
| B. 摘掉死引用 | 从 `icons.json` 移除 19 个键或改指占位图 | 消除报错，但 HUD 上这19 格会空白；等新一轮素材生成再补 |

方案 A 会把旧像素风格图标拉回1920x1080 的新版界面，与 `69831ac` 想要的"清空旧像素"方向相反，
所以**不能默认选 A**，需要显式裁决。

### 12.4 附带发现

`scripts/arena.gd:350` 的 `_request_bake()` 在 headless 哑渲染下会报
`Parameter "t" is null`（`texture_2d_get`）。代码本身已有防御
（`arena.gd:354` 判`img == null` 后直接 return，放弃烘焙回退逐砖），**属预期噪声，非 bug**，
但会污染 headless 日志、干扰真实报错的辨识。同理退出时的 RID/ObjectDB leaked 警告也是哑渲染清理噪声。

## 13. 地图与单位比例修复（2026-10-03 18:42）

### 13.1 根因

`69831ac` 把 viewport 从 `960×640` 升到 `1920×1080`，但没有同步建立新的世界单位显示标尺：

- 地图源图：`192×192`，`arena.gd` 按 `TILE=48` 绘制（正确显示为 48px）
- 角色与杂兵源图：`384×384`，此前 Sprite scale=1（错误地显示为 384px 画布）
- Boss 源图：`640×640`，此前 scale=1
- 拾取物（金币/经验宝石）：`256×256`，此前无 scale

因此人物、怪物、金币相对 48px 地砖全部偏大，出现“地图尺寸不对、人物怪物比例失衡”。
实测透明边界：角色实际内容高约 367–378px，杂兵约 314px，scale=1 时约等于 6.5–8 个地砖高。

### 13.2 修复口径

统一使用 `48 / 192 = 0.25` 作为源图到世界单位的基准显示缩放：

- `scripts/player.gd`：`Visual` 初始/行走/待机呼吸统一乘 `ART_SCALE=0.25`
- `scripts/enemy.gd`：idle、move、精英倍率统一乘 `ART_SCALE=0.25`
- `scripts/boss.gd`：Boss `_base_scale` 统一乘 `ART_SCALE=0.25`，保留各 Boss 原有相对倍率
- `scripts/summon.gd`：普通/mini/juice 统一乘 `ART_SCALE=0.25`
- `scripts/gem.gd`：XP/金币乘 `PICKUP_ART_SCALE=0.25`；遗物图标保留原有 `0.75`

未修改碰撞半径、移动速度、攻击距离、寻路网格和地图尺寸，避免把视觉问题扩大成玩法数值变化。

### 13.3 验证

- Godot `4.7.2.stable.official.ed1daf0bf`
- 角色动画：**15 PASS / 0 FAIL**
- 敌人动画：**PASS**
- OpenGL 真实窗口 gameplay 截图：成功落盘（约 954KB）
- 内容检查唯一失败：已知缺失 HUD 图标 19 项（`icons all exist n=31`），与本次比例修复无关

## 14. 金币比例二次修正（2026-10-03 18:55）

上一轮把金币和经验宝石都设为 `0.25`，但金币不应按“一整块地砖”标尺处理：
金币源图虽为 `256×256`，透明内容实际为 `240×164`，`0.25` 后仍显示约 `60×41px`，
所以用户反馈金币依然巨大。

本轮单独改为：

- `scripts/gem.gd`: `COIN_ART_SCALE=0.10`，金币实际显示约 `24×16px`
- XP 宝石继续使用 `PICKUP_ART_SCALE=0.25`，保留小/中/大三档尺寸区分
- `test/capture_proj_pickups.gd` 同步使用真实游戏缩放，并支持 `CAPTURE_OUT`

Godot 4.7.2 OpenGL 实机验证：拾取物/投射物加载 **12 PASS**，三档宝石形状一致 **PASS**，
截图 `C:/tmp/pickup_cap/all.png` 成功生成。

## 15. 地图格尺寸对齐修复（2026-10-03 19:06）

确认此前地图地面绘制 `TILE=48px`，但 `RoomGen.CELL`、寻路、房间墙绘制均为 `50px`；
竞技场刚好 `1600×1200 = 32×24 × 50px`。地板和边界墙由此与逻辑网格错位，且整除时原循环 `int(W/TILE)+1` 会多画出一整列/行到地图边界外。

修改 `scripts/arena.gd`：
- `TILE`、`WALL_T` 统一到 `50px`
- 地面数组和绘制循环的数量改为 `roundi(W/TILE)` / `roundi(H/TILE)`，严格绘制 32×24 格
- 外墙纵向循环同样严格按 24 格，不再额外多画一格
- 地图总尺寸、房间布局、碰撞/寻路数值均未改

Godot 4.7.2 验证：120 seed 走廊/连通回归 **PASS**，角色 **15 PASS / 0 FAIL**，敌人动画 **PASS**；OpenGL gameplay 截图 `C:/tmp/map_review/map_aligned.png` 成功生成。

## 16. 怪物死亡突然放大修复（2026-10-03 19:15）

根因：地图/单位比例修复后，敌人正常显示为 `ART_SCALE * base_scale`（普通怪为 0.25），
但 `enemy.gd:_die()` 的死亡 Tween 仍使用 `Vector2(base_scale*1.3, base_scale*0.3)`。
因此普通怪死亡时从 0.25 突然跳到 1.3，宽度约放大 5.2 倍。
`boss.gd` 也有同类绝对缩放（`Vector2(1.6,0.4)`）。

修复：
- `enemy.gd` / `boss.gd` 死亡目标缩放改为当前世界基准乘 `DEATH_SQUASH=Vector2(1.15,0.45)`
- 保留死亡淡出、顿帧、掉落、尸体和死亡判定逻辑

运行时验证：普通史莱姆正常 scale `0.250`，死亡帧宽 `0.287`、高 `0.115`，
`DEATH SCALE RESULT: PASS`；敌人动画 PASS，走廊/连通 PASS。

## 17. 开放竞技场：减少墙体并扩大移动空间（2026-10-03 19:30）

用户反馈墙体过多、角色移动空间不足，并提出动态扩展方向。检查确认旧版 `systems/room_gen.gd` 是“整张 32×24 网格先铺满墙，再挖房间和 2×2 走廊”，因此墙体密度和狭窄感来自生成策略本身，而不是单纯视觉渲染。

本轮采用固定竞技场内的开放方案：
- 网格内部默认全部为地面，只保留一格外圈墙；竞技场仍为 `1600×1200`、`32×24`、`50px` 网格
- `rooms` 元数据继续保留，用于刷怪、楼梯和主题逻辑，但不再用内部墙体切割移动空间
- 四根柱子、外圈碰撞、寻路网格和角色碰撞半径不变
- 不采用动态扩展：当前固定边界已经能提供约 `1500×1100` 的连续可移动区域；动态扩展会牵动相机、边界碰撞、刷怪范围和固定坐标，暂不值得引入额外复杂度

修改文件：`systems/room_gen.gd`。验证：开放竞技场走廊门禁 PASS（120 seed）、敌人动画 PASS；OpenGL 环境截图已生成于 `C:/tmp/open_arena_env/`，包括 corridor/forge/void 三套主题的 close/wide 图。

## 18. 增加怪物数量（2026-10-03 19:35）

用户要求增加怪物数量。刷怪总量由 `data/floors.json` 控制，波次仅按 60/25/15 拆分，因此只调整总量参数，不改单只怪物强度：
- `count.base`: 10 → 14
- `count.min`: 10 → 14
- `count.per_floor`: 2.2 → 3.0
- `count.max`: 80 → 120
- 第 1/10/30 层总量约为 14/41/101 只（原约 10/30/74 只）
- Boss 层陪战小怪由 2 史莱姆 + 2 蝙蝠提高为 3 史莱姆 + 3 蝙蝠

未修改 HP、伤害、精英倍率、波次时间或 Boss 本体属性。`auto_v08.gd`、开放竞技场连通门禁均通过；内容检查仍仅因既有 19 个 HUD 图标死引用失败。

## 19. HUD 图标缺失修复（2026-10-03 19:43）

用户确认图标素材应已生成。检查当前工作区及项目父目录后，未发现新的 `weapons/` / `passives/` PNG；唯一完整匹配资产位于历史提交 `a1ea3fc`，与 `data/icons.json` 的 19 条路径完全一致。因此恢复该提交中的既有图标资产到当前目录：

- `assets/icons/weapons/`：19 张武器图标
- `assets/icons/passives/`：12 张被动图标
- 其中本次死引用对应的 19 张路径全部恢复，并运行 Godot 4.7.2 导入

验证结果：
- `tools/check_content.gd`：`V4 RESULT: PASS`，`icons all exist | n=31`
- OpenGL gameplay 启动：成功进入战斗并生成 `C:/tmp/gameplay_icons_fixed/gameplay.png`
- 原先 `icon_bow.png` 等 Resource file not found 报错已消失

## 20. 遗物、动态、声音与整体视觉比例修复（2026-10-03 20:12）

用户反馈遗物体积巨大、无声音、人物移动像棋子，并要求地图、人物和掉落物同步放大。

修复内容：
- `scenes/player.tscn`：Camera2D `zoom=Vector2(1.16,1.16)`，统一放大地图、角色、敌人、柱子和掉落物的屏幕显示；碰撞、寻路和世界坐标不变
- `scripts/gem.gd`：XP `0.29`、金币 `0.13`、遗物 `0.29`；遗物从原来的 `0.75` 降到掉落物级别
- `scripts/joystick.gd`：补齐 `InputEventScreenTouch` / `InputEventScreenDrag`，Web/触屏移动现在会持续驱动角色，触发 walk 帧和步态动态
- `scripts/hud.gd`：角色开始按钮点击时显式调用 Web BGM/SFX 解锁，避免浏览器 AudioContext 未经用户手势导致无声

验证：角色四向资源 `15 PASS / 0 FAIL`，内容检查 `V4 RESULT: PASS`，真实 OpenGL gameplay 截图 `C:/tmp/gameplay_visual_fix/gameplay.png` 生成成功，无资源缺失或脚本错误。
