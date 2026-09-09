extends Control
class_name InboxOverlay
## 顶栏铃打开的消息层：待办列表、事件结果、必须点选的决策。

signal closed
signal choice_requested(choice_id: String)
signal jump_requested(jump: String)

const AMBER_LABEL := Color("#c8912f")
const AMBER_VALUE := Color("#ffc257")
const CRT_FRAME := Color("#3d3a33")
const KEY_TEXT := Color("#2a2419")
const KEY_TEXT_OFF := Color("#5c584f")
const CASE_INK := Color("#4a4438")
const CREAM := Color("#ffe9c9")

var _resume_speed := 0.0
var _holding_pause := false
var _mode := ""
var _panel: PanelContainer
var _title: Label
var _body: Label
var _list: VBoxContainer
var _actions: HBoxContainer
var _close_btn: Button
var _detail_id := ""


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_build()


func is_open() -> bool:
	return visible


func is_decision() -> bool:
	return visible and _mode == "decision"


func title_text() -> String:
	return _title.text if _title else ""


func body_text() -> String:
	return _body.text if _body else ""


func open_list(rows: Array) -> void:
	_mode = "list"
	_detail_id = ""
	_pause_sim()
	_title.text = "消息"
	_close_btn.visible = true
	_render_list(rows)
	visible = true
	_play_sfx("ui_open")


func show_decision(event: Dictionary) -> void:
	if event.is_empty():
		return
	_mode = "decision"
	_detail_id = ""
	_pause_sim()
	_title.text = str(event.get("title", "事件"))
	_body.text = str(event.get("body", ""))
	_body.visible = true
	_list.visible = false
	_close_btn.visible = false
	_fill_choices(event.get("choices", []))
	visible = true
	_play_sfx("ui_open")


func show_detail(item: Dictionary) -> void:
	_mode = "detail"
	_detail_id = str(item.get("id", ""))
	_title.text = str(item.get("title", "消息"))
	_body.text = _detail_body(item)
	_body.visible = true
	_list.visible = false
	_close_btn.visible = true
	_clear_actions()
	var back := _key("返回", Vector2(72, 24))
	back.pressed.connect(func(): open_list(GameState.inbox_rows()))
	_actions.add_child(back)
	if not visible:
		_pause_sim()
		visible = true
		_play_sfx("ui_open")


func close() -> void:
	if not visible:
		return
	if _mode == "decision":
		return
	visible = false
	_mode = ""
	_resume_sim()
	_play_sfx("ui_close")
	closed.emit()


func close_after_resolve() -> void:
	visible = false
	_mode = ""
	_resume_sim()
	closed.emit()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(_on_dim_input)
	add_child(dim)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(320, 200)
	_panel.add_theme_stylebox_override("panel", _texture_box("panel_case.png", 4))
	_center_panel(_panel, Vector2(320, 200))
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)

	var pad := MarginContainer.new()
	for name in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		pad.add_theme_constant_override(name, 6)
	_panel.add_child(pad)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	pad.add_child(column)

	var bar := HBoxContainer.new()
	_title = _label("消息", 10, AMBER_VALUE)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(_title)
	_close_btn = Button.new()
	_close_btn.text = "×"
	_close_btn.tooltip_text = "关闭"
	_close_btn.custom_minimum_size = Vector2(16, 16)
	_close_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_close_btn.add_theme_font_size_override("font_size", 10)
	_apply_keycap_style(_close_btn, "modkey", 2)
	_close_btn.pressed.connect(close)
	bar.add_child(_close_btn)
	column.add_child(bar)

	_body = _label("", 8, CREAM)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_body)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 3)
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_list)

	_actions = HBoxContainer.new()
	_actions.add_theme_constant_override("separation", 6)
	_actions.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(_actions)


func _render_list(rows: Array) -> void:
	_body.visible = false
	_list.visible = true
	_clear_children(_list)
	_clear_actions()
	if rows.is_empty():
		var empty := _label("没有新消息。脏机和故障会列在这里。", 8, AMBER_LABEL)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list.add_child(empty)
		return
	var shown := 0
	for row in rows:
		if shown >= 5:
			break
		_list.add_child(_row_button(row))
		shown += 1


func _row_button(row: Dictionary) -> Button:
	var unread := bool(row.get("unread", false))
	var prefix := "· " if unread else "  "
	var button := _key("%s%s" % [prefix, str(row.get("title", ""))], Vector2(300, 22))
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.pressed.connect(_on_row_pressed.bind(row))
	return button


func _on_row_pressed(row: Dictionary) -> void:
	_play_sfx("ui_click")
	var jump := str(row.get("jump", ""))
	if not jump.is_empty():
		close()
		jump_requested.emit(jump)
		return
	var item_id := str(row.get("id", ""))
	if not item_id.is_empty():
		GameState.mark_inbox_read(item_id)
	show_detail(row)


func _fill_choices(choices: Array) -> void:
	_clear_actions()
	for choice in choices:
		var choice_id := str(choice.get("id", ""))
		var button := _key(str(choice.get("label", "确定")), Vector2(88, 24))
		button.pressed.connect(_on_choice.bind(choice_id))
		_actions.add_child(button)


func _on_choice(choice_id: String) -> void:
	_play_sfx("ui_confirm")
	choice_requested.emit(choice_id)


func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _mode != "decision":
			close()


func _detail_body(item: Dictionary) -> String:
	var day := int(item.get("day", 0))
	var minute := int(item.get("minute", 0))
	var stamp := ""
	if day > 0:
		stamp = "第%d天 · %d:%02d\n" % [day, 10 + minute / 60, minute % 60]
	return stamp + str(item.get("body", ""))


func _pause_sim() -> void:
	if _holding_pause:
		return
	_resume_speed = float(GameState.clock.speed)
	_holding_pause = true
	if _resume_speed > 0.0:
		GameState.clock.set_speed(0.0)


func _resume_sim() -> void:
	if not _holding_pause:
		return
	_holding_pause = false
	if GameState.clock.speed == 0.0 and _resume_speed > 0.0:
		GameState.clock.set_speed(_resume_speed)


func _clear_actions() -> void:
	_clear_children(_actions)


func _clear_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.free()


func _center_panel(panel: Control, size: Vector2) -> void:
	panel.set_anchors_preset(PRESET_CENTER)
	panel.offset_left = -size.x * 0.5
	panel.offset_top = -size.y * 0.5
	panel.offset_right = size.x * 0.5
	panel.offset_bottom = size.y * 0.5


func _key(text: String, minimum: Vector2) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = minimum
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.add_theme_font_size_override("font_size", 9)
	_apply_keycap_style(button, "key", 4)
	return button


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


func _play_sfx(cue_id: String) -> void:
	var sfx := get_node_or_null("/root/Sfx")
	if sfx:
		sfx.play(cue_id)
