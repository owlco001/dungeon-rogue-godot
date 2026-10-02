extends CanvasLayer
## HUD v0.2: HP/XP bars, floor/gold/kills labels, relic bar, boss bar,
## virtual joystick, character select, dynamic level-up choices,
## death + victory overlays.

signal character_chosen(char_id: String)
signal upgrade_chosen(opt: Dictionary)
signal endless_chosen

var _font: Font
var _name_label: Label
var _hp_bar: ProgressBar
var _xp_bar: ProgressBar
var _level_label: Label
var _floor_label: Label
var _mute_btn: Button
var _gold_label: Label
var _kill_label: Label
var _enemy_label: Label
var _joy = null
var _select_overlay: Control
var _levelup_overlay: Control
var _levelup_vbox: VBoxContainer
var _death_overlay: ColorRect
var _death_gold: Label
var _death_title: Label
var _victory_overlay: ColorRect
var _victory_stats: Label
var _relic_slots: Array = []
# v0.8 D4 新手引导
var _skill_hint_shown := false
var _hint_center: CenterContainer = null
var _hint_label: Label = null
var _hint_tween: Tween = null
var _weapon_slots: Array = []
var _passive_slots: Array = []
var _weapons_data: Array = []
var _equip_wrap: VBoxContainer
var _passives_data: Dictionary = {}
var _relics_data: Array = []
var _detail_layer: Control
var _detail_panel: PanelContainer
var _detail_icon: TextureRect
var _detail_name: Label
var _detail_lv: Label
var _detail_desc: Label

var WEAPON_ICONS: Dictionary = {}  # v0.8: data/icons.json（ContentDB）
var PASSIVE_ICONS: Dictionary = {}  # v0.8: data/icons.json（ContentDB）
# 骷髅大军图标染色（尸毒主题绿紫，区别于骷髅战士）
const SUMMON_TINT := {
	"skel_army": Color(0.62, 1.0, 0.72),
	"super_skel_army": Color(0.62, 1.0, 0.72),
}
var _boss_box: VBoxContainer
var _boss_name: Label
var _boss_bar: ProgressBar
var _current_options: Array = []
# v0.3 技能栏
var _player_ref: Node2D = null
var _skill_slots: Array = []
var _skills_data: Array = []
# v0.6 成就 toast（顶部，1.5 秒）
var _toast_panel: PanelContainer
var _toast_label: Label
var _toast_tween: Tween = null


func _ready() -> void:
	var icons: Dictionary = ContentDB.table("icons")
	WEAPON_ICONS = icons.get("weapons", {})
	PASSIVE_ICONS = icons.get("passives", {})
	_font = load("res://assets/fonts/hud-subset.ttf") as Font
	_build_bars()
	_build_labels()
	_build_equip_bars()
	_build_detail_panel()
	_build_boss_bar()
	_build_joystick()
	_build_select_overlay()
	_build_levelup_overlay()
	_build_death_overlay()
	_build_victory_overlay()
	_build_skill_bar()
	_build_toast()
	EventBus.toast_requested.connect(_on_toast_requested)


func _on_toast_requested(text: String) -> void:
	Achievements.drain_pending()  # 事件已携带文本，清空队列防 _process 残留重复
	show_toast(text)


func _mk_label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = Lang.t(text)
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	return l


func _mk_bar(fill_color: Color, w: float) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(w, 18)
	b.max_value = 100.0
	b.value = 100.0
	b.show_percentage = false
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.55)
	bg.set_corner_radius_all(6)
	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_color
	fill.set_corner_radius_all(6)
	b.add_theme_stylebox_override("background", bg)
	b.add_theme_stylebox_override("fill", fill)
	return b


func _build_bars() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_TOP_LEFT)
	box.position = Vector2(16, 12)
	box.add_theme_constant_override("separation", 3)
	add_child(box)
	_name_label = _mk_label("艾拉", 16)
	box.add_child(_name_label)
	_hp_bar = _mk_bar(Color(0.85, 0.25, 0.3), 220)
	box.add_child(_hp_bar)
	var xrow := HBoxContainer.new()
	xrow.add_theme_constant_override("separation", 8)
	box.add_child(xrow)
	_xp_bar = _mk_bar(Color(0.35, 0.6, 0.95), 160)
	xrow.add_child(_xp_bar)
	_level_label = _mk_label("Lv.1", 15)
	xrow.add_child(_level_label)


