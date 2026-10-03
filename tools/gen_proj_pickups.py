#!/usr/bin/env python3
"""
投射物 + 拾取物素材生成

规格依据（先读代码再定规格，不猜）：
  投射物 proj_*.png —— projectile.gd 每帧 `sprite.rotation = dir.angle()`
      => 只需生成「朝右」单帧，方向由代码旋转。生成双方向 = 纯浪费。
      实际引用5 种：arrow / axe / bullet / meteor / orb
  拾取物 —— gem.gd 三档 xp 是三张独立贴图、且无scale 字段
      => 必须程序化缩放同一颗宝石，形状才一致（分别生成会得到三颗不同的宝石）
      chest.gd 有 scale 1.6，stairs.gd 有 scale 2.0 => 贴图本体画小一点即可

尺寸：投射物 128（高速小体，贴图太大反而糊），拾取物 256
管线：与角色/杂兵同族（纯黑底 -> rembg -> harmonize 色彩归一）
"""
import os
import sys
import time
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).parent))
import gen_enemies as GE  # noqa: E402  复用 fetch / cutout / harmonize

# 细长形（箭/斧）按宽度归一时，占画布宽度的目标值。
# 0.82 是实测校准：低于此值箭在128px 贴图里细到看不见，高于此值会顶到画布边缘且旋转时露角。
LONG_FILL = 0.82

# 密度阈值分档：斧头有镂空（斧刃与柄之间是空的）、箭是细杆，
# 这类物件天生稀疏，用 0.35 统一阈值会连续误杀（实测斧头 3 轮全被判失败）。
# 细长形 0.24（箭实测 0.42、斧实测 0.29~0.34）；团块形保持 0.35。
FILL_MIN_LONG = 0.24
FILL_MIN_BULK = 0.35

# 像素：投射物 | 拾取物
ROOT = Path(os.environ.get("DUNGEON_ROOT", Path(__file__).resolve().parent.parent))
ROOT = Path("/tmp/pickups")
PROJ_DIR = (ROOT / "assets/sprites/fx/projectiles")
PICK_DIR = (ROOT / "assets/sprites/pickups")

# 投射物 128（引擎里 scale 1.0，实际就是贴图像素大小）
P_SIZE = 128
# 拾取物 256（引擎会缩到 0.6~2.0，原生大一点更清晰）
K_SIZE = 256

# 投射物不该套用角色的明度目标——投射物要在暗 tile 上「看得见」，
# 用角色明度 0.255 会得到一团黑影（实测箭头像素明度仅 0.106，拉到 0.255 也发闷）。
# 投射物目标是 0.40：仍比场景亮，但不被后期压成剪影。收藏品宝石同理。
SAVED_SAT, SAVED_LUM = GE.TARGET_SAT, GE.TARGET_LUM


def proj_tone(enabled: bool = True) -> None:
    """切换到投射物/拾取物的明度目标（投射物必须亮，否则玩家看不清弹道）"""
    if enabled:
        GE.TARGET_LUM = 0.40
        GE.TARGET_SAT = 0.22
        GE.HIGHLIGHT_CAP = 0.78
    else:
        GE.TARGET_SAT, GE.TARGET_LUM = SAVED_SAT, SAVED_LUM
        GE.HIGHLIGHT_CAP = 0.62

# 投射物风格锚点：与角色同族的暗调手绘，但更简洁——小尺寸下细节只会变噪点
PROJ_STYLE = ("detailed hand-painted 2D dark fantasy game art, thick painterly texture, "
              "heavy dark ink outline, dark moody dungeon lighting from above, "
              "restrained desaturated muted palette, bright readable core with dark edges, "
              "single object fully inside frame, centered with wide margin, "
              "solid pure black background, NO background scenery, NO ground shadow, "
              "NO text, NO watermark, "
              "NOT pixel art, NO flat color, NO cartoon outline, NO photorealistic, "
              "NOT glossy plastic, NOT neon glow overload")

