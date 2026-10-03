# 新沙箱环境配置清单

> 生成于：2026-10-03
> 用途：新沙箱跑素材生成/验证脚本前，按本清单配置环境。
> ⚠️ **本文件不含任何密钥明文** —— 密钥需你自己填入（沙箱内不存在你的密钥，我无法代为导出）。

---

## 1. 必须配置的（不配就跑不了生图脚本）

| 变量 | 值 | 来源 |
|---|---|---|
| `PAVO_API_KEY` | `cpk-...` | https://agnes-ai.com 开发者控制台 |
| `DUNGEON_ROOT` | `/workspace/dungeon-rogue-godot` | 本仓库根目录（也可省略，脚本会自定位） |
| `AGNES_BIN` | 路径或留空 | Agnes CLI；留空则回退到 `PATH` 里的 `agnes` |

一键配置：
```bash
export PAVO_API_KEY="cpk-你的Agnes密钥"
export DUNGEON_ROOT="/workspace/dungeon-rogue-godot"
export AGNES_BIN=""            # 留空=用 PATH 里的 agnes
```

> ⚠️ 密钥变量名是 **`PAVO_API_KEY`**，不是 `AGNES_API_KEY`（后者无效）。
> 2026-10-03 实测：设错会报 `MissingApiKey: PAVO_API_KEY environment variable is not set`。
> 值以 `cpk-` 开头（早期文档写的 `sk-` 已过时）。

> **pavo-drama 仓库可直接从 Gitee 克隆**（2026-10-03 确认，无需本地已有）：
> ```bash
> git clone https://gitee.com/owlco001/pavo.git          # → /workspace/pavo
> ```
> 克隆到仓库同级目录后**零配置即可用**（`tools/agnes_path.py` 会自动探测）。

新增（仅生图脚本需要，解析 `agnes_client` 位置）：

| 变量 | 用途 |
|---|---|
| `PAVO_ROOT` | pavo-drama 仓库根，自动找 `$PAVO_ROOT/skill/pavo-drama/scripts` |
| `AGNES_CLIENT_DIR` | 直接指定 `agnes_client.py` 所在目录（优先级最高） |
| `STAGE_DIR` | 生图中间文件暂存目录，默认 `/tmp/artwork/stage` |
| `GODOT_BIN` | `export_web.py` 用的 godot 可执行文件，默认取 `PATH` |
| `VENV_PY` | 抠图用的 python（需装 rembg），默认当前解释器 |

> 解析逻辑统一在 `tools/agnes_path.py`，全部脚本共用。
> 自检：`python3 tools/agnes_path.py`
> 也支持**零配置自动探测**——把 pavo 克隆成仓库同级目录（`<repo>/../pavo`）即可直接跑。

## 2. 可选（只有涉及 LLM 脚本才需要）

| 变量 | 用途 |
|---|---|
| `DEEPSEEK_API_KEY` | `vid_prompt_test.py` 等用LLM 的脚本；不配则跳过该功能 |

---

## 3. ⚠️ 关键：代码依赖了**另一个仓库**的模块

`tools/gen_*.py` 里的 `import agnes_client` **不在本仓库内**。

| 项 | 值 |
|---|---|
| 实际位置 | `/workspace/pavo/skill/pavo-drama/scripts/agnes_client.py` |
| 所属项目 | `pavo-drama`（AI 短剧生成 pipeline） |
| 服务域名 | `https://apihub.agnes-ai.com/v1`（硬编码在agnes_client.py 里，不可配） |
| 图像模型 | `agnes-image-2.1-flash` |

**新沙箱必须同时具备 pavo-drama 仓库**，否则所有生图脚本会报
找不到 `agnes_client` 的错误（现已带修复指引，不再是裸ModuleNotFoundError）。

四种解决方式（任选，解析逻辑统一在 `tools/agnes_path.py`）：
```bash
# 方式 1：设PAVO_ROOT —— 脚本自动找 $PAVO_ROOT/skill/pavo-drama/scripts（推荐）
git clone <pavo-drama 仓库> /workspace/pavo
export PAVO_ROOT=/workspace/pavo

# 方式 2：直接指定 agnes_client.py 所在目录（优先级最高）
export AGNES_CLIENT_DIR=/path/to/pavo/skill/pavo-drama/scripts

# 方式 3：PYTHONPATH
export PYTHONPATH="/workspace/pavo/skill/pavo-drama/scripts:$PYTHONPATH"

# 方式 4：零配置 —— 把 pavo 克隆成仓库同级目录，脚本会自己找到
git clone <pavo-drama 仓库> "$(dirname "$PWD")/pavo"
```

