#!/usr/bin/env python3
"""
地图瓦片生成（txt2img 单帧路线，不用视频）

规格:
  6 主题 × 5 张 = 30 张：floor_a / floor_b / floor_c / wall / side
  + 5 张 decal（cracks/rubble/bones/blood/moss）
  + pillar + flame
  共 37 张，192x192（正方形，场景按 1:1 铺）

铁律（来自 STYLE_GUIDE 与实测教训）:
  - tile 必须「无缝可平铺」：提示词必须加 seamless tileable texture,
    NO grid lines, NOT a tileset atlas, NO borders, NO edge frame
  - 背景纯黑或纯色，便于 rembg（decals/pillar/flame 需要透明底）
  - 风格锚点逐字复用，与角色保持同一世界（精细化手绘 + 俯视 3/4 视角）
  - tile 不需要抠图（本身是方形贴图），decals/decor 需要 rembg
"""
import base64
import json
import os
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))  # 让同目录的 agnes_path 可导入
from agnes_path import require_agnes_client  # noqa: E402
ac = require_agnes_client()  # 跨仓库依赖，缺失时给出修复指引

ROOT = Path("/tmp/tilegen")
SIZE = 192
MODEL = "agnes-image-2.1-flash"

# ---------------- 风格锚点（逐字复用，禁止改写） ----------------
STYLE = ("detailed hand-painted 2D fantasy game texture, top-down three-quarter "
         "top-down game view, crisp clean edges, no pixel art, no flat color, "
         "no cartoon outline, consistent with dark fantasy dungeon art")

SEAMLESS = ("seamless tileable texture, perfectly repeating pattern, "
            "NO grid lines, NOT a tileset atlas, NO borders, NO edge frame, "
            "NO text, NO watermark, fills the entire square frame edge to edge")

THEMES = {
    "corridor": ("ancient stone dungeon corridor floor, fitted grey granite flagstones "
                 "with mortar gaps, worn edges, faint dust"),
    "forge":    ("molten slag forge floor, cracked dark basalt with glowing orange "
                 "lava veins in the cracks, soot and ember scorch marks"),
    "ice":      ("frozen cave floor, pale blue ice sheets with deep cracks, frost "
                 "and snow patches, pale cyan sheen"),
    "tomb":     ("crypt tomb floor, dark weathered stone slabs covered in carved "
                 "runes and faded mosaic, dust and small bones"),
    "thorn":    ("overgrown forest floor, mossy earth with tangled roots and fallen "
                 "leaves, patches of grass and small thorns"),
    "void":     ("void altar floor, obsidian black stone with violet glowing cracks, "
                 "floating dust motes, arcane circle fragments"),
}

PART = {
    "wall":  "a seamless dungeon WALL texture, stacked stone bricks mortared "
             "together, weathered and chipped",
    "side":  "a seamless dungeon WALL SIDE texture, stacked stone bricks seen from "
             "a low three-quarter angle, weathered, darker than the wall top",
}

# decal / decor（需透明底）
TRANSPARENT = [
    ("decals/decal_cracks", "a cluster of thin hairline cracks spreading across the "
     "ground, dark cracks on nothing, cracks decal, isolated, no background"),
    ("decals/decal_rubble", "a small pile of broken stone rubble and shattered brick "
     "fragments, rubble decal, isolated, no background"),
    ("decals/decal_bones", "a small scattered pile of old bones and a cracked skull, "
     "bone decal, isolated, no background"),
    ("decals/decal_blood", "an irregular dark blood splatter stain on the ground, "
     "blood decal, isolated, no background"),
    ("decals/decal_moss", "a patch of green moss growing on stone, moss decal, "
     "isolated, no background"),
    ("decor/pillar", "an ancient carved stone dungeon pillar, full column with base "
     "and capital, vertical, isolated, no background"),
    ("decor/flame", "a single small flickering orange-yellow flame with soft glow, "
     "torch flame, isolated, no background"),
    ("decals/decal_rune", "a glowing arcane rune circle carved on the ground, "
     "intricate circular geometric glyph, violet glowing lines, "
     "rune decal, isolated, no background"),
]

