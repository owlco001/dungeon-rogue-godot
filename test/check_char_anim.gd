extends SceneTree
## 角色四方向动画完整性验证
##
## player.gd _tex() 的约定：引擎的 down/up 会映射到素材的 front/back
## （"行走动画只产出 right/left/front/back 四个朝向"）。
## 所以素材目录必须有 front/back，缺了这两个朝向 load() 会返回 null，
## 角色在 down/up 朝向就是空的—— 而引擎默认初始朝向正是 down。
##
## Run: godot --headless --path . --script res://test/check_char_anim.gd

const CHARS := ["batong", "mofei", "aila"]
const DIRS := ["down", "up", "left", "right"]

var _pass := 0
var _fail := 0


func _check(cond: bool, label: String, detail := "") -> void:
	if cond:
		_pass += 1
		print("  [PASS] %s  %s" % [label, detail])
	else:
		_fail += 1
		print("  [FAIL] %s  %s" % [label, detail])


## 复刻 player.gd _tex() 的映射逻辑
func _mapped(cid: String, dirn: String) -> String:
	if dirn == "down":
		return "front"
	if dirn == "up":
		return "back"
	return dirn


func _count(cid: String, d: String, action: String) -> int:
	var dir := DirAccess.open("res://assets/sprites/characters/%s" % cid)
	if dir == null:
		return -1
	var n := 0
	for f in dir.get_files():
		if f.ends_with(".import"):
			continue
		if f.begins_with("char_%s_%s_%s_" % [cid, d, action]) and f.ends_with(".png"):
			n += 1
	return n


func _init() -> void:
	print("=== 角色四方向动画验证 ===\n")
	print("[映射] 引擎 down->front, up->back, left->left, right->right\n")

	for cid in CHARS:
		print("[%s]" % cid)
		# 1) 四个朝向都必须能load 到第 0 帧
		for dirn in DIRS:
			var d := _mapped(cid, dirn)
			var p := "res://assets/sprites/characters/%s/char_%s_%s_idle_00.png" % [cid, cid, d]
			var exists := ResourceLoader.exists(p)
			var tex := load(p) as Texture2D if exists else null
			_check(tex != null, "%s/%s idle_00" % [cid, dirn],
				"-> %s_%s  %s" % [cid, d, "OK %dx%d" % [tex.get_width(), tex.get_height()] if tex != null else "缺失"])

		# 2) 行走帧数（两套命名各统计一次，报出实际用哪套）
		var walk_actual := 0
		var walk_mapped := 0
		var walk_legacy := 0
		for dirn in DIRS:
			var d := _mapped(cid, dirn)
			walk_mapped += _count(cid, d, "walk")
			walk_legacy += _count(cid, dirn, "walk")
			walk_actual = maxi(walk_actual, _count(cid, d, "walk"))
		_check(walk_mapped > 0, "%s 行走帧(映射后)" % cid,
			"映射后共%d 帧  旧命名共%d 帧" % [walk_mapped, walk_legacy])
		print("")

	print("=== 结果：%d PASS / %d FAIL ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
