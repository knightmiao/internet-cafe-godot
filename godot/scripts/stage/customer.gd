extends StageInteractable
class_name CafeCustomer


func setup(index: int, state: String, appearance: int) -> void:
	configure("customer", index, state, "顾客", Vector2(18, 26))
	var sprite := Sprite2D.new()
	sprite.texture = load(
		"res://assets/world/npc/customer_%02d_idle.png" % clampi(appearance, 1, 8)
	)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(sprite)

	if state in ["排队中", "待接待", "待结账", "要点单", "有需求"]:
		var bubble_name := "wait"
		if state == "待结账":
			bubble_name = "checkout"
		elif state == "要点单":
			bubble_name = "order"
		var bubble := Sprite2D.new()
		bubble.texture = load("res://assets/world/feedback/bubble_%s.png" % bubble_name)
		bubble.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		bubble.position = Vector2(8, -20)
		add_child(bubble)
