extends SceneTree
## 固定种子连测三个营业日，断言余额、电费、包夜一口价、清洁维修和读档。
## 用法：godot --path godot --script res://tools/sim_verify.gd

const SEED := 20260907

var GS: Node


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	GS = root.get_node("GameState")
	GS.begin_test(SEED)
	var sfx: Node = root.get_node_or_null("Sfx")
	assert(sfx != null, "必须注册 Sfx Autoload")
	assert(sfx.catalog.size() >= 16, "音效目录必须包含第一批 cue")
	assert(sfx.enabled == false, "测试模式必须静音")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	_assert_window_scale()

	var stage: StageController = GS.stage
	assert(stage != null)
	assert(GS.business_phase == "closed")
	assert(stage.active_session_count() == 0)
	assert(stage.active_customer_count() == 0)
	assert(is_equal_approx(GS.money, 800.0), "开局周转金必须是 800")
	assert(GS.player_level == 1, "开局等级必须是 1")

	var starting_money: float = GS.money
	await _assert_hotkeys(main)
	for _day_index in range(3):
		for pc_index in range(stage.pc_data.size()):
			if stage.get_pc_state(pc_index) == "待清洁":
				GS.clean_pc(pc_index)
		GS.open_shop()
		assert(GS.business_phase == "open")
		GS.tick_minutes(GS.clock.day_length)
		if GS.business_phase == "open":
			GS.stop_admission()
		assert(GS.business_phase == "closing")
		assert(stage.active_session_count() == 0)
		GS.checkout_all_pending()
		assert(stage.active_customer_count() == 0)
		assert(GS.close_settlement())
		assert(GS.business_phase == "closed")

	assert(GS.day == 4, "连营三日后应进入第 4 天")
	assert(GS.player_level == 2, "第 4 天等级应为 2")
	assert(_ledger_electricity() > 0, "三日后电费支出必须大于 0")
	assert(
		is_equal_approx(GS.money, starting_money + float(GS.ledger.net())),
		"余额必须等于开局资金加流水净额"
	)
	assert(stage.active_session_count() == 0, "关店后不能残留进行中会话")

	_assert_overnight_flat_rate(stage)
	_assert_electricity_responds(stage)

	GS.debug_set_pc_state(3, "待清洁")
	assert(GS.clean_pc(3), "待清洁机位必须能清洁")
	assert(stage.get_pc_state(3) == "已关机")

	var money_before_repair: float = GS.money
	GS.debug_set_pc_state(5, "故障")
	assert(GS.repair_pc(5), "故障机位必须能维修")
	assert(stage.get_pc_state(5) == "已关机")
	assert(is_equal_approx(GS.money, money_before_repair - 50.0), "维修必须扣 50 元")
	assert(GS.ledger.day_expense(GS.day) >= 50)

	var saved_day: int = GS.day
	assert(GS.hire_clerk(), "必须能招聘前台")
	var saved_clerks: int = GS.staff_clerks
	var saved_money: float = GS.money
	assert(GS.save_game())
	GS.money = 0.0
	GS.day = 99
	GS.staff_clerks = 0
	assert(GS.load_save(), "读档失败")
	assert(GS.day == saved_day, "读档后天数不一致")
	assert(is_equal_approx(GS.money, saved_money), "读档后资金不一致")
	assert(GS.staff_clerks == saved_clerks, "读档后前台人数不一致")
	assert(stage.get_pc_state(5) == "已关机")

	GS.start_new_game()
	assert(is_equal_approx(GS.money, 800.0), "重新开局必须回到 800 元")
	assert(GS.day == 1, "重新开局必须回到第 1 天")
	assert(GS.player_level == 1, "重新开局必须回到 1 级")
	assert(GS.business_phase == "closed")
	assert(stage.active_customer_count() == 0)
	assert(GS.staff_clerks == 0, "重新开局必须清掉前台")
	_assert_auto_service(stage)
	_assert_events(main)

	print("SIM_OK day=%d money=%d net=%d elec=%d served_last=%d" % [
		GS.day, int(GS.money), GS.ledger.net(), _ledger_electricity(),
		int(GS.last_report.get("customers", 0)),
	])
	quit()


