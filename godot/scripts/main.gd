extends Control

const CREAM := Color("#ffe9c9")
const GOLD := Color("#b8860b")
const HIGHLIGHT := Color("#ffcf7a")
const PANEL := Color("#3f2a18")
const PANEL_LIGHT := Color("#5c3a20")
const LABEL := Color("#dcc08a")
const INK := Color("#2a1d12")
const OPEN_GREEN := Color("#7ea84e")
const CLOSED_RED := Color("#c0392b")

# 操作区复古电脑皮肤：琥珀单色屏 + 米白塑料键帽
const AMBER_LABEL := Color("#c8912f")
const AMBER_VALUE := Color("#ffc257")
const AMBER_HEAD := Color("#2f2413")
const AMBER_LINE := Color("#6b4a1c")
const CRT_FRAME := Color("#3d3a33")
const KEY_TEXT := Color("#2a2419")
const KEY_TEXT_OFF := Color("#5c584f")
const CASE_INK := Color("#4a4438")

# 语义动作 → icon 文件名。同义动作共用一张图（接待/响应走 serve，收银/结算走 cash）。
# toggle_shop 两态图不同，由 _show_counter 显式传 icon 覆盖。
const ACTION_ICONS := {
	"toggle_shop": "shop_open",
	"serve_customer": "serve",
	"quick_restock": "restock",
	"checkout": "cash",
	"pc_power": "power",
	"pc_clean": "clean",
	"pc_repair": "repair",
	"pc_details": "details",
	"customer_respond": "serve",
	"customer_checkout": "cash",
	"customer_membership": "member",
	"customer_remove": "remove",
	"shelf_restock": "restock",
	"shelf_inventory": "inventory",
	"shelf_pricing": "pricing",
	"shelf_promotion": "promotion",
	"area_preview": "preview",
	"area_plan": "plan",
	"area_requirements": "lock",
}

@onready var topbar: PanelContainer = $TopBar
@onready var stage_container: SubViewportContainer = $Body/Stage
@onready var stage_controller: StageController = $Body/Stage/SubViewport/InitialCafe
@onready var operation_panel: PanelContainer = $Body/OperationPanel

var money: float = 500.0
var is_open: bool = false
var pc_nodes: Array[Dictionary] = []
var day: int = 1
var elapsed: float = 0.0
var selected_kind := "counter"
var selected_index := -1

var title_label: Label
var badge_label: Label
var portrait_texture: TextureRect
var portrait_label: Label
var overview_title: Label
var stat_keys: Array[Label] = []
var stat_values: Array[Label] = []
var stat_lamps: Array[ColorRect] = []
var action_buttons: Array[Button] = []
var current_action_ids: Array[String] = []

func _ready() -> void:
	_connect_stage()
	_build_operation_panel()
	_show_counter()
	topbar.set_unread(true)
	topbar.notify_clicked.connect(func(): _show_placeholder("通知与待办列表待接入"))
	topbar.settings_clicked.connect(func(): _show_placeholder("设置面板待接入"))
	_update_topbar()


func _connect_stage() -> void:
	pc_nodes = stage_controller.pc_data
	stage_controller.object_selected.connect(_on_stage_object_selected)
	stage_controller.background_selected.connect(_show_counter)
	stage_container.gui_input.connect(_on_stage_gui_input)


func _on_stage_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		stage_controller.handle_pointer(event.position)
		stage_container.accept_event()


func _on_stage_object_selected(kind: String, id: int, state: String, zone: String) -> void:
	match kind:
		"pc":
			_show_pc(id)
		"customer":
			_show_customer(id, state)
		"counter":
			_show_counter()
		"shelf":
			_show_shelf()
		"locked":
			_show_locked("电竞高配区", "成长期装修解锁\n8～12 台 · 单价 +1～2 元/时")
		_:
			_show_facility(zone, state)


