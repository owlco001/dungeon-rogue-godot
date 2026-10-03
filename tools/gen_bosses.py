#!/usr/bin/env python3
"""
Boss 立绘生成（txt2img 单帧路线）

规格依据（先读代码，不猜）：
  boss.gd: _sprite.texture = load(tex)，_base_scale = boss_def["scale"]（全部 1.0）
  boss.gd: _sprite.flip_h = to.x < 0.0   => 只需一个朝右的（正面朝向）立绘
  boss.gd: _enter_phase 里 tex_key = "tex"+str(p) => phase2/3 用独立贴图
        墨骸是三阶段 Boss，三张必须【同主体逐阶段恶化】，不能各生成一个新怪
  boss.gd: 攻击范围圈radius 130~150 => Boss 视觉体量必须明显大于杂兵（杂兵碰撞 22）
        杂兵视觉高311~423px（引擎内），Boss 取 512 画布、占画布 84% ≈ 430px 视觉高，
        视觉体量约为蛮兽的 1.4 倍，符合「每5 层一只」的分量

8 张：colossus / batking / forgemaster / widow_a / widow_b / thorntyrant /
    mohei_phase1 / mohei_phase2 / mohei_phase3
（widow 双生共 9 个文件，其中 mohei 三阶段）

管线与杂兵同源：纯黑底 txt2img -> rembg 抠图 -> harmonize 色彩归一
"""
import os
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import gen_enemies as GE# noqa: E402

ROOT = Path(os.environ.get("DUNGEON_ROOT", Path(__file__).resolve().parent.parent))
ROOT = Path("/tmp/bosses")
DST = (ROOT / "assets/sprites/bosses")
SIZE = 640# 比杂兵(384)大一档，配合 scale=1.0 直接体现 Boss 体量
# 实测：SIZE=512 时 Boss 视觉高 430px，和蛮兽（引擎内 422px）几乎一样大—— 压不住场。
# Boss 攻击范围圈 130~150 半径 = 杂兵碰撞(22) 的 6 倍，视觉体量必须匹配，
# 否则玩家看到「大范围技能」打在「一样大的怪」身上，说服力全无。
# 640 画布 -> 视觉高约 540px ≈ 蛮兽的 1.28 倍，视觉上明确是Boss 级别。
FILL = 0.84# 占画布比例，比杂兵 0.82略高（Boss 要压场）
GEN_SIZE = 384             # 模型出 384 质量更稳，再归一到 640

# Boss 色彩比杂兵略亮（要压得住暗场景，且是玩家注意力焦点），但不能到糖果感
GE.TARGET_SAT = 0.20
GE.TARGET_LUM = 0.28
GE.HIGHLIGHT_CAP = 0.66

# 风格锚点：与角色/杂兵同族，但更沉重、更压迫
BOSS_STYLE = ("detailed hand-painted 2D dark fantasy boss creature art, thick painterly brush texture, "
              "heavy dark ink outline, three-quarter top-down game view, "
              "clean readable silhouette, large imposing heavy-set proportions, "
              "dark moody dungeon lighting from above, deep shadows, "
              "restrained desaturated muted palette with one strong accent colour, "
              "single creature, full body fully inside frame, centered with margin, "
              "solid pure black background, NO background scenery, NO ground plane, "
              "NO shadow on ground, NO text, NO watermark, "
              "NOT pixel art, NO flat color, NO cartoon outline, NO photorealistic, "
              "NOT glossy plastic, NOT cute, NOT chibi")

NEG = ("multiple creatures, extra limbs, mutated, blurry, low detail, "
       "human face, human body, living flesh skin, small creature, tiny, "
       "cropped, out of frame, busy background, scenery, gradient background, "
       "text, watermark, signature, border, frame")

# Boss 定位偏正面朝右（flip_h 靠代码镜像，左右不能各出一张）
FACING = "facing the viewer at a slight three-quarter angle, body oriented toward the right"

