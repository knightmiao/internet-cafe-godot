class_name EventService
extends RefCounted
## 随机事件与消息收件箱。每天最多抽一条，测试模式不自动抽。

const CATALOG_PATH := "res://data/events_catalog.json"
const INBOX_CAP := 12

var catalog: Array = []
var inbox: Array[Dictionary] = []
var pending: Dictionary = {}
var fired_today: Array[String] = []
var traffic_bonus := 0
var next_event_minute := 80
var _seq := 1


func load_catalog() -> void:
	var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	assert(file != null, "无法读取事件目录：%s" % CATALOG_PATH)
	var parsed = JSON.parse_string(file.get_as_text())
	assert(parsed is Dictionary and parsed.get("events") is Array, "events_catalog.json 必须有 events")
	catalog = parsed["events"]
	assert(catalog.size() >= 6, "第一批事件至少 6 条")
	for event in catalog:
		assert(str(event.get("id", "")) != "", "事件缺少 id")
		assert(event.get("choices") is Array and event["choices"].size() >= 1, "事件必须有选项")


func reset() -> void:
	inbox.clear()
	pending = {}
	fired_today.clear()
	traffic_bonus = 0
	next_event_minute = 80
	_seq = 1


func begin_day(rng: RandomNumberGenerator, first_min: int, first_max: int) -> void:
	pending = {}
	fired_today.clear()
	traffic_bonus = 0
	next_event_minute = rng.randi_range(first_min, first_max)


func to_dict() -> Dictionary:
	return {
		"inbox": inbox.duplicate(true),
		"pending_id": str(pending.get("id", "")),
		"fired_today": fired_today.duplicate(),
		"traffic_bonus": traffic_bonus,
		"next_event_minute": next_event_minute,
		"seq": _seq,
	}


func from_dict(data: Dictionary) -> void:
	inbox.clear()
	for row in data.get("inbox", []):
		if row is Dictionary:
			inbox.append((row as Dictionary).duplicate(true))
	fired_today.clear()
	for event_id in data.get("fired_today", []):
		fired_today.append(str(event_id))
	traffic_bonus = int(data.get("traffic_bonus", 0))
	next_event_minute = int(data.get("next_event_minute", 80))
	_seq = int(data.get("seq", 1))
	var pending_id := str(data.get("pending_id", ""))
	pending = find_event(pending_id)


func find_event(event_id: String) -> Dictionary:
	if event_id.is_empty():
		return {}
	for event in catalog:
		if str(event.get("id", "")) == event_id:
			return event
	return {}


func has_pending() -> bool:
	return not pending.is_empty()


func unread_count() -> int:
	var total := 0
	for row in inbox:
		if bool(row.get("unread", false)):
			total += 1
	return total


func mark_read(item_id: String) -> void:
	for row in inbox:
		if str(row.get("id", "")) == item_id:
			row["unread"] = false
			return


func mark_all_read() -> void:
	for row in inbox:
		row["unread"] = false


func can_roll(minute: int, max_per_day: int) -> bool:
	if has_pending():
		return false
	if fired_today.size() >= max_per_day:
		return false
	return minute >= next_event_minute


func eligible(event: Dictionary, period: String, has_session: bool) -> bool:
	var event_id := str(event.get("id", ""))
	if event_id.is_empty() or fired_today.has(event_id):
		return false
	var when: Array = event.get("when", [])
	if not when.is_empty() and not when.has(period):
		return false
	if str(event.get("require", "")) == "session" and not has_session:
		return false
	return true


func pick(rng: RandomNumberGenerator, period: String, has_session: bool) -> Dictionary:
	var pool: Array = []
	var total := 0
	for event in catalog:
		if not eligible(event, period, has_session):
			continue
		var weight := maxi(1, int(event.get("weight", 1)))
		pool.append({"event": event, "weight": weight})
		total += weight
	if pool.is_empty() or total <= 0:
		return {}
	var roll := rng.randi_range(1, total)
	var acc := 0
	for row in pool:
		acc += int(row["weight"])
		if roll <= acc:
			return row["event"]
	return pool[pool.size() - 1]["event"]


func offer(event: Dictionary) -> bool:
	if event.is_empty() or has_pending():
		return false
	pending = event
	var event_id := str(event.get("id", ""))
	if not fired_today.has(event_id):
		fired_today.append(event_id)
	return true


func offer_by_id(event_id: String, force := false) -> bool:
	var event := find_event(event_id)
	if event.is_empty():
		return false
	if has_pending():
		return false
	if not force and fired_today.has(event_id):
		return false
	return offer(event)


func resolve(choice_id: String, host: Node) -> Dictionary:
	if pending.is_empty():
		return {}
	var choice := _find_choice(pending, choice_id)
	if choice.is_empty():
		return {}
	var effects: Dictionary = choice.get("effects", {})
	var summary := _apply_effects(effects, host)
	var event: Dictionary = pending
	var title := str(event.get("title", "事件"))
	var body := str(choice.get("label", "已处理"))
	if not summary.is_empty():
		body = "%s。%s" % [body, summary]
	_push_inbox(title, body)
	pending = {}
	return {"event_id": str(event.get("id", "")), "choice_id": choice_id, "summary": summary}


func _find_choice(event: Dictionary, choice_id: String) -> Dictionary:
	for choice in event.get("choices", []):
		if str(choice.get("id", "")) == choice_id:
			return choice
	return {}


func _apply_effects(effects: Dictionary, host: Node) -> String:
	var notes: Array[String] = []
	if effects.has("money"):
		var amount := int(effects["money"])
		if amount > 0:
			host.earn(amount, "事件收入", "event")
			notes.append("收入 ¥%d" % amount)
		elif amount < 0:
			host.spend(-amount, "事件支出", "event", true)
			notes.append("支出 ¥%d" % -amount)
	if effects.has("reputation"):
		var delta := float(effects["reputation"])
		host.adjust_reputation(delta)
		notes.append("声誉 %+.2f" % delta)
	if effects.has("traffic"):
		var delta := int(effects["traffic"])
		traffic_bonus += delta
		notes.append("客流 %+d" % delta)
	if bool(effects.get("end_session", false)):
		if host.end_random_session():
			notes.append("已劝下一台")
	if int(effects.get("spawn", 0)) > 0:
		for _i in range(int(effects["spawn"])):
			host.spawn_extra_customer()
		notes.append("门口多来了人")
	return " · ".join(notes)


func _push_inbox(title: String, body: String) -> void:
	inbox.append({
		"id": "msg_%d" % _seq,
		"title": title,
		"body": body,
		"day": 0,
		"minute": 0,
		"unread": true,
	})
	_seq += 1
	while inbox.size() > INBOX_CAP:
		inbox.pop_front()


func stamp_latest(day: int, minute: int) -> void:
	if inbox.is_empty():
		return
	inbox[inbox.size() - 1]["day"] = day
	inbox[inbox.size() - 1]["minute"] = minute