确认解析结果：
```bash
python3 tools/agnes_path.py       # agnes_client 一行应显示实际路径
```

> 建议方式 1 或 4 —— 保持模块单一来源，避免两处副本各自漂移。
> 方式 4 无需任何环境变量，适合快速验证。

---

## 4. 运行时依赖

| 依赖 | 版本/要求 | 用途 |
|---|---|---|
| Python | 3.11 | 所有生成脚本 |
| `pillow` (PIL) | 必装 | 抠图、归一、后处理 |
| `numpy` | 必装 | `harmonize()` / `peak_cap()` 等全部色彩计算 |
| `rembg` | 建议 | 杂兵/Boss 抠图（不用则无法重生成该批） |
| `godot` | **4.7.2.stable** | 所有验证脚本与实机截图 |
| `xvfb` | 建议 | `xvfb-run` 用于无头截图 |
| `requests` | 必装 | `agnes_client` 调 API |

安装：
```bash
pip3 install pillow numpy requests rembg
# Godot 4.7.2 + xvfb 需按各自渠道安装
```

### 4.1 Godot 下载源（实测踩坑）

GitHub Releases 直连**极慢**（实测 ~28 KB/s，78MB 需要 45 分钟且常下不完整）。
换镜像源，15 秒完成：

```bash
curl -L -o godot.zip \
  "https://ghfast.top/https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip"
unzip -t godot.zip          # 必须先验完整性，中断的包没有尾部目录会误判
unzip -oq godot.zip && mv Godot_v4.7.2-stable_linux.x86_64 /usr/local/bin/godot
chmod +x /usr/local/bin/godot
godot --version             # 期望：4.7.2.stable.official.ed1daf0bf
```

> 下到一半中断的 zip 用 `unzip -t` 会报 `cannot find zipfile directory`，
> 表现为「文件有几十 MB 但解不开」—— 换源重下，别试续传。
> 版本串 `4.7.2.stable.official.ed1daf0bf` 与本项目记录的完全一致，可作为装对了的判据。

---

## 5. 不需要凭据的部分（克隆即用）

以下**零外部依赖**，新沙箱拉下仓库立刻能跑：

### 5.0 ⚠️ 第一步必须先导入资源（否则验证假红）

`.godot/imported/` 是引擎导入产物，**未纳入 git**，新 clone 的仓库必然是空的。
不先导入就跑验证脚本，会得到与代码质量无关的假失败：

```bash
godot --headless --path . --import    # 约 1~2 分钟，产出 572 个 .ctex，零错误
```

跳过这步的症状（**假 FAIL，别据此改代码**）：

```
ERROR: Unable to open file: res://.godot/imported/char_aila_....ctex
[FAIL] aila/left idle_00  -> aila_left  缺失
=== 结果：3 PASS / 12 FAIL ===          # 真实基线是 15 PASS / 0 FAIL
```

同批还会连带刷一屏看起来很吓人的报错，**同样是假的**：

```
SCRIPT ERROR: Parse Error: Identifier "Meta" not declared in the current scope.   at: sfx.gd:76
SCRIPT ERROR: Parse Error: Identifier "Lang" not declared in the current scope.   at: sfx.gd:138
ERROR: Failed to instantiate an autoload, script 'res://scripts/sfx.gd' does not inherit from 'Node'.
```

> `Meta` / `Lang` 的 `class_name` 都在（`scripts/meta.gd`、`scripts/lang.gd`），
> 缺失的只是**首次运行时还没建立全局类缓存**。`--import` 完成后 Parse Error 自行消失，
> 验证立刻回到基线。**遇到这两个报错，先检查有没有执行过 `--import`，而不是去改代码。**

### 5.1 校验命令

```bash
# 全部素材缺失检查
grep -rhoE 'res://assets/[a-zA-Z0-9_/]+\.png' scripts/ | sort -u \
  | while read p; do [ -f "${p#res://}" ] || echo "MISSING $p"; done

# 逻辑校验（只需 Godot）
godot --headless --path . --script res://test/check_char_anim.gd   # 15 PASS / 0 FAIL
godot --headless --path . --script res://test/check_fx.gd          # 63 PASS / 0 FAIL
godot --headless --path . --script res://test/check_enemy_anim.gd  # ENEMY ANIM RESULT: PASS
python3 tools/check_audio.py                                        # 音频 23 条

# 素材后处理（只需 pillow/numpy）
python3 .workbuddy/experts/cocos-game-artist/skills/game-art-support/scripts/art_asset_tools.py \
  check assets/sprites/fx
```

