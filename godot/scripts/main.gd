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
	"staff_hire": "cash",
	"staff_fire": "remove",
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
@onready var settings_overlay = $SettingsOverlay
@onready var inbox_overlay = $InboxOverlay

const SettingsSvc := preload("res://scripts/sim/settings_service.gd")
const CAMERA_PAN_SPEED := 220.0
const HOTKEY_ACTIONS := [
	"hotkey_pause", "hotkey_speed_1", "hotkey_speed_2", "hotkey_primary",
	"hotkey_zoom", "hotkey_left", "hotkey_right", "hotkey_up", "hotkey_down",
	"hotkey_counter", "hotkey_find", "hotkey_clean", "hotkey_repair",
]
var settings = SettingsSvc.new()
var _unfocus_resume_speed := 0.0
var _paused_by_unfocus := false
var _hotkey_resume_speed := 1.0

var money: float:
	get:
		return GameState.money
	set(value):
		GameState.money = value
var is_open: bool:
	get:
		return GameState.is_open()
	set(_value):
		pass
var pc_nodes: Array[Dictionary] = []
var day: int:
	get:
		return GameState.day
	set(value):
		GameState.day = value
var business_phase: String:
	get:
		return GameState.business_phase
	set(value):
		GameState.business_phase = value
var last_report: Dictionary:
	get:
		return GameState.last_report
	set(value):
		GameState.last_report = value
var selected_kind := "counter"
var selected_index := -1
var player_level: int:
	get:
		return GameState.player_level
	set(value):
		GameState.player_level = value
var selected_decor_slot := -1
var selected_decor_cursor := 0
var selected_decor_options: Array = []
var operation_data: Dictionary = {}
var operation_modules: Array = []
var operation_modules_by_id: Dictionary = {}
var active_module := ""
var active_module_section := ""

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
var shelf_view := ""

func _ready() -> void:
	_connect_stage()
	_load_operation_data()
	_bind_operation_panel()
	_bind_inbox()
	GameState.bind_stage(stage_controller)
	_show_counter()
	_bind_settings()
	_refresh_bell()
	_maybe_show_pending_event()
	topbar.settings_clicked.connect(toggle_settings)
	_update_topbar()
	_on_clock_updated()


func _exit_tree() -> void:
	if not GameState.test_mode:
		GameState.save_game()


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
	operation_panel.speed_requested.connect(_apply_clock_speed)
	GameState.clock_updated.connect(_on_clock_updated)


func _bind_settings() -> void:
	settings.test_mode = GameState.test_mode
	settings.load_from_disk()
	settings.apply_all()
	settings_overlay.settings = settings
	settings_overlay.closed.connect(func(): topbar.set_settings_open(false))
	settings_overlay.save_requested.connect(_save_from_settings)
	settings_overlay.load_confirmed.connect(_load_from_settings)
	settings_overlay.new_game_confirmed.connect(_new_game_from_settings)


func _bind_inbox() -> void:
	GameState.event_offered.connect(_on_event_offered)
	GameState.inbox_changed.connect(_refresh_bell)
	inbox_overlay.closed.connect(_refresh_bell)
	inbox_overlay.choice_requested.connect(_on_event_choice)
	inbox_overlay.jump_requested.connect(_on_inbox_jump)
	topbar.notify_clicked.connect(toggle_inbox)


func toggle_inbox() -> void:
	if inbox_overlay.is_decision():
		return
	if inbox_overlay.is_open():
		inbox_overlay.close()
		return
	if settings_overlay.is_open():
		close_settings()
	GameState.mark_inbox_all_read()
	inbox_overlay.open_list(GameState.inbox_rows())
	_refresh_bell()


func _on_event_offered(_event: Dictionary) -> void:
	_maybe_show_pending_event()


func _maybe_show_pending_event() -> void:
	if not GameState.has_pending_event():
		return
	if settings_overlay.is_open():
		return
	inbox_overlay.show_decision(GameState.pending_event())
	_refresh_bell()


func _on_event_choice(choice_id: String) -> void:
	if GameState.resolve_event(choice_id):
		inbox_overlay.close_after_resolve()
		_refresh_bell()
		_on_clock_updated()
	else:
		_play_sfx("ui_deny")


func _on_inbox_jump(jump: String) -> void:
	if jump == "dirty":
		if not _focus_next_pc("待清洁", true):
			_show_counter()
	elif jump == "broken":
		if not _focus_next_pc("故障", true):
			_show_counter()
	elif jump == "shelf":
		stage_controller.select_facility("shelf")


func _refresh_bell() -> void:
	topbar.set_unread(GameState.has_pending_event() or GameState.unread_inbox_count() > 0)


