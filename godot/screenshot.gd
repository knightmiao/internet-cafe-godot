extends SceneTree

func _init() -> void:
    call_deferred("_go")

func _go() -> void:
    var scene: Node = load("res://main.tscn").instantiate()
    root.add_child(scene)
    await create_timer(1.0).timeout
    # 强制跑几帧让 UI 渲染
    await create_timer(0.5).timeout
    var img := root.get_texture().get_image()
    img.save_png("res://screenshot_topbar.png")
    print("SCREENSHOT_SAVED res://screenshot_topbar.png")
    quit()
