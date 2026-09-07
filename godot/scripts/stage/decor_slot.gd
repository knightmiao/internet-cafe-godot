extends StageInteractable
class_name DecorSlot

var slot_id := ""
var slot_type := "floor"
var zone_id := "hall"
var allowed_tags: Array[String] = []
var decor_id := ""
var zone_locked := false

var _indicator: Sprite2D
var _decor: Sprite2D


func setup(id: String, type: String, zone: String, tags: Array,
		initial_decor := "", locked := false) -> void:
	slot_id = id
	slot_type = type
	zone_id = zone
	zone_locked = locked
	allowed_tags.clear()
	for tag in tags:
		allowed_tags.append(str(tag))
	decor_id = initial_decor
	configure(
		"decor_slot", -1, "已安装" if not decor_id.is_empty() else "空槽",
		zone_id, Vector2(56, 56)
	)
	input_pickable = false

	_indicator = Sprite2D.new()
	_indicator.texture = load("res://assets/world/decor/slot.png")
	_indicator.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_indicator.modulate = Color(1, 0.45, 0.35, 0.9) if locked else Color(1, 1, 1, 0.85)
	_indicator.visible = false
	_indicator.z_index = 10
	add_child(_indicator)

	_decor = Sprite2D.new()
	_decor.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_decor)
	_refresh_decor()


func set_preview(enabled: bool) -> void:
	_indicator.visible = enabled
	input_pickable = enabled


func install(id: String, texture_path := "") -> void:
	decor_id = id
	object_state = "已安装"
	if not texture_path.is_empty():
		_decor.texture = load(texture_path)
	else:
		_refresh_decor()


func is_compatible(tags: Array) -> bool:
	for tag in tags:
		if allowed_tags.has(str(tag)):
			return true
	return false


func set_slot_index(index: int) -> void:
	object_id = index


func installed_texture() -> Texture2D:
	return _decor.texture


func clear_installation() -> void:
	decor_id = ""
	object_state = "空槽"
	_refresh_decor()


func _refresh_decor() -> void:
	if not is_instance_valid(_decor):
		return
	if decor_id.is_empty():
		_decor.texture = null
		return
	var path := "res://assets/world/decor/%s.png" % decor_id
	_decor.texture = load(path) if ResourceLoader.exists(path) else null