func toggle_settings() -> void:
	if settings_overlay.is_open():
		close_settings()
	else:
		open_settings()


func open_settings() -> void:
	if inbox_overlay.is_decision():
		return
	if inbox_overlay.is_open():
		inbox_overlay.close()
	if _paused_by_unfocus:
		_paused_by_unfocus = false
	settings_overlay.open()
	topbar.set_settings_open(true)


func close_settings() -> void:
	settings_overlay.close()
	topbar.set_settings_open(false)
	_maybe_show_pending_event()


func _save_from_settings() -> void:
	if GameState.save_game():
		_play_sfx("ui_save")
		settings_overlay.show_status("已保存 · 第 %d 天 · %s" % [
			GameState.day, GameState.clock.period()
		])
		settings_overlay.refresh()
	else:
		_play_sfx("ui_deny")
		settings_overlay.show_status("存档失败")


func _load_from_settings() -> void:
	if not GameState.load_save():
		_play_sfx("ui_deny")
		settings_overlay.show_status("读取失败，存档可能已损坏")
		return
	stage_controller.set_decor_preview(false)
	var resume := float(GameState.clock.speed)
	if settings_overlay.is_open():
		GameState.clock.set_speed(0.0)
		settings_overlay.remember_resume_speed(resume)
	_show_counter()
	_update_topbar()
	_on_clock_updated()
	settings_overlay.show_status("已读取存档 · 第 %d 天" % GameState.day)
	settings_overlay.refresh()


func _new_game_from_settings() -> void:
	GameState.start_new_game()
	stage_controller.set_decor_preview(false)
	if settings_overlay.is_open():
		GameState.clock.set_speed(0.0)
		settings_overlay.remember_resume_speed(0.0 if GameState.test_mode else 1.0)
	_show_counter()
	_update_topbar()
	_on_clock_updated()
	settings_overlay.show_status("已重新开局 · 第 1 天")
	settings_overlay.refresh()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if settings_overlay.confirm_open():
			settings_overlay.cancel_confirm()
		elif settings_overlay.is_open():
			close_settings()
		elif inbox_overlay.is_decision():
			pass
		elif inbox_overlay.is_open():
			inbox_overlay.close()
		else:
			open_settings()
		get_viewport().set_input_as_handled()
		return
	if _overlay_blocks_hotkeys():
		if _is_game_hotkey(event):
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("hotkey_pause"):
		_toggle_pause_hotkey()
	elif event.is_action_pressed("hotkey_speed_1"):
		_apply_clock_speed(1.0)
	elif event.is_action_pressed("hotkey_speed_2"):
		_apply_clock_speed(2.0)
	elif event.is_action_pressed("hotkey_primary"):
		_hotkey_primary()
	elif event.is_action_pressed("hotkey_zoom"):
		stage_controller.toggle_zoom()
	elif event.is_action_pressed("hotkey_counter"):
		_hotkey_counter()
	elif event.is_action_pressed("hotkey_find"):
		_focus_next_maintenance()
	elif event.is_action_pressed("hotkey_clean"):
		_hotkey_clean()
	elif event.is_action_pressed("hotkey_repair"):
		_hotkey_repair()
	elif _is_pan_hotkey(event):
		pass
	else:
		return
	get_viewport().set_input_as_handled()


func _overlay_blocks_hotkeys() -> bool:
	return (
		settings_overlay.is_open()
		or settings_overlay.confirm_open()
		or inbox_overlay.is_open()
	)


func _is_game_hotkey(event: InputEvent) -> bool:
	for action in HOTKEY_ACTIONS:
		if event.is_action(action):
			return true
	return false


func _is_pan_hotkey(event: InputEvent) -> bool:
	return (
		event.is_action("hotkey_left")
		or event.is_action("hotkey_right")
		or event.is_action("hotkey_up")
		or event.is_action("hotkey_down")
	)


func _apply_clock_speed(speed: float) -> void:
	if speed > 0.0:
		_hotkey_resume_speed = speed
	elif GameState.clock.speed > 0.0:
		_hotkey_resume_speed = GameState.clock.speed
	GameState.clock.set_speed(speed)


func _toggle_pause_hotkey() -> void:
	if GameState.clock.speed > 0.0:
		_apply_clock_speed(0.0)
	else:
		_apply_clock_speed(_hotkey_resume_speed if _hotkey_resume_speed > 0.0 else 1.0)


func _hotkey_primary() -> void:
	match GameState.business_phase:
		"closed":
			_open_shop()
		"open":
			_stop_admission()
		"closing":
			_close_settlement()


func _hotkey_counter() -> void:
	stage_controller.clear_selection()
	_show_counter()


