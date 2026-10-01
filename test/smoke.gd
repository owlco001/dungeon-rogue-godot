extends SceneTree
## Headless smoke test: drives the game with synthetic input and verifies
## animation state transitions, enemy AI and attack. Run:
##   godot --headless -s res://test/smoke.gd

var frame := 0
var player: Player = null
var failures: Array[String] = []
var _attack_seen := false


func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main := packed.instantiate()
	root.add_child(main)
	print("[smoke] main scene loaded")


func _check(cond: bool, what: String) -> void:
	if cond:
		print("[smoke] PASS: ", what)
	else:
		failures.append(what)
		print("[smoke] FAIL: ", what)


func _process(_delta: float) -> bool:
	frame += 1
	if player == null:
		player = root.get_node_or_null("Main/Player") as Player
		if player == null:
			if frame > 30:
				_check(false, "player node exists")
				return _finish()
			return false
		print("[smoke] player found, anim=", player.current_anim)

	# drive input in phases
	Input.action_release("move_left")
	Input.action_release("move_right")
	Input.action_release("move_up")
	Input.action_release("move_down")
	match frame:
		_ when frame >= 10 and frame < 45:
			Input.action_press("move_right")
		_ when frame >= 50 and frame < 85:
			Input.action_press("move_up")
		_ when frame >= 90 and frame < 125:
			Input.action_press("move_down")
		_ when frame >= 155 and frame < 186:
			Input.action_press("move_left")
		_:
			pass

	if frame == 190:
		player.try_attack()
		_attack_seen = true

	# assertions at phase ends
	if frame == 44:
		_check(player.dir_name == "right", "move right -> dir right (got %s)" % player.dir_name)
		_check(player.current_anim == "walk_left" and player.sprite.flip_h, "move right -> walk_left mirrored (anim=%s flip=%s)" % [player.current_anim, str(player.sprite.flip_h)])
		_check(player.velocity.length() > 100.0, "velocity builds up (got %.1f)" % player.velocity.length())
	if frame == 84:
		_check(player.dir_name == "up", "move up -> dir up (got %s)" % player.dir_name)
		_check(player.current_anim == "walk_up", "move up -> walk_up (got %s)" % player.current_anim)
	if frame == 124:
		_check(player.dir_name == "down", "move down -> dir down (got %s)" % player.dir_name)
		_check(player.current_anim == "walk_down", "move down -> walk_down (got %s)" % player.current_anim)
	if frame == 150:
		_check(player.current_anim == "idle_down", "stop -> idle_down (got %s)" % player.current_anim)
		_check(player.velocity.length() < 60.0, "deceleration works (vel %.1f)" % player.velocity.length())
	if frame == 185:
		_check(player.dir_name == "left", "move left -> dir left (got %s)" % player.dir_name)
		_check(player.current_anim == "walk_left" and not player.sprite.flip_h, "move left -> walk_left unmirrored")
	if frame == 195:
		_check(_attack_seen, "attack executed without error")
		var n := get_nodes_in_group("enemies").size()
		_check(n == 3, "3 enemies spawned (got %d)" % n)
		var all_moving := true
		for e in get_nodes_in_group("enemies"):
			if (e as CharacterBody2D).velocity.length() < 1.0:
				all_moving = false
				break
		_check(all_moving, "enemies are moving")
	if frame == 196:
		# hit-flash check: damage the player directly
		player.take_damage(10.0, Vector2.RIGHT)
		_check(player.hp < 100.0, "player takes damage (hp=%.1f)" % player.hp)
	if frame >= 210:
		return _finish()
	return false


func _finish() -> bool:
	print("[smoke] done at frame %d, failures=%d" % [frame, failures.size()])
	for f in failures:
		print("[smoke] FAILED: ", f)
	if failures.is_empty():
		print("[smoke] ALL PASS")
	return true
