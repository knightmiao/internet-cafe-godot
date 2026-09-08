extends Node2D
class_name StageController

signal object_selected(kind: String, object_id: int, state: String, zone: String)
signal background_selected
signal zoom_changed(level: float)

const PC_SCENE := preload("res://scenes/stage/pc_station.tscn")
const FACILITY_SCENE := preload("res://scenes/stage/facility.tscn")
const CUSTOMER_SCENE := preload("res://scenes/stage/customer.tscn")

const ASSETS := "res://assets/world/"
const CUSTOMER_DATA_PATH := "res://data/customers.json"
const PC_CONFIG_DATA_PATH := "res://data/pc_configs.json"
const DECOR_DATA_PATH := "res://data/decor_catalog.json"
const INITIAL_PC_CONFIG := "gen_09"

# 世界与视口。世界宽高刚好是视口的两倍，所以 0.5 倍相机能一屏看满整店，
# 1.0 倍则是近景，需要拖拽。
const VIEWPORT_SIZE := Vector2(480, 336)
const WORLD_SIZE := Vector2(960, 672)
const TILE := 64
# 联排上一个座位的横向节拍，与联排素材的画面节奏一致
const SEAT_PITCH := 64
const ROW_SEATS := 4
# 陡俯视联排的桌深只有 68px，四排并列后每排之间还剩 44px 走道
const ROW_DEPTH := 68

# 分区边界。营业区在上，服务区在下
const HALL_LEFT := 32
const HIGHEND_LEFT := 544
const ROOM_LEFT := 672
# 服务区高度按卫生间素材的 192px 定死，营业区拿走剩下的全部纵向空间
const SERVICE_TOP := 480
# 四排联排的中心线，间距 112 = 68 桌深 + 44 走道
const ROW_CENTERS := [88, 200, 312, 424]

const ZOOM_LEVELS := [0.5, 1.0]
const DRAG_THRESHOLD := 4.0
# 对齐机位图里椅面中心：椅子在 64×68 整图偏左下，人坐进去而不是站在椅侧
const SEAT_OFFSET := Vector2(-6, 14)
const QUEUE_ORIGIN := Vector2(168, 644)
const QUEUE_PITCH := 36.0
const CHECKOUT_ORIGIN := Vector2(248, 618)
const CHECKOUT_PITCH := 28.0

@onready var floor_layer: TileMapLayer = $FloorLayer
@onready var wall_layer: Node2D = $WallLayer
# 设施、机位、NPC、装修共用一个 y_sort 图层，前后遮挡按纵坐标自动成立：
# 老板站在柜台后面就会被柜台挡住，顾客走到柜台前面就压在柜台上。
@onready var world_layer: Node2D = $WorldLayer
@onready var selection_layer: Node2D = $SelectionLayer
@onready var camera: Camera2D = $Camera2D

var pc_data: Array[Dictionary] = []
var pc_configs: Dictionary = {}
var customer_data: Array[Dictionary] = []
var customer_profiles: Array = []
var decor_slots: Array[DecorSlot] = []
var decor_catalog: Array = []
var decor_by_id: Dictionary = {}
var owned_decor: Dictionary = {"theme_old": true, "plant_large": true}
var zone_themes: Dictionary = {
	"hall": "theme_old", "rooms": "theme_old", "highend": "theme_old",
}
var business_bonuses: Dictionary = {
	"decor": 0, "clean": 0, "comfort": 0, "reputation": 0, "traffic": 0,
}
var decor_preview := false

var _selection: Sprite2D
var _labels: Array[Label] = []
var _stations: Array[PcStation] = []
var _facilities: Dictionary = {}
var _theme_floor_roots: Dictionary = {}
var _theme_wall_roots: Dictionary = {}
var _zoom_index := 0
var _pressing := false
var _dragged := false
var _press_point := Vector2.ZERO


func _ready() -> void:
	_load_customer_profiles()
	_load_pc_configs()
	_load_decor_catalog()
	_build_floor()
	_build_walls()
	_build_theme_layers()
	_build_hall()
	_build_rooms()
	_build_highend()
	_build_service()
	_build_decor_slots()
	_build_selection()
	_setup_camera()


# ── 输入 ──────────────────────────────────────────────

func handle_input(event: InputEvent) -> void:
	"""接收 SubViewportContainer 转发的输入：左键点选、按住拖拽、滚轮缩放。"""
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_pressing = true
				_dragged = false
				_press_point = event.position
			else:
				# 拖拽过就不算点选，免得平移完顺手改了右栏内容
				if _pressing and not _dragged:
					handle_pointer(event.position)
				_pressing = false
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			set_zoom_index(_zoom_index + 1)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			set_zoom_index(_zoom_index - 1)
	elif event is InputEventMouseMotion and _pressing:
		if event.position.distance_to(_press_point) > DRAG_THRESHOLD:
			_dragged = true
		if _dragged:
			_pan(-event.relative / camera.zoom.x)


func handle_pointer(point: Vector2) -> bool:
	"""point 是视口本地坐标，需要经相机变换回世界坐标再命中测试。"""
	var world := get_viewport().get_canvas_transform().affine_inverse() * point
	var picked := _pick_interactable(world)
	if picked != null:
		_on_object_activated(
			picked.object_kind, picked.object_id,
			picked.object_state, picked.object_zone, picked
		)
		return true
	_selection.visible = false
	background_selected.emit()
	return false


