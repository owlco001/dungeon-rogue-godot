extends Control
## 大厅：天赋 / 强化 / 解锁 / 出战。深色+金色描边风格，手机触摸可用。

const SCHOOL_NAMES := {"gun": "枪械流", "summon": "召唤流", "necro": "死灵流", "melee": "近战流"}

var _font: Font
var _gold_label: Label
var _talent_label: Label
var _record_label: Label
var _mute_btn: Button
var _tab_bar: HBoxContainer
var _content: VBoxContainer
var _tab := "talent"
var _tab_btns := {}
var _scroll: ScrollContainer
var _bg_tex: Texture2D
# v0.6 成就 toast
var _toast_panel: PanelContainer
var _toast_label: Label
var _toast_tween: Tween = null
# v0.8 D8 无尽直连
var _endless_pick := false
var _endless_btn: Button = null


func _ready() -> void:
	Meta._ensure()
	_font = load("res://assets/fonts/hud-subset.ttf") as Font
	_build()
	EventBus.toast_requested.connect(_on_toast_requested)
	var mt := Meta.pop_migration_toast()
	if mt != "":
		show_toast(mt)
	if OS.has_feature("web"):
		var q = JavaScriptBridge.eval("location.search", true)
		if q != null and "autotest=1" in str(q):
			_autotest.call_deferred()


## 浏览器内音频诊断（?autotest=1）：自动点试音，把引擎+浏览器音频状态写进 document.title
func _autotest() -> void:
	await get_tree().create_timer(2.0).timeout
	_on_test_sound()
	await get_tree().create_timer(0.6).timeout
	var ctx_state = JavaScriptBridge.eval("(function(){try{var C=window.AudioContext||window.webkitAudioContext;if(!C)return 'noapi';var c=new C();var s=c.state;c.close();return s;}catch(e){return 'err';}})()", true)
	var info := "ctx=" + str(ctx_state) + " | " + Sfx.debug_state()
	JavaScriptBridge.eval("document.title=" + JSON.stringify(info) + ";")


func _on_toast_requested(text: String) -> void:
	Achievements.drain_pending()
	show_toast(text)


func _mk_label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = Lang.t(text)
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(0.92, 0.90, 0.86))
	return l


func _mk_button(text: String, size: int = 18) -> Button:
	var b := Button.new()
	b.text = Lang.t(text)
	b.add_theme_font_override("font", _font)
	b.add_theme_font_size_override("font_size", size)
	b.custom_minimum_size = Vector2(120, 52)
	return b


func _panel() -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.09, 0.14, 0.97)
	sb.set_corner_radius_all(10)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.75, 0.65, 0.4)
	p.add_theme_stylebox_override("panel", sb)
	return p


