#!/usr/bin/env python3
"""
技能特效贴图生成（9 张）—— 与角色/杂兵/Boss 完全不同的管线

规格依据（先读代码）：
  player.gd / fx.gd 每处都是同一个模式：
      sp.texture = load(fx_xxx.png)
      sp.modulate = Color(...)          <- 颜色由代码染色
      sp.material = FX._additive_mat()  <- 加法混合！
      sp.scale = Vector2.ONE (或 target_s * 0.5)

由此推出三条硬约束（与前面所有素材相反）：
  1) 加法混合下「黑色 = 透明」。所以必须【黑底发光形状】，不能抠成透明底，
     抠图反而错——抠完只剩形状轮廓，丢了柔光衰减。
  2) modulate 由代码染色 => 素材必须是【白光/中性灰】，带自身颜色会被代码色相覆盖成脏色。
  3) 素材是【居中径向对称】形状（技能特效几乎都是圆形爆发/环形冲击波），
     不需要朝向，只需要居中 + 画布留同等边距（否则缩放时中心偏移）。

尺寸 256：代码有 scale=1.0 和 scale=target_s*0.5 两种，用 256 兼顾。
"""
import os
import sys
import time
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).parent))
import gen_enemies as GE# noqa: E402  只为复用 ac / SIZE 之外的东西

ROOT = Path(os.environ.get("DUNGEON_ROOT", Path(__file__).resolve().parent.parent))
ROOT = Path("/tmp/fx")
DST = (ROOT / "assets/sprites/fx")
SIZE = 256

# 特效不做harmonize（不用 GE.cutout）—— 加法混合素材需要保留黑色作为透明区。
# 色彩目标改由「必须接近中性灰」保证：通道最大值与最小值差越小越中性。
NEUTRAL_TOL = 0.22

# 风格锚点：能量特效。关键是"能量感"不是"物件感"。
#
# 踩过的坑：第一版写「glowing white hot core」+「bright inner filled disc」，
# 生成出来是两块死白色实心圆盘 —— 加法混合下 fx * modulate 直接把背景烧成纯白，
# modulate 的染色（橙/紫/蓝）全被吃光，通道极差 0.004 说明素材是纯白，
#染色必然失效。
# 正确形态：黑底 + 稀疏的亮线/亮环/亮丝 + 少量柔光。
# 加法混合下「少而亮」= 能量感；「多而亮」= 白斑。
FX_STYLE = ("game skill visual effect sprite, radial symmetrical energy effect, "
            "sparse thin bright energy filaments and rings on black, "
            "concentric thin shockwave RINGS with dark gaps between them, "
            "thin bright radiating spikes, wispy translucent smoke wisps, "
            "mostly BLACK background with dark empty space, "
            "only thin bright lines and small bright nodes, "
            "centered perfectly in the frame with equal margin, "
            "the majority of the frame must be pure black, "
            "NEVER a solid filled bright disc, NEVER a solid white blob, "
            "NOT an object, NOT a prop, NOT a creature, NOT a weapon, "
            "NOT colored, NOT rainbow, NOT orange, NOT purple, NOT blue, "
            "NOT pixel art, NOT photorealistic, NO text, NO watermark, "
            "NO background scenery, NO ground, NO border frame")

NEG = ("object, prop, weapon, creature, character, hand, sword, shield, "
       "solid filled disc, solid white blob, filled circle, opaque white mass, "
       "solid shape, bright background, white background, "
       "colored, orange, purple, blue, green, red, rainbow, multicolored, "
       "solid blob, opaque fill, textured surface, photograph, logo, "
       "text, letters, watermark, border, frame, square edge, rectangular outline")

# 9 张：文件名 -> 形态描述（全部中性白，靠 modulate 染色）
FX = {
    # 箭雨：落地区域警示圈
    "arrow_rain_zone": ("a wide flat circular ground zone marker drawn as THIN BRIGHT RINGS ONLY, "
                        "one thick bright outer ring plus two thinner concentric inner rings "
                        "with dark gaps between them, short radial tick spokes, "
                        "the inside of the circle stays mostly BLACK, "
                        "viewed as a flat circle seen from above"),
    # 圣盾冲击：竖立球形护盾
    "shield_slam": ("a large round dome shield bubble outline, "
                    "a THIN BRIGHT outer rim arc plus sparse thin vertical and horizontal "
                    "energy lines inside forming a dome, dark gaps between the lines, "
                    "vertical barrier standing up, brightest along the bottom edge"),
    # 狂暴战鼓：放射状爆发
    "warcry": ("a violent radial burst, THREE THIN SHOCKWAVE RINGS with wide dark gaps, "
               "sharp jagged energy spikes radiating from a small bright centre node, "
               "the space between rings stays BLACK, wispy smoke streaks between spikes"),
    # 践踏裂纹：地面龟裂
    "stomp_crack": ("a cracked ground impact pattern made of THIN BRANCHING CRACK LINES "
                    "spreading outward from a small bright impact node, "
                    "irregular web of fractured thin lines with BLACK space between them, "
                    "no solid filled area, flat seen from above"),
    # 灵魂虹吸：汇聚漩涡
    "soul_orb": ("a swirling vortex spiral pulling inward, bright spiral arms "
                 "twisting toward a dark bright-rimmed centre, wispy tendrils"),
    # 闪现残影：竖向人形轮廓虚影
    "dash_ghost": ("a vertical humanoid afterimage silhouette, "
                   "translucent glowing outline of a standing figure with faint "
                   "motion streak edges, brightest at the head and shoulders"),
    # 圣盾：护盾包裹
    "holy_shield": ("a protective spherical energy bubble around a small humanoid shape, "
                    "bright rim halo with flowing energy filaments wrapping the figure, "
                    "soft glow filling the sphere"),
    # 时间凝滞：时钟涟漪
    "time_ripple": ("concentric circular ripple rings spreading outward from the centre, "
                    "like a clock face with radial tick marks between the rings, "
                    "a frozen suspended distortion field, clock hand shapes"),
    # 升级光柱
    "levelup": ("a tall vertical light pillar rising upward, "
                "a bright base burst at the bottom with a column of light above it, "
                "rising energy streaks, brightest at the base"),
}