func _hotkey_clean() -> void:
	if selected_kind != "pc" or selected_index < 0:
		return
	if str(pc_nodes[selected_index]["state"]) != "待清洁":
		return
	if GameState.clean_pc(selected_index):
		_show_pc(selected_index)


func _hotkey_repair() -> void:
	if selected_kind != "pc" or selected_index < 0:
		return
	if str(pc_nodes[selected_index]["state"]) != "故障":
		return
	if GameState.repair_pc(selected_index):
		_show_pc(selected_index)
	else:
		_play_sfx("ui_deny")


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_pause_for_unfocus()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_resume_from_unfocus()


func _pause_for_unfocus() -> void:
	if GameState.test_mode or settings_overlay.is_open() or inbox_overlay.is_open() or not settings.pause_on_unfocus:
		return
	if GameState.clock.speed <= 0.0:
		return
	_unfocus_resume_speed = GameState.clock.speed
	_paused_by_unfocus = true
	GameState.clock.set_speed(0.0)


func _resume_from_unfocus() -> void:
	if not _paused_by_unfocus:
		return
	_paused_by_unfocus = false
	if settings_overlay.is_open() or inbox_overlay.is_open():
		return
	if _unfocus_resume_speed > 0.0:
		GameState.clock.set_speed(_unfocus_resume_speed)


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
	active_module = ""
	active_module_section = ""
	operation_panel.set_active_module("")
	if kind != "decor_slot":
		stage_controller.set_decor_preview(false)
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
	active_module = ""
	active_module_section = ""
	operation_panel.set_active_module("")
	title_label.text = "经营总台"
	badge_label.text = "店"
	portrait_texture.texture = load("res://assets/ui/portraits/portrait_counter.png")
	portrait_texture.visible = true
	portrait_label.visible = false
	var reception_count := _customer_count(["排队中", "待接待"])
	var checkout_count := _customer_count(["待结账"])
	var active_count := stage_controller.active_customer_count()
	var phase_label := _phase_label()
	var phase_color := (
		CLOSED_RED if business_phase == "closed"
		else Color("#d4a017") if business_phase == "closing"
		else OPEN_GREEN
	)
	_set_overview("营业总览", [
		{"key": "状态", "value": phase_label, "lamp": phase_color, "value_color": phase_color},
		{"key": "在店顾客", "value": "%d 人 · 前台 %d/%d" % [
			active_count, GameState.busy_service_count(), GameState.desk_slots(),
		]},
		{"key": "今日营收", "value": "¥ %d" % GameState.today_revenue()},
	])
	if business_phase == "closed":
		_set_actions([
			_action("open_shop", "开店营业", true, "shop_open", "回车"),
			_action("opening_check", "开店检查"),
			_action("review_report", "日结回顾"),
		], true)
	elif business_phase == "open":
		_set_actions([
			_action("stop_admission", "停止接客", true, "shop_close", "回车"),
			_action("focus_reception", "排队 %d" % reception_count, reception_count > 0),
			_action("focus_checkout", "结账 %d" % checkout_count, checkout_count > 0),
		], true)
	else:
		_set_actions([
			_action("close_settlement", "关店结算", active_count == 0, "cash", "回车"),
			_action("focus_reception", "收尾中", false, "serve"),
			_action("focus_checkout", "结账 %d" % checkout_count, checkout_count > 0),
		], true)


func _phase_label() -> String:
	for phase in operation_data.get("phases", []):
		if str(phase["id"]) == business_phase:
			return str(phase["label"])
	return business_phase


func _customer_count(states: Array) -> int:
	var count := 0
	for data in stage_controller.customer_data:
		if str(data["state"]) in states:
			count += 1
	return count


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
	shelf_view = ""
	active_module_section = ""
	var empty: int = GameState.shop.empty_count() if GameState.shop else 0
	portrait_texture.visible = false
	portrait_label.visible = true
	title_label.text = "小卖部货架"
	badge_label.text = "货"
	portrait_label.text = "【小卖部】\n%s" % GameState.shop.stock_lines()
	_set_overview("库存概览", [
		{
			"key": "库存",
			"value": "%d 件" % GameState.shop.total_stock(),
			"lamp": Color("#d4a017") if empty > 0 else Color.TRANSPARENT,
			"value_color": Color("#d4a017") if empty > 0 else Color("#ffc257"),
		},
		{"key": "缺货", "value": "%d 种" % empty},
		{"key": "今日销售", "value": "¥%d" % GameState.today_shop_revenue()},
	])
	_set_actions([
		_action("shelf_restock", "快捷补货"),
		_action("shelf_inventory", "查看库存"),
		_action("shelf_pricing", "调价", false),
		_action("shelf_promotion", "促销", false),
	])


