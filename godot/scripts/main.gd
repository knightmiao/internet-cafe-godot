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
const OPERATION_DATA_PATH := "res://data/operation_modules.json"

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
	"decor_prev": "plan",
	"decor_buy_install": "cash",
	"decor_next": "details",
	"decor_exit": "remove",
}

@onready var topbar: PanelContainer = $TopBar
@onready var stage_container: SubViewportContainer = $Body/Stage
@onready var stage_controller: StageController = $Body/Stage/SubViewport/InitialCafe
@onready var operation_panel: OperationPanelUI = $Body/OperationPanel

var money: float = 500.0
var is_open: bool = false
var pc_nodes: Array[Dictionary] = []
var day: int = 1
var elapsed: float = 0.0
var selected_kind := "counter"
var selected_index := -1
var player_level := 3
var selected_decor_slot := -1
var selected_decor_cursor := 0
var selected_decor_options: Array = []
var operation_data: Dictionary = {}
var operation_modules: Array = []
var operation_modules_by_id: Dictionary = {}

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
	_load_operation_data()
	_bind_operation_panel()
	_show_counter()
	topbar.set_unread(true)
	topbar.notify_clicked.connect(func(): _show_placeholder("通知与待办列表待接入"))
	topbar.settings_clicked.connect(func(): _show_placeholder("设置面板待接入"))
	_update_topbar()


func _load_operation_data() -> void:
	var file := FileAccess.open(OPERATION_DATA_PATH, FileAccess.READ)
	assert(file != null, "无法读取操作区目录：%s" % OPERATION_DATA_PATH)
	var parsed = JSON.parse_string(file.get_as_text())
	assert(parsed is Dictionary and parsed["modules"].size() == 8)
	operation_data = parsed
	operation_modules = operation_data["modules"]
	for module in operation_modules:
		operation_modules_by_id[str(module["id"])] = module


func _bind_operation_panel() -> void:
	title_label = operation_panel.title_label
	badge_label = operation_panel.badge_label
	portrait_texture = operation_panel.portrait_texture
	portrait_label = operation_panel.portrait_label
	overview_title = operation_panel.overview_title
	stat_keys = operation_panel.stat_keys
	stat_values = operation_panel.stat_values
	stat_lamps = operation_panel.stat_lamps
	action_buttons = operation_panel.action_buttons
	operation_panel.configure_modules(operation_modules)
	operation_panel.action_requested.connect(_on_action_requested)
	operation_panel.module_requested.connect(_open_module)


func _connect_stage() -> void:
	pc_nodes = stage_controller.pc_data
	stage_controller.object_selected.connect(_on_stage_object_selected)
	stage_controller.background_selected.connect(_show_counter)
	stage_container.gui_input.connect(_on_stage_gui_input)


func _on_stage_gui_input(event: InputEvent) -> void:
	# 场景自己处理点选、拖拽平移和滚轮缩放，这里只负责把事件送进去
	stage_controller.handle_input(event)
	if event is InputEventMouseButton or event is InputEventMouseMotion:
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
		"decor_slot":
			_show_decor_slot(id)
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
	], true)


