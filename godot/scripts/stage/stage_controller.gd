extends Node2D
class_name StageController

signal object_selected(kind: String, object_id: int, state: String, zone: String)
signal background_selected

const PC_SCENE := preload("res://scenes/stage/pc_station.tscn")
const FACILITY_SCENE := preload("res://scenes/stage/facility.tscn")
const CUSTOMER_SCENE := preload("res://scenes/stage/customer.tscn")

@onready var floor_layer: TileMapLayer = $FloorLayer
@onready var wall_layer: Node2D = $WallLayer
@onready var facility_layer: Node2D = $FacilityLayer
@onready var npc_layer: Node2D = $NpcLayer
@onready var decor_slot_layer: Node2D = $DecorSlotLayer
@onready var selection_layer: Node2D = $SelectionLayer

var pc_data: Array[Dictionary] = []
var customer_data: Array[Dictionary] = []
var decor_slots: Array[DecorSlot] = []
var decor_preview := false
var _selection: Sprite2D


func _ready() -> void:
	_build_floor()
	_build_walls()
	_build_furniture()
	_build_decor_slots()
	_build_selection()


func handle_pointer(point: Vector2) -> bool:
	var picked := _pick_interactable(point)
	if picked != null:
		_on_object_activated(
			picked.object_kind,
			picked.object_id,
			picked.object_state,
			picked.object_zone,
			picked
		)
		return true
	_selection.visible = false
	background_selected.emit()
	return false


func _pick_interactable(point: Vector2) -> StageInteractable:
	# SubViewportContainer 直接把本地坐标交给这里；Area2D 仍保留给未来独立地图窗口。
	for layer: Node in [npc_layer, facility_layer]:
		var children: Array[Node] = layer.get_children()
		children.reverse()
		for child in children:
			if child is StageInteractable:
				var half_size: Vector2 = child.hit_size * 0.5
				var hit_rect := Rect2(child.position - half_size, child.hit_size)
				if hit_rect.has_point(point):
					return child
	return null


func set_decor_preview(enabled: bool) -> void:
	decor_preview = enabled
	for slot in decor_slots:
		slot.set_preview(enabled)


func toggle_decor_preview() -> void:
	set_decor_preview(not decor_preview)


func install_demo_decor() -> void:
	for slot in decor_slots:
		if slot.slot_id == "hall_plant_a":
			slot.install("plant")
		elif slot.slot_id == "hall_trash":
			slot.install("trash_bin")
		elif slot.slot_id == "room_team_poster":
			slot.install("poster")
	set_decor_preview(decor_preview)


func select_pc(index: int) -> void:
	if index < 0 or index >= pc_data.size():
		return
	var data: Dictionary = pc_data[index]
	var node: Node2D = data["node"]
	_on_object_activated("pc", index, data["state"], data["zone"], node)


func select_customer(index: int) -> void:
	if index < 0 or index >= customer_data.size():
		return
	var data: Dictionary = customer_data[index]
	var node: Node2D = data["node"]
	_on_object_activated("customer", index, data["state"], "顾客", node)


func select_facility(kind: String) -> void:
	for child in facility_layer.get_children():
		if child is StageInteractable and child.object_kind == kind:
			_on_object_activated(
				child.object_kind, child.object_id, child.object_state, child.object_zone, child
			)
			return


func _build_floor() -> void:
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(32, 32)
	var source := TileSetAtlasSource.new()
	source.texture = load("res://assets/world/tiles/floor_atlas.png")
	source.texture_region_size = Vector2i(32, 32)
	for atlas_x in range(3):
		source.create_tile(Vector2i(atlas_x, 0))
	var source_id := tile_set.add_source(source)
	floor_layer.tile_set = tile_set
	for y in range(11):
		for x in range(15):
			var atlas_x := (x + y) % 2
			if x >= 13 and y >= 7:
				atlas_x = 2
			floor_layer.set_cell(Vector2i(x, y), source_id, Vector2i(atlas_x, 0))


