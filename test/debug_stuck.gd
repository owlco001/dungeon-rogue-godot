extends SceneTree
## DEBUG: 复现 V10 卡墙场景并打印每只怪的内部状态
const RG2 := preload("res://systems/room_gen.gd")


func _initialize() -> void:
	_run.call_deferred()


func _wait(s: float) -> void:
	var t0 := Time.get_ticks_msec()
	while float(Time.get_ticks_msec() - t0) / 1000.0 < s:
		await process_frame


func _find_btn(n: Node, texts: Array) -> Button:
	if n is Button:
		for t in texts:
			if String(t) in String((n as Button).text):
				return n as Button
	for c in n.get_children():
		var r := _find_btn(c, texts)
		if r != null:
			return r
	return null


func _run() -> void:
	var inst: Node = load("res://scenes/lobby.tscn").instantiate()
	root.add_child(inst)
	await _wait(1.0)
	_find_btn(inst, ["出战", "Battle"]).pressed.emit()
	await _wait(0.5)
	_find_btn(inst, ["开始战斗", "Start"]).pressed.emit()
	var main: Node = null
	for i in range(50):
		await _wait(0.1)
		main = get_first_node_in_group("game")
		if main != null:
			break
	await _wait(0.5)
	for i in range(8):
		main.call("_spawn_enemy", "slime", 1.0, 1.0, false)
	await _wait(0.3)
	var snap := {}
	for e in get_nodes_in_group("enemies"):
		snap[e.get_instance_id()] = e.global_position
	await _wait(4.0)
	var player: Node = null
	for e in get_nodes_in_group("enemies"):
		var t = e.get("target")
		if t != null:
			player = t
			break
	print("player=", player.global_position if player != null else "null")
	# 物理探针：冻结怪位置处有什么碰撞体
	var pq := PhysicsPointQueryParameters2D.new()
	pq.position = Vector2(1159.711, 414.1913)
	pq.collision_mask = 4
	var hits := root.get_world_2d().direct_space_state.intersect_point(pq, 8)
	print("point_hits=", hits.size())
	# 形状探针：以敌人半径 22 在冻结位置做圆查询（验证是否与柱子重叠）
	var sq := PhysicsShapeQueryParameters2D.new()
	var circ := CircleShape2D.new()
	circ.radius = 22.0
	sq.shape = circ
	sq.transform = Transform2D(0.0, Vector2(1159.711, 414.1913))
	sq.collision_mask = 4
	var shits := root.get_world_2d().direct_space_state.intersect_shape(sq, 8)
	print("shape_hits=", shits.size())
	for h in shits:
		print("  shape hit collider=", h["collider"])
	for h in hits:
		print("  hit collider=", h["collider"], " shape=", h["shape"]) 
	for e in get_nodes_in_group("enemies"):
		if not snap.has(e.get_instance_id()):
			continue
		var moved: float = e.global_position.distance_to(snap[e.get_instance_id()])
		var dpl: float = e.global_position.distance_to(player.global_position) if player != null else -1.0
		if moved < 40.0:
			var pp: PackedVector2Array = e.get("_path")
			print("  STUCKDBG id=", e.get_instance_id(), " pos=", e.global_position,
				" dir_smooth=", e.get("_dir_smooth"),
				" path0=", pp[0] if pp.size() > 0 else Vector2.ZERO,
				" path1=", pp[1] if pp.size() > 1 else Vector2.ZERO,
				" path2=", pp[2] if pp.size() > 2 else Vector2.ZERO,
				" path_i=", e.get("_path_i"),
				" spd=", e.get("speed"), " wobble=", e.get("_wobble"))
		print("e=", e.get_instance_id(), " moved=", r2i(moved),
			" pos=", e.global_position,
			" kind=", e.get("kind"), " dead=", e.get("dead"), " stun=", e.get("stun_t"),
			" path_i=", e.get("_path_i"), " path_n=", (e.get("_path") as PackedVector2Array).size(),
			" los=", e.get("_los_clear"), " vel=", (e as CharacterBody2D).velocity.length())
	quit(0)


func r2i(v: float) -> int:
	return int(round(v))
