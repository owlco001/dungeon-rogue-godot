class_name RunSave
extends RefCounted
## 中途存档：保存当前冒险进度，下次可继续。
## 存档位置 user://run_save.cfg (ConfigFile)，Web 版走 IndexedDB 持久化。

const SAVE_PATH := "user://run_save.cfg"

## 待继续的存档（场景切换时传递）
static var pending_continue: Dictionary = {}


## 是否有中途存档
static func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


## 保存一局进度。data 由 main.gd 组装。
static func save_run(data: Dictionary) -> bool:
	var cfg := ConfigFile.new()
	for k in data.keys():
		cfg.set_value("run", k, data[k])
	cfg.set_value("run", "saved_at", Time.get_unix_time_from_system())
	var err := cfg.save(SAVE_PATH)
	return err == OK


## 读取存档，返回 Dictionary；无存档返回空字典
static func load_run() -> Dictionary:
	if not has_save():
		return {}
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return {}
	var data := {}
	for k in cfg.get_section_keys("run"):
		data[k] = cfg.get_value("run", k)
	return data


## 删除存档（通关/死亡/开始新局时调用）
static func clear() -> void:
	if has_save():
		DirAccess.remove_absolute(SAVE_PATH)


## 存档摘要（大厅"继续"按钮显示用）
static func summary() -> String:
	var d := load_run()
	if d.is_empty():
		return ""
	var cname := str(d.get("char_id", "?"))
	if GameData.CHARACTERS.has(cname):
		cname = str(GameData.CHARACTERS[cname]["name"])
	var fl := int(d.get("floor_num", 1))
	var lv := int(d.get("level", 1))
	return "%s · 第%d层 · Lv.%d" % [cname, fl, lv]
