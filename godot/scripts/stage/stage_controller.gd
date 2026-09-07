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

@onready var floor_layer: TileMapLayer = $FloorLayer
@onready var wall_layer: Node2D = $WallLayer
# 设施、机位、NPC、装修共用一个 y_sort 图层，前后遮挡按纵坐标自动成立：
# 老板站在柜台后面就会被柜台挡住，顾客走到柜台前面就压在柜台上。
@onready var world_layer: Node2D = $WorldLayer
@onready var selection_layer: Node2D = $SelectionLayer
@onready var camera: Camera2D = $Camera2D

var pc_data: Array[Dictionary] = []
var customer_data: Array[Dictionary] = []
var customer_profiles: Array = []
var decor_slots: Array[DecorSlot] = []
var decor_preview := false

var _selection: Sprite2D
var _labels: Array[Label] = []
var _stations: Array[PcStation] = []
var _zoom_index := 1
var _pressing := false
var _dragged := false
var _press_point := Vector2.ZERO


func _ready() -> void:
	_load_customer_profiles()
	_build_floor()
	_build_walls()
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
	camera.position = Vector2(240, 168)
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


# ── 机位 ──────────────────────────────────────────────

const HALL_STATES := [
	"使用中", "使用中", "空闲", "待清洁", "空闲", "使用中", "空闲", "空闲",
	"空闲", "使用中", "故障", "空闲", "空闲", "使用中", "待清洁", "空闲",
	"空闲", "空闲", "使用中", "空闲", "空闲", "使用中", "空闲", "待清洁",
	"空闲", "使用中", "空闲", "故障", "空闲", "使用中", "空闲", "空闲",
]


func _add_station_row(center: Vector2, seats: int) -> void:
	"""铺一段联排底图，桌面在素材里本来就是连续的，不需要拼桌板。"""
	var sprite := Sprite2D.new()
	sprite.texture = load(ASSETS + "stations/station_row_%d.png" % seats)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.position = center
	world_layer.add_child(sprite)


func _seat_offset(index: int, seats: int) -> float:
	"""联排内第 index 个座位相对底图中心的横向偏移。"""
	return SEAT_PITCH * (index + 0.5 - seats * 0.5)


func _build_hall() -> void:
	_add_label("普通大厅 · 32台", Vector2(40, 38), Color("#f5d790"))
	for row in range(ROW_CENTERS.size()):
		var row_y: float = ROW_CENTERS[row]
		# 一排 8 台 = 两段 4 座联排，接缝落在两组之间，正好读成两组桌子
		for group in range(2):
			var group_center := Vector2(
				HALL_LEFT + SEAT_PITCH * ROW_SEATS * (group + 0.5), row_y
			)
			_add_station_row(group_center, ROW_SEATS)
			for seat in range(ROW_SEATS):
				var index := row * 8 + group * ROW_SEATS + seat
				_add_pc(
					index,
					Vector2(group_center.x + _seat_offset(seat, ROW_SEATS), row_y),
					HALL_STATES[index],
					"普通大厅"
				)


func _build_rooms() -> void:
	_add_label("双人A", Vector2(ROOM_LEFT + 16, 38), Color("#e8b4c8"))
	_add_room_row(Vector2(816, 104), 2, 32, ["使用中", "空闲"], "双人包A")

	_add_label("双人B", Vector2(ROOM_LEFT + 16, 198), Color("#e8b4c8"))
	_add_room_row(Vector2(816, 264), 2, 34, ["空闲", "空闲"], "双人包B")

	_add_label("四人开黑", Vector2(ROOM_LEFT + 16, 358), Color("#b6d97a"))
	_add_room_row(
		Vector2(816, 424), ROW_SEATS, 36,
		["使用中", "使用中", "空闲", "待清洁"], "四人开黑"
	)