func _pick_interactable(world: Vector2) -> StageInteractable:
	# 从后往前找，保证叠在上层的物件优先响应
	var children: Array[Node] = world_layer.get_children()
	children.reverse()
	for child in children:
		if child is StageInteractable:
			if child is DecorSlot and not decor_preview:
				continue
			var half: Vector2 = child.hit_size * 0.5
			if Rect2(child.position - half, child.hit_size).has_point(world):
				return child
	return null


# ── 相机 ──────────────────────────────────────────────

func _setup_camera() -> void:
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(WORLD_SIZE.x)
	camera.limit_bottom = int(WORLD_SIZE.y)
	# 默认 0.5 倍：视野正好等于世界，锁在店面中心，一打开就能看满整店。
	camera.position = WORLD_SIZE * 0.5
	camera.make_current()
	_apply_zoom()


func set_zoom_index(index: int) -> void:
	var clamped := clampi(index, 0, ZOOM_LEVELS.size() - 1)
	if clamped == _zoom_index:
		return
	_zoom_index = clamped
	_apply_zoom()


func toggle_zoom() -> void:
	set_zoom_index(0 if _zoom_index == ZOOM_LEVELS.size() - 1 else ZOOM_LEVELS.size() - 1)


func zoom_level() -> float:
	return ZOOM_LEVELS[_zoom_index]


func _apply_zoom() -> void:
	var level: float = ZOOM_LEVELS[_zoom_index]
	camera.zoom = Vector2(level, level)
	# 拉远到 0.5 倍时小字号只剩几个像素，全部收掉
	var detailed := level >= 1.0
	for label in _labels:
		label.visible = detailed
	for station in _stations:
		station.set_number_visible(detailed)
	_pan(Vector2.ZERO)
	zoom_changed.emit(level)


func _pan(delta: Vector2) -> void:
	var half := VIEWPORT_SIZE * 0.5 / camera.zoom.x
	var target := camera.position + delta
	# 世界比视口小的方向直接锁死居中，避免出现黑边
	if half.x * 2.0 >= WORLD_SIZE.x:
		target.x = WORLD_SIZE.x * 0.5
	else:
		target.x = clampf(target.x, half.x, WORLD_SIZE.x - half.x)
	if half.y * 2.0 >= WORLD_SIZE.y:
		target.y = WORLD_SIZE.y * 0.5
	else:
		target.y = clampf(target.y, half.y, WORLD_SIZE.y - half.y)
	camera.position = target


func focus_on(world_position: Vector2) -> void:
	_pan(world_position - camera.position)


# ── 地面与墙体 ────────────────────────────────────────

func _build_floor() -> void:
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(TILE, TILE)
	var source := TileSetAtlasSource.new()
	source.texture = load(ASSETS + "tiles/floor_atlas.png")
	source.texture_region_size = Vector2i(TILE, TILE)
	for atlas_x in range(4):
		source.create_tile(Vector2i(atlas_x, 0))
	var source_id := tile_set.add_source(source)
	floor_layer.tile_set = tile_set

	# 多铺一行一列当安全边，避免拖到边缘露出背景。
	# 卫生间不铺湿区瓷砖：那间是带地面的 cutaway 素材，自己就画了地砖，
	# 再铺一层反而会溢出房间轮廓，在屋外拖出一块绿。
	for y in range(WORLD_SIZE.y / TILE + 1):
		for x in range(WORLD_SIZE.x / TILE + 1):
			var atlas_x := (x + y) % 2
			if x >= 9 and x <= 10 and y <= 7:
				atlas_x = 3  # 高配待装修区：裸水泥
			floor_layer.set_cell(Vector2i(x, y), source_id, Vector2i(atlas_x, 0))


func _build_walls() -> void:
	var horizontal := load(ASSETS + "tiles/wall.png")
	var vertical := load(ASSETS + "tiles/wall_v.png")

	# 只画后墙与两侧，前墙不画：视角是从店门往里看
	for x in range(0, int(WORLD_SIZE.x), 32):
		_add_wall(horizontal, Vector2(x + 16, 16))
	for y in range(0, int(WORLD_SIZE.y), 32):
		_add_wall(vertical, Vector2(16, y + 16))
		_add_wall(vertical, Vector2(WORLD_SIZE.x - 16, y + 16))

	# 营业区与服务区之间的隔墙，留两处走道门洞
	for x in range(0, int(WORLD_SIZE.x), 32):
		var in_doorway := (x >= 416 and x < 544) or (x >= 800 and x < 864)
		if not in_doorway:
			_add_wall(horizontal, Vector2(x + 16, SERVICE_TOP))

	# 高配区两侧围墙
	for y in range(32, SERVICE_TOP, 32):
		_add_wall(vertical, Vector2(HIGHEND_LEFT, y + 16))
		_add_wall(vertical, Vector2(ROOM_LEFT, y + 16))

	# 包间横隔断，靠走道一侧留门
	for room_y in [176, 336]:
		for x in range(ROOM_LEFT, int(WORLD_SIZE.x), 32):
			if x >= ROOM_LEFT + 32 and x < ROOM_LEFT + 96:
				continue
			_add_wall(horizontal, Vector2(x + 16, room_y))


