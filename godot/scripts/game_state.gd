extends Node
## 经营内核：资金、日期、三态、时钟、流水和存档。场景表现由 StageController 承担。

signal money_changed(amount: float)
signal phase_changed(phase: String)
signal clock_updated
signal day_settled(report: Dictionary)

const TUNING_PATH := "res://data/sim_tuning.json"
const SAVE_VERSION := 1
const ClockScript := preload("res://scripts/sim/clock.gd")
const LedgerScript := preload("res://scripts/sim/ledger.gd")
const SaveScript := preload("res://scripts/sim/save_service.gd")

var money: float = 500.0
var day: int = 1
var player_level: int = 3
var business_phase := "closed"
var last_report: Dictionary = {
	"day": 0, "revenue": 0, "expense": 0, "customers": 0, "dirty": 0, "broken": 0,
}
var served_today := 0
var next_spawn_minute := 0
var test_mode := false
var tuning: Dictionary = {}
var rng := RandomNumberGenerator.new()
var clock
var ledger
var save_service
var stage: StageController


func _ready() -> void:
	_load_tuning()
	clock = ClockScript.new()
	clock.configure(tuning)
	ledger = LedgerScript.new()
	save_service = SaveScript.new()
	rng.randomize()
	_reset_economy()


func _process(delta: float) -> void:
	if business_phase != "open" and business_phase != "closing":
		return
	if clock.speed <= 0.0:
		return
	var steps: int = clock.advance(delta)
	if steps <= 0:
		return
	for _i in range(steps):
		_on_minute()
		if clock.minute >= clock.day_length and business_phase == "open":
			stop_admission()
			break
	clock_updated.emit()


func bind_stage(controller: StageController) -> void:
	stage = controller
	if test_mode:
		start_new_game()
		return
	if save_service.has_save():
		load_save()
	else:
		start_new_game()


func begin_test(seed: int = 20260907) -> void:
	test_mode = true
	save_service.set_test_mode(true)
	save_service.clear()
	rng.seed = seed
	_reset_economy()


func start_new_game() -> void:
	_reset_economy()
	if stage:
		stage.reset_simulation()


func is_open() -> bool:
	return business_phase == "open"


func today_revenue() -> int:
	return ledger.day_income(day)


func reputation() -> float:
	var bonus := 0
	if stage:
		bonus = int(stage.business_bonuses.get("reputation", 0))
	return 3.5 + float(bonus) * 0.05


func clean_score() -> int:
	var bonus := 0
	if stage:
		bonus = int(stage.business_bonuses.get("clean", 0))
	return 42 + bonus


func decor_score() -> int:
	var bonus := 0
	if stage:
		bonus = int(stage.business_bonuses.get("decor", 0))
	return 50 + bonus


func earn(amount: int, note: String, ref := "") -> void:
	if amount <= 0:
		return
	money += float(amount)
	ledger.add(day, clock.minute, "income", amount, note, ref)
	money_changed.emit(money)


func spend(amount: int, note: String, ref := "") -> bool:
	if amount <= 0:
		return true
	if money < float(amount):
		return false
	money -= float(amount)
	ledger.add(day, clock.minute, "expense", amount, note, ref)
	money_changed.emit(money)
	return true


func open_shop() -> void:
	if business_phase != "closed":
		return
	business_phase = "open"
	clock.reset_day()
	if not test_mode:
		clock.set_speed(1.0)
	served_today = 0
	if stage:
		stage.prepare_open()
	_try_spawn()
	next_spawn_minute = spawn_interval()
	phase_changed.emit(business_phase)
	clock_updated.emit()


func stop_admission() -> void:
	if business_phase != "open":
		return
	business_phase = "closing"
	if stage:
		for pc_index in range(stage.pc_data.size()):
			if not stage.pc_data[pc_index].get("session", {}).is_empty():
				_end_session(pc_index, true)
		for customer_index in stage.waiting_indices():
			stage.dismiss_customer(customer_index)
	phase_changed.emit(business_phase)
	clock_updated.emit()


func close_settlement() -> bool:
	if business_phase != "closing":
		return false
	if stage and stage.active_customer_count() > 0:
		return false
	last_report = {
		"day": day,
		"revenue": ledger.day_income(day),
		"expense": ledger.day_expense(day),
		"customers": served_today,
		"dirty": stage.count_pc_state("待清洁") if stage else 0,
		"broken": stage.count_pc_state("故障") if stage else 0,
	}
	if stage:
		stage.clear_all_customers()
	day += 1
	served_today = 0
	business_phase = "closed"
	clock.reset_day()
	save_game()
	phase_changed.emit(business_phase)
	day_settled.emit(last_report)
	clock_updated.emit()
	return true


