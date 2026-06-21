extends Node
## Central sound manager — loads all sounds from res://resources/sounds_data.tres.
## Edit that .tres file (or use the spreadsheet) to change any sound in the game.
## If a sound has no stream assigned, calling play_by_id() simply does nothing (silent).

const SOUND_DATA_PATH := "res://resources/sounds_data.tres"

var _sound_data = null
var _by_id: Dictionary = {}  # id -> AudioStream

# Audio players
var _sfx_player: AudioStreamPlayer = null
var _ui_player: AudioStreamPlayer = null

func _ready() -> void:
	_sfx_player = AudioStreamPlayer.new()
	_sfx_player.bus = "Master"
	_sfx_player.name = "SoundManager_SFX"
	add_child(_sfx_player)

	_ui_player = AudioStreamPlayer.new()
	_ui_player.bus = "Master"
	_ui_player.name = "SoundManager_UI"
	add_child(_ui_player)

	# Load sound data from the .tres resource
	_load_sound_data()


func _load_sound_data() -> void:
	if not ResourceLoader.exists(SOUND_DATA_PATH):
		push_warning("SoundManager: %s not found — all sounds will be silent." % SOUND_DATA_PATH)
		return
	var res = load(SOUND_DATA_PATH)
	if res == null or not (res is Resource):
		push_warning("SoundManager: Failed to load %s — all sounds will be silent." % SOUND_DATA_PATH)
		return
	_sound_data = res
	if res.entries.is_empty():
		push_warning("SoundManager: %s has no entries — all sounds will be silent." % SOUND_DATA_PATH)
		return
	var loaded := 0
	var skipped := 0
	for entry in res.entries:
		if entry == null or entry.id.is_empty():
			continue
		if entry.stream != null:
			_by_id[entry.id] = entry.stream
			loaded += 1
		else:
			skipped += 1
	print("SoundManager: Loaded %d sounds, %d blank slots from %s" % [loaded, skipped, SOUND_DATA_PATH])


## Look up an AudioStream by its id from sounds_data.tres.
## Returns null if not found or if the entry has no stream assigned.
func get_stream(id: String) -> AudioStream:
	return _by_id.get(id) if _by_id.has(id) else null


## Play a sound effect by id. Does nothing if the sound has no stream.
func play_by_id(id: String) -> void:
	var stream = get_stream(id)
	if stream == null:
		return
	play_sfx(stream)


## Play a raw AudioStream.
func play_sfx(stream: AudioStream) -> void:
	if stream == null or _sfx_player == null:
		return
	_sfx_player.stop()
	_sfx_player.stream = stream
	_sfx_player.pitch_scale = randf_range(0.95, 1.05)
	_sfx_player.play()


## Play a UI sound (e.g. menu click).
func play_ui_sfx(id: String) -> void:
	var stream = get_stream(id)
	if stream == null or _ui_player == null:
		return
	_ui_player.stream = stream
	_ui_player.pitch_scale = randf_range(0.95, 1.05)
	_ui_player.play()
