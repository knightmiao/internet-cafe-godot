class_name SettingsService
extends RefCounted
## 玩家偏好：音量、全屏、切走暂停。测试走独立文件，避免污染本机设置。

const PATH := "user://settings.json"
const TEST_PATH := "user://settings_test.json"

var test_mode := false
var master_volume := 0.8
var muted := false
var fullscreen := false
var pause_on_unfocus := true


func path() -> String:
	return TEST_PATH if test_mode else PATH


func load_from_disk() -> void:
	if not FileAccess.file_exists(path()):
		return
	var file := FileAccess.open(path(), FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		apply_dict(parsed)


func save_to_disk() -> bool:
	var file := FileAccess.open(path(), FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(to_dict(), "\t"))
	return true


func to_dict() -> Dictionary:
	return {
		"master_volume": master_volume,
		"muted": muted,
		"fullscreen": fullscreen,
		"pause_on_unfocus": pause_on_unfocus,
	}


func apply_dict(data: Dictionary) -> void:
	master_volume = clampf(float(data.get("master_volume", 0.8)), 0.0, 1.0)
	muted = bool(data.get("muted", false))
	fullscreen = bool(data.get("fullscreen", false))
	pause_on_unfocus = bool(data.get("pause_on_unfocus", true))


func set_master_volume(value: float) -> void:
	master_volume = clampf(snappedf(value, 0.1), 0.0, 1.0)
	if master_volume > 0.0:
		muted = false
	apply_audio()
	save_to_disk()


func set_muted(value: bool) -> void:
	muted = value
	apply_audio()
	save_to_disk()


func set_fullscreen(value: bool) -> void:
	fullscreen = value
	apply_display()
	save_to_disk()


func set_pause_on_unfocus(value: bool) -> void:
	pause_on_unfocus = value
	save_to_disk()


func volume_step() -> int:
	return int(round(master_volume * 10.0))


func apply_audio() -> void:
	var bus := AudioServer.get_bus_index("Master")
	if bus < 0:
		return
	AudioServer.set_bus_mute(bus, muted or master_volume <= 0.0)
	var linear := 0.0001 if master_volume <= 0.0 else master_volume
	AudioServer.set_bus_volume_db(bus, linear_to_db(linear))


func apply_display() -> void:
	if test_mode:
		return
	var mode := (
		DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen
		else DisplayServer.WINDOW_MODE_WINDOWED
	)
	DisplayServer.window_set_mode(mode)


func apply_all() -> void:
	apply_audio()
	apply_display()