func _assert_auto_service(stage: StageController) -> void:
	assert(GS.desk_slots() == 1, "开局只有老板一个办理位")
	GS.open_shop()
	assert(stage.waiting_count() >= 1, "开店必须有人排队")
	GS.tick_minutes(2)
	assert(stage.active_session_count() == 0, "接待未满 3 分钟不该上机")
	GS.tick_minutes(1)
	assert(stage.active_session_count() >= 1, "接待满 3 分钟必须自动上机")
	GS.tick_minutes(40)
	GS.stop_admission()
	var pending := stage.checkout_indices().size()
	assert(pending >= 1, "收尾后应进入结账队列")
	GS.tick_minutes(1)
	assert(stage.checkout_indices().size() == pending, "结账未满 2 分钟不该离店")
	GS.tick_minutes(1)
	assert(stage.checkout_indices().size() < pending, "结账满 2 分钟必须自动收银离店")
	var money_before_hire: float = GS.money
	assert(GS.hire_clerk(), "必须能招聘前台")
	assert(GS.desk_slots() == 2, "雇一名前台后应有两个办理位")
	assert(is_equal_approx(GS.money, money_before_hire - 60.0), "招聘前台必须扣 60 元")
	assert(GS.hire_clerk())
	assert(GS.desk_slots() == 3)
	assert(not GS.hire_clerk(), "前台最多雇 2 人")
	GS.checkout_all_pending()
	if GS.business_phase == "closing":
		var money_before_close: float = GS.money
		assert(GS.close_settlement())
		assert(GS.money < money_before_close, "关店必须发前台日薪")


func _assert_hotkeys(main: Node) -> void:
	GS.open_shop()
	assert(GS.business_phase == "open")
	GS.clock.set_speed(1.0)
	Input.parse_input_event(_space_event())
	await process_frame
	assert(is_equal_approx(GS.clock.speed, 0.0), "开店后空格必须暂停")
	Input.parse_input_event(_space_event())
	await process_frame
	assert(is_equal_approx(GS.clock.speed, 1.0), "再按空格必须恢复上次速度")
	main.open_settings()
	assert(is_equal_approx(GS.clock.speed, 0.0), "打开设置必须暂停")
	Input.parse_input_event(_space_event())
	await process_frame
	assert(is_equal_approx(GS.clock.speed, 0.0), "设置打开时空格不改速度")
	main.close_settings()
	GS.start_new_game()
	assert(GS.business_phase == "closed")
	assert(is_equal_approx(GS.money, 800.0))


func _space_event() -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = KEY_SPACE
	event.physical_keycode = KEY_SPACE
	event.pressed = true
	event.echo = false
	return event


func _assert_events(main: Node) -> void:
	assert(GS.events != null and GS.events.catalog.size() >= 6, "事件目录必须有第一批 6 条")
	GS.start_new_game()
	GS.open_shop()
	GS.clock.set_speed(1.0)
	var money_before: float = GS.money
	assert(GS.debug_offer_event("inspection"), "必须能弹出抽查事件")
	assert(GS.has_pending_event())
	assert(main.inbox_overlay.is_decision(), "事件必须打开消息层")
	assert(is_equal_approx(GS.clock.speed, 0.0), "事件打开必须暂停")
	assert(not GS.resolve_event("missing"), "无效选项不能结算")
	main._on_event_choice("pay")
	assert(not GS.has_pending_event())
	assert(is_equal_approx(GS.money, money_before - 30.0), "抽查交钱必须扣 30")
	assert(GS.unread_inbox_count() >= 1, "处理后应写入收件箱")
	assert(not main.inbox_overlay.is_open())

	var interval_before: int = GS.spawn_interval()
	assert(GS.debug_offer_event("game_craze"))
	main._on_event_choice("open")
	assert(GS.event_traffic_bonus() == 24, "敞开接待必须加客流")
	assert(GS.spawn_interval() <= interval_before, "客流加成必须缩短间隔")

	GS.start_new_game()
	GS.open_shop()
	GS.tick_minutes(200)
	assert(not GS.has_pending_event(), "测试模式不能自动弹事件")


