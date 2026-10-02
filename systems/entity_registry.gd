extends Node
## v0.8 EntityRegistry（07 §2.3）：存活敌人定长数组 + 每物理帧重建空间网格，
## 替代热路径上的全量组扫描。feature flag dungeon/use_registry 关闭时内部回退组查询，
## 调用点无需分支。注册源：enemy.gd / boss.gd 的 _ready 与 _die（tree_exited 兜底注销）。

const CELL := 128.0  # 1600×1200 → 13×10 格

var enemies: Array = []  # 存活敌人（含 Boss）
var taunts: Array = []  # 嘲讽召唤物（≤32，替代 taunt_summons 组扫描）
var _grid := {}  # Vector2i -> Array[Node2D]


static func use_registry() -> bool:
	return bool(ProjectSettings.get_setting("dungeon/use_registry", true))


func register_enemy(e: Node2D) -> void:
	if e in enemies:
		return
	enemies.append(e)
	if not e.tree_exited.is_connected(_on_enemy_exited):
		e.tree_exited.connect(_on_enemy_exited.bind(e))


func unregister_enemy(e: Node2D) -> void:
	var i := enemies.find(e)
	if i >= 0:
		enemies[i] = enemies[enemies.size() - 1]
		enemies.remove_at(enemies.size() - 1)


func _on_enemy_exited(e: Node2D) -> void:
	unregister_enemy(e)


func register_taunt(s: Node2D) -> void:
	if s in taunts:
		return
	taunts.append(s)
	if not s.tree_exited.is_connected(_on_taunt_exited):
		s.tree_exited.connect(_on_taunt_exited.bind(s))


func unregister_taunt(s: Node2D) -> void:
	var i := taunts.find(s)
	if i >= 0:
		taunts[i] = taunts[taunts.size() - 1]
		taunts.remove_at(taunts.size() - 1)


func _on_taunt_exited(s: Node2D) -> void:
	unregister_taunt(s)


func alive_count() -> int:
	if not use_registry():
		return get_tree().get_nodes_in_group("enemies").size()
	return enemies.size()


## 每物理帧由 main.gd 首行调用：按当前位置重建空间网格
func begin_frame() -> void:
	if not use_registry():
		return
	_grid.clear()
	for e in enemies:
		if not is_instance_valid(e) or bool(e.get("dead")):
			continue
		var key := Vector2i(int(e.global_position.x / CELL), int(e.global_position.y / CELL))
		if not _grid.has(key):
			_grid[key] = []
		_grid[key].append(e)


## 圆内候选（格粒度的超集，调用方自行做精确距离判定）
func query_circle(pos: Vector2, radius: float) -> Array:
	if not use_registry():
		return get_tree().get_nodes_in_group("enemies")
	var out: Array = []
	var lo := Vector2i(int((pos.x - radius) / CELL), int((pos.y - radius) / CELL))
	var hi := Vector2i(int((pos.x + radius) / CELL), int((pos.y + radius) / CELL))
	for gx in range(lo.x, hi.x + 1):
		for gy in range(lo.y, hi.y + 1):
			var key := Vector2i(gx, gy)
			if _grid.has(key):
				out.append_array(_grid[key])
	return out


## 半径内最近的存活敌人（exclude_ids = {instance_id: true}）
func nearest(pos: Vector2, max_d: float, exclude_ids: Dictionary = {}) -> Node2D:
	var best: Node2D = null
	var bd := max_d
	for e in query_circle(pos, max_d):
		if not is_instance_valid(e) or bool(e.get("dead")):
			continue
		if exclude_ids.has(e.get_instance_id()):
			continue
		var d := pos.distance_to(e.global_position)
		if d < bd:
			bd = d
			best = e
	return best


## 全部存活敌人（已过滤 dead；flag 关闭时回退组查询）
func all_enemies() -> Array:
	if not use_registry():
		return get_tree().get_nodes_in_group("enemies")
	var out: Array = []
	for e in enemies:
		if is_instance_valid(e) and not bool(e.get("dead")):
			out.append(e)
	return out


## 嘲讽召唤物列表（flag 关闭时回退组查询）
func taunt_list() -> Array:
	if not use_registry():
		return get_tree().get_nodes_in_group("taunt_summons")
	return taunts
