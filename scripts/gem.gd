extends Node2D
## Pickup: XP gem (s/m/l) or gold coin. Magnet-attracted to the player.

const PoolManager := preload("res://systems/pool_manager.gd")
# 拾取物源图为 256px，统一映射到 48px 地砖世界标尺。
const PICKUP_ART_SCALE := 0.29
# 金币透明内容占 256 画布约 240px 宽；相机整体放大后保持小而清晰。
const COIN_ART_SCALE := 0.13
# 遗物图标也按掉落物世界标尺显示，避免 0.75 造成远大于角色的图标。
const RELIC_ART_SCALE := 0.29

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
	spawn_init()


## 出生初始化（首生由 _ready 调用；池化复用时由生成方在 add_child 后调用）
func spawn_init() -> void:
	add_to_group("pickups")
	_build_sprite()
	z_index = 3
	_taken = false
	_t = 0.0
	visible = true
	# little pop-out scatter
	_vel = Vector2.RIGHT.rotated(randf() * TAU) * randf_range(60.0, 140.0)
	_player = get_tree().get_first_node_in_group("player") as Node2D


func _build_sprite() -> void:
	if sprite != null and is_instance_valid(sprite):
		sprite.queue_free()
	var sp := Sprite2D.new()
	sp.name = "Sprite2D"
	if kind == "xp":
		sp.texture = load(GameData.GEM_TEX[GameData.gem_tier_for_xp(value)]) as Texture2D
		sp.scale = Vector2.ONE * PICKUP_ART_SCALE
	elif kind == "relic":
		sp.texture = load(String(GameData.RELICS[relic_id]["icon"])) as Texture2D
		sp.scale = Vector2.ONE * RELIC_ART_SCALE
	else:
		sp.texture = load(GameData.COIN_TEX) as Texture2D
		sp.scale = Vector2.ONE * COIN_ART_SCALE
	add_child(sp)
	sprite = sp


## 池化回收前：标记已拾取，防停放期间继续物理
func pool_reset() -> void:
	_taken = true


func _physics_process(delta: float) -> void:
	if _taken:
		return
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node2D
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
	PoolManager.release_or_free("gem", self)
