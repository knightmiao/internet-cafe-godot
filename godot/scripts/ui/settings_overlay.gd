extends Control
class_name SettingsOverlay
## 顶栏齿轮打开的居中设置层。打开时暂停模拟，不挡住顶栏。

signal closed
signal save_requested
signal load_confirmed
signal new_game_confirmed

const GOLD := Color("#b8860b")
const PANEL := Color("#3f2a18")
const AMBER_LABEL := Color("#c8912f")
const AMBER_VALUE := Color("#ffc257")
const AMBER_HEAD := Color("#2f2413")
const AMBER_LINE := Color("#6b4a1c")
const CRT_FRAME := Color("#3d3a33")
const KEY_TEXT := Color("#2a2419")
const KEY_TEXT_OFF := Color("#5c584f")
const CASE_INK := Color("#4a4438")
const CREAM := Color("#ffe9c9")

var settings
var status_text := ""

var _resume_speed := 0.0
var _panel: PanelContainer
var _status: Label
var _volume_label: Label
var _window_btn: Button
var _fullscreen_btn: Button
var _mute_btn: Button
var _unfocus_btn: Button
var _save_info: Label
var _save_btn: Button
var _load_btn: Button
var _new_btn: Button
var _confirm: PanelContainer
var _confirm_title: Label
var _confirm_body: Label
var _confirm_action := ""


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_build()


func is_open() -> bool:
	return visible


func confirm_open() -> bool:
	return _confirm != null and _confirm.visible


func cancel_confirm() -> void:
	_hide_confirm()


func hint_text() -> String:
	return _status.text if _status else ""


func remember_resume_speed(value: float) -> void:
	_resume_speed = value


func open() -> void:
	if visible:
		refresh()
		return
	_resume_speed = float(GameState.clock.speed)
	if _resume_speed > 0.0:
		GameState.clock.set_speed(0.0)
	status_text = ""
	cancel_confirm()
	visible = true
	refresh()


func close() -> void:
	if not visible:
		return
	cancel_confirm()
	visible = false
	if GameState.clock.speed == 0.0 and _resume_speed > 0.0:
		GameState.clock.set_speed(_resume_speed)
	closed.emit()


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func refresh() -> void:
	if settings == null:
		return
	_window_btn.set_pressed_no_signal(not settings.fullscreen)
	_fullscreen_btn.set_pressed_no_signal(settings.fullscreen)
	_mute_btn.set_pressed_no_signal(settings.muted or settings.master_volume <= 0.0)
	_unfocus_btn.set_pressed_no_signal(settings.pause_on_unfocus)
	_volume_label.text = "音量 %d/10" % settings.volume_step()
	_save_info.text = _save_summary()
	_load_btn.disabled = not GameState.has_save()
	_load_btn.tooltip_text = "还没有存档" if _load_btn.disabled else "用最近一次存档覆盖当前店面"
	_status.text = status_text if not status_text.is_empty() else "打开时暂停模拟 · Esc 或齿轮关闭"


func show_status(text: String) -> void:
	status_text = text
	if _status:
		_status.text = text


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(_on_dim_input)
	add_child(dim)

	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.custom_minimum_size = Vector2(384, 240)
	_panel.add_theme_stylebox_override("panel", _texture_box("panel_case.png", 4))
	_center_panel(_panel, Vector2(384, 240))
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)

	var pad := MarginContainer.new()
	for name in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		pad.add_theme_constant_override(name, 6)
	_panel.add_child(pad)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	pad.add_child(column)

	column.add_child(_title_bar())
	_status = _label("打开时暂停模拟 · Esc 或齿轮关闭", 8, AMBER_LABEL)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_status)

	column.add_child(_option_row("显示", _display_buttons()))
	column.add_child(_option_row("声音", _audio_buttons()))
	column.add_child(_option_row("后台", _focus_buttons()))

	_save_info = _label("", 8, AMBER_VALUE)
	_save_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_save_info)

	var archive := HBoxContainer.new()
	archive.add_theme_constant_override("separation", 4)
	archive.alignment = BoxContainer.ALIGNMENT_CENTER
	_save_btn = _key("立即存档", Vector2(88, 22))
	_save_btn.pressed.connect(_on_save_pressed)
	_load_btn = _key("读取存档", Vector2(88, 22))
	_load_btn.pressed.connect(_on_load_pressed)
	_new_btn = _key("重新开局", Vector2(88, 22))
	_new_btn.pressed.connect(_on_new_pressed)
	archive.add_child(_save_btn)
	archive.add_child(_load_btn)
	archive.add_child(_new_btn)
	column.add_child(archive)

	var back := _key("返回游戏", Vector2(160, 24))
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(close)
	var back_wrap := HBoxContainer.new()
	back_wrap.alignment = BoxContainer.ALIGNMENT_CENTER
	back_wrap.add_child(back)
	column.add_child(back_wrap)

	_build_confirm()