BOSSES = {
    # ---- L5 石颅巨像：石头巨人，纯力量型 ----
    "colossus": dict(
        cn="石颅巨像", desc=(
            "a colossal towering stone giant idol made of cracked grey granite blocks, "
            "a huge square stone head with no face except two deep glowing amber eye slits, "
            "enormous slab arms resting on the ground, thick stone fists, "
            "heavy stone legs, moss patches in the cracks, "
            "intimidating and ancient, " + FACING),
        # 石头偏灰，靠琥珀色眼缝做识别色
        vivid=True),
    # ---- L10 噬影蝠王：飞行蝠王 ----
    "batking": dict(
        cn="噬影蝠王", desc=(
            "a giant evil bat king, huge charcoal grey leathery wings fully spread wide "
            "spanning far out, thick furry black body, large pointed ears, "
            "a broad fanged snout, small piercing bright red eyes, "
            "clawed feet, regal crown-like horn ridges on the head, "
            "menacing and dominant, " + FACING),
        vivid=True),
    # ---- L15 熔渣铸造者：火焰锻造巨人 ----
    "forgemaster": dict(
        cn="熔渣铸造者", desc=(
            "a hulking blacksmith golem forged from dark iron armor plates, "
            "glowing molten orange lava cracks between the armor seams, "
            "a huge square furnace chest with an open furnace door glowing bright orange, "
            "thick arms with giant steel hammer fused into the right hand, "
            "dull orange heat glow from the visor slit, heavy slag dripping, " + FACING),
        vivid=True),
    # ---- L20 双生亡语者 A/B：必须同族成对（同一物种的两种形态） ----
    "widow_a": dict(
        cn="亡语者A", desc=(
            "a tall gaunt ghostly widow creature, pale grey translucent skin, "
            "long tattered black shroud hanging down covering the whole body, "
            "a veiled pale face with hollow dark eye sockets, "
            "skeletal thin arms with long fingers, "
            "weeping black tears, cold eerie, " + FACING),
        # 幽灵要发光眼窝做识别
        vivid=True, pair="widow"),
    "widow_b": dict(
        cn="亡语者B", desc=(
            "the twin sister form of the same ghostly widow creature, "
            "taller and more distorted than the first one, "
            "pale grey translucent skin, long tattered black shroud with torn ragged edges, "
            "one side of the veil torn away revealing a cracked pale face, "
            "one skeletal arm unnaturally long, wider black tear stains, "
            "cold eerie, " + FACING),
        vivid=True, pair="widow", img2img_from="widow_a"),
    # ---- L25荆棘暴君：植物荆棘 ----
    "thorntyrant": dict(
        cn="荆棘暴君", desc=(
            "a huge tyrant creature made of twisted dark thorny vines and brambles, "
            "a vaguely humanoid shape but made entirely of thick jagged thorns, "
            "a broad chest of woven branches, long thorn claws, "
            "BRIGHT glowing toxic green sap veins running through the black thorns, "
            "bright acid-green glowing eyes deep inside the thorn mass, "
            "dry leaves and dead vines hanging, " + FACING),
        # 荆棘是纯黑木+灰白，饱和仅 0.084 在暗场景里太沉。绿汁是识别色，必须够亮。
        vivid=True, sat=0.34, lum=0.30),
    # ---- L30 墨骸三阶段：同一主体逐阶段恶化，必须靠 img2img 派生 ----
    "mohei_phase1": dict(
        cn="墨骸·初", desc=(
            "a towering void demon lord, body made of dense swirling black ink smoke "
            "held together by a dark armored shell, "
            "a smooth featureless dark mask face with two thin horizontal eye slits, "
            "long tattered black cape dripping ink, "
            "clawed hands with black smoke trailing from the fingers, "
            "calm and restrained, " + FACING),
        vivid=True, phase=1),
    "mohei_phase2": dict(
        cn="墨骸·中", desc=(
            "the SAME void demon lord from the calm form, now cracking apart, "
            "the dark mask face split down the middle revealing a glowing violet core, "
            "armor shell fracturing with bright violet light pouring out of the cracks, "
            "black ink smoke boiling outward, cape tattered further, "
            "one horn broken off, more violent and unstable, " + FACING),
        vivid=True, phase=2, img2img_from="mohei_phase1"),
    "mohei_phase3": dict(
        cn="墨骸·终", desc=(
            "the SAME void demon lord, final enraged form, "
            "half the dark mask face destroyed, one eye replaced by a blazing violet flame, "
            "a huge cracked violet core exposed in the chest cavity, "
            "massive jagged black spikes erupting from the back and arms, "
            "dissolving into violent swirling ink smoke at the edges, "
            "unstable and apocalyptic, " + FACING),
        vivid=True, phase=3, img2img_from="mohei_phase2"),
}

# 分阶段墨骸要「更亮更紫」—— 阶段越高威胁越大，视觉上要能看出来
PHASE_TONE = {
    1: dict(sat=0.20, lum=0.28),
    2: dict(sat=0.28, lum=0.32),
    3: dict(sat=0.34, lum=0.36),
}


def fetch_boss(prompt: str, dst: Path, ref: Path | None = None) -> bool:
    from PIL import Image
    import base64 as _b64
    if dst.exists() and dst.stat().st_size > 1000:
        print(f"  [跳过] {dst.name}", flush=True)
        return True
    dst.parent.mkdir(parents=True, exist_ok=True)
    kw = dict(prompt=prompt, size=f"{GEN_SIZE}x{GEN_SIZE}", model=GE.MODEL)
    if ref is not None:
        kw["input_images"] = ["data:image/png;base64," +
                              _b64.b64encode(ref.read_bytes()).decode()]
    for t in range(3):
        try:
            r = GE.ac.generate_image(**kw)
            url = r["data"][0]["url"]
            os.system(f'curl -sL --max-time 150 -o "{dst}" "{url}" 2>/dev/null')
            if not dst.exists() or dst.stat().st_size < 1200:
                raise RuntimeError("download failed")
            im = Image.open(dst)
            if im.size != (GEN_SIZE, GEN_SIZE):
                im.convert("RGB").resize((GEN_SIZE, GEN_SIZE), Image.LANCZOS).save(dst)
            print(f"  [{dst.name}] 第{t+1}次 {dst.stat().st_size//1024}KB", flush=True)
            return True
        except Exception as e:
            print(f"  [{dst.name}] 第{t+1}次失败: {type(e).__name__}: {str(e)[:100]}", flush=True)
            time.sleep(5)
    return False


