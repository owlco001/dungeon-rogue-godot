extends SceneTree
## Glow verification: explosion glow, whirlwind glow disc, projectile halo.
## Run: godot --rendering-driver opengl3 --audio-driver Dummy --path <project> --script res://test/capture_glow.gd

const OUT := "/tmp/godot_glow"

var _main: Node = null


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var inst: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(inst)
	_main = inst
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
	await _wait(1.5)
	_main._on_character_chosen("aila")
	await _wait(1.0)
	var player = _main.player
	var ppos: Vector2 = player.global_position

	# 1. explosion glow mid-flash
	FX.explosion(_main, ppos + Vector2(120, -40), 130.0, Color(1.0, 0.55, 0.2))
	await _wait(0.12)
	await _shot("g1_explosion_glow")

	await _wait(0.8)
	# 2. whirlwind glow disc
	player._do_whirlwind({"radius": 170.0, "fx": "fx_whirlwind"})
	await _wait(0.18)
	await _shot("g2_whirlwind_glow")

	await _wait(0.8)
	# 3. projectile halo: spawn a real projectile flying past
	var prj := preload("res://scripts/projectile.gd").new()
	prj.setup("res://assets/sprites/fx/projectiles/proj_arrow.png", ppos + Vector2(-260, -60), Vector2.RIGHT, 420.0, 20.0, 0, 0)
	_main.add_child(prj)
	await _wait(0.35)
	await _shot("g3_projectile_halo")

	# 4. stairs aura: clear enemies to force stairs spawn
	for e in get_nodes_in_group("enemies"):
		e.queue_free()
	await _wait(1.2)
	_main._check_floor_clear()
	await _wait(1.0)
	await _shot("g4_stairs_aura")

	print("GLOW_CAPTURE_DONE")
	quit()