func _title_bar() -> PanelContainer:
	var bar := PanelContainer.new()
	bar.custom_minimum_size.y = 20
	bar.add_theme_stylebox_override("panel", _box(CRT_FRAME, CASE_INK, 1))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	bar.add_child(row)
	var title := _label("设置", 10, AMBER_VALUE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "×"
	close_btn.tooltip_text = "关闭"
	close_btn.custom_minimum_size = Vector2(16, 16)
	close_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close_btn.add_theme_font_size_override("font_size", 10)
	_apply_keycap_style(close_btn, "modkey", 2)
	close_btn.pressed.connect(close)
	row.add_child(close_btn)
	return bar


func _option_row(caption: String, controls: HBoxContainer) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.custom_minimum_size.y = 22
	var label := _label(caption, 9, AMBER_LABEL)
	label.custom_minimum_size.x = 36
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(controls)
	return row


func _display_buttons() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	_window_btn = _toggle("窗口", Vector2(64, 20))
	_fullscreen_btn = _toggle("全屏", Vector2(64, 20))
	_window_btn.pressed.connect(func(): _set_fullscreen(false))
	_fullscreen_btn.pressed.connect(func(): _set_fullscreen(true))
	row.add_child(_window_btn)
	row.add_child(_fullscreen_btn)
	return row


func _audio_buttons() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var minus := _key("－", Vector2(22, 20))
	minus.pressed.connect(func(): _nudge_volume(-0.1))
	_volume_label = _label("音量 8/10", 9, AMBER_VALUE)
	_volume_label.custom_minimum_size.x = 72
	_volume_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_volume_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var plus := _key("＋", Vector2(22, 20))
	plus.pressed.connect(func(): _nudge_volume(0.1))
	_mute_btn = _toggle("静音", Vector2(48, 20))
	_mute_btn.pressed.connect(func(): settings.set_muted(not settings.muted))
	_mute_btn.pressed.connect(refresh)
	row.add_child(minus)
	row.add_child(_volume_label)
	row.add_child(plus)
	row.add_child(_mute_btn)
	return row


func _focus_buttons() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	_unfocus_btn = _toggle("切走暂停", Vector2(88, 20))
	_unfocus_btn.tooltip_text = "窗口失焦时自动暂停营业时间"
	_unfocus_btn.pressed.connect(func():
		settings.set_pause_on_unfocus(not settings.pause_on_unfocus)
		refresh()
	)
	row.add_child(_unfocus_btn)
	var hint := _label("失焦时停表", 8, AMBER_LABEL)
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(hint)
	return row


func _build_confirm() -> void:
	_confirm = PanelContainer.new()
	_confirm.visible = false
	_confirm.custom_minimum_size = Vector2(288, 160)
	_confirm.add_theme_stylebox_override("panel", _texture_box("panel_case.png", 4))
	_center_panel(_confirm, Vector2(288, 160))
	_confirm.z_index = 2
	_confirm.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_confirm)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	_confirm.add_child(column)
	_confirm_title = _label("请确认", 10, AMBER_VALUE)
	_confirm_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_confirm_title)
	_confirm_body = _label("", 9, CREAM)
	_confirm_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirm_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_confirm_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_confirm_body)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	var cancel := _key("取消", Vector2(72, 24))
	cancel.pressed.connect(_hide_confirm)
	var ok := _key("确认", Vector2(72, 24))
	ok.pressed.connect(_accept_confirm)
	actions.add_child(cancel)
	actions.add_child(ok)
	column.add_child(actions)