func _assert_window_scale() -> void:
	var SettingsSvc := preload("res://scripts/sim/settings_service.gd")
	var svc = SettingsSvc.new()
	svc.test_mode = true
	assert(svc.window_scale == 2, "默认窗口档应是小/2x")
	assert(svc.normalize_scale(1) == 2)
	assert(svc.normalize_scale(3) == 3)
	assert(svc.normalize_scale(5) == 4)
	assert(svc.window_size_for(2) == Vector2i(1280, 720))
	assert(svc.window_size_for(3) == Vector2i(1920, 1080))
	assert(svc.window_size_for(4) == Vector2i(2560, 1440))
	svc.apply_dict({"window_scale": 4})
	assert(svc.window_scale == 4)
	assert(svc.resolved_window_scale() == 4, "测试模式不应按屏幕下压档位")
	svc.apply_display()


func _ledger_electricity() -> int:
	var total := 0
	for row in GS.ledger.entries:
		if str(row.get("ref", "")) == "electricity":
			total += int(row["amount"])
	return total


func _assert_overnight_flat_rate(stage: StageController) -> void:
	for pc_index in range(stage.pc_data.size()):
		var state := stage.get_pc_state(pc_index)
		if state == "待清洁":
			GS.clean_pc(pc_index)
		elif state == "已关机":
			GS.toggle_pc_power(pc_index)
	GS.open_shop()
	var profile_index := _overnight_profile_index(stage)
	assert(profile_index >= 0, "角色库必须包含包夜客")
	var customer_index: int = GS.spawn_from_profile_index(profile_index)
	assert(customer_index >= 0)
	assert(GS.assign_customer(customer_index), "包夜客必须能上机")
	var session := {}
	for pc in stage.pc_data:
		var candidate: Dictionary = pc.get("session", {})
		if int(candidate.get("customer_index", -1)) == customer_index:
			session = candidate
			break
	assert(bool(session.get("overnight", false)), "包夜客会话必须标记 overnight")
	assert(int(session.get("planned_duration", 0)) > 180, "包夜时长应能超过 180 分钟")
	assert(int(session.get("overnight_rate", 0)) == 26, "9 系包夜一口价必须是 26")
	GS.stop_admission()
	assert(stage.customer_bill(customer_index) == 26, "强制收尾仍应收包夜一口价")
	GS.checkout_all_pending()
	assert(GS.close_settlement())


func _assert_electricity_responds(stage: StageController) -> void:
	var watts_full: int = GS.current_watts()
	var shutdowns := 0
	for pc_index in range(stage.pc_data.size()):
		if stage.get_pc_state(pc_index) == "空闲":
			assert(GS.toggle_pc_power(pc_index))
			shutdowns += 1
			if shutdowns >= 15:
				break
	assert(shutdowns > 0, "关店后应有空闲机可供关机")
	assert(GS.current_watts() < watts_full, "关掉空闲机后功耗必须下降")
	var watts_after_shutdown: int = GS.current_watts()
	stage.mark_decor_owned("wall_ac")
	assert(stage.install_decor("hall_utility", "wall_ac"), "壁挂空调安装失败")
	assert(GS.current_watts() == watts_after_shutdown + 800, "装空调后应增加 800W")


func _overnight_profile_index(stage: StageController) -> int:
	for index in range(stage.customer_profiles.size()):
		var habit: Dictionary = stage.customer_profiles[index].get("internet_habit", {})
		if (
			str(habit.get("spending_focus", "")).contains("包夜")
			or str(habit.get("type", "")).contains("夜间包时")
		):
			return index
	return -1