func _build() -> void:
	# 背景：Agnes 生成的地牢大厅图 + 暗罩（保证文字可读）
	_bg_tex = load("res://assets/art/lobby/lobby_bg.png") as Texture2D
	var bg := TextureRect.new()
	bg.texture = _bg_tex
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(bg)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.01, 0.03, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.add_theme_constant_override("separation", 8)
	add_child(vb)
	# 顶栏（两行：信息行 + 按钮行，窄屏不溢出）
	var top := VBoxContainer.new()
	top.add_theme_constant_override("separation", 4)
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(top)
	var info := HBoxContainer.new()
	info.add_theme_constant_override("separation", 24)
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_child(info)
	var title := _mk_label("地牢肉鸽", 38)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	title.add_theme_color_override("font_shadow_color", Color(0.45, 0.2, 0.0, 0.9))
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_offset_y", 3)
	info.add_child(title)
	_gold_label = _mk_label("", 22)
	_gold_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	info.add_child(_gold_label)
	_talent_label = _mk_label("", 22)
	_talent_label.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0))
	info.add_child(_talent_label)
	_record_label = _mk_label("", 18)
	info.add_child(_record_label)
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 16)
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_child(btns)
	_mute_btn = _mk_button("声音开", 18)
	_mute_btn.custom_minimum_size = Vector2(88, 44)
	_mute_btn.tooltip_text = Lang.t("静音开关")
	_mute_btn.pressed.connect(_on_mute_toggle)
	btns.add_child(_mute_btn)
	var test_btn := _mk_button("试音", 16)
	test_btn.custom_minimum_size = Vector2(96, 44)
	test_btn.tooltip_text = Lang.t("播放测试音效")
	test_btn.pressed.connect(_on_test_sound)
	btns.add_child(test_btn)
	var lang_btn := _mk_button("EN" if Lang.current() != "en" else "中文", 16)
	lang_btn.custom_minimum_size = Vector2(72, 44)
	lang_btn.tooltip_text = "Language / 语言"
	lang_btn.pressed.connect(_on_lang_toggle)
	btns.add_child(lang_btn)
	_update_mute_btn()
	# 中途存档：如果有存档，显示"继续冒险"按钮
	if RunSave.has_save():
		var cont_btn := _mk_button("继续冒险", 20)
		cont_btn.custom_minimum_size = Vector2(160, 48)
		cont_btn.tooltip_text = RunSave.summary()
		cont_btn.pressed.connect(_on_continue_run)
		btns.add_child(cont_btn)
		var sum_label := _mk_label(RunSave.summary(), 15)
		sum_label.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6))
		top.add_child(sum_label)
	# 页签
	_tab_bar = HBoxContainer.new()
	_tab_bar.add_theme_constant_override("separation", 12)
	_tab_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(_tab_bar)
	for tid in ["talent", "attr", "unlock", "achieve", "fight"]:
		var names := {"talent": "天赋", "attr": "强化", "unlock": "解锁", "achieve": "收集", "fight": "出战"}
		var b := _mk_button(names[tid], 20)
		b.toggle_mode = true
		b.pressed.connect(_on_tab.bind(tid))
		_style_tab(b, false)
		_tab_bar.add_child(b)
		_tab_btns[tid] = b
	# 内容区：限宽居中（SHRINK_CENTER），避免宽屏下文字框撑满全屏
	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(_scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 10)
	_scroll.add_child(_content)
	_update_content_width()
	get_tree().root.size_changed.connect(_update_content_width)
	_refresh_top()
	_on_tab("talent")
	_build_toast()
	var ver := _mk_label("v0.7", 14)
	ver.add_theme_color_override("font_color", Color(0.45, 0.42, 0.55))
	ver.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ver.offset_top = -28
	ver.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ver)


## 内容区限宽：桌面宽屏居中 600px，手机窄屏留 12px 边距
func _update_content_width() -> void:
	if not is_instance_valid(_scroll):
		return
	var vw := get_viewport_rect().size.x
	var w := minf(600.0, maxf(vw - 24.0, 200.0))
	_scroll.custom_minimum_size = Vector2(w, 0)


func _refresh_top() -> void:
	_gold_label.text = Lang.t("金币:%d") % Meta.gold()
	_talent_label.text = Lang.t("天赋点:%d") % Meta.talent_points()
	var rec := Lang.t("最高 %d 层 · 通关 %d 次") % [Meta.max_floor(), Meta.victories()]
	if Meta.endless_best_floor() > 0:
		rec += Lang.t(" · 无尽 %d 层(%d分)") % [Meta.endless_best_floor(), Meta.endless_best_score()]
	_record_label.text = rec


func _on_mute_toggle() -> void:
	Sfx.set_muted(not Meta.is_muted())
	_update_mute_btn()
	Sfx.play("click")


