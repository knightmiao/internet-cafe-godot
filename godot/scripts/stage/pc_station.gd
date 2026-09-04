extends StageInteractable
class_name PcStation

const STATE_TEXTURES := {
	"已关机": "state_off.png",
	"空闲": "state_idle.png",
	"使用中": "state_busy.png",
	"待清洁": "state_dirty.png",
	"故障": "state_broken.png",
}

# 一个座位的点击热区：横向按联排节拍，纵向覆盖桌面到椅子
const HIT_SIZE := Vector2(60, 64)
# 状态点放在桌子正上方的排间走道里。一排 8 个点连成一线，扫一眼就知道哪台
# 故障、哪台待清洁，比压在设备上更好认，也不会被相邻排遮住。
const DOT_OFFSET := Vector2(0, -40)
# 编号压在显示器的亮蓝屏幕上，用深色字，屏幕正好是这一格里唯一的空白面
const NUMBER_OFFSET := Vector2(-14, -28)

var _number: Label


func setup(index: int, state: String, zone: String, texture_path := "") -> void:
	configure("pc", index, state, zone, HIT_SIZE)

	# 大厅与四人房的桌面由 station_row_4 联排底图统一提供，单座不再重复画桌子，
	# 这样并排时桌面是连续的；只有包间的独立机位才自带桌子。
	if not texture_path.is_empty():
		var sprite := Sprite2D.new()
		sprite.texture = load(texture_path)
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(sprite)

	_number = Label.new()
	_number.text = "%02d" % (index + 1)
	_number.position = NUMBER_OFFSET
	_number.size = Vector2(28, 11)
	_number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_number.add_theme_font_size_override("font_size", 8)
	_number.add_theme_color_override("font_color", Color("#0d2b33"))
	_number.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_number)

	var dot := Sprite2D.new()
	dot.texture = load(
		"res://assets/world/feedback/" + STATE_TEXTURES.get(state, "state_idle.png")
	)
	dot.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	dot.position = DOT_OFFSET
	add_child(dot)


func set_number_visible(visible_now: bool) -> void:
	# 相机拉远到 0.5 倍时 10px 字号只剩 5px，读不出来，直接收掉
	if is_instance_valid(_number):
		_number.visible = visible_now