func _build_labels() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	box.offset_left = -330
	box.offset_right = -16
	box.offset_top = 12
	box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	box.add_theme_constant_override("separation", 2)
	add_child(box)
	_floor_label = _mk_label("第1层·地牢回廊", 17)
	_floor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(_floor_label)
	_gold_label = _mk_label("金币 0", 15)
	_gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(_gold_label)
	_kill_label = _mk_label("击杀 0", 15)
	_kill_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(_kill_label)
	_enemy_label = _mk_label("剩余 0", 15)
	_enemy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_enemy_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	box.add_child(_enemy_label)
	# 静音开关（暂停菜单入口：升级三选一/结算时可点）
	_mute_btn = Button.new()
	_mute_btn.text = Lang.t("声音开")
	_mute_btn.add_theme_font_override("font", _font)
	_mute_btn.add_theme_font_size_override("font_size", 18)
	_mute_btn.custom_minimum_size = Vector2(48, 36)
	_mute_btn.focus_mode = Control.FOCUS_NONE
	_mute_btn.pressed.connect(_on_mute_toggle)
	_mute_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	box.add_child(_mute_btn)
	_update_mute_btn()
	# 存档按钮：保存当前进度并回大厅
	var save_btn := Button.new()
	save_btn.text = Lang.t("存档")
	save_btn.add_theme_font_override("font", _font)
	save_btn.add_theme_font_size_override("font_size", 18)
	save_btn.custom_minimum_size = Vector2(48, 36)
	save_btn.focus_mode = Control.FOCUS_NONE
	save_btn.pressed.connect(_on_save_pressed)
	save_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	box.add_child(save_btn)


func _on_save_pressed() -> void:
	Sfx.play("click")
	var main := get_tree().current_scene
	if main and main.has_method("save_and_exit"):
		main.save_and_exit()
	else:
		show_toast("当前无法存档")


func _on_mute_toggle() -> void:
	Sfx.set_muted(not Meta.is_muted())
	_update_mute_btn()
	Sfx.play("click")


func _update_mute_btn() -> void:
	if is_instance_valid(_mute_btn):
		_mute_btn.text = Lang.t("声音关") if Meta.is_muted() else Lang.t("声音开")


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


# ---------- v0.8 D4 新手引导（首局中央提示） ----------
func start_first_run_hints() -> void:
	if Meta.victories() > 0 or Meta.max_floor() > 0:
		return
	_first_run_hint_seq()


func _first_run_hint_seq() -> void:
	await get_tree().create_timer(15.0, false).timeout
	if not is_inside_tree():
		return
	_show_center_hint(Lang.t("拖动屏幕左半边 = 移动"), 2.0)
	await get_tree().create_timer(10.0, false).timeout
	if not is_inside_tree():
		return
	_show_center_hint(Lang.t("武器会自动攻击最近的目标"), 2.0)


func _show_center_hint(text: String, dur: float) -> void:
	if _hint_center == null:
		_hint_center = CenterContainer.new()
		_hint_center.set_anchors_preset(Control.PRESET_FULL_RECT)
		_hint_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hint_label = Label.new()
		_hint_label.add_theme_font_override("font", _font)
		_hint_label.add_theme_font_size_override("font_size", 30)
		_hint_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.55))
		_hint_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
		_hint_label.add_theme_constant_override("shadow_offset_x", 2)
		_hint_label.add_theme_constant_override("shadow_offset_y", 2)
		_hint_center.add_child(_hint_label)
		add_child(_hint_center)
	_hint_label.text = text
	_hint_center.visible = true
	_hint_center.modulate.a = 1.0
	if _hint_tween != null and _hint_tween.is_valid():
		_hint_tween.kill()
	_hint_tween = create_tween()
	_hint_tween.tween_interval(dur)
	_hint_tween.tween_property(_hint_center, "modulate:a", 0.0, 0.6)
	_hint_tween.tween_callback(func() -> void: _hint_center.visible = false)


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
	_toast_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_toast_tween.tween_interval(1.5)
	_toast_tween.tween_property(_toast_panel, "modulate:a", 0.0, 0.4)
	_toast_tween.tween_callback(func() -> void: _toast_panel.visible = false)


# ---------- 装备栏（武器/被动/遗物，可点击看详情） ----------
func _slot_button() -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(44, 44)
	b.focus_mode = Control.FOCUS_NONE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.5)
	sb.set_corner_radius_all(6)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.5, 0.5, 0.55)
	b.add_theme_stylebox_override("normal", sb)
	var sbh := sb.duplicate() as StyleBoxFlat
	sbh.border_color = Color(1.0, 0.85, 0.5)
	b.add_theme_stylebox_override("hover", sbh)
	b.add_theme_stylebox_override("pressed", sbh)
	return b


func _slot_icon() -> TextureRect:
	var tr := TextureRect.new()
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 父节点 Button 不是容器：不用锚点，直接给显式矩形，保证图标居中
	tr.position = Vector2(2, 2)
	tr.size = Vector2(40, 40)
	return tr


