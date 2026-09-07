extends PanelContainer
class_name OperationPanelUI

signal action_requested(action_id: String)
signal module_requested(module_id: String)
signal speed_requested(speed: float)

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

const ACTION_ICONS := {
	"open_shop": "shop_open", "stop_admission": "shop_close",
	"close_settlement": "cash", "opening_check": "inventory",
	"review_report": "details", "focus_reception": "serve",
	"focus_checkout": "cash", "back_module": "remove",
	"toggle_shop": "shop_open", "serve_customer": "serve",
	"quick_restock": "restock", "checkout": "cash",
	"pc_power": "power", "pc_clean": "clean", "pc_repair": "repair",
	"pc_details": "details", "customer_respond": "serve",
	"customer_checkout": "cash", "customer_membership": "member",
	"customer_remove": "remove", "shelf_restock": "restock",
	"shelf_inventory": "inventory", "shelf_pricing": "pricing",
	"shelf_promotion": "promotion", "area_preview": "preview",
	"area_plan": "plan", "area_requirements": "lock",
	"decor_prev": "plan", "decor_buy_install": "cash",
	"decor_next": "details", "decor_exit": "remove",
}

var title_label: Label
var badge_label: Label
var portrait_texture: TextureRect
var portrait_label: Label
var overview_title: Label
var stat_keys: Array[Label] = []
var stat_values: Array[Label] = []
var stat_lamps: Array[ColorRect] = []
var action_buttons: Array[Button] = []
var module_buttons: Dictionary = {}
var clock_label: Label
var speed_buttons: Dictionary = {}

var _normal_actions: GridContainer
var _normal_buttons: Array[Button] = []
var _counter_actions: VBoxContainer
var _counter_buttons: Array[Button] = []
var _module_grid: GridContainer


func _ready() -> void:
	_build()