# 需要压掉中心伪影的特效（逐张显式声明，不能自动判别，理由见normalize_fx 内注释）
CENTER_ARTIFACT_SUPPRESS = {"holy_shield"}

# 代码里各特效的 modulate（逐字抄自 scripts/player.gd 与 scripts/fx.gd），
# 用于反算「峰值上限」—— 见 normalize_fx 里的推导。
MODULATE = {
    "arrow_rain_zone": (1.0, 0.9, 0.6, 0.75),
    "shield_slam":     (0.7, 0.9, 1.0, 0.95),
    "warcry":          (1.0, 0.75, 0.35, 0.9),
    "stomp_crack":     (1.0, 0.8, 0.5, 0.95),
    "soul_orb":        (0.7, 0.4, 1.0, 0.9),
    "dash_ghost":      (0.6, 0.9, 1.0, 0.8),
    "holy_shield":     (0.6, 0.9, 1.0, 0.85),
    "time_ripple":     (0.5, 0.8, 1.0, 0.8),
    "levelup":         (1.0, 0.95, 0.7, 0.9),
}
# 实测地板平均明度（corridor floor a/b/c 的均值），用作合成基准
BG_LUM = 0.27


def peak_cap(name: str) -> float:
    """按 modulate 反算素材峰值上限。

    加法混合：out = bg + src * mod * mod.a。src 峰值归一到 1.0 时，
    最亮通道的结果是 bg + 1.0 * max(mod) * mod.a。
    实测 shield_slam = 0.27 + 1.0*1.0*0.95 = 1.22 -> 超出 22%，必然截顶变白，
    实机纯白占比 46%。holy_shield / time_ripple / stomp_crack 同理。

    解法：解出让最亮通道恰好落在 1.0 的 src 峰值，即
        cap = (1.0 - bg) / (max(mod) * mod.a)
    这样最亮通道刚好饱和、其余通道保留色差，染色可辨。
    （不需要 headroom：加法下中心过曝一点是正常的能量核心，
      真正要保住的是衰减区的色相，那部分本来就远低于 1.0。）
    """
    mod = MODULATE.get(name)
    if mod is None:
        return 1.0
    r, g, b, a = mod
    return (1.0 - BG_LUM) / (max(r, g, b) * a)


def fetch_fx(prompt: str, dst: Path) -> bool:
    from PIL import Image
    if dst.exists() and dst.stat().st_size > 800:
        print(f"  [跳过] {dst.name}", flush=True)
        return True
    dst.parent.mkdir(parents=True, exist_ok=True)
    kw = dict(prompt=prompt + ". Avoid: " + NEG, size=f"{SIZE}x{SIZE}", model=GE.MODEL)
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


