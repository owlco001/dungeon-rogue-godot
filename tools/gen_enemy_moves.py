#!/usr/bin/env python3
"""批量生成怪物移动帧（Agnes img2img）+ 蛮兽待机重画。"""
import subprocess
import sys
from pathlib import Path
from PIL import Image

ROOT = Path("/home/hatch/workspace/games/dungeon-rogue-godot")
AGNES = Path("/home/hatch/workspace/skills/agnes/bin/agnes")
OUT = ROOT / "assets/sprites/enemies"
TMP = Path("/tmp/enemy_gen")
TMP.mkdir(exist_ok=True)

# 先备份蛮兽原待机
for f in ["enemy_brute_idle_00.png", "enemy_brute_idle_01.png"]:
    src = OUT / f
    dst = ROOT / "preview" / ("orig_" + f)
    if src.exists() and not dst.exists():
        dst.write_bytes(src.read_bytes())
        print("backup", f, flush=True)


def gen(prompt, ref, out_raw):
    r = subprocess.run(
        [str(AGNES), "img2img", "--prompt", prompt, "--image", str(ref),
         "--size", "1024x1024", "--out", str(out_raw)],
        capture_output=True, text=True, timeout=300)
    if r.returncode != 0:
        print("GEN FAILED", out_raw, r.stderr[-500:], flush=True)
        return False
    print("gen ok", out_raw.name, flush=True)
    return True


def finish(raw, final_name):
    im = Image.open(raw).convert("RGBA")
    bbox = im.getbbox()
    if bbox is None:
        print("EMPTY", raw, flush=True)
        return False
    im.crop(bbox).resize((64, 64), Image.LANCZOS).save(OUT / final_name)
    print("saved", final_name, flush=True)
    return True


BASE = ("pixel art game sprite, 2D top-down game asset, transparent background, "
        "keep exact same character design and colors as reference, do not add extra limbs")

# 1) 蛮兽待机重画（先做，后续 move 帧以新待机为参照）
brute_ref = OUT / "enemy_brute_idle_00.png"
brute_new_raw = TMP / "brute_idle_new.png"
if gen("hulking muscular demon brute monster, big arms, menacing front-facing idle stance, "
       "dark red skin, black horns, " + BASE, brute_ref, brute_new_raw):
    finish(brute_new_raw, "enemy_brute_idle_00.png")
    # idle_01：新待机下移 2px 做呼吸差分
    im = Image.open(OUT / "enemy_brute_idle_00.png").convert("RGBA")
    canvas = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    canvas.paste(im, (0, 2), im)
    canvas.save(OUT / "enemy_brute_idle_01.png")
    print("saved enemy_brute_idle_01.png (bob)", flush=True)

JOBS = [
    ("bat", 0, "bat monster wings raised high, flapping up"),
    ("bat", 1, "bat monster wings swept down, flapping down"),
    ("skeleton", 0, "skeleton warrior left leg stepping forward, walking"),
    ("skeleton", 1, "skeleton warrior right leg stepping forward, walking"),
    ("brute", 0, "demon brute lunging forward, attacking"),
    ("brute", 1, "demon brute recoiling back, recovering"),
    ("spitter", 0, "carnivorous plant monster mouth wide open, spitting"),
    ("spitter", 1, "carnivorous plant monster mouth closed, recoiled"),
    ("exploder", 0, "fire beetle monster crouched low, compressed"),
    ("exploder", 1, "fire beetle monster body bulging swollen, about to burst"),
    ("gargoyle", 0, "stone gargoyle wings raised high"),
    ("gargoyle", 1, "stone gargoyle wings lowered, stepping forward"),
]

ok = True
for eid, idx, desc in JOBS:
    ref = OUT / f"enemy_{eid}_idle_00.png"
    raw = TMP / f"{eid}_move_{idx:02d}.png"
    if gen(f"{desc}, {BASE}", ref, raw):
        ok = finish(raw, f"enemy_{eid}_move_{idx:02d}.png") and ok
    else:
        ok = False

# 史莱姆沿用已确认的样品
for i in [0, 1]:
    src = Path(f"/tmp/slime_move_0{i}.png")
    if src.exists():
        Image.open(src).save(OUT / f"enemy_slime_move_0{i:02d}.png")
        print("saved enemy_slime_move_%02d.png (sample)" % i, flush=True)

print("ALL DONE" if ok else "DONE WITH FAILURES", flush=True)
