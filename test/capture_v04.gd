extends SceneTree
## v0.4 验证：大厅4页签 / 买天赋 / 解锁 / 开局加成 / 结算入库 / 存档读写
## Run: xvfb-run godot --rendering-driver opengl3 --audio-driver Dummy --path . --script res://test/capture_v04.gd

const OUT := "/tmp/godot_v04"


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	# 干净存档起步
	var d := DirAccess.open("user://")
	if d != null and d.file_exists("savegame.cfg"):
		d.remove("savegame.cfg")
	Meta._loaded = false
	var inst: Node = load("res://scenes/lobby.tscn").instantiate()
	root.add_child(inst)
	_run.call_deferred()


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	var img: Image = root.get_texture().get_image()
	img.save_png(OUT + "/" + name + ".png")
	print("shot: ", name)


func _wait(secs: float) -> void:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < int(secs * 1000.0):
		await process_frame


func _run() -> void:
	var lobby: Control = root.get_child(root.get_child_count() - 1)
	await _wait(1.0)
	# 给测试金币
	Meta.add_gold(5000)
	print("gold after add: ", Meta.gold())
	await _shot("v01_lobby_talent")
	# 买天赋：锋利
	print("buy sharp: ", Meta.buy_talent("sharp"), " lv=", Meta.talent_lv("sharp"), " gold=", Meta.gold())
	print("buy vitality: ", Meta.buy_talent("vitality"))
	print("buy undying: ", Meta.buy_talent("undying"))
	lobby._on_tab("talent")
	await _wait(0.6)
	await _shot("v02_talent_bought")
	# 强化页
	lobby._on_tab("attr")
	print("buy atk attr: ", Meta.buy_attr("atk"), " lv=", Meta.attr_lv("atk"))
	lobby._on_tab("attr")
	await _wait(0.6)
	await _shot("v03_attr")
	# 解锁页
	lobby._on_tab("unlock")
	await _wait(0.6)
	await _shot("v04_unlock_before")
	print("buy hound: ", Meta.buy_weapon("hound"), " unlocked=", Meta.is_weapon_unlocked("hound"))
	print("unlock batong: ", Meta.try_unlock_char("batong"), " unlocked=", Meta.is_char_unlocked("batong"))
	lobby._on_tab("unlock")
	await _wait(0.6)
	await _shot("v05_unlock_after")
	# 出战页
	lobby._on_tab("fight")
	await _wait(0.6)
	await _shot("v06_fight")
	# 开局：验证加成 (体魄+10血， 锋利+4%攻）
	lobby._on_fight("aila")
	var tries := 0
	var game: Node = null
	while tries < 200:
		await process_frame
		game = get_first_node_in_group("game")
		if game != null and game.get("player") != null:
			break
		tries += 1
	var p = game.get("player")
	print("BONUS_CHECK max_hp=", p.max_hp, " (expect 110) dmg_mult=", p._dmg_mult(), " (expect ~1.06)")
	await _wait(1.0)
	await _shot("v07_ingame_bonus")
	# 结算入库
	p.gold = 250
	game._bank_run_gold(false)
	print("banked: ", game._last_banked, " meta gold=", Meta.gold())
	# 存档重读
	Meta._loaded = false
	print("RELOAD gold=", Meta.gold(), " sharp=", Meta.talent_lv("sharp"), " hound=", Meta.is_weapon_unlocked("hound"), " batong=", Meta.is_char_unlocked("batong"))
	print("V04_CAPTURE_DONE")
	quit()
