extends Node
## 按 cue id 播放短音效。音乐总线预留，本节点不碰。

const CATALOG_PATH := "res://data/sfx_catalog.json"
const POOL_SIZE := 8

var enabled := true
var catalog: Dictionary = {}
var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _last_play_ms: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_load_catalog()
	for _i in range(POOL_SIZE):
		var player := AudioStreamPlayer.new()
		player.bus = "SFX"
		add_child(player)
		_players.append(player)


func play(cue_id: String) -> void:
	if not enabled:
		return
	var gs := get_node_or_null("/root/GameState")
	if gs != null and bool(gs.get("test_mode")):
		return
	if not catalog.has(cue_id):
		return
	var cue: Dictionary = catalog[cue_id]
	var now_ms := Time.get_ticks_msec()
	var cooldown := float(cue.get("cooldown", 0.04))
	if _last_play_ms.has(cue_id) and float(now_ms - int(_last_play_ms[cue_id])) < cooldown * 1000.0:
		return
	var stream: AudioStream = _streams.get(cue_id, null)
	if stream == null:
		return
	var player := _acquire()
	if player == null:
		return
	player.stream = stream
	player.volume_db = linear_to_db(maxf(0.0001, float(cue.get("volume", 1.0))))
	player.pitch_scale = 1.0
	if bool(cue.get("pitch_jitter", false)):
		player.pitch_scale = _rng.randf_range(0.94, 1.06)
	player.play()
	_last_play_ms[cue_id] = now_ms


func _acquire() -> AudioStreamPlayer:
	for player in _players:
		if not player.playing:
			return player
	if _players.is_empty():
		return null
	return _players[0]


func _load_catalog() -> void:
	var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return
	catalog = parsed
	for cue_id in catalog:
		var cue: Dictionary = catalog[cue_id]
		var path := str(cue.get("path", ""))
		if path.is_empty() or not ResourceLoader.exists(path):
			continue
		var stream = load(path)
		if stream is AudioStream:
			_streams[cue_id] = stream
