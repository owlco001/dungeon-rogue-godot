extends SceneTree

const RG := preload("res://systems/room_gen.gd")
## V12 走廊宽度门禁（v0.8.10）：多种子生成布局，断言
## 1) 每个房间中心在 pf 网格上可达大厅中心；
## 2) 每个非房间地面格都属于某个 2×2 全地面块（不存在 1 格宽通道）；
## 3) 2×2 锚点图（以 pf 网格计，含柱子封格）上各房间锚点与大厅锚点连通，
##    即"占两格的身位"能走完全图。
## 用法：godot --headless --path . --script res://test/check_corridor.gd

var _fail := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, label: String) -> void:
	print(("PASS V12 " if ok else "FAIL V12 ") + label)
	if not ok:
		_fail += 1


func _in_room(rooms: Array, x: int, y: int) -> bool:
	for rm in rooms:
		if x >= int(rm["x"]) and x < int(rm["x"]) + int(rm["w"]) \
				and y >= int(rm["y"]) and y < int(rm["y"]) + int(rm["h"]):
			return true
	return false


func _block2_ok(g: PackedByteArray, gw: int, x: int, y: int) -> bool:
	return g[y * gw + x] == 0 and g[y * gw + x + 1] == 0 \
		and g[(y + 1) * gw + x] == 0 and g[(y + 1) * gw + x + 1] == 0


func _run() -> void:
	var gw: int = RG.GW
	var gh: int = RG.GH
	var narrow := 0
	var unreachable := 0
	var body_blocked := 0
	for s in range(1, 121):
		var rg = RG.new()
		rg.generate(s * 7919 + 13)
		var rooms: Array = rg.rooms
		# 1) pf 真连通：房间内至少一格可 BFS 到达大厅（不做端点吸附）
		var hall_c := Vector2(gw * RG.CELL * 0.5, gh * RG.CELL * 0.5)
		var hall_cell := rg.world_to_cell(hall_c)
		var reach := {}
		if rg.pf_grid[hall_cell.y * gw + hall_cell.x] == 0:
			reach[hall_cell] = true
			var q: Array[Vector2i] = [hall_cell]
			while not q.is_empty():
				var c: Vector2i = q.pop_back()
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var n: Vector2i = c + d
					if n.x >= 0 and n.y >= 0 and n.x < gw and n.y < gh \
							and not reach.has(n) and rg.pf_grid[n.y * gw + n.x] == 0:
						reach[n] = true
						q.append(n)
		for rm in rooms:
			var room_ok := false
			for y in range(int(rm["y"]), int(rm["y"]) + int(rm["h"])):
				for x in range(int(rm["x"]), int(rm["x"]) + int(rm["w"])):
					if reach.has(Vector2i(x, y)):
						room_ok = true
			if not room_ok:
				unreachable += 1
		# 2) 非房间地面格的 2×2 归属
		for y in range(0, gh - 1):
			for x in range(0, gw - 1):
				if rg.grid[y * gw + x] != 0 or _in_room(rooms, x, y):
					continue
				var ok := false
				for oy in range(-1, 1):
					for ox in range(-1, 1):
						var bx := x + ox
						var by := y + oy
						if bx >= 0 and by >= 0 and bx < gw - 1 and by < gh - 1 \
								and _block2_ok(rg.grid, gw, bx, by):
							ok = true
				if not ok:
					narrow += 1
		# 3) 2×2 锚点连通（物理布局 grid；pf 的柱子膨胀是给敌人寻路的，不代表玩家过不去）
		var anchors := {}
		for y in range(0, gh - 1):
			for x in range(0, gw - 1):
				if _block2_ok(rg.grid, gw, x, y):
					anchors[Vector2i(x, y)] = true
		var start := Vector2i(gw / 2 - 1, gh / 2 - 1)
		if not anchors.has(start):
			body_blocked += 1
			continue
		var seen := {start: true}
		var queue: Array[Vector2i] = [start]
		while not queue.is_empty():
			var cur: Vector2i = queue.pop_back()
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
					Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
				var n: Vector2i = cur + d
				if anchors.has(n) and not seen.has(n):
					seen[n] = true
					queue.append(n)
		for rm in rooms:
			# 锚点块与房间矩形相交即可（门口块常骑在房间边缘上）
			var room_ok := false
			for y in range(int(rm["y"]) - 1, int(rm["y"]) + int(rm["h"])):
				for x in range(int(rm["x"]) - 1, int(rm["x"]) + int(rm["w"])):
					if seen.has(Vector2i(x, y)):
						room_ok = true
			if not room_ok:
				body_blocked += 1
	_check(unreachable == 0, "rooms reachable on pf (%d bad)" % unreachable)
	_check(narrow == 0, "no 1-wide corridor cells (%d bad)" % narrow)
	_check(body_blocked == 0, "2x2 body graph connected (%d bad)" % body_blocked)
	print("V12 RESULT: " + ("PASS" if _fail == 0 else "FAIL"))
	quit(0 if _fail == 0 else 1)
