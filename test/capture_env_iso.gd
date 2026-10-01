extends SceneTree
## 隔离测试：只画 arena，无玩家/敌人，确认白斑来源。

const OUT := "/tmp/env_verify"


func _initialize() -> void:
	_run.call_deferred()


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	var img: Image = root.get_texture().get_image()
	img.save_png(OUT + "/" + name + ".png")
	print("shot: ", name)


func _wait(secs: float) -> void:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < int(secs * 1000.0):
		await process_frame


func _run() -> void:
	var arena: Node2D = load("res://scripts/arena.gd").new()
	arena.name = "Arena"
	root.add_child(arena)
	var cam := Camera2D.new()
	cam.position = Vector2(800, 600)
	cam.zoom = Vector2(0.55, 0.55)
	root.add_child(cam)
	cam.make_current()
	await _wait(2.0)
	await _shot("env_arena_only")
	print("torches=", arena._torches.size())
	print("DONE")
	quit()