func _show_shelf_restock(from_module := false) -> void:
	selected_kind = "shelf"
	selected_index = -1
	shelf_view = "restock"
	if from_module:
		active_module = "procurement"
		active_module_section = "shop"
	portrait_texture.visible = false
	portrait_label.visible = true
	title_label.text = "快捷补货"
	badge_label.text = "货"
	portrait_label.text = "【按包进货】\n%s" % GameState.shop.stock_lines()
	var rows: Array = []
	for item in GameState.shop.catalog:
		var item_id := str(item["id"])
		rows.append({
			"key": str(item["name"]),
			"value": "+%d / ¥%d" % [int(item["pack"]), GameState.shop.pack_cost(item_id)],
		})
	_set_overview("进货", rows)
	var actions: Array = []
	for item in GameState.shop.catalog:
		var item_id := str(item["id"])
		var cost: int = GameState.shop.pack_cost(item_id)
		actions.append(_action(
			"shelf_buy:%s" % item_id,
			"补%s" % item["name"],
			money >= float(cost)
		))
	if from_module or active_module == "procurement":
		actions.append(_action("back_module", "返回采购"))
	else:
		actions.append(_action("shelf_home", "返回货架"))
	_set_actions(actions)


func _show_shelf_inventory() -> void:
	selected_kind = "shelf"
	selected_index = -1
	shelf_view = "stock"
	portrait_texture.visible = false
	portrait_label.visible = true
	title_label.text = "库存明细"
	badge_label.text = "货"
	var lines: Array[String] = []
	for item in GameState.shop.catalog:
		var item_id := str(item["id"])
		lines.append("%s 剩 %d · 今日 %d" % [
			item["name"], GameState.shop.stock_of(item_id),
			int(GameState.shop.sold.get(item_id, 0)),
		])
	portrait_label.text = "【今日】\n%s\n缺货 %d 次" % [
		"\n".join(lines), GameState.shop.missed,
	]
	_set_overview("销量", [
		{"key": "售出", "value": "%d 件" % GameState.shop.today_sold_count()},
		{"key": "商品收入", "value": "¥%d" % GameState.today_shop_revenue()},
		{"key": "缺货", "value": "%d 次" % GameState.shop.missed},
	])
	_set_actions([_action("shelf_home", "返回货架")])


func _show_customer(index: int, state_text: String) -> void:
	selected_kind = "customer"
	selected_index = index
	var profile := stage_controller.get_customer_profile(index)
	var habit: Dictionary = profile.get("internet_habit", {})
	var portrait_path := str(profile.get(
		"portrait",
		"res://assets/ui/portraits/portrait_%s.png" % profile.get("id", "customer_01")
	))
	title_label.text = str(profile.get("name", "顾客 %d" % (index + 1)))
	badge_label.text = "客"
	if ResourceLoader.exists(portrait_path):
		portrait_texture.texture = load(portrait_path)
		portrait_texture.visible = true
		portrait_label.visible = false
	else:
		portrait_texture.visible = false
		portrait_label.visible = true
		portrait_label.text = "%s岁 · %s\n%s · %scm\n%s%s" % [
			int(profile.get("age", 0)),
			profile.get("occupation", "未知职业"),
			profile.get("outfit_style", "日常着装"),
			int(profile.get("height_cm", 0)),
			profile.get("hair_color", ""),
			profile.get("hair_type", ""),
		]
	var third_key := "习惯"
	var third_value := str(habit.get("type", "普通上网"))
	if state_text == "待结账":
		third_key = "账单"
		third_value = "¥%d" % stage_controller.customer_bill(index)
	elif state_text == "使用中":
		var bought := str(stage_controller.customer_data[index].get("shop_item", ""))
		if bought.is_empty():
			third_key = "机位"
			third_value = "%02d号" % (int(stage_controller.customer_data[index].get("pc_index", -1)) + 1)
		else:
			third_key = "买了"
			third_value = bought
	_set_overview("顾客概览", [
		{"key": "职业", "value": profile.get("occupation", "未知")},
		{"key": "心情", "value": stage_controller.customer_mood(index)},
		{"key": third_key, "value": third_value},
	])
	_set_actions([
		_action(
			"customer_respond",
			_service_action_label(index, "接待"),
			false
		),
		_action("customer_checkout", _service_action_label(index, "结算"), false),
		_action("customer_membership", "办会员"),
		_action("customer_remove", "劝离"),
	])


