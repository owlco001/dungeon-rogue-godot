extends Node2D
## Pickup: XP gem (s/m/l) or gold coin. Magnet-attracted to the player.

var kind := "xp"   # "xp" / "gold" / "relic"
var value := 2
var relic_id := ""
var _player: Node2D = null
var _t := 0.0
var _vel := Vector2.ZERO
var _taken := false
var sprite: Sprite2D


func setup(p_kind: String, p_value: int, p_pos: Vector2, p_relic_id: String = "") -> void:
	kind = p_kind
	value = p_value
	global_position = p_pos
	relic_id = p_relic_id


func _ready() -> void:
	add_to_group("pickups")
	var sp := Sprite2D.new()
	sp.name = "Sprite2D"
	if kind == "xp":
		sp.texture = load(GameData.GEM_TEX[GameData.gem_tier_for_xp(value)]) as Texture2D
	elif kind == "relic":
		sp.texture = load(String(GameData.RELICS[relic_id]["icon"])) as Texture2D
		sp.scale = Vector2.ONE * 0.75
	else:
		sp.texture = load(GameData.COIN_TEX) as Texture2D
	add_child(sp)
	sprite = sp
	z_index = 3
	# little pop-out scatter
	_vel = Vector2.RIGHT.rotated(randf() * TAU) * randf_range(60.0, 140.0)
	_player = get_tree().get_first_node_in_group("player") as Node2D


func _physics_process(delta: float) -> void:
	if _taken:
		return
	_t += delta
	_vel = _vel.move_toward(Vector2.ZERO, 600.0 * delta)
	var move := _vel * delta
	if is_instance_valid(_player):
		var to: Vector2 = _player.global_position - global_position
		var dist := to.length()
		var magnet_r: float = _player.MAGNET_RADIUS
		if dist < magnet_r:
			move += to.normalized() * lerpf(900.0, 220.0, dist / magnet_r) * delta
		if dist < _player.PICKUP_RADIUS:
			_collect()
			return
	global_position += move
	sprite.position.y = -6.0 + sin(_t * 5.0) * 3.0


func _collect() -> void:
	_taken = true
	if is_instance_valid(_player):
		if kind == "xp":
			_player.gain_xp(value)
			Sfx.play("gem")
		elif kind == "relic":
			_player.gain_relic(relic_id)
			Sfx.play("relic")
		else:
			_player.gain_gold(value)
			Sfx.play("coin")
	queue_free()
