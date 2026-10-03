#!/usr/bin/env python3
"""dungeon-rogue-godot 精细化角色动画生成管线 v09

核心目标：动作流畅 + 运动不变形
技术方案（对应清单 §4）：
  ① 基准帧 txt2img 定形象
  ② img2img 转walk 帧序列（保持同一形象）
  ③ PIL 镜像生成右方向
  ④ union bbox 统一裁剪（防帧间抖动）
  ⑤ 脚底基线对齐（防上下跳）
  ⑥ rembg 抠透明底
  ⑦ 帧间配准校验（bbox 方差超阈值告警）

用法：
  python3 tools/gen_anim.py --char aila --frames 6
"""
import argparse
import base64
import json
import os
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))  # 让同目录的 agnes_path 可导入
from agnes_path import ROOT  # noqa: E402  优先 DUNGEON_ROOT，否则脚本自定位

OUT = ROOT / "assets/sprites/characters"
STAGE = Path(os.environ.get("STAGE_DIR", "/tmp/artwork/stage"))

# 角色设定（与 data/*.json 一致）
CHARS = {
    "aila": {
        "name": "艾拉", "weapon": "glowing golden longbow",
        "palette": "warm gold #F0C060 and bronze armor, crimson cape",
        "desc": "female archer, ornate gold-bronze plate armor with engraved filigree, "
                "detailed crimson cape, leather boots",
    },
    "batong": {
        "name": "巴顿", "weapon": "heavy battle axe",
        "palette": "dark crimson and weathered leather brown",
        "desc": "male warrior, heavy crimson and leather armor, broad shoulders, "
                "carrying a heavy battle axe",
    },
    "mofei": {
        "name": "墨菲", "weapon": "glowing arcane orb",
        "palette": "undead purple #8E44AD and spectral blue",
        "desc": "mage character, layered purple and dark robes, "
                "glowing arcane orb floating beside the hand",
    },
}

DIRS = ["down", "left", "right", "up"]
# 6 帧行走循环的肢体相位（实测：img2img 对"温和"描述忠实度过高、动作几乎不变，
#  必须用强对比的姿态词才出可见幅度。stride_wide 与 legs_together 实测相差 87px 宽度）
WALK_PHASES = [
    "STRIDE WIDE pose, legs spread far apart, front foot planted far forward, "
    "rear foot trailing far behind, body extended, cloak swept to the side",
    "CENTER COMPRESSED pose, legs together at center, feet close together, "
    "body compressed low, cloak wrapped inward",
    "STRIDE WIDE pose mirrored, legs spread far apart, opposite foot forward, "
    "body extended, cloak swept to the opposite side",
    "CENTER COMPRESSED pose mirrored, legs together, body at lowest point, "
    "cloak wrapped inward",
    "STRIDE WIDE pose, front foot far forward again, body extended, cloak swept",
    "CENTER COMPRESSED pose, legs together, body rising, cloak lifting",
]

# 风格锚点：精细化手绘 + 3/4 俯视 + 隔离主体
STYLE = (
    "top-down 3/4 overhead view 2D game character sprite, viewed from above at an angle, "
    "head at top of frame and feet at bottom, character fully visible head to toe, "
    "dark fantasy dungeon, highly detailed hand-painted illustration, "
    "rich material rendering, volumetric shading, rim light, sharp clean silhouette, "
    "dark moody palette with gold key light, cinematic game art quality, "
    "isolated on pure black background, single character only, "
    "NO pixel art, NO flat color, NO cartoon outline, "
    "no background scenery, no environment, no props, no text, no watermark"
)

NEG_IMG2IMG = (
    "text, watermark, UI, frame, border, multiple characters, "
    "background scenery, environment, cropped body, head cut off, feet cut off"
)


