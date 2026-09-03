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
	hit_size = size
	input_pickable = true
	var shape := RectangleShape2D.new()
	shape.size = size
	var collision := CollisionShape2D.new()
	collision.shape = shape
	add_child(collision)


func _ready() -> void:
	input_event.connect(_on_input_event)


func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		activated.emit(object_kind, object_id, object_state, object_zone)
		get_viewport().set_input_as_handled()