func _build_walls() -> void:
	var wall := load("res://assets/world/tiles/wall.png")
	# 外墙
	for x in range(0, 480, 16):
		_add_wall_sprite(wall, Vector2(x + 8, 8))
	for y in range(0, 336, 16):
		_add_wall_sprite(wall, Vector2(8, y + 8))
	# 经营区与服务区、普通厅与高配区、高配区与包间
	for x in range(0, 480, 16):
		if x not in range(208, 272) and x not in range(400, 432):
			_add_wall_sprite(wall, Vector2(x + 8, 224))
	for y in range(0, 224, 16):
		_add_wall_sprite(wall, Vector2(272, y + 8))
		_add_wall_sprite(wall, Vector2(368, y + 8))
	# 包间横隔断，门口各留 32px
	for room_y in [80, 144]:
		for x in range(368, 480, 16):
			if x not in range(384, 416):
				_add_wall_sprite(wall, Vector2(x + 8, room_y))
	# 高配区围挡
	var fence := load("res://assets/world/tiles/fence.png")
	for x in range(288, 352, 16):
		_add_wall_sprite(fence, Vector2(x + 8, 40))
		_add_wall_sprite(fence, Vector2(x + 8, 200))


func _build_furniture() -> void:
	_add_label("普通大厅 · 32台", Vector2(18, 14), Color("#6b4126"))
	_add_label("待装修 · 高配", Vector2(280, 14), Color("#7a5a30"))
	_add_label("双人A", Vector2(374, 14), Color("#7a4a5c"))
	_add_label("双人B", Vector2(374, 86), Color("#7a4a5c"))
	_add_label("四人开黑", Vector2(374, 150), Color("#6d8a3a"))

	var states := [
		"使用中", "使用中", "空闲", "待清洁", "空闲", "使用中", "空闲", "空闲",
		"空闲", "使用中", "故障", "空闲", "空闲", "使用中", "待清洁", "空闲",
		"空闲", "空闲", "使用中", "空闲", "空闲", "使用中", "空闲", "待清洁",
		"空闲", "使用中", "空闲", "故障", "空闲", "使用中", "空闲", "空闲",
	]
	var row_y := [42, 90, 138, 186]
	for row in range(4):
		_add_desk_row(Vector2(16, row_y[row] - 14), 8)
		for col in range(8):
			_add_pc(row * 8 + col, Vector2(32 + col * 30, row_y[row]), states[row * 8 + col], "普通大厅")

	# 包间 33～40
	_add_desk_row(Vector2(376, 22), 3)
	_add_pc(32, Vector2(392, 46), "使用中", "双人包A")
	_add_pc(33, Vector2(432, 46), "空闲", "双人包A")
	_add_desk_row(Vector2(376, 94), 3)
	_add_pc(34, Vector2(392, 118), "空闲", "双人包B")
	_add_pc(35, Vector2(432, 118), "空闲", "双人包B")
	_add_desk_row(Vector2(376, 158), 3)
	for i in range(4):
		_add_pc(36 + i, Vector2(380 + i * 24, 184), ["使用中", "使用中", "空闲", "待清洁"][i], "四人开黑")

	_add_facility("locked", -1, "未装修", "电竞高配区", Vector2(320, 112),
		"res://assets/world/facilities/locked_sign.png", Vector2(80, 144))
	_add_facility("counter", -1, "营业中", "柜台", Vector2(80, 264),
		"res://assets/world/facilities/counter.png", Vector2(96, 40))
	_add_facility("shelf", -1, "库存偏低", "小卖部", Vector2(176, 264),
		"res://assets/world/facilities/shelf.png", Vector2(64, 40))
	_add_facility("facility", 0, "正常", "入口", Vector2(24, 304),
		"res://assets/world/facilities/entrance.png", Vector2(48, 48))
	_add_facility("facility", 1, "需清洁", "卫生间", Vector2(448, 280),
		"res://assets/world/facilities/toilet.png", Vector2(64, 80))
	_add_prop("res://assets/world/facilities/construction_crate.png", Vector2(304, 166), 2)
	_add_prop("res://assets/world/facilities/construction_crate.png", Vector2(340, 184), 2)
	_add_prop("res://assets/world/npc/boss_idle.png", Vector2(86, 232), 5)
	_add_prop("res://assets/world/npc/cat_stage.png", Vector2(112, 246), 6)

	_add_customer(0, Vector2(136, 304), "待结账", 1)
	_add_customer(1, Vector2(244, 286), "上机中", 4)
	_add_customer(2, Vector2(112, 218), "排队中", 7)
	_add_label("入口", Vector2(8, 326), Color("#315b60"))
	_add_label("32px 主走道", Vector2(248, 302), Color("#7a5a30"))


