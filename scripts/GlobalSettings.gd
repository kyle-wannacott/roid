extends Node
## Global settings manager — persistable audio, graphics, controls, and game settings.
## Attached as an autoload so any script can read/write settings at any time.

# ── Audio ──────────────────────────────────────────────────────────────────────
var master_volume: float = 1.0
var sfx_volume: float = 1.0
var music_volume: float = 1.0
var master_muted: bool = false
var sfx_muted: bool = false
var music_muted: bool = false

# ── Graphics ───────────────────────────────────────────────────────────────────
var vsync_enabled: bool = true
var pixelate_enabled: bool = true
## 0=Low(640×360) 1=Med(800×450) 2=High(1152×648)
var pixelation_level: int = 2
var crt_enabled: bool = false
var quantize_enabled: bool = false
var quantize_palette_index: int = 0
var fog_enabled: bool = true
var tonemapping_mode: int = 2  # 0=Linear 1=Reinhard 2=Filmic 3=ACES 4=AGX
var shadows_enabled: bool = true

# ── Gameplay / HUD ─────────────────────────────────────────────────────────────
var damage_numbers_enabled: bool = true
var hud_layout: int = 0  # 0=default 1=mirrored

# ── Signals ────────────────────────────────────────────────────────────────────
signal graphics_settings_changed
signal game_settings_changed

const SETTINGS_PATH := "user://roid_settings.cfg"
const KEYBIND_PATH := "user://roid_controls.cfg"

