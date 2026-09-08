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

var money: float = 800.0
var day: int = 1
var player_level: int = 1
var reputation_value := 3.5
var watt_minutes := 0.0
var business_phase := "closed"
var last_report: Dictionary = {
	"day": 0, "revenue": 0, "expense": 0, "electricity": 0,
	"customers": 0, "dirty": 0, "broken": 0,
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
	var scale := float(tuning.get("reputation_decor_scale", 0.05))
	return clampf(reputation_value + float(bonus) * scale, 1.0, 5.0)


func clean_score() -> int:
	var bonus := 0
	var dirty := 0
	var broken := 0
	if stage:
		bonus = int(stage.business_bonuses.get("clean", 0))
		dirty = stage.count_pc_state("待清洁")
		broken = stage.count_pc_state("故障")
	return clampi(
		int(tuning.get("clean_base", 42)) + bonus
		- dirty * int(tuning.get("clean_dirty_penalty", 3))
		- broken * int(tuning.get("clean_broken_penalty", 2)),
		0, 100
	)


func comfort_score() -> int:
	if stage == null:
		return 0
	return int(stage.business_bonuses.get("comfort", 0))


func pending_electricity() -> int:
	var rate := float(tuning.get("electricity_yuan_per_kwh", 0.85))
	return int(round(watt_minutes / 1000.0 / 60.0 * rate))


func today_electricity() -> int:
	var pending := pending_electricity()
	if pending > 0:
		return pending
	var total := 0
	for row in ledger.entries:
		if int(row["day"]) == day and str(row.get("ref", "")) == "electricity":
			total += int(row["amount"])
	return total


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


func spend(amount: int, note: String, ref := "", allow_overdraft := false) -> bool:
	if amount <= 0:
		return true
	if money < float(amount) and not allow_overdraft:
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
	watt_minutes = 0.0
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
	var electricity := _settle_electricity()
	last_report = {
		"day": day,
		"revenue": ledger.day_income(day),
		"expense": ledger.day_expense(day),
		"electricity": electricity,
		"customers": served_today,
		"dirty": stage.count_pc_state("待清洁") if stage else 0,
		"broken": stage.count_pc_state("故障") if stage else 0,
	}
	if stage:
		stage.clear_all_customers()
	day += 1
	served_today = 0
	_refresh_player_level()
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
	var shown_rep := reputation()
	var rep_scale := shown_rep / float(tuning.get("starting_reputation", 3.5))
	if rep_scale <= 0.0:
		rep_scale = 1.0
	return maxi(4, int(round(float(base) * 100.0 / float(100 + traffic) / rep_scale)))


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
	var config: Dictionary = stage.get_pc_config(pc_index)
	var remaining := maxi(1, clock.day_length - clock.minute)
	var overnight := _is_overnight(habit)
	var duration: int
	if overnight:
		duration = remaining
	else:
		var preferred := int(round(float(habit.get("session_hours", 2.0)) * 60.0))
		duration = preferred + rng.randi_range(-20, 20)
	var comfort_scale := 1.0 + float(comfort_score()) * float(tuning.get("comfort_duration_scale", 0.01))
	duration = int(round(float(duration) * comfort_scale))
	var mood := _mood_label(_mood_score(index, pc_index, habit))
	if mood == "满意":
		duration = int(round(float(duration) * float(tuning.get("mood_good_duration", 1.1))))
	elif mood == "不满":
		duration = int(round(float(duration) * float(tuning.get("mood_bad_duration", 0.8))))
	if overnight:
		duration = clampi(duration, 1, remaining)
	else:
		duration = clampi(
			duration,
			int(tuning.get("session_minutes_min", 40)),
			int(tuning.get("session_minutes_max", 180))
		)
	stage.customer_data[index]["mood"] = mood
	stage.start_session(pc_index, index, clock.minute, duration, float(config.get("hourly_rate", 3)), {
		"overnight": overnight,
		"overnight_rate": int(config.get("overnight_rate", 26)),
		"mood": mood,
		"assigned_at": clock.minute,
	})
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
		"starting_reputation", "reputation_decor_scale", "reputation_mood_good",
		"reputation_mood_bad", "clean_base", "comfort_duration_scale",
		"mood_good_threshold", "mood_bad_threshold", "electricity_yuan_per_kwh",
		"store_base_watts", "ac_watts",
	]:
		assert(tuning.has(key), "sim_tuning.json 缺少字段：%s" % key)


func _reset_economy() -> void:
	money = float(tuning.get("starting_money", 800))
	day = int(tuning.get("starting_day", 1))
	reputation_value = float(tuning.get("starting_reputation", 3.5))
	watt_minutes = 0.0
	_refresh_player_level()
	business_phase = "closed"
	served_today = 0
	next_spawn_minute = 0
	last_report = {
		"day": 0, "revenue": 0, "expense": 0, "electricity": 0,
		"customers": 0, "dirty": 0, "broken": 0,
	}
	ledger.clear()
	clock.reset_day()
	clock.set_speed(0.0 if test_mode else 1.0)