func _build_equip_bars() -> void:
	var wrap := VBoxContainer.new()
	_equip_wrap = wrap
	wrap.set_anchors_preset(Control.PRESET_TOP_LEFT)
	wrap.position = Vector2(16, 108)
	wrap.add_theme_constant_override("separation", 6)
	wrap.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(wrap)
	# 武器 6 格
	var wrow := HBoxContainer.new()
	wrow.add_theme_constant_override("separation", 6)
	wrap.add_child(wrow)
	for i in range(GameData.WEAPON_SLOTS):
		var b := _slot_button()
		var tr := _slot_icon()
		b.add_child(tr)
		var idx := i
		b.pressed.connect(func() -> void: _show_detail("weapon", idx, b))
		wrow.add_child(b)
		_weapon_slots.append({"btn": b, "icon": tr})
	# 被动 6 格
	var prow := HBoxContainer.new()
	prow.add_theme_constant_override("separation", 6)
	wrap.add_child(prow)
	for i in range(GameData.PASSIVE_SLOTS):
		var b := _slot_button()
		var tr := _slot_icon()
		b.add_child(tr)
		var idx := i
		b.pressed.connect(func() -> void: _show_detail("passive", idx, b))
		prow.add_child(b)
		_passive_slots.append({"btn": b, "icon": tr})
	# 遗物 3 格
	var rrow := HBoxContainer.new()
	rrow.add_theme_constant_override("separation", 6)
	wrap.add_child(rrow)
	for i in range(GameData.RELIC_SLOTS):
		var b := _slot_button()
		var tr := _slot_icon()
		b.add_child(tr)
		var idx := i
		b.pressed.connect(func() -> void: _show_detail("relic", idx, b))
		rrow.add_child(b)
		_relic_slots.append({"btn": b, "icon": tr})


func set_weapons(weapons: Array) -> void:
	_weapons_data = weapons
	for i in range(_weapon_slots.size()):
		var tr: TextureRect = _weapon_slots[i]["icon"]
		if i < weapons.size():
			var wid := String(weapons[i]["id"])
			var base := GameData.base_weapon_of(wid)
			var path: String = WEAPON_ICONS.get(base, "")
			tr.texture = load(path) as Texture2D if path != "" else null
			tr.modulate = SUMMON_TINT.get(wid, Color.WHITE)
			# 超武金色描边
			var b: Button = _weapon_slots[i]["btn"]
			var sb := b.get_theme_stylebox("normal").duplicate() as StyleBoxFlat
			if GameData.is_super(wid):
				sb.border_color = Color(1.0, 0.82, 0.3)
				sb.set_border_width_all(2)
			else:
				sb.border_color = Color(0.5, 0.5, 0.55)
				sb.set_border_width_all(1)
			b.add_theme_stylebox_override("normal", sb)
		else:
			tr.texture = null
			tr.modulate = Color.WHITE


func set_passives(passives: Dictionary) -> void:
	_passives_data = passives
	var keys := passives.keys()
	for i in range(_passive_slots.size()):
		var tr: TextureRect = _passive_slots[i]["icon"]
		if i < keys.size():
			var pid := String(keys[i])
			var path: String = PASSIVE_ICONS.get(pid, "")
			tr.texture = load(path) as Texture2D if path != "" else null
		else:
			tr.texture = null


func set_relics(relics: Array) -> void:
	_relics_data = relics
	for i in range(_relic_slots.size()):
		var tr: TextureRect = _relic_slots[i]["icon"]
		var b: Button = _relic_slots[i]["btn"]
		if i < relics.size():
			tr.texture = load(String(GameData.RELICS[relics[i]]["icon"])) as Texture2D
			# v0.8 稀有度描边（StatBlock 口径：普通蓝/稀有紫/传说金）
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(0.08, 0.08, 0.12, 0.65)
			sb.set_corner_radius_all(8)
			sb.set_border_width_all(2)
			sb.border_color = StatBlock.rarity_color(String(GameData.RELICS[relics[i]]["rarity"]))
			b.add_theme_stylebox_override("normal", sb)
		else:
			tr.texture = null
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(0.08, 0.08, 0.12, 0.65)
			sb.set_corner_radius_all(8)
			sb.set_border_width_all(1)
			sb.border_color = Color(0.5, 0.5, 0.55)
			b.add_theme_stylebox_override("normal", sb)


