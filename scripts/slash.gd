extends Node2D
## Slash arc effect for the melee attack. Fades out over ~0.18s.

var _t := 1.0
var _ang := 0.0


func do_slash(ang: float) -> void:
	_ang = ang
	_t = 0.0
	visible = true
	queue_redraw()


func _process(delta: float) -> void:
	if _t < 1.0:
		_t = minf(1.0, _t + delta / 0.18)
		queue_redraw()
		if _t >= 1.0:
			visible = false


func _draw() -> void:
	if _t >= 1.0:
		return
	var fade := 1.0 - _t
	var a0 := _ang - 1.15 + _t * 1.5
	var a1 := a0 + 0.85
	draw_arc(Vector2.ZERO, 72.0, a0, a1, 28, Color(1, 1, 1, 0.85 * fade), 12.0, true)
	draw_arc(Vector2.ZERO, 72.0, a0, a1, 28, Color(0.55, 0.85, 1.0, 0.5 * fade), 5.0, true)
