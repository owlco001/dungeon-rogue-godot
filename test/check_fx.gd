extends SceneTree
## 技能特效专项验证（9 张）
##
## 与其他素材管线的根本区别：这些是【加法混合】素材，验证标准不是
## "自身好不好看"，而是"叠加到暗场景后，染色是否还看得见"。
## 所以这里除了常规 load / 尺寸 / 中性检查，还必须实测加法合成结果。

const FX := {
	"arrow_rain_zone": [1.0, 0.9, 0.6, 0.75],
	"shield_slam": [0.7, 0.9, 1.0, 0.95],
	"warcry": [1.0, 0.75, 0.35, 0.9],
	"stomp_crack": [1.0, 0.8, 0.5, 0.95],
	"soul_orb": [0.7, 0.4, 1.0, 0.9],
	"dash_ghost": [0.6, 0.9, 1.0, 0.8],
	"holy_shield": [0.6, 0.9, 1.0, 0.85],
	"time_ripple": [0.5, 0.8, 1.0, 0.8],
	"levelup": [1.0, 0.95, 0.7, 0.9],
}

var _pass := 0
var _fail := 0

func _check(cond: bool, label: String, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("  [PASS] %s  %s" % [label, detail])
	else:
		_fail += 1
		print("  [FAIL] %s  %s" % [label, detail])


## 用 get_data() 批量读，不用 get_pixel 逐点—— 256x256 逐点调 6.5 万次尚可，
## 但若将来提到 1024 就会卡到超时，导致断言被跳过、变成假通过。
func _pixels(img: Image) -> PackedFloat32Array:
	var d := img.get_data()
	var out := PackedFloat32Array()
	out.resize(d.size() / 4)
	for i in range(0, d.size(), 4):
		out[i / 4] = (float(d[i]) + float(d[i + 1]) + float(d[i + 2])) / 765.0
	return out


func _init() -> void:
	print("=== 技能特效验证（加法混合管线）===")
	var names := FX.keys()

	# 1) 全部可加载
	print("\n[1] 引擎 load 验证")
	for n in names:
		var t := load("res://assets/sprites/fx/fx_%s.png" % n) as Texture2D
		_check(t != null, "fx_%s" % n, "null" if t == null else "%dx%d" % [t.get_width(), t.get_height()])

	# 2) 尺寸统一 256x256
	print("\n[2] 尺寸一致性")
	for n in names:
		var t := load("res://assets/sprites/fx/fx_%s.png" % n) as Texture2D
		_check(t != null and t.get_width() == 256 and t.get_height() == 256,
			"fx_%s 尺寸" % n, "%dx%d" % [t.get_width(), t.get_height()])

	# 3) 中性灰：素材带色会让代码 modulate 染色变脏
	print("\n[3] 中性检查（三通道必须相等）")
	for n in names:
		var t := load("res://assets/sprites/fx/fx_%s.png" % n) as Texture2D
		var img := t.get_image()
		var d := img.get_data()
		var maxdiff := 0.0
		for i in range(0, d.size(), 4):
			var m := maxf(float(d[i]), maxf(float(d[i + 1]), float(d[i + 2])))
			var mn := minf(float(d[i]), minf(float(d[i + 1]), float(d[i + 2])))
			maxdiff = maxf(maxdiff, m - mn)
		_check(maxdiff <= 1.0, "fx_%s 中性" % n, "最大通道差 %.0f" % maxdiff)

	# 4) alpha 全 255：加法混合下 alpha 参与衰减，半透明会整体变暗
	print("\n[4] alpha 全不透明")
	for n in names:
		var img := (load("res://assets/sprites/fx/fx_%s.png" % n) as Texture2D).get_image()
		var d := img.get_data()
		var amin := 255.0
		for i in range(3, d.size(), 4):
			amin = minf(amin, float(d[i]))
		_check(amin >= 254.0, "fx_%s alpha" % n, "min=%.0f" % amin)

	# 5) 黑区够黑：加法下黑=透明，灰底会整体提亮成"脏雾"
	print("\n[5] 暗区够暗（加法素材不能有灰底）")
	for n in names:
		var img := (load("res://assets/sprites/fx/fx_%s.png" % n) as Texture2D).get_image()
		var px := _pixels(img)
		var dark := 0
		for v in px:
			if v < 0.06:
				dark += 1
		var ratio := float(dark) / float(px.size())
		_check(ratio > 0.60, "fx_%s 暗区占比" % n, "%.0f%%" % (ratio * 100.0))

	# 6) 有实际发光内容（不能是全黑图）
	print("\n[6] 发光内容存在")
	for n in names:
		var img := (load("res://assets/sprites/fx/fx_%s.png" % n) as Texture2D).get_image()
		var px := _pixels(img)
		var lit := 0
		for v in px:
			if v > 0.35:
				lit += 1
		var ratio := float(lit) / float(px.size())
		_check(ratio > 0.002 and ratio < 0.25, "fx_%s 亮核占比" % n, "%.2f%%" % (ratio * 100.0))

	# 7)★核心：模拟加法混合后染色是否可辨
	#    Godot BLEND_MODE_ADD = dst + src*mod。背景取实测地板明度 0.27。
	#    若三通道全部撞 255 -> 纯白 -> modulate 染色失效 = 素材不合格。
	print("\n[7] 加法混合后染色可辨（核心）")
	for n in names:
		var img := (load("res://assets/sprites/fx/fx_%s.png" % n) as Texture2D).get_image()
		var d := img.get_data()
		var m: Array = FX[n]
		var bg := 0.27
		var white := 0
		var total := 0
		var tint_sum := 0.0
		for i in range(0, d.size(), 4):
			var lum := (float(d[i]) + float(d[i + 1]) + float(d[i + 2])) / 765.0
			var r := bg + lum * float(m[0]) * float(m[3])
			var g := bg + lum * float(m[1]) * float(m[3])
			var b := bg + lum * float(m[2]) * float(m[3])
			if lum > 0.25:
				total += 1
				if r >= 0.995 and g >= 0.995 and b >= 0.995:
					white += 1
				# 染色强度：最强通道 - 最弱通道
				var hi := maxf(r, maxf(g, b))
				var lo := minf(r, minf(g, b))
				tint_sum += hi - lo
		var wr := (float(white) / float(maxi(total, 1))) * 100.0
		var avg_tint := tint_sum / float(maxi(total, 1))
		# 纯白率 <8%（染色基本保住）且平均色差 >0.03（有可辨色相）
		_check(wr < 8.0 and avg_tint > 0.03, "fx_%s 染色" % n,
			"纯白率=%.1f%% 平均色差=%.3f" % [wr, avg_tint])

	# 8) 差异化：9 张不能长得一样
	print("\n[8] 相互差异度")
	for i in range(names.size()):
		for j in range(i + 1, names.size()):
			var ia := (load("res://assets/sprites/fx/fx_%s.png" % names[i]) as Texture2D).get_image()
			var ib := (load("res://assets/sprites/fx/fx_%s.png" % names[j]) as Texture2D).get_image()
			var da := ia.get_data()
			var db := ib.get_data()
			var diff := 0.0
			var cnt := 0
			for k in range(0, da.size(), 4):
				var va := (float(da[k]) + float(da[k + 1]) + float(da[k + 2])) / 765.0
				var vb := (float(db[k]) + float(db[k + 1]) + float(db[k + 2])) / 765.0
				diff += absf(va - vb)
				cnt += 1
			var dm := diff / float(cnt)
			if dm < 0.02:
				_check(false, "差异 %s/%s" % [names[i], names[j]], "%.4f 过低" % dm)

	print("\n=== 结果：%d PASS / %d FAIL ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
