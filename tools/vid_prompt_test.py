#!/usr/bin/env python3
"""
强化提示词 + keyframes 闭环 —— 解决视频抽帧的转身与漂移问题

实验设计：
  A  强化 prompt + negative_prompt（单图模式）  —— 测负向约束能否压住转身
  B  keyframes 模式（首帧 = 末帧 = 基准帧）    —— 从结构上强制闭环

对比指标：转身帧、步态周期、中心 X 漂移、宽度极差、接缝代价
"""
import json
import os
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))  # 让同目录的 agnes_path 可导入
from agnes_path import require_agnes_client  # noqa: E402
ac = require_agnes_client()  # 跨仓库依赖，缺失时给出修复指引
# 注意：agnes_client 读的是 PAVO_API_KEY（不是 AGNES_API_KEY）

WORK = Path("/tmp/artwork/vprompt")
WORK.mkdir(parents=True, exist_ok=True)
BASE = Path("/tmp/artwork/aila_base_cut.png")

# ---- 强化后的正向提示词：把「朝向 / 位移 / 取景」三件事钉死 ----
PROMPT = (
    "2D game sprite walk cycle. Female archer in gold-bronze plate armor and crimson cape. "
    "STRICT SIDE PROFILE view, facing screen right, entire video stays in side profile. "
    "Walking in place: legs stride, body bobs gently, cape sways, bow bobs. "
    "One full walk cycle then returns to the exact starting pose. "
    "Static locked camera, no zoom, no pan. "
    "Full body fully inside frame, constant scale, constant position, centered. "
    "Uniform flat dark grey background. Hand-painted detailed fantasy game art, "
    "crisp silhouette, consistent character design throughout."
)

# ---- 负向约束：把「转身 / 镜头 / 背景 / 变形」明确排除 ----
NEG = (
    "turning, rotating, spinning, changing facing direction, walking away, back view, rear view, "
    "profile change, camera movement, zoom, pan, dolly, camera shake, "
    "walking toward camera, character leaving frame, jumping, running, "
    "background scenery, room, pillars, torch, floor tiles, props, other characters, "
    "morphing, extra limbs, distorted body, changing costume, changing armor color, "
    "blurry, low detail, pixel art, text, watermark"
)

FRAME_RATES = [("A_prompt", dict(mode="single", use_neg=True)),
               ("B_keyframes", dict(mode="keyframes", use_neg=True))]
RESULTS = {}


def data_uri(p: Path) -> str:
    import base64
    return "data:image/png;base64," + base64.b64encode(p.read_bytes()).decode()


def make(tag: str, cfg: dict) -> dict:
    out = WORK / tag
    out.mkdir(exist_ok=True)
    print(f"\n{'='*60}\n[{tag}] 提交... mode={cfg['mode']}\n{'='*60}", flush=True)

    kw = dict(prompt=PROMPT, width=768, height=768,
              num_frames=97, frame_rate=24.0, audio=False)
    if cfg["mode"] == "keyframes":
        uri = data_uri(BASE)
        kw["first_image"] = uri
        kw["last_image"] = uri
    else:
        kw["image"] = data_uri(BASE)
    if cfg["use_neg"]:
        kw["negative_prompt"] = NEG

    t0 = time.time()
    r = ac.generate_video(**kw)
    vid = r["video_id"]
    (out / "task.json").write_text(json.dumps(r, ensure_ascii=False, indent=2))
    print(f"  task={vid}  submit={time.time()-t0:.1f}s", flush=True)

    res = ac.poll_video_result(vid)
    print(f"  done in {time.time()-t0:.1f}s  status={res.get('status')}", flush=True)
    (out / "result.json").write_text(json.dumps(res, ensure_ascii=False, indent=2))
    return {"tag": tag, "video_id": vid, "elapsed": round(time.time() - t0, 1),
            "status": res.get("status"), "raw": res}


if __name__ == "__main__":
    (WORK / "prompt.txt").write_text("PROMPT:\n" + PROMPT + "\n\nNEGATIVE:\n" + NEG)
    for tag, cfg in FRAME_RAMES if False else FRAME_RATES:
        try:
            RESULTS[tag] = make(tag, cfg)
        except Exception as e:
            print(f"[{tag}] FAILED: {type(e).__name__}: {e}", flush=True)
            RESULTS[tag] = {"tag": tag, "error": f"{type(e).__name__}: {e}"}
        (WORK / "summary.json").write_text(
            json.dumps({k: {kk: vv for kk, vv in v.items() if kk != 'raw'}
                        for k, v in RESULTS.items()}, ensure_ascii=False, indent=2))
        if tag != FRAME_RATES[-1][0]:
            print("\n等待 60s 避开 1 RPM 限流...", flush=True)
            time.sleep(60)
    print("\nDONE", flush=True)
