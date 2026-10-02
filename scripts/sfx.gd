extends Node
## Sfx v0.8: 程序化合成音效（AudioStreamWAV），无外部音频资产。
## autoload 单例：Sfx.play("shoot") / Sfx.play_at("spit", pos)（Web 声像）。
## 音色唯一事实源 = data/audio_manifest.json（tools/check_audio.py 三方校验）。

const RATE := 22050
const POOL := 10
const VOL_DB := -4.0

var _manifest := {}  # data/audio_manifest.json 的 sounds 表

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
	_load_manifest()
	_gen_all()
	# v0.8 事件音（B5 新增内容的声音接线）
	EventBus.enemy_fired.connect(func(pos: Vector2) -> void: play_at("spit", pos))
	EventBus.exploder_fuse_start.connect(func(pos: Vector2) -> void: play_at("fuse", pos))
	EventBus.chest_opened.connect(func(pos: Vector2) -> void: play_at("chest", pos))
	EventBus.boss_phase_changed.connect(func(_id: String, _p: int) -> void: play("boss_phase"))
	# v0.8 音频第二批（L3）：波次/倒计时/精英出场 + BGM ducking
	EventBus.wave_started.connect(func(_n: int, _t: int) -> void: play("wave_start"))
	EventBus.floor_timer_warning.connect(func(_s: int) -> void: play("timer_warn"))
	EventBus.elite_spawned.connect(func(pos: Vector2) -> void: play_at("elite_spawn", pos))
	EventBus.bgm_duck.connect(_on_bgm_duck)


func _load_manifest() -> void:
	var path := "res://data/audio_manifest.json"
	if not FileAccess.file_exists(path):
		push_error("Sfx: audio_manifest.json missing")
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		_manifest = parsed.get("sounds", {})


func _gen_all() -> void:
	for sname in _manifest.keys():
		_streams[sname] = _gen_one(_manifest[sname])


func _gen_one(d: Dictionary) -> AudioStreamWAV:
	match String(d.get("gen", "")):
		"tone":
			return _tone(float(d["f0"]), float(d["f1"]), float(d["dur"]),
				float(d["vol"]), int(d.get("wave", 2)))
		"noise":
			return _noise(float(d["dur"]), float(d["vol"]))
		"boom":
			return _boom(float(d["dur"]), float(d["vol"]))
		"two_tone":
			return _two_tone(float(d["f0"]), float(d["f1"]), float(d["dur"]), float(d["vol"]))
		"arp":
			return _arp(d["notes"], float(d["dur"]), float(d["vol"]))
		"sweep":
			return _sweep(float(d["f0"]), float(d["f1"]), float(d["dur"]), float(d["vol"]))
		"roar":
			return _roar(float(d["dur"]), float(d["vol"]))
	return _noise(0.05, 0.2)


func play(sname: String) -> void:
	if Meta.is_muted():
		return
	if not _streams.has(sname):
		return
	var now := Time.get_ticks_msec() / 1000.0
	var th: float = float(_manifest.get(sname, {}).get("throttle", 0.05))
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


## 带声像的播放：Web 端按相对玩家横向位置算 pan（-1..1）；原生端降级为 play
func play_at(sname: String, pos: Vector2) -> void:
	if not OS.has_feature("web"):
		play(sname)
		return
	if Meta.is_muted() or not _streams.has(sname):
		return
	var now := Time.get_ticks_msec() / 1000.0
	var th: float = float(_manifest.get(sname, {}).get("throttle", 0.05))
	if now - float(_last.get(sname, -99.0)) < th:
		return
	_last[sname] = now
	var pan := 0.0
	var pl := get_tree().get_first_node_in_group("player") as Node2D
	if pl != null:
		pan = clampf((pos.x - pl.global_position.x) / 600.0, -0.8, 0.8)
	JavaScriptBridge.eval("window._gameSfx&&window._gameSfx.play('%s',%.2f)" % [sname, pan], true)


## BGM ducking（Boss 层 / 合成演出期间压低 BGM 到 0.30）
func _on_bgm_duck(active: bool) -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window._gameBgm&&window._gameBgm.duck(%s)" % ("true" if active else "false"), true)


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
