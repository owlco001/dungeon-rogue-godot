extends Node2D
## Soft elliptical blob shadow drawn under the player.


func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.7, 0.62))
	draw_circle(Vector2.ZERO, 30.0, Color(0, 0, 0, 0.32))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
