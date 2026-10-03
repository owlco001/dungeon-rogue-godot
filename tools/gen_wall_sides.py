#!/usr/bin/env python3
"""6 主题墙面 side 贴图批量重画（Agnes txt2img），96px 入库。"""
import subprocess
import os
from pathlib import Path

from PIL import Image

# 仓库根目录= 本脚本上级目录；如在别处运行可设 DUNGEON_ROOT 覆盖
ROOT = Path(os.environ.get("DUNGEON_ROOT", Path(__file__).resolve().parent.parent))
# Agnes CLI 路径：默认读环境变量 AGNES_BIN，找不到时回退到 PATH 里的 agnes
AGNES = Path(os.environ.get("AGNES_BIN", "agnes"))
RAW = Path("/tmp/wall_gen")
RAW.mkdir(exist_ok=True)
OUT = ROOT / "assets/tiles"

BASE = ("dungeon stone wall texture, large rough-hewn stone blocks with mortar lines, "
        "subtle depth and shading, seamless tileable game texture, pixel art style, "
        "2D top-down dungeon crawler wall")

# corridor 已确认（/tmp/wall_side_new.png），直接入库
READY = {"corridor": Path("/tmp/wall_side_new.png")}

JOBS = [
    ("tomb", "warm brown sandstone blocks, torch-lit, ancient tomb"),
    ("forge", "dark basalt blocks with glowing ember cracks, forge heat"),
    ("ice", "pale ice-blue frosted stone blocks, frozen, cold light"),
    ("thorn", "dark mossy stone blocks with creeping thorn vines"),
    ("void", "dark purple-black void stone blocks with faint violet rune glow"),
]


def gen(theme, desc):
    raw = RAW / f"{theme}.png"
    if raw.exists() and raw.stat().st_size > 50000:
        print("skip", theme, flush=True)
        return True
    r = subprocess.run(
        [str(AGNES), "txt2img", "--prompt", f"{desc}, {BASE}",
         "--size", "512x512", "--out", str(raw)],
        capture_output=True, text=True, timeout=300)
    ok = r.returncode == 0 and raw.exists()
    print(("gen ok " if ok else "GEN FAIL ") + theme, flush=True)
    return ok


def finish(theme, raw):
    im = Image.open(raw).convert("RGB")
    im.resize((96, 96), Image.LANCZOS).save(OUT / theme / f"tile_{theme}_side.png")
    print("saved", f"tile_{theme}_side.png", flush=True)


ok = True
for theme, desc in JOBS:
    if gen(theme, desc):
        finish(theme, RAW / f"{theme}.png")
    else:
        ok = False
for theme, raw in READY.items():
    if raw.exists():
        finish(theme, raw)
    else:
        print("MISSING READY", theme, flush=True)
        ok = False
print("WALLS DONE" if ok else "WALLS DONE WITH FAILURES", flush=True)
