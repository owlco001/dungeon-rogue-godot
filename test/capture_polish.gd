extends SceneTree
## Polish verification: equipment detail panel, boss juice, FX.
## Run: godot --rendering-driver opengl3 --audio-driver Dummy --path <project> --script res://test/capture_polish.gd

const OUT := "/tmp/godot_polish"
const BossScript := preload("res://scripts/boss.gd")

var _main: Node = null
var _hud: CanvasLayer = null


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
	# 选择角色开始游戏
	_hud = _main.get_node("HUD")
	_main._on_character_chosen("aila")
	await _wait(1.0)
	var player = _main.player
	# 给玩家加个被动，方便截图
	player.passives["attack"] = 2
	player.passives["crit"] = 1
	_hud.set_passives(player.passives)
	_hud.set_weapons(player.weapons)
	await _wait(0.5)
	await _shot("p1_equip_bar")

	# 武器详情弹窗
	_hud._show_detail("weapon", 0)
	await _wait(0.4)
	await _shot("p2_weapon_detail")
	_hud._detail_layer.visible = false

	# 被动详情弹窗
	_hud._show_detail("passive", 0)
	await _wait(0.4)
	await _shot("p3_passive_detail")
	_hud._detail_layer.visible = false

	# 爆炸特效
	_main.spawn_explosion(player.global_position + Vector2(200, -100), 130.0, 50.0, 0.5, 2.0)
	await _wait(0.15)
	await _shot("p4_explosion")
	await _wait(0.8)

	# 升级光柱
	FX.levelup_beam(_main, player.global_position)
	await _wait(0.25)
	await _shot("p5_levelup_beam")
	await _wait(1.0)

	# Boss：生成并截图 idle
	var bdef: Dictionary = GameData.BOSSES[5]
	var b := CharacterBody2D.new()
	b.set_script(BossScript)
	b.setup(bdef, player.global_position + Vector2(250, -50))
	_main.add_child(b)
	await _wait(1.0)
	await _shot("p6_boss_idle")
	# 受击 squash
	b.take_damage(100.0, Vector2.LEFT)
	await _wait(0.08)
	await _shot("p7_boss_hit")
	await _wait(0.5)
	# 前摇
	b._windup_t = 0.4
	b._windup_pos = player.global_position
	await _wait(0.2)
	await _shot("p8_boss_windup")
	await _wait(1.5)

	print("CAPTURE_DONE")
	quit()
