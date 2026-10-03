#!/usr/bin/env python3
"""
技能图标 7 张 + 遗物图标 12 张= 19 张

规格依据（先读代码）：
  hud.gd: _detail_icon.custom_minimum_size = 64x64，EXPAND_IGNORE_SIZE
      => 引擎显示 64px。生成 256 画布（GUI 缩放），关键是 64px 下还能分辨。
  命名严格照抄 game_data.gd：
      技能 icon_skill_<sid>.png，sid ∈ arrowrain/stomp/souldrain/dash/holyshield/meteor/timestop
      遗物 icon_relic_<rid>.png，注意有文件名与 id 不同名的（照抄 game_data.gd）：
           wardrum      -> icon_relic_berserk.png   （狂暴战鼓）
           blink 是技能 id，其文件名为 icon_skill_dash.png（闪现）
      抄错文件名 = 运行时 load 失败，必须严格对齐

与角色/杂兵的差别：
  角色/杂兵在 384px 显示，细节是加分项；
  图标在 64px 显示，细节全是噪点，必须「剪影极简 + 单一主体 + 高对比」。
  所以风格锚点里加重thick outline / flat readable shape，并强制做 64px 缩略图测试。
"""
import os
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import gen_enemies as GE# noqa: E402

ROOT = Path(os.environ.get("DUNGEON_ROOT", Path(__file__).resolve().parent.parent))
ROOT = Path("/tmp/icons")
SKILL_DIR = (ROOT / "assets/icons/skills")
RELIC_DIR = (ROOT / "assets/icons/relics")
SIZE = 256
FILL = 0.80   # 图标要撑满，不留过多边距（小尺寸下主体越小越看不清）
# 图标密度阈值放宽到 0.24：图标风格就是「剪影极简」，镰刀、沙漏这类细长形天然稀疏
# （实测镰刀 0.27~0.30），沿用角色素材的 0.35 阈值会连续 3 轮误杀正确素材。
FILL_MIN = 0.24

# 图标比角色稍亮：UI 面板通常比场景亮，且图标要在深色面板上有对比
GE.TARGET_SAT = 0.22
GE.TARGET_LUM = 0.30
GE.HIGHLIGHT_CAP = 0.75

# 风格锚点：剪影优先，细节最少化
# 注意：全局「muted desaturated」会覆盖单个图标的鲜艳需求（实测磁铁要求
# "bold saturated crimson" 仍被生成成灰钢主体，饱和仅 0.097，缩略图下认不出）。
# 需要高识别度的图标改用 VIVID_STYLE。
ICON_STYLE = ("game skill icon, single bold simple symbol, extremely readable clear silhouette, "
              "thick heavy dark ink outline, flat simplified shapes with minimal interior detail, "
              "single centered symbol filling most of the square frame, "
              "dark fantasy dungeon theme, muted desaturated palette with one accent colour, "
              "plain very dark grey background, "
              "NOT pixel art, NO photorealistic, NO 3D render, NO glossy plastic, "
              "NO text, NO letters, NO numbers, NO border frame, NO multiple objects, "
              "NO tiny details, NO clutter")

# 高识别度图标：主体本身就是识别标志（磁铁的红、火焰的橙），
# 不能被去饱和抹平，所以给独立风格（保留饱和 + 提高明度对比）。
VIVID_STYLE = ("game skill icon, single bold simple symbol, extremely readable clear silhouette, "
               "thick heavy black ink outline, flat simplified shapes, minimal interior detail, "
               "single centered symbol filling most of the square frame, "
               "STRONG SATURATED COLOUR on the main body, high contrast against the background, "
               "dark fantasy dungeon theme, plain very dark grey background, "
               "NOT pixel art, NOT photorealistic, NOT 3D render, NOT glossy plastic, "
               "NO text, NO letters, NO numbers, NO border frame, NO multiple objects, "
               "NO muted grey palette, NO washed out colours, NO desaturated body")

# 需要高识别度（主体颜色即标志）的图标 -> 用 VIVID_STYLE
VIVID = {"magnetcore", "phoenixheart", "infinitefire", "bloodgem", "scythe", "thornmail"}

NEG_ICON = ("text, letters, numbers, watermark, signature, border, frame, "
            "multiple objects, multiple icons, grid, sheet, collage, "
            "photorealistic, 3d render, glossy, neon glow, gradient, "
            "busy background, scenery, cropped, out of frame, low contrast")

