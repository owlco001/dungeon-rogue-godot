# 地牢肉鸽 · 美术风格指南（Agnes 管线定稿版）

> 2026-10-01 试点 + 全量 164 张资产沉淀。后续补任何资产（新角色/新怪/新图标）照此执行，风格不会跑偏。

## 1. 风格基准
- 视角：严格俯视（top-down），角色/敌人取约 3/4 俯角、头顶朝上，便于 4 方向辨识
- 画风：扁平色块 + 粗描边（2~3px 深色描边）的 2D 卡通暗黑奇幻；非像素、非写实 3D
- 可读性优先：轮廓清晰，远看能分辨敌我（玩家用暖色，敌人用冷色或危险红）

## 2. 固定调色板（所有资产共用）
| 用途 | 色值 |
|------|------|
| 描边/暗部 | `#0D0A12` |
| 背景（游戏内） | `#1A1420` |
| 暖金主光（玩家/拾取） | `#F0C060` |
| 血/危险 | `#C0392B` |
| 冰 | `#6FB7D6` |
| 毒 | `#6AB04C` |
| 亡灵紫 | `#8E44AD` |
| 金属 | `#B0B8C0` |

## 3. 禁忌（prompt 常驻）
无文字 / 无 UI / 无边框 / 无写实照片感 / 无复杂渐变 / 主体不搞半透明 / 背景透明（靠后处理实现，不靠 prompt）

## 4. Godot 技术规格

> ⚠️ **2026-10-03 校准**：本节原先写的分辨率（角色 128/杂兵 64/Boss 256/tile 48）
> 与命名（`down`/`up`）**已过时**，与当前代码实际不符。下表为实测值，以代码为准。

| 类别 | 实际尺寸 | 命名示例 |
|---|---|---|
| 角色 | **384×384** | `char_batong_front_walk_01.png` |
| 杂兵 | **384×384** | 7 种 × 4 帧 |
| Boss | **640×640** | 含双生 A/B、墨骸三阶段 |
| 特效 | **256×256** | 加法混合，**黑底不抠图** |
| 投射物 / 拾取物 | **256×256** | 投射物**只需朝右单帧**（代码按 `dir.angle()` 旋转） |
| tile | 见 `assets/tiles/*` | — |
| 图标 | 见 `assets/icons/{skills,relics}/` | 两个特例：`icon_relic_berserk`（狂暴战鼓）、`icon_skill_dash`（闪现） |

- 目录：`assets/sprites/characters/{aila,batong,mofei}/`、`sprites/enemies/`、`sprites/bosses/`、`sprites/fx/projectiles/`、`sprites/fx/`、`sprites/pickups/`、`tiles/{corridor,forge,ice,tomb,thorn,void}/`、`icons/{relics,skills}/`
- 格式：PNG（RGBA）透明底（tile 除外，全幅 RGB）
- **角色朝向素材侧是 `front`/`back`/`left`/`right`**，不存在 `down`/`up`
  —— `scripts/player.gd` 的 `_tex()` 做了 `down→front` / `up→back` 的引擎侧映射
- 角色动画：4 方向 ×（idle 1 帧 + walk 6 帧）

## 5. Agnes 调用规范

> ⚠️ **2026-10-03 校准**：原先写的工具路径 `~/workspace/skills/agnes/bin/agnes`
> 与 `~/workspace/.rbg-venv` 是旧机器的个人路径，已不存在。现行规范：

- 密钥：**`PAVO_API_KEY`** 环境变量（不是 `AGNES_API_KEY`——设错会抛 `MissingApiKey`）
- 模块：`agnes_client` 属于 **pavo-drama** 仓库，用 `tools/agnes_path.py` 定位
  （支持 `PAVO_ROOT` / `AGNES_CLIENT_DIR` / `PYTHONPATH` / 同级目录自动探测）
- 模型：`agnes-image-2.1-flash`
- **抠图（rembg）**：需装在专用 venv，`new_session("u2net")`，**单进程串行**，并行必OOM
- 返回 429/5xx → 指数退避重试；校验文件 >0 字节才算完成
- `generate_image` 返回 `{"data":[{"url":...}], "created":..., "task_id":...}`
  —— 图片 URL 在 **`data[0].url`**，不是顶层
- 单资产 prompt 模板：`top-down 2D game sprite, <主体>, dark fantasy dungeon, flat color with bold dark outline, <调色板约束>, no text, clean silhouette` + 方向/动作/阶段限定
  - ⚠️ `transparent background` **写在 prompt 里不可信**（实测换来白底/棋盘格/场景底），透明靠 rembg 后处理
- tile 必加：`NO grid lines, NOT a tileset atlas`（否则必出成网格 atlas，已验证）
- 图标模板：`game UI icon, <主体>, dark fantasy, flat color with bold dark outline, no text, centered, single object`（**必须做 40px 等比缩略图测试**）

## 6. 管线铁律（血泪版，违反必返工）
1. **四方向/多帧一律 img2img 转**，不独立文生图（会变人）；右方向 = PIL 镜像左方向
2. **"transparent background" prompt 不可信**（实测只换来纯白/棋盘格/场景底），全部走 rembg：`new_session("u2net")` 需装在专用 venv（`VENV_PY` 指向它），**单进程串行**，并行必 OOM
3. 同一动作多帧用 **union bbox 统一裁剪**后再缩到目标尺寸，否则缩放/配准抖动
4. 每帧人工目视朝向（模型有方向偏置，如"朝右"画成朝左）；tile 全查 atlas 问题；图标/特效拼蒙太奇批量查
5. 模型自带脚下椭圆阴影，抠图会保留——游戏里可直接当阴影用；不想要需在 prompt 明确禁止
6. 后处理脚本：`tools/postprocess_assets.py`、`tools/video_to_sprite.py`（抠图阶段用 venv python）

## 7. 省量规则
- 超武弹道/特效 = 基础版变色放大，不单独生成
- `summon_skeleton`（骷髅大军单体）复用 `enemy_skeleton`，不单独生成
- 经验宝石三档靠颜色 + 尺寸双区分（蓝小/紫中/金大）