## 页签胶囊样式：激活态金底深字，未激活深底金边
func _style_tab(b: Button, active: bool) -> void:
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(12)
		sb.content_margin_left = 18
		sb.content_margin_right = 18
		sb.content_margin_top = 10
		sb.content_margin_bottom = 10
		if active:
			sb.bg_color = Color(0.85, 0.66, 0.28)
			sb.set_border_width_all(0)
		else:
			sb.bg_color = Color(0.13, 0.11, 0.18, 0.95)
			sb.set_border_width_all(2)
			sb.border_color = Color(0.55, 0.45, 0.28)
		b.add_theme_stylebox_override(state, sb)
	b.add_theme_color_override("font_color", Color(0.10, 0.07, 0.02) if active else Color(0.95, 0.90, 0.75))
	b.add_theme_color_override("font_hover_color", Color(0.10, 0.07, 0.02) if active else Color(1.0, 0.95, 0.80))
	b.add_theme_color_override("font_pressed_color", Color(0.10, 0.07, 0.02))


func _on_test_sound() -> void:
	# 第1声：游戏引擎（点按的 touchstart 已触发引擎 resume，这里直接播）
	Sfx.play("levelup")
	Sfx.play("coin")
	var actx := "?"
	if OS.has_feature("web"):
		actx = str(JavaScriptBridge.eval("window._getAudioState ? window._getAudioState() : 'no-hook'", true))
	show_toast(Lang.t("第1声(游戏引擎,叮叮声)已播放...\n[音频上下文:") + actx + "]")
	await get_tree().create_timer(1.8).timeout
	# 第2声：浏览器原生(哔长音)，对照组
	_web_beep()
	await get_tree().create_timer(1.2).timeout
	show_toast(Lang.t("播了2次:1=游戏(叮叮) 2=浏览器(哔)\n") + Sfx.debug_state() + Lang.t("\n你听到第几声?"))


## 浏览器原生蜂鸣（绕过 Godot 音频管线）：用于定位无声是引擎问题还是设备问题
func _web_beep() -> void:
	if not OS.has_feature("web"):
		return
	JavaScriptBridge.eval("(function(){try{var C=window.AudioContext||window.webkitAudioContext;if(!C)return;window._tac=window._tac||new C();var ac=window._tac;if(ac.state==='suspended'){ac.resume();}var o=ac.createOscillator(),g=ac.createGain();o.type='sine';o.frequency.value=880;g.gain.setValueAtTime(0.5,ac.currentTime);g.gain.exponentialRampToValueAtTime(0.001,ac.currentTime+0.8);o.connect(g);g.connect(ac.destination);o.start();o.stop(ac.currentTime+0.8);}catch(e){}})()", true)


func _update_mute_btn() -> void:
	if is_instance_valid(_mute_btn):
		_mute_btn.text = Lang.t("声音关") if Meta.is_muted() else Lang.t("声音开")


func _on_lang_toggle() -> void:
	Lang.set_lang("en" if Lang.current() != "en" else "zh")
	get_tree().reload_current_scene()


func _on_tab(tid: String) -> void:
	Sfx.play("click")
	_tab = tid
	for k in _tab_btns.keys():
		_tab_btns[k].button_pressed = (k == tid)
		_style_tab(_tab_btns[k], k == tid)
	for c in _content.get_children():
		c.queue_free()
	match tid:
		"talent":
			_build_talent_tab()
		"attr":
			_build_attr_tab()
		"unlock":
			_build_unlock_tab()
		"achieve":
			_build_achieve_tab()
		"fight":
			_build_fight_tab()
	_refresh_top()


func _section(title: String, color: Color) -> VBoxContainer:
	var p := _panel()
	_content.add_child(p)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	p.add_child(vb)
	var t := _mk_label(title, 24)
	t.add_theme_color_override("font_color", color)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	return vb


func _buy_row(parent: VBoxContainer, name: String, lv_text: String, desc: String, btn_text: String, enabled: bool, on_buy: Callable) -> void:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	parent.add_child(hb)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(vb)
	var h1 := HBoxContainer.new()
	h1.add_theme_constant_override("separation", 12)
	vb.add_child(h1)
	var n := _mk_label(name, 20)
	h1.add_child(n)
	var lv := _mk_label(lv_text, 16)
	lv.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0))
	h1.add_child(lv)
	var d := _mk_label(desc, 15)
	d.add_theme_color_override("font_color", Color(0.75, 0.73, 0.7))
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(d)
	var b := _mk_button(btn_text, 17)
	b.disabled = not enabled
	b.pressed.connect(func() -> void:
		Sfx.play("click")
		on_buy.call())
	hb.add_child(b)


