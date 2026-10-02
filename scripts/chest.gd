extends Node2D
## v0.8 宝箱（01 §4.2 / 05 §4.2）：非 Boss 层 15% 刷新，玩家靠近自动开启。
## 演出分镜：T0 盖子弹开 → T+100 金光 → T+350 金环+震屏 → T+450 掉落弹出。
## 掉落结算在 main.spawn_chest_loot（遗物权重 roll + 30–60 金）。

var _opened := false
var _sprite: Sprite2D = null


func _ready() -> void:
	_sprite = Sprite2D.new()
	_sprite.texture = load("res://assets/sprites/pickups/chest.png") as Texture2D
	_sprite.scale = Vector2.ONE * 1.6
	add_child(_sprite)
	add_to_group("chests")


func _physics_process(_delta: float) -> void:
	if _opened:
		return
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null or not is_instance_valid(player):
		return
	if global_position.distance_to(player.global_position) < 76.0:
		_open()


func _open() -> void:
	_opened = true
	EventBus.chest_opened.emit(global_position)
	var game := get_tree().get_first_node_in_group("game")
	var pos := global_position
	# T0 盖子弹开：弹性回弹（单图近似：倾倒回正 + 缩放弹跳）
	_sprite.rotation = -0.42
	var tw := create_tween()
	tw.set_ignore_time_scale(true)
	tw.tween_property(_sprite, "rotation", 0.0, 0.2).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_sprite, "scale", Vector2.ONE * 1.85, 0.1)
	tw.tween_property(_sprite, "scale", Vector2.ONE * 1.6, 0.12)
	if game != null:
		# T+100 金光
		await get_tree().create_timer(0.1, true, false, true).timeout
		FX.glow(game, pos, 240.0, Color(1.0, 0.85, 0.3, 0.72), 0.45, 5)
		FX.hit_spark(game, pos + Vector2(0, -10), Color(1.0, 0.85, 0.3))
		# T+350 金环 + 震屏
		await get_tree().create_timer(0.25, true, false, true).timeout
		FX.glow_ring(game, pos, 320.0, Color(1.0, 0.85, 0.3, 0.85), 0.5, 5)
		FX.shake(game, 8.0)
		# T+450 掉落弹出
		await get_tree().create_timer(0.1, true, false, true).timeout
		if is_instance_valid(game) and game.has_method("spawn_chest_loot"):
			game.spawn_chest_loot(pos)
	# 开启后宝箱变暗留置（探索痕迹），不再交互
	_sprite.modulate = Color(0.55, 0.5, 0.5, 0.9)
	set_physics_process(false)