# 投射物一律朝右（代码按 dir.angle() 旋转，生成朝向 = 0°）
FACING = "pointing to the RIGHT, horizontal, tip on the right side"

PROJ = {
    "arrow": dict(
        desc=("a single long wooden arrow with a steel arrowhead and grey feather fletching, "
              "shaft fully visible end to end, " + FACING),
        fill=0.86),
    "axe": dict(
        desc=("a single heavy throwing axe with a curved steel blade and a wrapped leather handle, "
              "blade edge on the right side, " + FACING),
        fill=0.82),
    "bullet": dict(
        desc=("a single round glowing arcane energy orb projectile, dark metal rim with a "
              "dull amber glowing core, compact and dense, " + FACING),
        fill=0.70),
    "meteor": dict(
        desc=("a single burning fireball meteor, dark charred rock core with dull orange "
              "molten cracks, short tapering flame tail on the left side, " + FACING),
        fill=0.88),
    "orb": dict(
        desc=("a single floating dark magic orb, matte charcoal sphere with dull violet "
              "glowing veins across its surface, compact and dense, " + FACING),
        fill=0.70),
}

PICK = {
    "gem": dict(
        desc=("a single faceted teardrop-cut gemstone, dark crimson red ruby with deep "
              "internal glow, sharp clean facet edges, thick dark outline, "
              "viewed straight on, resting flat, no rotation"),
        fill=0.62),
    "coin": dict(
        desc=("a single round gold coin lying flat on the ground, dull aged gold with a dark "
              "embossed skull emblem in the centre, thick dark rim, viewed from "
              "slightly above at a low angle"),
        fill=0.72),
    "chest": dict(
        desc=("a single closed wooden treasure chest with dark iron banding and a rusty metal "
              "lock plate, lid shut, viewed from a slightly high three-quarter angle"),
        fill=0.86),
    "portal_stairs": dict(
        desc=("a single ancient stone staircase portal going up into darkness, worn grey "
              "stone steps with chipped edges, faint warm golden glow rising from the "
              "top of the stairs, viewed straight from the front"),
        fill=0.90),
}

NEG_EXTRA = ("motion blur, motion trail, multiple objects, duplicate, "
             "strong glow bloom, lens flare, sparks, particles, "
             "arrow pointing left, arrow pointing down, vertical")


def fetch_to(prompt: str, dst: Path, size: int, ref: Path | None = None) -> bool:
    """复用 gen_enemies.fetch，但指定尺寸"""
    if dst.exists() and dst.stat().st_size > 1000:
        print(f"  [跳过] {dst.name}", flush=True)
        return True
    dst.parent.mkdir(parents=True, exist_ok=True)
    from PIL import Image
    import base64 as _b64
    kw = dict(prompt=prompt + ". Avoid: " + NEG_EXTRA, size=f"{size}x{size}",
              model=GE.MODEL)
    if ref is not None:
        kw["input_images"] = ["data:image/png;base64," +
                              _b64.b64encode(ref.read_bytes()).decode()]
    for t in range(3):
        try:
            r = GE.ac.generate_image(**kw)
            url = r["data"][0]["url"]
            os.system(f'curl -sL --max-time 120 -o "{dst}" "{url}" 2>/dev/null')
            if not dst.exists() or dst.stat().st_size < 800:
                raise RuntimeError("download failed")
            im = Image.open(dst)
            if im.size != (size, size):
                im.convert("RGB").resize((size, size), Image.LANCZOS).save(dst)
            print(f"  [{dst.name}] 第{t+1}次 {dst.stat().st_size//1024}KB", flush=True)
            return True
        except Exception as e:
            print(f"  [{dst.name}] 第{t+1}次失败: {type(e).__name__}: {str(e)[:100]}", flush=True)
            time.sleep(4)
    return False