# ---------- 天赋页（v0.6：天赋点购买） ----------
func _build_talent_tab() -> void:
	var hint_all := _mk_label("天赋点:通关/Boss/收集获得", 15)
	hint_all.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0))
	hint_all.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(hint_all)
	for sid in Meta.SCHOOL_ORDER:
		var sc: Dictionary = Meta.SCHOOLS[sid]
		var vb := _section(String(sc["name"]), sc["color"])
		for tid in Meta.TALENT_ORDER:
			var d: Dictionary = Meta.TALENTS[tid]
			if String(d["school"]) != sid:
				continue
			var lv := Meta.talent_lv(tid)
			var maxed := lv >= int(d["max"])
			var cost := Meta.talent_point_cost(tid)
			_buy_row(vb, String(d["name"]), "Lv.%d/%d" % [lv, int(d["max"])],
				Meta.talent_desc(tid),
				"满级" if maxed else Lang.t("%d点") % cost,
				not maxed and Meta.talent_points() >= cost,
				_on_buy_talent.bind(tid))


func _on_buy_talent(tid: String) -> void:
	if Meta.buy_talent(tid):
		Achievements.check_talent_masters()
		_on_tab(_tab)


# ---------- 强化页 ----------
func _build_attr_tab() -> void:
	var vb := _section("永久属性", Color(1.0, 0.85, 0.4))
	var hint := _mk_label("金币升级，开局生效，可叠加天赋", 15)
	hint.add_theme_color_override("font_color", Color(0.75, 0.73, 0.7))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(hint)
	for aid in Meta.ATTR_ORDER:
		var d: Dictionary = Meta.ATTRS[aid]
		var lv := Meta.attr_lv(aid)
		var maxed := lv >= int(d["max"])
		var cost := Meta.attr_cost(aid)
		var per: float = float(d["per"])
		var desc := ""
		if per < 1.0:
			desc = Lang.t(String(d["desc"])) % int(round(per * 100.0 * lv))
		else:
			desc = Lang.t(String(d["desc"])) % int(per * lv)
		_buy_row(vb, String(d["name"]), "Lv.%d/%d" % [lv, int(d["max"])], desc,
			"满级" if maxed else Lang.t("%d金") % cost,
			not maxed and Meta.gold() >= cost,
			_on_buy_attr.bind(aid))


func _on_buy_attr(aid: String) -> void:
	if Meta.buy_attr(aid):
		_on_tab(_tab)


# ---------- 解锁页 ----------
func _build_unlock_tab() -> void:
	var cv := _section("角色", Color(0.7, 0.9, 1.0))
	for cid in ["aila", "batong", "mofei"]:
		var d: Dictionary = GameData.CHARACTERS[cid]
		var unlocked := Meta.is_char_unlocked(cid)
		var ud: Dictionary = Meta.CHAR_UNLOCKS[cid]
		var btn_text := "已解锁"
		var enabled := false
		if not unlocked:
			var cost := int(ud["gold"])
			btn_text = Lang.t("%d金解锁") % cost
			enabled = Meta.gold() >= cost or Meta.max_floor() >= int(ud["floor"])
		_buy_row(cv, String(d["name"]), String(d["title"]),
			"已解锁" if unlocked else Meta.char_unlock_desc(cid),
			btn_text, enabled, _on_unlock_char.bind(cid))
	var wv := _section("武器", Color(1.0, 0.85, 0.4))
	var whint := _mk_label("未解锁武器不会出现在升级三选一", 15)
	whint.add_theme_color_override("font_color", Color(0.75, 0.73, 0.7))
	whint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wv.add_child(whint)
	for wid in GameData.WEAPON_POOL:
		var wd: Dictionary = GameData.WEAPONS[wid]
		var unlocked := Meta.is_weapon_unlocked(wid)
		var school: String = String(SCHOOL_NAMES.get(String(wd.get("school", "")), ""))
		_buy_row(wv, String(wd["name"]), school,
			"已解锁" if unlocked else "三选一新武器候选",
			"已解锁" if unlocked else Lang.t("%d金") % Meta.WEAPON_UNLOCK_COST,
			not unlocked and Meta.gold() >= Meta.WEAPON_UNLOCK_COST,
			_on_buy_weapon.bind(wid))