func _add_wall(texture: Texture2D, position_at: Vector2) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.position = position_at
	wall_layer.add_child(sprite)


func _build_theme_layers() -> void:
	floor_layer.z_index = -10
	for zone_id in ["hall", "rooms", "highend"]:
		var floor_root := Node2D.new()
		floor_root.name = "%sThemeFloor" % zone_id.capitalize()
		floor_root.z_index = -5
		add_child(floor_root)
		_theme_floor_roots[zone_id] = floor_root
		var wall_root := Node2D.new()
		wall_root.name = "%sThemeWalls" % zone_id.capitalize()
		wall_root.z_index = 2
		wall_layer.add_child(wall_root)
		_theme_wall_roots[zone_id] = wall_root
		_apply_zone_theme_visuals(zone_id, str(zone_themes[zone_id]))


func _zone_rect(zone_id: String) -> Rect2:
	match zone_id:
		"hall":
			return Rect2(32, 32, 512, SERVICE_TOP - 32)
		"rooms":
			return Rect2(ROOM_LEFT, 32, WORLD_SIZE.x - ROOM_LEFT, SERVICE_TOP - 32)
		"highend":
			return Rect2(HIGHEND_LEFT, 32, ROOM_LEFT - HIGHEND_LEFT, SERVICE_TOP - 32)
	return Rect2()


func _apply_zone_theme_visuals(zone_id: String, theme_id: String) -> void:
	if not _theme_floor_roots.has(zone_id) or not decor_by_id.has(theme_id):
		return
	var item: Dictionary = decor_by_id[theme_id]
	var floor_root: Node2D = _theme_floor_roots[zone_id]
	var wall_root: Node2D = _theme_wall_roots[zone_id]
	for child in floor_root.get_children():
		child.free()
	for child in wall_root.get_children():
		child.free()
	var floor_texture: Texture2D = load(str(item["theme_floor"]))
	var horizontal: Texture2D = load(str(item["theme_wall"]))
	var vertical: Texture2D = load(str(item["theme_wall_v"]))
	var rect := _zone_rect(zone_id)
	for y in range(int(rect.position.y), int(rect.end.y), TILE):
		for x in range(int(rect.position.x), int(rect.end.x), TILE):
			_add_theme_sprite(
				floor_root, floor_texture, Vector2(x + TILE * 0.5, y + TILE * 0.5)
			)
	_add_zone_theme_walls(zone_id, wall_root, horizontal, vertical)


func _add_zone_theme_walls(zone_id: String, root: Node2D,
		horizontal: Texture2D, vertical: Texture2D) -> void:
	var left := HALL_LEFT
	var right := HIGHEND_LEFT
	if zone_id == "highend":
		left = HIGHEND_LEFT
		right = ROOM_LEFT
	elif zone_id == "rooms":
		left = ROOM_LEFT
		right = int(WORLD_SIZE.x)
	for x in range(left, right, 32):
		_add_theme_sprite(root, horizontal, Vector2(x + 16, 16))
		var doorway := (x >= 416 and x < 544) or (x >= 800 and x < 864)
		if not doorway:
			_add_theme_sprite(root, horizontal, Vector2(x + 16, SERVICE_TOP))
	if zone_id == "hall":
		for y in range(32, SERVICE_TOP, 32):
			_add_theme_sprite(root, vertical, Vector2(16, y + 16))
	elif zone_id == "highend":
		for y in range(32, SERVICE_TOP, 32):
			_add_theme_sprite(root, vertical, Vector2(HIGHEND_LEFT, y + 16))
			_add_theme_sprite(root, vertical, Vector2(ROOM_LEFT, y + 16))
	else:
		for y in range(32, SERVICE_TOP, 32):
			_add_theme_sprite(root, vertical, Vector2(WORLD_SIZE.x - 16, y + 16))
		for room_y in [176, 336]:
			for x in range(ROOM_LEFT, int(WORLD_SIZE.x), 32):
				if x < ROOM_LEFT + 32 or x >= ROOM_LEFT + 96:
					_add_theme_sprite(root, horizontal, Vector2(x + 16, room_y))


func _add_theme_sprite(root: Node2D, texture: Texture2D, position_at: Vector2) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.position = position_at
	root.add_child(sprite)


# ── 机位 ──────────────────────────────────────────────

func _seat_offset(index: int, seats: int) -> float:
	"""一组机位内第 index 个座位相对组中心的横向偏移。"""
	return SEAT_PITCH * (index + 0.5 - seats * 0.5)


func _build_hall() -> void:
	_add_label("普通大厅 · 32台", Vector2(40, 38), Color("#f5d790"))
	for row in range(ROW_CENTERS.size()):
		var row_y: float = ROW_CENTERS[row]
		# 一排 8 台 = 两组 4 座；每台使用独立完整套装，便于以后逐台升级。
		for group in range(2):
			var group_center := Vector2(
				HALL_LEFT + SEAT_PITCH * ROW_SEATS * (group + 0.5), row_y
			)
			for seat in range(ROW_SEATS):
				var index := row * 8 + group * ROW_SEATS + seat
				_add_pc(
					index,
					Vector2(group_center.x + _seat_offset(seat, ROW_SEATS), row_y),
					"空闲",
					"普通大厅"
				)


