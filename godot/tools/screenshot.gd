extends SceneTree
## 界面预览截图：无需打开编辑器，直接出图到 res://.preview/
## 用法：godot --path godot --script res://tools/screenshot.gd

const OUT_DIR := "res://.preview/"
# 逻辑画布 640x360 直接看太小，额外导出邻近采样放大版便于查看
const ZOOM := 2

var _main: Node


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
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

	# 先拉到 0.5 倍，一屏看满整店；此时视口本地坐标正好是世界坐标的一半
	stage_controller.call("set_zoom_index", 0)
	await process_frame
	await _shoot("01-全局视图")

	stage_controller.select_pc(3)
	assert(_main.selected_kind == "pc" and _main.selected_index == 3, "机位选中未接回右栏")
	assert(_main.portrait_texture.visible, "机位详情立绘未显示")
	assert(
		_main.portrait_texture.texture.resource_path.ends_with("portrait_pc_gen_09.png"),
		"初始机位未加载 9 系详情立绘"
	)
	await _shoot("02-选中机位")

	stage_controller.select_customer(0)
	assert(_main.selected_kind == "customer" and _main.selected_index == 0, "顾客选中未接回右栏")
	assert(_main.title_label.text == "林宇航", "顾客真实姓名未接入右栏")
	await _shoot("03-选中顾客")

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
	var img := root.get_texture().get_image()
	img.save_png(OUT_DIR + label + ".png")

	var zoomed := img.duplicate() as Image
	zoomed.resize(img.get_width() * ZOOM, img.get_height() * ZOOM, Image.INTERPOLATE_NEAREST)
	zoomed.save_png(OUT_DIR + label + "@%dx.png" % ZOOM)
	if label == "04-装修槽位":
		zoomed.save_png("res://../docs/ui/preview/decor_before@2x.png")
	elif label == "05-装修已安装":
		zoomed.save_png("res://../docs/ui/preview/decor_after@2x.png")
	print("SHOT %s (%dx%d)" % [label, img.get_width(), img.get_height()])
