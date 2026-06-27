extends Node
## Central sound manager — loads all sounds from res://resources/sounds_data.tres.
## Edit that .tres file (or use the spreadsheet) to change any sound in the game.
## If a sound has no stream assigned, calling play_by_id() simply does nothing (silent).
## Uses a pool of audio players to allow multiple simultaneous sounds.

const SOUND_DATA_PATH := "res://resources/sounds_data.tres"
const MAX_SFX_PLAYERS := 16  # Max simultaneous sound effects

var _sound_data = null
var _by_id: Dictionary = {}  # id -> AudioStream

# Audio player pool
var _sfx_pool: Array[AudioStreamPlayer] = []
var _ui_player: AudioStreamPlayer = null
var _next_sfx_index: int = 0  # Round-robin index for pool

func _ready() -> void:
	# Ensure the required audio buses exist
	_ensure_audio_buses()
	
	# Create pool of SFX players for simultaneous sounds
	for i in MAX_SFX_PLAYERS:
		var player = AudioStreamPlayer.new()
		player.bus = "SFX"
		player.name = "SFX_%d" % i
		add_child(player)
		_sfx_pool.append(player)

	_ui_player = AudioStreamPlayer.new()
	_ui_player.bus = "SFX"
	_ui_player.name = "SoundManager_UI"
	add_child(_ui_player)

	# Load sound data from the .tres resource
	_load_sound_data()


## Create the SFX and Music audio buses if they don't exist.
func _ensure_audio_buses() -> void:
	if AudioServer.get_bus_index("SFX") < 0:
		var master_idx := AudioServer.get_bus_index("Master")
		if master_idx >= 0:
			AudioServer.add_bus(master_idx + 1)
			AudioServer.set_bus_name(master_idx + 1, "SFX")
	if AudioServer.get_bus_index("Music") < 0:
		var sfx_idx := AudioServer.get_bus_index("SFX")
		if sfx_idx >= 0:
			AudioServer.add_bus(sfx_idx + 1)
			AudioServer.set_bus_name(sfx_idx + 1, "Music")
		else:
			var master_idx := AudioServer.get_bus_index("Master")
			if master_idx >= 0:
				AudioServer.add_bus(master_idx + 1)
				AudioServer.set_bus_name(master_idx + 1, "Music")


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
## Uses a pool of audio players so multiple sounds can play simultaneously.
func play_sfx(stream: AudioStream) -> void:
	if stream == null or _sfx_pool.is_empty():
		return
	
	# First, try to find an idle player
	var player_to_use: AudioStreamPlayer = null
	for player in _sfx_pool:
		if not player.playing:
			player_to_use = player
			break
	
	# If all players are busy, steal the oldest one (round-robin)
	if player_to_use == null:
		player_to_use = _sfx_pool[_next_sfx_index]
		player_to_use.stop()
		_next_sfx_index = (_next_sfx_index + 1) % _sfx_pool.size()
	
	player_to_use.stream = stream
	player_to_use.pitch_scale = randf_range(0.95, 1.05)
	player_to_use.play()


## Play a sound effect by id with a specific pitch scale.
func play_by_id_with_pitch(id: String, pitch: float = 1.0) -> void:
	var stream = get_stream(id)
	if stream == null:
		return
	play_sfx_with_pitch(stream, pitch)


## Play a raw AudioStream with a specific pitch scale.
func play_sfx_with_pitch(stream: AudioStream, pitch: float = 1.0) -> void:
	if stream == null or _sfx_pool.is_empty():
		return
	
	var player_to_use: AudioStreamPlayer = null
	for player in _sfx_pool:
		if not player.playing:
			player_to_use = player
			break
	
	if player_to_use == null:
		player_to_use = _sfx_pool[_next_sfx_index]
		player_to_use.stop()
		_next_sfx_index = (_next_sfx_index + 1) % _sfx_pool.size()
	
	player_to_use.stream = stream
	player_to_use.pitch_scale = pitch
	player_to_use.play()


## Play a UI sound (e.g. menu click).
func play_ui_sfx(id: String) -> void:
	var stream = get_stream(id)
	if stream == null or _ui_player == null:
		return
	_ui_player.stream = stream
	_ui_player.pitch_scale = randf_range(0.95, 1.05)
	_ui_player.play()
