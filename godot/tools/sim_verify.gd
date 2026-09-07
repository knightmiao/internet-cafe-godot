extends SceneTree
## 固定种子连测三个营业日，断言余额、会话、清洁维修和读档。
## 用法：godot --path godot --script res://tools/sim_verify.gd

const SEED := 20260907

var GS: Node


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	GS = root.get_node("GameState")
	GS.begin_test(SEED)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	var stage: StageController = GS.stage
	assert(stage != null)
	assert(GS.business_phase == "closed")
	assert(stage.active_session_count() == 0)
	assert(stage.active_customer_count() == 0)

	var starting_money: float = GS.money
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
	assert(
		is_equal_approx(GS.money, starting_money + float(GS.ledger.net())),
		"余额必须等于开局资金加流水净额"
	)
	assert(stage.active_session_count() == 0, "关店后不能残留进行中会话")

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
	var saved_money: float = GS.money
	assert(GS.save_game())
	GS.money = 0.0
	GS.day = 99
	assert(GS.load_save(), "读档失败")
	assert(GS.day == saved_day, "读档后天数不一致")
	assert(is_equal_approx(GS.money, saved_money), "读档后资金不一致")
	assert(stage.get_pc_state(5) == "已关机")

	print("SIM_OK day=%d money=%d net=%d served_last=%d" % [
		GS.day, int(GS.money), GS.ledger.net(),
		int(GS.last_report.get("customers", 0)),
	])
	quit()
