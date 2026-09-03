extends SceneTree
## 界面预览截图：无需打开编辑器，直接出图到 res://.preview/
## 用法：godot --path godot --script res://tools/screenshot.gd

const OUT_DIR := "res://.preview/"
# 逻辑画布 640x360 直接看太小，额外导出邻近采样放大版便于查看
const ZOOM := 2

var _main: Node


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	await create_timer(0.6).timeout
	var stage_controller := _main.get_node("Body/Stage/SubViewport/InitialCafe")
	assert(stage_controller.pc_data.size() == 40, "初期店面必须恰好包含 40 台机位")
	assert(stage_controller.decor_slots.size() == 12, "初期店面必须预埋 12 个装修槽位")

	await _shoot("01-柜台默认态")

	await _click_stage(Vector2(122, 42))
	assert(_main.selected_kind == "pc" and _main.selected_index == 3, "SubViewport 机位点击未接回右栏")
	await _shoot("02-选中机位")

	await _click_stage(Vector2(136, 304))
	assert(_main.selected_kind == "customer" and _main.selected_index == 0, "顾客点击未接回右栏")
	await _shoot("03-选中顾客")

	stage_controller.call("set_decor_preview", true)
	await _shoot("04-装修槽位")
	stage_controller.call("set_decor_preview", false)

	stage_controller.call("select_facility", "locked")
	await _shoot("05-选中锁定区")

	stage_controller.call("select_facility", "shelf")
	await _shoot("06-选中货架")

	_main.call("_show_counter")
	quit()


func _click_stage(position: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.position = position
	event.global_position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	_main.call("_on_stage_gui_input", event)
	await process_frame


func _shoot(label: String) -> void:
	# 连等两帧，确保上一步的 UI 变更已经绘制
	await process_frame
	await process_frame
	var img := root.get_texture().get_image()
	img.save_png(OUT_DIR + label + ".png")

	var zoomed := img.duplicate() as Image
	zoomed.resize(img.get_width() * ZOOM, img.get_height() * ZOOM, Image.INTERPOLATE_NEAREST)
	zoomed.save_png(OUT_DIR + label + "@%dx.png" % ZOOM)
	print("SHOT %s (%dx%d)" % [label, img.get_width(), img.get_height()])
