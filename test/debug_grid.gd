extends SceneTree
## DEBUG: 打印 floor1 布局 grid / pf_grid + 各房间 pf 连通性
const RG3 := preload("res://systems/room_gen.gd")
const PF3 := preload("res://systems/pathfind.gd")


func _initialize() -> void:
	var fdef_theme := "corridor"
	var seed := absi(hash(fdef_theme + ":" + str(1)))
	var g = RG3.new()
	g.generate(seed)
	print("seed=", seed, " rooms=", g.rooms.size())
	for y in range(RG3.GH):
		var line := ""
		for x in range(RG3.GW):
			var c := Vector2i(x, y)
			var lay: int = g.grid[y * RG3.GW + x]
			var pf: int = g.pf_grid[y * RG3.GW + x]
			if lay == 1:
				line += "#"
			elif pf == 1:
				line += "x"  # 布局地面但 pf 封
			else:
				line += "."
		print(line)
	var hall := Vector2(800, 600)
	for r in g.rooms:
		var rc := Vector2((float(r["x"]) + float(r["w"]) * 0.5) * RG3.CELL,
			(float(r["y"]) + float(r["h"]) * 0.5) * RG3.CELL)
		var p: PackedVector2Array = PF3.find_path(g.pf_grid, RG3.GW, RG3.GH, rc, hall, RG3.CELL)
		print("room at ", rc, " pf_path=", p.size())
	quit(0)