func tick_minutes(count: int) -> void:
	for _i in range(count):
		if clock.minute >= clock.day_length:
			if business_phase == "open":
				stop_admission()
			break
		clock.advance_one_minute()
		_on_minute()
		if clock.minute >= clock.day_length and business_phase == "open":
			stop_admission()
			break
	clock_updated.emit()


func spawn_interval() -> int:
	var period: String = clock.period()
	var base := int(tuning.get("spawn_interval_morning", 12))
	if period == "下午":
		base = int(tuning.get("spawn_interval_afternoon", 8))
	elif period == "晚上":
		base = int(tuning.get("spawn_interval_evening", 6))
	var traffic := 0
	if stage:
		traffic = int(stage.business_bonuses.get("traffic", 0))
	return maxi(4, int(round(float(base) * 100.0 / float(100 + traffic))))


func spawn_from_profile_index(profile_index: int, state := "排队中") -> int:
	if stage == null or profile_index < 0 or profile_index >= stage.customer_profiles.size():
		return -1
	return stage.spawn_customer(stage.customer_profiles[profile_index], clock.minute, state)


func assign_customer(index: int) -> bool:
	if stage == null or index < 0 or index >= stage.customer_data.size():
		return false
	var state := str(stage.customer_data[index]["state"])
	if state != "排队中" and state != "待接待":
		return false
	var pc_index := stage.pick_pc_for_customer(index)
	if pc_index < 0:
		return false
	var profile: Dictionary = stage.get_customer_profile(index)
	var habit: Dictionary = profile.get("internet_habit", {})
	var preferred := int(round(float(habit.get("session_hours", 2.0)) * 60.0))
	var duration := clampi(
		preferred + rng.randi_range(-20, 20),
		int(tuning.get("session_minutes_min", 40)),
		int(tuning.get("session_minutes_max", 180))
	)
	var rate := float(stage.get_pc_config(pc_index).get("hourly_rate", 3))
	stage.start_session(pc_index, index, clock.minute, duration, rate)
	return true


func assign_waiting() -> int:
	if stage == null:
		return -1
	var waiting := stage.waiting_indices()
	if waiting.is_empty():
		return -1
	var index: int = waiting[0]
	return index if assign_customer(index) else -1


func checkout_customer(index: int) -> int:
	if stage == null or index < 0 or index >= stage.customer_data.size():
		return 0
	if str(stage.customer_data[index]["state"]) != "待结账":
		return 0
	var bill := stage.customer_bill(index)
	var profile: Dictionary = stage.get_customer_profile(index)
	if bill > 0:
		earn(bill, "网费 %s" % profile.get("name", "顾客"), "customer:%s" % profile.get("id", ""))
	served_today += 1
	stage.dismiss_customer(index)
	return bill


func checkout_all_pending() -> int:
	if stage == null:
		return 0
	var total := 0
	var pending := stage.checkout_indices()
	pending.reverse()
	for index in pending:
		total += checkout_customer(index)
	return total


func checkout_next() -> int:
	if stage == null:
		return 0
	var pending := stage.checkout_indices()
	if pending.is_empty():
		return 0
	return checkout_customer(pending[0])


func dismiss_customer(index: int) -> void:
	if stage:
		stage.dismiss_customer(index)


func clean_pc(index: int) -> bool:
	if stage == null or stage.get_pc_state(index) != "待清洁":
		return false
	stage.set_pc_state(index, "空闲" if business_phase != "closed" else "已关机")
	return true


func repair_pc(index: int) -> bool:
	if stage == null or stage.get_pc_state(index) != "故障":
		return false
	var cost := int(tuning.get("repair_cost", 50))
	if not spend(cost, "维修 %02d号机" % (index + 1), "pc:%d" % index):
		return false
	stage.set_pc_state(index, "空闲" if business_phase != "closed" else "已关机")
	return true


func toggle_pc_power(index: int) -> bool:
	if stage == null:
		return false
	var state := stage.get_pc_state(index)
	if state == "使用中":
		return false
	if state == "已关机":
		stage.set_pc_state(index, "空闲")
		return true
	if state == "空闲":
		stage.set_pc_state(index, "已关机")
		return true
	return false


func debug_set_pc_state(index: int, state: String) -> void:
	if stage:
		stage.clear_session(index)
		stage.set_pc_state(index, state)


func save_game() -> bool:
	if stage == null:
		return save_service.write(_economy_snapshot())
	return save_service.write(_full_snapshot())


func load_save() -> bool:
	var data := save_service.read() as Dictionary
	if data.is_empty() or int(data.get("version", 0)) != SAVE_VERSION:
		return false
	_apply_economy(data)
	if stage:
		stage.import_world_state(data)
	clock_updated.emit()
	phase_changed.emit(business_phase)
	return true


