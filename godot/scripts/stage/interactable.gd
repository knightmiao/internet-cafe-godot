extends Area2D
class_name StageInteractable

signal activated(kind: String, object_id: int, state: String, zone: String)

var object_kind := ""
var object_id := -1
var object_state := ""
var object_zone := ""
var hit_size := Vector2.ZERO


func configure(kind: String, id: int, state: String, zone: String, size: Vector2) -> void:
	object_kind = kind
	object_id = id
	object_state = state
	object_zone = zone
	input_pickable = true
	var collision := CollisionShape2D.new()
	add_child(collision)
	set_hit_size(size)


func set_hit_size(size: Vector2) -> void:
	hit_size = size
	for child in get_children():
		if child is CollisionShape2D:
			var shape := RectangleShape2D.new()
			shape.size = size
			child.shape = shape
			return


func _ready() -> void:
	input_event.connect(_on_input_event)


func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		activated.emit(object_kind, object_id, object_state, object_zone)
		get_viewport().set_input_as_handled()
