#!/usr/bin/env python3
"""
按朝向生成角色基准立绘（txt2img，纯黑底便于 rembg）

根因记录: 2026-10-03 四朝向视频实验发现，用「正面基准图」去生成「侧向行走」
视频时，模型会从正面逐步转向侧面来和解指令 —— 这就是转身检测失败的真正原因。
解法: 基准图朝向必须与目标视频朝向一致。
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

OUT = Path(os.environ.get("WALKGEN_ROOT", "/tmp/walkgen")) / "bases"
OUT.mkdir(parents=True, exist_ok=True)

# ---------------- 角色形象配置（按角色 ID 取用） ----------------
# 原实现把 aila 的身份串写死在IDENTITY，2026-10-03 改为按角色取，
# 以便同一条管线给不同角色出基准图（batong 重装造型即新增项）。
IDENTITIES = {
    "aila": (
        "full body female archer warrior, young woman, long dark brown hair, "
        "ornate engraved gold-bronze plate armor with filigree, red scarf and crimson cape, "
        "dark blue embroidered skirt armor, brown leather boots, "
        "holding an ornate glowing golden recurve bow with BOTH hands firmly gripping the bow "
        "handle, the bow is physically connected to her hands, one single nocked arrow resting "
        "on the bowstring, arrow tip pointing forward, bow and arrow form one connected unit, "
        "no floating weapons"
    ),
    # batong：重装·肉盾（game_data.gd: speed 200 / max_hp 170 / weapon whirlwind aoe r150）
    # 2026-10-03 新造型。旧素材是「斗篷+弯刀+瘦削人形」，与定位不符且与 mofei 同图。
    # 造型锚点：宽厚铁甲 + 全包铁盔 + 巨型矩形塔盾 + 双手双刃战斧；去斗篷去蝠翼。
    "batong": (
        "full body heavily armored male bulwark knight, stocky broad muscular build, "
        "wearing full heavy iron plate armor with oversized rounded pauldrons, "
        "a closed iron great helm with NO visible face, thick layered steel plate, "
        "a massive RECTANGULAR TOWER SHIELD strapped to his LEFT arm, "
        "the tower shield is broad and tall, wide enough to cover most of his torso and "
        "clearly visible as a large solid rectangle, iron rim with small warm gold trim, "
        "the axe head is a LARGE DOUBLE-BITTED head with TWO big curved steel blades, "
        "one on each side of the haft, a wide symmetric two-bladed axe head that reads "
        "unmistakably as a double-bladed battle axe, "
        "gripping a heavy DOUBLE-BLADED battle axe with BOTH hands in his right hand, "
        "the axe is physically connected to his hands, one single axe, no floating weapons, "
        "broad shoulders, thick waist, planted heavy stance, "
        "NOT slender, NOT feminine, NO cloak, NO cape, NO bat wings, NO demon wings, "
        "NO exposed face, NO curved sword, NO robe, NO hood, light armor, "
        # v2 实测：同时要求「斧高举过盾」与「斧不与盾重叠」会让模型丢掉塔盾。
        # 故负向里只锁「盾不能消失」与「斧不能残缺」，不再管两者位置关系。
        "NO missing shield, NO shield removed, NO axe hidden behind the shield, "
        "NO tiny axe head, NO cropped weapon"
    ),
    "mofei": (
        "full body dark necromancer sorcerer, lean slender body, "
        "black robe with tattered hem, dark hood, pale glowing eyes, "
        "holding a floating crimson soul orb in one hand"
    ),
}

# 与已有正面基准图 aila_base_cut.png 同一形象设定
IDENTITY = IDENTITIES["aila"]
STYLE = (
    "detailed hand-painted 2D fantasy game art, three-quarter top-down game view, "
    "clean crisp silhouette, isolated single character, "
    "plain pure black background, NO background scenery, NO ground, NO shadow, "
    "NO text, NO watermark, centered with margin, full body fully inside frame, "
    "NOT pixel art, NO flat color, NO cartoon outline, NO photorealistic"
)

# 朝向描述同样按角色区分：VIEWS_ARROW 是 aila（弓手）的原文，
# VIEWS_AXE 是重装持斧角色的对应描述（塔盾在左臂、斧在右手）。
VIEWS = {
    "right": "strict SIDE PROFILE view, facing screen RIGHT, body seen from the side, "
             "profile silhouette, she holds the bow in FRONT of her body and the bow curves "
             "toward screen right, bow arm on the right side, arrow nocked pointing right",
    "left":  "strict SIDE PROFILE view, facing screen LEFT, body seen from the side, "
             "profile silhouette, she holds the bow in FRONT of her body and the bow curves "
             "toward screen left, bow arm on the left side, arrow nocked pointing left",
    "front": "FRONT view facing the camera, body seen from the front, "
             "holding bow at her side, symmetrical stance",
    "back":  "BACK view, back turned toward camera, seen from behind, "
             "face not visible, cape and back armor visible, bow held down at her side, entire silhouette clearly separated from background",
}

# 2026-10-03 修正记录（两轮返工，值得留档）：
#   v1原描述 → 实测宽高比 0.73，塔盾把斧头完全挡住，只露一截斧柄。根因是几何必然：
#     面朝screen RIGHT 时观众看到的是角色左侧身体，塔盾在左臂= 正对镜头，必然遮挡躯干。
#   v2 改成「斧高举过盾上缘 + 斧与盾轮廓不重叠」→ 实测更糟，宽高比 0.68，塔盾整个消失、
#     只剩一根小斧柄。根因是两条约束互相打架，模型取舍时把盾整个丢了。
#   v3 改为单一动作描述：盾在身前（近侧）、斧向身后斜举（远侧、屏幕右方），
#     两件装备分居身体两侧，天然不遮挡。不再要求它们在画面上「分离」或「不重叠」。
#     实测 v3 基准帧通过人工审查，但斧头仍是「单刃月牙」而非设定的双刃战斧——
#     行走视频锁定基准图缺陷后，斧刃几乎完全消失（交接文档 HANDOVER-batong §6.1）。
#   v4 改用「斧高举过肩、斧头置于头部高度或以上的开阔背景处」。依据来自实测对照：
#     **left 基准帧的斧头是完整双刃战斧**，而 left 与 right 的描述此前几乎逐字对称
#     （唯一差别是 screen left / screen right），说明差异不来自提示词措辞，
#     而来自 right 描述里「held low and angled BACKWARD」把斧头压到了身体后下方——
#     那正是 v1/v2/v3 反复丢斧头的同一位置。复刻 left 成功的构图而非继续修辞。
#     同时在 IDENTITIES 里把斧头形状写成可判读的物理描述（两侧各一片弯刃）。
VIEWS_AXE = {
    "right": "strict SIDE PROFILE view, facing screen RIGHT, body seen from the side, "
             "full body side profile silhouette, he walks toward screen right, "
             "the massive RECTANGULAR TOWER SHIELD is strapped to his LEFT arm held in "
             "FRONT of his body on the near side, clearly visible as a large solid "
             "rectangle covering his near side, "
             "the double-bladed battle axe is gripped in his right hand and raised HIGH "
             "above his right shoulder, the axe head is held high in the air at head "
             "level or above, completely clear of the shield and completely clear of "
             "his body silhouette, the entire axe head is fully visible in open space "
             "against the plain background, the axe head is large and unmistakably "
             "DOUBLE-BLADED with two curved blades, one on each side of the haft, "
             "broad heavy stance, NO cape flowing",
    "left":  "strict SIDE PROFILE view, facing screen LEFT, body seen from the side, "
             "full body side profile silhouette, he walks toward screen left, "
             "the massive RECTANGULAR TOWER SHIELD is strapped to his LEFT arm held in "
             "FRONT of his body on the near side, clearly visible as a large solid "
             "rectangle covering his near side, "
             "the double-bladed battle axe is gripped in his right hand held low and "
             "angled BACKWARD behind his body toward screen left, axe head fully visible, "
             "broad heavy stance, NO cape flowing",
    "front": "FRONT view facing the camera, body seen from the front, the massive "
             "rectangular tower shield faces the camera covering most of his torso and is "
             "clearly visible as a large rectangle, the double-bladed battle axe is held "
             "at his right side, symmetrical heavy stance",
    "back":  "BACK view, back turned toward camera, seen from behind, "
             "face not visible, back of the closed iron great helm visible, back armor and "
             "shoulder plates visible, the tower shield seen from its back side strapped to "
             "his left arm, the axe held down at his right side, "
             "entire silhouette clearly separated from background, NO cape",
}


def data_uri(p: Path) -> str:
    return "data:image/png;base64," + base64.b64encode(p.read_bytes()).decode()


def qc_single(p: Path, view: str, char: str = "aila", ref_ar: float | None = None) -> bool:
    """
    单图自检：检测武器/部件分离（水平连通域数异常）＋ 体型走形（宽高比）。

    人物 + 武器若被画成悬浮分离的多个块，连通域会明显多于 1 个大块。

    宽高比门禁（2026-10-03 新增）：同一角色的四向基准帧体型必须一致。
    实测教训——right 朝向因提示词里两条约束互相打架，模型把塔盾整个丢掉、
    只留一根小斧柄，连通块仍是 1、覆盖率 29%，旧判据全部通过，
    但宽高比掉到 0.68（同组其余三向 0.90~0.98），一眼看出是残次品。
    故增加：与参考值偏离超过 ±0.18 直接判失败。0（首张，无参考）时仅做下限。
    """
    import numpy as np
    from PIL import Image
    a = np.array(Image.open(p).convert("RGBA"))[:, :, 3]
    m = (a > 40).astype(np.uint8)
    if m.sum() == 0:
        return False
    try:
        from scipy import ndimage
        lab, n = ndimage.label(m)
        sizes = np.bincount(lab.ravel())[1:]
        big = (sizes >= m.sum() * 0.02).sum()   # >=2% 画面的连通块
    except Exception:
        big = 1
    ys, xs = np.where(m)
    # 主体占外接框的比例：太低 = 主体细碎/分散；太高 = 没留边距
    bbox_area = (xs.max()-xs.min()+1) * (ys.max()-ys.min()+1)
    fill = m.sum() / bbox_area
    # 主体在画布中的占比（用于确保人物够大）
    cover = m.sum() / m.size
    # 体型宽高比（重装角色明显方阔，弓手/术士偏瘦；给一个宽容下限）
    ar = (xs.max()-xs.min()+1) / float(ys.max()-ys.min()+1)
    ar_min = 0.55 if char == "batong" else 0.40
    ok = big <= 3 and cover >= 0.10 and ar >= ar_min
    detail = f"连通块={big} 占画布={cover*100:.1f}% 密度={fill:.2f} 宽高比={ar:.2f}"
    if ref_ar is not None:
        drift = abs(ar - ref_ar)
        # 阈值维持 0.18。2026-10-03 曾一度想放宽到 0.30，原因是参考值取法有缺陷
        # —— ref_aspect() 把四个朝向混取中位数，导致 front/back 拿侧视的 0.67
        # 当参考而被误判（偏离 0.30~0.33，连续 3 次被拦、白耗生图配额）。
        # 现已改为**只取同视角**作参考，视角差异不再进入判据，
        # 故阈值回到 0.18（该值仍能拦住 v2「盾消失」那类残次品）。
        if drift > 0.18:
            ok = False
            detail += f" 偏离参考{ref_ar:.2f}达{drift:.2f}(阈值0.18,同视角)"
    tag = "自检通过" if ok else "自检失败"
    print(f"[{view}] {tag}: {detail}", flush=True)
    return ok


def _rembg_session():
    """
    取rembg 会话，优先复用本地已有的 isnet-general-use.onnx。

    坑：rembg 默认会话是 u2net（176MB），直连下载 ~20KB/s，会把整个流程
    伪装成「生图卡住」—— 实际图早已落盘，进程卡在模型下载。
    本地~/.u2net/isnet-general-use.onnx（178MB）存在时直接用。
    """
    import rembg
    from rembg import new_session
    home = Path.home() / ".u2net" / "isnet-general-use.onnx"
    if home.exists():
        return new_session("isnet-general-use")
    print("    [warn] 本地无 isnet-general-use.onnx，回退默认会话（首次会很慢）", flush=True)
    return new_session()


def aspect_ratio(p: Path) -> float:
    """已落盘抠图的宽高比；文件缺失返回 0。"""
    import numpy as np
    from PIL import Image
    a = np.array(Image.open(p).convert("RGBA"))[:, :, 3]
    ys, xs = np.where(a > 40)
    if len(xs) == 0:
        return 0.0
    return (xs.max()-xs.min()+1) / float(ys.max()-ys.min()+1)


def ref_aspect(char: str, exclude: str) -> float | None:
    """
    取同角色**同视角**已生成朝向的宽高比中位数，作为体型参考。

    必须与同角色比：不同定位体型本就不同（重装方阔 0.9+ / 术士瘦高），
    跨角色比会误杀。

    2026-10-03 修正：**必须与同视角比**。
    实测 batong 正/背视宽高比约 0.83~0.98，侧视（斧头高举过肩把 bbox 拉高）
    约 0.66~0.86，**同角色内部视角间就差0.19~0.31** —— 已超过原 0.18 阈值。
    原实现把四个朝向混在一起取中位数，于是 front/back 拿侧视的 0.67 当参考，
    被判「偏离 0.30~0.33」而连续 3 次全被拦截，白耗生图配额（Agnes 约 1RPM）。

    但同视角样本只有 1~2 个，中位数不稳。故：同视角样本 >=1 时用同视角中位数；
    不足则退回「全部朝向」并由调用方放宽阈值。
    """
    import statistics
    SAME_VIEW = {"front": ("front", "back"), "back": ("front", "back"),
                 "left": ("left", "right"), "right": ("left", "right")}
    group = SAME_VIEW.get(exclude, ("front", "back", "left", "right"))

    def collect(views):
        ars = []
        for v in views:
            if v == exclude:
                continue
            f = OUT / f"{char}_{v}_cut.png"
            if f.exists():
                r = aspect_ratio(f)
                if r > 0:
                    ars.append(r)
        return ars

    same = collect(group)
    if same:
        return statistics.median(same)
    # 同视角样本不足（如「只有 right 就先生成 front」）：返回 None 而非退回
    # 跨视角中位数。实测跨视角参考会让正常产物被误判（front 0.98 对参考 0.67
    # 偏离 0.31 > 阈值 0.18），宁可少一道检查，也不要用错误的参考值。
    # 此时只剩绝对下限 ar_min 与连通块/覆盖率三项生效，仍能拦住残次品。
    return None


def gen(view: str, tries: int = 3, char: str = "aila") -> Path | None:
    identity = IDENTITIES[char]
    views = VIEWS_AXE if char == "batong" else VIEWS
    out = OUT / f"{char}_{view}.png"
    cut = OUT / f"{char}_{view}_cut.png"
    if cut.exists():
        print(f"[{view}] 已存在", flush=True)
        return cut
    ref_ar = ref_aspect(char, view)
    if ref_ar:
        print(f"[{view}] 体型参考（其余朝向中位宽高比）= {ref_ar:.2f}", flush=True)
    prompt = f"{identity}. {views[view]}. {STYLE}"
    # 原图已存在时复用：Agnes 约 1RPM，生图是最贵的一步。
    # 上一次运行若在抠图阶段中断（模型下载卡死等），原图是完好的，不该重出。
    reuse_raw = out.exists() and out.stat().st_size > 100_000
    if reuse_raw:
        print(f"[{view}] 复用已有原图 {out.stat().st_size//1024}KB，直接抠图", flush=True)
    sess = None   # 懒加载一次，避免每次重试都重新载入 178MB 模型
    for t in range(tries):
        try:
            if reuse_raw:
                reuse_raw = False
            else:
                r = ac.generate_image(prompt=prompt, size="768x768", model="agnes-image-2.1-flash")
                u = r["data"][0]["url"]
                out.parent.mkdir(parents=True, exist_ok=True)
                os.system(f'curl -sL --max-time 120 -o "{out}" "{u}"')
                print(f"[{view}] 第{t+1}次生成 {out.stat().st_size//1024}KB", flush=True)
            # rembg 抠图（固定 session：默认 u2net 模型 176MB 直连下载极慢，
            # 表现为「生图已完成但进程卡在 rembg 十分钟不出结果」——
            # 2026-10-03 实测。isnet-general-use.onnx 本地已有，抠图质量等价。）
            from PIL import Image
            from rembg import remove
            im = Image.open(out).convert("RGBA")
            if sess is None:
                sess = _rembg_session()
            res = remove(im, session=sess)
            if not isinstance(res, Image.Image):
                import io
                res = Image.open(io.BytesIO(res))
            # 抠图后处理：抑制黑边残留
            import numpy as np
            arr = np.array(res)
            a = arr[:, :, 3].astype(np.int16)
            # 半透明且极暗的像素 = 背景残留，直接归零
            lum = arr[:, :, :3].max(axis=2).astype(np.int16)
            ghost = (a > 8) & (a < 200) & (lum < 45)
            arr[:, :, 3][ghost] = 0
            # 形态学开运算去孤立噪点
            from PIL import ImageFilter
            clean = Image.fromarray(arr).filter(ImageFilter.MinFilter(3))
            ca = np.array(clean)
            ca[:, :, 3] = np.maximum(ca[:, :, 3], arr[:, :, 3] * 0)
            res = Image.fromarray(ca)
            res.save(cut)
            cov = float((np.array(res)[:, :, 3] > 8).sum()) / (768 * 768)
            print(f"[{view}] 抠图完成 alpha覆盖={cov*100:.1f}%", flush=True)
            if not qc_single(cut, view, char=char, ref_ar=ref_ar):
                print(f"[{view}] 质量自检未过，重新生成", flush=True)
                cut.unlink(missing_ok=True)
                (OUT / f"{char}_{view}.png").unlink(missing_ok=True)
                import time as _t; _t.sleep(3)
                continue
            if cov < 0.08:
                print(f"[{view}] 覆盖率过低，判定抠图失败", flush=True)
                (OUT / f"{char}_{view}.png").unlink(missing_ok=True)
                return None
            return cut
        except Exception as e:
            print(f"[{view}] 第{t+1}次失败: {type(e).__name__}: {e}", flush=True)
            time.sleep(5)
    return None


if __name__ == "__main__":
    args = sys.argv[1:]
    char = "aila"
    if args and args[0] in IDENTITIES:
        char = args.pop(0)
    views = args or ["right", "left", "front", "back"]
    log = OUT / f"gen_log_{char}.json"
    res = json.loads(log.read_text()) if log.exists() else {}
    for v in views:
        p = gen(v, char=char)
        res[v] = str(p) if p else "FAILED"
        log.write_text(json.dumps(res, ensure_ascii=False, indent=2))
    print("\nDONE", flush=True)
