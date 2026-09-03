extends Control

@onready var topbar: PanelContainer = $TopLayer/TopBar
@onready var pc_grid: GridContainer = $PCGrid
@onready var open_btn: Button = $OpenButton

var money: float = 500.0
var is_open: bool = false
var pc_nodes: Array = []
var rng := RandomNumberGenerator.new()
var day: int = 1
var elapsed: float = 0.0

func _ready() -> void:
    rng.randomize()
    open_btn.pressed.connect(_on_open_pressed)
    _build_pcs(8)
    _update_topbar()

func _build_pcs(n: int) -> void:
    for i in range(n):
        var panel := PanelContainer.new()
        panel.custom_minimum_size = Vector2(180, 100)
        var label := Label.new()
        label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        label.add_theme_font_size_override("font_size", 22)
        panel.add_child(label)
        pc_grid.add_child(panel)
        pc_nodes.append({"label": label, "busy": false})
        _refresh_pc(i)

func _refresh_pc(i: int) -> void:
    var state := "空闲"
    if pc_nodes[i]["busy"]:
        state = "使用中"
        pc_nodes[i]["label"].modulate = Color(0.35, 1.0, 0.5)
    else:
        pc_nodes[i]["label"].modulate = Color(0.65, 0.65, 0.65)
    pc_nodes[i]["label"].text = "%d号机  %s" % [i + 1, state]

func _on_open_pressed() -> void:
    is_open = not is_open
    open_btn.text = "打烊" if is_open else "开店营业"

func _process(delta: float) -> void:
    if is_open:
        for i in range(pc_nodes.size()):
            if rng.randf() < delta * 0.4:
                pc_nodes[i]["busy"] = not pc_nodes[i]["busy"]
                _refresh_pc(i)
        var busy_count := 0
        for p in pc_nodes:
            if p["busy"]:
                busy_count += 1
        money += (busy_count * 3.0 - 1.5) * delta

    # 模拟时间流逝：约 60 秒 = 一天的一个时段
    elapsed += delta
    if elapsed >= 60.0:
        elapsed = 0.0
        day += 1
    _update_topbar()


func _period() -> String:
    if elapsed < 20.0:
        return "上午"
    if elapsed < 40.0:
        return "下午"
    return "晚上"


func _update_topbar() -> void:
    var online := 0
    for p in pc_nodes:
        if p["busy"]:
            online += 1
    topbar.set_money(money)
    topbar.set_pc(online, pc_nodes.size())
    topbar.set_customers(online)
    topbar.set_reputation(5.0)
    topbar.set_clean(100)
    topbar.set_decor(50)
    topbar.set_time(day, _period())
