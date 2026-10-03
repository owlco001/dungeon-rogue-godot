class_name WaveDirector
extends Node
## v0.8 L3 波次调度（01 §5.1/§5.3）：独立于 main 的推进逻辑，只发事件，
## 不直接调用 main 的推进函数。3 波 60/25/15（T+0/8/18s）；
## 楼梯条件 = 层计时 70s 到期（本类 stairs_ready）或三波全清（main 存活计数判定）。

signal spawn_wave(entries: Array)  # entries: [{kind: String, elite: bool}]
signal stairs_ready
signal wave_announced(n: int, total: int)
signal tick_warning(seconds_left: int)

const WAVE_TIMES := [0.0, 8.0, 18.0]
const FLOOR_TIME := 70.0

var active := false
var waves: Array = []
var wave_idx := 0  # 已放出的波数
var t := 0.0
var _warn_left := 11


## 拆波：每兵种 round(60%)/round(25%)/余数；精英标记挂该兵种最先放出的个体
static func split_waves(comp: Dictionary, elite_asg: Dictionary) -> Array:
	var out: Array = [[], [], []]
	for kind in comp.keys():
		var n := int(comp[kind])
		var n1 := int(round(float(n) * 0.6))
		var n2 := int(round(float(n) * 0.25))
		var counts := [n1, n2, n - n1 - n2]
		var elites := int(elite_asg.get(kind, 0))
		for w in range(3):
			for i in range(counts[w]):
				var is_elite := elites > 0
				if is_elite:
					elites -= 1
				out[w].append({"kind": kind, "elite": is_elite})
	return out


func start_floor(comp: Dictionary, elite_asg: Dictionary) -> void:
	waves = split_waves(comp, elite_asg)
	wave_idx = 0
	t = 0.0
	_warn_left = 11
	active = true
	_release_wave()


func stop() -> void:
	active = false


func all_spawned() -> bool:
	return wave_idx >= waves.size()


func time_left() -> float:
	return maxf(0.0, FLOOR_TIME - t)


## 门禁用：直接置计时到期
func debug_force_time_up() -> void:
	if active:
		t = FLOOR_TIME


func _release_wave() -> void:
	if wave_idx >= waves.size():
		return
	spawn_wave.emit(waves[wave_idx])
	wave_announced.emit(wave_idx + 1, waves.size())
	wave_idx += 1


func _process(delta: float) -> void:
	if not active:
		return
	t += delta
	var left := FLOOR_TIME - t
	if left <= 10.0 and left > 0.0:
		var li := int(ceil(left))
		if li < _warn_left:
			_warn_left = li
			tick_warning.emit(li)
	if wave_idx < waves.size() and t >= WAVE_TIMES[wave_idx]:
		_release_wave()
	if t >= FLOOR_TIME:
		active = false
		stairs_ready.emit()
