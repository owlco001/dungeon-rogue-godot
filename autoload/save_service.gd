extends Node
## SaveService（v0.8 B1 / A8）：存档版本化 + 原子写 + 损坏兜底 + 写盘节流。
## 静态工具供 Meta / RunSave 调用；实例负责 dirty 合并写（0.5s）与关键节点立即写。

const SAVE_VERSION := 3

var _dirty := false
var _t := 0.0
var _flush_cb := Callable()


func _ready() -> void:
	EventBus.save_requested.connect(flush_now)


## 由 Meta 注册落盘回调（解耦：本文件不反向引用 Meta，避免编译期循环依赖）。
func register_flush(cb: Callable) -> void:
	if not _flush_cb.is_valid():
		_flush_cb = cb


func mark_dirty() -> void:
	_dirty = true


func clear_dirty() -> void:
	_dirty = false
	_t = 0.0


func flush_now() -> void:
	if _dirty:
		_dirty = false
		_t = 0.0
		if _flush_cb.is_valid():
			_flush_cb.call()


func _process(delta: float) -> void:
	if not _dirty:
		return
	_t += delta
	if _t >= 0.5:
		flush_now()


## 版本号（Meta/RunSave 经 root 节点动态调用，避免静态类编译期引用 autoload 标识符）。
func version() -> int:
	return SAVE_VERSION


## 原子写：先写 .tmp，旧档备份为 .bak，再 rename 替换。
func atomic_save_cfg(cfg: ConfigFile, path: String) -> bool:
	var tmp := path + ".tmp"
	if cfg.save(tmp) != OK:
		push_error("SaveService: tmp save failed: " + path)
		return false
	var g := ProjectSettings.globalize_path(path)
	var gtmp := ProjectSettings.globalize_path(tmp)
	if FileAccess.file_exists(path):
		DirAccess.copy_absolute(g, g + ".bak")
		DirAccess.remove_absolute(g)
	return DirAccess.rename_absolute(gtmp, g) == OK


## 读取：主档 → .bak 兜底；两者皆坏则把坏主档 dump 为 .corrupt 并返回空。
## 返回 {"cfg": ConfigFile|null, "source": 0=无/坏 1=主档 2=备份}
func load_cfg(path: String) -> Dictionary:
	# 注意：ConfigFile.load 对无节垃圾内容也返回 OK（sections 为空），必须把空节视为损坏。
	var cfg := ConfigFile.new()
	if cfg.load(path) == OK and not cfg.get_sections().is_empty():
		return {"cfg": cfg, "source": 1}
	var bak := ConfigFile.new()
	if FileAccess.file_exists(path + ".bak") and bak.load(path + ".bak") == OK \
			and not bak.get_sections().is_empty():
		return {"cfg": bak, "source": 2}
	if FileAccess.file_exists(path):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(path),
			ProjectSettings.globalize_path(path + ".corrupt"))
	return {"cfg": null, "source": 0}
