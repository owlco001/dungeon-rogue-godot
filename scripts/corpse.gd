extends Node2D
class_name Corpse
## 尸体标记（尸爆用）：程序化画圈，5 秒褪去，group "corpses"。

var elite := false
var _t := 0.0
const LIFE := 5.0


func setup(p_pos: Vector2, p_elite: bool) -> void:
	position = p_pos
	elite = p_elite


func _ready() -> void:
	add_to_group("corpses")


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()
	if _t >= LIFE:
		queue_free()


func _draw() -> void:
	var k := clampf(_t / LIFE, 0.0, 1.0)
	var a := 0.55 * (1.0 - k)
	var r := 22.0 if not elite else 30.0
	var tint := Color(0.75, 0.15, 0.2, a) if not elite else Color(0.9, 0.35, 0.1, a)
	draw_circle(Vector2.ZERO, r, Color(0.25, 0.05, 0.08, a * 0.8))
	draw_circle(Vector2.ZERO, r * 0.7, tint)
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 24, Color(tint.r, tint.g, tint.b, a), 3.0)
