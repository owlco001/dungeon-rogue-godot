extends Control
## Floating virtual joystick: the base appears where the finger lands
## (left half of the screen), knob follows the drag. Works with touch
## (via mouse emulation) and mouse.
## (no class_name: avoids clash, hud.gd loads this script directly)

const RADIUS := 80.0
const KNOB_R := 34.0

var value := Vector2.ZERO
var _active := false
var _origin := Vector2.ZERO
var _hint := Vector2.ZERO  # idle hint position, follows last touch


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(queue_redraw)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_begin_drag(event.position)
		else:
			_release()
	elif event is InputEventMouseMotion and _active:
		_update_knob(event.position)
	elif event is InputEventScreenTouch:
		if event.pressed:
			_begin_drag(event.position)
		else:
			_release()
	elif event is InputEventScreenDrag and _active:
		_update_knob(event.position)


func _begin_drag(pos: Vector2) -> void:
	_active = true
	_origin = _clamp_origin(pos)
	_hint = _origin
	_update_knob(pos)


func _input(event: InputEvent) -> void:
	# catch release outside the control
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and _active:
		_release()
	elif event is InputEventScreenTouch and not event.pressed and _active:
		_release()


func _clamp_origin(p: Vector2) -> Vector2:
	return Vector2(
		clampf(p.x, RADIUS, maxf(size.x - RADIUS, RADIUS)),
		clampf(p.y, RADIUS, maxf(size.y - RADIUS, RADIUS))
	)


func _update_knob(pos: Vector2) -> void:
	var d := pos - _origin
	if d.length() > RADIUS:
		d = d.normalized() * RADIUS
	value = d / RADIUS
	queue_redraw()


func _release() -> void:
	_active = false
	value = Vector2.ZERO
	queue_redraw()


func _draw() -> void:
	if _active:
		draw_circle(_origin, RADIUS, Color(1, 1, 1, 0.10))
		draw_arc(_origin, RADIUS, 0.0, TAU, 48, Color(1, 1, 1, 0.35), 3.0, true)
		var k := _origin + value * RADIUS
		draw_circle(k, KNOB_R, Color(1, 1, 1, 0.30))
		draw_arc(k, KNOB_R, 0.0, TAU, 32, Color(1, 1, 1, 0.55), 2.0, true)
	else:
		# faint idle hint so players discover the touch zone
		var h := _hint if _hint != Vector2.ZERO else Vector2(140.0, size.y - 180.0)
		draw_arc(h, RADIUS, 0.0, TAU, 48, Color(1, 1, 1, 0.10), 2.0, true)