# ---------- 装备详情弹窗 ----------
func _build_detail_panel() -> void:
	_detail_layer = Control.new()
	_detail_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_detail_layer.visible = false
	_detail_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_detail_layer)
	# 点空白关闭
	var bg := Button.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.flat = true
	bg.text = ""
	bg.focus_mode = Control.FOCUS_NONE
	bg.pressed.connect(func() -> void: _detail_layer.visible = false)
	_detail_layer.add_child(bg)
	# 详情面板：不再居中，而是锚定在被点击的槽位旁边（见 _position_detail_panel）
	var panel := PanelContainer.new()
	_detail_panel = panel
	panel.custom_minimum_size = Vector2(340, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.07, 0.12, 0.97)
	sb.set_corner_radius_all(10)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.75, 0.65, 0.4)
	panel.add_theme_stylebox_override("panel", sb)
	_detail_layer.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)
	# margin
	var mc := MarginContainer.new()
	mc.add_theme_constant_override("margin_left", 18)
	mc.add_theme_constant_override("margin_right", 18)
	mc.add_theme_constant_override("margin_top", 16)
	mc.add_theme_constant_override("margin_bottom", 16)
	vb.add_child(mc)
	var iv := VBoxContainer.new()
	iv.add_theme_constant_override("separation", 10)
	mc.add_child(iv)
	var hc := HBoxContainer.new()
	hc.add_theme_constant_override("separation", 14)
	iv.add_child(hc)
	_detail_icon = TextureRect.new()
	_detail_icon.custom_minimum_size = Vector2(64, 64)
	_detail_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_detail_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hc.add_child(_detail_icon)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 4)
	hc.add_child(tv)
	_detail_name = _mk_label("", 22)
	tv.add_child(_detail_name)
	_detail_lv = _mk_label("", 15)
	_detail_lv.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	tv.add_child(_detail_lv)
	_detail_desc = _mk_label("", 15)
	_detail_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_desc.custom_minimum_size = Vector2(220, 0)
	iv.add_child(_detail_desc)


func _show_detail(kind: String, idx: int, btn: Button) -> void:
	var icon_tex: Texture2D = null
	var title := ""
	var lv_text := ""
	var desc := ""
	if kind == "weapon":
		if idx < 0 or idx >= _weapons_data.size():
			return
		var w: Dictionary = _weapons_data[idx]
		var wid := String(w["id"])
		var lv := int(w["lv"])
		var base := GameData.base_weapon_of(wid)
		var d: Dictionary = GameData.WEAPONS[base]
		icon_tex = load(String(WEAPON_ICONS.get(base, ""))) as Texture2D
		if GameData.is_super(wid):
			title = "【超武】" + String(GameData.SUPERWEAPONS[wid]["name"])
			lv_text = "MAX · 不再升级"
		else:
			title = String(d["name"])
			lv_text = "Lv.%d / %d" % [lv, GameData.WEAPON_MAX_LV]
		desc = _weapon_desc(wid, lv, d)
	elif kind == "passive":
		var keys := _passives_data.keys()
		if idx < 0 or idx >= keys.size():
			return
		var pid := String(keys[idx])
		var lv := int(_passives_data[pid])
		var d: Dictionary = GameData.PASSIVES[pid]
		icon_tex = load(String(PASSIVE_ICONS.get(pid, ""))) as Texture2D
		title = String(d["name"])
		lv_text = "Lv.%d / %d" % [lv, GameData.PASSIVE_MAX_LV]
		var per := float(d["per"]) * 100.0
		desc = Lang.t("每级 +%d%%，当前 +%d%%") % [int(per), int(per * lv)]
	elif kind == "relic":
		if idx < 0 or idx >= _relics_data.size():
			return
		var rid := String(_relics_data[idx])
		var d: Dictionary = GameData.RELICS[rid]
		icon_tex = load(String(d["icon"])) as Texture2D
		title = String(d["name"])
		lv_text = String(d["rarity"])
		lv_text = "【" + lv_text + "】"
		desc = String(d["desc"])
	else:
		return
	_detail_icon.texture = icon_tex
	_detail_name.text = Lang.t(title)
	_detail_lv.text = Lang.t(lv_text)
	_detail_desc.text = Lang.t(desc)
	_detail_layer.visible = true
	_position_detail_panel.call_deferred(btn)


## 把详情面板放到被点击槽位旁边（优先右侧），钳制在屏幕内
func _position_detail_panel(btn: Button) -> void:
	if not is_instance_valid(btn) or not _detail_layer.visible:
		return
	var vp := _detail_layer.size
	if vp.x <= 0.0:
		return
	var ps := _detail_panel.get_combined_minimum_size()
	var br := btn.get_global_rect()
	var x := br.end.x + 10.0
	var y := br.position.y
	if x + ps.x > vp.x:
		x = br.position.x - 10.0 - ps.x
		if x < 8.0:
			x = 8.0
	if y + ps.y > vp.y:
		y = vp.y - ps.y - 8.0
	_detail_panel.position = Vector2(maxf(8.0, x), maxf(8.0, y))


