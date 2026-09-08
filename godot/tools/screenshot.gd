extends SceneTree
## 界面预览截图：无需打开编辑器，直接出图到 res://.preview/
## 用法：godot --path godot --script res://tools/screenshot.gd

const OUT_DIR := "res://.preview/"
# 逻辑画布 640x360 直接看太小，额外导出邻近采样放大版便于查看
const ZOOM := 2

var _main: Node
var GS: Node


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	GS = root.get_node("GameState")
	GS.begin_test(20260907)
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	await create_timer(0.6).timeout
	var stage_controller := _main.get_node("Body/Stage/SubViewport/InitialCafe")
	assert(stage_controller.pc_data.size() == 40, "初期店面必须恰好包含 40 台机位")
	assert(
		stage_controller.pc_data.all(func(pc): return pc["config_id"] == "gen_09"),
		"初期店面 40 台机位必须全部使用 9 系配置"
	)
	assert(stage_controller.decor_slots.size() == 12, "初期店面必须预埋 12 个装修槽位")
	assert(stage_controller.customer_profiles.size() == 50, "顾客角色库必须恰好包含 50 人")
	assert(_main.operation_modules.size() == 8, "右栏必须恰好包含 8 个全局经营模块")
	assert(
		_main.operation_modules.map(func(module): return module["id"]) == [
			"finance", "staff", "equipment", "procurement",
			"strategy", "dining", "construction", "cat",
		],
		"八模块顺序错误"
	)
	assert(_main.business_phase == "closed")
	assert(_main.operation_panel.action_buttons.size() == 3, "柜台必须使用一主两副动作布局")
	assert(_main.operation_panel.action_buttons[0].custom_minimum_size.x == 144)
	assert(_main.operation_panel.action_buttons[0].text == "开店营业")

	# 开局必须是 0.5 倍全局，不能停在入口近景。
	assert(is_equal_approx(stage_controller.zoom_level(), 0.5), "开局相机必须是 0.5 倍全局视野")
	assert(stage_controller.camera.position == Vector2(480, 336), "开局相机必须居中看满整店")
	await _shoot("01-全局视图")

	stage_controller.select_pc(3)
	assert(_main.selected_kind == "pc" and _main.selected_index == 3, "机位选中未接回右栏")
	assert(_main.portrait_texture.visible, "机位详情立绘未显示")
	assert(
		_main.portrait_texture.texture.resource_path.ends_with("portrait_pc_gen_09.png"),
		"初始机位未加载 9 系详情立绘"
	)
	await _shoot("02-选中机位")

	var preview_customer: int = GS.spawn_from_profile_index(0)
	assert(preview_customer >= 0, "预览顾客生成失败")
	stage_controller.select_customer(preview_customer)
	assert(_main.selected_kind == "customer" and _main.selected_index == preview_customer, "顾客选中未接回右栏")
	assert(_main.title_label.text == "林宇航", "顾客真实姓名未接入右栏")
	assert(_main.portrait_texture.visible, "顾客立绘未显示")
	assert(
		_main.portrait_texture.texture.resource_path.ends_with("portrait_customer_01.png"),
		"顾客立绘未加载对应半身像"
	)
	await _shoot("03-选中顾客")
	GS.dismiss_customer(preview_customer)

	stage_controller.call("set_decor_preview", true)
	await _shoot("04-装修槽位")

	# 选中墙面槽位，购买并安装首个兼容装修；余额、属性和场景贴图必须同步变化。
	_main.call("_show_decor_slot", 4)
	var money_before: float = _main.money
	var decor_before: int = stage_controller.business_bonuses["decor"]
	_main.call("_buy_or_install_decor")
	var installed_slot = stage_controller.get_decor_slot(4)
	assert(_main.money < money_before, "购买装修后余额没有减少")
	assert(installed_slot.decor_id == "wall_ac", "兼容装修没有安装到当前槽位")
	assert(installed_slot.installed_texture() != null, "安装后场景贴图为空")
	assert(stage_controller.business_bonuses["decor"] > decor_before, "装修值没有增加")
	await _shoot("05-装修已安装")

	# 主题按区域独立；包间换木质主题不能改动大厅。
	stage_controller.mark_decor_owned("theme_wood")
	assert(stage_controller.install_decor("rooms_skin", "theme_wood"), "包间主题安装失败")
	assert(stage_controller.zone_themes["rooms"] == "theme_wood")
	assert(stage_controller.zone_themes["hall"] == "theme_old")
	await _shoot("06-包间主题换肤")

	# 资金不足和高配区锁定都应禁用购买键，但仍能轮播预览。
	_main.money = 0.0
	_main.call("_show_decor_slot", 1)
	assert(_main.action_buttons[1].disabled, "资金不足时购买键仍可用")
	assert(_main.action_buttons[1].text == "资金不足")
	_main.call("_show_decor_slot", 11)
	assert(_main.action_buttons[1].disabled, "高配区锁定时安装键仍可用")
	assert(_main.action_buttons[1].text == "区域未解锁")
	await _shoot("07-高配装修锁定")
	stage_controller.call("set_decor_preview", false)
	_main.money = 500.0

	stage_controller.call("select_facility", "locked")
	await _shoot("08-选中锁定区")

	stage_controller.call("select_facility", "shelf")
	await _shoot("09-选中货架")

	# 推近到 1.0 倍看细节，相机分别对准大厅和服务区
	_main.call("_show_counter")
	stage_controller.call("set_zoom_index", 1)
	stage_controller.call("focus_on", Vector2(280, 180))
	await _shoot("10-近景大厅")

	stage_controller.call("focus_on", Vector2(360, 540))
	await _shoot("11-近景服务区")

	# 八模块首页、深层占位和建设→装修跳转。
	_main.call("_open_module", "finance")
	assert(_main.selected_kind == "module" and _main.active_module == "finance")
	assert(_main.operation_panel.title_label.text == "财务", "财务模块标题未渲染")
	assert(_main.operation_panel.module_buttons["finance"].button_pressed)
	assert(_main.operation_panel.action_buttons.size() == 4)
	await _shoot("12-财务模块首页")
	_main.call("_open_module_section", "module:finance:today")
	assert(_main.active_module_section == "today")
	await _shoot("13-一级页面占位")
	_main.call("_open_module", "construction")
	_main.call("_open_module_section", "module:construction:decor")
	assert(stage_controller.decor_preview, "建设模块没有进入场景装修模式")
	await _shoot("14-建设跳转装修")
	stage_controller.select_pc(0)
	assert(_main.active_module.is_empty(), "选中场景对象后没有退出模块页")
	assert(not _main.operation_panel.module_buttons["construction"].button_pressed)

	# 休息→营业→停止接客→清空顾客→日结→次日休息。
	_main.call("_show_counter")
	_main.call("_open_shop")
	assert(_main.business_phase == "open" and _main.is_open)
	assert(_main.operation_panel.action_buttons[0].text == "停止接客")
	await _shoot("15-开店营业")
	assert(GS.assign_waiting() >= 0, "开店后应能把排队顾客分配到空闲机位")
	GS.tick_minutes(30)
	_main.call("_stop_admission")
	assert(_main.business_phase == "closing" and not _main.is_open)
	assert(stage_controller.find_customer_by_states(["待结账"]) >= 0)
	await _shoot("16-停止接客收尾")
	GS.checkout_all_pending()
	_main.call("_show_counter")
	assert(not _main.operation_panel.action_buttons[0].disabled, "顾客清空后关店结算仍禁用")
	_main.call("_close_settlement")
	assert(_main.business_phase == "closed" and _main.day == 2)
	assert(_main.last_report["day"] == 1)
	await _shoot("17-关店日结")

	# 单日经营闭环四张验收图。
	_main.call("_open_shop")
	GS.spawn_from_profile_index(1)
	GS.spawn_from_profile_index(2)
	GS.spawn_from_profile_index(3)
	_main.call("_show_counter")
	stage_controller.call("set_zoom_index", 1)
	stage_controller.call("focus_on", Vector2(280, 620))
	await _shoot("18-营业排队")
	assert(stage_controller.waiting_count() >= 2)

	# 关掉测试瞬移，拍一张从门口走进队列的走路帧。
	stage_controller.debug_force_walk = true
	var walker: int = GS.spawn_from_profile_index(4)
	assert(walker >= 0, "走路预览顾客生成失败")
	await create_timer(0.22).timeout
	var walker_node: CafeCustomer = stage_controller.customer_data[walker]["node"]
	assert(walker_node.is_walking(), "新客应从门口走向队列")
	stage_controller.select_customer(walker)
	stage_controller.call("focus_on", walker_node.position)
	await _shoot("22-顾客走路")
	stage_controller.debug_force_walk = false
	stage_controller.call("_refresh_queue_positions")

	assert(GS.assign_waiting() >= 0)
	assert(GS.assign_waiting() >= 0)
	GS.tick_minutes(30)
	var busy_pc := -1
	for index in range(stage_controller.pc_data.size()):
		if str(stage_controller.pc_data[index]["state"]) == "使用中":
			busy_pc = index
			break
	assert(busy_pc >= 0, "分配后应有上机中的机位")
	var seated_index := int(stage_controller.pc_data[busy_pc]["session"]["customer_index"])
	var seated_node: CafeCustomer = stage_controller.customer_data[seated_index]["node"]
	assert(seated_node.is_seated(), "上机顾客必须换成坐姿")
	assert(
		seated_node.position
		== stage_controller.pc_data[busy_pc]["node"].position + stage_controller.SEAT_OFFSET,
		"上机顾客必须坐在椅面上"
	)
	stage_controller.select_pc(busy_pc)
	stage_controller.call("focus_on", stage_controller.pc_data[busy_pc]["node"].position)
	await _shoot("19-上机中")

	_main.call("_stop_admission")
	var checkout_index: int = stage_controller.find_customer_by_states(["待结账"])
	assert(checkout_index >= 0, "收尾后应有待结账顾客")
	stage_controller.select_customer(checkout_index)
	stage_controller.call("focus_on", Vector2(280, 620))
	await _shoot("20-待结账入账")
	var money_before_bill: float = GS.money
	var billed: int = GS.checkout_all_pending()
	assert(billed > 0, "待结账必须产生网费收入")
	assert(GS.money > money_before_bill)
	assert(GS.ledger.day_income(GS.day) >= billed)

	GS.debug_set_pc_state(10, "故障")
	_main.call("_close_settlement")
	assert(_main.business_phase == "closed" and _main.day == 3)
	_main.call("_show_opening_check")
	assert(stage_controller.count_pc_state("故障") >= 1, "次日开店检查应保留故障台")
	await _shoot("21-次日开店检查")
	quit()


