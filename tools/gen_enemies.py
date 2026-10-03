#!/usr/bin/env python3
"""
杂兵素材生成（txt2img 单帧路线）

管线分工：行走/攻击循环动画才用视频抽帧；杂兵/Boss/特效/图标/tile 走单帧路线。

规格: 7 种 × 4 帧（idle 00/01 + move 00/01）= 28 张，256x256 透明底
敌人: bat(蝙蝠) brute(蛮兽) exploder(自爆怪) gargoyle(石像鬼)
      skeleton(骷髅) slime(史莱姆) spitter(喷吐怪)

铁律:
  - 纯黑底生成 -> rembg 抠图（透明通道提示词不可信）
  - 同一敌人的 idle/move 必须用 img2img 从同一基准帧派生，保证形象一致
  - 风格锚点与角色逐字复用，保持同一世界
  - 剪影可读性优先：敌人要在 10% 缩略图下也能认出是什么
"""
import base64
import json
import os
import sys
import time
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))  # 让同目录的 agnes_path 可导入
from agnes_path import require_agnes_client  # noqa: E402
ac = require_agnes_client()  # 跨仓库依赖，缺失时给出修复指引

ROOT = Path("/tmp/enemys")
DST = (ROOT / "assets/sprites/enemies")
SIZE = 384                             # 与角色画布一致（角色 384，敌人 256 会天生显小）
MODEL = "agnes-image-2.1-flash"
GEN_SIZE = 256                         # 生图尺寸：模型出 256 质量更稳，再归一到 384

# ---------------- 风格锚点（与角色一致，逐字复用） ----------------
# 实测角色 char_aila_front_walk_00：饱和 0.185 / 明度 0.241（暗调厚涂写实）
# 敌人必须落在同一区间，否则同画面出现两套东西（拼凑感）。
STYLE = ("detailed hand-painted 2D dark fantasy game art, thick painterly brush texture, "
         "visible brush strokes on every surface, heavy dark ink outline, "
         "three-quarter top-down game view, clean crisp readable silhouette, "
         "restrained desaturated muted palette, dark moody dungeon lighting from above, "
         "deep shadows in the crevices, "
         "NOT pixel art, NO flat color, NO cartoon outline, NO photorealistic, "
         "NO glossy plastic toy look, NO candy colours, NO glassy jelly sheen, "
         "NO cute, NO chibi, NO big shiny eyes")

# 角色实测色相锚点（暗暖褐+ 冷暗绿/蓝），敌人向该区间收敛
TARGET_SAT = 0.185         # 角色实测饱和度
TARGET_LUM = 0.255         # 略高于角色，因敌人需从暗背景里跳出来
# 环境光：角色身处暖褐火把光环境。敌人必须落在同一光线里，否则纯色怪物会「跳出来」。
# 暗部加暖褐反弹光 + 高光压缩，是让不同物种同族的关键（不是单纯降饱和）。
AMBIENT = np.array([0.42, 0.26, 0.19])   # 暖褐环境色
AMBIENT_MIX = 0.30                        # 暗部混入比例
HIGHLIGHT_CAP = 0.62                      # 高光上限（压掉糖果塑料高光）

BASE_TAIL = ("single creature, full body fully inside frame, centered with margin, "
             "solid pure black background, NO background scenery, NO ground plane, "
             "NO shadow on ground, NO text, NO watermark, "
             "same three-quarter top-down game camera as the player character")