func _service_action_label(index: int, fallback: String) -> String:
	var kind := stage_controller.customer_service_kind(index)
	var remain := stage_controller.customer_service_remaining(index)
	if kind == "reception":
		return "接待 %d′" % remain
	if kind == "checkout":
		return "结账 %d′" % remain
	return fallback


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
		_play_sfx("ui_deny")
		return
	var slot := stage_controller.get_decor_slot(selected_decor_slot)
	var item: Dictionary = selected_decor_options[selected_decor_cursor]
	var item_id := str(item["id"])
	if not stage_controller.decor_install_block_reason(
		selected_decor_slot, item_id, player_level
	).is_empty():
		_play_sfx("ui_deny")
		return
	if not stage_controller.is_decor_owned(item_id):
		var price := int(item["price"])
		if not GameState.spend(price, "装修 %s" % item["name"], item_id):
			_play_sfx("ui_deny")
			return
		stage_controller.mark_decor_owned(item_id)
	stage_controller.install_decor(slot.slot_id, item_id)
	_play_sfx("decor_place")
	_show_decor_slot(selected_decor_slot, true)
	_update_topbar()


func _set_overview(title: String, rows: Array) -> void:
	operation_panel.set_overview(title, rows)


func _action(id: String, label: String, enabled: bool = true, icon: String = "", tip: String = "") -> Dictionary:
	return {"id": id, "label": label, "enabled": enabled, "icon": icon, "tooltip": tip}


func _set_actions(actions: Array, counter_layout := false) -> void:
	operation_panel.set_actions(actions, counter_layout)
	action_buttons = operation_panel.action_buttons


func _action_icon(action_id: String, override_name: String) -> Texture2D:
	var icon_name := override_name if not override_name.is_empty() else str(ACTION_ICONS.get(action_id, ""))
	if icon_name.is_empty():
		return null
	return load("res://assets/ui/icons/%s.png" % icon_name)


func _on_action_requested(action_id: String) -> void:
	if action_id.begins_with("module:"):
		_open_module_section(action_id)
		return
	if action_id.begins_with("shelf_buy:"):
		if GameState.restock_item(action_id.get_slice(":", 1)):
			_show_shelf_restock()
		else:
			_play_sfx("ui_deny")
		return
	match action_id:
		"shelf_restock":
			_show_shelf_restock()
		"shelf_inventory":
			_show_shelf_inventory()
		"shelf_home":
			_show_shelf()
		"shelf_pricing", "shelf_promotion":
			_play_sfx("ui_deny")
		"open_shop":
			_open_shop()
		"stop_admission":
			_stop_admission()
		"close_settlement":
			_close_settlement()
		"opening_check":
			_show_opening_check()
		"review_report":
			_show_last_report()
		"focus_reception":
			_focus_customer(["排队中", "待接待"])
		"focus_checkout":
			_focus_customer(["待结账"])
		"staff_hire":
			if GameState.hire_clerk():
				_show_staff_hire()
				_play_sfx("ui_confirm")
			else:
				_play_sfx("ui_deny")
		"staff_fire":
			if GameState.fire_clerk():
				_show_staff_hire()
				_play_sfx("ui_toggle")
			else:
				_play_sfx("ui_deny")
		"pc_power":
			if GameState.toggle_pc_power(selected_index):
				_show_pc(selected_index)
			else:
				_play_sfx("ui_deny")
		"pc_clean":
			if selected_kind == "pc" and GameState.clean_pc(selected_index):
				_show_pc(selected_index)
			elif selected_kind == "pc":
				_play_sfx("ui_deny")
			else:
				_focus_pc("待清洁")
		"pc_repair":
			if selected_kind == "pc" and GameState.repair_pc(selected_index):
				_show_pc(selected_index)
			elif selected_kind == "pc":
				_play_sfx("ui_deny")
			else:
				_focus_pc("故障")
		"customer_respond":
			if GameState.assign_customer(selected_index):
				_show_customer(selected_index, "使用中")
			else:
				_play_sfx("ui_deny")
				_show_placeholder("当前没有空闲机位")
		"customer_checkout":
			GameState.checkout_customer(selected_index)
			_show_counter()
		"customer_remove":
			GameState.dismiss_customer(selected_index)
			_show_counter()
		"back_module":
			if active_module.is_empty():
				_show_counter()
			else:
				_show_module(active_module)
		"toggle_shop":
			if business_phase == "closed":
				_open_shop()
			else:
				_stop_admission()
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


func _open_shop() -> void:
	GameState.open_shop()
	_show_counter()


func _stop_admission() -> void:
	GameState.stop_admission()
	_show_counter()


func _close_settlement() -> void:
	if GameState.close_settlement():
		_show_counter()
	else:
		_play_sfx("ui_deny")