func _weapon_desc(wid: String, lv: int, d: Dictionary) -> String:
	var lines: Array = []
	var kind := String(d["kind"])
	var is_super := GameData.is_super(wid)
	var el := GameData.WEAPON_MAX_LV if is_super else lv  # 超武按 Lv8 词条全解锁显示
	match kind:
		"aoe", "shock", "arc":
			lines.append(Lang.t("范围 %.0f · 冷却 %.1fs") % [float(d.get("radius", 0)), float(d["cd"])])
		"summon":
			lines.append(Lang.t("维持 %d 只 · 冷却 %.1fs") % [int(d.get("count", 1)), float(d["cd"])])
		"corpse":
			lines.append(Lang.t("爆炸 %.0f · 范围 %.0f") % [float(d["dmg"]), float(d.get("radius", 0))])
		"drain":
			lines.append(Lang.t("伤害 %.0f · 链式 %d") % [float(d["dmg"]), int(d.get("chain", 0))])
		"aura":
			lines.append(Lang.t("每秒 %.0f · 范围 %.0f") % [float(d["dmg"]), float(d.get("radius", 0))])
		"orbit":
			lines.append(Lang.t("斧刃 %d · 半径 %.0f") % [int(d.get("count", 1)), float(d.get("radius", 0))])
		"boomerang":
			lines.append(Lang.t("伤害 %.0f · 冷却 %.1fs") % [float(d["dmg"]), float(d["cd"])])
		_:
			lines.append(Lang.t("伤害 %.0f · 冷却 %.2fs") % [float(d["dmg"]), float(d["cd"])])
	var extras: Array = []
	if int(d.get("count", 1)) > 1 and kind != "summon" and kind != "orbit":
		extras.append(Lang.t("数量 %d") % int(d["count"]))
	if int(d.get("pierce", 0)) > 0:
		extras.append(Lang.t("穿透 %d") % int(d["pierce"]))
	if int(d.get("chain", 0)) > 0:
		extras.append(Lang.t("弹射 %d") % int(d["chain"]))
	if float(d.get("explosive", 0.0)) > 0.0:
		extras.append(Lang.t("爆炸 %.0f") % float(d["explosive"]))
	if not extras.is_empty():
		lines.append(" · ".join(extras))
	# 已解锁 signature
	var sig: Dictionary = d.get("sig", {})
	var unlocked: Array = []
	for slv in sig.keys():
		if el >= int(slv):
			unlocked.append("Lv%d" % int(slv))
	if not unlocked.is_empty():
		lines.append(Lang.t("已解锁: ") + " ".join(unlocked))
	if is_super:
		var sw: Dictionary = GameData.SUPERWEAPONS[wid]
		lines.append(Lang.t("合成:%s+%s") % [String(GameData.WEAPONS[String(sw["weapon"])]["name"]),
			String(GameData.PASSIVES[String(sw["passive"])]["name"])])
	return "\n".join(lines)


func _build_boss_bar() -> void:
	_boss_box = VBoxContainer.new()
	_boss_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_boss_box.position = Vector2(-210, 12)
	_boss_box.custom_minimum_size = Vector2(420, 40)
	_boss_box.add_theme_constant_override("separation", 2)
	_boss_box.visible = false
	add_child(_boss_box)
	_boss_name = _mk_label("Boss", 18)
	_boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_box.add_child(_boss_name)
	_boss_bar = _mk_bar(Color(0.7, 0.15, 0.6), 420)
	_boss_box.add_child(_boss_bar)


func _build_joystick() -> void:
	_joy = load("res://scripts/joystick.gd").new()
	# 左半屏浮动触区：手指落哪，摇杆就出哪
	_joy.anchor_left = 0.0
	_joy.anchor_top = 0.0
	_joy.anchor_right = 0.5
	_joy.anchor_bottom = 1.0
	_joy.offset_left = 0.0
	_joy.offset_top = 0.0
	_joy.offset_right = 0.0
	_joy.offset_bottom = 0.0
	_joy.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_joy)
	# 沉到装备栏下面，避免吞掉装备槽的点击
	if is_instance_valid(_equip_wrap):
		move_child(_joy, _equip_wrap.get_index())


func get_move_vector() -> Vector2:
	return _joy.value if is_instance_valid(_joy) else Vector2.ZERO


# ---------- v0.3 技能栏（右下，自动/手动切换） ----------
func bind_player(p: Node2D) -> void:
	_player_ref = p


func _build_skill_bar() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	box.position = Vector2(-170, -190)
	box.add_theme_constant_override("separation", 8)
	box.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(box)
	for i in range(2):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		box.add_child(row)
		var b := Button.new()
		b.custom_minimum_size = Vector2(64, 64)
		b.focus_mode = Control.FOCUS_NONE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0.55)
		sb.set_corner_radius_all(8)
		sb.set_border_width_all(2)
		sb.border_color = Color(0.5, 0.7, 1.0)
		b.add_theme_stylebox_override("normal", sb)
		var sbd := sb.duplicate() as StyleBoxFlat
		sbd.bg_color = Color(0.1, 0.1, 0.12, 0.75)
		b.add_theme_stylebox_override("disabled", sbd)
		var tr := TextureRect.new()
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.position = Vector2(4, 4)
		tr.size = Vector2(56, 56)
		b.add_child(tr)
		var cdl := _mk_label("", 20)
		cdl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cdl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cdl.position = Vector2(0, 0)
		cdl.size = Vector2(64, 64)
		cdl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(cdl)
		var idx := i
		b.pressed.connect(func() -> void: _on_skill_btn(idx))
		row.add_child(b)
		var ab := Button.new()
		ab.custom_minimum_size = Vector2(44, 44)
		ab.focus_mode = Control.FOCUS_NONE
		ab.add_theme_font_override("font", _font)
		ab.add_theme_font_size_override("font_size", 18)
		ab.pressed.connect(func() -> void: _on_skill_auto(idx))
		row.add_child(ab)
		b.visible = false
		ab.visible = false
		_skill_slots.append({"btn": b, "icon": tr, "cd": cdl, "auto": ab})


