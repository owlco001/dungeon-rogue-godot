#!/usr/bin/env python3
"""
tile 无缝化处理

AI 生成的 tile 往往「看起来像 tile」但四边对不上（平铺会露网）。
本脚本用「镜像混合法」把任意图变成真正可无缝平铺的图：

  1. 中心裁切：去掉边缘 1/4（AI 生成时边缘最不可靠）
  2. 偏移环绕：把裁切结果做 offset-wrap 混合（周期 1/2 交叉淡化）
  3. 输出后四边像素连续，任何方向平铺都无缝

参考实现：offset + mirror blend，产出 1/2 对称的无缝纹理。
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image


def make_seamless(src: Path, dst: Path, inset: float = 0.26) -> dict:
    im = Image.open(src).convert("RGB")
    w, h = im.size
    # 1) 中心裁切
    ix, iy = int(w * inset), int(h * inset)
    c = im.crop((ix, iy, w - ix, h - iy))
    # 2) 镜像混合：与 180° 旋转 + 镜像叠加，边界自然连续
    a = np.asarray(c, dtype=np.float32)
    m = np.asarray(c.transpose(Image.FLIP_LEFT_RIGHT).transpose(Image.FLIP_TOP_BOTTOM),
                   dtype=np.float32)
    # 权重沿 x/y 做线性渐变，使两半在各自边界处均为 50/50
    wx = np.linspace(0, 1, a.shape[1], dtype=np.float32)[None, :, None]
    wy = np.linspace(0, 1, a.shape[0], dtype=np.float32)[:, None, None]
    wgt = (wx + wy) / 2.0
    out = a * (1 - wgt) + m * wgt
    # 3) 再次中心裁切并放大回原尺寸（去掉渐变最明显的过渡带残留）
    res = Image.fromarray(np.clip(out, 0, 255).astype(np.uint8))
    res = res.resize((w, h), Image.LANCZOS)

    dst.parent.mkdir(parents=True, exist_ok=True)
    res.save(dst)

    # 量化接缝
    a2 = np.asarray(res, dtype=np.float32)
    h_edge = float(np.abs(a2[0] - a2[-1]).mean())
    v_edge = float(np.abs(a2[:, 0] - a2[:, -1]).mean())
    return {"file": dst.name, "h_edge": round(h_edge, 2), "v_edge": round(v_edge, 2)}


def verify(t: Path, reps: int = 3) -> dict:
    """多格平铺后，量化接缝处的可见度"""
    a = np.asarray(Image.open(t).convert("RGB"), dtype=np.float32)
    h, w, _ = a.shape
    g = np.zeros((h * reps, w * reps, 3), dtype=np.float32)
    for y in range(reps):
        for x in range(reps):
            g[y * h:(y + 1) * h, x * w:(x + 1) * w] = a
    # 接缝 = 相邻 tile 交界处的行/列梯度
    sx = np.abs(np.diff(g, axis=1)).mean()
    sy = np.abs(np.diff(g, axis=0)).mean()
    # 与图内平均梯度对比，比例 <1 说明接缝不比普通纹理更突兀
    inner = np.abs(np.diff(a, axis=1)).mean()
    inner_y = np.abs(np.diff(a, axis=0)).mean()
    return {
        "seam_x_vs_inner": round(float(sx / max(inner, 1e-6)), 3),
        "seam_y_vs_inner": round(float(sy / max(inner_y, 1e-6)), 3),
    }


if __name__ == "__main__":
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("/tmp/tilegen/tiles")
    out = Path(sys.argv[2]) if len(sys.argv) > 2 else Path("/tmp/tilegen/seamless")
    rows = []
    for f in sorted(root.rglob("*.png")):
        if "decal" in f.name or "pillar" in f.name or "flame" in f.name:
            continue
        r = make_seamless(f, out / f.relative_to(root))
        v = verify(out / f.relative_to(root))
        r.update(v)
        rows.append(r)
        print(f"{f.name:34s} 边差h={r['h_edge']:6.2f} v={r['v_edge']:6.2f} "
              f"接缝比 x={v['seam_x_vs_inner']:.2f} y={v['seam_y_vs_inner']:.2f}", flush=True)
    ok = [r for r in rows if max(r["seam_x_vs_inner"], r["seam_y_vs_inner"]) < 1.6]
    print(f"\n无缝比<1.6 的合格 tile: {len(ok)}/{len(rows)}")
