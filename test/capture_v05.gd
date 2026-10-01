extends SceneTree
## v0.5 验证：无尽模式 + 音效 + 大厅纪录/静音。
## Run: godot --rendering-driver opengl3 --audio-driver Dummy --path <project> --script res://test/capture_v05.gd

const OUT := "/tmp/godot_cap_v05"


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


func _run() -> void:
	# ---- 大厅：无尽纪录 + 静音按钮 ----
	Meta.record_endless(47, 5230)
	Meta.add_gold(900)
	var lobby: Node = load("res://scenes/lobby.tscn").instantiate()
	root.add_child(lobby)
	await _wait(1.0)
	await _shot("v01_lobby_endless_record")
	# 静音开关
	lobby._on_mute_toggle()
	await _wait(0.4)
	await _shot("v02_lobby_muted")
	lobby._on_mute_toggle()  # 恢复有声
	root.remove_child(lobby)
	lobby.queue_free()
	await _wait(0.5)

	# ---- 进游戏 ----
	Meta.selected_char = "aila"
	var game: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await _wait(2.5)  # 等开局
	if not is_instance_valid(game.player):
		print("FATAL: player not spawned")
		quit()
		return
	# 给点构筑免得截图太素
	game.player.add_weapon("dual")
	game.player.add_weapon("sentry")
	await _wait(1.0)
	await _shot("v03_ingame_base")

	# ---- 通关结算：进入无尽按钮 ----
	game.floor_num = 30
	game._on_victory()
	await _wait(0.6)
	await _shot("v04_victory_endless_btn")

	# ---- 进入无尽：31 层 ----
	game.enter_endless()
	await _wait(2.0)
	await _shot("v05_endless_floor31")
	print("endless flag: ", game.endless, " floor: ", game.floor_num)

	# ---- 无尽 Boss（35 层 = 噬影蝠王·2轮）----
	game.floor_num = 34
	game.next_floor()
	await _wait(2.0)
	await _shot("v06_endless_boss35")

	# ---- 无尽死亡结算 ----
	game._on_player_died()
	await _wait(0.6)
	await _shot("v07_endless_death")

	print("endless best: ", Meta.endless_best_floor(), " / ", Meta.endless_best_score())
	print("V05 DONE")
	quit()
