class_name RoomGen
extends RefCounted
## v0.8 L4 程序化房间（01 §6.2）：格子房间-走廊图，确定性 seed（同 seed 同布局）。
## 网格 32×24（CELL=50px = 1600×1200，贴合 ARENA_W/H）；1=墙 0=地面。

const CELL := 50.0
const GW := 32
const GH := 24

var grid := PackedByteArray()
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
		if grid[cy * GW + cx] == 0:
			var p := cell_center(cx, cy)
			if p.distance_to(player_pos) > min_dist_px:
				return p
	# 兜底：任一地面格
	for y in range(GH):
		for x in range(GW):
			if grid[y * GW + x] == 0:
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
	var x0 := mini(ax, bx)
	var x1 := maxi(ax, bx)
	var y0 := mini(ay, by)
	var y1 := maxi(ay, by)
	if rng.randf() < 0.5:
		_carve_h(ax, bx, ay)
		_carve_v(ay, by, bx)
	else:
		_carve_v(ay, by, ax)
		_carve_h(ax, bx, by)
	# 走廊宽 2 格
	_carve_h(x0, x1, clampi(ay + 1, 0, GH - 1))
	_carve_v(y0, y1, clampi(bx + 1, 0, GW - 1))


func _carve_h(x0: int, x1: int, y: int) -> void:
	for x in range(mini(x0, x1), maxi(x0, x1) + 1):
		if x >= 0 and y >= 0 and x < GW and y < GH:
			grid[y * GW + x] = 0


func _carve_v(y0: int, y1: int, x: int) -> void:
	for y in range(mini(y0, y1), maxi(y0, y1) + 1):
		if x >= 0 and y >= 0 and x < GW and y < GH:
			grid[y * GW + x] = 0