func _add_desk_row(pos: Vector2, count: int) -> void:
	for i in range(count):
		var sprite := Sprite2D.new()
		var kind := "mid"
		if i == 0:
			kind = "left"
		elif i == count - 1:
			kind = "right"
		sprite.texture = load("res://assets/world/stations/desk_%s.png" % kind)
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.position = pos + Vector2(i * 32 + 16, 8)
		sprite.z_index = 1
		facility_layer.add_child(sprite)


func _add_pc(index: int, pos: Vector2, state: String, zone: String) -> void:
	var pc: PcStation = PC_SCENE.instantiate()
	pc.setup(index, state, zone)
	pc.position = pos
	pc.z_index = 3
	pc.activated.connect(_on_object_activated.bind(pc))
	facility_layer.add_child(pc)
	pc_data.append({"state": state, "zone": zone, "node": pc})


func _add_facility(
	kind: String, id: int, state: String, zone: String, pos: Vector2,
	texture_path: String, hit_size: Vector2
) -> void:
	var facility: CafeFacility = FACILITY_SCENE.instantiate()
	facility.setup(kind, id, state, zone, texture_path, hit_size)
	facility.position = pos
	facility.z_index = 2
	facility.activated.connect(_on_object_activated.bind(facility))
	facility_layer.add_child(facility)


func _add_customer(index: int, pos: Vector2, state: String, appearance: int) -> void:
	var customer: CafeCustomer = CUSTOMER_SCENE.instantiate()
	customer.setup(index, state, appearance)
	customer.position = pos
	customer.z_index = 5
	customer.activated.connect(_on_object_activated.bind(customer))
	npc_layer.add_child(customer)
	customer_data.append({"state": state, "node": customer})


func _add_prop(texture_path: String, pos: Vector2, layer: int) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = load(texture_path)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.position = pos
	sprite.z_index = layer
	facility_layer.add_child(sprite)


func _build_decor_slots() -> void:
	var definitions := [
		["hall_plant_a", "floor", Vector2(256, 64), ["plant"], "plant"],
		["hall_plant_b", "floor", Vector2(256, 184), ["plant"], ""],
		["hall_trash", "floor", Vector2(224, 208), ["trash"], "trash_bin"],
		["entrance_sign", "wall", Vector2(56, 236), ["sign"], "light_sign"],
		["counter_decor", "utility", Vector2(112, 240), ["counter"], ""],
		["shop_promo", "wall", Vector2(176, 232), ["poster"], ""],
		["room_a_poster", "wall", Vector2(456, 28), ["poster"], ""],
		["room_b_poster", "wall", Vector2(456, 96), ["poster"], ""],
		["room_team_poster", "wall", Vector2(456, 160), ["poster"], "poster"],
		["toilet_clean", "utility", Vector2(416, 312), ["clean"], ""],
		["hall_skin", "zone_skin", Vector2(264, 208), ["floor"], ""],
		["highend_skin", "zone_skin", Vector2(352, 208), ["theme"], ""],
	]
	for definition in definitions:
		var slot := DecorSlot.new()
		slot.setup(definition[0], definition[1], definition[3], definition[4])
		slot.position = definition[2]
		slot.z_index = 4
		decor_slot_layer.add_child(slot)
		decor_slots.append(slot)


func _build_selection() -> void:
	_selection = Sprite2D.new()
	_selection.texture = load("res://assets/world/feedback/selection.png")
	_selection.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_selection.z_index = 20
	_selection.visible = false
	selection_layer.add_child(_selection)


func _on_object_activated(
	kind: String, id: int, state: String, zone: String, source: Node2D
) -> void:
	_selection.position = source.position
	_selection.visible = true
	object_selected.emit(kind, id, state, zone)


func _add_wall_sprite(texture: Texture2D, pos: Vector2) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.position = pos
	sprite.z_index = 6
	wall_layer.add_child(sprite)


func _add_label(text: String, pos: Vector2, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.position = pos
	label.add_theme_font_size_override("font_size", 7)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.z_index = 8
	facility_layer.add_child(label)