func _build() -> void:
	add_theme_stylebox_override("panel", _texture_box("panel_case.png", 4))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	add_child(column)

	var title_bar := PanelContainer.new()
	title_bar.custom_minimum_size.y = 20
	title_bar.add_theme_stylebox_override("panel", _box(CRT_FRAME, CASE_INK, 1))
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 4)
	title_bar.add_child(title_row)
	title_label = _label("柜台", 10, AMBER_VALUE)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title_label)
	badge_label = _label("台", 8, PANEL)
	badge_label.custom_minimum_size.x = 18
	badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge_label.add_theme_stylebox_override("normal", _box(GOLD, Color.TRANSPARENT))
	title_row.add_child(badge_label)
	column.add_child(title_bar)

	var portrait := PanelContainer.new()
	portrait.custom_minimum_size.y = 102
	portrait.add_theme_stylebox_override("panel", _texture_box("screen_frame.png", 3))
	var portrait_content := Control.new()
	portrait_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.add_child(portrait_content)
	portrait_texture = TextureRect.new()
	portrait_texture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	portrait_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait_texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_content.add_child(portrait_texture)
	portrait_label = _label("", 9, AMBER_VALUE)
	portrait_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	portrait_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	portrait_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	portrait_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	portrait_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_content.add_child(portrait_label)
	column.add_child(portrait)

	var overview := PanelContainer.new()
	overview.custom_minimum_size.y = 64
	overview.add_theme_stylebox_override("panel", _texture_box("amber_frame.png", 3))
	var overview_col := VBoxContainer.new()
	overview_col.add_theme_constant_override("separation", 0)
	overview.add_child(overview_col)
	var overview_head := PanelContainer.new()
	overview_head.custom_minimum_size.y = 14
	overview_head.add_theme_stylebox_override("panel", _box(AMBER_HEAD, AMBER_LINE, 0, 0, 1))
	overview_title = _label("经营概览", 8, AMBER_VALUE)
	overview_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overview_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	overview_head.add_child(overview_title)
	overview_col.add_child(overview_head)
	var rows := VBoxContainer.new()
	rows.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 0)
	rows.alignment = BoxContainer.ALIGNMENT_CENTER
	for _i in range(3):
		var row := HBoxContainer.new()
		row.custom_minimum_size.y = 14
		row.add_theme_constant_override("separation", 4)
		var lamp := ColorRect.new()
		lamp.custom_minimum_size = Vector2(5, 5)
		lamp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		lamp.color = Color.TRANSPARENT
		stat_lamps.append(lamp)
		row.add_child(lamp)
		var key := _label("", 8, AMBER_LABEL)
		key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stat_keys.append(key)
		row.add_child(key)
		var value := _label("", 9, AMBER_VALUE)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		stat_values.append(value)
		row.add_child(value)
		rows.add_child(row)
	var rows_wrap := MarginContainer.new()
	rows_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows_wrap.add_theme_constant_override("margin_left", 6)
	rows_wrap.add_theme_constant_override("margin_right", 6)
	rows_wrap.add_child(rows)
	overview_col.add_child(rows_wrap)
	column.add_child(overview)

	var actions_wrap := MarginContainer.new()
	actions_wrap.custom_minimum_size.y = 64
	for pair in [["margin_top", 6], ["margin_bottom", 4], ["margin_left", 4], ["margin_right", 4]]:
		actions_wrap.add_theme_constant_override(pair[0], pair[1])
	var action_stack := Control.new()
	actions_wrap.add_child(action_stack)
	_normal_actions = GridContainer.new()
	_normal_actions.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_normal_actions.columns = 2
	_normal_actions.add_theme_constant_override("h_separation", 8)
	_normal_actions.add_theme_constant_override("v_separation", 6)
	for _i in range(4):
		_normal_buttons.append(_make_action_button(Vector2(68, 24), _normal_actions))
	action_stack.add_child(_normal_actions)
	_counter_actions = VBoxContainer.new()
	_counter_actions.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_counter_actions.add_theme_constant_override("separation", 6)
	var primary := _make_action_button(Vector2(144, 24), _counter_actions)
	primary.alignment = HORIZONTAL_ALIGNMENT_CENTER
	var secondary := HBoxContainer.new()
	secondary.add_theme_constant_override("separation", 8)
	_counter_actions.add_child(secondary)
	_counter_buttons.append(primary)
	_counter_buttons.append(_make_action_button(Vector2(68, 24), secondary))
	_counter_buttons.append(_make_action_button(Vector2(68, 24), secondary))
	action_stack.add_child(_counter_actions)
	column.add_child(actions_wrap)

	var modules_wrap := MarginContainer.new()
	modules_wrap.custom_minimum_size.y = 78
	modules_wrap.add_theme_constant_override("margin_left", 4)
	modules_wrap.add_theme_constant_override("margin_right", 4)
	var modules := VBoxContainer.new()
	modules.add_theme_constant_override("separation", 4)
	_module_grid = GridContainer.new()
	_module_grid.columns = 4
	_module_grid.add_theme_constant_override("h_separation", 4)
	_module_grid.add_theme_constant_override("v_separation", 3)
	modules.add_child(_module_grid)
	var time_row := HBoxContainer.new()
	time_row.custom_minimum_size.y = 22
	time_row.add_theme_constant_override("separation", 3)
	clock_label = _label("10:00  上午", 9, CASE_INK)
	clock_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clock_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	time_row.add_child(clock_label)
	for data in [
		{"icon": "tp_pause", "tip": "暂停", "speed": 0.0},
		{"icon": "tp_play", "tip": "正常速度", "speed": 1.0},
		{"icon": "tp_fast", "tip": "快进", "speed": 2.0},
	]:
		var control := Button.new()
		control.icon = load("res://assets/ui/icons/%s.png" % data["icon"])
		control.tooltip_text = str(data["tip"])
		control.custom_minimum_size = Vector2(24, 20)
		control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		control.toggle_mode = true
		_apply_keycap_style(control, "modkey", 2)
		control.pressed.connect(_on_speed_pressed.bind(float(data["speed"])))
		speed_buttons[data["speed"]] = control
		time_row.add_child(control)
	modules.add_child(time_row)
	modules_wrap.add_child(modules)
	column.add_child(modules_wrap)
	set_counter_layout(false)
	action_buttons = _normal_buttons
	set_speed_highlight(1.0)


func _make_action_button(minimum: Vector2, parent: Container) -> Button:
	var button := Button.new()
	button.custom_minimum_size = minimum
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.add_theme_font_size_override("font_size", 9)
	button.add_theme_constant_override("h_separation", 3)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_apply_keycap_style(button, "key", 4, 7)
	button.pressed.connect(_on_action_pressed.bind(button))
	parent.add_child(button)
	return button


func configure_modules(modules: Array) -> void:
	for child in _module_grid.get_children():
		child.free()
	module_buttons.clear()
	for module in modules:
		var button := Button.new()
		var module_id := str(module["id"])
		button.text = str(module["label"])
		var icon_path := "res://assets/ui/icons/%s.png" % module["icon"]
		button.icon = load(icon_path) if ResourceLoader.exists(icon_path) else null
		button.custom_minimum_size = Vector2(33, 24)
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		button.add_theme_font_size_override("font_size", 8)
		button.add_theme_constant_override("h_separation", 1)
		button.tooltip_text = str(module["summary"])
		button.toggle_mode = true
		_apply_keycap_style(button, "modkey", 2)
		button.pressed.connect(_on_module_pressed.bind(module_id))
		_module_grid.add_child(button)
		module_buttons[module_id] = button


