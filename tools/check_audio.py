#!/usr/bin/env python3
"""三方一致性校验（07 §2.4）：data/audio_manifest.json ↔ scripts/sfx.gd
生成表 ↔ web/shell.html PLAYERS，另校验全部 Sfx.play/play_at 调用点
引用的音色都存在于 manifest。任一不一致 exit 1。
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def main() -> int:
    errors = []
    manifest = json.loads((ROOT / "data" / "audio_manifest.json").read_text(encoding="utf-8"))
    names = set(manifest["sounds"].keys())

    # shell PLAYERS 键集合
    shell = (ROOT / "web" / "shell.html").read_text(encoding="utf-8")
    m = re.search(r"var PLAYERS = \{(.*?)\n\t\};", shell, re.S)
    if not m:
        errors.append("shell.html: PLAYERS block not found")
        shell_names = set()
    else:
        shell_names = set(re.findall(r"^\t\t(\w+): function", m.group(1), re.M))
    if shell_names != names:
        errors.append("shell PLAYERS != manifest: shell-only=%s manifest-only=%s"
                      % (sorted(shell_names - names), sorted(names - shell_names)))

    # sfx.gd 不得再有硬编码 _streams["x"] 生成（必须走 manifest 分发）
    sfx = (ROOT / "scripts" / "sfx.gd").read_text(encoding="utf-8")
    hard = re.findall(r'_streams\["(\w+)"\]\s*=', sfx)
    if hard:
        errors.append("sfx.gd still hardcodes streams: %s" % hard)
    if "_gen_one" not in sfx or "audio_manifest.json" not in sfx:
        errors.append("sfx.gd is not manifest-driven")

    # 全部调用点引用的音色必须存在
    used = set()
    for gd in ROOT.glob("scripts/**/*.gd"):
        text = gd.read_text(encoding="utf-8")
        used |= set(re.findall(r'Sfx\.play(?:_at)?\("(\w+)"', text))
        used |= set(re.findall(r'\bplay(?:_at)?\("(\w+)"', text)) if gd.name == "sfx.gd" else set()
    missing = used - names
    if missing:
        errors.append("call sites reference unknown sounds: %s" % sorted(missing))

    for e in errors:
        print("AUDIO CHECK FAIL:", e)
    if errors:
        return 1
    print("check_audio: OK (%d sounds, %d referenced)" % (len(names), len(used)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
