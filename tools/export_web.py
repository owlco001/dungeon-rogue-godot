#!/usr/bin/env python3
"""v0.8 B8 Web 多文件导出（替代 build_single_html.py 的单文件路线）。

流程：Godot 导出 web/index.* → 重命名为 dungeon-rogue-v08.* → 音频 worklet
改名 godot.audio.*（引擎 locateFile 的固定名）→ 打印体积与 brotli 首包估算。
门禁：pck ≤ 5MB、brotli 首包（html+js+wasm+pck）≤ 12MB。
"""
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WEB = ROOT / "web"
GODOT = Path.home() / "workspace/.tools/godot/Godot_v4.7.2-stable_linux.x86_64"
NAME = "dungeon-rogue-v08"


def brotli_size(path: Path) -> int:
    try:
        import brotli
        return len(brotli.compress(path.read_bytes(), quality=11))
    except ImportError:
        import gzip
        return len(gzip.compress(path.read_bytes(), compresslevel=9))


def main() -> int:
    r = subprocess.run(
        [str(GODOT), "--headless", "--path", str(ROOT),
         "--export-release", "Web", str(WEB / "index.html")],
        capture_output=True, text=True, timeout=600)
    if r.returncode != 0:
        print(r.stdout[-2000:], r.stderr[-2000:])
        print("EXPORT FAILED")
        return 1
    # 重命名 index.* → dungeon-rogue-v08.*
    for ext in ("html", "js", "wasm", "pck"):
        src = WEB / f"index.{ext}"
        dst = WEB / f"{NAME}.{ext}"
        shutil.copyfile(src, dst)
    # HTML 内 executable 名 index → v08（引擎据此拼 pck/wasm 名）
    html = (WEB / f"{NAME}.html").read_text(encoding="utf-8")
    assert '"executable":"index"' in html, "executable pattern drifted"
    html = html.replace('"executable":"index"', f'"executable":"{NAME}"')
    html = html.replace("index.js", f"{NAME}.js")
    html = html.replace('"index.pck"', f'"{NAME}.pck"').replace(
        '"index.wasm"', f'"{NAME}.wasm"')
    (WEB / f"{NAME}.html").write_text(html, encoding="utf-8")
    # 音频 worklet 改引擎固定名
    shutil.copyfile(WEB / "index.audio.worklet.js", WEB / "godot.audio.worklet.js")
    shutil.copyfile(WEB / "index.audio.position.worklet.js",
                    WEB / "godot.audio.position.worklet.js")
    # 体积报告 + 门禁
    parts = {}
    total_br = 0
    for ext in ("html", "js", "wasm", "pck"):
        p = WEB / f"{NAME}.{ext}"
        parts[ext] = p.stat().st_size
        total_br += brotli_size(p)
        print(f"{NAME}.{ext}: {parts[ext] / 1048576:.2f} MB")
    print(f"brotli first-load total: {total_br / 1048576:.2f} MB (limit 12)")
    print(f"pck: {parts['pck'] / 1048576:.2f} MB (limit 5)")
    ok = parts["pck"] <= 5 * 1048576 and total_br <= 12 * 1048576
    print("SIZE GATE:", "PASS" if ok else "FAIL")
    return 0 if ok else 2


if __name__ == "__main__":
    sys.exit(main())
