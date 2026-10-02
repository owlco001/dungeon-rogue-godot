extends SceneTree
## 怪物 move/idle 切换验证：每种怪建 move 动画 2 帧；追击时播 move，停下播 idle。

var fails := 0

func _check(name: String, cond: bool, info := "") -> void:
	if cond:
		print("PASS ", name, " | ", info)
	else:
		fails += 1
		print("FAIL ", name, " | ", info)


func _initialize() -> void:
	_run.call_deferred()


func _wait(secs: float) -> void:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < int(secs * 1000.0):
		await process_frame


func _run() -> void:
	var EnemyScript := load("res://scripts/enemy.gd")
	var eids := ["slime", "bat", "skeleton", "brute", "spitter", "exploder", "gargoyle"]
	for eid in eids:
		var sf: SpriteFrames = EnemyScript.call("_shared_frames", eid)
		var ok := sf.has_animation("move") and sf.get_frame_count("move") == 2
		_check("move frames " + eid, ok,
			"n=%d" % sf.get_frame_count("move") if sf.has_animation("move") else "no move anim")
	# 行为切换：假玩家 + 真追击
	var fake := Node2D.new()
	fake.add_to_group("player")
	fake.global_position = Vector2(400, 300)
	root.add_child(fake)
	var EnemyScene := load("res://scenes/enemy.tscn") as PackedScene
	var e: Node2D = EnemyScene.instantiate()
	e.set("enemy_id", "slime")
	e.global_position = Vector2(100, 300)
	root.add_child(e)
	await _wait(0.5)
	var sprite: AnimatedSprite2D = e.get_node("AnimatedSprite2D")
	# 敌人在追击假玩家（距离 300），应播 move
	for i in range(12):
		await physics_frame
	_check("move while chasing", sprite.animation == "move", sprite.animation)
	# 眩晕 -> 原地不动 -> idle
	e.set("stun_t", 2.0)
	for i in range(12):
		await physics_frame
	_check("idle when stopped", sprite.animation == "idle", sprite.animation)
	print("ENEMY ANIM RESULT: ", "PASS" if fails == 0 else "FAIL")
	quit(0 if fails == 0 else 1)