func _add_room_row(center: Vector2, seats: int, first_index: int,
		states: Array, zone: String) -> void:
	_add_station_row(center, seats)
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

	# 同屏只放合理数量的顾客，但从完整角色库抽取青年、中年、老年三种样本。
	_add_customer(0, Vector2(200, 648), "待结账", 1)
	_add_customer(1, Vector2(452, 652), "要点单", 24)
	_add_customer(2, Vector2(640, 612), "排队中", 47)


# ── 物件工厂 ──────────────────────────────────────────

func _add_pc(index: int, position_at: Vector2, state: String, zone: String,
		texture_path := "") -> void:
	var pc: PcStation = PC_SCENE.instantiate()
	pc.setup(index, state, zone, texture_path)
	pc.position = position_at
	pc.activated.connect(_on_object_activated.bind(pc))
	world_layer.add_child(pc)
	pc_data.append({"state": state, "zone": zone, "node": pc})
	_stations.append(pc)


func _add_facility(kind: String, id: int, state: String, zone: String,
		position_at: Vector2, texture_path: String, hit_size: Vector2) -> void:
	var facility: CafeFacility = FACILITY_SCENE.instantiate()
	facility.setup(kind, id, state, zone, texture_path, hit_size)
	facility.position = position_at
	facility.activated.connect(_on_object_activated.bind(facility))
	world_layer.add_child(facility)


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
	# 营业区被 32 台占满，没有余地摆落地装饰，所以绿植垃圾桶都落在服务区走道上；
	# 大厅和高配区只保留 zone_skin 槽位，那类装修是整区换皮不占地面。
	var definitions := [
		["hall_plant_a", "floor", Vector2(392, 504), ["plant"], "plant"],
		["hall_plant_b", "floor", Vector2(616, 520), ["plant"], ""],
		["hall_trash", "floor", Vector2(352, 648), ["trash"], "trash_bin"],
		["entrance_sign", "wall", Vector2(120, 512), ["sign"], "light_sign"],
		["counter_decor", "utility", Vector2(180, 514), ["counter"], ""],
		["shop_promo", "wall", Vector2(480, 496), ["poster"], ""],
		["room_a_poster", "wall", Vector2(936, 60), ["poster"], ""],
		["room_b_poster", "wall", Vector2(936, 212), ["poster"], ""],
		["room_team_poster", "wall", Vector2(936, 364), ["poster"], "poster"],
		["toilet_clean", "utility", Vector2(824, 500), ["clean"], ""],
		["hall_skin", "zone_skin", Vector2(288, 456), ["floor"], ""],
		["highend_skin", "zone_skin", Vector2(608, 420), ["theme"], ""],
	]
	for definition in definitions:
		var slot := DecorSlot.new()
		slot.setup(definition[0], definition[1], definition[3], definition[4])
		slot.position = definition[2]
		world_layer.add_child(slot)
		decor_slots.append(slot)


func set_decor_preview(enabled: bool) -> void:
	decor_preview = enabled
	for slot in decor_slots:
		slot.set_preview(enabled)


func toggle_decor_preview() -> void:
	set_decor_preview(not decor_preview)


func install_demo_decor() -> void:
	for slot in decor_slots:
		if slot.slot_id == "hall_plant_b":
			slot.install("plant")
		elif slot.slot_id == "shop_promo":
			slot.install("poster")
	set_decor_preview(decor_preview)


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


func select_customer(index: int) -> void:
	if index < 0 or index >= customer_data.size():
		return
	var data: Dictionary = customer_data[index]
	_on_object_activated("customer", index, data["state"], "顾客", data["node"])


func get_customer_profile(index: int) -> Dictionary:
	if index < 0 or index >= customer_data.size():
		return {}
	return customer_data[index].get("profile", {})


func select_facility(kind: String) -> void:
	for child in world_layer.get_children():
		if child is StageInteractable and child.object_kind == kind:
			_on_object_activated(
				child.object_kind, child.object_id,
				child.object_state, child.object_zone, child
			)
			return
