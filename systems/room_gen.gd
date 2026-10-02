class_name RoomGen
extends RefCounted
## v0.8 L4 程序化房间（01 §6.2）：格子房间-走廊图，确定性 seed（同 seed 同布局）。
## 网格 32×24（CELL=50px = 1600×1200，贴合 ARENA_W/H）；1=墙 0=地面。

const CELL := 50.0
const GW := 32
const GH := 24

var grid := PackedByteArray()
var pf_grid := PackedByteArray()  # 寻路专用：布局网格 + 柱子占位（柱子不在布局里）
const PILLARS := [Vector2(480, 380), Vector2(1120, 380), Vector2(480, 820), Vector2(1120, 820)]
const PF := preload("res://systems/pathfind.gd")
var rooms: Array = []  # [{x,y,w,h}] 格子矩形
var rng := RandomNumberGenerator.new()


func generate(p_seed: int) -> void:
	rng.seed = p_seed
	grid.resize(GW * GH)
	grid.fill(1)
	rooms.clear()
	# 出生大厅：中央 6×5 固定先挖（保证玩家出生点是地面）
	var hall := {"x": GW / 2 - 3, "y": GH / 2 - 2, "w": 6, "h": 5}
	rooms.append(hall)
	_carve_rect(hall)
	# 5–8 个随机房间
	var target := 5 + rng.randi_range(0, 3)
	var tries := 0
	while rooms.size() < target and tries < 80:
		tries += 1
		var r := {
			"x": rng.randi_range(1, GW - 9),
			"y": rng.randi_range(1, GH - 7),
			"w": rng.randi_range(4, 8),
			"h": rng.randi_range(3, 6),
		}
		var overlap := false
		for o in rooms:
			if _rects_overlap(r, o, 1):
				overlap = true
				break
		if overlap:
			continue
		rooms.append(r)
		_carve_rect(r)
	if rooms.size() < 2:
		generate(p_seed + 1)
		return
	# 按 x 排序依次 L 形走廊连通（保证全连通）
	rooms.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["x"]) < int(b["x"]))
	for i in range(1, rooms.size()):
		_carve_corridor(rooms[i - 1], rooms[i])
	# 柱子广场：每根柱子周围 3×3 挖空成小广场（柱径 84 + 身宽 44 = 128 < 150 可绕行）
	for p in PILLARS:
		var pc := world_to_cell(p)
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var cx := pc.x + dx
				var cy := pc.y + dy
				if cx > 0 and cy > 0 and cx < GW - 1 and cy < GH - 1:
					grid[cy * GW + cx] = 0
	_rebuild_pf()
	# 连通性修复 v3（v0.8.10）：用 BFS 真连通判定。旧版用 find_path 判连通，但它会把
	# 端点吸附到 4 格内的最近地面，隔墙也会误报连通，于是整间房被口袋修剪误杀
	# （玩家能走进去、怪却寻不到路）。仍不通的房间沿布局路径 3×3 加宽后重建 pf，
	# 两轮后仍不通则换 seed 重生成，保证每间房都真连通。
	var hall_c := Vector2(GW * CELL * 0.5, GH * CELL * 0.5)
	for round_i in range(2):
		var reach := _pf_reachable(hall_c)
		var all_ok := true
		for rm in rooms:
			if _room_reached(rm, reach):
				continue
			all_ok = false
			var rc := Vector2((float(rm["x"]) + float(rm["w"]) * 0.5) * CELL,
				(float(rm["y"]) + float(rm["h"]) * 0.5) * CELL)
			var lp: PackedVector2Array = PF.find_path(grid, GW, GH, rc, hall_c, CELL)
			for wp in lp:
				var cc := world_to_cell(wp)
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						var nx := cc.x + dx
						var ny := cc.y + dy
						if nx > 0 and ny > 0 and nx < GW - 1 and ny < GH - 1:
							grid[ny * GW + nx] = 0
			_rebuild_pf()
		if all_ok:
			break
	var reach2 := _pf_reachable(hall_c)
	for rm in rooms:
		if not _room_reached(rm, reach2):
			generate(p_seed + 997)
			return
	# 口袋修剪：pf 上未连通大厅的地面格一律标墙（不可达区域不进刷怪/寻路池）
	for y in range(GH):
		for x in range(GW):
			if pf_grid[y * GW + x] == 0 and not reach2.has(Vector2i(x, y)):
				pf_grid[y * GW + x] = 1


