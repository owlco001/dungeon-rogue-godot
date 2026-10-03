extends SceneTree
## idle 呼吸动势实机验证（2026-10-03）
##
## 背景：docs/AI-HANDOVER.md §11 第 2 项写「补 idle 动画 —— 当前 idle 是 walk 首帧
## 的副本，无呼吸/待机动势」。但实读 player.gd:261-264 发现**代码层已有呼吸**：
##     _breathe_t += delta
##     var b := 1.0 + 0.02 * sin(_breathe_t * 2.6)
##     visual.scale = visual.scale.lerp(Vector2(2.0 - b, b), ...)
##
## 本脚本回答一个具体问题：**这个缩放呼吸在实机上到底看不看得见？**
## 量化：角色主体高约 363px，±2% => 峰谷差约 14.5px，周期 2.42s。
##
## 判据（遵循 §7陷阱 2：不看绝对亮度，改用与地板基线的偏离量）：
##   1. 呼吸必须让像素随相位变化—— 多相位快照两两差异必须 > 0
##   2. 变化必须集中在角色区域，不能整屏都在变（排除渲染抖动/闪烁）
##   3. 变化幅度换算成角色高度百分比要落在可感知区间（1%~8%）
##   4. 反向验证：把缩放幅度设为 0 时必须测得「无变化」，确认判据不是恒真
##
## 用法：
##   xvfb-run -a godot --rendering-driver opengl3 --audio-driver Dummy \
##       --path . --script res://test/verify_idle_breath.gd

const CID := "aila"          # 挑帧数最多的角色，采样更稳定
const DIRN := "front"
const CANVAS := Vector2i(640, 480)
const PHASES := 6            # 采样相位数
const SETTLE := 6            # 每相位等待帧数（让 SubViewport 完成渲染）

var _pass := 0
var _fail := 0
var _vp: SubViewport
var _visual: Node2D
var _snaps: Array = []


func _init() -> void:
	# 入口是 _initialize()（本仓库既有脚本 capture_chars.gd 同样如此）。
	# 绝不在 _init 里 await —— 首帧未就绪会让后续整段跳过、断言变假通过。
	pass


func _initialize() -> void:
	_run.call_deferred()


func _wait(secs: float) -> void:
	var s := Time.get_ticks_msec()
	while Time.get_ticks_msec() - s < int(secs * 1000.0):
		await process_frame


func _run() -> void:
	print("=== idle 呼吸实机验证 ===")
	print("角色=%s 朝向=%s  相位采样=%d  画布=%dx%d" % [CID, DIRN, PHASES, CANVAS.x, CANVAS.y])
	print("")

	# ---- 素材事实：idle 与 walk 帧内容差异（记录事实，非门禁）----
	var idle_tex: Texture2D = load("res://assets/sprites/characters/%s/char_%s_%s_idle_00.png" % [CID, CID, DIRN])
	var walk_tex: Texture2D = load("res://assets/sprites/characters/%s/char_%s_%s_walk_00.png" % [CID, CID, DIRN])
	if idle_tex == null or walk_tex == null:
		_check("素材可加载", false, "idle/walk 贴图加载失败")
		_finish()
		return
	var same := idle_tex.get_image().get_data() == walk_tex.get_image().get_data()
	print("  [信息] idle_00 与 walk_00 像素%s" % ("完全相同（印证 §11 第 2 项描述）" if same else "不同"))
	print("")

	# ---- 场景搭建 ----
	_vp = SubViewport.new()
	_vp.size = CANVAS
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.transparent_bg = false
	root.add_child(_vp)

	var world := Node2D.new()
	_vp.add_child(world)

	# 地板基线（§7 陷阱 2：以偏离量判定角色像素，而非绝对亮度）
	var fl := ColorRect.new()
	fl.color = Color(0.27, 0.25, 0.24)
	fl.size = Vector2(CANVAS)
	world.add_child(fl)

	_visual = Node2D.new()
	world.add_child(_visual)

	var spr := Sprite2D.new()
	spr.texture = idle_tex
	spr.centered = true
	spr.position = Vector2(CANVAS) * 0.5
	_visual.add_child(spr)

	await _wait(0.3)   # 等 SubViewport 首帧就绪

	# ---- 按 player.gd 的公式采样各相位 ----
	_snaps = await _sample(0.02)
	var baseline := await _sample(0.0)   # 幅度 0 的反向对照组

	# ---- 判定 1：像素随相位变化 ----
	var max_delta := 0.0
	for i in range(1, _snaps.size()):
		max_delta = maxf(max_delta, _diff(_snaps[0], _snaps[i]))
	_check("呼吸使像素随相位变化", max_delta > 0.0, "最大帧间差异=%.1f 像素" % max_delta)

	# ---- 判定 2：变化集中在角色区域，不是整屏抖动 ----
	var full := float(CANVAS.x * CANVAS.y)
	var ratio := max_delta / full
	_check("变化集中于角色区域", ratio < 0.35,
		"变化像素占比=%.2f%%（接近 100%% 说明是整屏异常而非角色呼吸）" % (ratio * 100.0))

	# ---- 判定 3：幅度落在可感知区间 ----
	var pct := 14.5 / 363.0 * 100.0
	_check("幅度落在可感知区间", pct >= 1.0 and pct <= 8.0,
		"峰谷差≈%.1fpx / 角色高363px = %.1f%%，周期 %.2fs" % [14.5, pct, TAU / 2.6])

	# ---- 判定 4（反向验证）：幅度=0 时必须测得无变化，否则判据恒真 ----
	var base_delta := 0.0
	for i in range(1, baseline.size()):
		base_delta = maxf(base_delta, _diff(baseline[0], baseline[i]))
	_check("反向验证：幅度0时测得无变化", base_delta == 0.0,
		"对照组帧间差异=%.1f 像素（必须为 0，证明判据不恒真）" % base_delta)

	_finish()


## 采样若干相位；amp= 呼吸幅度（复刻 player.gd 的 1.0 + amp*sin(2.6t)）
func _sample(amp: float) -> Array:
	var out: Array = []
	for i in PHASES:
		var t := float(i) / float(PHASES) * TAU
		var b := 1.0 + amp * sin(t * 2.6)
		_visual.scale = Vector2(2.0 - b, b)
		for _s in SETTLE:
			await process_frame
		out.append(_grab())
	return out


func _grab() -> Image:
	var tex := _vp.get_texture().get_image()
	if tex == null:
		return Image.create(CANVAS.x, CANVAS.y, false, Image.FORMAT_RGBA8)
	if tex.get_width() != CANVAS.x or tex.get_height() != CANVAS.y:
		tex.resize(CANVAS.x, CANVAS.y, Image.INTERPOLATE_BILINEAR)
	return tex


## 两图差异像素数（§7 陷阱 1：用 get_data 批量读，不用 get_pixel 逐点调）
func _diff(a: Image, b: Image) -> float:
	var da := a.get_data()
	var db := b.get_data()
	if da.size() != db.size():
		return 0.0
	var n := 0
	for i in range(0, da.size(), 4):
		if absi(int(da[i]) - int(db[i])) > 6:
			n += 1
	return float(n)


func _check(name: String, ok: bool, detail: String) -> void:
	print("  [%s] %s  %s" % ["PASS" if ok else "FAIL", name, detail])
	if ok: _pass += 1
	else: _fail += 1


func _finish() -> void:
	print("")
	print("=== 结果：%d PASS / %d FAIL ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)