func _show_opening_check() -> void:
	var dirty := 0
	var broken := 0
	for pc in pc_nodes:
		if pc["state"] == "待清洁":
			dirty += 1
		elif pc["state"] == "故障":
			broken += 1
	var empty: int = GameState.shop.empty_count() if GameState.shop else 0
	var shelf_value: String = "缺 %d 种" % empty if empty > 0 else "%d 件" % GameState.shop.total_stock()
	operation_panel.show_portrait_text(
		"【开店检查】\n机位问题 %d 项\n货架缺货 %d 种" % [dirty + broken, empty]
	)
	_set_overview("准备清单", [
		{"key": "待清洁", "value": "%d 台" % dirty},
		{"key": "故障", "value": "%d 台" % broken},
		{"key": "货架", "value": shelf_value},
	])
	_set_actions([
		_action("open_shop", "确认开店", true, "shop_open"),
		_action("pc_clean", "查看脏污", dirty > 0),
		_action("pc_repair", "查看故障", broken > 0),
		_action("back_module", "返回"),
	])


func _show_last_report() -> void:
	operation_panel.show_portrait_text(
		"【最近日结】\n第 %d 天已归档\n脏污 %d · 故障 %d · 电费 ¥%d" % [
			int(last_report.get("day", 0)),
			int(last_report.get("dirty", 0)),
			int(last_report.get("broken", 0)),
			int(last_report.get("electricity", 0)),
		]
	)
	_set_overview("日结回顾", [
		{"key": "营业日", "value": "第 %d 天" % int(last_report.get("day", 0))},
		{"key": "营收", "value": "¥ %d" % int(last_report.get("revenue", 0))},
		{"key": "服务顾客", "value": "%d 人" % int(last_report.get("customers", 0))},
	])
	_set_actions([_action("back_module", "返回")])


func _show_staff_hire() -> void:
	active_module = "staff"
	active_module_section = "hire"
	operation_panel.set_title("招聘", "员")
	var remain := GameState.clerk_max() - GameState.staff_clerks
	operation_panel.show_portrait_text(
		"【前台】\n柜台自动接待和结账\n每人占一个办理位\n招满还可再雇 %d 人" % remain
	)
	_set_overview("招聘前台", [
		{"key": "已雇", "value": "%d/%d 人" % [GameState.staff_clerks, GameState.clerk_max()]},
		{"key": "招聘费", "value": "¥%d" % GameState.clerk_hire_cost()},
		{"key": "日薪", "value": "¥%d/人" % GameState.clerk_daily_wage()},
	])
	_set_actions([
		_action(
			"staff_hire",
			"招前台",
			GameState.staff_clerks < GameState.clerk_max()
			and GameState.money >= float(GameState.clerk_hire_cost())
		),
		_action("staff_fire", "解雇", GameState.staff_clerks > 0),
		_action("back_module", "返回员工"),
	])


func _show_staff_status() -> void:
	active_module = "staff"
	active_module_section = "status"
	operation_panel.set_title("员工状态", "员")
	operation_panel.show_portrait_text(
		"【服务效率】\n接待 %d 分钟/人\n结账 %d 分钟/人\n同时办理 %d 人" % [
			int(GameState.tuning.get("service_reception_minutes", 3)),
			int(GameState.tuning.get("service_checkout_minutes", 2)),
			GameState.desk_slots(),
		]
	)
	_set_overview("前台状态", [
		{"key": "办理中", "value": "%d/%d" % [
			GameState.busy_service_count(), GameState.desk_slots(),
		]},
		{"key": "排队", "value": "%d 人" % _customer_count(["排队中", "待接待"])},
		{"key": "待结账", "value": "%d 人" % _customer_count(["待结账"])},
	])
	_set_actions([_action("back_module", "返回员工")])


func _show_finance_today() -> void:
	operation_panel.set_title("今日账单", "财")
	operation_panel.show_portrait_text(
		"【今日流水】\n%s\n共 %d 笔" % [
			GameState.ledger.latest_note(GameState.day),
			GameState.ledger.day_count(GameState.day),
		]
	)
	_set_overview("今日账单", [
		{"key": "收入", "value": "¥%d" % GameState.ledger.day_income(GameState.day)},
		{"key": "商品", "value": "¥%d" % GameState.today_shop_revenue()},
		{"key": "净额", "value": "¥%d" % GameState.ledger.day_net(GameState.day)},
	])
	_set_actions([_action("back_module", "返回财务")])


func _focus_customer(states: Array) -> void:
	var index := stage_controller.find_customer_by_states(states)
	if index >= 0:
		stage_controller.select_customer(index)
	else:
		_show_counter()


