#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
美术资源后处理与规格校验工具

用法：
    python art_asset_tools.py check   <dir>                    # 命名/尺寸/格式/透明边合规校验 + 清单
    python art_asset_tools.py trim    <dir> [--out <dir>]       # 批量裁掉透明边
    python art_asset_tools.py keyout  <img> --color "#FF00FF" [--tol 40] [--out <png>]
    python art_asset_tools.py palette <img> [--top 8]            # 提取主色板
    python art_asset_tools.py sheet   <dir> [--cols 6] [--cell 128] [--out <png>]

依赖：Pillow>=9

退出码：0 正常 / 1 参数错 / 2 文件或目录问题 / 3 校验发现不合规项
"""

import argparse
import json
import os
import re
import sys

try:
    from PIL import Image
except ImportError:
    print('❌ 缺少依赖 Pillow，请先执行：pip install Pillow')
    sys.exit(2)

EXTS = ('.png', '.jpg', '.jpeg', '.webp')
# 命名规范：<类别>_<对象>[_<变体或状态>][@v<版本>].<扩展名>
NAME_RE = re.compile(
    r'^(char|mon|env|ui|icon|fx|font)_[a-z0-9]+(?:_[a-z0-9]+)*(@v\d+)?\.(png|jpg|jpeg|webp)$')
# 允许的后缀：透明底版本与中间产物
SUFFIX_OK = ('_src', '_deprecated')
# 这些类别必须带透明通道；env（场景/背景）允许不透明，不按缺陷处理
ALPHA_REQUIRED = ('char', 'mon', 'ui', 'icon', 'fx', 'font')
MIN_CELL = 24   # 接触表单格最小像素


def harden_streams():
    """Windows 中文控制台默认 GBK，直接打印 ❌ / ⚠️ 会 UnicodeEncodeError —— 报错时报错。"""
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding='utf-8', errors='replace')
        except (AttributeError, ValueError, OSError):
            pass


def _category(name):
    """从文件名取类别前缀（去掉 _src / _deprecated 后缀）。"""
    stem = name.rsplit('.', 1)[0]
    for sfx in SUFFIX_OK:
        if stem.endswith(sfx):
            stem = stem[:-len(sfx)]
    return stem.split('_', 1)[0].lower()


def _list_images(d):
    if not os.path.isdir(d):
        print('❌ 目录不存在：%s' % d)
        sys.exit(2)
    out = []
    for root, dirs, files in os.walk(d):
        # 跳过工具自己的输出目录（_trimmed / _contact_sheet 等），避免重复扫描
        dirs[:] = [x for x in dirs if not x.startswith('_')]
        for f in files:
            if f.lower().endswith(EXTS) and not f.startswith('_'):
                out.append(os.path.join(root, f))
    return sorted(out)


def _is_pow2(n):
    return n > 0 and (n & (n - 1)) == 0


def _alpha_report(im):
    """返回 (是否有透明通道, 可裁掉的边框像素数, 半透明边缘像素数)"""
    if im.mode not in ('RGBA', 'LA'):
        return False, 0, 0
    a = im.getchannel('A')
    bbox = a.getbbox()
    crop = 0
    if bbox:
        crop = (im.width * im.height) - ((bbox[2] - bbox[0]) * (bbox[3] - bbox[1]))
    # 边缘 2px 内的半透明像素（抠图不干净的信号）
    # 注意：上下/左右各取 2 行（列），小图时窗口会重叠，用集合去重避免重复计数
    half = 0
    w, h = im.size
    px = a.load()
    edge_rows = sorted(set(list(range(0, min(2, h))) + list(range(max(0, h - 2), h))))
    edge_cols = sorted(set(list(range(0, min(2, w))) + list(range(max(0, w - 2), w))))
    for x in range(w):
        for y in edge_rows:
            if 0 < px[x, y] < 250:
                half += 1
    for y in range(h):
        for x in edge_cols:
            if 0 < px[x, y] < 250:
                half += 1
    return True, crop, half


def cmd_check(args):
    files = _list_images(args.dir)
    if not files:
        print('⚠️ 目录下没有图片文件：%s' % args.dir)
        return 0
    problems, manifest = [], []
    for p in files:
        name = os.path.basename(p)
        stem = name.rsplit('.', 1)[0]
        base = stem
        for sfx in SUFFIX_OK:
            if base.endswith(sfx):
                base = base[:-len(sfx)]
                break
        item = {'file': os.path.relpath(p, args.dir), 'size': None, 'mode': None, 'issues': []}
        if not NAME_RE.match(base + os.path.splitext(name)[1]):
            item['issues'].append('命名不符合规范')
        try:
            with Image.open(p) as im:
                item['size'] = '%dx%d' % im.size
                item['mode'] = im.mode
                if not (_is_pow2(im.width) and _is_pow2(im.height)):
                    item['issues'].append('尺寸非 2 的幂')
                has_a, crop, half = _alpha_report(im)
                if has_a and crop > 0:
                    item['issues'].append('残留透明边（可裁 %d px²）' % crop)
                if half > 0:
                    item['issues'].append('边缘半透明像素 %d 个（抠图不干净/有外发光）' % half)
                # 只有"本该透明"的类别才把缺失透明通道判为缺陷；
                # env（场景/背景）允许不透明，否则会把合法的背景图误报成不合规
                if (not has_a and name.lower().endswith('.png')
                        and _category(name) in ALPHA_REQUIRED):
                    item['issues'].append('PNG 无透明通道（%s 类应为透明底）' % _category(name))
        except Exception as e:
            item['issues'].append('无法读取：%s' % e)
        if item['issues']:
            problems.append(item)
        manifest.append(item)

    print('检查目录：%s' % args.dir)
    print('图片 %d 个 ｜ 不合规 %d 个' % (len(manifest), len(problems)))
    for it in problems:
        print('  ⚠️ %-38s %s' % (it['file'], '；'.join(it['issues'])))
    if not problems:
        print('  ✅ 全部通过命名 / 尺寸 / 透明边检查')
    print()
    print('清单（前 20 条）：')
    for it in manifest[:20]:
        print('  %-38s %-12s %s' % (it['file'], it['size'] or '-', it['mode'] or '-'))
    if len(manifest) > 20:
        print('  …（共 %d 条，完整清单见 JSON 输出）' % len(manifest))
    if args.json:
        with open(args.json, 'w', encoding='utf-8') as f:
            json.dump(manifest, f, ensure_ascii=False, indent=2)
        print('\n已写入清单：%s' % args.json)
    return 3 if problems else 0


def cmd_trim(args):
    files = _list_images(args.dir)
    if not files:
        print('⚠️ 目录下没有图片文件：%s' % args.dir)
        return 0
    outdir = args.out or os.path.join(args.dir, '_trimmed')
    n = 0
    for p in files:
        try:
            with Image.open(p) as im:
                if im.mode not in ('RGBA', 'LA'):
                    print('  · 跳过（无透明通道）：%s' % os.path.basename(p))
                    continue
                bbox = im.getchannel('A').getbbox()
                if not bbox:
                    print('  · 跳过（整图透明）：%s' % os.path.basename(p))
                    continue
                if bbox == (0, 0, *im.size):
                    print('  · 无需裁切：%s' % os.path.basename(p))
                    continue
                # 保留相对路径：不同子目录下的同名文件否则会互相覆盖（静默丢文件）
                rel = os.path.relpath(p, args.dir)
                dst = os.path.join(outdir, rel)
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                im.crop(bbox).save(dst)
                n += 1
                print('  ✅ 已裁切 %s → %dx%d' % (rel, bbox[2] - bbox[0], bbox[3] - bbox[1]))
        except Exception as e:
            print('  ❌ %s：%s' % (os.path.basename(p), e))
    print('\n共处理 %d 个文件，输出目录：%s' % (n, outdir))
    return 0


def _parse_hex(s):
    t = (s or '').strip().lstrip('#')
    if len(t) != 6:
        return None
    try:
        return tuple(int(t[i:i + 2], 16) for i in (0, 2, 4))
    except ValueError:
        return None


def cmd_keyout(args):
    if not os.path.isfile(args.img):
        print('❌ 文件不存在：%s' % args.img)
        return 2
    key = _parse_hex(args.color)
    if key is None:
        print('❌ --color 期望 #RRGGBB，实际是 %r' % args.color)
        return 1
    # 负数容差会被平方成正数、静默等价于正容差，必须显式拒绝
    if args.tol < 0:
        print('❌ --tol 不能为负数，实际是 %d' % args.tol)
        return 1
    out = args.out or os.path.splitext(args.img)[0] + '_alpha.png'
    if os.path.isdir(out):
        print('❌ 输出路径是一个目录，请指定 .png 文件名：%s' % out)
        return 2
    try:
        with Image.open(args.img) as im:
            im = im.convert('RGBA')
            px = im.load()
            w, h = im.size
            tol2 = args.tol * args.tol * 3
            removed = 0
            kept = 0
            for x in range(w):
                for y in range(h):
                    r, g, b, a = px[x, y]
                    if a == 0:
                        continue
                    d = (r - key[0]) ** 2 + (g - key[1]) ** 2 + (b - key[2]) ** 2
                    if d <= tol2:
                        px[x, y] = (r, g, b, 0)
                        removed += 1
                    else:
                        kept += 1
            bbox = im.getchannel('A').getbbox()
            # 整图被抠空：不能输出一张全透明的空图还报成功 —— 那是最难发现的静默错误
            if bbox is None or kept == 0:
                print('❌ 整张图都被判为底色，没有剩下任何不透明像素：%s' % args.img)
                print('   像素 %d×%d ｜ 被判为底色 %d 个' % (w, h, removed))
                print('   请确认 --color 是否取到了背景色（可用 palette 命令先取色），或调小 --tol（当前 %d）。' % args.tol)
                return 3
            cropped = im.crop(bbox)
            if os.path.exists(out):
                print('   ⚠️ 覆盖已存在的输出文件：%s' % out)
            cropped.save(out)
    except OSError as e:
        print('❌ 读写失败：%s（%s）' % (args.img, e))
        return 2
    except Exception as e:
        print('❌ 处理失败：%s' % e)
        return 2
    print('✅ 已转透明底：%s' % out)
    print('   去除底色像素 %d 个 ｜ 保留主体像素 %d 个 ｜ 输出尺寸 %dx%d'
          % (removed, kept, cropped.width, cropped.height))
    _, crop, half = _alpha_report(cropped)
    if half:
        print('   ⚠️ 边缘仍有 %d 个半透明像素，建议检查容差或人工修边' % half)
    return 0


def cmd_palette(args):
    if not os.path.isfile(args.img):
        print('❌ 文件不存在：%s' % args.img)
        return 2
    try:
        with Image.open(args.img) as im:
            im = im.convert('RGBA')
            # 大图先缩到 512 以内：既够取色，又避免逐像素统计过慢
            if max(im.size) > 512:
                im.thumbnail((512, 512), Image.LANCZOS)
            data = im.tobytes()
    except Exception as e:
        print('❌ 读取失败：%s' % e)
        return 2

    # 只统计不透明像素（否则透明区会被算进配色，占比失真）
    counts = {}
    for i in range(0, len(data), 4):
        if data[i + 3] > 128:
            key = (data[i], data[i + 1], data[i + 2])
            counts[key] = counts.get(key, 0) + 1
    if not counts:
        print('⚠️ 图中没有不透明像素（全透明？）')
        return 0

    # 按通道量化合并近似色，取前 N
    top = max(1, args.top)
    merged = {}
    for (r, g, b), c in counts.items():
        k = (r >> 3 << 3, g >> 3 << 3, b >> 3 << 3)
        merged[k] = merged.get(k, 0) + c
    total = sum(merged.values())
    ranked = sorted(merged.items(), key=lambda kv: -kv[1])[:top]
    print('主色板（%s，不透明像素 %d 个）：' % (args.img, total))
    for (r, g, b), cnt in ranked:
        print('  #%02X%02X%02X  占比 %5.1f%%' % (r, g, b, cnt * 100.0 / total))
    return 0


def cmd_sheet(args):
    files = _list_images(args.dir)
    if not files:
        print('⚠️ 目录下没有图片文件：%s' % args.dir)
        return 0
    # 太小会让缩略图尺寸算成负数，产出无意义的碎图却报成功 —— 直接拦下
    if args.cell < MIN_CELL:
        print('❌ --cell 太小：%d（最小 %d）。接触表用于缩略图测试，格子太小看不出问题。'
              % (args.cell, MIN_CELL))
        return 1
    cell = args.cell
    cols = max(1, args.cols)
    if args.cols < 1:
        print('   ⚠️ --cols %d 已按 1 处理' % args.cols)
    rows = (len(files) + cols - 1) // cols
    sheet = Image.new('RGBA', (cols * cell, rows * cell), (240, 240, 240, 255))
    placed = 0
    for i, p in enumerate(files):
        try:
            with Image.open(p) as im:
                im = im.convert('RGBA')
                im.thumbnail((cell - 8, cell - 8), Image.LANCZOS)
                x = (i % cols) * cell + (cell - im.width) // 2
                y = (i // cols) * cell + (cell - im.height) // 2
                sheet.alpha_composite(im, (x, y))
                placed += 1
        except Exception as e:
            print('  ⚠️ 跳过 %s：%s' % (os.path.basename(p), e))
    if placed == 0:
        print('❌ 没有一张图能放入接触表，未生成文件')
        return 2
    out = args.out or os.path.join(args.dir, '_contact_sheet.png')
    if os.path.isdir(out):
        print('❌ 输出路径是一个目录，请指定 .png 文件名：%s' % out)
        return 2
    sheet.convert('RGB').save(out)
    print('✅ 已生成接触表：%s（%d 张，%d 列，单格 %dpx）' % (out, placed, cols, cell))
    print('   用途：缩略图测试 —— 缩到这个尺寸还认不出是谁，说明剪影或明度有问题')
    return 0


def main():
    harden_streams()
    ap = argparse.ArgumentParser(description='美术资源后处理与规格校验')
    sub = ap.add_subparsers(dest='cmd')

    c = sub.add_parser('check', help='命名/尺寸/格式/透明边合规校验')
    c.add_argument('dir')
    c.add_argument('--json', help='把清单写入 JSON 文件')

    t = sub.add_parser('trim', help='批量裁掉透明边')
    t.add_argument('dir')
    t.add_argument('--out', help='输出目录（默认 <dir>/_trimmed）')

    k = sub.add_parser('keyout', help='纯色底转透明底')
    k.add_argument('img')
    k.add_argument('--color', required=True, help='要去掉的底色，如 #FF00FF')
    k.add_argument('--tol', type=int, default=40, help='颜色容差，默认 40')
    k.add_argument('--out', help='输出路径（默认 <name>_alpha.png）')

    p = sub.add_parser('palette', help='提取主色板')
    p.add_argument('img')
    p.add_argument('--top', type=int, default=8)

    s = sub.add_parser('sheet', help='生成接触表（缩略图测试）')
    s.add_argument('dir')
    s.add_argument('--cols', type=int, default=6)
    s.add_argument('--cell', type=int, default=128)
    s.add_argument('--out')

    args = ap.parse_args()
    if not args.cmd:
        ap.print_help()
        return 1
    return {'check': cmd_check, 'trim': cmd_trim, 'keyout': cmd_keyout,
            'palette': cmd_palette, 'sheet': cmd_sheet}[args.cmd](args)


if __name__ == '__main__':
    sys.exit(main())