## pf 网格上从大厅出发的 BFS 真连通集（不做端点吸附）
func _pf_reachable(hall_c: Vector2) -> Dictionary:
	var seen := {}
	var start := world_to_cell(hall_c)
	if pf_grid[start.y * GW + start.x] != 0:
		return seen
	seen[start] = true
	var queue: Array = [start]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		for dd in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nb: Vector2i = c + dd
			if nb.x < 0 or nb.y < 0 or nb.x >= GW or nb.y >= GH:
				continue
			if not seen.has(nb) and pf_grid[nb.y * GW + nb.x] == 0:
				seen[nb] = true
				queue.append(nb)
	return seen


## 房间矩形内至少有一格在连通集里（房心压柱子不算不通）
func _room_reached(rm: Dictionary, reach: Dictionary) -> bool:
	for y in range(int(rm["y"]), int(rm["y"]) + int(rm["h"])):
		for x in range(int(rm["x"]), int(rm["x"]) + int(rm["w"])):
			if reach.has(Vector2i(x, y)):
				return true
	return false


## 寻路网格重建：布局网格 + 柱心 63px（柱 r42 + 身 r22）内格心标墙
func _rebuild_pf() -> void:
	pf_grid = grid.duplicate()
	for p in PILLARS:
		for y in range(GH):
			for x in range(GW):
				if cell_center(x, y).distance_to(p) < 63.0:
					pf_grid[y * GW + x] = 1


func is_wall(cx: int, cy: int) -> bool:
	if cx < 0 or cy < 0 or cx >= GW or cy >= GH:
		return true
	return grid[cy * GW + cx] == 1


func cell_center(cx: int, cy: int) -> Vector2:
	return Vector2((float(cx) + 0.5) * CELL, (float(cy) + 0.5) * CELL)


func world_to_cell(p: Vector2) -> Vector2i:
	return Vector2i(clampi(int(p.x / CELL), 0, GW - 1), clampi(int(p.y / CELL), 0, GH - 1))


## 距玩家 >min_dist_px 的随机地面格（刷怪/宝箱用）
func random_floor_cell_far(player_pos: Vector2, min_dist_px: float) -> Vector2:
	for i in range(60):
		var cx := rng.randi_range(1, GW - 2)
		var cy := rng.randi_range(1, GH - 2)
		if pf_grid[cy * GW + cx] == 0:
			var p := cell_center(cx, cy)
			if p.distance_to(player_pos) > min_dist_px:
				return p
	# 兜底：任一地面格
	for y in range(GH):
		for x in range(GW):
			if pf_grid[y * GW + x] == 0:
				return cell_center(x, y)
	return Vector2(GW * CELL * 0.5, GH * CELL * 0.5)


## 距 from 最远的房间中心（楼梯用）；second=true 取次远（宝箱用）
func farthest_room_center(from_pos: Vector2, second: bool = false) -> Vector2:
	var best := Vector2.ZERO
	var best_d := -1.0
	var second_best := Vector2.ZERO
	var second_d := -1.0
	for r in rooms:
		var c := Vector2((float(r["x"]) + float(r["w"]) * 0.5) * CELL,
			(float(r["y"]) + float(r["h"]) * 0.5) * CELL)
		var d := c.distance_to(from_pos)
		if d > best_d:
			second_best = best
			second_d = best_d
			best = c
			best_d = d
		elif d > second_d:
			second_best = c
			second_d = d
	return second_best if second and second_d >= 0.0 else best