func _show_facility(name: String, state: String) -> void:
	selected_kind = "facility"
	selected_index = -1
	portrait_texture.visible = false
	portrait_label.visible = true
	title_label.text = name
	badge_label.text = "设"
	portrait_label.text = "【%s】\n%s" % [name, state]
	_set_overview("设施概览", [
		{"key": "设施", "value": name},
		{"key": "状态", "value": state},
	])
	_set_actions([
		_action("pc_details", "详情"),
	])


func _build_operation_panel() -> void:
	# 机身外壳九宫格带 4px 内衬，column 实际可用 152×328。
	operation_panel.add_theme_stylebox_override("panel", _texture_box("panel_case.png", 4))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	operation_panel.add_child(column)

	# 标题条做成机身上的深色铭牌
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

	# CRT 框吃掉上下各 3px，102 保证屏内仍有 96px，插画得以 1:1 显示不被缩放。
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

	portrait_label = _label("", 10, AMBER_VALUE)
	portrait_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	portrait_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	portrait_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	portrait_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_content.add_child(portrait_label)
	column.add_child(portrait)

	# 琥珀单色信息屏：屏框吃 3px，内部 58 = 标题条 14 + 数据行 44。
	var overview := PanelContainer.new()
	overview.custom_minimum_size.y = 64
	overview.add_theme_stylebox_override("panel", _texture_box("amber_frame.png", 3))
	var overview_col := VBoxContainer.new()
	overview_col.add_theme_constant_override("separation", 0)
	overview.add_child(overview_col)

	var overview_head := PanelContainer.new()
	overview_head.custom_minimum_size.y = 14
	overview_head.add_theme_stylebox_override("panel", _box(AMBER_HEAD, AMBER_LINE, 0, 0, 1))
	overview_title = _label("柜台概览", 8, AMBER_VALUE)
	overview_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overview_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	overview_head.add_child(overview_title)
	overview_col.add_child(overview_head)

	var rows := VBoxContainer.new()
	rows.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 0)
	rows.alignment = BoxContainer.ALIGNMENT_CENTER
	for i in range(3):
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

	# 键帽区外面套一层 margin：概览屏和第一行按钮之间必须露出 6px 机身，
	# 否则琥珀屏的深色边框会和键帽描边糊成一条线。
	var actions_wrap := MarginContainer.new()
	actions_wrap.custom_minimum_size.y = 64
	actions_wrap.add_theme_constant_override("margin_top", 6)
	actions_wrap.add_theme_constant_override("margin_bottom", 4)
	actions_wrap.add_theme_constant_override("margin_left", 4)
	actions_wrap.add_theme_constant_override("margin_right", 4)
	var actions := GridContainer.new()
	actions.columns = 2
	actions.add_theme_constant_override("h_separation", 8)
	actions.add_theme_constant_override("v_separation", 6)
	for i in range(4):
		var button := Button.new()
		button.custom_minimum_size = Vector2(68, 24)
		# 不设 SHRINK_CENTER 的话 GridContainer 会把按钮拉满整段高度
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		button.add_theme_font_size_override("font_size", 9)
		button.add_theme_constant_override("h_separation", 3)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_apply_keycap_style(button, "key", 4, 7)
		button.pressed.connect(_on_context_action.bind(i))
		action_buttons.append(button)
		actions.add_child(button)
	actions_wrap.add_child(actions)
	column.add_child(actions_wrap)

	var modules_wrap := MarginContainer.new()
	modules_wrap.custom_minimum_size.y = 78
	modules_wrap.add_theme_constant_override("margin_left", 4)
	modules_wrap.add_theme_constant_override("margin_right", 4)
	var modules := VBoxContainer.new()
	modules.add_theme_constant_override("separation", 4)
	var module_grid := GridContainer.new()
	module_grid.columns = 4
	module_grid.add_theme_constant_override("h_separation", 4)
	module_grid.add_theme_constant_override("v_separation", 3)
	for module_data in [
		{"id": "finance", "label": "财务"},
		{"id": "staff", "label": "人力"},
		{"id": "machines", "label": "机器"},
		{"id": "procurement", "label": "采购"},
		{"id": "events", "label": "事件"},
		{"id": "archive", "label": "档案"},
		{"id": "upgrade", "label": "升级"},
	]:
		var module_id: String = module_data["id"]
		var module_name: String = module_data["label"]
		var module := Button.new()
		module.text = module_name
		module.custom_minimum_size = Vector2(33, 24)
		module.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		module.add_theme_font_size_override("font_size", 8)
		module.tooltip_text = "%s模块（待接入）" % module_name
		_apply_keycap_style(module, "modkey", 2)
		module.pressed.connect(_open_module.bind(module_id, module_name))
		module_grid.add_child(module)
	# 第 8 格明确留空；设置只保留顶栏齿轮。
	var empty_slot := Control.new()
	empty_slot.custom_minimum_size = Vector2(33, 24)
	empty_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	module_grid.add_child(empty_slot)
	modules.add_child(module_grid)

	# 走带键直接压在米白机身上，时钟文字改深墨才看得清。
	var time_row := HBoxContainer.new()
	time_row.custom_minimum_size.y = 22
	time_row.add_theme_constant_override("separation", 3)
	var clock := _label("14:30  午后", 9, CASE_INK)
	clock.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clock.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	time_row.add_child(clock)
	# 字体符号 Ⅱ ▶ ≫ 不是点阵字形，换成像素 icon 才和键帽同风格
	for data in [
		{"icon": "tp_pause", "tip": "暂停"},
		{"icon": "tp_play", "tip": "正常速度"},
		{"icon": "tp_fast", "tip": "快进"},
	]:
		var control := Button.new()
		control.icon = load("res://assets/ui/icons/%s.png" % data["icon"])
		control.tooltip_text = str(data["tip"])
		control.custom_minimum_size = Vector2(24, 20)
		control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_apply_keycap_style(control, "modkey", 2)
		time_row.add_child(control)
	modules.add_child(time_row)
	modules_wrap.add_child(modules)
	column.add_child(modules_wrap)


