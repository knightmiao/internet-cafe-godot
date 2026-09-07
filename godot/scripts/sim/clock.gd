class_name SimClock
extends RefCounted
## 压缩实时时钟：1× 下 1 秒 = 1 游戏分钟，一天 480 分钟。

var minute := 0
var speed := 1.0
var accumulator := 0.0
var day_length := 480
var seconds_per_minute := 1.0
var open_hour := 10
var morning_end := 160
var afternoon_end := 320


func configure(tuning: Dictionary) -> void:
	day_length = int(tuning.get("day_length_minutes", 480))
	seconds_per_minute = float(tuning.get("seconds_per_game_minute", 1.0))
	open_hour = int(tuning.get("open_hour", 10))
	morning_end = int(tuning.get("period_morning_end", 160))
	afternoon_end = int(tuning.get("period_afternoon_end", 320))


func set_speed(value: float) -> void:
	speed = value


func reset_day() -> void:
	minute = 0
	accumulator = 0.0


func advance_one_minute() -> void:
	minute += 1


func advance(delta: float) -> int:
	if speed <= 0.0:
		return 0
	accumulator += delta * speed
	var steps := 0
	while accumulator >= seconds_per_minute:
		accumulator -= seconds_per_minute
		if minute >= day_length:
			break
		minute += 1
		steps += 1
	return steps


func period() -> String:
	if minute < morning_end:
		return "上午"
	if minute < afternoon_end:
		return "下午"
	return "晚上"


func display_text() -> String:
	var total := open_hour * 60 + minute
	return "%02d:%02d  %s" % [int(total / 60.0), total % 60, period()]