# terrain 图层（draw_polygon UV 采样，大面积平铺）
TERRAIN = {
    "rubble":  "scattered stone rubble and broken brick debris field, top-down",
    "lava":    "molten lava cracks network, glowing orange magma veins, top-down",
    "ice":     "cracked ice sheet with deep fissures, pale blue, top-down",
    "mire":    "murky swampy mud with algae and wet patches, top-down",
    "bramble": "dense tangled thorny brambles and thicket, top-down",
    "rift":    "dark dimensional rift with violet glowing energy, top-down",
}


def data_uri(p: Path) -> str:
    return "data:image/png;base64," + base64.b64encode(p.read_bytes()).decode()


def download(url: str, dst: Path) -> bool:
    dst.parent.mkdir(parents=True, exist_ok=True)
    os.system(f'curl -sL --max-time 120 -o "{dst}" "{url}" 2>/dev/null')
    return dst.exists() and dst.stat().st_size > 1000


def gen(prompt: str, dst: Path, tries: int = 3) -> bool:
    if dst.exists():
        print(f"  [跳过] {dst.name}", flush=True)
        return True
    for t in range(tries):
        try:
            r = ac.generate_image(prompt=prompt, size=f"{SIZE}x{SIZE}", model=MODEL)
            u = r["data"][0]["url"]
            if not download(u, dst):
                raise RuntimeError("download failed")
            # API 可能返回非请求尺寸，统一缩放到 SIZE
            from PIL import Image as _I
            _im = _I.open(dst)
            if _im.size != (SIZE, SIZE):
                _im.convert("RGB").resize((SIZE, SIZE), _I.LANCZOS).save(dst)
            print(f"  [{dst.name}] 第{t+1}次 {dst.stat().st_size//1024}KB", flush=True)
            return True
        except Exception as e:
            print(f"  [{dst.name}] 第{t+1}次失败: {type(e).__name__}: {str(e)[:120]}", flush=True)
            time.sleep(4)
    return False


def cutout(src: Path, dst: Path) -> bool:
    """透明底素材抠图 + 黑边抑制"""
    from PIL import Image
    import numpy as np
    try:
        from rembg import remove, new_session
    except Exception as e:
        print(f"  rembg 不可用: {e}", flush=True)
        return False
    im = Image.open(src).convert("RGB")
    res = remove(im, session=new_session("u2netp"))
    if not isinstance(res, Image.Image):
        import io
        res = Image.open(io.BytesIO(res))
    arr = np.array(res.convert("RGBA"))
    a = arr[:, :, 3].astype(np.int16)
    lum = arr[:, :, :3].max(axis=2).astype(np.int16)
    arr[:, :, 3][(a > 8) & (a < 220) & (lum < 55)] = 0
    arr[:, :, 3][a < 20] = 0
    dst.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(arr).save(dst)
    cov = float((arr[:, :, 3] > 8).sum()) / arr.shape[0] / arr.shape[1]
    print(f"  [{dst.name}] 抠图 alpha覆盖={cov*100:.1f}%", flush=True)
    return cov > 0.05


def qc_tile(p: Path) -> bool:
    """
    tile 质检：1) 不能有网格线（检测规整的暗直线）
               2) 四边颜色应接近（无缝平铺的必要条件）
    """
    from PIL import Image
    import numpy as np
    a = np.array(Image.open(p).convert("RGB")).astype(float)
    h, w, _ = a.shape
    edges = [a[0, :, :].mean(axis=1), a[h - 1, :, :].mean(axis=1),
             a[:, 0, :].mean(axis=1), a[:, w - 1, :].mean(axis=1)]
    # 相邻边差分小 = 无边框
    tl, tr, bl, br = a[0, 0], a[0, w - 1], a[h - 1, 0], a[h - 1, w - 1]
    corner_gap = float(np.mean([np.linalg.norm(tl - tr), np.linalg.norm(tl - bl)]))
    # 网格线检测：行/列均值的周期性剧烈起伏
    row_mean = a.mean(axis=(1, 2))
    col_mean = a.mean(axis=(0, 2))
    ripple = float(row_mean.max() - row_mean.min()) + float(col_mean.max() - col_mean.min())
    ok = corner_gap < 60 and ripple < 55
    print(f"  [{p.name}] 质检 {'通过' if ok else '存疑'}: 角差={corner_gap:.0f} 纹理起伏={ripple:.0f}", flush=True)
    return ok