func _show_counter() -> void:
	selected_kind = "counter"
	selected_index = -1
	title_label.text = "柜台"
	badge_label.text = "台"
	portrait_texture.texture = load("res://assets/ui/portraits/portrait_counter.png")
	portrait_texture.visible = true
	portrait_label.visible = false
	_set_overview("柜台概览", [
		{
			"key": "营业",
			"value": "开店中" if is_open else "未营业",
			"lamp": OPEN_GREEN if is_open else CLOSED_RED,
			"value_color": OPEN_GREEN if is_open else CLOSED_RED,
		},
		{"key": "今日收银", "value": "¥ %d" % max(0, int(money - 500.0))},
	])
	_set_actions([
		_action(
			"toggle_shop",
			"打烊" if is_open else "开店",
			true,
			"shop_close" if is_open else "shop_open"
		),
		_action("serve_customer", "接待"),
		_action("quick_restock", "补货"),
		_action("checkout", "收银"),
	])


func _show_pc(index: int) -> void:
	selected_kind = "pc"
	selected_index = index
	portrait_texture.visible = false
	portrait_label.visible = true
	var state_text: String = pc_nodes[index]["state"]
	var zone: String = pc_nodes[index]["zone"]
	title_label.text = "%d 号机" % (index + 1)
	badge_label.text = "机"
	portrait_label.text = "【机位侧视占位】\n%s" % zone
	_set_overview("机位概览", [
		{"key": "分区", "value": zone},
		{"key": "状态", "value": state_text, "lamp": _state_color(state_text), "value_color": _state_color(state_text)},
		{"key": "预计收益", "value": "¥ 12"},
	])
	var power_label := "开机" if state_text == "已关机" else "关机"
	_set_actions([
		_action("pc_power", power_label, state_text in ["已关机", "空闲"]),
		_action("pc_clean", "清洁", state_text == "待清洁"),
		_action("pc_repair", "维修", state_text == "故障" and money >= 50.0),
		_action("pc_details", "详情"),
	])