def gen_base(char: str, size="1024x1024", tries=3) -> Path | None:
    """生成基准帧（txt2img，纯黑底便于 rembg）"""
    from agnes_path import require_agnes_client

    ac = require_agnes_client()
    c = CHARS[char]
    prompt = f"{STYLE}, {c['desc']}, {c['weapon']}, {c['palette']}, standing still"
    for i in range(tries):
        try:
            u = ac.generate_image_url(prompt, size=size)
            raw = base64.b64decode(u.split(",", 1)[1]) if u.startswith("data:") \
                  else __import__("requests").get(u, timeout=90).content
            STAGE.mkdir(parents=True, exist_ok=True)
            p = STAGE / f"{char}_base.png"
            p.write_bytes(raw)
            print(f"  ✅ 基准帧 {len(raw)//1024}KB")
            return p
        except Exception as e:
            print(f"  ⚠️ 基准帧第{i+1}次: {str(e)[:90]}")
            time.sleep(15 * (i + 1))
    return None


def gen_walk_frames(char: str, base: Path, direction: str, n: int, tries=3) -> list[Path]:
    """img2img 从基准帧转行走帧序列 —— 保持同一形象的关键"""
    from agnes_path import require_agnes_client

    ac = require_agnes_client()
    c = CHARS[char]
    b64 = "data:image/png;base64," + base64.b64encode(base.read_bytes()).decode()
    dir_desc = {
        "down": "facing toward the viewer / facing down-screen, face visible",
        "up": "facing away from the viewer, back of head and cape visible",
        "left": "facing left side of screen, profile view, left side visible",
        "right": "facing right side of screen, profile view, right side visible",
    }[direction]

    out = []
    STAGE.mkdir(parents=True, exist_ok=True)
    for idx in range(n):
        phase = WALK_PHASES[idx % len(WALK_PHASES)]
        p = STAGE / f"{char}_{direction}_walk_{idx:02d}.png"
        if p.exists():
            out.append(p)
            print(f"  · {p.name} 已存在,跳过")
            continue
        prompt = (f"{STYLE}, {c['desc']}, {c['weapon']}, {c['palette']}, "
                  f"{dir_desc}, walking cycle frame, {phase}, "
                  f"SAME character design as reference, identical armor and cape, "
                  f"consistent body proportions, same scale, same lighting")
        for i in range(tries):
            try:
                u = ac.generate_image_url(prompt, size="1024x1024",
                                          input_images=[b64], negative_prompt=NEG_IMG2IMG)
                raw = base64.b64decode(u.split(",", 1)[1]) if u.startswith("data:") \
                      else __import__("requests").get(u, timeout=90).content
                p.write_bytes(raw)
                out.append(p)
                print(f"  ✅ {p.name}  {len(raw)//1024}KB")
                break
            except Exception as e:
                print(f"  ⚠️ {p.name} 第{i+1}次: {str(e)[:90]}")
                time.sleep(15 * (i + 1))
    return out


def cutout(src: Path, dst: Path) -> Path:
    """rembg 抠透明底（单进程串行，铁律 2）"""
    code = f'''
from rembg import new_session, remove
from PIL import Image
sess = new_session("u2net")
im = Image.open("{src}").convert("RGBA")
out = remove(im, session=sess)
out.save("{dst}")
print("bbox", out.split()[3].getbbox())
'''
    r = subprocess.run([sys.executable, "-c", code],
                       capture_output=True, text=True, timeout=600)
    return dst if dst.exists() else None


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--char", default="aila")
    ap.add_argument("--frames", type=int, default=6)
    ap.add_argument("--dirs", default="down,left,up")  # right 由镜像生成
    args = ap.parse_args()

    print(f"=== {args.char} 行走序列生成（{args.frames} 帧/方向）===")
    base = STAGE / f"{args.char}_base.png"
    if base.exists():
        print("  基准帧已存在,复用")
    else:
        base = gen_base(args.char)
    if not base:
        sys.exit(1)
    print(f"基准帧: {base}")

    for d in args.dirs.split(","):
        d = d.strip()
        if not d:
            continue
        print(f"\n-- 方向 {d} --")
        frames = gen_walk_frames(args.char, base, d, args.frames)
        print(f"  完成 {d}: {len(frames)}/{args.frames} 帧")