func _build_rooms() -> void:
	_add_label("双人A", Vector2(ROOM_LEFT + 16, 38), Color("#e8b4c8"))
	_add_room_row(Vector2(816, 104), 2, 32, ["空闲", "空闲"], "双人包A")

	_add_label("双人B", Vector2(ROOM_LEFT + 16, 198), Color("#e8b4c8"))
	_add_room_row(Vector2(816, 264), 2, 34, ["空闲", "空闲"], "双人包B")

	_add_label("四人开黑", Vector2(ROOM_LEFT + 16, 358), Color("#b6d97a"))
	_add_room_row(
		Vector2(816, 424), ROW_SEATS, 36,
		["空闲", "空闲", "空闲", "空闲"], "四人开黑"
	)


func _add_room_row(center: Vector2, seats: int, first_index: int,
		states: Array, zone: String) -> void:
	for seat in range(seats):
		_add_pc(
			first_index + seat,
			Vector2(center.x + _seat_offset(seat, seats), center.y),
			states[seat],
			zone
		)


func _build_highend() -> void:
	_add_label("待装修 · 高配", Vector2(HIGHEND_LEFT + 12, 38), Color("#d8c9a8"))
	# 围挡封住上下两端，比铺一块大色块更能说明"这里还没开"
	for x in [576, 640]:
		_add_prop(ASSETS + "facilities/hazard_fence.png", Vector2(x, 72))
		_add_prop(ASSETS + "facilities/hazard_fence.png", Vector2(x, 448))
	_add_facility(
		"locked", -1, "未装修", "电竞高配区", Vector2(608, 170),
		ASSETS + "facilities/locked_sign.png", Vector2(64, 72)
	)
	# 多堆几箱料，免得这条竖井显得空旷
	_add_prop(ASSETS + "facilities/construction_crate.png", Vector2(584, 262))
	_add_prop(ASSETS + "facilities/construction_crate.png", Vector2(636, 330))
	_add_prop(ASSETS + "facilities/construction_crate.png", Vector2(592, 384))


func _build_service() -> void:
	_add_label("入口", Vector2(44, 502), Color("#9fd8d0"))
	_add_facility(
		"facility", 0, "正常", "入口", Vector2(96, 606),
		ASSETS + "facilities/entrance.png", Vector2(96, 124)
	)
	_add_facility(
		"counter", -1, "营业中", "柜台", Vector2(280, 560),
		ASSETS + "facilities/counter.png", Vector2(192, 100)
	)
	_add_facility(
		"shelf", -1, "库存偏低", "小卖部", Vector2(480, 570),
		ASSETS + "facilities/shelf.png", Vector2(128, 128)
	)
	_add_facility(
		"facility", 1, "需清洁", "卫生间", Vector2(896, 576),
		ASSETS + "facilities/toilet.png", Vector2(128, 192)
	)

	# 老板站柜台内侧，y 比柜台小，y_sort 会让柜台挡住他的下半身
	_add_prop(ASSETS + "npc/boss_idle.png", Vector2(240, 506))
	_add_prop(ASSETS + "npc/cat_stage.png", Vector2(348, 520))


# ── 物件工厂 ──────────────────────────────────────────

func _add_pc(index: int, position_at: Vector2, state: String, zone: String,
		config_id := INITIAL_PC_CONFIG) -> void:
	var config: Dictionary = pc_configs.get(config_id, {})
	assert(not config.is_empty(), "未知机位配置：%s" % config_id)
	var pc: PcStation = PC_SCENE.instantiate()
	pc.setup(index, state, zone, config_id)
	pc.position = position_at
	pc.activated.connect(_on_object_activated.bind(pc))
	world_layer.add_child(pc)
	pc_data.append({
		"state": state,
		"zone": zone,
		"node": pc,
		"config_id": config_id,
		"config": config,
		"locked": false,
		"session": {},
	})
	_stations.append(pc)


func _add_facility(kind: String, id: int, state: String, zone: String,
		position_at: Vector2, texture_path: String, hit_size: Vector2) -> void:
	var facility: CafeFacility = FACILITY_SCENE.instantiate()
	facility.setup(kind, id, state, zone, texture_path, hit_size)
	facility.position = position_at
	facility.activated.connect(_on_object_activated.bind(facility))
	world_layer.add_child(facility)
	if kind in ["counter", "shelf"] or zone == "卫生间":
		_facilities[kind if kind != "facility" else "restroom"] = facility


func _add_customer(index: int, position_at: Vector2, state: String, appearance: int) -> void:
	var profile_index := clampi(appearance - 1, 0, customer_profiles.size() - 1)
	var profile: Dictionary = customer_profiles[profile_index]
	var customer: CafeCustomer = CUSTOMER_SCENE.instantiate()
	customer.setup(index, state, appearance, str(profile["name"]))
	customer.position = position_at
	customer.activated.connect(_on_object_activated.bind(customer))
	world_layer.add_child(customer)
	customer_data.append({"state": state, "node": customer, "profile": profile})


