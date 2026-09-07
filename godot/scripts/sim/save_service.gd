class_name SaveService
extends RefCounted
## 把经营快照写到 user://，测试走独立文件以免污染本机存档。

var path := "user://save.json"


func set_test_mode(enabled: bool) -> void:
	path = "user://save_test.json" if enabled else "user://save.json"


func has_save() -> bool:
	return FileAccess.file_exists(path)


func write(data: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data, "\t"))
	return true


func read() -> Dictionary:
	if not has_save():
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}


func clear() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