func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _confirm.visible:
			_hide_confirm()
		else:
			close()


func _nudge_volume(delta: float) -> void:
	settings.set_master_volume(settings.master_volume + delta)
	refresh()


func _set_fullscreen(value: bool) -> void:
	settings.set_fullscreen(value)
	refresh()


func _on_save_pressed() -> void:
	save_requested.emit()


func _on_load_pressed() -> void:
	if not GameState.has_save():
		show_status("还没有可读取的存档")
		return
	_ask_confirm(
		"load",
		"读取存档",
		"用最近一次存档覆盖当前店面。今天还没关店的进度会丢掉。"
	)


func _on_new_pressed() -> void:
	_ask_confirm(
		"new",
		"重新开局",
		"从 800 元、第 1 天再开一家店。当前店面和未日结进度都会清空，并写成新存档。"
	)


func _ask_confirm(action: String, title: String, body: String) -> void:
	_confirm_action = action
	_confirm_title.text = title
	_confirm_body.text = body
	_confirm.visible = true


func _hide_confirm() -> void:
	_confirm_action = ""
	if _confirm:
		_confirm.visible = false


func _accept_confirm() -> void:
	var action := _confirm_action
	_hide_confirm()
	if action == "load":
		load_confirmed.emit()
	elif action == "new":
		new_game_confirmed.emit()


func _save_summary() -> String:
	if GameState.has_save():
		return "存档：第 %d 天 · %s · 资金 ¥%d" % [
			GameState.day, _phase_label(), int(GameState.money)
		]
	return "还没有存档 · 当前第 %d 天 · %s" % [GameState.day, _phase_label()]


func _phase_label() -> String:
	match GameState.business_phase:
		"open":
			return "营业中"
		"closing":
			return "收尾中"
		_:
			return "休息中"


func _key(text: String, minimum: Vector2) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = minimum
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.add_theme_font_size_override("font_size", 9)
	_apply_keycap_style(button, "key", 4)
	return button


func _toggle(text: String, minimum: Vector2) -> Button:
	var button := _key(text, minimum)
	button.toggle_mode = true
	_apply_keycap_style(button, "modkey", 2)
	return button


func _center_panel(panel: Control, size: Vector2) -> void:
	panel.set_anchors_preset(PRESET_CENTER)
	panel.offset_left = -size.x * 0.5
	panel.offset_top = -size.y * 0.5
	panel.offset_right = size.x * 0.5
	panel.offset_bottom = size.y * 0.5


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _texture_box(file: String, margin: int) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = load("res://assets/ui/panel/" + file)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		style.set_texture_margin(side, margin)
	return style


func _apply_keycap_style(button: Button, prefix: String, margin: int) -> void:
	for name in ["font_color", "font_hover_color", "font_pressed_color"]:
		button.add_theme_color_override(name, KEY_TEXT)
	button.add_theme_color_override("font_disabled_color", KEY_TEXT_OFF)
	for state in ["normal", "hover", "pressed"]:
		button.add_theme_stylebox_override(
			state, _texture_box("%s_%s.png" % [prefix, state], margin)
		)
	var disabled_file := "%s_disabled.png" % prefix
	if not ResourceLoader.exists("res://assets/ui/panel/" + disabled_file):
		disabled_file = "%s_pressed.png" % prefix
	button.add_theme_stylebox_override("disabled", _texture_box(disabled_file, margin))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


func _box(fill: Color, border: Color, border_width: int = 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(border_width)
	return style