func set_active_module(module_id: String) -> void:
	for id in module_buttons:
		(module_buttons[id] as Button).set_pressed_no_signal(str(id) == module_id)


func set_clock_text(text: String) -> void:
	if clock_label:
		clock_label.text = text


func set_speed_highlight(speed: float) -> void:
	for value in speed_buttons:
		(speed_buttons[value] as Button).set_pressed_no_signal(is_equal_approx(float(value), speed))


func set_title(text: String, badge: String) -> void:
	title_label.text = text
	badge_label.text = badge


func show_portrait(path: String) -> void:
	portrait_texture.texture = load(path) if not path.is_empty() else null
	portrait_texture.visible = not path.is_empty()
	portrait_label.visible = path.is_empty()


func show_portrait_text(text: String) -> void:
	portrait_texture.visible = false
	portrait_label.visible = true
	portrait_label.text = text


func set_overview(title: String, rows: Array) -> void:
	overview_title.text = title
	var row_h := 22 if rows.size() <= 2 else 14
	for i in range(stat_keys.size()):
		var row_node := stat_keys[i].get_parent()
		if i < rows.size():
			var row: Dictionary = rows[i]
			stat_keys[i].text = str(row["key"])
			stat_values[i].text = str(row["value"])
			stat_lamps[i].color = row.get("lamp", Color.TRANSPARENT)
			stat_values[i].add_theme_color_override(
				"font_color", row.get("value_color", AMBER_VALUE)
			)
			row_node.custom_minimum_size.y = row_h
			row_node.visible = true
		else:
			row_node.visible = false


func set_actions(actions: Array, counter_layout := false) -> void:
	set_counter_layout(counter_layout)
	action_buttons = _counter_buttons if counter_layout else _normal_buttons
	for i in range(action_buttons.size()):
		var button := action_buttons[i]
		if i < actions.size():
			var action: Dictionary = actions[i]
			var action_id := str(action["id"])
			button.text = str(action["label"])
			button.disabled = not action.get("enabled", true)
			button.visible = true
			button.set_meta("action_id", action_id)
			button.icon = _action_icon(action_id, str(action.get("icon", "")))
		else:
			button.text = ""
			button.icon = null
			button.disabled = true
			button.visible = false
			button.set_meta("action_id", "")


func set_counter_layout(enabled: bool) -> void:
	_counter_actions.visible = enabled
	_normal_actions.visible = not enabled


func _on_action_pressed(button: Button) -> void:
	var action_id := str(button.get_meta("action_id", ""))
	if not action_id.is_empty():
		action_requested.emit(action_id)


func _on_module_pressed(module_id: String) -> void:
	module_requested.emit(module_id)


func _on_speed_pressed(speed: float) -> void:
	set_speed_highlight(speed)
	speed_requested.emit(speed)


func _action_icon(action_id: String, override_name: String) -> Texture2D:
	var icon_name := override_name if not override_name.is_empty() else str(ACTION_ICONS.get(action_id, "details"))
	return load("res://assets/ui/icons/%s.png" % icon_name)


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _texture_box(file: String, margin: int, pad_left: int = -1) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = load("res://assets/ui/panel/" + file)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		style.set_texture_margin(side, margin)
	if pad_left >= 0:
		style.set_content_margin(SIDE_LEFT, pad_left)
	return style


func _apply_keycap_style(button: Button, prefix: String, margin: int, pad_left: int = -1) -> void:
	for name in ["font_color", "font_hover_color", "font_pressed_color"]:
		button.add_theme_color_override(name, KEY_TEXT)
	button.add_theme_color_override("font_disabled_color", KEY_TEXT_OFF)
	for name in ["icon_normal_color", "icon_hover_color", "icon_pressed_color"]:
		button.add_theme_color_override(name, KEY_TEXT)
	button.add_theme_color_override("icon_disabled_color", KEY_TEXT_OFF)
	for state in ["normal", "hover", "pressed"]:
		button.add_theme_stylebox_override(
			state, _texture_box("%s_%s.png" % [prefix, state], margin, pad_left)
		)
	var disabled_file := "%s_disabled.png" % prefix
	if not ResourceLoader.exists("res://assets/ui/panel/" + disabled_file):
		disabled_file = "%s_pressed.png" % prefix
	button.add_theme_stylebox_override(
		"disabled", _texture_box(disabled_file, margin, pad_left)
	)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


func _box(fill: Color, border: Color, border_width: int = 0,
		left: int = 0, bottom: int = 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(border_width)
	if left > 0:
		style.border_width_left = left
	if bottom > 0:
		style.border_width_bottom = bottom
	return style