func _on_unlock_char(cid: String) -> void:
	if Meta.try_unlock_char(cid):
		_on_tab(_tab)


func _on_buy_weapon(wid: String) -> void:
	if Meta.buy_weapon(wid):
		_on_tab(_tab)


# ---------- 成就页（v0.6） ----------
func _build_achieve_tab() -> void:
	var hint := _mk_label("解锁收集获得天赋点", 16)
	hint.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(hint)
	var done_n := 0
	for aid in Achievements.ORDER:
		if Meta.is_achievement_done(aid):
			done_n += 1
	var prog := _mk_label("%d/%d" % [done_n, Achievements.ORDER.size()], 15)
	prog.add_theme_color_override("font_color", Color(0.75, 0.73, 0.7))
	prog.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(prog)
	for aid in Achievements.ORDER:
		_ach_row(aid)


func _ach_row(aid: String) -> void:
	var d: Dictionary = Achievements.DEFS[aid]
	var done := Meta.is_achievement_done(aid)
	var p := _panel()
	# 已解锁：金色描边高亮；未解锁：暗描边
	var sb := p.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	if done:
		sb.border_color = Color(1.0, 0.85, 0.4)
		sb.bg_color = Color(0.14, 0.11, 0.08, 0.97)
	else:
		sb.border_color = Color(0.35, 0.32, 0.28)
	p.add_theme_stylebox_override("panel", sb)
	_content.add_child(p)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	p.add_child(hb)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(vb)
	var n := _mk_label(String(d["name"]), 20)
	if done:
		n.add_theme_color_override("font_color", Color(1.0, 0.88, 0.5))
	vb.add_child(n)
	var dd := _mk_label(String(d["desc"]), 15)
	dd.add_theme_color_override("font_color", Color(0.75, 0.73, 0.7))
	vb.add_child(dd)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 2)
	hb.add_child(rv)
	var r := _mk_label("+%d天赋点" % int(d["points"]), 17)
	r.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0))
	rv.add_child(r)
	var st := _mk_label("已解锁" if done else "未解锁", 15)
	if done:
		st.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
		var ts := Meta.achievement_time(aid)
		if ts > 0:
			var dt := Time.get_datetime_dict_from_unix_time(ts)
			var dl := _mk_label("%d-%02d-%02d" % [int(dt["year"]), int(dt["month"]), int(dt["day"])], 13)
			dl.add_theme_color_override("font_color", Color(0.6, 0.58, 0.55))
			rv.add_child(dl)
	else:
		st.add_theme_color_override("font_color", Color(0.55, 0.53, 0.5))
	rv.add_child(st)


# ---------- v0.6 成就 toast（屏幕顶部，1.5 秒） ----------
func _build_toast() -> void:
	var wrap := HBoxContainer.new()
	wrap.set_anchors_preset(Control.PRESET_TOP_WIDE)
	wrap.alignment = BoxContainer.ALIGNMENT_CENTER
	wrap.offset_top = 120
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wrap)
	_toast_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.07, 0.10, 0.96)
	sb.set_corner_radius_all(8)
	sb.set_border_width_all(2)
	sb.border_color = Color(1.0, 0.85, 0.4)
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	_toast_panel.add_theme_stylebox_override("panel", sb)
	_toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_label = Label.new()
	_toast_label.add_theme_font_override("font", _font)
	_toast_label.add_theme_font_size_override("font_size", 24)
	_toast_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.55))
	_toast_panel.add_child(_toast_label)
	_toast_panel.visible = false
	wrap.add_child(_toast_panel)


