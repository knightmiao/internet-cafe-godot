extends PanelContainer
## 24px 像素风状态栏。图标暂用文字占位，后续替换为 12x12 点阵素材。

signal notify_clicked
signal settings_clicked

const CAFE_NAME := "猫网电竞"
const TEXT := Color("#ffe9c9")
const HIGHLIGHT := Color("#ffcf7a")
const LABEL := Color("#dcc08a")
# 分隔线做成一深一亮两列，在木纹底上呈现刻线的凹槽感
const DIVIDER_DARK := Color("#4a2c16")
const DIVIDER_LIGHT := Color("#a8742e")

var stat_labels: Dictionary = {}
var _bell: Button
var _settings: Button


func _ready() -> void:
	custom_minimum_size = Vector2(640, 24)
	add_theme_stylebox_override("panel", _wood_box())

	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 5
	row.offset_right = -5
	row.offset_bottom = -5   # 底部让开金色收边，文字不压在装饰上
	row.add_theme_constant_override("separation", 5)
	add_child(row)

	row.add_child(_brand())

	for config in [
		["pc", "机位", "0/40"],
		["money", "资金", "500"],
		["customers", "顾客", "0"],
		["reputation", "声誉", "5"],
		["clean", "清洁", "100"],
		["decor", "装修", "50"],
	]:
		row.add_child(_divider())
		row.add_child(_make_stat(config[0], config[1], config[2]))

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	row.add_child(_divider())

	var time := _label("第1天·上午", 9, HIGHLIGHT)
	time.custom_minimum_size.x = 65
	time.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stat_labels["time"] = time
	row.add_child(time)

	_bell = _icon_button("icon_bell.png", "消息")
	_bell.pressed.connect(func(): notify_clicked.emit())
	row.add_child(_bell)
	_settings = _icon_button("icon_gear.png", "设置")
	_settings.pressed.connect(func(): settings_clicked.emit())
	row.add_child(_settings)


func _brand() -> TextureRect:
	var logo := TextureRect.new()
	logo.texture = load("res://assets/ui/topbar/logo.png")
	logo.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	logo.custom_minimum_size = Vector2(65, 16)
	logo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	logo.tooltip_text = CAFE_NAME
	return logo


func _make_stat(id: String, title: String, initial: String) -> HBoxContainer:
	var group := HBoxContainer.new()
	group.add_theme_constant_override("separation", 3)
	group.add_child(_pixel_icon("icon_%s.png" % id))
	# 标题用暗金、数值用亮奶油，靠明度差分出主次
	group.add_child(_label(title, 8, LABEL))
	var value := _label(initial, 9, TEXT)
	stat_labels[id] = value
	group.add_child(value)
	return group


func _divider() -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for color in [DIVIDER_DARK, DIVIDER_LIGHT]:
		var line := ColorRect.new()
		line.color = color
		line.custom_minimum_size = Vector2(1, 14)
		box.add_child(line)
	return box


func _pixel_icon(file: String) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = load("res://assets/ui/topbar/" + file)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	icon.custom_minimum_size = Vector2(12, 12)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return icon


func _icon_button(file: String, tooltip: String) -> Button:
	var button := Button.new()
	button.icon = load("res://assets/ui/topbar/" + file)
	button.tooltip_text = tooltip
	button.flat = true
	button.custom_minimum_size = Vector2(14, 14)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.add_theme_stylebox_override("hover", _box(Color("#7a4a2a"), HIGHLIGHT, 0, 1))
	return button


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


# 木纹底图两端是收口 cap，中段 24px 可平铺，用九宫格保住端头不被拉伸
func _wood_box() -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = load("res://assets/ui/topbar/topbar_bg.png")
	style.set_texture_margin(SIDE_LEFT, 24)
	style.set_texture_margin(SIDE_RIGHT, 24)
	style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	return style


func _box(fill: Color, border: Color, radius: int = 0, width: int = 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	return style


func set_settings_open(on: bool) -> void:
	if _settings:
		_settings.modulate = HIGHLIGHT if on else Color.WHITE
		_settings.tooltip_text = "关闭设置" if on else "设置"


func set_unread(on: bool) -> void:
	if _bell:
		var file := "icon_bell_badge.png" if on else "icon_bell.png"
		_bell.icon = load("res://assets/ui/topbar/" + file)


func set_stat(id: String, text: String) -> void:
	if stat_labels.has(id):
		stat_labels[id].text = text


func set_money(v: float) -> void:
	set_stat("money", "%d" % int(v))


func set_pc(online: int, total: int) -> void:
	set_stat("pc", "%d/%d" % [online, total])


func set_customers(n: int) -> void:
	set_stat("customers", "%d" % n)


func set_reputation(n: float) -> void:
	set_stat("reputation", "%.1f" % n)


func set_clean(v: int) -> void:
	set_stat("clean", "%d" % v)


func set_decor(v: int) -> void:
	set_stat("decor", "%d" % v)


func set_time(day: int, period: String) -> void:
	set_stat("time", "第%d天·%s" % [day, period])