# ── Palette definitions (adapted from keep project) ───────────────────────────
var PALETTES: Array = [
	# Gothic (dark fantasy)
	PackedColorArray([
		Color(0.094, 0.094, 0.125),
		Color(0.176, 0.157, 0.192),
		Color(0.251, 0.200, 0.192),
		Color(0.353, 0.235, 0.208),
		Color(0.475, 0.286, 0.176),
		Color(0.608, 0.357, 0.145),
		Color(0.784, 0.455, 0.196),
		Color(0.902, 0.616, 0.298),
		Color(0.922, 0.792, 0.498),
		Color(0.953, 0.890, 0.694),
		Color(0.804, 0.729, 0.616),
		Color(0.616, 0.533, 0.435),
		Color(0.447, 0.396, 0.345),
		Color(0.196, 0.169, 0.149),
		Color(0.094, 0.090, 0.102),
		Color(0.078, 0.086, 0.106),
		Color(0.110, 0.141, 0.125),
		Color(0.184, 0.212, 0.129),
		Color(0.306, 0.318, 0.173),
		Color(0.431, 0.447, 0.239),
		Color(0.584, 0.584, 0.316),
		Color(0.698, 0.678, 0.357),
		Color(0.659, 0.522, 0.349),
		Color(0.820, 0.518, 0.318),
		Color(1.000, 0.686, 0.373),
		Color(0.973, 0.804, 0.514),
		Color(0.553, 0.282, 0.110),
		Color(0.392, 0.188, 0.114),
		Color(0.188, 0.114, 0.090),
		Color(0.082, 0.055, 0.039),
		Color(0.173, 0.043, 0.031),
		Color(0.302, 0.067, 0.024),
	]),
	# Pico-8
	PackedColorArray([
		Color(0.0, 0.0, 0.0),
		Color(0.122, 0.122, 0.122),
		Color(0.498, 0.498, 0.498),
		Color(0.749, 0.749, 0.749),
		Color(1.0, 0.231, 0.231),
		Color(1.0, 0.643, 0.165),
		Color(1.0, 0.945, 0.145),
		Color(0.243, 0.843, 0.333),
		Color(0.259, 0.702, 0.702),
		Color(0.176, 0.400, 0.749),
		Color(0.271, 0.247, 0.663),
		Color(0.608, 0.239, 0.616),
		Color(0.843, 0.475, 0.624),
		Color(0.769, 0.678, 0.561),
		Color(0.957, 0.820, 0.718),
		Color(1.0, 1.0, 1.0),
	]),
	# Game Boy
	PackedColorArray([
		Color(0.094, 0.165, 0.086),
		Color(0.267, 0.345, 0.176),
		Color(0.553, 0.569, 0.349),
		Color(0.886, 0.898, 0.686),
	]),
	# CGA
	PackedColorArray([
		Color(0.0, 0.0, 0.0),
		Color(0.0, 0.545, 0.545),
		Color(0.545, 0.0, 0.545),
		Color(0.545, 0.545, 0.545),
		Color(0.0, 0.0, 0.0),
		Color(0.0, 0.545, 0.545),
		Color(0.545, 0.0, 0.545),
		Color(1.0, 1.0, 1.0),
	]),
	# Mono (single-channel greyscale)
	PackedColorArray([
		Color(0.0, 0.0, 0.0),
		Color(0.25, 0.25, 0.25),
		Color(0.5, 0.5, 0.5),
		Color(0.75, 0.75, 0.75),
		Color(1.0, 1.0, 1.0),
	]),
	# Sepia
	PackedColorArray([
		Color(0.09, 0.06, 0.02),
		Color(0.20, 0.15, 0.10),
		Color(0.33, 0.25, 0.17),
		Color(0.47, 0.38, 0.27),
		Color(0.62, 0.52, 0.38),
		Color(0.78, 0.68, 0.52),
		Color(0.90, 0.82, 0.68),
		Color(0.98, 0.95, 0.88),
	]),
	# Neon
	PackedColorArray([
		Color(0.0, 0.0, 0.0),
		Color(0.39, 0.0, 0.70),
		Color(0.0, 0.39, 0.98),
		Color(0.0, 0.95, 1.0),
		Color(0.0, 0.55, 0.0),
		Color(0.0, 1.0, 0.55),
		Color(0.95, 0.95, 0.0),
		Color(1.0, 0.55, 0.0),
		Color(1.0, 0.0, 0.0),
		Color(1.0, 0.0, 0.63),
		Color(0.35, 0.35, 0.35),
		Color(0.65, 0.65, 0.65),
		Color(1.0, 1.0, 1.0),
	]),
	# NES
	PackedColorArray([
		Color(0.408, 0.412, 0.369),
		Color(0.282, 0.286, 0.251),
		Color(0.129, 0.129, 0.114),
		Color(0.576, 0.380, 0.247),
		Color(0.412, 0.212, 0.114),
		Color(0.196, 0.098, 0.059),
		Color(0.988, 0.533, 0.055),
		Color(0.992, 0.784, 0.043),
		Color(0.443, 0.702, 0.161),
		Color(0.169, 0.420, 0.192),
		Color(0.067, 0.322, 0.545),
		Color(0.039, 0.196, 0.380),
		Color(0.314, 0.208, 0.525),
		Color(0.259, 0.149, 0.286),
		Color(0.973, 0.282, 0.286),
		Color(0.588, 0.176, 0.200),
		Color(0.024, 0.024, 0.024),
		Color(0.788, 0.792, 0.749),
		Color(0.620, 0.624, 0.580),
		Color(0.329, 0.329, 0.286),
		Color(0.212, 0.137, 0.086),
		Color(0.094, 0.059, 0.031),
		Color(0.988, 0.459, 0.110),
		Color(0.263, 0.569, 0.043),
		Color(0.118, 0.255, 0.125),
		Color(0.137, 0.282, 0.451),
		Color(0.122, 0.122, 0.122),
		Color(0.545, 0.463, 0.294),
		Color(0.373, 0.333, 0.220),
		Color(0.212, 0.184, 0.114),
		Color(0.573, 0.306, 0.310),
		Color(0.345, 0.129, 0.133),
	]),
]

var PALETTE_NAMES: Array = ["Gothic", "Pico-8", "Game Boy", "CGA", "Mono", "Sepia", "Neon", "NES"]


func _ready() -> void:
	load_all()


# ── Save / Load ────────────────────────────────────────────────────────────────