func _load_customer_profiles() -> void:
	var file := FileAccess.open(CUSTOMER_DATA_PATH, FileAccess.READ)
	assert(file != null, "无法读取顾客角色库：%s" % CUSTOMER_DATA_PATH)
	var parsed = JSON.parse_string(file.get_as_text())
	assert(parsed is Array and parsed.size() == 50, "顾客角色库必须恰好包含 50 人")
	customer_profiles = parsed


func _load_pc_configs() -> void:
	var file := FileAccess.open(PC_CONFIG_DATA_PATH, FileAccess.READ)
	assert(file != null, "无法读取机位配置库：%s" % PC_CONFIG_DATA_PATH)
	var parsed = JSON.parse_string(file.get_as_text())
	assert(parsed is Array and parsed.size() == 6, "机位配置库必须恰好包含 6 个世代")
	for config in parsed:
		pc_configs[str(config["id"])] = config


func _load_decor_catalog() -> void:
	var file := FileAccess.open(DECOR_DATA_PATH, FileAccess.READ)
	assert(file != null, "无法读取装修目录：%s" % DECOR_DATA_PATH)
	var parsed = JSON.parse_string(file.get_as_text())
	assert(parsed is Array and parsed.size() == 24, "装修目录必须恰好包含 24 项")
	decor_catalog = parsed
	for item in decor_catalog:
		decor_by_id[str(item["id"])] = item


func _add_prop(texture_path: String, position_at: Vector2) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = load(texture_path)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.position = position_at
	world_layer.add_child(sprite)