# ---- 技能图标（key = 文件名，值 = 主体描述）----
SKILLS = {
    "arrowrain": ("a downward rain of five golden arrows falling diagonally onto the ground, "
                  "arrowheads pointing down, motion streaks behind them"),
    "stomp": ("a heavy armored boot sole slamming down onto cracked stone ground, "
              "impact lines radiating outward from the contact point"),
    "souldrain": ("a ghostly pale soul wisp being pulled into a dark jagged maw, "
                  "dull violet soul energy streaming inward"),
    "dash": ("a fast motion streak silhouette of a figure dashing to the right, "
             "three tapered speed lines trailing behind, no visible face"),
    "holyshield": ("a solid rounded shield with a dull golden holy cross emblem in the centre, "
                   "faint warm glow outlining the shield edge"),
    "meteor": ("a burning meteor falling from the top right with a short flame trail, "
               "hitting a cracked ground surface with a small burst of embers"),
    "timestop": ("a classic hourglass with dull amber sand inside, "
                 "the falling sand frozen mid-air, faint clock hands behind it"),
}

# ---- 遗物图标（key = 文件名，值 = 主体描述）----
RELICS = {
    "greedcup": ("a golden chalice goblet overflowing with dull gold coins, ornate worn rim"),
    "bloodgem": ("a deep crimson teardrop gemstone in a dull gold ring setting, "
                 "dark blood-red glow inside"),
    "windboots": ("a pair of worn leather boots with tattered cloth streamers trailing "
                  "behind them, wind lines swirling around"),
    "sagestone": ("a rough pale grey wizard stone tablet with a carved spiral symbol, "
                  "faint amber glow in the carved groove"),
    # 需要高识别度的图标（暗调主体在灰度下糊成一团，必须给足对比色）
    "magnetcore": ("a bright red horseshoe magnet, bold saturated crimson red tips and "
                   "dark steel body, thick black outline, strong high contrast, "
                   "four iron filings clinging to it in a fan shape"),
    "berserk": ("a war drum with a dark hide stretched over it and drumsticks crossed on top, "
                "dull red war paint stripe"),
    "hourglass": ("a small brass hourglass with dull amber sand, "
                  "the sand frozen mid-fall, one drop frozen beside it"),
    "cross": ("an ornate golden cross with worn stone and a faint warm halo behind it, "
              "bloodstain at the base"),
    "scythe": ("a curved steel scythe blade with a wrapped dark handle, "
               "a faint crimson glow along the cutting edge"),
    "phoenixheart": ("a beating heart-shaped ember with dull orange flame feathers "
                     "growing out of it, charred edges"),
    "thornmail": ("a curved iron chest plate covered in sharp outward thorns, "
                  "dark steel with worn edges"),
    "infinitefire": ("an eternal flame burning inside a small dark iron brazier bowl, "
                     "dull orange flame with floating embers rising"),
}


def fetch_icon(prompt: str, dst: Path, ref: Path | None = None) -> bool:
    from PIL import Image
    import base64 as _b64
    if dst.exists() and dst.stat().st_size > 800:
        print(f"  [跳过] {dst.name}", flush=True)
        return True
    dst.parent.mkdir(parents=True, exist_ok=True)
    kw = dict(prompt=prompt, size=f"{SIZE}x{SIZE}", model=GE.MODEL)
    if ref is not None:
        kw["input_images"] = ["data:image/png;base64," +
                              _b64.b64encode(ref.read_bytes()).decode()]
    for t in range(3):
        try:
            r = GE.ac.generate_image(**kw)
            url = r["data"][0]["url"]
            os.system(f'curl -sL --max-time 120 -o "{dst}" "{url}" 2>/dev/null')
            if not dst.exists() or dst.stat().st_size < 600:
                raise RuntimeError("download failed")
            im = Image.open(dst)
            if im.size != (SIZE, SIZE):
                im.convert("RGB").resize((SIZE, SIZE), Image.LANCZOS).save(dst)
            print(f"  [{dst.name}] 第{t+1}次 {dst.stat().st_size//1024}KB", flush=True)
            return True
        except Exception as e:
            print(f"  [{dst.name}] 第{t+1}次失败: {type(e).__name__}: {str(e)[:100]}", flush=True)
            time.sleep(4)
    return False


