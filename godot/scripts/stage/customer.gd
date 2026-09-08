extends StageInteractable
class_name CafeCustomer

# 角色素材 32x72，热区略收一圈，避免站位相邻时互相抢点击
const HIT_SIZE := Vector2(28, 68)
# 坐姿更矮，热区收到椅背一带，免得把头上方的显示器点击抢走
const SIT_HIT_SIZE := Vector2(28, 36)
# 气泡挂在头顶偏右，不遮住脸
const BUBBLE_OFFSET := Vector2(18, -52)
const SIT_BUBBLE_OFFSET := Vector2(16, -28)
# 节点对准椅面；贴图略上移，后脑勺靠近显示器、下摆压在椅座上
const SIT_SPRITE_OFFSET := Vector2(0, -6)

const BUBBLES := {
	"排队中": "wait",
	"待接待": "wait",
	"有需求": "wait",
	"待结账": "checkout",
	"要点单": "order",
}

var _bubble: Sprite2D
var _body: Sprite2D
var _appearance := 1
var _seated := false


func setup(index: int, state: String, appearance: int, display_name := "顾客") -> void:
	configure("customer", index, state, display_name, HIT_SIZE)
	_appearance = clampi(appearance, 1, 50)

	_body = Sprite2D.new()
	_body.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_body)
	set_seated(state == "使用中")
	set_need_state(state)


func is_seated() -> bool:
	return _seated


func set_seated(seated: bool) -> void:
	_seated = seated
	var pose := "sit" if seated else "idle"
	_body.texture = load(
		"res://assets/world/npc/customer_%02d_%s.png" % [_appearance, pose]
	)
	_body.offset = SIT_SPRITE_OFFSET if seated else Vector2.ZERO
	set_hit_size(SIT_HIT_SIZE if seated else HIT_SIZE)
	if is_instance_valid(_bubble):
		_bubble.position = SIT_BUBBLE_OFFSET if seated else BUBBLE_OFFSET


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
	_bubble.position = SIT_BUBBLE_OFFSET if _seated else BUBBLE_OFFSET
	add_child(_bubble)
