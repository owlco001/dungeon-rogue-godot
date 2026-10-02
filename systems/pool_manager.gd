extends RefCounted
## v0.8 B4 实体池（07 §2.3）：敌 96 / 弹 256 / 召唤 32 / 宝石 256。
## 调用方以 preload 常量引用（无 class_name，避免全局类缓存与循环依赖）。
## feature flag dungeon/pool_entities 关闭时 acquire 恒新建、release 恒 queue_free。
## 复用节点由 acquire 打上 pooled_reuse 标记，生成方负责在 add_child 后调 spawn_init()。

const CAPS := {"enemy": 96, "projectile": 256, "gem": 256, "summon": 32}
static var _pools := {}  # kind -> Array[Node]（树外停放的空闲节点）


static func use_pools() -> bool:
	return bool(ProjectSettings.get_setting("dungeon/pool_entities", true))


static func acquire(kind: String, factory: Callable) -> Node:
	if use_pools():
		var arr: Array = _pools.get(kind, [])
		while not arr.is_empty():
			var n: Node = arr.pop_back()
			if is_instance_valid(n):
				_pools[kind] = arr
				n.set_meta("pooled_reuse", true)
				return n
		_pools[kind] = arr
	return factory.call()


static func release_or_free(kind: String, n: Node) -> void:
	if not is_instance_valid(n):
		return
	if not use_pools():
		n.queue_free()
		return
	var arr: Array = _pools.get(kind, [])
	if arr.size() >= int(CAPS.get(kind, 0)):
		n.queue_free()
		return
	if n.has_method("pool_reset"):
		n.call("pool_reset")
	if n.get_parent() != null:
		n.get_parent().remove_child(n)
	arr.append(n)
	_pools[kind] = arr


static func pool_size(kind: String) -> int:
	return (_pools.get(kind, []) as Array).size()
