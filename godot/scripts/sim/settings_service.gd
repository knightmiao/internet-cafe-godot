class_name SettingsService
extends RefCounted
## 玩家偏好：音效音量、全屏、窗口档、切走暂停。测试走独立文件，避免污染本机设置。

const PATH := "user://settings.json"
const TEST_PATH := "user://settings_test.json"
const VIEW_W := 640
const VIEW_H := 360
const SCALE_SMALL := 2
const SCALE_MEDIUM := 3
const SCALE_LARGE := 4

var test_mode := false
var master_volume := 0.8
var muted := false
var fullscreen := false
var window_scale := SCALE_SMALL
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
		"window_scale": window_scale,
		"pause_on_unfocus": pause_on_unfocus,
	}


func apply_dict(data: Dictionary) -> void:
	master_volume = clampf(float(data.get("master_volume", 0.8)), 0.0, 1.0)
	muted = bool(data.get("muted", false))
	fullscreen = bool(data.get("fullscreen", false))
	window_scale = normalize_scale(int(data.get("window_scale", SCALE_SMALL)))
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


func set_window_scale(value: int) -> void:
	window_scale = normalize_scale(value)
	apply_display()
	save_to_disk()


func set_pause_on_unfocus(value: bool) -> void:
	pause_on_unfocus = value
	save_to_disk()


func volume_step() -> int:
	return int(round(master_volume * 10.0))


func apply_audio() -> void:
	var master := AudioServer.get_bus_index("Master")
	if master >= 0:
		AudioServer.set_bus_mute(master, false)
		AudioServer.set_bus_volume_db(master, 0.0)
	var bus := AudioServer.get_bus_index("SFX")
	if bus < 0:
		bus = master
	if bus < 0:
		return
	AudioServer.set_bus_mute(bus, muted or master_volume <= 0.0)
	var linear := 0.0001 if master_volume <= 0.0 else master_volume
	AudioServer.set_bus_volume_db(bus, linear_to_db(linear))


func normalize_scale(value: int) -> int:
	if value >= SCALE_LARGE:
		return SCALE_LARGE
	if value <= SCALE_SMALL:
		return SCALE_SMALL
	return SCALE_MEDIUM


func window_size_for(scale: int) -> Vector2i:
	var s := normalize_scale(scale)
	return Vector2i(VIEW_W * s, VIEW_H * s)


func resolved_window_scale() -> int:
	var requested := normalize_scale(window_scale)
	if test_mode:
		return requested
	var usable := DisplayServer.screen_get_usable_rect(
		DisplayServer.window_get_current_screen()
	)
	var max_scale := maxi(1, mini(
		int(usable.size.x / VIEW_W),
		int(usable.size.y / VIEW_H)
	))
	return mini(requested, max_scale)


func apply_display() -> void:
	if test_mode:
		return
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	var scale := maxi(1, resolved_window_scale())
	var size := Vector2i(VIEW_W * scale, VIEW_H * scale)
	DisplayServer.window_set_size(size)
	var usable := DisplayServer.screen_get_usable_rect(
		DisplayServer.window_get_current_screen()
	)
	var pos := usable.position + (usable.size - size) / 2
	DisplayServer.window_set_position(pos)


func apply_all() -> void:
	apply_audio()
	apply_display()