func _add_label(text: String, position_at: Vector2, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.position = position_at
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color("#141a16"))
	label.add_theme_constant_override("outline_size", 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.z_index = 8
	wall_layer.add_child(label)
	_labels.append(label)


# ── 装修槽与选中框 ────────────────────────────────────

func _build_decor_slots() -> void:
	# 实体槽与三个区域主题槽分离。主题槽只负责整区换肤，不会额外生成物件。
	var definitions := [
		["hall_floor_a", "floor", "hall", Vector2(392, 520),
			["plant", "seat", "floor"], "plant_large", false],
		["hall_floor_b", "floor", "hall", Vector2(616, 536),
			["plant", "seat", "floor"], "", false],
		["hall_utility", "utility", "hall", Vector2(600, 632),
			["water", "vending", "charge", "utility", "ac"], "", false],
		["entrance_wall", "wall", "hall", Vector2(120, 504),
			["sign", "poster", "flag", "wall", "light"], "", false],
		["hall_wall", "wall", "hall", Vector2(480, 496),
			["poster", "sign", "sound", "wall", "air"], "", false],
		["room_wall", "wall", "rooms", Vector2(928, 364),
			["poster", "flag", "sound", "wall"], "", false],
		["counter_service", "service", "service", Vector2(280, 560),
			["counter"], "", false],
		["shelf_service", "service", "service", Vector2(480, 570),
			["shelf"], "", false],
		["restroom_service", "service", "service", Vector2(896, 576),
			["restroom"], "", false],
		["hall_skin", "zone_skin", "hall", Vector2(520, 444),
			["theme"], "theme_old", false],
		["rooms_skin", "zone_skin", "rooms", Vector2(720, 444),
			["theme"], "theme_old", false],
		["highend_skin", "zone_skin", "highend", Vector2(608, 420),
			["theme"], "theme_old", true],
	]
	for definition in definitions:
		var slot := DecorSlot.new()
		slot.setup(
			definition[0], definition[1], definition[2], definition[4],
			definition[5], definition[6]
		)
		slot.position = definition[3]
		world_layer.add_child(slot)
		slot.set_slot_index(decor_slots.size())
		slot.activated.connect(_on_object_activated.bind(slot))
		decor_slots.append(slot)
	_recalculate_business_bonuses()


func set_decor_preview(enabled: bool) -> void:
	decor_preview = enabled
	for slot in decor_slots:
		slot.set_preview(enabled)


func toggle_decor_preview() -> void:
	set_decor_preview(not decor_preview)


func install_demo_decor() -> void:
	mark_decor_owned("poster_set")
	install_decor("hall_wall", "poster_set")
	set_decor_preview(decor_preview)


func get_decor_slot(index: int) -> DecorSlot:
	if index < 0 or index >= decor_slots.size():
		return null
	return decor_slots[index]


func get_decor_item(item_id: String) -> Dictionary:
	return decor_by_id.get(item_id, {})


func get_compatible_decor(slot_index: int) -> Array:
	var slot := get_decor_slot(slot_index)
	if slot == null:
		return []
	var matches: Array = []
	for item in decor_catalog:
		if slot.is_compatible(item["tags"]):
			matches.append(item)
	return matches


func is_decor_owned(item_id: String) -> bool:
	return bool(owned_decor.get(item_id, false))


func mark_decor_owned(item_id: String) -> void:
	assert(decor_by_id.has(item_id), "未知装修：%s" % item_id)
	owned_decor[item_id] = true


func decor_install_block_reason(slot_index: int, item_id: String,
		player_level: int) -> String:
	var slot := get_decor_slot(slot_index)
	if slot == null or not decor_by_id.has(item_id):
		return "无效装修"
	var item: Dictionary = decor_by_id[item_id]
	if not slot.is_compatible(item["tags"]):
		return "槽位不兼容"
	if slot.zone_locked:
		return "区域未解锁"
	if int(item["unlock_level"]) > player_level:
		return "等级不足"
	return ""


func install_decor(slot_id: String, item_id: String) -> bool:
	var slot: DecorSlot
	for candidate in decor_slots:
		if candidate.slot_id == slot_id:
			slot = candidate
			break
	if slot == null or not decor_by_id.has(item_id) or not is_decor_owned(item_id):
		return false
	var item: Dictionary = decor_by_id[item_id]
	if not slot.is_compatible(item["tags"]) or slot.zone_locked:
		return false
	if slot.slot_type == "zone_skin":
		slot.install(item_id)
		zone_themes[slot.zone_id] = item_id
		_apply_zone_theme_visuals(slot.zone_id, item_id)
	else:
		slot.install(item_id, str(item["scene_asset"]))
		_update_replaced_facility(slot, item_id)
	_recalculate_business_bonuses()
	return true


func _update_replaced_facility(slot: DecorSlot, item_id: String) -> void:
	var facility_key := ""
	if slot.slot_id == "counter_service":
		facility_key = "counter"
	elif slot.slot_id == "shelf_service":
		facility_key = "shelf"
	elif slot.slot_id == "restroom_service":
		facility_key = "restroom"
	if not facility_key.is_empty() and _facilities.has(facility_key):
		(_facilities[facility_key] as CanvasItem).visible = item_id.is_empty()


func _recalculate_business_bonuses() -> void:
	for key in business_bonuses:
		business_bonuses[key] = 0
	for slot in decor_slots:
		if slot.decor_id.is_empty() or not decor_by_id.has(slot.decor_id):
			continue
		var bonuses: Dictionary = decor_by_id[slot.decor_id]["bonuses"]
		for key in business_bonuses:
			business_bonuses[key] += int(bonuses.get(key, 0))


func _build_selection() -> void:
	_selection = Sprite2D.new()
	_selection.texture = load(ASSETS + "feedback/selection.png")
	_selection.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_selection.visible = false
	selection_layer.add_child(_selection)


func _on_object_activated(kind: String, id: int, state: String, zone: String,
		source: Node2D) -> void:
	_selection.position = source.position
	_selection.visible = true
	object_selected.emit(kind, id, state, zone)


# ── 供主界面与截图脚本调用 ────────────────────────────

func select_pc(index: int) -> void:
	if index < 0 or index >= pc_data.size():
		return
	var data: Dictionary = pc_data[index]
	_on_object_activated("pc", index, data["state"], data["zone"], data["node"])


func get_pc_config(index: int) -> Dictionary:
	if index < 0 or index >= pc_data.size():
		return {}
	return pc_data[index].get("config", {})


func select_customer(index: int) -> void:
	if index < 0 or index >= customer_data.size():
		return
	var data: Dictionary = customer_data[index]
	_on_object_activated("customer", index, data["state"], "顾客", data["node"])


func get_customer_profile(index: int) -> Dictionary:
	if index < 0 or index >= customer_data.size():
		return {}
	return customer_data[index].get("profile", {})


func find_customer_by_states(states: Array) -> int:
	for index in range(customer_data.size()):
		if str(customer_data[index]["state"]) in states:
			return index
	return -1


func begin_closing_customers() -> void:
	# 兼容旧入口；真正的收尾由 GameState.stop_admission 处理会话和排队。
	for data in customer_data:
		if str(data["state"]) == "使用中":
			continue
		if str(data["state"]) != "离店":
			_set_customer_record_state(data, "待结账")


func complete_customer(index: int) -> bool:
	if index < 0 or index >= customer_data.size():
		return false
	dismiss_customer(index)
	return true


func active_customer_count() -> int:
	return customer_data.filter(func(data): return str(data["state"]) != "离店").size()


func reset_simulation() -> void:
	clear_all_customers()
	for index in range(pc_data.size()):
		clear_session(index)
		set_pc_state(index, "空闲")


func prepare_open() -> void:
	for index in range(pc_data.size()):
		var state := str(pc_data[index]["state"])
		if state == "已关机" or state == "使用中":
			clear_session(index)
			set_pc_state(index, "空闲")


func set_pc_state(index: int, state: String) -> void:
	if index < 0 or index >= pc_data.size():
		return
	pc_data[index]["state"] = state
	var node: PcStation = pc_data[index]["node"]
	node.set_operating_state(state)


func get_pc_state(index: int) -> String:
	if index < 0 or index >= pc_data.size():
		return ""
	return str(pc_data[index]["state"])


func count_pc_state(state: String) -> int:
	var total := 0
	for pc in pc_data:
		if str(pc["state"]) == state:
			total += 1
	return total


func idle_pc_indices() -> Array[int]:
	var result: Array[int] = []
	for index in range(pc_data.size()):
		if str(pc_data[index]["state"]) == "空闲" and not bool(pc_data[index].get("locked", false)):
			result.append(index)
	return result


func clear_session(index: int) -> void:
	if index < 0 or index >= pc_data.size():
		return
	pc_data[index]["session"] = {}


func take_session(index: int) -> Dictionary:
	if index < 0 or index >= pc_data.size():
		return {}
	var session: Dictionary = pc_data[index].get("session", {})
	pc_data[index]["session"] = {}
	return session.duplicate()


func start_session(pc_index: int, customer_index: int, start_minute: int,
		duration: int, rate: float) -> void:
	var profile: Dictionary = get_customer_profile(customer_index)
	pc_data[pc_index]["session"] = {
		"customer_index": customer_index,
		"customer_profile_id": str(profile.get("id", "")),
		"start_minute": start_minute,
		"planned_duration": duration,
		"hourly_rate": rate,
	}
	set_pc_state(pc_index, "使用中")
	seat_customer(customer_index, pc_index)


func due_sessions(minute: int) -> Array[int]:
	var due: Array[int] = []
	for index in range(pc_data.size()):
		var session: Dictionary = pc_data[index].get("session", {})
		if session.is_empty():
			continue
		if minute >= int(session["start_minute"]) + int(session["planned_duration"]):
			due.append(index)
	return due


func active_session_count() -> int:
	var total := 0
	for pc in pc_data:
		if not pc.get("session", {}).is_empty():
			total += 1
	return total


func pick_pc_for_customer(customer_index: int) -> int:
	var idle := idle_pc_indices()
	if idle.is_empty() or customer_index < 0 or customer_index >= customer_data.size():
		return -1
	var focus := str(
		customer_data[customer_index]["profile"].get("internet_habit", {}).get("spending_focus", "")
	)
	var preferred := _preferred_zones(focus)
	var customer_pos: Vector2 = customer_data[customer_index]["node"].position
	var best := -1
	var best_score := 999999.0
	for pc_index in idle:
		var zone := str(pc_data[pc_index]["zone"])
		var rank := preferred.find(zone)
		if rank < 0:
			rank = preferred.size()
		var dist: float = customer_pos.distance_to(pc_data[pc_index]["node"].position)
		var score := float(rank) * 10000.0 + dist
		if score < best_score:
			best_score = score
			best = pc_index
	return best


func spawn_customer(profile: Dictionary, minute: int, state := "排队中") -> int:
	var appearance := _appearance_of(profile)
	var index := customer_data.size()
	_add_customer(index, _queue_position(waiting_count()), state, appearance)
	var data: Dictionary = customer_data[index]
	data["profile"] = profile
	data["queued_at"] = minute
	data["bill"] = 0
	data["pc_index"] = -1
	_refresh_queue_positions()
	return index


func seat_customer(customer_index: int, pc_index: int) -> void:
	if customer_index < 0 or customer_index >= customer_data.size():
		return
	var data: Dictionary = customer_data[customer_index]
	var node: CafeCustomer = data["node"]
	node.position = pc_data[pc_index]["node"].position + SEAT_OFFSET
	data["pc_index"] = pc_index
	set_customer_state(customer_index, "使用中")
	_refresh_queue_positions()


func send_to_checkout(customer_index: int, bill: int) -> void:
	if customer_index < 0 or customer_index >= customer_data.size():
		return
	var data: Dictionary = customer_data[customer_index]
	data["bill"] = bill
	data["pc_index"] = -1
	set_customer_state(customer_index, "待结账")
	_refresh_checkout_positions()


func dismiss_customer(index: int) -> void:
	if index < 0 or index >= customer_data.size():
		return
	var data: Dictionary = customer_data[index]
	if str(data["state"]) == "离店":
		return
	set_customer_state(index, "离店")
	var node: CafeCustomer = data["node"]
	node.visible = false
	data["pc_index"] = -1
	_refresh_queue_positions()
	_refresh_checkout_positions()


func set_customer_state(index: int, state: String) -> void:
	if index < 0 or index >= customer_data.size():
		return
	_set_customer_record_state(customer_data[index], state)


func customer_bill(index: int) -> int:
	if index < 0 or index >= customer_data.size():
		return 0
	return int(customer_data[index].get("bill", 0))


func waiting_indices() -> Array[int]:
	return _indices_for_states(["排队中", "待接待"])


func checkout_indices() -> Array[int]:
	return _indices_for_states(["待结账"])


func waiting_count() -> int:
	return waiting_indices().size()


func clear_all_customers() -> void:
	for data in customer_data:
		var node: Node = data["node"]
		if is_instance_valid(node):
			node.free()
	customer_data.clear()


func export_world_state() -> Dictionary:
	return {
		"owned_decor": owned_decor.duplicate(),
		"zone_themes": zone_themes.duplicate(),
		"decor_installs": export_decor_installs(),
		"pcs": export_pcs(),
		"customers": export_customers(),
	}


func export_decor_installs() -> Dictionary:
	var installs := {}
	for slot in decor_slots:
		installs[slot.slot_id] = slot.decor_id
	return installs


func export_pcs() -> Array:
	var rows: Array = []
	for pc in pc_data:
		rows.append({
			"state": pc["state"],
			"config_id": pc["config_id"],
			"locked": pc.get("locked", false),
			"session": pc.get("session", {}),
		})
	return rows


func export_customers() -> Array:
	var rows: Array = []
	for data in customer_data:
		if str(data["state"]) == "离店":
			continue
		var node: Node2D = data["node"]
		rows.append({
			"profile_id": data["profile"]["id"],
			"state": data["state"],
			"queued_at": data.get("queued_at", 0),
			"bill": data.get("bill", 0),
			"pc_index": data.get("pc_index", -1),
			"x": node.position.x,
			"y": node.position.y,
		})
	return rows


func import_world_state(data: Dictionary) -> void:
	import_decor_state(
		data.get("owned_decor", owned_decor),
		data.get("zone_themes", zone_themes),
		data.get("decor_installs", {})
	)
	import_pcs(data.get("pcs", []))
	import_customers(data.get("customers", []))


func import_decor_state(owned: Dictionary, themes: Dictionary, installs: Dictionary) -> void:
	owned_decor = owned.duplicate()
	zone_themes = themes.duplicate()
	for slot in decor_slots:
		var item_id := str(installs.get(slot.slot_id, slot.decor_id))
		if slot.slot_type == "zone_skin":
			var theme_id := str(zone_themes.get(slot.zone_id, "theme_old"))
			slot.install(theme_id)
			_apply_zone_theme_visuals(slot.zone_id, theme_id)
		elif item_id.is_empty():
			slot.clear_installation()
			_update_replaced_facility(slot, "")
		elif decor_by_id.has(item_id):
			slot.install(item_id, str(decor_by_id[item_id]["scene_asset"]))
			_update_replaced_facility(slot, item_id)
	_recalculate_business_bonuses()


func import_pcs(rows: Array) -> void:
	for index in range(mini(rows.size(), pc_data.size())):
		var row: Dictionary = rows[index]
		clear_session(index)
		set_pc_state(index, str(row.get("state", "空闲")))
		pc_data[index]["locked"] = bool(row.get("locked", false))
		var session: Dictionary = row.get("session", {})
		pc_data[index]["session"] = session.duplicate() if session is Dictionary else {}


func import_customers(rows: Array) -> void:
	clear_all_customers()
	var profiles_by_id := {}
	for profile in customer_profiles:
		profiles_by_id[str(profile["id"])] = profile
	for row in rows:
		if not row is Dictionary:
			continue
		var profile_id := str(row.get("profile_id", ""))
		if not profiles_by_id.has(profile_id):
			continue
		var index := spawn_customer(
			profiles_by_id[profile_id], int(row.get("queued_at", 0)), str(row.get("state", "排队中"))
		)
		var data: Dictionary = customer_data[index]
		data["bill"] = int(row.get("bill", 0))
		data["pc_index"] = int(row.get("pc_index", -1))
		if data["pc_index"] >= 0 and data["pc_index"] < pc_data.size():
			data["node"].position = pc_data[data["pc_index"]]["node"].position + SEAT_OFFSET
		else:
			data["node"].position = Vector2(
				float(row.get("x", QUEUE_ORIGIN.x)), float(row.get("y", QUEUE_ORIGIN.y))
			)
		set_customer_state(index, str(row.get("state", "排队中")))
	_relink_sessions()
	_refresh_queue_positions()
	_refresh_checkout_positions()


func _preferred_zones(focus: String) -> Array:
	if focus.contains("安静") or focus.contains("包"):
		return ["双人包A", "双人包B", "四人开黑", "普通大厅"]
	if focus.contains("连坐"):
		return ["普通大厅", "四人开黑", "双人包A", "双人包B"]
	if focus.contains("高配"):
		return ["普通大厅", "四人开黑", "双人包A", "双人包B"]
	return ["普通大厅", "双人包A", "双人包B", "四人开黑"]


func _appearance_of(profile: Dictionary) -> int:
	var id := str(profile.get("id", "customer_01"))
	return clampi(int(id.get_slice("_", 1)), 1, 50)


func _queue_position(order: int) -> Vector2:
	return QUEUE_ORIGIN + Vector2(QUEUE_PITCH * order, 0)


func _checkout_position(order: int) -> Vector2:
	return CHECKOUT_ORIGIN + Vector2(CHECKOUT_PITCH * order, 0)


func _refresh_queue_positions() -> void:
	var order := 0
	for data in customer_data:
		if str(data["state"]) in ["排队中", "待接待"]:
			data["node"].position = _queue_position(order)
			order += 1


func _refresh_checkout_positions() -> void:
	var order := 0
	for data in customer_data:
		if str(data["state"]) == "待结账":
			data["node"].position = _checkout_position(order)
			order += 1


func _indices_for_states(states: Array) -> Array[int]:
	var result: Array[int] = []
	for index in range(customer_data.size()):
		if str(customer_data[index]["state"]) in states:
			result.append(index)
	return result


func _set_customer_record_state(data: Dictionary, state: String) -> void:
	data["state"] = state
	var node: CafeCustomer = data["node"]
	node.set_seated(state == "使用中")
	node.set_need_state(state)
	node.visible = state != "离店"


func _relink_sessions() -> void:
	var by_profile := {}
	for index in range(customer_data.size()):
		by_profile[str(customer_data[index]["profile"]["id"])] = index
	for pc in pc_data:
		var session: Dictionary = pc.get("session", {})
		if session.is_empty():
			continue
		var profile_id := str(session.get("customer_profile_id", ""))
		if by_profile.has(profile_id):
			session["customer_index"] = by_profile[profile_id]
		else:
			pc["session"] = {}


func select_facility(kind: String) -> void:
	for child in world_layer.get_children():
		if child is StageInteractable and child.object_kind == kind:
			_on_object_activated(
				child.object_kind, child.object_id,
				child.object_state, child.object_zone, child
			)
			return