func show_toast(text: String) -> void:
	if not is_instance_valid(_toast_panel):
		return
	Sfx.play("achievement")
	_toast_label.text = Lang.t(text)
	_toast_panel.visible = true
	_toast_panel.modulate.a = 1.0
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(1.5)
	_toast_tween.tween_property(_toast_panel, "modulate:a", 0.0, 0.4)
	_toast_tween.tween_callback(func() -> void: _toast_panel.visible = false)


# ---------- 出战页 ----------
func _build_fight_tab() -> void:
	var vb := _section("选择角色出战", Color(1.0, 0.85, 0.4))
	# v0.8 D8：无尽直连（通关过 1 次才显示）
	if Meta.victories() >= 1:
		var cc := CenterContainer.new()
		_endless_btn = _mk_button("无尽模式：关", 18)
		_endless_btn.pressed.connect(_on_toggle_endless)
		cc.add_child(_endless_btn)
		vb.add_child(cc)
	# 竖屏（手机）时卡片竖排全量展示，否则横排
	var vp: Vector2 = get_viewport_rect().size
	if vp.y > vp.x:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 16)
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		vb.add_child(col)
		for cid in GameData.CHAR_ORDER:
			var cc := CenterContainer.new()
			cc.add_child(_fight_card(cid, true))
			col.add_child(cc)
	else:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		vb.add_child(row)
		for cid in GameData.CHAR_ORDER:
			row.add_child(_fight_card(cid, false))


func _fight_card(cid: String, compact: bool = false) -> Control:
	var d: Dictionary = GameData.CHARACTERS[cid]
	var p := _panel()
	p.custom_minimum_size = Vector2(200, 326) if compact else Vector2(220, 346)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	p.add_child(vb)
	var tex := load("res://assets/sprites/characters/%s/char_%s_down_idle_00.png" % [cid, cid]) as Texture2D
	var pr := TextureRect.new()
	pr.texture = tex
	pr.custom_minimum_size = Vector2(128, 128)
	pr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	var pc := CenterContainer.new()
	pc.add_child(pr)
	vb.add_child(pc)
	var n := _mk_label(String(d["name"]), 24)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(n)
	var ti := _mk_label(String(d["title"]), 15)
	ti.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ti.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	vb.add_child(ti)
	# v0.8 D4：卡片底部玩法一句话（新手 3 分钟 T+0）
	var hint := _mk_label("走位躲怪，武器自动开火，升级选构筑", 12)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color(0.85, 0.85, 0.75))
	vb.add_child(hint)
	var bc := CenterContainer.new()
	vb.add_child(bc)
	if Meta.is_char_unlocked(cid):
		var b := _mk_button("开始战斗", 20)
		b.pressed.connect(_on_fight.bind(cid))
		bc.add_child(b)
	else:
		var lk := _mk_label(Meta.char_unlock_desc(cid), 14)
		lk.add_theme_color_override("font_color", Color(1.0, 0.6, 0.4))
		lk.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(lk)
	return p


func _on_fight(cid: String) -> void:
	Sfx.play("stairs")
	Meta.selected_char = cid
	Meta.start_endless = _endless_pick
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_toggle_endless() -> void:
	_endless_pick = not _endless_pick
	if _endless_btn != null:
		_endless_btn.text = Lang.t("无尽模式：开") if _endless_pick else Lang.t("无尽模式：关")


## 继续冒险：从中途存档恢复
func _on_continue_run() -> void:
	var data := RunSave.load_run()
	if data.is_empty():
		return
	Sfx.play("stairs")
	RunSave.pending_continue = data
	get_tree().change_scene_to_file("res://scenes/main.tscn")