func _on_context_action(index: int) -> void:
	# 兼容旧场景/测试入口；实际按钮由 OperationPanelUI 直接发送语义 action_id。
	if index >= 0 and index < action_buttons.size():
		_on_action_requested(str(action_buttons[index].get_meta("action_id", "")))


func _open_module(module_id: String, module_name := "") -> void:
	if module_id == "upgrade":
		module_id = "construction"
	if not operation_modules_by_id.has(module_id):
		return
	active_module = module_id
	active_module_section = ""
	stage_controller.set_decor_preview(false)
	_show_module(module_id)


func _show_module(module_id: String) -> void:
	if not operation_modules_by_id.has(module_id):
		return
	stage_controller.set_decor_preview(false)
	var module: Dictionary = operation_modules_by_id[module_id]
	selected_kind = "module"
	selected_index = -1
	active_module = module_id
	active_module_section = ""
	operation_panel.set_active_module(module_id)
	operation_panel.set_title(str(module["label"]), str(module["badge"]))
	operation_panel.show_portrait_text(
		"【%s系统】\n%s" % [module["label"], module["summary"]]
	)
	_set_overview("%s概览" % module["label"], _module_metrics(module_id))
	var actions: Array = []
	for section in module["sections"]:
		actions.append(_action(
			"module:%s:%s" % [module_id, section["id"]],
			str(section["label"])
		))
	_set_actions(actions)


func _module_metrics(module_id: String) -> Array:
	var bonuses: Dictionary = stage_controller.business_bonuses
	match module_id:
		"finance":
			return [
				{"key": "可用资金", "value": "¥%d" % int(money)},
				{"key": "今日营收", "value": "¥%d" % GameState.today_revenue()},
				{"key": "今日电费", "value": "¥%d" % GameState.today_electricity()},
			]
		"staff":
			return [
				{"key": "在岗", "value": "老板+前台%d" % GameState.staff_clerks},
				{"key": "同时办理", "value": "%d 人" % GameState.desk_slots()},
				{"key": "日薪", "value": "¥%d" % GameState.daily_wage_total()},
			]
		"equipment":
			return [
				{"key": "机位", "value": "%d 台" % pc_nodes.size()},
				{"key": "运行", "value": "%d 台" % _online_count()},
				{"key": "故障", "value": "%d 台" % _pc_state_count("故障")},
			]
		"procurement":
			return [
				{"key": "库存", "value": "%d 件" % GameState.shop.total_stock()},
				{"key": "缺货", "value": "%d 种" % GameState.shop.empty_count()},
				{"key": "今日商品", "value": "¥%d" % GameState.today_shop_revenue()},
			]
		"strategy":
			return [
				{"key": "基础网费", "value": "¥3/小时"},
				{"key": "声誉", "value": "%.1f" % GameState.reputation()},
				{"key": "客流加成", "value": "+%d" % int(bonuses["traffic"])},
			]
		"dining":
			return [
				{"key": "菜单", "value": "未启用"},
				{"key": "待出餐", "value": "0 单"},
				{"key": "卫生", "value": "待检查"},
			]
		"construction":
			return [
				{"key": "装修值", "value": "%d" % (50 + int(bonuses["decor"]))},
				{"key": "已拥有", "value": "%d 项" % stage_controller.owned_decor.size()},
				{"key": "区域主题", "value": "3 区"},
			]
		"cat":
			return [
				{"key": "店猫", "value": "布偶猫"},
				{"key": "心情", "value": "普通"},
				{"key": "用品", "value": "待配置"},
			]
	return []


func _pc_state_count(state: String) -> int:
	return pc_nodes.filter(func(pc): return str(pc["state"]) == state).size()