def cut_boss(src: Path, dst: Path, phase: int | None, cfg: dict | None = None) -> bool:
    """抠图 + 色彩归一 + 占画布 84%

    色彩目标优先级：cfg 里的单项覆盖 > phase 表 > 模块级默认。
    单项覆盖用于「整体就该暗但识别色要跳」的 Boss（如荆棘暴君：黑木主体+绿汁）。
    """
    from PIL import Image
    import numpy as np
    cfg = cfg or {}
    GE.TARGET_SAT = cfg.get("sat", PHASE_TONE[phase]["sat"] if phase else 0.20)
    GE.TARGET_LUM = cfg.get("lum", PHASE_TONE[phase]["lum"] if phase else 0.28)
    if cfg.get("vivid"):
        # Boss 的识别色（琥珀眼/红眼/橙炉火/紫核）是玩家判断威胁的线索，
        # 压成灰钢就等于白做（实测荆棘暴君饱和 0.084，暗场景里沉底）。
        GE.TARGET_SAT = max(GE.TARGET_SAT, 0.32)
    tmp = ROOT / (src.stem + "_cut.png")
    if not GE.cutout(src, tmp):
        print(f"  [{dst.name}] 抠图失败", flush=True)
        return False
    im = Image.open(tmp).convert("RGBA")
    bbox = im.getbbox()
    if not bbox:
        print(f"  [{dst.name}] 空图", flush=True)
        return False
    sub = im.crop(bbox)
    sc = (SIZE * FILL) / max(sub.height, 1)
    if sub.width * sc > SIZE * 0.96:
        sc = (SIZE * 0.96) / max(sub.width, 1)
    nw, nh = max(1, int(sub.width * sc)), max(1, int(sub.height * sc))
    sub = sub.resize((nw, nh), Image.LANCZOS)
    canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    # 底部留 8% 余量，不贴边。
    # 坑：贴底（余量 0~2px）在 boss.gd 的 sprite.rotation 生效时会露出画布底边，
    # 表现为 Boss 转动时脚下闪出一条横线。杂兵是纯左右+轻微 squash 不旋转，所以没暴露。
    bot = int(SIZE * 0.92)
    top = bot - nh
    if top < 0:                      # 极端情况：主体太高则整体上移
        shift = -top
        top += shift
    canvas.paste(sub, ((SIZE - nw) // 2, top))    # 底部对齐，视觉重心低 = 压迫感
    canvas.save(dst)
    a = np.array(canvas)[:, :, 3] > 40
    cov = a.sum() / a.size
    ys, xs = np.where(a)
    fillr = a.sum() / ((xs.max() - xs.min() + 1) * (ys.max() - ys.min() + 1))
    # Boss 体量下限：低于画布 40% 说明生成得太瘦小，压不住场
    ok = 0.16 < cov < 0.80 and fillr > 0.30
    print(f"  [{dst.name}] QC {'通过' if ok else '存疑'} {SIZE}x{SIZE} {nw}x{nh} "
          f"视觉高={nh} 覆盖={cov*100:.1f}% 密度={fillr:.2f}", flush=True)
    return ok


if __name__ == "__main__":
    only = sys.argv[1].split(",") if len(sys.argv) > 1 else None
    ROOT.mkdir(parents=True, exist_ok=True)
    DST.mkdir(parents=True, exist_ok=True)
    made, failed = [], []

    for bid, cfg in BOSSES.items():
        if only and bid not in only:
            continue
        print(f"\n[boss {bid} {cfg['cn']}]", flush=True)
        raw = ROOT / f"{bid}_raw.png"
        dst = DST / f"boss_{bid}.png"
        if dst.exists():
            made.append(str(dst))
            continue
        ref = None
        if cfg.get("img2img_from"):
            rp = DST / f"boss_{cfg['img2img_from']}.png"
            if rp.exists():
                ref = rp
                print(f"  img2img 派生自 {rp.name}", flush=True)
        p = f"{cfg['desc']}, {BOSS_STYLE}. Avoid: {NEG}"
        ok = False
        for att in range(3):
            if fetch_boss(p, raw, ref) and cut_boss(raw, dst, cfg.get("phase"), cfg):
                ok = True
                break
            print(f"  [{bid}] 第{att+1}轮未过，重试", flush=True)
            raw.unlink(missing_ok=True)
            dst.unlink(missing_ok=True)
            time.sleep(4)
        (made if ok else failed).append(str(dst) if ok else bid)

    print(f"\n===== 成功 {len(made)} / 失败 {len(failed)} =====", flush=True)
    for f in failed:
        print("  FAIL:", f)