func _on_skill_btn(idx: int) -> void:
	if is_instance_valid(_player_ref) and _player_ref.has_method("try_cast_skill"):
		_player_ref.try_cast_skill(idx)


func _on_skill_auto(idx: int) -> void:
	if is_instance_valid(_player_ref) and _player_ref.has_method("toggle_skill_auto"):
		_player_ref.toggle_skill_auto(idx)


func set_skills(skills: Array) -> void:
	_skills_data = skills
	# v0.8 D4：技能栏首次凑满 2 个技能时提示自动/手动（每局一次）
	if skills.size() >= 2 and not _skill_hint_shown:
		_skill_hint_shown = true
		show_toast(Lang.t("技能默认自动释放，可切手动"))
	for i in range(_skill_slots.size()):
		var slot: Dictionary = _skill_slots[i]
		if i < skills.size():
			var sk: Dictionary = skills[i]
			var sid := String(sk["id"])
			var sd: Dictionary = GameData.SKILLS[sid]
			(slot["icon"] as TextureRect).texture = load(String(sd["icon"])) as Texture2D
			(slot["btn"] as Button).visible = true
			(slot["auto"] as Button).visible = true
			(slot["auto"] as Button).text = Lang.t("自") if bool(sk["auto"]) else Lang.t("手")
		else:
			(slot["btn"] as Button).visible = false
			(slot["auto"] as Button).visible = false


func _process(_delta: float) -> void:
	# v0.8：成就 toast 改 EventBus 事件驱动（见 _on_toast_requested），不再每帧 drain
	if _player_ref == null or not is_instance_valid(_player_ref):
		return
	var sks: Array = _player_ref.get("skills")
	if sks.is_empty():
		return
	for i in range(_skill_slots.size()):
		if i >= sks.size():
			break
		var sk: Dictionary = sks[i]
		var slot: Dictionary = _skill_slots[i]
		var cd_t := float(sk["cd_t"])
		(slot["cd"] as Label).text = "%d" % int(ceil(cd_t)) if cd_t > 0.0 else ""
		(slot["btn"] as Button).disabled = cd_t > 0.0
		(slot["auto"] as Button).text = Lang.t("自") if bool(sk["auto"]) else Lang.t("手")


# ---------- runtime updates ----------
func set_hp(hp: float, max_hp: float, char_name: String) -> void:
	_name_label.text = Lang.t(char_name)
	_hp_bar.max_value = max_hp
	_hp_bar.value = hp


func set_xp(xp: int, xp_need: int, level: int) -> void:
	_xp_bar.max_value = float(xp_need)
	_xp_bar.value = float(xp)
	_level_label.text = "Lv.%d" % level


func set_gold(g: int) -> void:
	_gold_label.text = Lang.t("金币 %d") % g


func set_kills(k: int) -> void:
	_kill_label.text = Lang.t("击杀 %d") % k


func set_enemies(n: int) -> void:
	_enemy_label.text = Lang.t("剩余 %d") % n if n > 0 else Lang.t("上楼!")


func set_floor(floor_num: int, floor_name: String) -> void:
	_floor_label.text = Lang.t("第%d层·%s") % [floor_num, Lang.t(floor_name)]


func show_boss_bar(boss_name: String) -> void:
	_boss_name.text = Lang.t(boss_name)
	_boss_box.visible = true


func hide_boss_bar() -> void:
	_boss_box.visible = false


func set_boss_hp(hp: float, max_hp: float) -> void:
	_boss_bar.max_value = max_hp
	_boss_bar.value = hp


# ---------- character select ----------
func _build_select_overlay() -> void:
	_select_overlay = _dim_layer()
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_select_overlay.add_child(center)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 18)
	center.add_child(vb)
	var t := _mk_label("选择角色", 40)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	# 窄屏（手机竖屏）时卡片改竖排+滚动，避免右侧被裁
	# 注意：stretch=expand 下 viewport 宽恒为 960，竖屏时高>宽
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var narrow: bool = vp_size.y > vp_size.x
	if narrow:
		# 竖屏：卡片竖排全量展示（viewport 高 2000+，三张卡 812px 放得下，不用滚动）
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 16)
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		vb.add_child(col)
		for cid in GameData.CHAR_ORDER:
			var card := _char_card(cid, true)
			var cc := CenterContainer.new()
			cc.add_child(card)
			col.add_child(cc)
	else:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 24)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		vb.add_child(row)
		for cid in GameData.CHAR_ORDER:
			row.add_child(_char_card(cid, false))


