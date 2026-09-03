extends PanelContainer
## 顶栏（TopBar）—— 程序化构建，数据驱动
## 素材：assets/topbar/ 下的 flux 生成资源 (icon 均为 256x256)

signal notify_clicked
signal settings_clicked

const DIR := "res://assets/topbar/"

# ---- 统一尺寸基准 (单位: px) ----
const BAR_H      := 56.0   # 顶栏整体高度
const LOGO_H     := 44.0   # 品牌 Logo
const ICON_H     := 20.0   # 指标图标
const BTN_H      := 24.0   # 铃铛/设置按钮
const LABEL_SIZE := 15     # 指标文字字号

# 指标配置: [id, 图标文件, 初始文本]
const STATS := [
	["pc",       "icon_pc.png",       "0/8 台"],
	["money",    "icon_money.png",    "¥500"],
	["customers","icon_customers.png","0 人"],
	["reputation","icon_reputation.png","5 星"],
	["clean",    "icon_clean.png",    "100"],
	["decor",    "icon_decor.png",    "50"],
	["time",     "icon_time.png",     "第1天·上午"],
]

@onready var stat_labels: Dictionary = {}

func _ready() -> void:
	custom_minimum_size = Vector2(0, BAR_H)
	var bg := StyleBoxTexture.new()
	bg.texture = load(DIR + "topbar_bg.png")
	bg.texture_margin_left = 24
	bg.texture_margin_right = 24
	bg.texture_margin_top = 6
	bg.texture_margin_bottom = 6
	add_theme_stylebox_override("panel", bg)

	# 黑色 30% 透明蒙层，叠加在木纹背景上提升文字对比度
	var veil := ColorRect.new()
	veil.color = Color(0, 0, 0, 0.28)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(veil)
	move_child(veil, 0)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 16)
	add_child(hbox)
	hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hbox.offset_left = 12
	hbox.offset_right = -12
	# 深色蒙层也需要盖住底部圆角，保证对比度
	veil.top_level = false

	# 品牌 Logo —— 按基准高度统一缩放
	var logo := _make_icon(load(DIR + "logo.png"), LOGO_H)
	hbox.add_child(logo)

	# 分隔
	hbox.add_child(_vs())

	# 指标组 —— 图标统一 ICON_H
	for s in STATS:
		hbox.add_child(_make_stat(s[0], s[1], s[2]))

	# 弹性占位
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer)

	# 消息铃 + 设置按钮 —— 按钮统一 BTN_H
	hbox.add_child(_make_bell())
	hbox.add_child(_make_gear())


# 统一图标容器：固定高度 + 等比居中，源图(256x256)缩放为 height 指定尺寸
func _make_icon(tex: Texture2D, height: float) -> TextureRect:
	var t := TextureRect.new()
	t.texture = tex
	t.custom_minimum_size = Vector2(height, height)  # 视为正方形基准
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return t


func _vs() -> VSeparator:
	var sep := VSeparator.new()
	sep.add_theme_stylebox_override("separator", _sep_style())
	return sep


func _sep_style() -> StyleBoxLine:
	var s := StyleBoxLine.new()
	s.color = Color(0.72, 0.53, 0.20)
	s.thickness = 1
	return s


func _make_stat(id: String, icon_file: String, init_text: String) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.alignment = BoxContainer.ALIGNMENT_CENTER

	box.add_child(_make_icon(load(DIR + icon_file), ICON_H))

	var lab := Label.new()
	lab.text = init_text
	lab.add_theme_font_size_override("font_size", LABEL_SIZE)
	lab.add_theme_color_override("font_color", Color(1.0, 0.91, 0.78))
	lab.add_theme_color_override("font_outline_color", Color(0.25, 0.14, 0.05))
	lab.add_theme_constant_override("outline_size", 4)
	lab.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(lab)

	stat_labels[id] = lab
	return box


var _bell: Button
var _has_unread := false

# 统一按钮图标尺寸：icon 全屏填充 + 垂直居中
func _make_bell() -> Button:
	_bell = Button.new()
	_bell.icon = load(DIR + "icon_bell.png")
	_bell.tooltip_text = "消息"
	_bell.flat = true
	_bell.custom_minimum_size = Vector2(BTN_H, BTN_H)
	_bell.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_bell.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bell.expand_icon = true
	_bell.pressed.connect(func(): notify_clicked.emit())
	return _bell


func _make_gear() -> Button:
	var g := Button.new()
	g.icon = load(DIR + "icon_gear.png")
	g.tooltip_text = "设置"
	g.flat = true
	g.custom_minimum_size = Vector2(BTN_H, BTN_H)
	g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	g.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	g.expand_icon = true
	g.pressed.connect(func(): settings_clicked.emit())
	return g


# 消息铃红点徽标：true 显示红点，false 恢复无红点
func set_unread(on: bool) -> void:
	if _has_unread == on:
		return
	_has_unread = on
	if _bell:
		_bell.icon = load(DIR + ("icon_bell_badge.png" if on else "icon_bell.png"))


# ---- 数据更新接口 ----
func set_stat(id: String, text: String) -> void:
	if stat_labels.has(id):
		stat_labels[id].text = text

func set_money(v: float) -> void:
	set_stat("money", "¥%d" % int(v))

func set_pc(online: int, total: int) -> void:
	set_stat("pc", "%d/%d 台" % [online, total])

func set_customers(n: int) -> void:
	set_stat("customers", "%d 人" % n)

func set_reputation(n: float) -> void:
	set_stat("reputation", "%d 星" % int(n))

func set_clean(v: int) -> void:
	set_stat("clean", "%d" % v)

func set_decor(v: int) -> void:
	set_stat("decor", "%d" % v)

func set_time(day: int, period: String) -> void:
	set_stat("time", "第%d天·%s" % [day, period])
