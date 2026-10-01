#!/usr/bin/env python3
"""角色尺寸归一化：修复不同方向忽大忽小。

原理：
- batong/mofei：20 张 RAW 全在。按方向测 idle 包围盒高度，以最大者为基准，
  缩放各方向全部帧到统一尺度，再算全角色统一 union bbox，裁剪到 128。
- aila：pilot 8 帧（128px 成品，尺度已统一）+ walk_extra 8 张 RAW。
  用 down_walk 成品平均高度校准 RAW 缩放比，转到 pilot 尺度空间再统一 bbox。
串行 rembg（u2net），防 OOM。用 venv python 运行。
"""
import gc
from pathlib import Path
from PIL import Image
import numpy as np

BASE = Path(__file__).resolve().parent.parent
ASSETS = BASE / "assets"
STAGING = ASSETS / ".staging"
VENV_PY = Path.home() / "workspace" / ".rbg-venv" / "bin" / "python"


def alpha_bbox(img):
    a = np.array(img)[:, :, 3]
    ys, xs = np.where(a > 10)
    if len(ys) == 0:
        return None
    return (int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max()))


def finalize(cutout, union_bb, size=128):
    x0, y0, x1, y1 = union_bb
    pad = int(max(x1 - x0, y1 - y0) * 0.06) + 4
    x0, y0 = max(0, x0 - pad), max(0, y0 - pad)
    x1, y1 = min(cutout.size[0], x1 + pad), min(cutout.size[1], y1 + pad)
    crop = cutout.crop((x0, y0, x1, y1))
    side = max(crop.size)
    sq = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    sq.paste(crop, ((side - crop.size[0]) // 2, (side - crop.size[1]) // 2), crop)
    return sq.resize((size, size), Image.LANCZOS)


def main():
    from rembg import new_session, remove
    session = new_session("u2net")

    def rembg_cutout(path):
        img = Image.open(path).convert("RGBA")
        out = remove(img, session=session)
        del img
        gc.collect()
        return out

    # ============ batong / mofei：全 RAW ============
    for char in ["batong", "mofei"]:
        print(f"== {char}")
        rawdir = STAGING / char / "raw"
        # 按方向分组
        by_dir = {}
        for d in ["down", "up", "left", "right"]:
            idle = rawdir / f"char_{char}_{d}_idle_00.png"
            walks = sorted(rawdir.glob(f"char_{char}_{d}_walk_*.png"))
            by_dir[d] = {"idle": idle, "walks": walks}
        # rembg + 测 idle 高度
        idle_h = {}
        cutouts = {}  # (d, kind, idx) -> img
        for d, g in by_dir.items():
            co = rembg_cutout(g["idle"])
            cutouts[(d, "idle", 0)] = co
            bb = alpha_bbox(co)
            idle_h[d] = bb[3] - bb[1]
            for i, w in enumerate(g["walks"]):
                cutouts[(d, "walk", i)] = rembg_cutout(w)
        print("  idle heights:", idle_h)
        href = max(idle_h.values())
        # 缩放各方向到统一尺度
        scaled = {}
        for (d, kind, i), co in cutouts.items():
            s = href / idle_h[d]
            if abs(s - 1.0) > 0.001:
                nw, nh = int(co.size[0] * s), int(co.size[1] * s)
                co = co.resize((nw, nh), Image.LANCZOS)
            scaled[(d, kind, i)] = co
        print("  scale factors:", {d: round(href / h, 3) for d, h in idle_h.items()})
        # 统一 union bbox
        ux0, uy0, ux1, uy1 = None, None, None, None
        for co in scaled.values():
            bb = alpha_bbox(co)
            ux0 = bb[0] if ux0 is None else min(ux0, bb[0])
            uy0 = bb[1] if uy0 is None else min(uy0, bb[1])
            ux1 = bb[2] if ux1 is None else max(ux1, bb[2])
            uy1 = bb[3] if uy1 is None else max(uy1, bb[3])
        union = (ux0, uy0, ux1, uy1)
        print("  union bbox:", union)
        # 落盘
        outdir = ASSETS / "sprites" / "characters" / char
        for (d, kind, i), co in scaled.items():
            fin = finalize(co, union)
            if kind == "idle":
                dest = outdir / f"char_{char}_{d}_idle_00.png"
            else:
                dest = outdir / f"char_{char}_{d}_walk_{i:02d}.png"
            fin.save(dest)
            assert dest.stat().st_size > 0
        print(f"  saved 20 frames to {outdir}")
        for co in scaled.values():
            del co
        gc.collect()

    # ============ aila：pilot 成品 + walk_extra RAW ============
    print("== aila")
    char = "aila"
    outdir = ASSETS / "sprites" / "characters" / char
    # pilot 8 帧（已在 pilot 尺度）
    pilot_files = []
    for d in ["down", "up", "left", "right"]:
        pilot_files.append(outdir / f"char_{char}_{d}_idle_00.png")
    for i in range(4):
        pilot_files.append(outdir / f"char_{char}_down_walk_{i:02d}.png")
    pilot_imgs = [Image.open(f).convert("RGBA") for f in pilot_files]
    # down_walk 平均高度（校准目标）
    hp = float(np.mean([alpha_bbox(im)[3] - alpha_bbox(im)[1]
                        for im in pilot_imgs[4:8]]))
    print("  pilot down_walk avg h:", round(hp, 1))
    # walk_extra 8 RAW
    extra = {}
    for d in ["up", "left"]:
        for i in range(4):
            rp = STAGING / "aila_walk_extra" / "raw" / f"{d}_walk_{i:02d}.png"
            extra[(d, i)] = rembg_cutout(rp)
    hw_raw = float(np.mean([alpha_bbox(co)[3] - alpha_bbox(co)[1]
                            for co in extra.values()]))
    print("  extra raw avg h:", round(hw_raw, 1))
    s = hp / hw_raw
    print("  scale factor:", round(s, 3))
    scaled_extra = {}
    for k, co in extra.items():
        nw, nh = int(co.size[0] * s), int(co.size[1] * s)
        scaled_extra[k] = co.resize((nw, nh), Image.LANCZOS)
    # 统一 union bbox（pilot 空间，128px）
    all_imgs = pilot_imgs + list(scaled_extra.values())
    ux0, uy0, ux1, uy1 = None, None, None, None
    for co in all_imgs:
        bb = alpha_bbox(co)
        ux0 = bb[0] if ux0 is None else min(ux0, bb[0])
        uy0 = bb[1] if uy0 is None else min(uy0, bb[1])
        ux1 = bb[2] if ux1 is None else max(ux1, bb[2])
        uy1 = bb[3] if uy1 is None else max(uy1, bb[3])
    union = (ux0, uy0, ux1, uy1)
    print("  union bbox:", union)
    # 落盘 pilot 8 帧（重裁剪统一）
    for f, im in zip(pilot_files, pilot_imgs):
        finalize(im, union).save(f)
    # 落盘 up/left walk
    for d in ["up", "left"]:
        for i in range(4):
            dest = outdir / f"char_{char}_{d}_walk_{i:02d}.png"
            finalize(scaled_extra[(d, i)], union).save(dest)
    # right walk = mirror left walk（重做镜像，保证一致）
    for i in range(4):
        src = Image.open(outdir / f"char_{char}_left_walk_{i:02d}.png")
        src.transpose(Image.FLIP_LEFT_RIGHT).save(
            outdir / f"char_{char}_right_walk_{i:02d}.png")
    print("  saved 20 aila frames (right = mirror left)")
    print("DONE")


if __name__ == "__main__":
    main()
