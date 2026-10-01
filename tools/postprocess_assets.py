#!/usr/bin/env python3
"""批量资产后处理：rembg 抠图 -> union bbox 裁剪 -> 缩放到目标尺寸。
串行执行（7GB 内存，并行必 OOM）。用 venv python 运行：~/workspace/.rbg-venv/bin/python
输入：assets/.staging/<batch>/files.json；输出：assets/<final 路径>。
"""
import json, os, sys, gc
from pathlib import Path
from PIL import Image

ASSETS = Path(__file__).resolve().parent.parent / "assets"
STAGING = ASSETS / ".staging"

def load_entries():
    entries = []
    for fj in sorted(STAGING.glob("*/files.json")):
        data = json.loads(fj.read_text())
        items = data if isinstance(data, list) else data.get("items", data.get("entries", []))
        for e in items:
            if e.get("status") == "failed":
                print(f"SKIP failed: {e.get('id')}")
                continue
            e["_batch"] = fj.parent.name
            entries.append(e)
    return entries

def main():
    from rembg import new_session, remove
    session = new_session("u2net")  # 铁律：必须 u2net，默认模型会下 1GB
    entries = load_entries()
    print(f"entries: {len(entries)}")

    # 第一遍：rembg + 取 bbox，按 set 累 union bbox
    bboxes = {}   # set -> [x0,y0,x1,y1]
    cutouts = {}  # id -> RGBA image (抠图后)
    for e in entries:
        rawp = e["raw"]
        base = ASSETS.parent  # ~/workspace/games/dungeon-rogue-godot/
        if rawp.startswith("/"):
            raw = Path(rawp)
        elif rawp.startswith("assets/"):
            raw = base / rawp
        else:
            raw = STAGING / e["_batch"] / rawp  # batch 相对路径
        kind = e["kind"]
        img = Image.open(raw).convert("RGBA")
        if kind == "tile":
            # tile 全幅，不抠图
            cutouts[e["id"]] = img
            w, h = img.size
            bboxes.setdefault(e["set"], [0, 0, w, h])
            continue
        out = remove(img, session=session)
        cutouts[e["id"]] = out
        bb = out.getbbox()
        if not bb:
            print(f"WARN empty alpha: {e['id']}, 用全图")
            bb = (0, 0, out.size[0], out.size[1])
        s = e["set"]
        if s in bboxes:
            b = bboxes[s]
            bboxes[s] = [min(b[0], bb[0]), min(b[1], bb[1]), max(b[2], bb[2]), max(b[3], bb[3])]
        else:
            bboxes[s] = list(bb)
        del img, out
        gc.collect()
    print(f"sets: {len(bboxes)}")

    # 第二遍：按 union bbox 裁剪 -> 正方形 pad -> resize -> 落盘
    ok, fail = 0, []
    for e in entries:
        try:
            img = cutouts[e["id"]]
            kind = e["kind"]
            size = int(e["size"])
            if kind == "tile":
                fin = img.resize((size, size), Image.LANCZOS).convert("RGB")
            else:
                x0, y0, x1, y1 = bboxes[e["set"]]
                pad = int(max(x1 - x0, y1 - y0) * 0.06) + 4
                x0, y0 = max(0, x0 - pad), max(0, y0 - pad)
                x1, y1 = min(img.size[0], x1 + pad), min(img.size[1], y1 + pad)
                crop = img.crop((x0, y0, x1, y1))
                side = max(crop.size)
                sq = Image.new("RGBA", (side, side), (0, 0, 0, 0))
                sq.paste(crop, ((side - crop.size[0]) // 2, (side - crop.size[1]) // 2), crop)
                fin = sq.resize((size, size), Image.LANCZOS)
            dest = ASSETS / e["final"].replace("assets/", "", 1) if e["final"].startswith("assets/") else ASSETS / e["final"]
            dest.parent.mkdir(parents=True, exist_ok=True)
            fin.save(dest)
            assert dest.stat().st_size > 0
            ok += 1
            del fin
        except Exception as ex:
            fail.append((e["id"], str(ex)))
            print(f"FAIL {e['id']}: {ex}")
        gc.collect()

    print(f"done: ok={ok} fail={len(fail)}")
    for i, m in fail:
        print("FAILED:", i, m)

if __name__ == "__main__":
    main()
