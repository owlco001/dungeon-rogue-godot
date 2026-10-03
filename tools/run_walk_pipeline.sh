#!/usr/bin/env bash
# 四朝向行走动画一键流水线
#   基准图 -> 视频生成 -> 抽帧/抠图/质检 -> 导入游戏 assets
# 用法: bash tools/run_walk_pipeline.sh <角色ID> [方向...]
set -uo pipefail

CHAR="${1:-aila}"
shift || true
DIRS=("$@")
[ ${#DIRS[@]} -eq 0 ] && DIRS=(right front back left)

# 仓库根目录自定位（2026-10-03 脱敏补修：原为硬编码 /workspace/dungeon-rogue-godot）
PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# 2026-10-03 Windows 兼容：原写死 python3，而抠图 venv 的解释器在 Scripts/ 下。
# 优先取 VENV_PY，其次当前 python3，最后 Windows 的 python。
if [ -n "${VENV_PY:-}" ]; then
  PY="$VENV_PY"
elif command -v python3 >/dev/null 2>&1; then
  PY="python3"
else
  PY="python"
fi
# Agnes 密钥变量名是 PAVO_API_KEY，不是 AGNES_API_KEY —— 后者设了也不生效，
# 且部分旧脚本用 setdefault("AGNES_API_KEY","") 把「未配置」伪装成「已配置」。
if [ -z "${PAVO_API_KEY:-}" ] && [ -f /root/.agnes/agnes.env ]; then
  source /root/.agnes/agnes.env
fi

# 抽帧暂存根。2026-10-03 Windows 兼容修正：Git Bash 的 /tmp 解析到
# %TEMP%，而 Python 的 Path("/tmp/...") 解析到 C:\tmp，两者不是同一目录——
# 原写法会让第 4 步找不到第 3 步的产物（报 "no seq"）。
# 故统一由 WALKGEN_ROOT 传入，Python 侧读同一环境变量。
OUT="${WALKGEN_ROOT:-/tmp/walkgen}/$CHAR"
DEST="$PROJ/assets/sprites/characters/$CHAR"
mkdir -p "$DEST"

echo "########## 1/4 基准图 ##########"
# 角色 ID 必须作为首参传入：gen_base_views.py 用它选身份串与朝向描述，
# 漏传会把方向名当角色 ID（2026-10-03 实测）。
$PY "$PROJ/tools/gen_base_views.py" "$CHAR" "${DIRS[@]}" 2>&1 | grep -v retryable

echo "########## 2/4 视频生成 ##########"
$PY "$PROJ/tools/gen_walk_video.py" "$CHAR" "${DIRS[@]}" 2>&1

echo "########## 3/4 抽帧 + 质检 ##########"
$PY "$PROJ/tools/process_walk.py" "$CHAR" "${DIRS[@]}" 2>&1

echo "########## 4/4 导入游戏 ##########"
$PY - "$CHAR" "$DEST" "${DIRS[@]}" <<'PYEOF'
import json, shutil, sys
from pathlib import Path
char, dest = sys.argv[1], Path(sys.argv[2])
dirs = sys.argv[3:]
root = Path(os.environ.get("WALKGEN_ROOT", "/tmp/walkgen"))
rep = root / "process_summary.json"
summary = json.loads(rep.read_text()) if rep.exists() else {}
ok, ng = [], []
from PIL import Image, ImageOps

# 左侧向由 right 镜像派生（项目铁律：多帧一律镜像，保证左右绝对一致，
# 避免两条独立视频之间的形象/装备漂移）
MIRROR = {"left": "right"}

for d in dirs:
    src_dir = MIRROR.get(d, d)
    rep = root / char / src_dir / "final/report.json"
    seq = root / char / src_dir / "final/seq"
    if not rep.exists() or not seq.exists():
        ng.append((d, "no seq")); continue
    r = json.loads(rep.read_text())
    fs = sorted(f for f in seq.glob("walk_[0-9]*.png"))
    n = 0
    for f in fs:
        im = Image.open(f).convert("RGBA")
        if d in MIRROR:
            im = ImageOps.mirror(im)
        im.save(dest / f.name.replace("walk_", f"char_{char}_{d}_walk_"))
        n += 1
    tag = f"{r.get('verdict')} seam={r.get('seam_cost_final')} frames={n} mode={r.get('loop_mode')}"
    (ok if r.get("verdict") == "PASS" else ng).append((d, tag))
print("\n===== 导入结果 =====")
for d, info in ok: print(f"  [PASS] {d}: {info}")
for d, info in ng: print(f"  [NG  ] {d}: {info}")
PYEOF

echo "########## 完成 ##########"
ls -1 "$DEST" | wc -l | xargs echo "角色目录文件数:"
du -sh "$OUT"
