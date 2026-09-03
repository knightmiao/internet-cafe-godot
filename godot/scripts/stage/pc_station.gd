extends StageInteractable
class_name PcStation

const STATE_TEXTURES := {
	"已关机": "state_off.png",
	"空闲": "state_idle.png",
	"使用中": "state_busy.png",
	"待清洁": "state_dirty.png",
	"故障": "state_broken.png",
}


func setup(index: int, state: String, zone: String) -> void:
	configure("pc", index, state, zone, Vector2(28, 32))

	var sprite := Sprite2D.new()
	sprite.texture = load("res://assets/world/stations/pc_station.png")
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.position = Vector2(0, 2)
	add_child(sprite)

	var number := Label.new()
	number.text = "%02d" % (index + 1)
	number.position = Vector2(-10, 11)
	number.size = Vector2(20, 10)
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	number.add_theme_font_size_override("font_size", 7)
	number.add_theme_color_override("font_color", Color("#ffe9c9"))
	number.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(number)

	var dot := Sprite2D.new()
	dot.texture = load(
		"res://assets/world/feedback/" + STATE_TEXTURES.get(state, "state_idle.png")
	)
	dot.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	dot.position = Vector2(9, -10)
	add_child(dot)
