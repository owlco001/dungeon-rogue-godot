#!/usr/bin/env python3
"""下载实验视频 -> 抽帧 -> rembg 抠图 -> 跑 video_to_sprite 评估"""
import os
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))  # 让同目录的 agnes_path 可导入
from agnes_path import require_agnes_client  # noqa: E402
ac = require_agnes_client()  # 跨仓库依赖，缺失时给出修复指引

WORK = Path("/tmp/artwork/vprompt")


def download(url: str, dst: Path) -> Path:
    dst.parent.mkdir(parents=True, exist_ok=True)
    r = ac._get(url) if hasattr(ac, "_get") else None
    if r is None:
        import urllib.request
        with urllib.request.urlopen(url, timeout=180) as f, open(dst, "wb") as o:
            o.write(f.read())
    return dst


def run(tag: str) -> None:
    import json
    d = WORK / tag
    res = json.loads((d / "result.json").read_text())
    url = None
    for k in ("video_url", "url", "video", "output_url"):
        v = res.get(k)
        if isinstance(v, str) and v.startswith("http"):
            url = v
            break
    if not url:
        print(f"[{tag}] no url, keys={list(res)}")
        return
    mp4 = d / "out.mp4"
    print(f"[{tag}] downloading {url[:80]}", flush=True)
    download(url, mp4)
    print(f"[{tag}] size={mp4.stat().st_size}", flush=True)

    fr = d / "frames"
    fr.mkdir(exist_ok=True)
    subprocess.run(["ffmpeg", "-y", "-i", str(mp4), "-vsync", "0",
                    str(fr / "f_%03d.png")], check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    n_raw = len(list(fr.glob("*.png")))
    print(f"[{tag}] raw frames={n_raw}", flush=True)

    cuts = d / "cuts"
    cuts.mkdir(exist_ok=True)
    # rembg>=2.0.72 返回 Image 对象（无 .data），需显式 save；用文件循环避免单次内存爆掉
    cut_script = f'''
import sys
from pathlib import Path
from PIL import Image
from rembg import remove
src = Path("{fr}"); out = Path("{cuts}"); out.mkdir(parents=True, exist_ok=True)
for i, f in enumerate(sorted(src.glob("*.png")), 1):
    res = remove(Image.open(f).convert("RGBA"))
    if not isinstance(res, Image.Image):
        res = Image.open(__import__("io").BytesIO(res))
    res.save(out / ("f_%03d.png" % i))
'''
    subprocess.run(["python3", "-c", cut_script], env=dict(os.environ), check=True)
    print(f"[{tag}] cut frames={len(list(cuts.glob('*.png')))}", flush=True)

    r = subprocess.run([sys.executable, str(Path(__file__).resolve().parent / "video_to_sprite.py"),
                        str(cuts), str(d / "cycle"), "384", "12.0"],
                       capture_output=True, text=True)
    print(f"[{tag}] {r.stdout}", flush=True)
    if r.returncode:
        print(f"[{tag}] ERR {r.stderr[-800:]}", flush=True)


if __name__ == "__main__":
    for t in sys.argv[1:]:
        try:
            run(t)
        except Exception as e:
            print(f"[{t}] FAIL {type(e).__name__}: {e}", flush=True)