# ---------------- 敌人设定 ----------------
ENEMIES = {
    "slime": dict(
        cn="史莱姆", scale=1.0,
        desc=("a translucent gelatinous slime creature, round blob body, "
              "glossy semi-transparent green-cyan jelly with inner glow, "
              "two dark round eyes, simple wide smiling mouth, "
              "wobbly jelly surface with bubbles inside"),
        move="the slime body stretched and wobbling, squashed lower and wider"),
    "bat": dict(
        cn="蝙蝠", scale=1.0,
        desc=("a small flying bat creature, dark charcoal grey fur, "
              "large leathery wings spread wide, pointed ears, "
              "small piercing red eyes, tiny fangs, clawed feet"),
        move="wings flapping up and down, body hovering in the air"),
    "skeleton": dict(
        cn="骷髅", scale=1.0,
        desc=("a bare-bones undead skeleton warrior, NO cloth NO hood NO cloak covering the body, "
              "fully exposed pale bone skull with visible teeth and hollow eye sockets glowing cold blue, "
              "exposed spine ribs pelvis and thin bare arm bones and leg bones clearly visible, "
              "only a small tattered loincloth at the waist, "
              "one broken rusty sword held in its right bony hand, "
              "thin bony fingers, gaunt skeletal frame"),
        move="sword arm swinging forward, bare bone legs striding"),
    "spitter": dict(
        cn="喷吐怪", scale=1.0,
        desc=("a bloated venomous toad-like creature, sickly green-purple mottled skin, "
              "wide gaping mouth full of sharp teeth, bulging toxic yellow eyes, "
              "pustules and warts on its back"),
        move="mouth opening wide, throat swelling with glowing green bile"),
    "exploder": dict(
        cn="自爆怪", scale=1.0,
        desc=("a round unstable bomb-like creature covered in dark cracked crust, "
              "glowing molten orange cracks all over its body, "
              "short stubby legs, a lit fuse on top of its head, "
              "menacing small eyes"),
        move="body inflating and glowing brighter, cracks spreading wider"),
    "brute": dict(
        cn="蛮兽", scale=1.35,
        desc=("a hulking massive brute beast, huge muscular arms, "
              "thick grey-brown shaggy fur, heavy iron spiked shoulder armor, "
              "small head sunk between shoulders, tiny eyes, "
              "massive fists, broad chest"),
        move="fist raised high to slam down, heavy body leaning forward"),
    "gargoyle": dict(
        cn="石像鬼", scale=1.15,
        desc=("a menacing stone gargoyle guardian, grey weathered granite skin, "
              "cracked stone body with moss patches, "
              "broad bat-like stone wings folded, horned head, "
              "glowing amber eyes, clawed stone feet"),
        move="stone wings unfurling, heavy clawed arm reaching forward"),
}

NEG = ("multiple creatures, extra limbs, mutated, blurry, low detail, "
       "pixel art, flat color, cartoon outline, text, watermark, signature, "
       "human face, human body, living flesh skin, "
       "hooded cloak robe, hood, cowl, fully clothed figure, "
       "cropped, out of frame, busy background, "
       "scenery, gradient background, border, frame")


def data_uri(p: Path) -> str:
    return "data:image/png;base64," + base64.b64encode(p.read_bytes()).decode()


def fetch(prompt: str, dst: Path, model: str = MODEL, ref: Path | None = None) -> bool:
    if dst.exists():
        print(f"  [跳过] {dst.name}", flush=True)
        return True
    dst.parent.mkdir(parents=True, exist_ok=True)
    kw = dict(prompt=prompt + ". Avoid: " + NEG, size=f"{GEN_SIZE}x{GEN_SIZE}", model=model)
    if ref is not None:
        kw["input_images"] = [data_uri(ref)]
    for t in range(3):
        try:
            r = ac.generate_image(**kw)
            url = r["data"][0]["url"]
            os.system(f'curl -sL --max-time 120 -o "{dst}" "{url}" 2>/dev/null')
            if not dst.exists() or dst.stat().st_size < 1000:
                raise RuntimeError("download failed")
            from PIL import Image
            im = Image.open(dst)
            if im.size != (GEN_SIZE, GEN_SIZE):
                im.convert("RGB").resize((GEN_SIZE, GEN_SIZE), Image.LANCZOS).save(dst)
            print(f"  [{dst.name}] 第{t+1}次 {dst.stat().st_size//1024}KB", flush=True)
            return True
        except Exception as e:
            print(f"  [{dst.name}] 第{t+1}次失败: {type(e).__name__}: {str(e)[:110]}", flush=True)
            time.sleep(4)
    return False


