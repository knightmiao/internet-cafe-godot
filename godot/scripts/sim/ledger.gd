class_name Ledger
extends RefCounted
## 经营流水。amount 恒为正，收入/支出靠 type 区分。

var entries: Array[Dictionary] = []


func add(day: int, minute: int, kind: String, amount: int, note: String, ref: String) -> void:
	entries.append({
		"day": day,
		"minute": minute,
		"type": kind,
		"amount": amount,
		"note": note,
		"ref": ref,
	})


func clear() -> void:
	entries.clear()


func to_array() -> Array:
	return entries.duplicate(true)


func from_array(rows: Array) -> void:
	entries.clear()
	for row in rows:
		if row is Dictionary:
			entries.append({
				"day": int(row.get("day", 1)),
				"minute": int(row.get("minute", 0)),
				"type": str(row.get("type", "income")),
				"amount": int(row.get("amount", 0)),
				"note": str(row.get("note", "")),
				"ref": str(row.get("ref", "")),
			})


func day_income(day: int) -> int:
	var total := 0
	for row in entries:
		if int(row["day"]) == day and str(row["type"]) == "income":
			total += int(row["amount"])
	return total


func day_expense(day: int) -> int:
	var total := 0
	for row in entries:
		if int(row["day"]) == day and str(row["type"]) == "expense":
			total += int(row["amount"])
	return total


func day_net(day: int) -> int:
	return day_income(day) - day_expense(day)


func net() -> int:
	var total := 0
	for row in entries:
		if str(row["type"]) == "income":
			total += int(row["amount"])
		else:
			total -= int(row["amount"])
	return total


func day_count(day: int) -> int:
	var total := 0
	for row in entries:
		if int(row["day"]) == day:
			total += 1
	return total


func day_ref_sum(day: int, kind: String, ref_prefix: String) -> int:
	var total := 0
	for row in entries:
		if int(row["day"]) != day or str(row["type"]) != kind:
			continue
		if str(row.get("ref", "")).begins_with(ref_prefix):
			total += int(row["amount"])
	return total


func latest_note(day: int) -> String:
	for index in range(entries.size() - 1, -1, -1):
		if int(entries[index]["day"]) == day:
			return str(entries[index]["note"])
	return "暂无流水"
