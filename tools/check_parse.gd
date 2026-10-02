extends SceneTree
## V1 解析门禁：遍历 res:// 全部 .gd 逐个 load()，并校验 autoload 注册文件存在。
## 不引用任何 autoload 单例（-s/--script 模式安全）。
## 运行：godot --headless --path . --script res://tools/check_parse.gd

func _initialize() -> void:
	var files: Array[String] = []
	_collect("res://", files)
	files.sort()
	var failed: Array[String] = []
	for f in files:
		var s := load(f) as GDScript
		# v0.8.20：load() 对语法错误的脚本也不返回 null；reload() 会误伤引用 autoload 的脚本，
		# 用 can_instantiate() 判定（坏脚本 false，正常脚本/autoload 均为 true，已实测）
		if s == null or not s.can_instantiate():
			failed.append(f)
	var auto_failed: Array[String] = []
	for p in ProjectSettings.get_property_list():
		var pname := String(p.get("name", ""))
		if not pname.begins_with("autoload/"):
			continue
		var v := String(ProjectSettings.get_setting(pname))
		var path := v.trim_prefix("*")
		if not FileAccess.file_exists(path):
			auto_failed.append(pname + " -> " + path)
	var ok := failed.is_empty() and auto_failed.is_empty()
	print("V1 checked scripts: ", files.size(), " failed: ", failed.size())
	for f in failed:
		print("V1 LOAD FAIL: ", f)
	for a in auto_failed:
		print("V1 AUTOLOAD MISSING: ", a)
	print("V1 RESULT: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)

func _collect(dir_path: String, out: Array[String]) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if name.begins_with("."):
			name = d.get_next()
			continue
		var full := dir_path.path_join(name)
		if d.current_is_dir():
			if name != ".godot":
				_collect(full, out)
		elif name.ends_with(".gd"):
			out.append(full)
		name = d.get_next()
	d.list_dir_end()
