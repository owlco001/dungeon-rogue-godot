#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
ppt_kit.py — 各专家包 PPT 生成器的公共底座（**单一来源**）

⚠️ 本文件是唯一来源（canonical）。各专家包 scripts/ 目录下的 ppt_kit.py 是它的**副本**，
   由 sync_ppt_kit.py 同步生成。**请勿单独修改某一份副本** —— 改完跑同步脚本并校验哈希。

提供：
  · 视觉调色板与排版参数（通过 configure() 由各脚本声明，保证各自外观不变）
  · OOXML 安全的中文字体写入（a:latin / a:ea / a:cs 按 schema 顺序插入）
  · 文本框 / 段落 / 页面样板 / 表格 / 原生图表
  · 数据契约校验（缺失板块跳过；字段值不合法则逐条报错）
  · 共用的命令行外壳（读 JSON → 校验 → 生成 → 原子写盘）

依赖：python-pptx>=0.6.21
"""

import json
import os
import sys

from pptx import Presentation
from pptx.chart.data import CategoryChartData
from pptx.dml.color import RGBColor
from pptx.enum.chart import XL_CHART_TYPE, XL_LEGEND_POSITION
from pptx.enum.text import PP_ALIGN, MSO_ANCHOR
from pptx.oxml import parse_xml
from pptx.oxml.ns import nsdecls, qn
from pptx.util import Inches, Pt

# ---------- 通用常量（两个脚本取值一致，不需要 configure）----------
FONT = '微软雅黑'
C_TEXT = RGBColor(0x33, 0x33, 0x33)
C_MUTED = RGBColor(0x80, 0x80, 0x80)
C_WARN = RGBColor(0xD4, 0x7A, 0x00)      # 风险 / 待定：橙
C_OK = RGBColor(0x1E, 0x7B, 0x34)        # 已定 / 可行：绿
C_UP = RGBColor(0xC0, 0x00, 0x00)        # 中文习惯：增长用红
C_DOWN = RGBColor(0x1E, 0x7B, 0x34)      # 中文习惯：下降用绿
C_WHITE = RGBColor(0xFF, 0xFF, 0xFF)

SW, SH = 13.333, 7.5  # 16:9 英寸

# ---------- 各脚本通过 configure() 覆盖的排版参数 ----------
# 默认值 = 财报生成器的取值；策划生成器会覆盖成自己的一套，以保持各自原样
CONFIG = {
    'accent': RGBColor(0x1F, 0x4E, 0x79),
    'title_color': RGBColor(0x1F, 0x2A, 0x44),
    'header_bg': RGBColor(0x1F, 0x4E, 0x79),
    'band_bg': RGBColor(0xF2, 0xF5, 0xF9),
    'title_x': 0.7,
    'title_y': 0.45,
    'title_size': 26,
    'bar_y': 1.28,
    'bar_w': 1.1,
    'table_y': 1.75,
    'chart_y': 1.75,
    'chart_bottom_margin': 1.45,
    'caption_y': SH - 1.32,
    'footer_y': SH - 0.62,
    'footer_h': 0.35,
}

# configure() 后会同步到这几个模块级名字，供脚本 `from ppt_kit import C_ACCENT` 使用
C_ACCENT = CONFIG['accent']
C_TITLE = CONFIG['title_color']
C_HEADER_BG = CONFIG['header_bg']
C_BAND_BG = CONFIG['band_bg']


def configure(**kw):
    """声明本脚本的排版参数。未知参数直接报错，避免拼错键名后静默失效。"""
    unknown = set(kw) - set(CONFIG)
    if unknown:
        raise KeyError('configure() 收到未知参数：%s' % sorted(unknown))
    CONFIG.update(kw)
    global C_ACCENT, C_TITLE, C_HEADER_BG, C_BAND_BG
    C_ACCENT = CONFIG['accent']
    C_TITLE = CONFIG['title_color']
    C_HEADER_BG = CONFIG['header_bg']
    C_BAND_BG = CONFIG['band_bg']


# ---------- OOXML：按 schema 顺序写入中文字体 ----------
# CT_TextCharacterProperties 子元素有严格顺序，写错 PowerPoint 会提示「需要修复」
_RPR_ORDER = [
    'a:ln', 'a:noFill', 'a:solidFill', 'a:gradFill', 'a:blipFill', 'a:pattFill', 'a:grpFill',
    'a:effectLst', 'a:effectDag', 'a:highlight', 'a:uLnTx', 'a:uLn', 'a:uFillTx', 'a:uFill',
    'a:latin', 'a:ea', 'a:cs', 'a:sym', 'a:hlinkClick', 'a:hlinkMouseOver', 'a:rtl', 'a:extLst',
]


def _ordered_insert(parent, tag, attrs):
    """把 <a:tag> 按 OOXML 规定顺序插入 parent。"""
    el = parent.find(qn(tag))
    if el is None:
        el = parse_xml('<%s %s/>' % (tag, nsdecls('a')))
        idx = _RPR_ORDER.index(tag)
        anchor = None
        for child in parent:
            full = 'a:' + child.tag.split('}')[-1]
            if full in _RPR_ORDER and _RPR_ORDER.index(full) > idx:
                anchor = child
                break
        if anchor is None:
            parent.append(el)
        else:
            anchor.addprevious(el)
    for k, v in attrs.items():
        el.set(k, v)
    return el


def _cjk_on_rpr(rPr, font=FONT):
    _ordered_insert(rPr, 'a:latin', {'typeface': font})
    _ordered_insert(rPr, 'a:ea', {'typeface': font})
    _ordered_insert(rPr, 'a:cs', {'typeface': font})


def style_run(run, size=14, bold=False, color=C_TEXT, font=FONT):
    run.font.size = Pt(size)
    run.font.bold = bold
    run.font.color.rgb = color
    _cjk_on_rpr(run._r.get_or_add_rPr(), font)
    return run


def style_chart_cjk(chart, font=FONT):
    """把图表内部所有文字（含 defRPr / rPr）都指向中文字体。"""
    for el in chart._chartSpace.iter():
        if el.tag in (qn('a:defRPr'), qn('a:rPr')):
            _cjk_on_rpr(el, font)


# ---------- 文本框 / 段落 / 页面样板 ----------
def txbox(slide, x, y, w, h):
    tb = slide.shapes.add_textbox(Inches(x), Inches(y), Inches(w), Inches(h))
    tf = tb.text_frame
    tf.word_wrap = True
    tf.margin_left = tf.margin_right = 0
    tf.margin_top = tf.margin_bottom = 0
    return tf


def para(tf, text, size=14, bold=False, color=C_TEXT, align=PP_ALIGN.LEFT,
         first=False, space_after=6, line=1.25):
    p = tf.paragraphs[0] if first else tf.add_paragraph()
    p.alignment = align
    p.space_after = Pt(space_after)
    p.line_spacing = line
    style_run(p.add_run(), size, bold, color).text = text
    return p


def accent_bar(slide, x, y, w, h):
    """标题下的主色短横线。"""
    bar = slide.shapes.add_shape(1, Inches(x), Inches(y), Inches(w), Inches(h))
    bar.fill.solid()
    bar.fill.fore_color.rgb = CONFIG['accent']
    bar.line.fill.background()
    bar.shadow.inherit = False
    return bar


def slide_title(slide, title, sub=None):
    c = CONFIG
    tf = txbox(slide, c['title_x'], c['title_y'], SW - 2 * c['title_x'], 0.75)
    para(tf, title, size=c['title_size'], bold=True, color=c['title_color'], first=True, space_after=2)
    if sub:
        para(tf, sub, size=12, color=C_MUTED, space_after=0)
    accent_bar(slide, c['title_x'], c['bar_y'], c['bar_w'], 0.055)


def new_page(prs, layout, title, sub=None):
    """新建一页并写好标题，省掉每个板块三行样板。"""
    slide = prs.slides.add_slide(layout)
    slide_title(slide, title, sub)
    return slide


def footer(slide, text):
    c = CONFIG
    tf = txbox(slide, 0.7, c['footer_y'], SW - 1.4, c['footer_h'])
    para(tf, text, size=9, color=C_MUTED, first=True, space_after=0)


def caption(slide, text, y=None):
    """图表/表格下方的一句话说明。"""
    y = CONFIG['caption_y'] if y is None else y
    tf = txbox(slide, 0.7, y, SW - 1.4, 0.55)
    para(tf, '一句话：' + text, size=12.5, color=CONFIG['title_color'], first=True, space_after=0)


# ---------- 表格 ----------
def add_table(slide, headers, rows, x=0.7, y=None, w=None, h=None,
              col_w=None, font_size=12, row_h=0.34, cell_color=None, cell_fill=None,
              max_rows=None):
    """cell_color(text, col) -> RGBColor|None 控制文字色；
    cell_fill(text, row, col) -> RGBColor|None 覆盖单元格底色（用于色板一类的彩色格）；
    max_rows：行数上限。超过时截断并补一行说明 —— 否则长表会超出画布、压住页脚。
    """
    y = CONFIG['table_y'] if y is None else y
    rows = list(rows)
    if max_rows and len(rows) > max_rows:
        total = len(rows)
        rows = rows[:max_rows]
        if len(headers) >= 2:
            note = ['…', '共 %d 条，此处仅显示前 %d 条' % (total, max_rows)]
            note += [''] * (len(headers) - 2)
            rows.append(note)
    w = (SW - 1.4) if w is None else w
    h = (0.34 * (len(rows) + 1)) if h is None else h
    shape = slide.shapes.add_table(len(rows) + 1, len(headers), Inches(x), Inches(y),
                                   Inches(w), Inches(h))
    tbl = shape.table
    if col_w:
        total = sum(col_w)
        for i, cw in enumerate(col_w):
            tbl.columns[i].width = Inches(w * cw / total)
    for i, hd in enumerate(headers):
        cell = tbl.cell(0, i)
        cell.text = ''
        cell.fill.solid()
        cell.fill.fore_color.rgb = CONFIG['header_bg']
        cell.vertical_anchor = MSO_ANCHOR.MIDDLE
        p = cell.text_frame.paragraphs[0]
        p.alignment = PP_ALIGN.CENTER if i else PP_ALIGN.LEFT
        style_run(p.add_run(), font_size, True, C_WHITE).text = str(hd)
    for r, row in enumerate(rows, start=1):
        for c, val in enumerate(row):
            cell = tbl.cell(r, c)
            cell.text = ''
            cell.vertical_anchor = MSO_ANCHOR.MIDDLE
            txt = '' if val is None else str(val)
            if r % 2 == 0:
                cell.fill.solid()
                cell.fill.fore_color.rgb = CONFIG['band_bg']
            fill = cell_fill(txt, r, c) if cell_fill else None
            if fill is not None:
                cell.fill.solid()
                cell.fill.fore_color.rgb = fill
            p = cell.text_frame.paragraphs[0]
            p.alignment = PP_ALIGN.CENTER if c else PP_ALIGN.LEFT
            color = (cell_color(txt, c) if cell_color else None) or C_TEXT
            style_run(p.add_run(), font_size, False, color).text = txt
    for r in range(len(rows) + 1):
        tbl.rows[r].height = Inches(row_h)
    return tbl


# ---------- 原生图表 ----------
def add_chart(slide, kind, categories, series, title, number_format='#,##0.00',
              x=0.7, y=None, w=None, h=None, legend=True, pct_labels=False,
              accent_series=False, legend_multiple_only=False):
    """accent_series=True 时把各系列统一成主色（best-effort，失败不影响出图）。"""
    y = CONFIG['chart_y'] if y is None else y
    w = (SW - 1.4) if w is None else w
    h = (SH - y - CONFIG['chart_bottom_margin']) if h is None else h
    cd = CategoryChartData()
    cd.categories = [str(c) for c in categories]
    for name, values in series:
        cd.add_series(name, tuple(values))
    chart = slide.shapes.add_chart(kind, Inches(x), Inches(y), Inches(w), Inches(h), cd).chart
    chart.has_title = True
    chart.chart_title.text_frame.text = title
    for p in chart.chart_title.text_frame.paragraphs:
        for r in p.runs:
            style_run(r, 14, True, CONFIG['title_color'])
    chart.has_legend = legend and (not legend_multiple_only or len(series) > 1)
    if chart.has_legend:
        chart.legend.position = XL_LEGEND_POSITION.BOTTOM
        chart.legend.include_in_layout = False
    chart.font.size = Pt(11)   # 放在 if 外：无图例的图表同样要设字号
    plot = chart.plots[0]
    plot.has_data_labels = True
    if pct_labels:
        plot.data_labels.show_percentage = True
        plot.data_labels.show_value = False
    else:
        plot.data_labels.number_format = number_format
        plot.data_labels.number_format_is_linked = False
        plot.data_labels.font.size = Pt(10)
    if accent_series:
        try:
            for s in plot.series:
                if kind in (XL_CHART_TYPE.LINE, XL_CHART_TYPE.LINE_MARKERS):
                    s.format.line.color.rgb = CONFIG['accent']
                else:
                    s.format.fill.solid()
                    s.format.fill.fore_color.rgb = CONFIG['accent']
        except Exception:
            pass
    try:
        chart.value_axis.tick_labels.number_format = number_format
        chart.value_axis.tick_labels.number_format_is_linked = False
        chart.value_axis.has_major_gridlines = True
    except Exception:
        pass
    style_chart_cjk(chart)
    return chart


# ---------- 数据契约校验 ----------
class DataError(Exception):
    """数据契约校验失败：一次性列出全部问题，不静默容忍。"""

    def __init__(self, problems):
        self.problems = list(problems)
        super().__init__('数据文件有 %d 处问题' % len(self.problems))


def _num(v, where, problems, hint=''):
    """把值转成 float。可转换的字符串（'90'）容错通过；不可转换的记录问题并返回 None。"""
    if isinstance(v, bool) or v is None:
        problems.append('%s：期望数值，实际是 %s' % (where, type(v).__name__ if v is not None else 'null'))
        return None
    if isinstance(v, (int, float)):
        return float(v)
    if isinstance(v, str):
        try:
            return float(v.strip())
        except ValueError:
            problems.append('%s：期望数值，实际是字符串 %r%s' % (where, v, hint))
            return None
    problems.append('%s：不支持的数值类型 %s' % (where, type(v).__name__))
    return None


def num_list(values, where, problems, hint=''):
    if values is None:
        return []
    if not isinstance(values, (list, tuple)):
        problems.append('%s：期望数组，实际是 %s' % (where, type(values).__name__))
        return []
    return [_num(v, '%s[%d]' % (where, i), problems, hint) for i, v in enumerate(values)]


def check_series(cats, values, cats_name, where, problems, hint=''):
    """校验「类别 + 数值」是否对齐，返回归一化后的数值列表。"""
    if not isinstance(cats, (list, tuple)):
        problems.append('%s：%s 期望数组' % (where, cats_name))
        return []
    nums = num_list(values, where, problems, hint)
    if len(cats) != len(nums):
        problems.append('%s：%s %d 个与数值 %d 个不一致，图表会错位'
                        % (where, cats_name, len(cats), len(nums)))
    return nums


def check_axis(obj, cats_key, vals_key, where, problems, hint=''):
    """对象内「类别 ↔ 数值」成对校验：两侧都缺就跳过，否则就地归一化。"""
    if not isinstance(obj, dict):
        problems.append('%s：期望对象' % where)
        return
    cats = obj.get(cats_key)
    vals = obj.get(vals_key)
    if cats is None and vals is None:
        return
    obj[vals_key] = check_series(cats, vals, cats_key, '%s.%s' % (where, vals_key), problems, hint)


def check_dict_list(container, key, problems, label=None):
    """校验 container[key] 是「对象数组」。

    只查容器类型是不够的：元素不是 dict 时，后面 `x.get(...)` 会抛
    AttributeError（'str' object has no attribute 'get'），绕过 main() 的友好错误处理。
    """
    label = label or key
    v = container.get(key)
    if v is None:
        return
    if not isinstance(v, (list, tuple)):
        problems.append('%s：期望数组，实际是 %s' % (label, type(v).__name__))
        return
    for i, x in enumerate(v):
        if not isinstance(x, dict):
            problems.append('%s[%d]：期望对象，实际是 %s' % (label, i, type(x).__name__))


def check_meta(data, problems):
    meta = data.get('meta')
    if meta is not None and not isinstance(meta, dict):
        problems.append('meta：期望对象')


def harden_streams():
    """把 stdout / stderr 切到 UTF-8。

    Windows 中文控制台默认 GBK，脚本里的 ❌ / ⚠️ 会触发 UnicodeEncodeError ——
    「报错时报错」，用户只看到 traceback 而看不到真正的原因。
    """
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding='utf-8', errors='replace')
        except (AttributeError, ValueError, OSError):
            pass


# ---------- 共用的命令行外壳 ----------
def run_cli(build, default_out_name, doc):
    """读 JSON → 校验 → 生成 → 原子写盘，并统一处理错误与退出码。

    build(data) -> (prs, skipped)
    default_out_name(data) -> str
    退出码：1 参数错 / 2 读文件或写盘失败 / 3 数据校验未通过
    """
    harden_streams()
    if len(sys.argv) < 2:
        print(doc)
        sys.exit(1)
    src = sys.argv[1]
    if not os.path.exists(src):
        print('❌ 数据文件不存在：%s' % src)
        sys.exit(1)

    try:
        with open(src, encoding='utf-8') as f:
            data = json.load(f)
    except json.JSONDecodeError as e:
        print('❌ 数据文件不是合法 JSON：%s' % src)
        print('   第 %d 行第 %d 列附近：%s' % (e.lineno, e.colno, e.msg))
        print('   提示：中文内容里的引号请用「」或『』，不要用英文双引号（会破坏 JSON）')
        sys.exit(2)
    except OSError as e:
        print('❌ 读不到数据文件：%s（%s）' % (src, e.strerror or e))
        sys.exit(2)

    try:
        prs, skipped = build(data)
    except DataError as e:
        print('❌ 数据校验未通过，共 %d 处问题：' % len(e.problems))
        for i, x in enumerate(e.problems, 1):
            print('   %d) %s' % (i, x))
        print('   修正后重新运行即可；若整个板块没有数据，请删掉对应的键，那一页会自动跳过。')
        sys.exit(3)

    out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(
        os.path.dirname(os.path.abspath(src)), default_out_name(data))
    if os.path.isdir(out):
        print('❌ 输出路径是一个目录，请指定 .pptx 文件名：%s' % out)
        sys.exit(2)
    try:
        os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    except OSError as e:
        print('❌ 无法创建输出目录：%s（%s）' % (os.path.dirname(out), e.strerror or e))
        sys.exit(2)

    # 先写临时文件再原子替换：避免中途失败留下半成品，也避免并发写同一路径互相截断
    tmp = out + '.tmp'
    try:
        prs.save(tmp)
        os.replace(tmp, out)
    except PermissionError:
        if os.path.exists(tmp):
            os.remove(tmp)
        print('❌ 无法写入 %s —— 文件可能正被 PowerPoint / WPS 打开。' % out)
        print('   请先关闭该文件，或另存为其他文件名后重试。')
        sys.exit(2)
    except OSError as e:
        if os.path.exists(tmp):
            os.remove(tmp)
        print('❌ 保存失败：%s（%s）' % (out, e.strerror or e))
        sys.exit(2)

    charts = sum(1 for sl in prs.slides for sh in sl.shapes if sh.has_chart)
    print('✅ 已生成：%s' % out)
    print('   幻灯片 %d 页 ｜ 原生图表 %d 个 ｜ %.1f KB'
          % (len(prs.slides), charts, os.path.getsize(out) / 1024))
    if skipped:
        print('   ⚠️ 因内容缺失跳过的板块：%s' % '；'.join(skipped))


def new_presentation():
    prs = Presentation()
    prs.slide_width, prs.slide_height = Inches(SW), Inches(SH)
    return prs, prs.slide_layouts[6]
