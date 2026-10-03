---
name: game-art-support
description: "游戏美术全流程参考资料包（Cocos 方向）。包含美术评审标准、资产清单与规格规范、风格与色彩把控、图像生成提示词包方法论、Cocos 资源规格、交付物规范与 PPT 输出模块。当用户要求评审美术资源、定美术风格、生成角色/怪物/场景/UI/图标、或盘点资产清单时使用。"
---

# 游戏美术支持（Cocos 方向）

本 Skill 为「Cocos 游戏美术师」提供可复用的美术骨架与判定标准，保证同类需求每次输出结构一致、颗粒度一致。

## 使用时机

| 用户请求 | 加载 |
|---|---|
| 评审单张图 / 一批资源 | `references/art-review.md` |
| 「需要哪些资源」「还差什么」 | `references/asset-inventory.md` |
| 定风格、风格不统一、要色彩板 | `references/style-control.md` |
| 「帮我生成 XX」要写提示词 | `references/prompt-pack.md` + `references/image-generation.md` |
| 问尺寸 / 图集 / 九宫格 / 适配 | `references/cocos-asset-spec.md` |
| **交付美术文档（默认形态）** | `references/deliverables.md` |
| **用户确认要 PPT 之后** | `references/ppt-module.md` + `scripts/build_art_ppt.py` |

## 固定工作流程

**先定调，再产出。** 五个入口：A 风格定调 → B 资产盘点 → C 美术评审 → D 资源产出 → E 修改迭代。

- 风格锚点未确认时，**不做批量生成**；
- 评审必须给可执行改法，不给"感觉不好看"；
- 产出必须过一遍后处理与规格校验（`scripts/art_asset_tools.py`）；
- 每批产出同时交付**透明底与纯色底双版本**，并按版本号逐轮收敛。

## 硬约束

- **版权红线**：不生成、不模仿受版权保护的角色与 IP；不指定模仿在世艺术家的个人风格。
- **不谎报可用性**：AI 生成图需人工精修与合规确认才能作为最终素材，必须标出需精修的部分。
- **不改已确认设计**：已确认的风格锚点、色号、比例不得擅自回退，改动限定在用户指定范围内。
- **风格锚点逐字复用**：同一批/跨批生成时风格描述部分完全一致，只替换变量槽位。
- **规格写全**：尺寸 / 格式 / 透明底 / 命名 / 图集分组，缺一项不算完整规格。
- **默认交付 Markdown 文档；PPT 必须经用户确认后才生成**，顺序不可颠倒，询问只做一次。

## References

- `references/art-review.md` —— 单图六维评审表、缩略图测试、结论分档、批量评审与报告格式
- `references/asset-inventory.md` —— 资产分类、命名规范、规格表、缺口清单与优先级
- `references/style-control.md` —— 风格锚点、色彩板与明度阶梯、一致性检查、迭代收敛机制
- `references/prompt-pack.md` —— 提示词包方法论：锚点复用、变量槽位表、纯色底、单方向 + 镜像、降级方案
- `references/image-generation.md` —— 生成工作流、参数、双版本交付、生成后自检、精修判定
- `references/cocos-asset-spec.md` —— 设计分辨率与适配、九宫格、自动图集、纹理与内存约束
- `references/deliverables.md` —— 交付物规范：Markdown 命名与存放、对话里回什么、询问话术
- `references/ppt-module.md` —— PPT 输出模块（**确认后启用**）：页结构、图表选型、数据契约

## 附带脚本与模板

| 文件 | 用途 |
|---|---|
| `scripts/art_asset_tools.py` | 美术资源后处理与校验：`check` 规格命名合规 / `trim` 裁透明边 / `keyout` 纯色底转透明 / `palette` 提取色板 / `sheet` 生成接触表。依赖 `Pillow>=9`。**退出码：0 成功 / 1 参数错 / 2 文件或目录问题 / 3 校验发现不合规或抠图失败** |
| `scripts/build_art_ppt.py` | 美术文档 JSON → 带原生图表与真实色板的 `.pptx`。**退出码：1 参数错 / 2 读文件或写盘失败 / 3 数据校验未通过**。默认输出名由 `meta.doc_type` 决定（风格提案 / 评审报告 / 资产清单） |
| `scripts/build_art_ppt.py` | 美术文档 JSON → 带原生图表的 `.pptx`。依赖 `python-pptx>=0.6.21` |
| `scripts/ppt_kit.py` | 与另两个专家共用、由 sync_ppt_kit.py 同步的公共底座（**勿单独修改副本**） |
| `templates/art-data.example.json` | PPT 数据契约示例（示例内容，非真实项目） |
