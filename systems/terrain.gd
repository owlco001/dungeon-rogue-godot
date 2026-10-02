class_name TerrainGen
extends RefCounted
## v0.8.5 地形系统：按主题在可达地面上生成确定性地形块。
## 只产出数据（格子簇 + 效果参数），视觉由 scripts/terrain_layer.gd 绘制，
## 效果结算由 main.gd 驱动。本文件保持 autoload-free（无头编译图约束）。

const CELL := 50.0
const GW := 32
const GH := 24
const PILLARS := [Vector2(480, 380), Vector2(1120, 380), Vector2(480, 820), Vector2(1120, 820)]

const PROFILES := {
	"corridor": {
		"id": "rubble", "name": "碎石地",
		"hint": "碎石地：你略慢，敌人慢得多",
		"player_speed": 0.90, "enemy_speed": 0.75,
		"player_accel": 0.85, "player_friction": 1.0,
		"player_dps": 0.0, "enemy_dps": 0.0,
		"player_dps_per_floor": 0.0, "enemy_dps_per_floor": 0.0,
	},
	"forge": {
		"id": "lava", "name": "熔岩池",
		"hint": "熔岩池：持续烫伤，敌人伤得更重",
		"player_speed": 1.0, "enemy_speed": 1.0,
		"player_accel": 1.0, "player_friction": 1.0,
		"player_dps": 6.0, "enemy_dps": 12.0,
		"player_dps_per_floor": 0.25, "enemy_dps_per_floor": 0.5,
	},
	"ice": {
		"id": "ice", "name": "薄冰面",
		"hint": "薄冰面：速度略升，但很难刹住",
		"player_speed": 1.06, "enemy_speed": 0.90,
		"player_accel": 0.32, "player_friction": 0.16,
		"player_dps": 0.0, "enemy_dps": 0.0,
		"player_dps_per_floor": 0.0, "enemy_dps_per_floor": 0.0,
	},
	"tomb": {
		"id": "mire", "name": "腐殖泥沼",
		"hint": "腐殖泥沼：深陷减速，敌人陷得更深",
		"player_speed": 0.74, "enemy_speed": 0.62,
		"player_accel": 0.80, "player_friction": 1.15,
		"player_dps": 0.0, "enemy_dps": 0.0,
		"player_dps_per_floor": 0.0, "enemy_dps_per_floor": 0.0,
	},
	"thorn": {
		"id": "bramble", "name": "荆棘地",
		"hint": "荆棘地：减速并持续扎伤",
		"player_speed": 0.80, "enemy_speed": 0.68,
		"player_accel": 0.90, "player_friction": 1.0,
		"player_dps": 3.5, "enemy_dps": 7.0,
		"player_dps_per_floor": 0.12, "enemy_dps_per_floor": 0.25,
	},
	"void": {
		"id": "rift", "name": "虚空裂隙",
		"hint": "虚空裂隙：侵蚀生命，步伐不稳",
		"player_speed": 0.92, "enemy_speed": 0.82,
		"player_accel": 0.68, "player_friction": 0.55,
		"player_dps": 4.5, "enemy_dps": 9.0,
		"player_dps_per_floor": 0.18, "enemy_dps_per_floor": 0.35,
	},
}


static func profile_for(theme: String) -> Dictionary:
	return (PROFILES.get(theme, PROFILES["corridor"]) as Dictionary).duplicate(true)


static func cell_key(c: Vector2i) -> String:
	return "%d:%d" % [c.x, c.y]


static func cell_center(c: Vector2i) -> Vector2:
	return Vector2((float(c.x) + 0.5) * CELL, (float(c.y) + 0.5) * CELL)


## 生成地形块：walkable 为 pf 风格网格（0=地面 1=墙）；reserved 为必须留空的世界坐标。
static func generate(theme: String, floor_num: int, walkable: PackedByteArray,
		reserved: Array, patch_count: int = 6) -> Array:
	var grid := walkable
	if grid.size() != GW * GH:
		grid = PackedByteArray()
		grid.resize(GW * GH)
		grid.fill(0)
	var prof := profile_for(theme)
	prof["player_dps"] = float(prof["player_dps"]) \
		+ float(prof["player_dps_per_floor"]) * float(maxi(floor_num - 1, 0))
	prof["enemy_dps"] = float(prof["enemy_dps"]) \
		+ float(prof["enemy_dps_per_floor"]) * float(maxi(floor_num - 1, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = absi(hash(theme + ":" + str(floor_num) + ":terrain"))
	var occupied := {}
	var patches: Array = []
	var attempts := 0
	while patches.size() < patch_count and attempts < 240:
		attempts += 1
		var anchor := Vector2i(rng.randi_range(1, GW - 2), rng.randi_range(1, GH - 2))
		if not _cell_ok(anchor, grid, reserved, occupied, true):
			continue
		var target := rng.randi_range(4, 7)
		var cells: Array = [anchor]
		var in_patch := {cell_key(anchor): true}
		var guard := 0
		while cells.size() < target and guard < 40:
			guard += 1
			var base: Vector2i = cells[rng.randi_range(0, cells.size() - 1)]
			var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
			var dir: Vector2i = dirs[rng.randi_range(0, 3)]
			var cand: Vector2i = base + dir
			if in_patch.has(cell_key(cand)):
				continue
			if not _cell_ok(cand, grid, reserved, occupied, false):
				continue
			cells.append(cand)
			in_patch[cell_key(cand)] = true
		if cells.size() < 3:
			continue
		for c in cells:
			occupied[cell_key(c)] = true
		var center := Vector2.ZERO
		for c in cells:
			center += cell_center(c)
		center /= float(cells.size())
		var patch := prof.duplicate(true)
		patch["theme"] = theme
		patch["cells"] = cells
		patch["cell_map"] = in_patch
		patch["center"] = center
		patches.append(patch)
	return patches


static func _cell_ok(c: Vector2i, grid: PackedByteArray, reserved: Array,
		occupied: Dictionary, is_anchor: bool) -> bool:
	if c.x < 1 or c.y < 1 or c.x >= GW - 1 or c.y >= GH - 1:
		return false
	if grid[c.y * GW + c.x] != 0:
		return false
	if occupied.has(cell_key(c)):
		return false
	var p := cell_center(c)
	for r in reserved:
		if p.distance_to(r as Vector2) < 135.0:
			return false
	for pillar in PILLARS:
		if p.distance_to(pillar) < 112.0:
			return false
	if is_anchor:
		# 地形块之间至少隔一格，避免整片连成一坨
		for other in occupied.keys():
			var parts := String(other).split(":")
			var oc := Vector2i(int(parts[0]), int(parts[1]))
			if absi(oc.x - c.x) + absi(oc.y - c.y) < 2:
				return false
	return true


## 位置查询：返回所在格的地形块（无地形则空字典）
static func patch_at(patches: Array, pos: Vector2) -> Dictionary:
	var c := Vector2i(clampi(int(pos.x / CELL), 0, GW - 1), clampi(int(pos.y / CELL), 0, GH - 1))
	var k := cell_key(c)
	for patch in patches:
		if (patch["cell_map"] as Dictionary).has(k):
			return patch
	return {}