if __name__ == "__main__":
    which = sys.argv[1] if len(sys.argv) > 1 else "all"
    ROOT.mkdir(parents=True, exist_ok=True)
    (ROOT / "raw").mkdir(exist_ok=True)
    only = which.split(",") if which != "all" else None
    made, failed = [], []

    # 1) 主题 tile
    for tname, tdesc in THEMES.items():
        if only and tname not in only:
            continue
        d = ROOT / "tiles" / tname
        print(f"\n[{tname}]", flush=True)
        for v in ["a", "b", "c"]:
            dst = d / f"tile_{tname}_floor_{v}.png"
            prompt = (f"{tdesc}, {SEAMLESS}, {STYLE}, top-down view, "
                      f"fills the whole square frame, flat even lighting, no shadows cast, "
                      f"no objects, pure surface texture only")
            (made if gen(prompt, dst) else failed).append(str(dst))
        for part, pdesc in PART.items():
            dst = d / f"tile_{tname}_{part}.png"
            prompt = f"{pdesc}, {SEAMLESS}, {STYLE}, fills the whole square frame, even lighting"
            (made if gen(prompt, dst) else failed).append(str(dst))
            qc_tile(dst)

    # 2) decals / decor（透明底）
    if not only or "decal" in only or set(only) & set(THEMES) == set(only) and not only:
        pass
    if not only or any(o in ("all", "decal") for o in only) or set(only) & set(THEMES.keys()):
        print("\n[decals/decor]", flush=True)
        for rel, desc in TRANSPARENT:
            name = Path(rel).name
            raw = ROOT / "raw" / f"{name}.png"
            prompt = (f"{desc}, {STYLE}, centered, fully inside frame with margin, "
                      f"solid pure black background, NO background scenery, no shadow on ground")
            if gen(prompt, raw):
                dst = ROOT / "tiles" / Path(rel).parent / f"{name}.png"
                (made if cutout(raw, dst) else failed).append(str(dst))
            else:
                failed.append(rel)

    # 3) terrain 图层（webp，大面积 UV 平铺）
    if not only or "terrain" in only or any(o in ("all", "decal") for o in only):
        print("\n[terrain 图层]", flush=True)
        for kind, desc in TERRAIN.items():
            webp = ROOT / "tiles" / "terrain" / f"tex_{kind}.webp"
            png = ROOT / "raw" / f"tex_{kind}.png"
            if webp.exists():
                print(f"  [跳过] tex_{kind}", flush=True)
                made.append(str(webp))
                continue
            prompt = (f"{desc}, {SEAMLESS}, {STYLE}, "
                      f"large uniform surface, even flat lighting, no shadows, "
                      f"fills the whole square frame, pure surface texture only")
            if gen(prompt, png):
                from PIL import Image as _I
                webp.parent.mkdir(parents=True, exist_ok=True)
                _I.open(png).convert("RGB").save(webp, "WEBP", quality=88)
                made.append(str(webp))
                print(f"  [tex_{kind}.webp] 转换完成", flush=True)
            else:
                failed.append(kind)

    print(f"\n===== 汇总: 成功 {len(made)} / 失败 {len(failed)} =====", flush=True)
    if failed:
        for f in failed:
            print("  FAIL:", f)
    (ROOT / "summary.json").write_text(json.dumps(
        {"made": made, "failed": failed}, ensure_ascii=False, indent=2))
