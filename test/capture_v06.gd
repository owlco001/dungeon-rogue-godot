extends SceneTree
## v0.6 验证：成就系统 + 天赋点货币 + 旧存档迁移。
## Run: xvfb-run godot --rendering-driver opengl3 --audio-driver Dummy --path <project> --script res://test/capture_v06.gd

const OUT := "/tmp/ach_verify"


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
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


func _write_old_save() -> void:
	# 模拟 v0.5 旧存档：金币买过天赋，无 talent_points / migrated_v06 字段
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "gold", 5000)
	cfg.set_value("meta", "talents", {"sharp": 3, "undying": 1})
	cfg.set_value("meta", "attrs", {})
	cfg.set_value("meta", "unlocked_chars", ["aila"])
	cfg.set_value("meta", "unlocked_weapons", [])
	cfg.set_value("records", "max_floor", 12)
	cfg.set_value("records", "victories", 0)
	cfg.set_value("records", "bosses", [])
	cfg.set_value("records", "endless_best_floor", 0)
	cfg.set_value("records", "endless_best_score", 0)
	cfg.set_value("meta", "muted", false)
	var err := cfg.save("user://savegame.cfg")
	print("old save written err=", err, " (expect 0)")


func _run() -> void:
	# ---- 1. 旧存档迁移 toast ----
	# 预期：退回 120*(1+2+3)+2000=2720 金币，发放 3*1+1*3=6 天赋点
	_write_old_save()
	var lobby: Node = load("res://scenes/lobby.tscn").instantiate()
	root.add_child(lobby)
	await _wait(1.2)
	await _shot("v06_1_migration_toast")
	print("after migration: gold=", Meta.gold(), " tp=", Meta.talent_points(),
		" sharp_lv=", Meta.talent_lv("sharp"), " undying_lv=", Meta.talent_lv("undying"))

	# ---- 2. 天赋页：天赋点价格 ----
	lobby._on_tab("talent")
	await _wait(0.6)
	await _shot("v06_2_talent_points_price")

	# ---- 3. 天赋点购买成功 ----
	Meta.add_talent_points(30)
	print("buy sharp(lv3->4, 1pt): ", Meta.buy_talent("sharp"), " tp=", Meta.talent_points())
	print("buy undying(maxed, expect false): ", Meta.buy_talent("undying"))
	# 质变 3 点购买：先给点数再买 magnetbody
	Meta.buy_talent("magnetbody")
	print("buy magnetbody(3pt): tp=", Meta.talent_points(), " lv=", Meta.talent_lv("magnetbody"))
	lobby._on_tab("talent")
	await _wait(0.6)
	await _shot("v06_3_talent_bought")

	# ---- 4. 收集页（未完成态） ----
	lobby._on_tab("achieve")
	await _wait(0.6)
	await _shot("v06_4_achieve_tab")

	# ---- 5. 模拟成就达成 toast ----
	print("unlock boss_5: ", Achievements.unlock("boss_5"))
	print("unlock super1: ", Achievements.unlock("super1"))
	print("unlock boss_5 again (expect false): ", Achievements.unlock("boss_5"))
	print("tp after unlocks: ", Meta.talent_points())
	await _wait(0.8)
	await _shot("v06_5_achievement_toast")

	# ---- 6. 收集页（已完成高亮） ----
	lobby._on_tab("achieve")
	await _wait(0.6)
	await _shot("v06_6_achieve_tab_done")

	# ---- 7. 游戏内 toast ----
	root.remove_child(lobby)
	lobby.queue_free()
	await _wait(0.5)
	Meta.selected_char = "aila"
	var game: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await _wait(2.0)
	if not is_instance_valid(game.player):
		print("FATAL: player not spawned")
		quit()
		return
	print("unlock kill1000 ingame: ", Achievements.unlock("kill1000"))
	await _wait(0.8)
	await _shot("v06_7_ingame_toast")
	print("ALL DONE, total_kills=", Meta.total_kills())
	quit()
