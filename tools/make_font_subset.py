#!/usr/bin/env python3
"""Regenerate assets/fonts/hud-subset.ttf from system Noto Sans CJK SC.

Char set = every character appearing in any game script/scene text
(scripts/, systems/, scenes/) + the previous subset's chars + ASCII.
Run tools/check_font.py afterwards to prove zero missing glyphs.
"""
import glob
import subprocess
import sys
from pathlib import Path

from fontTools.ttLib import TTFont, TTCollection

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets/fonts/hud-subset.ttf"
SRC_TTC = "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"


def collect_chars() -> set:
    chars = set(chr(c) for c in range(0x20, 0x7F))  # printable ASCII
    for pat in ("scripts/**/*.gd", "systems/**/*.gd", "scenes/**/*.tscn"):
        for path in glob.glob(str(ROOT / pat), recursive=True):
            for ch in Path(path).read_text(encoding="utf-8"):
                if ch not in "\n\r\t":
                    chars.add(ch)
    if OUT.exists():
        old = TTFont(str(OUT)).getBestCmap()
        chars |= {chr(c) for c in old.keys()}
    return chars


def sc_face_index() -> int:
    coll = TTCollection(SRC_TTC)
    for i, f in enumerate(coll.fonts):
        if f["name"].getDebugName(1) == "Noto Sans CJK SC":
            return i
    raise SystemExit("Noto Sans CJK SC face not found in TTC")


def main() -> None:
    chars = collect_chars()
    unicodes = ",".join("U+%04X" % ord(c) for c in sorted(chars))
    idx = sc_face_index()
    tmp = "/tmp/noto_sc_full.ttf"
    # Extract the SC face to a standalone TTF first (pyftsubset handles TTC poorly).
    coll = TTCollection(SRC_TTC)
    coll.fonts[idx].save(tmp)
    subprocess.run(
        [sys.executable, "-m", "fontTools.subset", tmp,
         "--unicodes=" + unicodes,
         "--output-file=" + str(OUT),
         "--layout-features=", "--no-hinting",
         "--desubroutinize", "--name-IDs="],
        check=True)
    print("subset written:", OUT, OUT.stat().st_size, "bytes,",
          len(TTFont(str(OUT)).getBestCmap()), "glyphs")


if __name__ == "__main__":
    main()
