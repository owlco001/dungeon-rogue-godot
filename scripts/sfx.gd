extends Node
## Sfx v0.5: 程序化合成音效（AudioStreamWAV），无外部音频资产。
## autoload 单例：Sfx.play("shoot")。10 路 Player 池 + 按音色节流，音量 -4dB。

const RATE := 22050
const POOL := 10
const VOL_DB := -4.0

# name -> {gen 参数}; throttle: 最小间隔秒
const DEFS := {
	"shoot": {"dur": 0.07, "throttle": 0.07},
	"hit": {"dur": 0.08, "throttle": 0.05},
	"explosion": {"dur": 0.45, "throttle": 0.10},
	"gem": {"dur": 0.12, "throttle": 0.05},
	"coin": {"dur": 0.16, "throttle": 0.06},
	"levelup": {"dur": 0.45, "throttle": 0.30},
	"hurt": {"dur": 0.22, "throttle": 0.15},
	"stairs": {"dur": 0.35, "throttle": 0.30},
	"click": {"dur": 0.06, "throttle": 0.05},
	"boss_roar": {"dur": 0.90, "throttle": 0.80},
	"superfuse": {"dur": 0.70, "throttle": 0.50},
	"relic": {"dur": 0.40, "throttle": 0.30},
	"achievement": {"dur": 0.55, "throttle": 0.30},
}

var _streams := {}
var _pool: Array[AudioStreamPlayer] = []
var _idx := 0
var _last := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in range(POOL):
		var p := AudioStreamPlayer.new()
		p.volume_db = VOL_DB
		p.bus = "Master"
		add_child(p)
		_pool.append(p)
	_gen_all()


func _gen_all() -> void:
	_streams["shoot"] = _tone(880.0, 440.0, 0.07, 0.5, 0)       # 方波下扫
	_streams["hit"] = _noise(0.08, 0.45)                          # 噪声碎击
	_streams["explosion"] = _boom(0.45, 0.8)                       # 低频轰爆
	_streams["gem"] = _tone(1320.0, 1760.0, 0.12, 0.4, 2)          # 正弦上扬
	_streams["coin"] = _two_tone(990.0, 1320.0, 0.16, 0.4)         # 双音金币
	_streams["levelup"] = _arp([523.0, 659.0, 784.0, 1046.0], 0.45, 0.45)
	_streams["hurt"] = _tone(220.0, 110.0, 0.22, 0.5, 1)           # 锯齿下沉
	_streams["stairs"] = _tone(784.0, 1568.0, 0.35, 0.35, 2)       # 上行风铃
	_streams["click"] = _tone(660.0, 660.0, 0.06, 0.35, 0)
	_streams["boss_roar"] = _roar(0.9, 0.7)
	_streams["superfuse"] = _sweep(200.0, 2000.0, 0.7, 0.5)
	_streams["relic"] = _arp([392.0, 523.0, 659.0, 784.0, 1046.0], 0.4, 0.4)
	_streams["achievement"] = _arp([659.0, 784.0, 1046.0, 1318.0, 1568.0], 0.55, 0.45)


func play(sname: String) -> void:
	if Meta.is_muted():
		return
	if not _streams.has(sname):
		return
	var now := Time.get_ticks_msec() / 1000.0
	var th: float = float(DEFS[sname]["throttle"])
	if now - float(_last.get(sname, -99.0)) < th:
		return
	_last[sname] = now
	if OS.has_feature("web"):
		# Web 端走浏览器原生音频（Godot 4.7 Web 音频在桌面端唤醒不可靠）
		JavaScriptBridge.eval("window._gameSfx&&window._gameSfx.play('%s')" % sname, true)
		return
	var p := _pool[_idx]
	_idx = (_idx + 1) % POOL
	p.stream = _streams[sname]
	p.play()


func set_muted(m: bool) -> void:
	Meta.set_muted(m)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window._gameSfx&&window._gameSfx.setMuted(%s)" % ("true" if m else "false"), true)
		JavaScriptBridge.eval("window._gameBgm&&window._gameBgm.setMuted(%s)" % ("true" if m else "false"), true)
		return
	if m:
		for p in _pool:
			p.stop()


