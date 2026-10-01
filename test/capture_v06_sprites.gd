extends SceneTree
## v0.6 精灵验证：巴顿/墨菲下+右行走帧 + 替换后实战。
## Run: xvfb-run godot --rendering-driver opengl3 --audio-driver Dummy --path <project> --script res://test/capture_v06_sprites.gd

const OUT := "/tmp/sprite_verify"


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


func _set_walk(player: Node, dirn: String, vec: Vector2) -> void:
	player.dir_name = dirn
	player.facing = vec
	player.velocity = vec * 120.0
	player._walk_t = 0.6  # 非零 -> 行走帧
	# 强制切到对应 walk 动画
	var spr = player.get_node_or_null("Sprite2D")
	if spr == null:
		for c in player.get_children():
			if c is AnimatedSprite2D:
				spr = c
				break
	if spr and spr is AnimatedSprite2D:
		var anim := "walk_" + dirn
		if spr.sprite_frames.has_animation(anim):
			spr.play(anim)
			spr.frame = 1


func _run() -> void:
	# 测试解锁（绕开解锁条件）：先触发 _ensure 读盘，再追加并落盘
	Meta.gold()
	for cid in ["batong", "mofei"]:
		if not Meta._unlocked_chars.has(cid):
			Meta._unlocked_chars.append(cid)
	Meta.save_data()
	Meta.selected_char = "batong"
	var game: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await _wait(0.5)
	game._on_character_chosen("batong")
	await _wait(1.5)
	if not is_instance_valid(game.player):
		print("FATAL: player not spawned")
		quit()
		return
	var player = game.player
	# 清怪清投射物，纯摆拍
	for e in get_nodes_in_group("enemies"):
		e.queue_free()
	await _wait(0.3)

	# 巴顿 下行走
	player.global_position = Vector2(480, 300)
	_set_walk(player, "down", Vector2.DOWN)
	await _wait(0.4)
	await _shot("v06_batong_walk_down")

	# 巴顿 右行走
	_set_walk(player, "right", Vector2.RIGHT)
	await _wait(0.4)
	await _shot("v06_batong_walk_right")

	# 巴顿实战（含攻击摆拍）
	for e in get_nodes_in_group("enemies"):
		e.queue_free()
	await _wait(1.5)
	await _shot("v06_batong_combat")

	# ---- 墨菲 ----
	root.remove_child(game)
	game.queue_free()
	await _wait(0.5)
	Meta.selected_char = "mofei"
	var game2: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game2)
	await _wait(0.5)
	game2._on_character_chosen("mofei")
	await _wait(1.5)
	if not is_instance_valid(game2.player):
		print("FATAL: mofei player not spawned")
		quit()
		return
	var p2 = game2.player
	for e in get_nodes_in_group("enemies"):
		e.queue_free()
	await _wait(0.3)
	p2.global_position = Vector2(480, 300)
	_set_walk(p2, "down", Vector2.DOWN)
	await _wait(0.4)
	await _shot("v06_mofei_walk_down")
	_set_walk(p2, "right", Vector2.RIGHT)
	await _wait(0.4)
	await _shot("v06_mofei_walk_right")
	for e in get_nodes_in_group("enemies"):
		e.queue_free()
	await _wait(1.5)
	await _shot("v06_mofei_combat")
	print("SPRITE DONE")
	quit()
