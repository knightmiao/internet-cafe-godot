extends Node2D
class_name DecorSlot

var slot_id := ""
var slot_type := "floor"
var allowed_tags: Array[String] = []
var decor_id := ""
var unlock_level := 1
var decor_value := 0
var clean_bonus := 0
var reputation_bonus := 0
var traffic_bonus := 0

var _indicator: Sprite2D
var _decor: Sprite2D


func setup(id: String, type: String, tags: Array, initial_decor := "") -> void:
	slot_id = id
	slot_type = type
	allowed_tags.clear()
	for tag in tags:
		allowed_tags.append(str(tag))
	decor_id = initial_decor

	_indicator = Sprite2D.new()
	_indicator.texture = load("res://assets/world/decor/slot.png")
	_indicator.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_indicator.modulate = Color(1, 1, 1, 0.85)
	_indicator.visible = false
	add_child(_indicator)

	_decor = Sprite2D.new()
	_decor.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_decor)
	_refresh_decor()


func set_preview(enabled: bool) -> void:
	_indicator.visible = enabled and decor_id.is_empty()


func install(id: String) -> void:
	decor_id = id
	_refresh_decor()


func _refresh_decor() -> void:
	if not is_instance_valid(_decor):
		return
	if decor_id.is_empty():
		_decor.texture = null
		return
	var path := "res://assets/world/decor/%s.png" % decor_id
	_decor.texture = load(path) if ResourceLoader.exists(path) else null