def decontaminate(arr):
    """剥离黑底污染：黑底生成图抠图后边缘会留一圈暗描边/半透明脏边。

    两道：
      1) 暗边剥离——只剥离「紧贴透明区外沿」的暗像素。深处暗部（骷髅眼窝、蛮兽毛）
         不受影响，否则暗色怪会被啃掉一层皮。
      2) alpha 收缩 1px——去掉最外圈半透明晕，避免在浅色 tile 上显出灰边。

    坑：判断必须在 alpha>0 区域做，且收缩只对半透明层做，实心区不动（否则主体变瘦）。
    """
    from PIL import Image as _I, ImageFilter as _IF
    a = arr[:, :, 3].astype(np.int16)
    rgb = arr[:, :, :3]
    lum = rgb.mean(axis=2)
    # 外沿邻域：alpha>0 的区域向透明侧扩2px，落在环带里的才算「边缘」
    solid = (a > 0).astype(np.uint8) * 255
    edge = np.zeros_like(solid)
    for _ in range(2):
        edge = np.maximum(edge, np.array(_I.fromarray(solid).filter(_IF.MaxFilter(3))))
    edge = (edge > 0) & (solid == 0)
    # 1) 暗边：低亮度 + 半透明 + 紧贴外沿 = 黑底溢出
    dark = (lum < 52) & (a > 6) & (a < 250) & edge
    a[dark] = 0
    # 2) alpha 收缩：仅收缩半透明晕（实心区保持不动）
    soft = ((a > 6) & (a < 250)).astype(np.uint8) * 255
    if soft.any():
        eroded = np.array(_I.fromarray(soft).filter(_IF.MinFilter(3)))
        # 只把被侵蚀掉的部分按比例减掉（保持过渡柔和，不做硬二值）
        a = np.where(soft > 0, np.minimum(a, a * 0.55 + eroded.astype(np.int16) * 0.45), a).astype(np.int16)
    a[a < 12] = 0
    arr[:, :, 3] = np.clip(a, 0, 255)
    return arr


def harmonize(im):
    """把生成图收敛到角色实测的色彩区间（饱和 0.185 / 明度 0.255）

    AI 生图即使提示词写对了，饱和和明度也会飘。提示词管构图，这个函数管色彩，
    两道锁都要有——否则同画面会出现两套东西。

    坑：所有统计必须在 alpha 掩膜内做。透明区 RGB=0，算进去会把均值拉低近一半，
    归一系数随之偏小，结果 QC 读出明度仍是原来的 2 倍。
    """
    from PIL import Image
    import numpy as np
    a = np.array(im).astype(np.float32)
    m = a[:, :, 3] > 60
    if m.sum() < 50:
        return im
    rgb = a[:, :, :3].copy()
    cur_sat = float((rgb.max(axis=2) - rgb.min(axis=2))[m].mean()) / 255.0
    cur_lum = float(rgb[m].mean()) / 255.0
    # 1) 饱和度归一（限幅，避免把该有的血/毒绿也抽掉）——以主体灰度为中心缩放色差
    s_ratio = max(0.45, min(1.6, TARGET_SAT / max(cur_sat, 0.01)))
    gray = rgb.mean(axis=2, keepdims=True)
    rgb = gray + (rgb - gray) * s_ratio
    # 1b) 原始饱和度极低时（纯灰主体，如荆棘暴君实测 0.023），
    #乘系数无论怎么夹都拉不到目标（0.32/0.023=13.9，被 1.6 上限锁死）。
    #     这类「整体就该暗、但需要一块识别色」的主体：整体抬到中饱和，
    #     识别色靠提示词的高饱和区域承担，不靠整体拉满。
    if cur_sat < 0.08 and TARGET_SAT >= 0.30:
        rgb = gray + (rgb - gray) * 2.2
    # 2) 明度归一到目标区间（同样限幅，别把暗色怪洗成灰）
    # 上限 2.6 而非 1.9：Boss（墨骸实测原始明度仅 0.11）用 1.9 上限只能拉到 0.21，
    # 永远够不到目标 0.28 —— Boss 是玩家注意力焦点，比杂兵更不能暗。
    l_ratio = max(0.55, min(2.6, TARGET_LUM / max(cur_lum, 0.01)))
    rgb = rgb * l_ratio
    # 3) 高光压缩：把塑料/糖果亮斑按比例压回上限，保留体积感但去掉塑料感
    over = np.maximum(0.0, (rgb - HIGHLIGHT_CAP * 255) / (255 - HIGHLIGHT_CAP * 255))
    rgb = rgb - over * (255 - HIGHLIGHT_CAP * 255)
    # 4) 环境光统一：暗部混入暖褐反弹光。纯色怪物（鲜绿/亮紫）不混这一手就会在暗tile 上跳出来
    lum3 = rgb.mean(axis=2, keepdims=True) / 255.0
    dark_w = np.clip(1.0 - lum3 * 1.9, 0.0, 1.0) * AMBIENT_MIX
    rgb = rgb * (1.0 - dark_w) + AMBIENT[None, None, :] * 255.0 * dark_w
    # 5) 边缘再压一档饱和，避免混完环境光又艳起来
    g = rgb.mean(axis=2, keepdims=True)
    rgb = g + (rgb - g) * 0.92
    rgb = np.clip(rgb, 0, 255)
    out = a.copy()
    out[:, :, :3] = rgb
    new_sat = float((rgb.max(axis=2) - rgb.min(axis=2))[m].mean()) / 255
    print(f"    风格归一 饱和 {cur_sat:.3f}->{new_sat:.3f} "
          f"明度 {cur_lum:.3f}->{float(rgb[m].mean())/255:.3f}", flush=True)
    return Image.fromarray(out.astype('uint8'), "RGBA")


