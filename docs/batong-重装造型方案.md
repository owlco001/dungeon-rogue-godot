# batong 重装造型 —— 提示词草案（待你确认，尚未生成）

> 状态：**未执行任何生成**。本文档是待批准的方案。
> 依据：`scripts/game_data.gd` 实际定位 + 实测现有素材缺陷 + `assets/STYLE_GUIDE.md` 调色板。

---

## 1. 问题确认（实测，非推测）

现有 batong 素材的**实际外观**（已导出预览核对）：

- 主体 366×305，宽高比 **0.83**（batong 与 mofei 完全相同，md5 一致）
- 视觉形象：**披风斗篷 + 弯刀 + 瘦削人形**，女性化轮廓
- 与 `game_data.gd` 定位「重装·肉盾 200速/170HP · 旋风斧」的**匹配度：低**
- 缺三项关键特征：**无重盾**（肉盾定位）、**体型不厚重**、**武器是弯刀不是斧**

**40px 缩略图级实测**（这是肉鸽里实际用来辨识的尺度）：

```
batong vs mofei  平均像素差 = 0.00    非零差异像素占比 = 0.0%
```

即缩略图下**两者完全无法区分**，而 aila 与他们的差异一眼可辨。
说明这不是「只有放大才看得出的细节问题」，**在实际游戏尺度上就已经是体验缺陷**。

> 缩略图必须**等比缩放**（高 40px 保持宽高比）。若直接压成 40×40 会被纵向拉伸，
> 反而掩盖差异 —— 这是评审缩略图时的常见错误（与 §9 图标管线的 40px 测试同理）。

而旋风斧实际是 `kind: "aoe", radius: 150` 的**范围旋风斩**——近身大范围重型打击。
现有弯刀造型无法传达「重」与「范围」。

---

## 2. 设计目标

| 项 | 要求 |
|---|---|
| 定位一致性 | 视觉必须能读出「重装·肉盾·旋风斧」 |
| 与 mofei 可区分 | 缩略图级（40px）即可分辨，无需对比 |
| 体型差异 | 明显更**宽厚**（宽高比目标 > 0.95，当前 0.83） |
| 核心识别物 | **铁甲重盾**（肉盾锚点）+ **双刃战斧**（武器锚点） |
| 去除 | 蝠翼、瘦削女性轮廓（那是 mofei 的特征） |
| 风格同族 | 沿用 STYLE_GUIDE §2 调色板，不跑偏 |

---

## 3. 造型设定

**巴顿 · 重装壁垒**

- **体型**：宽厚敦实，肩甲外扩，明显比现有版本更「横」
- **头部**：全包铁盔（无面部特征），区别于 mofei 的露脸
- **护甲**：厚重板甲，分层，金属 `#B0B8C0`，描边 `#0D0A12`
- **主识别物**：**左手巨型塔盾**（铁包边、木芯），正面朝向镜头时占显著面积
- **武器**：**双手双刃战斧**（不是弯刀），斧刃金属亮边
- **配色**：铁灰为主 + 暖金 `#F0C060` 描边点缀（玩家角色统一暖色系，见 STYLE_GUIDE §1）
- **禁止**：蝠翼、斗篷飘逸感、瘦削腰身、女性化曲线

---

## 4. 提示词草案

沿用 `gen_walk_video.py` 的硬性规则结构（锁定朝向、禁转身、固定相机、纯色背景）。
**风格描述逐字复用现有脚本**，仅替换角色特征段——避免风格漂移（STYLE_GUIDE §6）。

### 4.1 基准帧 prompt（txt2img，四方向各一张）

