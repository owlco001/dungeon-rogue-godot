#!/usr/bin/env python3
"""Font gate: every character used in game scripts/scenes must exist in
assets/fonts/hud-subset.ttf (Web has no system-font fallback -> tofu boxes).
Exit 1 with the missing set if any glyph is absent."""
import glob
import sys
from pathlib import Path

from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parent.parent


def main() -> int:
    cmap = TTFont(str(ROOT / "assets/fonts/hud-subset.ttf")).getBestCmap()
    used = set()
    for pat in ("scripts/**/*.gd", "systems/**/*.gd", "scenes/**/*.tscn"):
        for path in glob.glob(str(ROOT / pat), recursive=True):
            for ch in Path(path).read_text(encoding="utf-8"):
                if ord(ch) > 127:
                    used.add(ch)
    missing = sorted(c for c in used if ord(c) not in cmap)
    if missing:
        print("check_font: FAIL — %d missing glyphs: %s"
              % (len(missing), "".join(missing)))
        return 1
    print("check_font: OK (%d glyphs, %d used chars covered)"
          % (len(cmap), len(used)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
