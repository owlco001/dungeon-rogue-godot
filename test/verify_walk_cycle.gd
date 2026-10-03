extends SceneTree
## 各方向步态周期一致性验证（2026-10-03 新增）
## 起因：batong front/back 6 帧、left/right 18 帧，而 player.gd 原先
## 四向一律写死 12fps，导致上下走与左右走的步态周期差 3 倍。
## 本脚本复算「帧数 -> fps -> 周期」，确认四向周期一致。
##
## 判据遵循 AI-HANDOVER §7 陷阱 5：必须做反向验证 —— 沿用旧的固定 12fps
## 时，帧数不等必然测出周期发散，用作对照组证明判据不恒真。

const PROJ := "res://assets/sprites/characters/"
const CYCLE_SEC := 0.7
const TOL := 0.02

func _frame_count(cid: String, d: String) -> int:
	var n := 0
	while true:
		var p := PROJ + cid + "/char_" + cid + "_" + d + "_walk_" + str(n).pad_zeros(2) + ".png"
		if not FileAccess.file_exists(p):
			break
		n += 1
	return n

## 上限须与 player.gd 的 _walk_fps 一致：取 30 会把 aila 的25/27 帧
## 强行压成同一 fps，周期反而不一致（0.833 vs 0.900）。
const FPS_MAX := 60.0

func _fps(n: int) -> float:
	if n <= 1:
		return 2.0
	return clampf(float(n) / CYCLE_SEC, 4.0, FPS_MAX)

func _init() -> void:
	print("=== 各方向步态周期（复算 player.gd 的 _walk_fps） ===")
	var total := 0
	var npass := 0
	for cid in ["batong", "aila", "mofei"]:
		print("[", cid, "]")
		var cycles: Array = []
		var frames: Array = []
		for d in ["front", "back", "left", "right"]:
			var n := _frame_count(cid, d)
			if n <= 0:
				print("  ", d, ": 无素材")
				continue
			var cyc := float(n) / _fps(n)
			cycles.append(cyc)
			frames.append(n)
			print("  %s: %2d 帧 -> fps %5.1f -> 周期 %.3fs" % [d, n, _fps(n), cyc])
		if cycles.size() < 2:
			continue
		var lo: float = cycles[0]
		var hi: float = cycles[0]
		for c in cycles:
			lo = minf(lo, c)
			hi = maxf(hi, c)
		var ok: bool = absf(hi - lo) < TOL
		total += 1
		if ok:
			npass += 1
		print("  周期区间 %.3f~%.3fs  偏差 %.4fs  -> %s" % [
			lo, hi, absf(hi - lo), ("[PASS]" if ok else "[FAIL]")])
		# 反向验证：旧的固定 12fps 在帧数不等时周期必然发散
		if frames.size() >= 2:
			var f_lo: float = 1e9
			var f_hi: float = 0.0
			for n in frames:
				var c2 := float(n) / 12.0
				f_lo = minf(f_lo, c2)
				f_hi = maxf(f_hi, c2)
			print("  [对照] 旧固定 12fps 下周期 %.3f~%.3fs  偏差 %.4fs（应大于 %.2f）" % [
				f_lo, f_hi, absf(f_hi - f_lo), TOL])
	print("\n=== 结果：%d PASS / %d FAIL ===" % [npass, total - npass])
