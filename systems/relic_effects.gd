class_name RelicEffects
extends RefCounted
## v0.8 遗物代码钩子收口（01 §4.2 的 7 件）：监听 EventBus，不侵入结算主干。
## - bloodgem 血珀：击杀回复（精英/Boss 8，其余 2），经 enemy_died
## - thornmail 荆棘之甲：受击反弹 40%，经 player_damaged(attacker)
## - infinitefire 无尽之火：每 10s 对最近 5 只敌人各 40 点，经 tick 驱动
## cross 圣十字 / scythe 收割镰刀 / phoenixheart 凤凰之心在 player 结算点内联
## （减伤窗口、斩杀判定、复活均为同步结算语义，不走事件）。

static var _player: Node = null
static var _attached := false
static var _fire_t := 0.0


static func attach(p: Node) -> void:
	_player = p
	_fire_t = 0.0
	if _attached:
		return
	_attached = true
	EventBus.enemy_died.connect(_on_enemy_died)
	EventBus.player_damaged.connect(_on_player_damaged)


static func _has(rid: String) -> bool:
	return _player != null and is_instance_valid(_player) \
		and "relics" in _player and rid in _player.relics


static func _on_enemy_died(e: Node) -> void:
	if not _has("bloodgem") or not is_instance_valid(e):
		return
	var heal := 2.0
	if ("elite" in e and e.elite) or ("is_boss" in e and e.is_boss):
		heal = 8.0
	_player.hp = minf(_player.max_hp, _player.hp + heal)
	_player.hp_changed.emit(_player.hp, _player.max_hp)


static func _on_player_damaged(amount: float, _from_dir: Vector2, attacker: Node) -> void:
	if not _has("thornmail"):
		return
	if attacker == null or not is_instance_valid(attacker) \
			or not attacker.has_method("take_damage"):
		return
	var dir := Vector2.ZERO
	if "global_position" in attacker and "global_position" in _player:
		dir = (attacker.global_position - _player.global_position).normalized()
	attacker.take_damage(amount * 0.4, dir, 0.0)


static func tick(delta: float) -> void:
	if not _has("infinitefire"):
		_fire_t = 0.0
		return
	_fire_t += delta
	if _fire_t < 10.0:
		return
	_fire_t = 0.0
	_strike()


static func _strike() -> void:
	var center: Vector2 = _player.global_position
	var hit: Array = []
	var excluded := {}
	for i in range(5):
		var e := Registry.nearest(center, 100000.0, excluded)
		if e == null:
			break
		excluded[e.get_instance_id()] = true
		hit.append(e)
	var idx := 0
	for e in hit:
		if not is_instance_valid(e):
			continue
		var delay := 0.08 * float(idx)
		idx += 1
		_strike_one(e, center, delay)


static func _strike_one(e: Node, from_pos: Vector2, delay: float) -> void:
	if delay > 0.0:
		await Engine.get_main_loop().create_timer(delay).timeout
	if not is_instance_valid(e) or not is_instance_valid(_player):
		return
	var dir: Vector2 = (e.global_position - from_pos).normalized()
	if e.get_parent() != null:
		FX.glow_ring(e.get_parent(), e.global_position, 60.0,
			Color(1.0, 0.75, 0.3, 0.8), 0.35, 3)
	e.take_damage(40.0, dir, 0.0)