func _show_pc(index: int) -> void:
	selected_kind = "pc"
	selected_index = index
	var state_text: String = pc_nodes[index]["state"]
	var config := stage_controller.get_pc_config(index)
	portrait_texture.texture = load(str(config.get(
		"portrait", "res://assets/ui/portraits/portrait_pc_gen_09.png"
	)))
	portrait_texture.visible = true
	portrait_label.visible = false
	title_label.text = "%02d号 · %s" % [
		index + 1, config.get("name", "普通机位")
	]
	badge_label.text = "机"
	_set_overview("机位概览", [
		{"key": "显卡", "value": config.get("gpu_label", "GTX 960")},
		{"key": "显示", "value": config.get("monitor_label", "24寸·60Hz")},
		{
			"key": state_text,
			"value": "¥%s/小时" % int(config.get("hourly_rate", 3)),
			"lamp": _state_color(state_text),
		},
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
	var profile := stage_controller.get_customer_profile(index)
	var habit: Dictionary = profile.get("internet_habit", {})
	portrait_texture.visible = false
	portrait_label.visible = true
	title_label.text = str(profile.get("name", "顾客 %d" % (index + 1)))
	badge_label.text = "客"
	portrait_label.text = "%s岁 · %s\n%s · %scm\n%s%s" % [
		int(profile.get("age", 0)),
		profile.get("occupation", "未知职业"),
		profile.get("outfit_style", "日常着装"),
		int(profile.get("height_cm", 0)),
		profile.get("hair_color", ""),
		profile.get("hair_type", ""),
	]
	_set_overview("顾客概览", [
		{"key": "状态", "value": state_text},
		{"key": "习惯", "value": habit.get("type", "普通上网")},
		{"key": "偏好", "value": habit.get("spending_focus", "普通机位")},
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


func _show_decor_slot(slot_index: int, keep_cursor := false) -> void:
	var slot := stage_controller.get_decor_slot(slot_index)
	if slot == null:
		return
	selected_kind = "decor"
	selected_index = slot_index
	selected_decor_slot = slot_index
	selected_decor_options = stage_controller.get_compatible_decor(slot_index)
	if selected_decor_options.is_empty():
		_show_placeholder("该槽位暂无兼容装修")
		return
	if not keep_cursor:
		selected_decor_cursor = 0
		for i in range(selected_decor_options.size()):
			if str(selected_decor_options[i]["id"]) == slot.decor_id:
				selected_decor_cursor = i
				break
	selected_decor_cursor = posmod(selected_decor_cursor, selected_decor_options.size())
	var item: Dictionary = selected_decor_options[selected_decor_cursor]
	var bonuses: Dictionary = item["bonuses"]
	var item_id := str(item["id"])
	title_label.text = str(item["name"])
	badge_label.text = "装"
	portrait_texture.texture = load(str(item["portrait"]))
	portrait_texture.visible = true
	portrait_label.visible = false
	_set_overview("%s · %d/%d" % [
		_slot_type_name(slot.slot_type),
		selected_decor_cursor + 1,
		selected_decor_options.size(),
	], [
		{"key": "价格", "value": "¥%d" % int(item["price"])},
		{"key": "装/舒/洁", "value": "+%d/+%d/+%d" % [
			int(bonuses["decor"]), int(bonuses["comfort"]), int(bonuses["clean"])
		]},
		{"key": "声誉/客流", "value": "+%d / +%d" % [
			int(bonuses["reputation"]), int(bonuses["traffic"])
		]},
	])
	var installed := slot.decor_id == item_id
	var owned := stage_controller.is_decor_owned(item_id)
	var block_reason := stage_controller.decor_install_block_reason(
		slot_index, item_id, player_level
	)
	var action_label := "已安装"
	var action_enabled := false
	if not block_reason.is_empty():
		action_label = block_reason
	elif not installed and owned:
		action_label = "安装"
		action_enabled = true
	elif not installed and money >= float(item["price"]):
		action_label = "购买 ¥%d" % int(item["price"])
		action_enabled = true
	elif not installed:
		action_label = "资金不足"
	_set_actions([
		_action("decor_prev", "上一项"),
		_action("decor_buy_install", action_label, action_enabled),
		_action("decor_next", "下一项"),
		_action("decor_exit", "退出"),
	])


func _slot_type_name(slot_type: String) -> String:
	match slot_type:
		"zone_skin":
			return "区域主题"
		"service":
			return "服务升级"
		"wall":
			return "墙面装饰"
		"utility":
			return "功能设施"
		_:
			return "落地装修"


func _cycle_decor(step: int) -> void:
	if selected_decor_options.is_empty():
		return
	selected_decor_cursor = posmod(
		selected_decor_cursor + step, selected_decor_options.size()
	)
	_show_decor_slot(selected_decor_slot, true)


func _buy_or_install_decor() -> void:
	if selected_decor_options.is_empty():
		return
	var slot := stage_controller.get_decor_slot(selected_decor_slot)
	var item: Dictionary = selected_decor_options[selected_decor_cursor]
	var item_id := str(item["id"])
	if not stage_controller.decor_install_block_reason(
		selected_decor_slot, item_id, player_level
	).is_empty():
		return
	if not stage_controller.is_decor_owned(item_id):
		var price := float(item["price"])
		if money < price:
			return
		money -= price
		stage_controller.mark_decor_owned(item_id)
	stage_controller.install_decor(slot.slot_id, item_id)
	_show_decor_slot(selected_decor_slot, true)
	_update_topbar()


func _set_overview(title: String, rows: Array) -> void:
	operation_panel.set_overview(title, rows)


func _action(id: String, label: String, enabled: bool = true, icon: String = "") -> Dictionary:
	return {"id": id, "label": label, "enabled": enabled, "icon": icon}


func _set_actions(actions: Array, counter_layout := false) -> void:
	operation_panel.set_actions(actions, counter_layout)
	action_buttons = operation_panel.action_buttons


func _action_icon(action_id: String, override_name: String) -> Texture2D:
	var icon_name := override_name if not override_name.is_empty() else str(ACTION_ICONS.get(action_id, ""))
	if icon_name.is_empty():
		return null
	return load("res://assets/ui/icons/%s.png" % icon_name)


func _on_action_requested(action_id: String) -> void:
	match action_id:
		"toggle_shop":
			is_open = not is_open
			_show_counter()
		"decor_prev":
			_cycle_decor(-1)
		"decor_buy_install":
			_buy_or_install_decor()
		"decor_next":
			_cycle_decor(1)
		"decor_exit":
			stage_controller.set_decor_preview(false)
			_show_counter()
		_:
			_show_placeholder("%s：功能待接入" % action_id)


func _on_context_action(index: int) -> void:
	# 兼容旧场景/测试入口；实际按钮由 OperationPanelUI 直接发送语义 action_id。
	if index >= 0 and index < action_buttons.size():
		_on_action_requested(str(action_buttons[index].get_meta("action_id", "")))


func _open_module(module_id: String, module_name := "") -> void:
	if module_name.is_empty() and operation_modules_by_id.has(module_id):
		module_name = str(operation_modules_by_id[module_id]["label"])
	if module_id == "upgrade":
		stage_controller.set_decor_preview(true)
		_show_placeholder(
			"选择青色装修槽位\n红色槽位可预览但未解锁"
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
	var bonuses: Dictionary = stage_controller.business_bonuses
	topbar.set_reputation(3.5 + float(bonuses["reputation"]) * 0.05)
	topbar.set_clean(42 + int(bonuses["clean"]))
	topbar.set_decor(50 + int(bonuses["decor"]))
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