func _show_locked(title: String, detail: String) -> void:
	selected_kind = "locked"
	selected_index = -1
	portrait_texture.visible = false
	portrait_label.visible = true
	title_label.text = title
	badge_label.text = "锁"
	portrait_label.text = "【未开放】\n%s" % detail
	_set_overview("区域概览", [
		{"key": "状态", "value": "未装修"},
		{"key": "预计投入", "value": "待定"},
		{"key": "预计台数", "value": "8～12"},
	])
	_set_actions([
		_action("area_preview", "预览"),
		_action("area_plan", "规划"),
		_action("area_requirements", "解锁条件"),
	])


func _show_shelf() -> void:
	selected_kind = "shelf"
	selected_index = -1
	portrait_texture.visible = false
	portrait_label.visible = true
	title_label.text = "小卖部货架"
	badge_label.text = "货"
	portrait_label.text = "【货架特写占位】\n饮料 · 泡面 · 零食"
	_set_overview("库存概览", [
		{"key": "库存", "value": "偏低", "lamp": Color("#d4a017"), "value_color": Color("#d4a017")},
		{"key": "缺货", "value": "3 种"},
		{"key": "今日销售", "value": "¥ 36"},
	])
	_set_actions([
		_action("shelf_restock", "快捷补货"),
		_action("shelf_inventory", "查看库存"),
		_action("shelf_pricing", "调价"),
		_action("shelf_promotion", "促销"),
	])


func _show_customer(index: int, state_text: String) -> void:
	selected_kind = "customer"
	selected_index = index
	portrait_texture.visible = false
	portrait_label.visible = true
	title_label.text = "顾客 %d" % (index + 1)
	badge_label.text = "客"
	portrait_label.text = "【顾客立绘占位】\n心情：满意"
	_set_overview("顾客概览", [
		{"key": "状态", "value": state_text},
		{"key": "会员", "value": "普通"},
		{"key": "消费", "value": "¥ 12"},
	])
	_set_actions([
		_action(
			"customer_respond",
			"接待" if state_text == "排队中" else "响应",
			state_text in ["排队中", "待接待", "要点单", "有需求"]
		),
		_action("customer_checkout", "结算", state_text == "待结账"),
		_action("customer_membership", "办会员"),
		_action("customer_remove", "劝离"),
	])


func _set_overview(title: String, rows: Array) -> void:
	overview_title.text = title
	var row_h := 22 if rows.size() <= 2 else 14
	for i in range(stat_keys.size()):
		var row_node := stat_keys[i].get_parent()
		if i < rows.size():
			var row: Dictionary = rows[i]
			stat_keys[i].text = str(row["key"])
			stat_values[i].text = str(row["value"])
			stat_lamps[i].color = row.get("lamp", Color.TRANSPARENT)
			if row.has("value_color"):
				stat_values[i].add_theme_color_override("font_color", row["value_color"])
			else:
				stat_values[i].add_theme_color_override("font_color", AMBER_VALUE)
			row_node.custom_minimum_size.y = row_h
			row_node.visible = true
		else:
			row_node.visible = false


func _action(id: String, label: String, enabled: bool = true, icon: String = "") -> Dictionary:
	return {"id": id, "label": label, "enabled": enabled, "icon": icon}


func _set_actions(actions: Array) -> void:
	current_action_ids.clear()
	for i in range(action_buttons.size()):
		var button := action_buttons[i]
		if i < actions.size():
			var action: Dictionary = actions[i]
			var action_id := str(action["id"])
			button.text = str(action["label"])
			button.disabled = not action.get("enabled", true)
			button.visible = true
			button.icon = _action_icon(action_id, str(action.get("icon", "")))
			current_action_ids.append(action_id)
		else:
			button.text = ""
			button.icon = null
			button.disabled = true
			button.visible = false
			current_action_ids.append("")


func _action_icon(action_id: String, override_name: String) -> Texture2D:
	var icon_name := override_name if not override_name.is_empty() else str(ACTION_ICONS.get(action_id, ""))
	if icon_name.is_empty():
		return null
	return load("res://assets/ui/icons/%s.png" % icon_name)