def cut_gen(src: Path, dst: Path, size: int, fill: float) -> bool:
    """抠图+ 色彩归一 + 归一尺寸

    归一基准按形状分档：
      - 细长形（箭）必须按「占画布宽度」算。按高度算的话，一支横箭的高度只有几像素，
        结果箭头在 128px 贴图里缩成一条 20px 的细线（实测覆盖仅 4.8%），玩家根本看不见。
      - 团块形（弹/宝石/箱）按「占画布高度」算。
    """
    from PIL import Image
    tmp = ROOT / (src.stem + "_cut.png")
    if not GE.cutout(src, tmp):
        print(f"  [{dst.name}] 抠图失败（覆盖过低）", flush=True)
        return False
    im = Image.open(tmp).convert("RGBA")
    bbox = im.getbbox()
    if not bbox:
        print(f"  [{dst.name}] 空图", flush=True)
        return False
    sub = im.crop(bbox)
    long_shape = sub.width >= sub.height * 2.0     # 细长形
    if long_shape:
        sc = (size * LONG_FILL) / max(sub.width, 1)   # 细长形按宽度占满
    else:
        sc = (size * fill) / max(sub.height, 1)
        if sub.width * sc > size * 0.94:
            sc = (size * 0.94) / max(sub.width, 1)
    nw, nh = max(1, int(sub.width * sc)), max(1, int(sub.height * sc))
    sub = sub.resize((nw, nh), Image.LANCZOS)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.paste(sub, ((size - nw) // 2, (size - nh) // 2))
    canvas.save(dst)
    a = np.array(canvas)[:, :, 3] > 40
    cov = a.sum() / a.size
    ys, xs = np.where(a)
    fillr = a.sum() / ((xs.max() - xs.min() + 1) * (ys.max() - ys.min() + 1))
    # 细长形的面积阈值不能套 0.02（一支放大后的箭覆盖仍可能< 4%）
    min_cov = 0.012 if long_shape else 0.02
    min_fill = FILL_MIN_LONG if long_shape else FILL_MIN_BULK
    ok = min_cov < cov < 0.70 and fillr > min_fill
    print(f"  [{dst.name}] QC {'通过' if ok else '存疑'} {size}x{size} {nw}x{nh}"
          f"{' 细长' if long_shape else ''} 覆盖={cov*100:.1f}% 密度={fillr:.2f}"
          f"(阈值{min_fill:.2f})", flush=True)
    return ok


def make_gem_tiers(base_cut: Path, canvas: int = K_SIZE) -> None:
    """三档宝石 = 同一颗的程序化缩放（分别生成会得到三颗不同的宝石，形状不一致）

    坑：必须先从裁切结果重新按目标档位归一再贴进画布，不能直接缩放已归一的成品图——
    成品图里主体已占满 384 画布，再放大 100% 会溢出并被裁掉底部（实测 gem_l bbox 310px > 画布）。
    """
    from PIL import Image
    im = Image.open(base_cut).convert("RGBA")
    bbox = im.getbbox()
    if not bbox:
        print("  [gem] 基准图为空", flush=True)
        return
    base = im.crop(bbox)                 # 纯主体，无画布留白
    for tier, f in (("s", 0.34), ("m", 0.52), ("l", 0.78)):
        # 目标：小档 34%、中档 52%、大档 78% 画布高度 —— 三档一眼可分辨
        nh = max(1, int(canvas * f))
        nw = max(1, int(base.width * nh / max(base.height, 1)))
        if nw > canvas * 0.92:            # 宽宝石要按宽收
            nw = int(canvas * 0.92)
            nh = max(1, int(base.height * nw / max(base.width, 1)))
        r = base.resize((nw, nh), Image.LANCZOS)
        c = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
        c.paste(r, ((canvas - nw) // 2, (canvas - nh) // 2), r)
        out = PICK_DIR / f"gem_{tier}.png"
        c.save(out)
        a = np.array(c)[:, :, 3] > 40
        ys, xs = np.where(a)
        assert xs.max() < canvas and ys.max() < canvas, f"{tier} 溢出画布"
        print(f"  [{out.name}] 占画布高 {f:.0%} -> {nw}x{nh} 覆盖={a.sum()/a.size*100:.1f}%",
              flush=True)


if __name__ == "__main__":
    only = sys.argv[1].split(",") if len(sys.argv) > 1 else None
    ROOT.mkdir(parents=True, exist_ok=True)
    PROJ_DIR.mkdir(parents=True, exist_ok=True)
    PICK_DIR.mkdir(parents=True, exist_ok=True)
    proj_tone(True)          # 投射物/拾取物用更亮的明度目标（玩法可读性优先）
    made, failed = [], []

    # ---------- 投射物 ----------
    for pid, cfg in PROJ.items():
        if only and pid not in only and "proj" not in only:
            continue
        print(f"\n[proj_{pid}]", flush=True)
        raw = ROOT / f"{pid}_raw.png"
        dst = PROJ_DIR / f"proj_{pid}.png"
        if dst.exists():
            made.append(str(dst))
            continue
        p = f"{cfg['desc']}, {PROJ_STYLE}"
        ok = False
        for att in range(3):
            if fetch_to(p, raw, P_SIZE) and cut_gen(raw, dst, P_SIZE, cfg["fill"]):
                ok = True
                break
            print(f"  [proj_{pid}] 第{att+1}轮未过，重试", flush=True)
            raw.unlink(missing_ok=True)
            dst.unlink(missing_ok=True)
            time.sleep(3)
        (made if ok else failed).append(str(dst) if ok else f"proj_{pid}")

    # ---------- 拾取物 ----------
    for kid, cfg in PICK.items():
        if only and kid not in only and "pick" not in only:
            continue
        print(f"\n[pickup {kid}]", flush=True)
        raw = ROOT / f"{kid}_raw.png"
        if kid == "gem":
            gem_dst = PICK_DIR / "gem_s.png"
            if gem_dst.exists() and (PICK_DIR / "gem_l.png").exists():
                made.append(str(gem_dst))
                continue
            p = f"{cfg['desc']}, {PROJ_STYLE}"
            ok = False
            for att in range(3):
                # 只传raw：cut_gen 内部会调GE.cutout。传 cut 会二次抠图。
                if fetch_to(p, raw, K_SIZE) and cut_gen(raw, gem_dst, K_SIZE, cfg["fill"]):
                    ok = True
                    break
                print(f"  [gem] 第{att+1}轮未过，重试", flush=True)
                raw.unlink(missing_ok=True)
                gem_dst.unlink(missing_ok=True)
                time.sleep(3)
            if ok:
                # gem 的裁切结果落在 gem_raw_cut.png（cut_gen 的临时产物命名规则）
                make_gem_tiers(ROOT / "gem_raw_cut.png")
                made += [str(PICK_DIR / f"gem_{t}.png") for t in ("s", "m", "l")]
            else:
                failed.append("gem")
            continue

        dst = PICK_DIR / f"{kid}.png"
        if dst.exists():
            made.append(str(dst))
            continue
        p = f"{cfg['desc']}, {PROJ_STYLE}"
        ok = False
        for att in range(3):
            if fetch_to(p, raw, K_SIZE) and cut_gen(raw, dst, K_SIZE, cfg["fill"]):
                ok = True
                break
            print(f"  [{kid}] 第{att+1}轮未过，重试", flush=True)
            raw.unlink(missing_ok=True)
            dst.unlink(missing_ok=True)
            time.sleep(3)
        (made if ok else failed).append(str(dst) if ok else kid)

    print(f"\n===== 成功 {len(made)} / 失败 {len(failed)} =====", flush=True)
    for f in failed:
        print("  FAIL:", f)