func _on_minute() -> void:
	if stage == null:
		return
	if business_phase == "open" or business_phase == "closing":
		_accumulate_electricity()
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
	var profile: Dictionary = _pick_weighted_profile(pool)
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
	var bill := 0
	if bool(session.get("overnight", false)):
		bill = int(session.get("overnight_rate", 26))
	else:
		bill = int(round(float(session.get("hourly_rate", 3)) * float(used) / 60.0))
	_apply_mood_reputation(str(session.get("mood", "普通")))
	var dirty_chance := float(tuning["dirty_chance"])
	if clean_score() < 40:
		dirty_chance += float(tuning.get("dirty_chance_low_clean", 0.08))
	var roll := rng.randf()
	var next_state := "空闲"
	if roll < float(tuning["broken_chance"]):
		next_state = "故障"
	elif roll < float(tuning["broken_chance"]) + dirty_chance:
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
		"reputation_value": reputation_value,
		"watt_minutes": watt_minutes,
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
	money = float(data.get("money", tuning.get("starting_money", 800)))
	day = int(data.get("day", 1))
	reputation_value = float(data.get("reputation_value", tuning.get("starting_reputation", 3.5)))
	watt_minutes = float(data.get("watt_minutes", 0.0))
	_refresh_player_level()
	business_phase = str(data.get("business_phase", "closed"))
	served_today = int(data.get("served_today", 0))
	next_spawn_minute = int(data.get("next_spawn_minute", 0))
	rng.seed = int(data.get("rng_seed", rng.seed))
	clock.minute = int(data.get("clock_minute", 0))
	clock.accumulator = 0.0
	clock.set_speed(0.0 if test_mode else float(data.get("clock_speed", 1.0)))
	last_report = data.get("last_report", last_report)
	ledger.from_array(data.get("ledger", []))


func _refresh_player_level() -> void:
	player_level = clampi(1 + (day - 1) / 2, 1, 6)


func _is_overnight(habit: Dictionary) -> bool:
	return (
		str(habit.get("spending_focus", "")).contains("包夜")
		or str(habit.get("type", "")).contains("夜间包时")
	)


func _period_matches(preferred: String, clock_period: String) -> bool:
	if preferred == "周末":
		return false
	if clock_period == "上午":
		return preferred == "白天"
	if clock_period == "下午":
		return preferred == "午后"
	if clock_period == "晚上":
		return preferred in ["晚间", "夜间", "深夜"]
	return false


func _pick_weighted_profile(pool: Array) -> Dictionary:
	var clock_period := str(clock.period())
	var match_weight := int(tuning.get("spawn_period_match_weight", 3))
	var total := 0
	var weights: Array[int] = []
	for profile in pool:
		var habit: Dictionary = profile.get("internet_habit", {})
		var weight := match_weight if _period_matches(str(habit.get("preferred_period", "")), clock_period) else 1
		weights.append(weight)
		total += weight
	var roll := rng.randi_range(1, maxi(1, total))
	var acc := 0
	for index in range(pool.size()):
		acc += weights[index]
		if roll <= acc:
			return pool[index]
	return pool[pool.size() - 1]


func _mood_score(customer_index: int, pc_index: int, habit: Dictionary) -> float:
	var score := 50.0
	var focus := str(habit.get("spending_focus", ""))
	var zone := str(stage.pc_data[pc_index]["zone"])
	var preferred: Array = stage.preferred_zones_for(focus)
	if preferred.find(zone) == 0:
		score += 15.0
	else:
		score -= 10.0
	if _period_matches(str(habit.get("preferred_period", "")), str(clock.period())):
		score += 10.0
	score += float(mini(15, comfort_score() / 2))
	score += float(clean_score() - 40) / 4.0
	if focus.contains("高配") and int(stage.get_pc_config(pc_index).get("performance_score", 0)) < 50:
		score -= 10.0
	var queued_at := int(stage.customer_data[customer_index].get("queued_at", clock.minute))
	score -= float(clampi(clock.minute - queued_at, 0, 20))
	return score


func _mood_label(score: float) -> String:
	if score >= float(tuning.get("mood_good_threshold", 70)):
		return "满意"
	if score < float(tuning.get("mood_bad_threshold", 40)):
		return "不满"
	return "普通"


func _apply_mood_reputation(mood: String) -> void:
	if mood == "满意":
		reputation_value += float(tuning.get("reputation_mood_good", 0.03))
	elif mood == "不满":
		reputation_value += float(tuning.get("reputation_mood_bad", -0.05))
	reputation_value = clampf(reputation_value, 1.0, 5.0)


func current_watts() -> int:
	var watts := int(tuning.get("store_base_watts", 2000))
	if stage == null:
		return watts
	watts += stage.installed_ac_count() * int(tuning.get("ac_watts", 800))
	for pc in stage.pc_data:
		if str(pc["state"]) != "已关机":
			watts += int(pc.get("config", {}).get("power_watts", 240))
	return watts


func _accumulate_electricity() -> void:
	watt_minutes += float(current_watts())


func _settle_electricity() -> int:
	var cost := pending_electricity()
	if cost > 0:
		spend(cost, "电费", "electricity", true)
	watt_minutes = 0.0
	return cost
