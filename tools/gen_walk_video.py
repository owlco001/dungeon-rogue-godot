#!/usr/bin/env python3
"""
四朝向行走视频生成 —— 严格按美术规范执行

硬性规则:
  1. 锁定朝向，全程禁止转身/旋转/改变视角；相机完全固定，只允许角色水平平移
  2. 时长留冗余，裁剪后保证 >=12 帧原生稳定步态周期；ping-pong 仅兜底
  3. 传入角色基准参考图，锁定脸型/盔甲/披风/武器/身材比例
  4. 背景走纯色 + 后期 rembg 抠图（视频模型不吐真 alpha）
  5. FPS=12, 分辨率 768x768

用法: python3 gen_walk_video.py <角色ID> [方向...]  例: aila right front
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

ROOT = Path(os.environ.get("WALKGEN_ROOT", "/tmp/walkgen"))
FPS = 12.0
SIZE = 768
NUM_FRAMES = 121          # 10 秒 @12fps，冗余充足，够切出 >=12 帧原生周期
BASE_DIR = ROOT / "bases"


def base_for(char: str, direction: str) -> Path:
    """基准图朝向必须与视频朝向一致，否则模型会中途转向来和解指令。"""
    p = BASE_DIR / f"{char}_{direction}_cut.png"
    if not p.exists():
        raise FileNotFoundError(f"缺少 {direction} 基准图: {p}")
    # 2026-10-03：存在不等于可用。空文件/ 抠图失败留下的 0 字节图会让视频模型
    # 拿到一张无内容的参考图，产出必然跑偏，且现象是"生成成功但朝向乱"，
    # 极难归因。这里显式拦一道，给出可读的原因。
    if p.stat().st_size < 10_000:
        raise ValueError(
            f"{direction} 基准图无效（仅 {p.stat().st_size} 字节）：{p}\n"
            f"  常见原因：rembg 抠图阶段中断/失败，产出了 0 字节或残缺文件。\n"
            f"  处理：删掉该文件后重跑 gen_base_views.py，会重新生图。"
        )
    return p

# ---------------- 四朝向提示词（逐字复用，禁止改写风格描述） ----------------
# 2026-10-03 改为按角色参数化。原实现把 aila 的弓手描述硬编码在四个朝向里
# （"The bow is ALWAYS held..." + "same cloak" + 负向词里的 floating bow/arrow），
# 拿去生成 batong 会把斧盾描述成弓，还要求 "cloak sways" —— 而 batong 明确无斗篷。
# 复用 gen_base_views.py 的角色表口径：持械描述与负向词都必须跟着角色走。
#
# 塔盾朝向约束（2026-10-03 新增，实测修复）：
#   首轮 v4 视频（基准帧已修好双刃斧与朝向）质检仍 FAIL，漂移 30.39%（阈 8）、
#   面积波动 30.1%。逐帧量化后定位：**塔盾并没有消失，而是随步态在「面朝镜头的
#   宽矩形」与「侧向的窄板」之间旋转** —— 有盾帧宽高比 0.89、面积 7.6 万，
#   翻面帧宽高比 0.62~0.75、面积 4.0~5.2 万。
#   根因是原描述只要求盾「visible / never vanishes」，**从未要求它保持朝向**，
#   模型于是自由地让左臂随步态摆动。
#   修复沿用斧头已验证的思路（把装备状态写进提示词而非只写负向词）：
#   正面必须始终朝向镜头、宽度逐帧恒定，并补齐 shield turning sideways / edge-on /
#   rotating / narrow 等负向词。

WEAPON_PROMPT = {
    "aila": ("The bow is ALWAYS held firmly in her hand, the arrow stays nocked ON the "
             "bowstring at all times, bow and arrow remain ONE single connected object and "
             "never separate, the arrow never floats in the air, the arrow tip always points "
             "in the direction she is facing, horizontally",
             "same face, same armor, same cloak, same bow, same body proportion",
             "cloak sways gently with the movement",
             "detached bow, floating bow, separated bow, broken bow, bow split in two, "
             "floating arrow, detached arrow, arrow not on string, arrow in wrong direction, "
             "arrow pointing backwards, extra arrow"),
    "batong": ("The massive rectangular tower shield is ALWAYS strapped to his LEFT arm and "
               "stays clearly visible as a large solid rectangle in every frame, never "
               "vanishes and never shrinks. CRITICAL: the flat front face of the tower shield "
               "ALWAYS faces the camera, so the shield always reads as a WIDE upright "
               "rectangle the same width in every single frame; it never rotates edge-on, "
               "never turns to a narrow side-on slab, never swings around to face sideways "
               "or backwards, its width stays constant from frame to frame. The heavy "
               "double-bladed battle axe is ALWAYS "
               "gripped in his right hand, stays ONE single connected object welded to his "
               "hands, never floats free, never detaches from him. The axe head keeps its "
               "distinctive double-bladed silhouette and stays fully visible, never turns "
               "into a single crescent blade, never shrinks to a stub. His heavy armored body "
               "and broad stance keep the same proportions",
               "same closed iron helm, same heavy plate armor, same wide upright rectangular "
               "tower shield with gold trim always facing the camera at constant width, "
               "same double-bladed battle axe, same broad body proportion",
               "his heavy pauldrons and belt plates shift slightly with the movement, "
               "the tower shield does NOT rotate or swing around",
               "missing shield, shield removed, shield shrinking, shield vanishing, "
               "shield changing shape, shield turning sideways, shield edge-on, "
               "shield rotating, shield swinging around, shield seen from the side, "
               "narrow shield, shield facing backwards, "
               "detached axe, floating axe, separated axe, "
               "axe handle broken, single crescent blade, tiny axe head, axe shrinking, "
               "axe disappearing, stub axe, club"),
}

P = {}
P["right"] = """2D game sprite sheet animation, single fantasy warrior character, side view, keep character facing to the right all the time, NO TURNING, NO ROTATION, camera completely fixed, plain uniform light grey background, static empty backdrop, no scenery.
Character walking cycle, natural steady walk gait, 1.5 complete walking cycles, legs lift and step down smoothly, body subtle up and down bounce, {SWAY}.
{WEAPON}
Character appearance stays consistent in every frame: {IDENT}. No deformation, no changing outfit, no feature drift between frames.
Only horizontal translation of character, character never turn around, never change viewing angle.
Clean hand-painted game art style, line art stable, consistent color palette.
Smooth motion, no sudden pose jump.
Entire character stays fully inside frame at all times, do not crop, do not zoom in."""


def build_prompts(char: str) -> tuple[dict, str]:
    """按角色取持械描述与负向词，组装四朝向提示词。风格段落逐字复用不改写。"""
    weapon, ident, sway, neg_extra = WEAPON_PROMPT[char]
    p = {d: t.format(WEAPON=weapon, IDENT=ident, SWAY=sway) for d, t in P.items()}
    neg = NEG_BASE + ", " + neg_extra
    return p, neg


NEG_BASE = ("character turn around, rotate body, change viewing angle, camera pan, camera zoom, "
       "distorted face, change armor, change cloak, weapon disappear, body shape change, "
       "frame-to-frame character drift, flicker, sudden pose jump, extra limbs, deformed hands, "
       "messy background, shadow change, perspective shift, character scale changing, "
       "blinking face, inconsistent illustration style, walking away, "
       "cropped, out of frame, multiple characters, background objects, furniture, detached weapon, floating weapon, separated weapon, broken weapon, "
       "dismembered weapon, gradient background, vignette, motion blur, ghosting, double image")

P["front"] = P["right"].replace("side view, keep character facing to the right all the time",
                                "front view, keep front face toward camera all the time")
P["back"] = P["right"].replace("side view, keep character facing to the right all the time",
                               "back view, keep back toward camera all the time")
P["left"] = P["right"].replace("keep character facing to the right all the time",
                               "keep character facing to the left all the time")


def data_uri(p: Path) -> str:
    return "data:image/png;base64," + base64.b64encode(p.read_bytes()).decode()


def gen(char: str, direction: str) -> dict:
    out = ROOT / char / direction
    out.mkdir(parents=True, exist_ok=True)
    prompts, neg = build_prompts(char)
    print(f"\n{'='*64}\n[{char}/{direction}] 提交  {NUM_FRAMES}帧 @{FPS}fps {SIZE}x{SIZE}\n{'='*64}", flush=True)

    t0 = time.time()
    r = ac.generate_video(
        prompt=prompts[direction],
        image=data_uri(base_for(char, direction)),  # 规则 3：朝向一致的基准图锁形象
        width=SIZE, height=SIZE,
        num_frames=NUM_FRAMES, frame_rate=FPS,
        audio=False,                      # 无需配音，省流量
        negative_prompt=neg,               # 规则 1：负向锁死转身
    )
    vid = r["video_id"]
    print(f"  task={vid[:60]}  submit={time.time()-t0:.1f}s", flush=True)
    res = ac.poll_video_result(vid)
    print(f"  推理完成 {time.time()-t0:.1f}s  status={res.get('status')}", flush=True)
    (out / "task.json").write_text(json.dumps(
        {"video_id": vid, "response": r, "result": res,
         "params": {"fps": FPS, "size": SIZE, "num_frames": NUM_FRAMES,
                    "direction": direction, "prompt": prompts[direction],
                    "negative": neg}},
        ensure_ascii=False, indent=2))
    return {"char": char, "direction": direction, "video_id": vid,
            "elapsed": round(time.time() - t0, 1), "status": res.get("status")}


if __name__ == "__main__":
    char = sys.argv[1] if len(sys.argv) > 1 else "aila"
    dirs = sys.argv[2:] or ["right", "front", "back", "left"]
    if char not in WEAPON_PROMPT:
        sys.exit(f"未知角色 {char}，可用: {sorted(WEAPON_PROMPT)}。"
                 f"新增角色需在 WEAPON_PROMPT 里补持械描述与负向词，"
                 f"否则会拿别角色的武器设定去生成。")
    ROOT.mkdir(parents=True, exist_ok=True)
    log = ROOT / "gen_log.json"
    results = json.loads(log.read_text()) if log.exists() else {}

    for i, d in enumerate(dirs):
        try:
            results[f"{char}/{d}"] = gen(char, d)
        except Exception as e:
            print(f"[{char}/{d}] FAILED: {type(e).__name__}: {e}", flush=True)
            results[f"{char}/{d}"] = {"char": char, "direction": d,
                                      "error": f"{type(e).__name__}: {e}"}
        log.write_text(json.dumps(results, ensure_ascii=False, indent=2))
        if i < len(dirs) - 1:
            print(f"\n等待 70s 避开 1 RPM 限流...", flush=True)
            time.sleep(70)
    print("\nALL DONE", flush=True)
