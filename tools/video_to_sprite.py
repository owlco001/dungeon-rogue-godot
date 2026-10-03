#!/usr/bin/env python3
"""
视频抽帧 -> 可循环 384x384 Sprite 序列 + 自动质检

处理链：周期检测 / 转身检测 / union bbox 归一化 / 脚底基线对齐 / 等比缩放
质检项：转身检测、步态周期帧数、seam_cost、帧间主体面积波动、bbox 中心 X/Y 偏移
原生闭环优先；仅在原生不达标时启用 ping-pong 兜底并在报告中标记。

用法:
  python3 video_to_sprite.py <抠图帧目录> <输出目录> [--size 384] [--fps 12]
                             [--min-cycle 12] [--max-area-var 18.0]
                             [--max-center-drift 8.0] [--max-seam 12.0]
                             [--tag NAME]
"""
import argparse
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ALPHA_TH = 8
OK = "[PASS]"
NG = "[FAIL]"


# ---------------------------------------------------------------- 载入
def load_rgba(p: Path):
    arr = np.array(Image.open(p).convert("RGBA"))
    m = arr[:, :, 3] > ALPHA_TH
    if not m.any():
        return arr, None
    ys, xs = np.where(m)
    return arr, (int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max()))


def signature(arr: np.ndarray) -> np.ndarray:
    """alpha 轮廓签名：32 段列投影 + 32 段行投影，用于运动量与周期分析"""
    m = arr[:, :, 3] > ALPHA_TH
    ys, xs = np.where(m)
    if len(xs) == 0:
        return np.zeros(64)
    sub = m[ys.min():ys.max() + 1, xs.min():xs.max() + 1].astype(np.uint8) * 255
    im = Image.fromarray(sub)
    cols = np.asarray(im.resize((32, 1), Image.LANCZOS), dtype=float).ravel() / 255.0
    rows = np.asarray(im.resize((1, 32), Image.LANCZOS), dtype=float).ravel() / 255.0
    return np.concatenate([cols, rows])


# ---------------------------------------------------------------- 周期 / 转身
def detect_period(motion: np.ndarray, lo: int, hi: int) -> tuple[int, float]:
    """对帧间运动量做自相关，找一个完整步态周期（含左右各一次摆动）"""
    if len(motion) < lo * 2:
        return len(motion), 0.0
    s = motion - motion.mean()
    best, best_score = lo, -1e9
    for p in range(lo, min(hi, len(s) - lo) + 1):
        num = float(np.dot(s[: len(s) - p], s[p:]))
        den = float(np.linalg.norm(s[: len(s) - p]) * np.linalg.norm(s[p:]) + 1e-9)
        if num / den > best_score:
            best, best_score = p, num / den
    return best, best_score


def detect_turn(widths: np.ndarray, centers: np.ndarray) -> int | None:
    """
    转身检测：AI 视频会自己「演下去」逐渐转视角。特征 = 宽度持续收缩 + 中心单向漂移。
    返回转身起始帧；None = 全程未检出。

    ⚠️ 已知盲区（2026-10-03 实测确认，勿误以为本检测器能抓朝向）：
    本函数只回答「帧间有没有发生转身」，**不回答「整体朝哪边」**。
    角色全程面朝左（与期望相反）时，各帧宽度稳定、无旋转，
    本函数返回 None —— 即「漏判整体反向」。
    该盲区在 batong/right 上真实发生过：提示词要求 face right，
    实际全程面朝左，而质检里 turn_detected 恰好是唯一没报错的项。

    尝试过补几何判据（左右半区像素比 balance、镜像相似度 mirrsim、
    躯干带收窄），结论是**不可用**：拿已知正/反样本标定，
    全带下正确样本 +0.0016、反向样本 +0.0657，同号不可区分；
    只有在特定窄带上才偶然可区分，属对样本过拟合。
    根因是朝向属「装备位于身体哪一侧」的语义信息，像素量测捕获不到。

    现行对策（不靠产出端猜，靠生成端保证）：
      1. gen_base_views.py 的基准帧必须与目标朝向一致（须经人工审查）；
      2. gen_walk_video.py 的 base_for() 校验基准图非空，
         避免 0 字节参考图导致朝向往返。
    真正的自动判别需要训分类器，不在当前工具链范围内。
    """
    w0 = float(np.median(widths[:3]))
    for i in range(4, len(widths) - 2):
        win = widths[max(0, i - 3): i + 1]
        if win[-1] < w0 * 0.72 and win[-1] <= win.min() + 1:
            drift = abs(centers[min(len(centers) - 1, i + 4)] - centers[max(0, i - 4)])
            if drift > 10 or i > 4:
                return i
    return None