## 墙体矩形合并（行游程 + 纵向贪心合并），供 arena 建碰撞/视觉
func merged_wall_rects() -> Array:
	var runs: Array = []  # 每行：[{x0, x1}]
	for y in range(GH):
		var row: Array = []
		var x := 0
		while x < GW:
			if grid[y * GW + x] == 1:
				var x0 := x
				while x < GW and grid[y * GW + x] == 1:
					x += 1
				row.append({"x0": x0, "x1": x - 1})
			else:
				x += 1
		runs.append(row)
	var consumed := {}  # "y:i" -> true
	var rects: Array = []
	for y in range(GH):
		var row: Array = runs[y]
		for i in range(row.size()):
			if consumed.has("%d:%d" % [y, i]):
				continue
			var r: Dictionary = row[i]
			var h := 1
			while y + h < GH:
				var below: Array = runs[y + h]
				var found := -1
				for j in range(below.size()):
					if not consumed.has("%d:%d" % [y + h, j]) \
							and int(below[j]["x0"]) == int(r["x0"]) \
							and int(below[j]["x1"]) == int(r["x1"]):
						found = j
						break
				if found < 0:
					break
				consumed["%d:%d" % [y + h, found]] = true
				h += 1
			consumed["%d:%d" % [y, i]] = true
			rects.append({
				"pos": Vector2((float(r["x0"]) + float(r["x1"]) + 1.0) * 0.5 * CELL,
					(float(y) + float(y + h)) * 0.5 * CELL),
				"size": Vector2(float(int(r["x1"]) - int(r["x0"]) + 1) * CELL, float(h) * CELL),
			})
	return rects


func _rects_overlap(a: Dictionary, b: Dictionary, pad: int) -> bool:
	return int(a["x"]) < int(b["x"]) + int(b["w"]) + pad \
		and int(a["x"]) + int(a["w"]) + pad > int(b["x"]) \
		and int(a["y"]) < int(b["y"]) + int(b["h"]) + pad \
		and int(a["y"]) + int(a["h"]) + pad > int(b["y"])


func _carve_rect(r: Dictionary) -> void:
	for y in range(int(r["y"]), int(r["y"]) + int(r["h"])):
		for x in range(int(r["x"]), int(r["x"]) + int(r["w"])):
			if x >= 0 and y >= 0 and x < GW and y < GH:
				grid[y * GW + x] = 0


func _carve_corridor(a: Dictionary, b: Dictionary) -> void:
	var ax := int(a["x"]) + int(a["w"]) / 2
	var ay := int(a["y"]) + int(a["h"]) / 2
	var bx := int(b["x"]) + int(b["w"]) / 2
	var by := int(b["y"]) + int(b["h"]) / 2
	# v0.8.10：L 形路径逐格用 2×2 笔刷雕刻——旧写法只给随机一半的线段补平行线，
	# 另一半线段和拐角仍是 1 格宽（50px），真机上路口过不去。
	var pts: Array[Vector2i] = []
	if rng.randf() < 0.5:
		_path_h(pts, ax, bx, ay)
		_path_v(pts, ay, by, bx)
	else:
		_path_v(pts, ay, by, ax)
		_path_h(pts, ax, bx, by)
	for p in pts:
		_carve_block2(p.x, p.y)


func _path_h(pts: Array[Vector2i], x0: int, x1: int, y: int) -> void:
	var step := 1 if x1 >= x0 else -1
	var x := x0
	while true:
		pts.append(Vector2i(x, y))
		if x == x1:
			break
		x += step


func _path_v(pts: Array[Vector2i], y0: int, y1: int, x: int) -> void:
	var step := 1 if y1 >= y0 else -1
	var y := y0
	while true:
		pts.append(Vector2i(x, y))
		if y == y1:
			break
		y += step


func _carve_block2(cx: int, cy: int) -> void:
	for dy in range(0, 2):
		for dx in range(0, 2):
			var x := clampi(cx + dx, 1, GW - 2)
			var y := clampi(cy + dy, 1, GH - 2)
			grid[y * GW + x] = 0
