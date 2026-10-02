#!/usr/bin/env python3
"""从 data/audio_manifest.json 生成 web/shell.html 的 WebAudio 播放表。

shell.html 中 // === GEN AUDIO BEGIN/END === 之间的 helpers + PLAYERS
由本脚本生成，禁止手改（改音色改 manifest 再跑本脚本）。
生成配方与 scripts/sfx.gd 的 GDScript 原语一一对应（tone/noise/boom/roar
+ two_tone/arp/sweep 组合），波形映射 wave: 0=square 1=sawtooth 2=sine。
vol_web 存在时 Web 端用它（历史响度微调），否则用 vol。
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WAVES = {0: "square", 1: "sawtooth", 2: "sine"}


def num(x: float) -> str:
    return ("%g" % x)


def player_body(d: dict) -> str:
    gen = d["gen"]
    vol = d.get("vol_web", d["vol"])
    dur = d["dur"]
    if gen == "tone":
        return "tone(%s, %s, %s, %s, '%s')" % (num(d["f0"]), num(d["f1"]), num(dur), num(vol), WAVES[d.get("wave", 2)])
    if gen == "sweep":
        # JS 无独立 sweep 原语：用 sine tone 近似（GD 端为指数扫频+泛音）
        return "tone(%s, %s, %s, %s, 'sine')" % (num(d["f0"]), num(d["f1"]), num(dur), num(vol))
    if gen == "noise":
        return "noise(%s, %s)" % (num(dur), num(vol))
    if gen == "boom":
        return "boom(%s, %s)" % (num(dur), num(vol))
    if gen == "roar":
        return "roar(%s, %s)" % (num(dur), num(vol))
    if gen == "two_tone":
        half = dur / 2.0
        return "tone(%s, %s, %s, %s, 'sine'); tone(%s, %s, %s, %s, 'sine', %s)" % (
            num(d["f0"]), num(d["f0"]), num(half), num(vol),
            num(d["f1"]), num(d["f1"]), num(half), num(vol), num(half))
    if gen == "arp":
        notes = d["notes"]
        step = dur / len(notes)
        return "var f = [%s]; for (var i = 0; i < f.length; i++) { tone(f[i], f[i], %s, %s, 'sine', i * %s); }" % (
            ", ".join(num(float(n)) for n in notes), num(step), num(vol), num(step))
    raise SystemExit("unknown gen: %s" % gen)


def main() -> None:
    manifest = json.loads((ROOT / "data" / "audio_manifest.json").read_text(encoding="utf-8"))
    sounds = manifest["sounds"]
    lines = []
    lines.append("\tfunction tone(f0, f1, dur, vol, type, delay) {")
    lines.append("\t\tvar c = ac(), t = c.currentTime + (delay || 0);")
    lines.append("\t\tvar o = c.createOscillator(), g = c.createGain();")
    lines.append("\t\to.type = type;")
    lines.append("\t\to.frequency.setValueAtTime(Math.max(f0, 1), t);")
    lines.append("\t\tif (f1 !== f0) { o.frequency.exponentialRampToValueAtTime(Math.max(f1, 1), t + dur); }")
    lines.append("\t\tg.gain.setValueAtTime(vol, t);")
    lines.append("\t\tg.gain.exponentialRampToValueAtTime(0.001, t + dur);")
    lines.append("\t\to.connect(g); g.connect(master);")
    lines.append("\t\to.start(t); o.stop(t + dur + 0.02);")
    lines.append("\t}")
    lines.append("\tfunction noise(dur, vol, delay) {")
    lines.append("\t\tvar c = ac(), t = c.currentTime + (delay || 0);")
    lines.append("\t\tvar s = c.createBufferSource(); s.buffer = getNoise(c);")
    lines.append("\t\tvar g = c.createGain();")
    lines.append("\t\tg.gain.setValueAtTime(vol, t);")
    lines.append("\t\tg.gain.exponentialRampToValueAtTime(0.001, t + dur);")
    lines.append("\t\ts.connect(g); g.connect(master);")
    lines.append("\t\ts.start(t); s.stop(t + dur + 0.02);")
    lines.append("\t}")
    lines.append("\tfunction boom(dur, vol) {")
    lines.append("\t\ttone(90, 40, dur, vol * 0.8, 'sine');")
    lines.append("\t\tnoise(dur, vol * 0.35);")
    lines.append("\t}")
    lines.append("\tfunction roar(dur, vol) {")
    lines.append("\t\ttone(110, 55, dur, vol * 0.6, 'sawtooth');")
    lines.append("\t\tnoise(dur, vol * 0.3);")
    lines.append("\t}")
    lines.append("\tvar PLAYERS = {")
    names = sorted(sounds.keys())
    for i, name in enumerate(names):
        comma = "," if i < len(names) - 1 else ""
        lines.append("\t\t%s: function () { %s; }%s" % (name, player_body(sounds[name]), comma))
    lines.append("\t};")
    block = "\n".join(lines)

    shell_path = ROOT / "web" / "shell.html"
    shell = shell_path.read_text(encoding="utf-8")
    pat = re.compile(r"(// === GEN AUDIO BEGIN[^\n]*\n).*?(\n\t// === GEN AUDIO END ===)", re.S)
    if not pat.search(shell):
        raise SystemExit("GEN AUDIO markers not found in shell.html")
    shell = pat.sub(lambda m: m.group(1) + block + m.group(2), shell, count=1)
    shell_path.write_text(shell, encoding="utf-8")
    print("gen_shell_audio: wrote %d players" % len(names))


if __name__ == "__main__":
    main()