**即：验证与评审不需要任何密钥，只有「重新生成素材」才需要。**

---

## 6. 仓库里已脱敏的部分（无需你处理）

`9235572` 把 `.gd` /配置里的个人绝对路径改掉了：

| 原值 | 现值 |
|---|---|
| `/home/hatch/workspace/games/dungeon-rogue-godot` | `Path(__file__).resolve().parent.parent`（脚本自定位） |
| `/home/hatch/workspace/skills/agnes/bin/agnes` | `os.environ.get("AGNES_BIN", "agnes")` |
| `test/capture_v0*.gd` 的绝对输出路径 | `user://shot_v0*` |

### 6.1 `tools/` 下的遗漏与补修

`9235572` **漏掉了 `tools/*.py`**：13 处硬编码 `/workspace/dungeon-rogue-godot`、
7 处 `sys.path.insert(0, "/workspace/pavo/skill/pavo-drama/scripts")`、
3 处 `Path.home()/"workspace"/...`。
它们「能跑」只是因为 ENV-SETUP §3 恰好建议把 pavo 克隆到那个绝对路径 —— **巧合可用，不是真脱敏**。

现已补修：

| 原值 | 现值 |
|---|---|
| `sys.path.insert(0, "/workspace/pavo/...")` | `from agnes_path import require_agnes_client`（见 §1/§3） |
| `Path("/workspace/dungeon-rogue-godot/assets/...")` | `ROOT / "assets/..."`（`DUNGEON_ROOT` 或自定位） |
| `Path.home()/"workspace"/".rbg-venv"/"bin"/"python"` | `os.environ.get("VENV_PY", sys.executable)` |
| `Path.home()/"workspace/.tools/godot/..."` | `os.environ.get("GODOT_BIN", shutil.which("godot"))` |
| `subprocess.run(["/root/.rbg-venv/bin/python", ...])` | `subprocess.run([sys.executable, ...])` |

自检：
```bash
grep -rn 'Path\.home()\|/workspace/dungeon-rogue-godot\|/home/hatch' tools/*.py   # 应无输出
python3 tools/agnes_path.py# 看解析结果
```

> 顺带修掉一个坑：`process_walk.py` 的 `ROOT = /tmp/walkgen`是**抽帧暂存目录**、
> `PROJ` 才是仓库根，两者同名易混，补修时勿合并。

---

## 7. Git 凭据（推送时用，沙箱内没有）

沙箱**没有** Gitee 凭据，`git push` 需你本机执行：

```bash
cd /workspace/dungeon-rogue-godot
git push -u origin main
```

Gitee 已停用密码认证，需用**私人令牌**：
「设置 → 私人令牌」生成，勾选 `projects` 权限即可。

> 注：`gh` CLI 已安装但未登录 GitHub；本项目远端是 Gitee，不需要 gh。

---

## 8. 一句话总结

**新沙箱开箱即用**（素材齐全、验证可跑），**只有重新生成素材时**才需配
`PAVO_API_KEY` + pavo-drama 仓库（后者从 Gitee 克隆即可，`tools/agnes_path.py` 会自动探测）。
Gitee 推送需私人令牌。

---

## 9. 2026-10-03 实测记录（沙箱全链路打通）

| 环节 | 结果 |
|---|---|
| Godot 4.7.2 装载 | ✅ `4.7.2.stable.official.ed1daf0bf`，与本文档记录逐字一致 |
| 素材零缺失 | ✅ 引用 52 条全命中，实存 278 张 |
| 验证基线 | ✅ check_char_anim 15 PASS / check_fx 63 PASS / check_enemy_anim PASS |
| check_audio | ✅ 23 条（22 条被引用，未引用的即 `superfuse`，属设计裁决待办） |
| check_font | ✅ OK（1187 字形 / 485 玩家可见字符） |
| `agnes_path` 零配置探测 | ✅ pavo克隆到同级目录后自动找到 `agnes_client.py` |
| 9 个生成脚本导入链路 | ✅ 全部绑定真实模块（含经 `gen_enemies` 复用的 4 个） |
| Agnes 密钥连通性 | ✅ `chat_text` 正常返回；`generate_image` 成功出图并可下载 |

**密钥变量名：`PAVO_API_KEY`**（值以 `cpk-` 开头）。设成 `AGNES_API_KEY` 无效。

