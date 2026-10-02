class_name RunSave
extends RefCounted
## 中途存档：保存当前冒险进度，下次可继续。
## 存档位置 user://run_save.cfg (ConfigFile)，Web 版走 IndexedDB 持久化。

const SAVE_PATH := "user://run_save.cfg"

## SaveService 经 root 节点动态访问（理由同 meta.gd 的 _ss）。
static func _ss() -> Node:
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		return (ml as SceneTree).root.get_node_or_null("SaveService")
	return null


static func _ver() -> int:
	var n := _ss()
	return int(n.call("version")) if n != null else 3

## 待继续的存档（场景切换时传递）
static var pending_continue: Dictionary = {}


## 是否有中途存档
static func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


## 保存一局进度。data 由 main.gd 组装。v0.8：版本号 + 原子写（.tmp→.bak→rename）。
static func save_run(data: Dictionary) -> bool:
	var cfg := ConfigFile.new()
	for k in data.keys():
		cfg.set_value("run", k, data[k])
	cfg.set_value("run", "saved_at", Time.get_unix_time_from_system())
	cfg.set_value("run", "version", _ver())
	var n := _ss()
	if n != null:
		return bool(n.call("atomic_save_cfg", cfg, SAVE_PATH))
	return cfg.save(SAVE_PATH) == OK


## 读取存档，返回 Dictionary；无存档/损坏返回空字典。
## v0.8：主档坏自动回退 .bak；version 缺失或高于当前版本视为不合格（QA D-3）。
static func load_run() -> Dictionary:
	if not has_save():
		return {}
	var res: Dictionary = _ss().call("load_cfg", SAVE_PATH)
	var cfg: ConfigFile = res.get("cfg") as ConfigFile
	if cfg == null:
		return {}
	var v := int(cfg.get_value("run", "version", -1))
	if v < 0 or v > _ver():
		if int(res.get("source", 0)) == 1:
			var bak := ConfigFile.new()
			if bak.load(SAVE_PATH + ".bak") == OK:
				var bv := int(bak.get_value("run", "version", -1))
				if bv >= 0 and bv <= _ver():
					cfg = bak
					v = bv
		if v < 0 or v > _ver():
			return {}
	var data := {}
	for k in cfg.get_section_keys("run"):
		data[k] = cfg.get_value("run", k)
	data.erase("version")
	return data


## 删除存档（通关/死亡/开始新局时调用）；连 .bak 一并清，防幽灵继续。
static func clear() -> void:
	for p in [SAVE_PATH, SAVE_PATH + ".bak", SAVE_PATH + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


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
	return Lang.t("%s · 第%d层 · Lv.%d") % [Lang.t(cname), fl, lv]