func _on_context_action(index: int) -> void:
	if index < 0 or index >= current_action_ids.size():
		return
	var action_id := current_action_ids[index]
	match action_id:
		"toggle_shop":
			is_open = not is_open
			_show_counter()
		_:
			_show_placeholder("%s：功能待接入" % action_buttons[index].text)


func _open_module(module_id: String, module_name: String) -> void:
	if module_id == "upgrade":
		stage_controller.toggle_decor_preview()
		_show_placeholder(
			"装修槽位已%s\n青色虚线为可升级位置"
			% ("显示" if stage_controller.decor_preview else "隐藏")
		)
		return
	_show_placeholder("%s模块待接入\nID: %s" % [module_name, module_id])


func _show_placeholder(message: String) -> void:
	portrait_texture.visible = false
	portrait_label.visible = true
	portrait_label.text = "【功能占位】\n%s" % message


func _process(delta: float) -> void:
	if is_open:
		money += (_online_count() * 0.35 - 0.15) * delta
		elapsed += delta
		if elapsed >= 60.0:
			elapsed = 0.0
			day += 1
	_update_topbar()


func _period() -> String:
	if elapsed < 20.0:
		return "上午"
	if elapsed < 40.0:
		return "下午"
	return "晚上"


func _update_topbar() -> void:
	topbar.set_money(money)
	topbar.set_pc(_online_count(), pc_nodes.size())
	topbar.set_customers(stage_controller.customer_data.size())
	topbar.set_reputation(3.5)
	topbar.set_clean(42)
	topbar.set_decor(50)
	topbar.set_time(day, _period())


func _online_count() -> int:
	var count := 0
	for pc in pc_nodes:
		if pc["state"] == "使用中":
			count += 1
	return count


func _state_color(state_text: String) -> Color:
	match state_text:
		"使用中":
			return Color("#3a8fc5")
		"待清洁":
			return Color("#d4a017")
		"故障":
			return Color("#c0392b")
		_:
			return Color("#7ea84e")


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


# 键帽按钮：米白塑料面，字用深墨。禁用态去掉立体层次并压灰。
# pad_left 用于带 icon 的键帽——Godot 会把 icon 钉在内容区左缘、文字在剩余宽度里居中，
# 所以配合左对齐再留一点左内边距，四颗键的 icon 才会对齐成一列。
func _apply_keycap_style(button: Button, prefix: String, margin: int, pad_left: int = -1) -> void:
	button.add_theme_color_override("font_color", KEY_TEXT)
	button.add_theme_color_override("font_hover_color", KEY_TEXT)
	button.add_theme_color_override("font_pressed_color", KEY_TEXT)
	button.add_theme_color_override("font_disabled_color", KEY_TEXT_OFF)
	# icon 素材是纯白剪影，靠这几个调制色跟着文字一起变深或压灰
	button.add_theme_color_override("icon_normal_color", KEY_TEXT)
	button.add_theme_color_override("icon_hover_color", KEY_TEXT)
	button.add_theme_color_override("icon_pressed_color", KEY_TEXT)
	button.add_theme_color_override("icon_disabled_color", KEY_TEXT_OFF)
	button.add_theme_stylebox_override("normal", _texture_box(prefix + "_normal.png", margin, pad_left))
	button.add_theme_stylebox_override("hover", _texture_box(prefix + "_hover.png", margin, pad_left))
	button.add_theme_stylebox_override(
		"pressed", _texture_box(prefix + "_pressed.png", margin, pad_left)
	)
	var disabled_file := prefix + "_disabled.png"
	if not ResourceLoader.exists("res://assets/ui/panel/" + disabled_file):
		disabled_file = prefix + "_pressed.png"
	button.add_theme_stylebox_override("disabled", _texture_box(disabled_file, margin, pad_left))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


func _box(fill: Color, border: Color, border_width: int = 0, left: int = 0, bottom: int = 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(border_width)
	if left > 0:
		style.border_width_left = left
	if bottom > 0:
		style.border_width_bottom = bottom
	return style