func _char_card(cid: String, compact: bool = false) -> Control:
	var d: Dictionary = GameData.CHARACTERS[cid]
	var panel := PanelContainer.new()
	var card_w: float = 180.0 if compact else 220.0
	var card_h: float = 286.0 if compact else 326.0
	panel.custom_minimum_size = Vector2(card_w, card_h)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.09, 0.14, 0.95)
	sb.set_corner_radius_all(10)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.75, 0.65, 0.4)
	panel.add_theme_stylebox_override("panel", sb)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)
	# portrait from the down idle sprite
	var tex := load("res://assets/sprites/characters/%s/char_%s_down_idle_00.png" % [cid, cid]) as Texture2D
	var pr := TextureRect.new()
	pr.texture = tex
	pr.custom_minimum_size = Vector2(96, 96) if compact else Vector2(128, 128)
	pr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vb.add_child(pr)
	var n := _mk_label(String(d["name"]), 24)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(n)
	var ti := _mk_label(String(d["title"]), 15)
	ti.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ti.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	vb.add_child(ti)
	var de := _mk_label(String(d["desc"]), 13)
	de.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	de.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	de.custom_minimum_size = Vector2(160, 40) if compact else Vector2(200, 40)
	vb.add_child(de)
	# v0.8 D4：卡片底部玩法一句话（新手 3 分钟 T+0）
	var hint := _mk_label("走位躲怪，武器自动开火，升级选构筑", 12)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color(0.85, 0.85, 0.75))
	vb.add_child(hint)
	var b := Button.new()
	if Meta.is_char_unlocked(cid):
		b.text = Lang.t("开始")
	else:
		b.text = Lang.t("未解锁")
		b.disabled = true
		var lk := _mk_label(Meta.char_unlock_desc(cid), 13)
		lk.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lk.add_theme_color_override("font_color", Color(1.0, 0.6, 0.4))
		vb.add_child(lk)
	b.add_theme_font_override("font", _font)
	b.add_theme_font_size_override("font_size", 20)
	b.custom_minimum_size = Vector2(140, 44) if compact else Vector2(160, 48)
	b.pressed.connect(func() -> void: character_chosen.emit(cid))
	var bc := CenterContainer.new()
	bc.add_child(b)
	vb.add_child(bc)
	return panel


func hide_select() -> void:
	_select_overlay.visible = false


# ---------- level-up choice ----------
func _build_levelup_overlay() -> void:
	_levelup_overlay = _dim_layer()
	_levelup_overlay.visible = false
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_levelup_overlay.add_child(center)
	_levelup_vbox = VBoxContainer.new()
	_levelup_vbox.add_theme_constant_override("separation", 14)
	center.add_child(_levelup_vbox)


func _dim_layer() -> Control:
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.72)
	dim.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(dim)
	return dim


func is_levelup_open() -> bool:
	return _levelup_overlay.visible


func get_levelup_options() -> Array:
	return _current_options


func show_levelup(options: Array) -> void:
	_current_options = options
	for c in _levelup_vbox.get_children():
		c.queue_free()
	var t := _mk_label("升级!三选一", 34)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_levelup_vbox.add_child(t)
	for i in range(options.size()):
		var opt: Dictionary = options[i]
		var b := Button.new()
		b.text = "%s\n%s" % [String(opt["title"]), String(opt["desc"])]
		b.add_theme_font_override("font", _font)
		b.add_theme_font_size_override("font_size", 19)
		b.custom_minimum_size = Vector2(360, 64)
		if String(opt["type"]) == "synthesize":
			# 金色合成选项
			b.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
			var gsb := StyleBoxFlat.new()
			gsb.bg_color = Color(0.25, 0.18, 0.05, 0.95)
			gsb.set_corner_radius_all(8)
			gsb.set_border_width_all(3)
			gsb.border_color = Color(1.0, 0.82, 0.3)
			b.add_theme_stylebox_override("normal", gsb)
			var gsbh := gsb.duplicate() as StyleBoxFlat
			gsbh.bg_color = Color(0.35, 0.25, 0.08, 0.95)
			b.add_theme_stylebox_override("hover", gsbh)
			b.add_theme_stylebox_override("pressed", gsbh)
		elif bool(opt.get("recommended", false)):
			# v0.8 推荐金框（复用合成金框样式）+ 右上角「推荐」小标签
			var rsb := StyleBoxFlat.new()
			rsb.bg_color = Color(0.16, 0.13, 0.05, 0.95)
			rsb.set_corner_radius_all(8)
			rsb.set_border_width_all(2)
			rsb.border_color = Color(1.0, 0.82, 0.3)
			b.add_theme_stylebox_override("normal", rsb)
			var tag := Label.new()
			tag.text = Lang.t("推荐")
			tag.add_theme_font_override("font", _font)
			tag.add_theme_font_size_override("font_size", 12)
			tag.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
			tag.anchor_left = 1.0
			tag.anchor_right = 1.0
			tag.offset_left = -46
			tag.offset_right = -6
			tag.offset_top = 3
			tag.offset_bottom = 19
			tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.add_child(tag)
		var idx := i
		b.pressed.connect(func() -> void: _on_upgrade_btn(idx))
		_levelup_vbox.add_child(b)
	_levelup_overlay.visible = true