> 踩坑记录：`generate_image` 返回结构是
> `{"data":[{"url":...}], "created":..., "task_id":...}` —— 图片 URL 在 **`data[0].url`**，
> 不是顶层 `url`。另外 `chat_text(messages)` 的参数必须是
> `[{"role":"user","content":"..."}]` 列表，传字符串会报 HTTP 500。

---

## 10. 2026-10-03 PC（Windows）实况补充

Linux 沙箱那份清单在 Windows 上有若干处不成立，以下为实测修正。

### 10.1 Godot：必须自己装，版本串是装对了的判据

本机桌面只有 `Godot_v4.7-stable_win64.exe`（`4.7.stable.official.5b4e0cb0f`），
**与项目要求的 4.7.2 不是同一版本**，用它跑的实机截图结论不可信。需另装：

```bash
mkdir -p /c/tools/godot && cd /c/tools/godot
curl -L -o godot472.zip \
  "https://ghfast.top/https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_win64.exe.zip"
unzip -t godot472.zip          # 必须先验完整性
unzip -oq godot472.zip
./Godot_v4.7.2-stable_win64_console.exe --version
# 期望：4.7.2.stable.official.ed1daf0bf（与项目记录逐字一致）
```

ghfast.top 镜像实测 82MB / 15 秒完成。**用 `_console.exe` 变体**，
非 console 版在 Git Bash 下没有可用的 stdout。

### 10.2 ⚠️ `/tmp` 在 shell 与 Python 下不是同一目录

这是 Windows 上最容易踩的坑：

| 语境 | `/tmp` 解析到 |
|---|---|
| Git Bash | `C:\Users\<user>\AppData\Local\Temp` |
| Python `Path("/tmp")` | `C:\tmp` |

后果：流水线第 3 步（`process_walk.py`）把产物写到 `C:\tmp\walkgen`，
第 4 步（`run_walk_pipeline.sh` 内嵌 Python 读 `/tmp/walkgen`）却去 `%TEMP%` 找，
**报 `no seq`**。已修：三个脚本统一读 `WALKGEN_ROOT` 环境变量。

```bash
export WALKGEN_ROOT="C:/tmp/walkgen"   # 显式指定，别依赖 /tmp 默认值
```

> 注意 `C:\tmp` 是**真实写权限**位置，若用 msys 的 `%TEMP%` 反而要确认可写。

### 10.3 `python3` 在 Windows 上不存在

`run_walk_pipeline.sh` 与 `process_walk.py` 原先多处写死 `python3`。
已修为 `VENV_PY -> python3 -> python` 依次回退，子进程改用 `sys.executable`。

抠图 venv（`rembg` 只装在这一个解释器里）：

```bash
VENV="C:/Users/<user>/.workbuddy/binaries/python/envs/default"
"$VENV/Scripts/pip.exe" install pillow numpy rembg onnxruntime
```

### 10.4 rembg 模型预置（否则伪装成「生图卡住」）

`~/.u2net/isnet-general-use.onnx`（178,648,008 字节）本机默认没有。
不预置时 rembg 会去下 u2net 176MB，表现为「图已落盘但进程卡十分钟」。
`gen_base_views.py` 与 `process_walk.py` 都已固定用 `isnet-general-use`，
但**文件仍须自己在**：

```bash
mkdir -p ~/.u2net && cd ~/.u2net
curl -sL --max-time 600 -o isnet-general-use.onnx \
  "https://github.com/danielgatis/rembg/releases/download/v0.0.0/isnet-general-use.onnx"
```

### 10.5 导入产物数量：431 而非 572

`--import` 后 `.godot/imported/` 实测 **431 个 .ctex**（配套 433 个 .md5，
外加 1 个音频 `.oggvorbisstr` + 1 个字体 `.fontdata`，全部配对无残留）。
§5.0 与本文档原记的「572 个 .ctex」是沙箱时期的旧数字，**431 才是本机正确值**。

> 有个反直觉点：Godot 会把 `docs/v08/` 下的证据图也一并导入
> （如 `batong_right_cycle_sheet_20261003.png-....ctex`），
> 所以 ctex 数远多于 `assets/` 的 278 张游戏 PNG。计数对不上属正常，别据此判断导入失败。

### 10.6 Agnes 密钥 402 的排查顺序

若报 `HTTP 402: Subscription request not allowed`：