func _click_stage(position: Vector2) -> void:
	# 点选在抬起时才判定（按下到抬起之间可能是拖拽平移），所以要按下再释放
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = position
		event.global_position = position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		_main.call("_on_stage_gui_input", event)
		await process_frame


func _shoot(label: String) -> void:
	# 连等两帧，确保上一步的 UI 变更已经绘制
	await process_frame
	await process_frame
	RenderingServer.force_draw(false)
	var img := root.get_texture().get_image()
	img.save_png(OUT_DIR + label + ".png")

	var zoomed := img.duplicate() as Image
	zoomed.resize(img.get_width() * ZOOM, img.get_height() * ZOOM, Image.INTERPOLATE_NEAREST)
	zoomed.save_png(OUT_DIR + label + "@%dx.png" % ZOOM)
	if label == "04-装修槽位":
		zoomed.save_png("res://../docs/ui/preview/decor_before@2x.png")
	elif label == "05-装修已安装":
		zoomed.save_png("res://../docs/ui/preview/decor_after@2x.png")
	elif label == "12-财务模块首页":
		zoomed.save_png("res://../docs/ui/preview/operation_module@2x.png")
	elif label == "15-开店营业":
		zoomed.save_png("res://../docs/ui/preview/operation_open@2x.png")
	elif label == "16-停止接客收尾":
		zoomed.save_png("res://../docs/ui/preview/operation_closing@2x.png")
	elif label == "17-关店日结":
		zoomed.save_png("res://../docs/ui/preview/operation_closed@2x.png")
	elif label == "18-营业排队":
		zoomed.save_png("res://../docs/ui/preview/sim_queue@2x.png")
	elif label == "19-上机中":
		zoomed.save_png("res://../docs/ui/preview/sim_session@2x.png")
	elif label == "20-待结账入账":
		zoomed.save_png("res://../docs/ui/preview/sim_checkout@2x.png")
	elif label == "21-次日开店检查":
		zoomed.save_png("res://../docs/ui/preview/sim_opening_check@2x.png")
	elif label == "22-顾客走路":
		zoomed.save_png("res://../docs/ui/preview/sim_walk@2x.png")
	print("SHOT %s (%dx%d)" % [label, img.get_width(), img.get_height()])