func _load_tuning() -> void:
	var file := FileAccess.open(TUNING_PATH, FileAccess.READ)
	assert(file != null, "无法读取模拟调参：%s" % TUNING_PATH)
	var parsed = JSON.parse_string(file.get_as_text())
	assert(parsed is Dictionary, "sim_tuning.json 必须是对象")
	tuning = parsed
	for key in [
		"day_length_minutes", "seconds_per_game_minute", "session_minutes_min",
		"session_minutes_max", "dirty_chance", "broken_chance", "repair_cost",
		"queue_max", "auto_assign_wait_minutes", "spawn_interval_morning",
		"spawn_interval_afternoon", "spawn_interval_evening", "starting_money",
	]:
		assert(tuning.has(key), "sim_tuning.json 缺少字段：%s" % key)


func _reset_economy() -> void:
	money = float(tuning.get("starting_money", 500))
	day = int(tuning.get("starting_day", 1))
	player_level = 3
	business_phase = "closed"
	served_today = 0
	next_spawn_minute = 0
	last_report = {
		"day": 0, "revenue": 0, "expense": 0, "customers": 0, "dirty": 0, "broken": 0,
	}
	ledger.clear()
	clock.reset_day()
	clock.set_speed(0.0 if test_mode else 1.0)


func _on_minute() -> void:
	if stage == null:
		return
	if business_phase == "open":
		if clock.minute >= next_spawn_minute:
			_try_spawn()
			next_spawn_minute = clock.minute + spawn_interval()
		_try_auto_assign()
	if business_phase == "open" or business_phase == "closing":
		for pc_index in stage.due_sessions(clock.minute):
			_end_session(pc_index, false)


func _try_spawn() -> void:
	if stage == null or business_phase != "open":
		return
	if stage.waiting_count() >= int(tuning.get("queue_max", 6)):
		return
	var busy_ids := {}
	for data in stage.customer_data:
		if str(data["state"]) != "离店":
			busy_ids[str(data["profile"]["id"])] = true
	var pool: Array = []
	for profile in stage.customer_profiles:
		if not busy_ids.has(str(profile["id"])):
			pool.append(profile)
	if pool.is_empty():
		pool = stage.customer_profiles
	if pool.is_empty():
		return
	var profile: Dictionary = pool[rng.randi_range(0, pool.size() - 1)]
	stage.spawn_customer(profile, clock.minute, "排队中")


func _try_auto_assign() -> void:
	var wait_limit := int(tuning.get("auto_assign_wait_minutes", 15))
	for index in stage.waiting_indices():
		var queued_at := int(stage.customer_data[index].get("queued_at", clock.minute))
		if clock.minute - queued_at >= wait_limit:
			stage.set_customer_state(index, "待接待")
			assign_customer(index)


func _end_session(pc_index: int, forced: bool) -> void:
	var session: Dictionary = stage.take_session(pc_index)
	if session.is_empty():
		return
	var used := int(session["planned_duration"])
	if forced:
		used = maxi(0, clock.minute - int(session["start_minute"]))
	var bill := int(round(float(session["hourly_rate"]) * float(used) / 60.0))
	var roll := rng.randf()
	var next_state := "空闲"
	if roll < float(tuning["broken_chance"]):
		next_state = "故障"
	elif roll < float(tuning["broken_chance"]) + float(tuning["dirty_chance"]):
		next_state = "待清洁"
	stage.set_pc_state(pc_index, next_state)
	var customer_index := int(session.get("customer_index", -1))
	if customer_index < 0:
		return
	if bill > 0:
		stage.send_to_checkout(customer_index, bill)
	else:
		stage.dismiss_customer(customer_index)


func _economy_snapshot() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"money": money,
		"day": day,
		"player_level": player_level,
		"business_phase": business_phase,
		"served_today": served_today,
		"next_spawn_minute": next_spawn_minute,
		"rng_seed": rng.seed,
		"clock_minute": clock.minute,
		"clock_speed": clock.speed,
		"last_report": last_report,
		"ledger": ledger.to_array(),
	}


func _full_snapshot() -> Dictionary:
	var data: Dictionary = _economy_snapshot()
	data.merge(stage.export_world_state())
	return data


func _apply_economy(data: Dictionary) -> void:
	money = float(data.get("money", tuning.get("starting_money", 500)))
	day = int(data.get("day", 1))
	player_level = int(data.get("player_level", 3))
	business_phase = str(data.get("business_phase", "closed"))
	served_today = int(data.get("served_today", 0))
	next_spawn_minute = int(data.get("next_spawn_minute", 0))
	rng.seed = int(data.get("rng_seed", rng.seed))
	clock.minute = int(data.get("clock_minute", 0))
	clock.accumulator = 0.0
	clock.set_speed(0.0 if test_mode else float(data.get("clock_speed", 1.0)))
	last_report = data.get("last_report", last_report)
	ledger.from_array(data.get("ledger", []))
