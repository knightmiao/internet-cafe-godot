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
# 1× 下约 3 秒从门口走到大厅机位；暂停时停步，2× 时跑得更快
const WALK_SPEED := 180.0
const WALK_FRAME_TIME := 0.14
const WALK_SPLIT_Y := 40
const WALK_SHIFT := 2
const WALK_BOB := 1.0
const ARRIVE_EPS := 2.0

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
var _idle_texture: Texture2D
var _walk_frames: Array[Texture2D] = []
var _waypoints: Array[Vector2] = []
var _arrived: Callable = Callable()
var _walk_phase := 0.0
var _walk_frame := 0


func setup(index: int, state: String, appearance: int, display_name := "顾客") -> void:
	configure("customer", index, state, display_name, HIT_SIZE)
	_appearance = clampi(appearance, 1, 50)
	_idle_texture = load(
		"res://assets/world/npc/customer_%02d_idle.png" % _appearance
	)
	_walk_frames = _build_walk_frames(_idle_texture)

	_body = Sprite2D.new()
	_body.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_body)
	set_seated(state == "使用中")
	set_need_state(state)
	set_process(false)


func is_seated() -> bool:
	return _seated


func is_walking() -> bool:
	return not _waypoints.is_empty()


func place_at(target: Vector2) -> void:
	_clear_walk()
	position = target


func walk_to(target: Vector2, arrived: Callable = Callable()) -> void:
	_arrived = arrived
	if position.distance_to(target) <= ARRIVE_EPS or _should_snap():
		place_at(target)
		_finish_walk()
		return
	set_seated(false)
	_waypoints.clear()
	if absf(target.x - position.x) > 8.0:
		_waypoints.append(Vector2(target.x, position.y))
	_waypoints.append(target)
	_walk_phase = 0.0
	_apply_walk_frame(0)
	set_process(true)


func set_seated(seated: bool) -> void:
	_seated = seated
	if seated:
		_clear_walk()
	var pose := "sit" if seated else "idle"
	_body.texture = load(
		"res://assets/world/npc/customer_%02d_%s.png" % [_appearance, pose]
	)
	_body.flip_h = false
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


func _process(delta: float) -> void:
	var rate := _clock_rate()
	if _waypoints.is_empty() or rate <= 0.0:
		return
	var dest: Vector2 = _waypoints[0]
	var to: Vector2 = dest - position
	var step := WALK_SPEED * rate * delta
	if to.length() <= step:
		position = dest
		_waypoints.pop_front()
		if _waypoints.is_empty():
			_finish_walk()
		return
	position += to.normalized() * step
	if absf(to.x) > 0.5:
		_body.flip_h = to.x < 0.0
	_walk_phase += delta * rate
	var frame := int(_walk_phase / WALK_FRAME_TIME) % 2
	if frame != _walk_frame:
		_apply_walk_frame(frame)


func _apply_walk_frame(frame: int) -> void:
	_walk_frame = frame
	if _walk_frames.size() >= 2:
		_body.texture = _walk_frames[frame]
	_body.offset = Vector2(0, -WALK_BOB if frame == 1 else 0.0)


func _finish_walk() -> void:
	_clear_walk()
	var callback := _arrived
	_arrived = Callable()
	if callback.is_valid():
		callback.call()


func _clear_walk() -> void:
	_waypoints.clear()
	_walk_phase = 0.0
	_walk_frame = 0
	if is_instance_valid(_body) and not _seated:
		_body.texture = _idle_texture
		_body.offset = Vector2.ZERO
	set_process(false)


func _should_snap() -> bool:
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		return true
	if gs.stage != null and bool(gs.stage.debug_force_walk):
		return false
	return bool(gs.test_mode)


func _clock_rate() -> float:
	var gs := get_node_or_null("/root/GameState")
	if gs == null or gs.clock == null:
		return 1.0
	var rate := float(gs.clock.speed)
	if rate <= 0.0 and gs.stage != null and bool(gs.stage.debug_force_walk):
		return 1.0
	return rate


func _build_walk_frames(source: Texture2D) -> Array[Texture2D]:
	if source == null:
		return []
	var image := source.get_image()
	if image == null:
		return []
	image.convert(Image.FORMAT_RGBA8)
	var frames: Array[Texture2D] = []
	for shift in [-WALK_SHIFT, WALK_SHIFT]:
		var frame := _shift_legs(image, shift)
		var texture := ImageTexture.create_from_image(frame)
		texture.set_meta("walk_frame", true)
		frames.append(texture)
	return frames


func _shift_legs(source: Image, shift: int) -> Image:
	var width := source.get_width()
	var height := source.get_height()
	var out := Image.create(width, height, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	for y in range(height):
		var dx := shift if y >= WALK_SPLIT_Y else 0
		for x in range(width):
			var sx := x - dx
			if sx < 0 or sx >= width:
				continue
			out.set_pixel(x, y, source.get_pixel(sx, y))
	return out
