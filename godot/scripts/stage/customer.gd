extends StageInteractable
class_name CafeCustomer

# 角色素材 32x72，热区略收一圈，避免站位相邻时互相抢点击
const HIT_SIZE := Vector2(28, 68)
# 气泡挂在头顶偏右，不遮住脸
const BUBBLE_OFFSET := Vector2(18, -52)

const BUBBLES := {
	"排队中": "wait",
	"待接待": "wait",
	"有需求": "wait",
	"待结账": "checkout",
	"要点单": "order",
}


func setup(index: int, state: String, appearance: int) -> void:
	configure("customer", index, state, "顾客", HIT_SIZE)

	var sprite := Sprite2D.new()
	sprite.texture = load(
		"res://assets/world/npc/customer_%02d_idle.png" % clampi(appearance, 1, 8)
	)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(sprite)

	if BUBBLES.has(state):
		var bubble := Sprite2D.new()
		bubble.texture = load(
			"res://assets/world/feedback/bubble_%s.png" % BUBBLES[state]
		)
		bubble.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		bubble.position = BUBBLE_OFFSET
		add_child(bubble)