def cut_icon(src: Path, dst: Path, vivid: bool = False) -> bool:
    """抠图 + 归一。图标必须撑满：小尺寸下主体每缩小10% 可读性就掉一截。

    vivid=True 时放宽去饱和：识别色图标的颜色本身就是标志，
    被 harmonize 的去饱和抹平就等于白做（实测磁铁饱和 0.097 认不出）。
    """
    from PIL import Image
    import numpy as np
    saved = GE.TARGET_SAT
    tmp = ROOT / (src.stem + "_cut.png")
    if vivid:
        GE.TARGET_SAT = 0.42      # 允许高饱和识别色
    try:
        if not GE.cutout(src, tmp):
            print(f"  [{dst.name}] 抠图失败", flush=True)
            return False
    finally:
        GE.TARGET_SAT = saved
    im = Image.open(tmp).convert("RGBA")
    bbox = im.getbbox()
    if not bbox:
        print(f"  [{dst.name}] 空图", flush=True)
        return False
    sub = im.crop(bbox)
    sc = (SIZE * FILL) / max(sub.height, 1)
    if sub.width * sc > SIZE * 0.94:
        sc = (SIZE * 0.94) / max(sub.width, 1)
    nw, nh = max(1, int(sub.width * sc)), max(1, int(sub.height * sc))
    sub = sub.resize((nw, nh), Image.LANCZOS)
    canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    canvas.paste(sub, ((SIZE - nw) // 2, (SIZE - nh) // 2))
    canvas.save(dst)
    a = np.array(canvas)[:, :, 3] > 40
    cov = a.sum() / a.size
    ys, xs = np.where(a)
    fillr = a.sum() / ((xs.max() - xs.min() + 1) * (ys.max() - ys.min() + 1))
    ok = 0.10 < cov < 0.68 and fillr > FILL_MIN
    print(f"  [{dst.name}] QC {'通过' if ok else '存疑'} {nw}x{nh} 覆盖={cov*100:.1f}% 密度={fillr:.2f}",
          flush=True)
    return ok


def make_thumb_sheet(files: list[Path], dst: Path, cell: int = 256) -> None:
    """64px 缩略图测试：图标最终就显示在 64px，64px 下认不出就等于没做"""
    from PIL import Image
    import numpy as np
    n = len(files)
    rows = 2
    big = Image.new("RGBA", (cell * n, cell * rows), (30, 30, 38, 255))
    for i, f in enumerate(files):
        im = Image.open(f).convert("RGBA")
        r = i // (n // rows + 1)
        c = i - r * (n // rows + 1)
        big.paste(im, (c * cell, r * cell), im)
    t = big.resize((big.width // 4, big.height // 4), Image.LANCZOS)
    out = Image.new("RGBA", (t.width, t.height * 2 + 12), (20, 20, 26, 255))
    out.paste(t, (0, 0), t)
    # 灰度缩略图（看明度层级是否拉得开）
    g = t.convert("L").convert("RGBA")
    out.paste(g, (0, t.height + 12), g)
    out.convert("RGB").save(dst)
    print("缩略图测试: ", dst)


if __name__ == "__main__":
    only = sys.argv[1].split(",") if len(sys.argv) > 1 else None
    ROOT.mkdir(parents=True, exist_ok=True)
    SKILL_DIR.mkdir(parents=True, exist_ok=True)
    RELIC_DIR.mkdir(parents=True, exist_ok=True)
    made, failed = [], []

    for kind, table, outdir in (("skill", SKILLS, SKILL_DIR), ("relic", RELICS, RELIC_DIR)):
        for name, desc in table.items():
            if only and name not in only:
                continue
            fname = f"icon_{kind}_{name}.png"
            dst = outdir / fname
            if dst.exists():
                made.append(str(dst))
                continue
            print(f"\n[{fname}]", flush=True)
            raw = ROOT / f"{kind}_{name}_raw.png"
            vivid = name in VIVID
            p = f"{desc}, {VIVID_STYLE if vivid else ICON_STYLE}. Avoid: {NEG_ICON}"
            ok = False
            for att in range(3):
                if fetch_icon(p, raw) and cut_icon(raw, dst, vivid):
                    ok = True
                    break
                print(f"  [{fname}] 第{att+1}轮未过，重试", flush=True)
                raw.unlink(missing_ok=True)
                dst.unlink(missing_ok=True)
                time.sleep(3)
            (made if ok else failed).append(str(dst) if ok else fname)

    print(f"\n===== 成功 {len(made)} / 失败 {len(failed)} =====", flush=True)
    for f in failed:
        print("  FAIL:", f)
    # 缩略图测试（只在有产出时）
    if made:
        make_thumb_sheet([Path(x) for x in made], ROOT / "thumb_all.png")