## 诊断：返回引擎侧音频状态，用于试音按钮的 toast
func debug_state() -> String:
	var playing := 0
	for p in _pool:
		if p.playing:
			playing += 1
	var bus_mute := AudioServer.is_bus_mute(0)
	return Lang.t("播放中:%d 总线静音:%s 输出:%dHz") % [playing, str(bus_mute), int(AudioServer.get_mix_rate())]


# ---------- 合成原语（16-bit PCM） ----------
func _pack(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in range(samples.size()):
		var v := int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, v)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = data
	return w


func _env(i: int, n: int, power: float = 1.0) -> float:
	# 简单衰减包络
	var t := float(i) / float(maxi(n - 1, 1))
	return pow(1.0 - t, power)


# wave: 0 方波 / 1 锯齿 / 2 正弦；f0->f1 滑音
func _tone(f0: float, f1: float, dur: float, vol: float, wave: int) -> AudioStreamWAV:
	var n := int(RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	var phase := 0.0
	for i in range(n):
		var t := float(i) / float(n)
		var f := lerpf(f0, f1, t)
		phase += TAU * f / RATE
		var v := 0.0
		match wave:
			0:
				v = 1.0 if sin(phase) > 0.0 else -1.0
				v *= 0.6
			1:
				v = (fmod(phase, TAU) / TAU) * 2.0 - 1.0
			_:
				v = sin(phase)
		s[i] = v * vol * _env(i, n, 1.5)
	return _pack(s)


func _noise(dur: float, vol: float) -> AudioStreamWAV:
	var n := int(RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in range(n):
		s[i] = randf_range(-1.0, 1.0) * vol * _env(i, n, 2.0)
	return _pack(s)


func _boom(dur: float, vol: float) -> AudioStreamWAV:
	var n := int(RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	var phase := 0.0
	for i in range(n):
		var t := float(i) / float(n)
		var f := lerpf(90.0, 40.0, t)
		phase += TAU * f / RATE
		var v := sin(phase) * 0.8 + randf_range(-1.0, 1.0) * 0.35 * (1.0 - t)
		s[i] = v * vol * _env(i, n, 1.2)
	return _pack(s)


func _two_tone(f0: float, f1: float, dur: float, vol: float) -> AudioStreamWAV:
	var n := int(RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in range(n):
		var f := f0 if i < n / 2 else f1
		s[i] = sin(TAU * f * float(i) / RATE) * vol * _env(i, n, 1.5)
	return _pack(s)


func _arp(freqs: Array, dur: float, vol: float) -> AudioStreamWAV:
	var n := int(RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	var per := n / freqs.size()
	for i in range(n):
		var f: float = float(freqs[mini(int(i / per), freqs.size() - 1)])
		var local := fmod(float(i), per) / per
		s[i] = sin(TAU * f * float(i) / RATE) * vol * (1.0 - local)
	return _pack(s)


func _roar(dur: float, vol: float) -> AudioStreamWAV:
	var n := int(RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	var phase := 0.0
	for i in range(n):
		var t := float(i) / float(n)
		var f := lerpf(110.0, 55.0, t)
		phase += TAU * f / RATE
		var saw := (fmod(phase, TAU) / TAU) * 2.0 - 1.0
		var v := saw * 0.6 + randf_range(-1.0, 1.0) * 0.3
		s[i] = v * vol * sin(PI * minf(t * 3.0, 1.0)) * (1.0 - t * 0.5)
	return _pack(s)


func _sweep(f0: float, f1: float, dur: float, vol: float) -> AudioStreamWAV:
	var n := int(RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	var phase := 0.0
	for i in range(n):
		var t := float(i) / float(n)
		var f := f0 * pow(f1 / f0, t)
		phase += TAU * f / RATE
		var v := sin(phase) + 0.4 * sin(phase * 2.0)
		s[i] = v * vol * sin(PI * t) * 0.7
	return _pack(s)
