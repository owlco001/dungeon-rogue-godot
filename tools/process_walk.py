#!/usr/bin/env python3
"""
视频后处理流水线：下载 -> ffmpeg 抽帧 -> rembg 抠图 -> video_to_sprite 质检

rembg 用单次进程批量处理（铁律：串行，避免模型反复加载导致 OOM/卡死）
用法: python3 process_walk.py <角色ID> <方向> [方向...]
"""
import json
import subprocess
import sys
import time
from pathlib import Path

import os

ROOT = Path(os.environ.get("WALKGEN_ROOT", "/tmp/walkgen"))  # 抽帧暂存目录（非仓库路径）
PROJ = Path(os.environ.get("DUNGEON_ROOT", Path(__file__).resolve().parent.parent))


def sh(cmd, **kw):
    return subprocess.run(cmd, shell=True, capture_output=True, text=True, **kw)


def download(url: str, dst: Path) -> bool:
    dst.parent.mkdir(parents=True, exist_ok=True)
    r = sh(f'curl -sL --max-time 300 -o "{dst}" "{url}"')
    return r.returncode == 0 and dst.exists() and dst.stat().st_size > 1000


def find_url(res: dict) -> str | None:
    for k in ("video_url", "url", "video", "output_url", "output"):
        v = res.get(k)
        if isinstance(v, str) and v.startswith("http"):
            return v
        if isinstance(v, list) and v and isinstance(v[0], str) and v[0].startswith("http"):
            return v[0]
        if isinstance(v, dict):
            for kk in ("url", "video_url"):
                if isinstance(v.get(kk), str) and v[kk].startswith("http"):
                    return v[kk]
    return None


def cutout(src: Path, dst: Path) -> int:
    """rembg 批量抠图，单进程串行"""
    dst.mkdir(parents=True, exist_ok=True)
    fs = sorted(src.glob("*.png"))
    if not fs:
        return 0
    # 分批处理，避免单次调用过长被中断
    # 2026-10-03 修复两处rembg 陷阱：
    #  1) 不指定 session 时 rembg 默认下载 u2net（176MB，直连 ~20KB/s），
    #     表现为「帧都在但进程卡住不出结果」。改用本地 isnet-general-use.onnx。
    #  2) 每批起一个子进程 =每批都重新载入 178MB 模型，60 帧要载入 60 次。
    #     故每批只建一个 session 并在批内复用。
    B = 60
    total = 0
    for i in range(0, len(fs), B):
        chunk = fs[i:i + B]
        # 路径不能直接插进 f-string —— Windows 上 "\tmp\walkgen\batong\right\frames"
        # 里的 \b / \r / \f 会被 Python 解释成退格/回车/换页转义符，
        # 实际路径变成 C:\tmp\walkgen\x08atong\right\x0crames\ → OSError 22。
        # 用 repr() 生成 Python 字面量再嵌入：既避免转义歧义，又保证类型正确
        # （早前一版用 json.dumps 套两层，json.loads 解出来是 str 而非 list，names 直接坏掉）。
        script = f'''
from pathlib import Path
from PIL import Image
from rembg import remove, new_session
sess = new_session("isnet-general-use")   # 本地已有，勿用默认 u2net
src = Path({str(src)!r}); out = Path({str(dst)!r})
out.mkdir(parents=True, exist_ok=True)
names = {[f.name for f in chunk]!r}
for nm in names:
    p = src / nm
    if not p.exists():
        continue
    res = remove(Image.open(p).convert("RGBA"), session=sess)
    if not isinstance(res, Image.Image):
        import io; res = Image.open(io.BytesIO(res))
    res.save(out / nm)
'''
        # 走 subprocess 传参而非 shell 字符串：Windows 上 shlex.quote 的转义层
        # 与 cmd/PowerShell 的引号规则不兼容，2026-10-03 实测导致内嵌脚本
        # 报 SyntaxError: unterminated string literal（抠图 0 帧、后续质检全跳过）。
        # 用argv 传脚本正文，彻底绕开引号转义。
        r = subprocess.run([sys.executable, "-c", script],
                           capture_output=True, text=True)
        if r.returncode:
            print(f"    rembg 批次失败: {r.stderr[-300:]}", flush=True)
            return total
        total += len(chunk)
        print(f"    抠图 {total}/{len(fs)}", flush=True)
    return total


def process(char: str, direction: str) -> dict:
    d = ROOT / char / direction
    t0 = time.time()
    meta = json.loads((d / "task.json").read_text())
    url = find_url(meta["result"])
    if not url:
        print(f"[{char}/{direction}] 找不到视频 URL, keys={list(meta['result'])}", flush=True)
        return {"error": "no url"}

    mp4 = d / "out.mp4"
    if not mp4.exists():
        print(f"[{char}/{direction}] 下载...", flush=True)
        if not download(url, mp4):
            return {"error": "download failed"}
    print(f"[{char}/{direction}] mp4={mp4.stat().st_size//1024}KB", flush=True)

    frames = d / "frames"
    frames.mkdir(exist_ok=True)
    sh(f'ffmpeg -y -i "{mp4}" -vsync 0 "{frames}/f_%03d.png"')
    n_raw = len(list(frames.glob("*.png")))
    print(f"[{char}/{direction}] 抽帧 {n_raw}", flush=True)
    if n_raw < 12:
        return {"error": f"too few frames {n_raw}"}

    cuts = d / "cuts"
    n_cut = cutout(frames, cuts)
    print(f"[{char}/{direction}] 抠图 {n_cut}", flush=True)
    if n_cut < 12:
        return {"error": f"too few cuts {n_cut}"}

    r = subprocess.run(
        [sys.executable, str(PROJ / "tools/video_to_sprite.py"),
         str(cuts), str(d / "cycle"), "--size", "384", "--fps", "12",
         "--min-cycle", "12", "--tag", f"{char}_{direction}"],
        capture_output=True, text=True)
    print(r.stdout[-2500:], flush=True)
    if r.returncode not in (0, 1):
        print(f"[{char}/{direction}] 质检失败: {r.stderr[-500:]}", flush=True)
        return {"error": "qc failed"}

    rep = json.loads((d / "cycle/report.json").read_text())
    print(f"[{char}/{direction}] 判定={rep['verdict']}  耗时={time.time()-t0:.0f}s", flush=True)
    return rep


if __name__ == "__main__":
    char = sys.argv[1] if len(sys.argv) > 1 else "aila"
    dirs = sys.argv[2:] or ["right"]
    summary = {}
    sf = ROOT / "process_summary.json"
    if sf.exists():
        summary = json.loads(sf.read_text())
    for dd in dirs:
        try:
            summary[f"{char}/{dd}"] = process(char, dd)
        except Exception as e:
            print(f"[{char}/{dd}] FAIL {type(e).__name__}: {e}", flush=True)
            summary[f"{char}/{dd}"] = {"error": f"{type(e).__name__}: {e}"}
        sf.write_text(json.dumps(summary, ensure_ascii=False, indent=2))
    print("\nPIPELINE DONE", flush=True)