func _open_module_section(action_id: String) -> void:
	var parts := action_id.split(":")
	if parts.size() != 3 or not operation_modules_by_id.has(parts[1]):
		return
	var module_id := str(parts[1])
	var section_id := str(parts[2])
	var module: Dictionary = operation_modules_by_id[module_id]
	var selected: Dictionary = {}
	for section in module["sections"]:
		if str(section["id"]) == section_id:
			selected = section
			break
	if selected.is_empty():
		return
	active_module = module_id
	active_module_section = section_id
	operation_panel.set_active_module(module_id)
	if module_id == "staff" and section_id == "hire":
		stage_controller.set_decor_preview(false)
		_show_staff_hire()
		return
	if module_id == "staff" and section_id == "status":
		stage_controller.set_decor_preview(false)
		_show_staff_status()
		return
	if module_id == "procurement" and section_id == "shop":
		stage_controller.set_decor_preview(false)
		_show_shelf_restock(true)
		return
	if module_id == "finance" and section_id == "today":
		stage_controller.set_decor_preview(false)
		_show_finance_today()
		return
	if module_id == "finance" and section_id == "settlement":
		stage_controller.set_decor_preview(false)
		_show_last_report()
		return
	if module_id == "construction" and section_id == "decor":
		stage_controller.set_decor_preview(true)
		operation_panel.set_title("场景装修", "建")
		operation_panel.show_portrait_text("【装修模式】\n点击场景中的青色槽位\n红色槽位仅可预览")
		_set_overview("建设 · 装修", [
			{"key": "可用资金", "value": "¥%d" % int(money)},
			{"key": "装修槽位", "value": "%d 个" % stage_controller.decor_slots.size()},
			{"key": "已拥有", "value": "%d 项" % stage_controller.owned_decor.size()},
		])
		_set_actions([
			_action("back_module", "返回建设"),
			_action("decor_exit", "退出装修"),
		])
		return
	stage_controller.set_decor_preview(false)
	operation_panel.set_title(str(selected["label"]), str(module["badge"]))
	operation_panel.show_portrait_text(
		"【%s · %s】\n%s" % [
			module["label"], selected["label"], selected["description"]
		]
	)
	_set_overview("一级页面", [
		{"key": "所属系统", "value": str(module["label"])},
		{"key": "页面状态", "value": "框架已接入"},
		{"key": "业务数据", "value": "待实现"},
	])
	_set_actions([_action("back_module", "返回%s" % module["label"])])


func _show_placeholder(message: String) -> void:
	portrait_texture.visible = false
	portrait_label.visible = true
	portrait_label.text = "【功能占位】\n%s" % message


func _process(delta: float) -> void:
	_update_topbar()
	_update_camera_pan(delta)


func _update_camera_pan(delta: float) -> void:
	if _overlay_blocks_hotkeys():
		return
	var direction := Vector2.ZERO
	if Input.is_action_pressed("hotkey_left"):
		direction.x -= 1.0
	if Input.is_action_pressed("hotkey_right"):
		direction.x += 1.0
	if Input.is_action_pressed("hotkey_up"):
		direction.y -= 1.0
	if Input.is_action_pressed("hotkey_down"):
		direction.y += 1.0
	if direction == Vector2.ZERO:
		return
	stage_controller.pan_by(direction.normalized() * CAMERA_PAN_SPEED * delta)


func _on_clock_updated() -> void:
	operation_panel.set_clock_text(GameState.clock.display_text())
	operation_panel.set_speed_highlight(GameState.clock.speed)
	_update_topbar()
	if active_module == "staff" and active_module_section == "hire":
		_show_staff_hire()
	elif active_module == "staff" and active_module_section == "status":
		_show_staff_status()
	elif selected_kind == "counter":
		_show_counter()
	elif selected_kind == "pc" and selected_index >= 0:
		_show_pc(selected_index)
	elif selected_kind == "customer" and selected_index >= 0:
		if selected_index < stage_controller.customer_data.size():
			_show_customer(selected_index, str(stage_controller.customer_data[selected_index]["state"]))
		else:
			_show_counter()
	elif selected_kind == "shelf":
		if shelf_view == "restock":
			_show_shelf_restock()
		elif shelf_view == "stock":
			_show_shelf_inventory()
		else:
			_show_shelf()
	elif active_module == "procurement" and active_module_section == "shop":
		_show_shelf_restock(true)


func _focus_pc(state: String) -> void:
	if not _focus_next_pc(state, false):
		_show_counter()


func _focus_next_maintenance() -> void:
	if _focus_next_pc("待清洁", true):
		return
	if _focus_next_pc("故障", true):
		return
	_play_sfx("ui_deny")
	_show_counter()


func _focus_next_pc(state: String, cycle: bool) -> bool:
	if pc_nodes.is_empty():
		return false
	var start := 0
	if cycle and selected_kind == "pc" and selected_index >= 0:
		start = selected_index + 1
	for offset in range(pc_nodes.size()):
		var index := (start + offset) % pc_nodes.size()
		if str(pc_nodes[index]["state"]) == state:
			stage_controller.select_pc(index)
			return true
	return false


func _update_topbar() -> void:
	topbar.set_money(money)
	topbar.set_pc(_online_count(), pc_nodes.size())
	topbar.set_customers(stage_controller.active_customer_count())
	topbar.set_reputation(GameState.reputation())
	topbar.set_clean(GameState.clean_score())
	topbar.set_decor(GameState.decor_score())
	topbar.set_time(day, GameState.clock.period())


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


func _play_sfx(cue_id: String) -> void:
	var sfx := get_node_or_null("/root/Sfx")
	if sfx:
		sfx.play(cue_id)
