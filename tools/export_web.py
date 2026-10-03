#!/usr/bin/env python3
"""v0.8 B8 Web 多文件导出（替代 build_single_html.py 的单文件路线）。

流程：Godot 导出 web/index.* → 重命名为 dungeon-rogue-v08.* → 音频 worklet
改名 godot.audio.*（引擎 locateFile 的固定名）→ 打印体积与 brotli 首包估算。
门禁：pck 与 brotli 首包（html+js+wasm+pck）体积上限，
阈值见LIMIT_PCK / LIMIT_BR，可用 WEB_LIMIT_PCK_MB / WEB_LIMIT_BR_MB 覆盖。

前置条件：必须先装好对应版本的 Web 导出模板，且模板必须是 zip 形态
（文件名与版本号严格匹配），否则报No export template found：
    ~/.local/share/godot/export_templates/<版本>/web_nothreads_release.zip
模板可从 https://github.com/godotengine/godot/releases 的
Godot_v<版本>-stable_export_templates.tpz 取（全量 1.2GB+），
也可只取 web_nothreads_release.zip 手工放到上述路径。
"""
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WEB = ROOT / "web"
GODOT = Path(os.environ.get("GODOT_BIN", shutil.which("godot") or "godot"))
NAME = "dungeon-rogue-v08"

# 体积门禁阈值（可被环境变量覆盖，便于CI 或临时放宽/收紧）
# 2026-10-03 由 5/12MB 调高到 40/45MB，依据见main() 内注释。
MB = 1048576
LIMIT_PCK = int(os.environ.get("WEB_LIMIT_PCK_MB", "40")) * MB
LIMIT_BR = int(os.environ.get("WEB_LIMIT_BR_MB", "45")) * MB


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
    #
    # 阈值调整记录（2026-10-03，用户决定「按实际体积调高」）：
    # 原阈值 pck≤5MB / brotli 首包 ≤12MB 是 v0.8 初建时随手设的，
    # 当时素材量仅 aila + mofei + 少量杂兵，且文档里从未留下定阈值的依据。
    # 随素材补齐（batong 四向 walk 97 张 384px 帧 = 16MB，aila 11MB，
    # characters 目录合计 29MB）已远超原阈值，pck 实测 33.45MB。
    # 现按「实际体积 + 合理余量」重设，并在超限时打印构成便于定位大头。
    #
    # 注意：真正卡首包的是 wasm（37.68MB，不随素材变化）。
    # 要实质压缩首包应动 Godot 引擎（换更小的构建/开 wasm-opt），
    # 而不是砍素材 —— 素材是功能，引擎体积是可优化项。
    PARTS = {}
    total_br = 0
    for ext in ("html", "js", "wasm", "pck"):
        p = WEB / f"{NAME}.{ext}"
        PARTS[ext] = p.stat().st_size
        total_br += brotli_size(p)
        print(f"{NAME}.{ext}: {PARTS[ext] / 1048576:.2f} MB")
    print(f"brotli first-load total: {total_br / 1048576:.2f} MB (limit {LIMIT_BR / 1048576:.0f})")
    print(f"pck: {PARTS['pck'] / 1048576:.2f} MB (limit {LIMIT_PCK / 1048576:.0f})")
    ok = PARTS["pck"] <= LIMIT_PCK and total_br <= LIMIT_BR
    if not ok:
        over_pck = PARTS['pck'] / 1048576 - LIMIT_PCK / 1048576
        over_br = total_br / 1048576 - LIMIT_BR / 1048576
        print(f"  超限: pck +{over_pck:.2f}MB  首包 +{over_br:.2f}MB")
        print("  定位: 素材改用 exclude_filter 排除，引擎体积需换构建/开压缩")
    print("SIZE GATE:", "PASS" if ok else "FAIL")
    return 0 if ok else 2


if __name__ == "__main__":
    sys.exit(main())