```
top-down 2D game sprite, single fantasy warrior character, front view,
keep front face toward camera all the time, plain uniform light grey background,
static empty backdrop, no scenery.

Character: a heavily armored male bulwark knight, stocky broad build,
wearing full iron plate armor with oversized pauldrons, a closed iron great helm
with no visible face, holding a massive rectangular tower shield strapped to his
left arm, the shield is large enough to cover most of his torso and clearly visible,
and gripping a heavy double-bladed battle axe in his right hand.

Appearance: thick layered iron plate, muted steel grey #B0B8C0 metal with
#0D0A12 dark outline, small warm gold #F0C060 trim accents on shield rim and
axe haft, dark brown leather straps. Broad shoulders, thick waist, planted stance.

Style: clean hand-painted game art style, flat color with bold dark outline,
dark fantasy dungeon, strong readable silhouette, no text, no watermark.

NOT a slender figure, NOT a cloak, NO bat wings, NO exposed face, NO curved sword,
NOT feminine body shape.
```

### 4.2 行走动画 prompt（视频，4 方向各一条）

以 `gen_walk_video.py:43` 的 `P["right"]` 为模板，**仅替换角色特征与武器约束**：

```
Character walking cycle, natural steady heavy walk gait, 1.5 complete walking
cycles, legs lift and step down slowly with weight, body subtle up and down
bounce with each heavy step, the large tower shield sways slightly with the
movement. The heavy double-bladed axe is ALWAYS held firmly in his right hand
and remains ONE single connected object, never separates from the hand, the axe
never floats in the air, the axe head always points outward from the body.

The massive tower shield stays strapped to the left arm and never detaches,
never rotates away from the body, shield face keeps the same angle to the body.

Character appearance stays consistent in every frame: same armor, same helmet,
same tower shield, same axe, same broad body proportion. No deformation, no
changing outfit, no feature drift between frames.

Only horizontal translation of character, character never turn around, never
change viewing angle.
```

**negative prompt** 在现有 `NEG` 基础上追加（针对本次造型的反项）：

```
slender body, feminine shape, cloak flowing, bat wings, demon wings, exposed face,
curved sword, rapier, thin blade, light armor, robe, hood, bare head,
shield detaching, shield disappearing, axe disappearing, weapon floating
```

---

## 5. 差异化验证方案（生成后必做）

| 判据 | 方法 | 通过标准 |
|---|---|---|
| 体型差异 | 量主体宽高比 | batong > 0.95 且 mofei 保持 0.83，差异 ≥ 15% |
| 缩略图可辨 | 40px 缩略图并排 | 肉眼看不出谁是谁 |
| 像素级不同 | md5 比对 | 与 mofei **无任何相同帧** |
| 四方向齐全 | `check_char_anim.gd` | 15 PASS / 0 FAIL |
| 朝向正确 | 人工目视四方向 | front/back/left/right 各朝向正确 |
| 风格同族 | `harmonize()` 后统计 | 饱和 0.185 / 明度 0.241 区间内 |
| 铁甲重盾可辨 | 正面帧目视 | 盾占主体显著面积，非装饰性小盾 |

---

## 6. 待你决策的点

1. **盾的形态**：矩形塔盾（更厚重、辨识度高）/ 圆盾（更经典）/ 无盾纯重甲
2. **斧的形态**：双刃战斧（双手、重装感强）/ 单刃巨斧（更凶悍）/ 战锤（最厚重但偏离「斧」）
3. **性别呈现**：明确男性厚重身板 / 中性不强调 / 维持现状
4. **配色**：铁灰 + 暖金（玩家暖色系）/ 铁灰 + 暗红（更接近敌方，**不推荐**）
5. **是否保留斗篷**：建议**去掉**（飘逸感与重装矛盾，也是与 mofei 混淆的主因）

> 确认后我按以下顺序执行：
> 1. 跑 `gen_base_views.py` 出四方向基准帧（1024×1024）
> 2. rembg 抠图 → `harmonize()` 归一
> 3. 逐方向目视核对朝向与特征
> 4. 出基准图给你确认后，再跑 `gen_walk_video.py` 生成行走视频
> 5. `video_to_sprite.py` 抽帧 → union bbox 归一 → 384px
> 6. 全量验证 + 人工资产审查