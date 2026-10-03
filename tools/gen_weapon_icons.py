#!/usr/bin/env python3
"""19 武器图标批量生成（Agnes txt2img）+ 抠图入库 128px。"""
import subprocess
from collections import deque
import os
from pathlib import Path

import numpy as np
from PIL import Image
from scipy.ndimage import binary_dilation

# 仓库根目录= 本脚本上级目录；如在别处运行可设 DUNGEON_ROOT 覆盖
ROOT = Path(os.environ.get("DUNGEON_ROOT", Path(__file__).resolve().parent.parent))
# Agnes CLI 路径：默认读环境变量 AGNES_BIN，找不到时回退到 PATH 里的 agnes
AGNES = Path(os.environ.get("AGNES_BIN", "agnes"))
RAW = Path("/tmp/icon_gen")
OUT = ROOT / "assets/icons/weapons"
OUT.mkdir(parents=True, exist_ok=True)

STYLE = ("game weapon icon, stylized clean game art, subtle glow, "
         "transparent background, no text, no frame, centered")

# 已确认的 3 张：bow=v4, hound, corpse_blast（直接转存）
READY = {
    "bow": RAW / "bow_v4.png",
    "hound": RAW / "hound.png",
    "corpse_blast": RAW / "corpse_blast.png",
}

JOBS = [
    ("dual", "pair of crossed flintlock pistols, ornate steel, faint blue glow"),
    ("shotgun", "pump-action shotgun side view, wooden pump, steel barrel"),
    ("sniper", "long sniper rifle with telescopic scope, camouflage accents"),
    ("gatling", "minigun with six rotating barrels, brass ammo belt"),
    ("sentry", "compact deployable gun turret on tripod base, blue sensor light"),
    ("skel_warrior", "skeleton warrior bust with horned helmet and notched sword"),
    ("swarm", "swirling vortex of angry hornets, yellow-black"),
    ("orb", "arcane violet magic orb with glowing runes, purple glow"),
    ("skel_army", "three skeleton skulls stacked pyramid, eerie green glow"),
    ("life_drain", "green soul flame orb with rising wisps, necromancy"),
    ("curse_aura", "dark violet cursed rune circle, ominous glow"),
    ("whirlwind", "double-bladed axe spinning in motion blur whirlwind"),
    ("melee_axe", "heavy double-bit battle axe, worn steel, leather wrap"),
    ("shield_bash", "round steel shield with central spike boss"),
    ("warcry", "carved barbarian war horn, bone and brass"),
    ("flying_axe", "single throwing axe captured mid-spin, motion arcs"),
]


def gen(wid, desc):
    raw = RAW / f"{wid}.png"
    if raw.exists() and raw.stat().st_size > 50000:
        print("skip", wid, flush=True)
        return True
    r = subprocess.run(
        [str(AGNES), "txt2img", "--prompt", f"{desc}, {STYLE}",
         "--size", "512x512", "--out", str(raw)],
        capture_output=True, text=True, timeout=300)
    ok = r.returncode == 0 and raw.exists()
    print(("gen ok " if ok else "GEN FAIL ") + wid, flush=True)
    return ok


def cleanse(src: Path, tol=42.0):
    im = Image.open(src).convert("RGBA")
    a = np.array(im)
    h, w, _ = a.shape
    border = np.concatenate([a[0, :, :3].reshape(-1, 3), a[-1, :, :3].reshape(-1, 3),
                             a[:, 0, :3].reshape(-1, 3), a[:, -1, :3].reshape(-1, 3)])
    q = (border // 16 * 16 + 8).astype(np.int32)
    uniq, counts = np.unique(q.reshape(-1, 3), axis=0, return_counts=True)
    colors = []
    for i in np.argsort(-counts)[:4]:
        c = uniq[i]
        if c.min() > 150:
            colors.append(c.astype(float))
        if len(colors) == 2:
            break
    if not colors:
        colors = [np.array([255., 255., 255.])]
    f = a[..., :3].astype(float)
    bg = np.zeros((h, w), dtype=bool)
    for c in colors:
        bg |= np.abs(f - c).max(axis=2) < tol
    seen = np.zeros((h, w), dtype=bool)
    dq = deque()
    for x in range(w):
        for y in (0, h - 1):
            if bg[y, x] and not seen[y, x]:
                seen[y, x] = True
                dq.append((y, x))
    for y in range(h):
        for x in (0, w - 1):
            if bg[y, x] and not seen[y, x]:
                seen[y, x] = True
                dq.append((y, x))
    while dq:
        y, x = dq.popleft()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and bg[ny, nx] and not seen[ny, nx]:
                seen[ny, nx] = True
                dq.append((ny, nx))
    edge = binary_dilation(seen, iterations=2) & ~seen
    px = a[edge].astype(float)
    if len(px):
        px[..., :3] *= 0.82
        a[edge] = px.astype(np.uint8)
    a[seen, 3] = 0
    return Image.fromarray(a)


def finish(wid, raw):
    im = cleanse(raw)
    bb = im.getbbox()
    if bb:
        im = im.crop(bb)
    im.resize((128, 128), Image.LANCZOS).save(OUT / f"icon_{wid}.png")
    print("saved", f"icon_{wid}.png", flush=True)


ok = True
for wid, desc in JOBS:
    if gen(wid, desc):
        finish(wid, RAW / f"{wid}.png")
    else:
        ok = False
for wid, raw in READY.items():
    if raw.exists():
        finish(wid, raw)
    else:
        print("MISSING READY", wid, flush=True)
        ok = False
print("ICONS DONE" if ok else "ICONS DONE WITH FAILURES", flush=True)