1. **先用 `chat_text` 探活**。文本与生图**同时** 402 → 账号/密钥级问题，与代码无关。
2. base_url 与鉴权方式无需改动（`https://apihub.agnes-ai.com/v1` + `Authorization: Bearer`）。
3. 格式正确性看 `cpk-` 前缀 + 长度 52。
4. 最常见成因：**密钥已被轮换/停用**。§7 建议轮换明文泄露过的密钥，轮换后旧值即失效。

### 10.7 Windows 侧一键复现（含全部环境变量）

```bash
export PAVO_API_KEY="cpk-..."                 # 换用有效密钥
export WALKGEN_ROOT="C:/tmp/walkgen"           # 统一暂存根
export VENV_PY="C:/Users/<user>/.workbuddy/binaries/python/envs/default/Scripts/python.exe"
export GODOT_BIN="C:/tools/godot/Godot_v4.7.2-stable_win64_console.exe"
GODOT="/c/tools/godot/Godot_v4.7.2-stable_win64_console.exe"

cd /path/to/dungeon-rogue-godot
"$GODOT" --headless --path . --import                             # 必做第一步
bash tools/run_walk_pipeline.sh batong right
```


---

## 11. Web 导出（2026-10-03 实测）

### 11.1 必须先装 Web 导出模板，否则一律失败

本项目导出 Web 依赖对应版本的模板，缺模板时报错：

```
ERROR: Cannot export project with preset "Web" due to configuration errors:
No export template found at the expected path:
  <user>/.local/share/godot/export_templates/4.7.2.stable/web_nothreads_debug.zip
  <user>/.local/share/godot/export_templates/4.7.2.stable/web_nothreads_release.zip
```

模板路径（**文件名与版本号必须严格匹配，且必须是 zip 形态**）：

```
~/.local/share/godot/export_templates/4.7.2.stable/web_nothreads_release.zip
```

两种获取方式：

| 方式 | 包体 | 说明 |
|---|---|---|
| 只取 web 包 | ~10MB | 推荐。从 Godot Releases 取 `web_nothreads_release.zip` 手工放到上述路径 |
| 全量 tpz | 1.28GB | `Godot_v<版本>-stable_export_templates.tpz`，解压后**仍需重新打包成 zip** |

> **踩坑记录**：手工把 zip 解压成散文件（godot.js / godot.wasm / ...）放进去**不行**，
> Godot 认的是 zip 本身。必须 `zip -r web_nothreads_release.zip <那7 个文件>`。
>
> GitHub Releases 直连极慢（~20-28KB/s），用 `ghfast.top` 镜像可到 4MB/s：
> ```bash
> curl -L -o tpl.zip "https://ghfast.top/https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz"
> ```

### 11.2 导出与验证

```bash
GODOT_BIN=$(which godot) python3 tools/export_web.py
```

产物在 `web/`（已被 `.gitignore` 忽略，只保留 `shell.html`），门禁阈值见
`tools/export_web.py` 的 `LIMIT_PCK` / `LIMIT_BR`，可用
`WEB_LIMIT_PCK_MB` / `WEB_LIMIT_BR_MB` 覆盖。

2026-10-03 实测体积：html 0.02 / js 0.27 / wasm 37.68 / pck 33.47 MB，
brotli 首包 39.48 MB。

> **注意**：真正卡首包的是 **wasm（37.7MB，不随素材变化）**。
> 想实质压缩首包应优化引擎构建（更小的 wasm / 开 wasm-opt），
> 不要砍素材——素材是功能，引擎体积才是可优化项。

### 11.3 无头环境验证 Web 版（容易误判为「产物坏了」）

Web 版需要 **WebGL2**。沙箱无 GPU 时，即使产物完全正常也会报：

```
The following features required to run Godot projects on the Web are missing: WebGL2
```

这**不是产物问题**。解法与项目其他实机验证同一范式——xvfb + angle swiftshader：

```bash
# 需先起静态服务器
python3 -m http.server 8765 --directory web &
xvfb-run -a --server-args="-screen 0 1920x1080x24" python3 webcheck.py
```

判据（不是「页面返回 200」，也不是「进程退出码 0」）：

| 观察点 | 未渲染 | 正常 |
|---|---|---|
| canvas 尺寸 | 300x150（默认值） | **1280x720**（真实视口） |
| `#status` | `display:flex opacity=1`（加载屏卡住） | `display:none`（已淡出） |

> 这条与AI-HANDOVER §7「陷阱 1/3」同源：**资源能加载 ≠ 渲染链路能跑**。
> 光看 HTTP 200 或退出码 0 都会得出假通过结论。