func _on_upgrade_btn(idx: int) -> void:
	if idx < 0 or idx >= _current_options.size():
		return
	_levelup_overlay.visible = false
	Sfx.play("click")
	if String(_current_options[idx]["type"]) == "synthesize":
		var pos := Vector2.ZERO
		if _player_ref != null and is_instance_valid(_player_ref):
			pos = _player_ref.global_position
		EventBus.superweapon_synthesized.emit(String(_current_options[idx].get("super_id", "")), pos)
	upgrade_chosen.emit(_current_options[idx])


# ---------- death ----------
func _build_death_overlay() -> void:
	_death_overlay = ColorRect.new()
	_death_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_death_overlay.color = Color(0, 0, 0, 0.7)
	_death_overlay.visible = false
	_death_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_death_overlay)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_death_overlay.add_child(center)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	center.add_child(vb)
	var t := _mk_label("你死了", 44)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death_title = t
	vb.add_child(t)
	_death_gold = _mk_label("", 20)
	_death_gold.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death_gold.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	vb.add_child(_death_gold)
	var rb := Button.new()
	rb.text = Lang.t("重新开始")
	rb.add_theme_font_override("font", _font)
	rb.add_theme_font_size_override("font_size", 22)
	rb.custom_minimum_size = Vector2(200, 56)
	rb.pressed.connect(_on_restart)
	vb.add_child(rb)


func show_death(gold_earned: int) -> void:
	_death_gold.text = Lang.t("金币 +%d 已入库") % gold_earned
	_death_overlay.visible = true


func _on_restart() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")


# ---------- victory ----------
func _build_victory_overlay() -> void:
	_victory_overlay = ColorRect.new()
	_victory_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_victory_overlay.color = Color(0.05, 0.03, 0.0, 0.85)
	_victory_overlay.visible = false
	_victory_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_victory_overlay)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_victory_overlay.add_child(center)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	center.add_child(vb)
	var t := _mk_label("通关!", 48)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	vb.add_child(t)
	var t2 := _mk_label("深渊主宰·墨骸 已被击败", 20)
	t2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t2)
	_victory_stats = _mk_label("", 20)
	_victory_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_victory_stats)
	var rb := Button.new()
	rb.text = Lang.t("再来一局")
	rb.add_theme_font_override("font", _font)
	rb.add_theme_font_size_override("font_size", 22)
	rb.custom_minimum_size = Vector2(200, 56)
	rb.pressed.connect(_on_restart)
	var bc := CenterContainer.new()
	bc.add_child(rb)
	vb.add_child(bc)
	# 无尽模式入口
	var eb := Button.new()
	eb.text = Lang.t("进入无尽（31层起）")
	eb.add_theme_font_override("font", _font)
	eb.add_theme_font_size_override("font_size", 22)
	eb.custom_minimum_size = Vector2(260, 56)
	eb.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	eb.pressed.connect(_on_endless)
	var ec := CenterContainer.new()
	ec.add_child(eb)
	vb.add_child(ec)


func _on_endless() -> void:
	Sfx.play("click")
	endless_chosen.emit()


func hide_victory() -> void:
	_victory_overlay.visible = false


# ---------- 无尽死亡结算 ----------
func show_endless_death(floor_num: int, score: int, gold_earned: int) -> void:
	_death_title.text = Lang.t("无尽终焉 · 第 %d 层") % floor_num
	_death_gold.text = Lang.t("评分 %d\n金币 +%d 已入库（×1.5）") % [score, gold_earned]
	_death_overlay.visible = true


func show_victory(floor_num: int, kills: int, run_time: float, gold_earned: int) -> void:
	var mm := int(run_time) / 60
	var ss := int(run_time) % 60
	_victory_stats.text = Lang.t("层数 %d · 击杀 %d · 用时 %d分%02d秒\n金币 +%d 已入库") % [floor_num, kills, mm, ss, gold_earned]
	_victory_overlay.visible = true
