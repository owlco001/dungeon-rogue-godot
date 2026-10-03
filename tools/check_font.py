#!/usr/bin/env python3
"""Font gate: every player-visible character used in game scripts/scenes must
exist in assets/fonts/hud-subset.ttf (Web has no system-font fallback -> tofu).

历史误报（已修）：原实现扫描**整个文件**，把 `#` 注释里的中文也算进去。
2026-10-03 实测：`伴/势/姿/朝/省/素` 6 个字只出现在代码注释里
（如 player.gd:132「必须排除 .import 伴随文件」），玩家永远看不到，
却被报成「缺字形」。这类误报会让真正的缺字问题被淹没。

现在只统计**玩家可见文本**：
  - 有字符串字面量的行：只取字面量内容（那是真正显示的文案）
  - 无字面量的行：剔除 `#` 注释后再取（覆盖 lang 键等场景）
退出码 1 表示确有玩家可见文字缺字形。
"""
import glob
import re
import sys
from pathlib import Path

from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parent.parent

# 玩家实际看到的文字来自这些文件
PATTERNS = ("scripts/**/*.gd", "systems/**/*.gd", "scenes/**/*.tscn")

_STR = re.compile(r'"([^"\n]*)"')


def visible_chars(text: str) -> set:
    """返回玩家可能看到的非 ASCII 字符集合（剔除行注释）。"""
    out = set()
    for line in text.splitlines():
        strings = _STR.findall(line)
        if strings:
            for s in strings:
                out.update(ch for ch in s if ord(ch) > 127)
        else:
            code = line.split("#", 1)[0]
            out.update(ch for ch in code if ord(ch) > 127)
    return out


def main() -> int:
    cmap = TTFont(str(ROOT / "assets/fonts/hud-subset.ttf")).getBestCmap()
    used = set()
    for pat in PATTERNS:
        for path in glob.glob(str(ROOT / pat), recursive=True):
            used |= visible_chars(Path(path).read_text(encoding="utf-8"))

    missing = sorted(c for c in used if ord(c) not in cmap)
    if missing:
        print("check_font: FAIL — %d missing glyphs: %s"
              % (len(missing), "".join(missing)))
        return 1
    print("check_font: OK (%d glyphs, %d player-visible chars covered)"
          % (len(cmap), len(used)))
    return 0


if __name__ == "__main__":
    sys.exit(main())