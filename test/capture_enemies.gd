extends SceneTree
## 杂兵实机观感验证：7 种敌人 + 角色同框，摆在真实 tile 上
## Run: xvfb-run -a godot --rendering-driver opengl3 --audio-driver Dummy --path . --script res://test/capture_enemies.gd
##
## 数值 QC 过不代表观感对——这一脚本只看三件事：
##   1. 敌人/角色比例是否协调（蛮兽该明显更大，蝙蝠该明显小）
##   2. 敌人在暗 tile 上是否「跳出来」（明度层级是否够）
##   3. 敌人之间剪影是否互相混淆

const OUT := "/tmp/enemyshot"
const IDS := ["slime", "bat", "skeleton", "spitter", "exploder", "brute", "gargoyle"]


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	_run.call_deferred()


func _wait(secs: float) -> void:
	var s := Time.get_ticks_msec()
	while Time.get_ticks_msec() - s < int(secs * 1000.0):
		await process_frame


func _find_sprite(n: Node) -> Node2D:
	if n is AnimatedSprite2D:
		return n as Node2D
	for c in n.get_children():
		var r := _find_sprite(c)
		if r != null:
			return r
	return null


func _run() -> void:
	# tile 背景
	var tp := "res://assets/tiles/corridor/tile_corridor_floor_a.png"
	var tex: Texture2D = load(tp) if ResourceLoader.exists(tp) else null
	if tex != null:
		for i in range(8):
			for j in range(5):
				var t := Sprite2D.new()
				t.texture = tex
				t.scale = Vector2(2.0, 2.0)
				t.position = Vector2(i * 384, j * 288)
				root.add_child(t)

	# 角色
	var ps := load("res://scenes/player.tscn") as PackedScene
	var pl := ps.instantiate()
	pl.position = Vector2(330, 480)
	root.add_child(pl)
	await process_frame
	await process_frame

	# 敌人：3列 × 3 行，间距 360，避开角色
	var EnemyScene := load("res://scenes/enemy.tscn") as PackedScene
	var placed := 0
	for i in range(IDS.size()):
		var e: Node = EnemyScene.instantiate()
		e.set("enemy_id", IDS[i])
		e.set("target", null)          # 不追击，避免乱跑出画面
		var col := i % 3
		var row := i / 3
		e.position = Vector2(880 + col * 360, 300 + row * 340)
		root.add_child(e)
		await _wait(0.3)
		var sp := _find_sprite(e)
		if sp != null:
			print("%-10s scale=%.2f anim=%s" % [IDS[i], sp.scale.x, sp.animation])
		placed += 1
	print("已摆放: ", placed)

	# 全景截图
	await _wait(0.5)
	var img: Image = root.get_texture().get_image()
	img.save_png(OUT + "/all.png")

	# 剪影测试：把敌人统一缩到 88px（一局游戏里的实际显示尺寸量级），看是否还能分辨
	var sheet := Image.create(IDS.size() * 96, 112, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.11, 0.11, 0.14, 1.0))
	for i in range(IDS.size()):
		var p := "res://assets/sprites/enemies/enemy_%s_idle_00.png" % IDS[i]
		if not ResourceLoader.exists(p):
			continue
		var src: Texture2D = load(p)
		var si := src.get_image()
		si.resize(88, 88, Image.INTERPOLATE_LANCZOS)
		# 灰度剪影：明度层级对比也一起看
		for y in range(88):
			for x in range(88):
				var c := si.get_pixel(x, y)
				if c.a > 0.4:
					var g := (c.r + c.g + c.b) / 3.0
					sheet.set_pixel(i * 96 + 4 + x, 12 + y, Color(g, g, g, 1.0))
	sheet.save_png(OUT + "/silhouette_88px.png")
	print("截图完成: ", OUT)
	quit(0)