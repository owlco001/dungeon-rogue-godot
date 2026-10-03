#!/usr/bin/env python3
"""生成脚本的共享路径解析：定位仓库根目录与 `agnes_client` 模块。

为什么需要本模块（`9235572` 脱敏遗漏的修复）：

`agnes_client` 不在本仓库内，它属于 pavo-drama 项目。此前 7 个生成脚本把它
硬编码成 `sys.path.insert(0, "/workspace/pavo/skill/pavo-drama/scripts")`，
只在「pavo 恰好克隆到那个绝对路径」的机器上才能跑。已改为本模块统一解析。

解析顺序（全部可覆盖，无任何硬编码个人路径）：

1. 环境变量 `AGNES_CLIENT_DIR` —— 显式指定 `agnes_client.py` 所在目录
2. 环境变量 `PAVO_ROOT`          —— pavo-drama 仓库根，在其下自动找 scripts/
3. 环境变量 `PYTHONPATH` 里已可直接 `import agnes_client`
4. 常见相邻位置自动探测（同级仓库、各类 venv site-packages、系统路径）

对应环境变量见 `docs/ENV-SETUP.md` §1/§3。

用法：
    from agnes_path import require_agnes_client, ROOT
    agnes_client = require_agnes_client()   # 找不到就抛带修复指引的 RuntimeError
"""
import importlib.util
import os
import sys
from pathlib import Path

# 仓库根目录：优先 DUNGEON_ROOT，否则按脚本位置自定位（tools/ 的上一级）
ROOT = Path(os.environ.get("DUNGEON_ROOT", Path(__file__).resolve().parent.parent))

# venv 探测候选（相对仓库根 / 相对父目录 / 绝对路径三种写法都覆盖）
_VENV_CANDIDATES = (
    ".rbg-venv/lib/python3.11/site-packages",
    ".rbg-venv/lib/python3.12/site-packages",
    ".rbg-venv/lib/python3/site-packages",
    "venv/lib/python3.11/site-packages",
    "venv/lib/python3/site-packages",
)
# 用 rembg/抠图的脚本通常跑在专用 venv 里，合成目录也一并探测
_SITE_GLOBS = ("lib/python3*/site-packages", "lib64/python3*/site-packages")


def _from_pavo_root() -> "list[Path]":
    """从 PAVO_ROOT 下找出可能的 scripts 目录。"""
    root = os.environ.get("PAVO_ROOT")
    if not root:
        return []
    base = Path(root)
    hits = [base / "skill" / "pavo-drama" / "scripts", base / "scripts", base]
    return [p for p in hits if (p / "agnes_client.py").is_file()]


def _from_siblings() -> "list[Path]":
    """探测仓库同级/上级的 pavo 克隆目录与 venv site-packages。"""
    parent = ROOT.parent
    out: list[Path] = []
    # 同级或上级的 pavo 仓库（目录名允许任意，故按特征文件而非名字找）
    for anc in (ROOT, parent, parent.parent):
        for cand in (
            anc / "pavo" / "skill" / "pavo-drama" / "scripts",
            anc / "pavo-drama" / "scripts",
            anc / "pavo" / "scripts",
        ):
            out.append(cand)
    # 仓库根与父目录下的 venv site-packages
    for anc in (ROOT, parent):
        for rel in _VENV_CANDIDATES:
            out.append(anc / rel)
        for pat in _SITE_GLOBS:
            out.extend(sorted(anc.glob(pat)))
    return out


def _candidates() -> "list[Path]":
    seen: list[Path] = []
    for p in [Path(os.environ["AGNES_CLIENT_DIR"])] if os.environ.get("AGNES_CLIENT_DIR") else []:
        seen.append(p)
    seen.extend(_from_pavo_root())
    seen.extend(_from_siblings())
    # 去重并保持顺序
    uniq: list[Path] = []
    for p in seen:
        if p not in uniq:
            uniq.append(p)
    return uniq


def find_agnes_client() -> "Path | None":
    """返回 `agnes_client.py` 的绝对路径；找不到返回 None。"""
    # 已在 sys.path 中（含 PYTHONPATH 或已 site-packages 安装）
    spec = importlib.util.find_spec("agnes_client")
    if spec and spec.origin and spec.origin != "built-in":
        return Path(spec.origin)
    for cand in _candidates():
        if (cand / "agnes_client.py").is_file():
            return cand / "agnes_client.py"
    return None


def import_agnes_client():
    """导入并返回 `agnes_client` 模块。找不到时抛带修复指引的 RuntimeError。"""
    found = find_agnes_client()
    if found and str(found.parent) not in sys.path:
        sys.path.insert(0, str(found.parent))
    try:
        import agnes_client  # noqa: F401
        return agnes_client
    except ImportError as exc:
        raise RuntimeError(
            "找不到 agnes_client 模块（它属于 pavo-drama 项目，不在本仓库内）。\n"
            "修复任选其一：\n"
            "  1) export PAVO_ROOT=/path/to/pavo            # 自动找 $PAVO_ROOT/skill/pavo-drama/scripts\n"
            "  2) export AGNES_CLIENT_DIR=/path/to/scripts  # 直接指定 agnes_client.py 所在目录\n"
            "  3) export PYTHONPATH=/path/to/scripts:$PYTHONPATH\n"
            "详见 docs/ENV-SETUP.md §3。注意：没有凭据就只能跑验证，不能重新生成素材。"
        ) from exc


def require_agnes_client():
    """`import_agnes_client` 的别名，语义更直白。"""
    return import_agnes_client()


if __name__ == "__main__":
    # 自检：python3 tools/agnes_path.py
    hit = find_agnes_client()
    print("ROOT            :", ROOT)
    print("agnes_client    :", hit if hit else "❌ 未找到")
    print("PAVO_ROOT       :", os.environ.get("PAVO_ROOT", "(未设置)"))
    print("AGNES_CLIENT_DIR:", os.environ.get("AGNES_CLIENT_DIR", "(未设置)"))
    if not hit:
        print("\n修复：设置 PAVO_ROOT 或 AGNES_CLIENT_DIR 指向 agnes_client.py 所在目录，")
        print("详见 docs/ENV-SETUP.md §3。")