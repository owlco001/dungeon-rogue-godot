extends Area2D
## Stairs portal: appears when the floor is cleared; walking in goes up a floor.

var _t := 0.0
var _used := false
var sprite: Sprite2D


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1
	var sp := Sprite2D.new()
	sp.name = "Sprite2D"
	sp.texture = load(GameData.STAIRS_TEX) as Texture2D
	sp.scale = Vector2(2.0, 2.0)
	add_child(sp)
	sprite = sp
	# 金色呼吸光环，引导玩家注意楼梯
	FX.attach_aura(self, 150.0, Color(1.0, 0.85, 0.4, 0.45), 2)
	var cs := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 40.0
	cs.shape = circle
	add_child(cs)
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_t += delta
	sprite.position.y = sin(_t * 3.0) * 5.0
	sprite.modulate.a = 0.85 + 0.15 * sin(_t * 5.0)


func _on_body_entered(body: Node2D) -> void:
	if _used or not body.is_in_group("player"):
		return
	_used = true
	var game := get_tree().get_first_node_in_group("game")
	if game != null and game.has_method("next_floor"):
		# deferred: body_entered fires during physics flush, and next_floor
		# adds new collision shapes -> must not run inside the callback
		game.call_deferred("next_floor")
		Sfx.play("stairs")