def detect_pose_jump(motion: np.ndarray, thresh: float = 8.0,
                     min_run: int = 2) -> list[int]:
    """
    姿态突变检测 —— 判「连续跳变」而非孤立尖峰。

    理由：AI 视频偶发单帧抖动（孤立高运动量）是常态，不影响观感；
    真正的姿态跳变是连续多帧的高运动量。首帧（起步）不计入。
    """
    if len(motion) < 5:
        return []
    med = float(np.median(motion)) + 1e-6
    hot = [i > 0 and v > med * thresh for i, v in enumerate(motion)]
    bad, run = [], 0
    for i, h in enumerate(hot):
        if h:
            run += 1
            if run >= min_run:
                bad.extend(range(i - run + 1, i + 1))
        else:
            run = 0
    return sorted(set(bad))


# ---------------------------------------------------------------- 归一化
def normalize(frames, bboxes, indices, target: int, pad: int = 6,
              fill: float = 0.96) -> list[Image.Image]:
    """
    union bbox 裁剪 -> 等比缩放 -> 脚底基线对齐 -> 水平居中

    fill: 主体在画布中的占比上限。行走动画按身高对齐（而非 union bbox 等比），
    因为弓的横向跨度会把人物压得很小。
    """
    H, W = frames[0].shape[:2]
    sub = [bboxes[i] for i in indices]
    x0 = max(0, min(b[0] for b in sub) - pad)
    y0 = max(0, min(b[1] for b in sub) - pad)
    x1 = min(W, max(b[2] for b in sub) + pad + 1)
    y1 = min(H, max(b[3] for b in sub) + pad + 1)
    cw, ch = x1 - x0, y1 - y0
    # 按「身高」定尺：步态中身高变化小，比宽度（受弓/披风影响）更稳定
    scale = (target * fill) / max(ch, 1)
    nw, nh = max(1, round(cw * scale)), max(1, round(ch * scale))
    # 极端情况（横向跨度远大于身高）才退回等比
    if nw > target or nh > target:
        k = target / max(nw, nh)
        nw, nh = max(1, round(nw * k)), max(1, round(nh * k))
    out = []
    for i in indices:
        im = Image.fromarray(frames[i][y0:y1, x0:x1]).resize((nw, nh), Image.LANCZOS)
        canvas = Image.new("RGBA", (target, target), (0, 0, 0, 0))
        canvas.paste(im, ((target - nw) // 2, target - nh))
        out.append(canvas)
    return out


def _anchor_x(im: Image.Image) -> float:
    """
    锚点取 alpha 掩膜的水平重心。
    重心比 bbox 中心/脚底中点更鲁棒：对手臂摆动、弓的伸缩不敏感。
    """
    a = (np.array(im)[:, :, 3] > ALPHA_TH).astype(float)
    tot = a.sum()
    if tot == 0:
        return im.size[0] / 2
    cols = a.sum(axis=0)
    xs = np.arange(len(cols), dtype=float)
    return float((cols * xs).sum() / tot)


def recenter_x(ims: list[Image.Image]) -> list[Image.Image]:
    """把整段序列对齐到统一 X 中心，消除残余水平位移"""
    if len(ims) < 2:
        return ims
    target = float(np.median([_anchor_x(im) for im in ims]))
    out = []
    for im in ims:
        dx = int(round(_anchor_x(im) - target))
        if dx == 0:
            out.append(im)
            continue
        out.append(im.transform(im.size, Image.AFFINE, (1, 0, -dx, 0, 1, 0),
                                resample=Image.BICUBIC))
    return out


def crossfade_loop(ims: list[Image.Image], n_blend: int = 3) -> list[Image.Image]:
    """
    交叉淡化闭环 —— 优于 ping-pong：不会「来回踱步」。

    做法：保留前 N-n 帧不变，把尾部 n 帧逐帧向首帧渐变（最后一帧 = 首帧），
    循环时天然连续。输出长度与输入一致。
    """
    N, n = len(ims), n_blend
    if N < n * 2 + 2:
        return ims
    first = ims[0].convert("RGBA")
    blended = []
    for j in range(n):
        # j=0 对应最后一帧 -> 完全变成首帧（t=1）；j 越大越保留原帧
        t = (n - j) / n
        blended.append(Image.blend(ims[N - 1 - j].convert("RGBA"), first, t))
    return ims[: N - n] + blended


# ---------------------------------------------------------------- 指标
def seam_cost(ims) -> float:
    """首尾帧接缝代价：alpha IoU 缺口 + RGB 差，0 = 完全无缝"""
    a, b = np.array(ims[0]).astype(np.int16), np.array(ims[-1]).astype(np.int16)
    am, bm = a[:, :, 3] > ALPHA_TH, b[:, :, 3] > ALPHA_TH
    u = int((am | bm).sum())
    if u == 0:
        return 0.0
    iou = float((am & bm).sum()) / u
    d = float(np.abs(a[:, :, :3] - b[:, :, :3]).sum(axis=2)[am | bm].mean() / 3.0)
    return round((1.0 - iou) * 60.0 + d * 0.4, 2)


def area_stats(frames, indices) -> dict:
    """帧间主体像素面积波动"""
    areas = np.array([float((frames[i][:, :, 3] > ALPHA_TH).sum()) for i in indices])
    lo, hi = float(areas.min()), float(areas.max())
    return {
        "min": int(lo), "max": int(hi),
        "var_pct": round((hi - lo) / max(hi, 1.0) * 100.0, 2),
    }


def part_separation(frames, indices, alpha_th: int = 40) -> dict:
    """
    逐帧部件分离检测：人物+武器应连成一块。
    武器被画成悬浮分离的块时，>=2% 画面的连通块会 > 1。
    """
    try:
        from scipy import ndimage
    except Exception:
        return {"enabled": False}
    per_frame, bad = [], []
    for i in indices:
        m = (frames[i][:, :, 3] > alpha_th).astype(np.uint8)
        if m.sum() == 0:
            continue
        lab, _ = ndimage.label(m)
        sizes = np.bincount(lab.ravel())[1:]
        big = int((sizes >= m.sum() * 0.02).sum())
        per_frame.append(big)
        if big > 1:
            bad.append(i)
    if not per_frame:
        return {"enabled": True, "max_parts": 0, "bad_frames": []}
    return {
        "enabled": True,
        "max_parts": max(per_frame),
        "avg_parts": round(sum(per_frame) / len(per_frame), 2),
        "bad_frames": bad[:12],
        "bad_count": len(bad),
    }


def center_drift_norm(ims) -> dict:
    """在归一化后的成品帧上测量中心漂移"""
    xs, ys, ws, hs = [], [], [], []
    for im in ims:
        mf = (np.array(im)[:, :, 3] > ALPHA_TH).astype(float)
        m = mf > 0
        if not m.any():
            continue
        yy, xx = np.where(m)
        # X 用重心（与 recenter_x 的校正口径一致），Y 用 bbox 中心
        cols = mf.sum(axis=0)
        gx = float((cols * np.arange(len(cols), dtype=float)).sum() / mf.sum())
        xs.append(gx)
        ys.append((yy.min() + yy.max()) / 2)
        ws.append(xx.max() - xx.min() + 1)
        hs.append(yy.max() - yy.min() + 1)
    if not xs:
        return {"x_span": 0, "y_span": 0, "x_drift_norm": 0.0, "y_drift_norm": 0.0}
    xs, ys = np.array(xs), np.array(ys)
    bw, bh = float(np.mean(ws)), float(np.mean(hs))
    return {
        "x_span": round(float(xs.max() - xs.min()), 2),
        "y_span": round(float(ys.max() - ys.min()), 2),
        "x_drift_norm": round(float((xs.max() - xs.min()) / max(bw, 1) * 100), 2),
        "y_drift_norm": round(float((ys.max() - ys.min()) / max(bh, 1) * 100), 2),
    }


def center_drift(bboxes, indices) -> dict:
    xs = np.array([(bboxes[i][0] + bboxes[i][2]) / 2 for i in indices], dtype=float)
    ys = np.array([(bboxes[i][1] + bboxes[i][3]) / 2 for i in indices], dtype=float)
    bx = np.array([bboxes[i][2] - bboxes[i][0] + 1 for i in indices], dtype=float)
    by = np.array([bboxes[i][3] - bboxes[i][1] + 1 for i in indices], dtype=float)
    return {
        "x_span": round(float(xs.max() - xs.min()), 2),
        "y_span": round(float(ys.max() - ys.min()), 2),
        "x_drift_norm": round(float((xs.max() - xs.min()) / max(bx.mean(), 1.0) * 100), 2),
        "y_drift_norm": round(float((ys.max() - ys.min()) / max(by.mean(), 1.0) * 100), 2),
    }


# ---------------------------------------------------------------- 主流程
def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("out")
    ap.add_argument("--size", type=int, default=384)
    ap.add_argument("--fps", type=float, default=12.0)
    ap.add_argument("--min-cycle", type=int, default=12)
    ap.add_argument("--max-area-var", type=float, default=18.0)
    ap.add_argument("--max-center-drift", type=float, default=8.0)
    ap.add_argument("--max-seam", type=float, default=20.0)
    ap.add_argument("--tag", default="")
    a = ap.parse_args()

    SRC, OUT = Path(a.src), Path(a.out)
    OUT.mkdir(parents=True, exist_ok=True)

    files = sorted(SRC.glob("f_*.png")) or sorted(SRC.glob("*.png"))
    if not files:
        print(f"{NG} no frames in {SRC}")
        return 2

    frames, bboxes = [], []
    for f in files:
        arr, bb = load_rgba(f)
        frames.append(arr)
        bboxes.append(bb)
    n = len(frames)
    empty = [i for i, b in enumerate(bboxes) if b is None]
    if empty:
        print(f"{NG} {len(empty)} empty frames: {empty[:10]}")
        if len(empty) > n * 0.2:
            return 2

    sigs = np.array([signature(frames[i]) for i in range(n)])
    motion = np.array([float(np.abs(sigs[i + 1] - sigs[i]).mean()) for i in range(n - 1)])
    del sigs  # 及时释放，避免后续大数组叠加占用内存

    widths = np.array([(bboxes[i][2] - bboxes[i][0] + 1) if bboxes[i] else 0 for i in range(n)], float)
    heights = np.array([(bboxes[i][3] - bboxes[i][1] + 1) if bboxes[i] else 0 for i in range(n)], float)
    centers = np.array([((bboxes[i][0] + bboxes[i][2]) / 2) if bboxes[i] else 0 for i in range(n)], float)

    turn = detect_turn(widths, centers)
    jumps = detect_pose_jump(motion)
    period, corr = detect_period(motion, lo=max(6, a.min_cycle - 6), hi=40)

    # 有效段：转身帧之前；至少容纳一个完整周期
    valid_end = n if turn is None else max(turn, period + 3)
    valid_end = min(valid_end, n)

    # 候选 A：原生闭环 —— 两阶段搜索，避免 O(周期²) 次像素级重算
    #   阶段1 用 bbox 几何量（O(1)）粗筛所有 (周期, 起点) 组合
    #   阶段2 只对最优的 K 个候选做像素级 normalize + seam_cost
    K = 6
    geo = []
    for p in range(max(a.min_cycle, 8), min(period + 10, valid_end) + 1):
        for s in range(0, min(valid_end - p, max(1, valid_end // 2)) + 1):
            win = list(range(s, s + p))
            # 几何代价：首尾 bbox 的宽高/中心差，比例化后加权
            b0, b1 = bboxes[win[0]], bboxes[win[-1]]
            if b0 is None or b1 is None:
                continue
            w0, h0 = b0[2] - b0[0] + 1, b0[3] - b0[1] + 1
            w1, h1 = b1[2] - b1[0] + 1, b1[3] - b1[1] + 1
            dw = abs(w0 - w1) / max(w0, w1, 1)
            dh = abs(h0 - h1) / max(h0, h1, 1)
            dcx = abs((b0[0] + b0[2]) - (b1[0] + b1[2])) / 2 / max((w0 + w1) / 2, 1)
            geo.append((dw + dh + dcx, win))
    geo.sort(key=lambda t: t[0])

    best = None
    for _g, win in geo[:K]:
        ims = normalize(frames, bboxes, win, a.size)
        sc = seam_cost(ims)
        if best is None or sc < best[0]:
            best = (sc, win, ims)
    if best is None:
        fb = list(range(0, min(period, valid_end)))
        best = (seam_cost(normalize(frames, bboxes, fb, a.size)), fb,
                normalize(frames, bboxes, fb, a.size))
    native_seam, native_win, native_ims = best

    # 居中校正：规范允许角色水平平移，但玩家不该看到整段序列整体位移。
    # 以「脚底中点」为锚（脚底不受弓/披风摆动影响，比 bbox 中心更稳）
    native_ims = recenter_x(native_ims)

    # 候选 B：crossfade 闭环（首选兜底，不产生来回踱步）
    xf_win = native_win
    xf_ims = crossfade_loop(normalize(frames, bboxes, xf_win, a.size), n_blend=3)
    xf_seam = seam_cost(xf_ims)

    # 候选 C：ping-pong（最后兜底）
    ping_win = native_win + native_win[-2:0:-1]
    ping_ims = normalize(frames, bboxes, ping_win, a.size)
    ping_seam = seam_cost(ping_ims)

    # 自动质检（面积/漂移/转身/稳定帧 与闭环方式无关）
    area = area_stats(frames, native_win)
    # 漂移在「归一化后的成品帧」上测量 —— 归一化已消除位移/缩放，
    # 残留的才是玩家真正会看到的抖动。原始 bbox 里的位移属正常（规范允许水平平移）。
    drift = center_drift_norm(native_ims)
    stable = len(native_win) >= a.min_cycle
    pose_ok = len(jumps) == 0
    sep = part_separation(frames, native_win)

    # 闭环质量项（决定用哪种闭环方式），与素材质量项分开评估
    loop_ok = native_seam < a.max_seam
    # 素材质量项（决定是否合格）
    quality = {
        "无转身检测": turn is None,
        f"连续稳定>={a.min_cycle}帧": stable,
        f"形象波动<{a.max_area_var}%": area["var_pct"] < a.max_area_var,
        f"中心漂移<{a.max_center_drift}%": max(drift["x_drift_norm"], drift["y_drift_norm"]) < a.max_center_drift,
        "无姿态突变": pose_ok,
        "装备无分离": (not sep["enabled"]) or sep.get("bad_count", 0) == 0,
    }
    quality_ok = all(quality.values())
    checks = dict(quality)
    checks[f"闭环seam<{a.max_seam}"] = loop_ok

    # 闭环方式：优先原生。原生 seam 不达标时才降级，
    # 且降级不能掩盖素材质量问题 —— 素材不合格就是不合格。
    if loop_ok:
        mode, final_ims, final_seam = "native", native_ims, native_seam
    elif xf_seam < native_seam:
        mode, final_ims, final_seam = "crossfade", xf_ims, xf_seam
    else:
        mode, final_ims, final_seam = "pingpong", ping_ims, ping_seam
    native_pass = quality_ok and loop_ok

    # ---- 输出 ----
    seq = OUT / "seq"
    seq.mkdir(exist_ok=True)
    for old in seq.glob("*.png"):
        old.unlink()
    for i, im in enumerate(final_ims):
        im.save(seq / f"walk_{i:02d}.png")
        im.transpose(Image.FLIP_LEFT_RIGHT).save(seq / f"walk_mirror_{i:02d}.png")

    disp = 240
    g = [im.resize((disp, disp), Image.LANCZOS) for im in final_ims]
    g[0].save(OUT / "cycle_preview.gif", save_all=True, append_images=g[1:],
              duration=int(1000 / a.fps), loop=0, disposal=2)

    cols = min(len(final_ims), 8)
    rows = (len(final_ims) + cols - 1) // cols
    sheet = Image.new("RGBA", (cols * 150, rows * 172), (26, 24, 32, 255))
    for i, im in enumerate(final_ims):
        t = im.resize((150, 150), Image.LANCZOS)
        sheet.paste(t, ((i % cols) * 150, (i // cols) * 172 + 16), t)
    sheet.save(OUT / "cycle_sheet.png")

    report = {
        "tag": a.tag or OUT.name,
        "verdict": "PASS" if native_pass else "FAIL",
        "quality_ok": quality_ok,
        "loop_ok": loop_ok,
        "source_frames": n,
        "turn_detected": turn is not None,
        "turn_frame": turn,
        "pose_jump_frames": jumps,
        "gait_period_frames": period,
        "period_autocorr": round(corr, 3),
        "stable_cycle_frames": len(native_win),
        "stable_window": [native_win[0], native_win[-1]],
        "seam_cost_native": native_seam,
        "seam_cost_crossfade": xf_seam,
        "seam_cost_pingpong": ping_seam,
        "seam_cost_final": final_seam,
        "loop_mode": mode,
        "pingpong_used": mode == "pingpong",
        "crossfade_used": mode == "crossfade",
        "area_var_pct": area["var_pct"],
        "part_separation": sep,
        "center_drift": drift,
        "raw_drift": {
            "width_range_pct": round(float((widths.max() - widths.min()) / max(widths.max(), 1) * 100), 1),
            "height_min_max": [int(heights.min()), int(heights.max())],
        },
        "checks": checks,
        "output_size": [a.size, a.size],
        "final_frames": len(final_ims),
        "note": ("原生步态周期，直接循环" if mode == "native" else
                 ("【crossfade兜底：首尾交叉淡化，无来回踱步】" if mode == "crossfade" else
                  "【ping-pong兜底生成，动作来回踱步】")),
        "failed_checks": [k for k, v in checks.items() if not v],
    }
    (OUT / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2))
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0 if mode == "native" else 1


if __name__ == "__main__":
    raise SystemExit(main())
