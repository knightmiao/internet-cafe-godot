extends StageInteractable
class_name CafeFacility


func setup(
	kind: String,
	id: int,
	state: String,
	zone: String,
	texture_path: String,
	hit_size: Vector2
) -> void:
	configure(kind, id, state, zone, hit_size)
	var sprite := Sprite2D.new()
	sprite.texture = load(texture_path)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(sprite)
