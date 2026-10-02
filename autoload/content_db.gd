extends Node
## ContentDB（v0.8 B1 / A2 第一批）：data/*.json 统一加载入口。
## 启动时加载 res://data/ 下全部 JSON 为表；玩法代码经 table()/value() 读取，
## 缺表/坏文件只报错不崩溃（回退由调用方用默认值兜底）。

var _tables := {}


func _ready() -> void:
	load_all()


func load_all() -> void:
	_tables.clear()
	var dir := DirAccess.open("res://data")
	if dir == null:
		push_warning("ContentDB: res://data missing")
		return
	for f in dir.get_files():
		if not f.ends_with(".json"):
			continue
		var tname := f.trim_suffix(".json")
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/" + f))
		if parsed is Dictionary or parsed is Array:
			_tables[tname] = parsed
		else:
			push_error("ContentDB: bad json: " + f)
	print("ContentDB tables: ", _tables.keys())


func has_table(tname: String) -> bool:
	return _tables.has(tname)


func table(tname: String) -> Dictionary:
	var t = _tables.get(tname, {})
	return t if t is Dictionary else {}


func value(tname: String, key: String, default_value = null):
	return table(tname).get(key, default_value)
