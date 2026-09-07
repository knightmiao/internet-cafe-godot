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

var _bubble: Sprite2D


func setup(index: int, state: String, appearance: int, display_name := "顾客") -> void:
	configure("customer", index, state, display_name, HIT_SIZE)

	var sprite := Sprite2D.new()
	sprite.texture = load(
		"res://assets/world/npc/customer_%02d_idle.png" % clampi(appearance, 1, 50)
	)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(sprite)
	set_need_state(state)


func set_need_state(state: String) -> void:
	object_state = state
	if is_instance_valid(_bubble):
		_bubble.free()
		_bubble = null
	if not BUBBLES.has(state):
		return
	_bubble = Sprite2D.new()
	_bubble.texture = load(
		"res://assets/world/feedback/bubble_%s.png" % BUBBLES[state]
	)
	_bubble.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_bubble.position = BUBBLE_OFFSET
	add_child(_bubble)
