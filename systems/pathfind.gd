class_name Pathfind
extends RefCounted
## v0.8 L4 轻量 A*（01 §6.2）：4 向、网格 ≤768 格，单次 <0.05ms 量级。
## 输入 grid 为 PackedByteArray（1=墙），返回世界坐标路径点（含起点）。

const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]


static func find_path(grid: PackedByteArray, gw: int, gh: int,
		from_w: Vector2, to_w: Vector2, cell: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if grid.is_empty():
		return out
	var start := _to_cell(from_w, gw, gh, cell)
	var goal := _to_cell(to_w, gw, gh, cell)
	start = _nearest_floor(grid, gw, gh, start)
	goal = _nearest_floor(grid, gw, gh, goal)
	if start.x < 0 or goal.x < 0:
		return out
	if start == goal:
		out.append(_cell_center(start, cell))
		out.append(_cell_center(goal, cell))
		return out
	var open: Array = [start]
	var g := {start: 0.0}
	var came := {}
	var closed := {}
	while not open.is_empty():
		# 取 f 最小（线性扫描；768 格足够）
		var bi := 0
		var bf := _f(open[0], goal, g)
		for i in range(1, open.size()):
			var f := _f(open[i], goal, g)
			if f < bf:
				bf = f
				bi = i
		var cur: Vector2i = open[bi]
		open.remove_at(bi)
		if cur == goal:
			return _reconstruct(came, cur, cell)
		closed[cur] = true
		for d in DIRS:
			var nb: Vector2i = cur + d
			if nb.x < 0 or nb.y < 0 or nb.x >= gw or nb.y >= gh:
				continue
			if grid[nb.y * gw + nb.x] == 1 or closed.has(nb):
				continue
			var ng := float(g[cur]) + 1.0
			if not g.has(nb) or ng < float(g[nb]):
				g[nb] = ng
				came[nb] = cur
				if not open.has(nb):
					open.append(nb)
	return out


static func _f(c: Vector2i, goal: Vector2i, g: Dictionary) -> float:
	return float(g[c]) + float(absi(c.x - goal.x) + absi(c.y - goal.y))


static func _reconstruct(came: Dictionary, cur: Vector2i, cell: float) -> PackedVector2Array:
	var cells: Array = [cur]
	while came.has(cur):
		cur = came[cur]
		cells.push_front(cur)
	var out := PackedVector2Array()
	for c in cells:
		out.append(_cell_center(c, cell))
	return out


static func _to_cell(p: Vector2, gw: int, gh: int, cell: float) -> Vector2i:
	return Vector2i(clampi(int(p.x / cell), 0, gw - 1), clampi(int(p.y / cell), 0, gh - 1))


static func _cell_center(c: Vector2i, cell: float) -> Vector2:
	return Vector2((float(c.x) + 0.5) * cell, (float(c.y) + 0.5) * cell)


static func _nearest_floor(grid: PackedByteArray, gw: int, gh: int, c: Vector2i) -> Vector2i:
	if grid[c.y * gw + c.x] == 0:
		return c
	for r in range(1, 5):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var nb := c + Vector2i(dx, dy)
				if nb.x >= 0 and nb.y >= 0 and nb.x < gw and nb.y < gh \
						and grid[nb.y * gw + nb.x] == 0:
					return nb
	return Vector2i(-1, -1)