func save_all() -> void:
	var cfg := ConfigFile.new()
	
	# Audio
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("audio", "sfx_volume", sfx_volume)
	cfg.set_value("audio", "music_volume", music_volume)
	cfg.set_value("audio", "master_muted", master_muted)
	cfg.set_value("audio", "sfx_muted", sfx_muted)
	cfg.set_value("audio", "music_muted", music_muted)
	
	# Graphics
	cfg.set_value("graphics", "vsync_enabled", vsync_enabled)
	cfg.set_value("graphics", "pixelate_enabled", pixelate_enabled)
	cfg.set_value("graphics", "pixelation_level", pixelation_level)
	cfg.set_value("graphics", "crt_enabled", crt_enabled)
	cfg.set_value("graphics", "quantize_enabled", quantize_enabled)
	cfg.set_value("graphics", "quantize_palette_index", quantize_palette_index)
	cfg.set_value("graphics", "fog_enabled", fog_enabled)
	cfg.set_value("graphics", "tonemapping_mode", tonemapping_mode)
	cfg.set_value("graphics", "shadows_enabled", shadows_enabled)
	
	# Game
	cfg.set_value("game", "damage_numbers_enabled", damage_numbers_enabled)
	cfg.set_value("game", "hud_layout", hud_layout)
	
	cfg.save(SETTINGS_PATH)


func load_all() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		_apply_vsync()
		return
	
	# Audio
	master_volume = cfg.get_value("audio", "master_volume", 1.0)
	sfx_volume = cfg.get_value("audio", "sfx_volume", 1.0)
	music_volume = cfg.get_value("audio", "music_volume", 1.0)
	master_muted = cfg.get_value("audio", "master_muted", false)
	sfx_muted = cfg.get_value("audio", "sfx_muted", false)
	music_muted = cfg.get_value("audio", "music_muted", false)
	
	# Graphics
	vsync_enabled = cfg.get_value("graphics", "vsync_enabled", true)
	pixelate_enabled = cfg.get_value("graphics", "pixelate_enabled", true)
	pixelation_level = cfg.get_value("graphics", "pixelation_level", 2)
	crt_enabled = cfg.get_value("graphics", "crt_enabled", false)
	quantize_enabled = cfg.get_value("graphics", "quantize_enabled", false)
	quantize_palette_index = cfg.get_value("graphics", "quantize_palette_index", 0)
	fog_enabled = cfg.get_value("graphics", "fog_enabled", true)
	tonemapping_mode = cfg.get_value("graphics", "tonemapping_mode", 2)
	shadows_enabled = cfg.get_value("graphics", "shadows_enabled", true)
	
	# Game
	damage_numbers_enabled = cfg.get_value("game", "damage_numbers_enabled", true)
	hud_layout = cfg.get_value("game", "hud_layout", 0)
	
	_apply_vsync()


func save_keybinds() -> void:
	var cfg := ConfigFile.new()
	for action in InputMap.get_actions():
		if (action as String).begins_with("ui_"):
			continue
		cfg.set_value("keybinds", action, InputMap.action_get_events(action))
	cfg.save(KEYBIND_PATH)


func load_keybinds() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(KEYBIND_PATH) != OK:
		return
	for action in cfg.get_section_keys("keybinds"):
		if not InputMap.has_action(action):
			continue
		var events: Array = cfg.get_value("keybinds", action, [])
		InputMap.action_erase_events(action)
		for event in events:
			InputMap.action_add_event(action, event)


func reset_keybinds() -> void:
	InputMap.load_from_project_settings()
	var cfg := ConfigFile.new()
	cfg.save(KEYBIND_PATH)
	save_keybinds()


# ── Apply functions ────────────────────────────────────────────────────────────

func apply_audio() -> void:
	var master_idx := AudioServer.get_bus_index("Master")
	var sfx_idx := AudioServer.get_bus_index("SFX")
	var music_idx := AudioServer.get_bus_index("Music")
	
	if master_idx >= 0:
		AudioServer.set_bus_volume_db(master_idx, linear_to_db(master_volume))
		AudioServer.set_bus_mute(master_idx, master_muted)
	if sfx_idx >= 0:
		AudioServer.set_bus_volume_db(sfx_idx, linear_to_db(sfx_volume))
		AudioServer.set_bus_mute(sfx_idx, sfx_muted or master_muted)
	if music_idx >= 0:
		AudioServer.set_bus_volume_db(music_idx, linear_to_db(music_volume))
		AudioServer.set_bus_mute(music_idx, music_muted or master_muted)


func _apply_vsync() -> void:
	var mode := DisplayServer.VSYNC_ENABLED if vsync_enabled else DisplayServer.VSYNC_DISABLED
	DisplayServer.window_set_vsync_mode(mode)