def cutout(src: Path, dst: Path) -> bool:
    from PIL import Image
    import numpy as np
    from rembg import remove, new_session
    im = Image.open(src).convert("RGB")
    res = remove(im, session=new_session("u2netp"))
    if not isinstance(res, Image.Image):
        import io
        res = Image.open(io.BytesIO(res))
    arr = np.array(res.convert("RGBA"))
    arr = decontaminate(arr)
    out = Image.fromarray(arr)
    out = harmonize(out)                       # 色彩归一（顺序：抠图后、缩放前）
    # 居中 + 按高度归一（敌人应占画布约 82%，留碰撞box余量）
    bbox = out.getbbox()
    if bbox:
        sub = out.crop(bbox)
        sc = (SIZE * 0.82) / max(sub.height, 1)
        if sub.width * sc > SIZE * 0.92:
            sc = (SIZE * 0.92) / max(sub.width, 1)
        nw, nh = max(1, int(sub.width * sc)), max(1, int(sub.height * sc))
        sub = sub.resize((nw, nh), Image.LANCZOS)
        canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
        canvas.paste(sub, ((SIZE - nw) // 2, SIZE - nh))  # 底部对齐（fly 类由代码做悬浮）
        out = canvas
    out.save(dst)
    cov = float((np.array(out)[:, :, 3] > 8).sum()) / (SIZE * SIZE)
    print(f"  [{dst.name}] 抠图 覆盖={cov*100:.1f}%", flush=True)
    return cov > 0.05


def qc(p: Path) -> bool:
    """质检：覆盖率合理 + 剪影可读（密度） + 与角色色彩同族"""
    from PIL import Image
    import numpy as np
    im = Image.open(p).convert("RGBA")
    arr = np.array(im)
    a = arr[:, :, 3] > 40
    if a.sum() == 0:
        print(f"  [{p.name}] QC FAIL: 空", flush=True)
        return False
    ys, xs = np.where(a)
    fill = a.sum() / ((xs.max() - xs.min() + 1) * (ys.max() - ys.min() + 1))
    cover = a.sum() / a.size
    rgb = arr[:, :, :3][a].astype(np.float32)
    sat = float((rgb.max(axis=1) - rgb.min(axis=1)).mean()) / 255
    lum = float(rgb.mean()) / 255
    # 同族阈值：饱和不超角色 1.8 倍、明度落在 0.15~0.38（角色实测 0.185/0.241）
    tone_ok = sat < TARGET_SAT * 1.8 and 0.15 <= lum <= 0.38
    # 密度阈值按兵种分档：骷髅/蝙蝠这类细枝型天然稀疏（0.28~0.40），
    # 用统一 0.30 会把正确素材误判为失败（实测连续 3 轮被误杀）。
    min_fill = cfg_minfill(p.name)
    ok = 0.05 < cover < 0.72 and fill > min_fill and tone_ok
    print(f"  [{p.name}] QC {'通过' if ok else '存疑'} 覆盖={cover*100:.1f}% 密度={fill:.2f}"
          f"(阈值{min_fill:.2f}) 饱和={sat:.3f} 明度={lum:.3f}"
          f"{'' if tone_ok else ' [色彩跑偏]'}", flush=True)
    return ok


def cfg_minfill(name: str) -> float:
    """细枝型生物（骷髅/蝙蝠）密度阈值放宽，遮挡型（史莱姆/自爆）保持严格"""
    thin = ("skeleton", "bat")
    return 0.24 if any(t in name for t in thin) else 0.30


if __name__ == "__main__":
    only = sys.argv[1].split(",") if len(sys.argv) > 1 else None
    ROOT.mkdir(parents=True, exist_ok=True)
    DST.mkdir(parents=True, exist_ok=True)
    made, failed = [], []

    for eid, cfg in ENEMIES.items():
        if only and eid not in only:
            continue
        print(f"\n[{eid} {cfg['cn']}]", flush=True)
        base = ROOT / f"{eid}_base.png"        # 基准帧（黑底）
        cut = ROOT / f"{eid}_base_cut.png"    # 抠图后（作为 img2img 输入）
        p = f"{cfg['desc']}, {BASE_TAIL}, {STYLE}"

        # 基准帧最多 3 轮：QC 不过就重生成（不放弃，否则一种怪缺失 = 引擎崩）
        ok_base = False
        for attempt in range(3):
            if fetch(p, base):
                if cutout(base, cut) and qc(cut):
                    ok_base = True
                    break
            print(f"  [{eid}] 基准帧第{attempt + 1}轮未过，重试", flush=True)
            base.unlink(missing_ok=True)
            cut.unlink(missing_ok=True)
            time.sleep(3)
        if not ok_base:
            failed.append(f"{eid}/base")
            continue

        # 2) idle_00 = 基准帧抠图；idle_01 / move_00 / move_01 用 img2img 从基准帧派生（锁形象）
        idle00 = DST / f"enemy_{eid}_idle_00.png"
        if not idle00.exists():
            idle00.write_bytes(cut.read_bytes())
        made.append(str(idle00))

        variants = [("idle_01", f"{cfg['desc']}, subtle idle breathing motion, "
                                 f"slightly shifted pose, {BASE_TAIL}, {STYLE}"),
                    ("move_00", f"{cfg['desc']}, {cfg['move']}, {BASE_TAIL}, {STYLE}"),
                    ("move_01", f"{cfg['desc']}, {cfg['move']}, different phase of the "
                                 f"same motion, {BASE_TAIL}, {STYLE}")]
        for tag, vp in variants:
            raw = ROOT / f"{eid}_{tag}_raw.png"
            d = DST / f"enemy_{eid}_{tag}.png"
            if d.exists():
                made.append(str(d))
                continue
            # img2img 从基准帧派生，锁形象；每张都过 QC（派生也会漂）
            if fetch(vp, raw, ref=cut):
                if cutout(raw, d):
                    if qc(d):
                        made.append(str(d))
                    else:
                        d.unlink(missing_ok=True)
                        failed.append(f"{eid}/{tag}/qc")
                else:
                    failed.append(f"{eid}/{tag}")
            else:
                failed.append(f"{eid}/{tag}")

    print(f"\n===== 成功 {len(made)} / 失败 {len(failed)} =====", flush=True)
    for f in failed:
        print("  FAIL:", f)
    (ROOT / "summary.json").write_text(json.dumps(
        {"made": made, "failed": failed}, ensure_ascii=False, indent=2))