def normalize_fx(src: Path, dst: Path, name: str = "") -> bool:
    """特效归一：加法混合的关键是「对比度」，不是「总量」。

    踩过的坑（两轮）：
      1) 素材是纯白实心盘 -> 总能量爆表，modulate 染色被吃光
      2) 改成「稀疏亮线」后数值达标（总能量 0.138 / 亮核 1.9%），
         但模拟加法混合仍是白色方块 —— 因为亮区在空间上仍然【连续成片】。
         加法混合是逐像素叠加的，只要一片区域连续发亮就必然饱和，
         和总量多少无关。
    正解：对亮度做伽马拉伸，把中灰压成黑，只留最亮的核心。
         等价于「有能量线的地方很亮，线之间完全是黑的」。
    """
    from PIL import Image
    a = np.array(Image.open(src).convert("RGB")).astype(np.float32)
    lum = a.mean(axis=2) / 255.0
    spread = float((a.max(axis=2) - a.min(axis=2)).mean()) / 255.0
    # 伽马拉伸：把中灰压成黑，只保留最亮的能量线。
    # gamma 不能固定：固定 2.0 对「本就稀疏的细线」会拉伸过头，
    # 实测 time_ripple / soul_orb / dash_ghost 能量被压到 0.013~0.035（阈值 0.02）全灭；
    # 而对「本就成片的连续区域」又不够，会烧白。
    # 改成自适应：原始能量越低（越稀疏），拉伸越轻。
    base_energy = float((lum ** 1.0).mean())
    if base_energy < 0.06:
        gamma = 1.25          # 稀疏素材：轻拉，保留细线
    elif base_energy < 0.12:
        gamma = 1.6
    else:
        gamma = 2.0# 连续成片：重拉，压掉中间灰
    stretched = np.power(lum, gamma)
    # 峰值归一：不是归到 1.0，而是归到 peak_cap(name)——
    # 加法混合下 1.0 会让最亮通道撞顶（实测 shield_slam 撞到 1.22），
    # 导致 modulate 染色被截掉、实机纯白占比 46%。详见 peak_cap()。
    peak = float(stretched.max())
    cap = peak_cap(name)
    if peak > 1e-6:
        stretched = stretched / peak * cap
    # 中心伪影抑制：模型偶尔在画面正中吐一个孤立小符号（实测 holy_shield
    # 中心有个像字母 A 的亮块，中心/外环 = 1.68），加法混合会放大成抢戏亮斑。
    #
    # 踩过的坑：先想用「中心 vs 外环亮度比」自动判别，结果完全判反了——
    #   误伤：soul_orb(比值8.4) / stomp_crack(4.4) / time_ripple(2.4) / dash_ghost(3.0)
    #         全被挖空，soul_orb 球心变黑洞、time_ripple 中心环被压平。
    #   漏判：真正有伪影的 holy_shield(1.68) 反而低于阈值。
    # 原因：中心该多亮完全取决于**形态语义**，不是亮度比。
    #   soul_orb 提示词就写的 "dark bright-rimmed centre"（中心本来就该暗），
    #   stomp_crack 是 "spreading outward from a small bright impact node"（中心就该亮）。
    # 结论：这类语义判断不能靠阈值自动推断，必须逐张显式声明。
    if name in CENTER_ARTIFACT_SUPPRESS:
        h, w = stretched.shape
        cy, cx = h // 2, w // 2
        rw, rh = int(w * 0.13), int(h * 0.13)
        stretched[cy - rh:cy + rh, cx - rw:cx + rw] *= 0.25
        print(f"    · 抑制中心伪影（{name}）", flush=True)
    out_lum = np.clip(stretched * 255.0, 0, 255)
    # 保持中性：灰度化到三通道（代码要用 modulate 上色，素材必须中性）
    out = np.stack([out_lum] * 3, axis=2)
    res = np.concatenate([out, np.full_like(out_lum, 255.0)[:, :, None]], axis=2)

    energy = float(out_lum.mean() / 255.0)
    lit = float((out_lum > 24).mean())
    # 亮核阈值随峰值上限走：cap 现在是 0.77~0.97，固定 128 会误判。
    # 用「相对峰值的 55%」而不是绝对值。
    core = float((stretched > cap * 0.55).mean())
    # 阈值只卡「上界」和「形状」，不卡下界。
    # 理由：加法混合下素材偏暗是可补偿的（代码 FX 用 add * 强度 倍率），
    # 但形态退化（大片过曝 / 几乎没有亮区）是不可补偿的。
    ok = core < 0.22 and 0.008 < energy < 0.22 and 0.015 < lit < 0.55
    Image.fromarray(res.astype('uint8'), "RGBA").save(dst)
    print(f"  [{dst.name}] QC {'通过' if ok else '存疑'} 能量={energy:.3f} 峰值上限={cap:.3f} "
          f"亮核={core*100:.1f}% 发光区={lit*100:.0f}% 极差={spread:.3f}", flush=True)
    return ok


if __name__ == "__main__":
    only = sys.argv[1].split(",") if len(sys.argv) > 1 else None
    ROOT.mkdir(parents=True, exist_ok=True)
    DST.mkdir(parents=True, exist_ok=True)
    made, failed = [], []
    for name, desc in FX.items():
        if only and name not in only:
            continue
        print(f"\n[fx_{name}]", flush=True)
        raw = ROOT / f"{name}_raw.png"
        dst = DST / f"fx_{name}.png"
        if dst.exists():
            made.append(str(dst))
            continue
        p = f"{desc}, {FX_STYLE}"
        ok = False
        for att in range(3):
            if fetch_fx(p, raw) and normalize_fx(raw, dst, name):
                ok = True
                break
            print(f"  [fx_{name}] 第{att+1}轮未过，重试", flush=True)
            raw.unlink(missing_ok=True)
            dst.unlink(missing_ok=True)
            time.sleep(4)
        (made if ok else failed).append(str(dst) if ok else name)
    print(f"\n===== 成功 {len(made)} / 失败 {len(failed)} =====", flush=True)
    for f in failed:
        print("  FAIL:", f)