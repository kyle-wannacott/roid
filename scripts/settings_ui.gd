extends Control
## Settings UI — audio, controls, graphics, and game options tabs.

signal close_requested

# ── Audio tab ──────────────────────────────────────────────────────────────────
@onready var master_slider: HSlider = %MasterSlider
@onready var sfx_slider: HSlider = %SFXSlider
@onready var music_slider: HSlider = %MusicSlider
@onready var mute_master_check: CheckBox = %MuteMasterCheckbox
@onready var mute_sfx_check: CheckBox = %MuteSFXCheckbox
@onready var mute_music_check: CheckBox = %MuteMusicCheckbox

# ── Controls tab ───────────────────────────────────────────────────────────────
@onready var keybind_list: VBoxContainer = %KeybindList

# ── Tabs ───────────────────────────────────────────────────────────────────────
@onready var tabs: TabContainer = $PanelContainer/VBoxContainer/TabContainer

## Friendly display names for game actions
const ACTION_LABELS: Dictionary = {
	"thrust_forward": "Thrust Forward",
	"thrust_back": "Thrust Backward",
	"turn_left": "Turn Left",
	"turn_right": "Turn Right",
	"thrust_up": "Afterburner (Space)",
	"roll_left": "Barrel Roll Left",
	"roll_right": "Barrel Roll Right",
	"mine": "Mine / Harpoon",
	"turret_fire": "Fire Turret",
	"missile_fire": "Fire Missiles",
	"flare_fire": "Fire Flares",
	"harpoon": "Fire Harpoon",
	"reset": "Respawn / Reset",
	"camera_toggle": "Toggle Camera",
	"toggle_settings": "Toggle Settings (Escape)",
	"toggle_skill_tree": "Toggle Skill Tree (T)",
}

var _remapping := false
var _remap_action: StringName = &""
var _remap_button: Button = null

var _panel_border_style: StyleBoxFlat

func _ready() -> void:
	# Load current audio values
	master_slider.value = GlobalSettings.master_volume
	sfx_slider.value = GlobalSettings.sfx_volume
	music_slider.value = GlobalSettings.music_volume
	mute_master_check.button_pressed = GlobalSettings.master_muted
	mute_sfx_check.button_pressed = GlobalSettings.sfx_muted
	mute_music_check.button_pressed = GlobalSettings.music_muted
	
	_update_mute_icon(mute_master_check, GlobalSettings.master_muted)
	_update_mute_icon(mute_sfx_check, GlobalSettings.sfx_muted)
	_update_mute_icon(mute_music_check, GlobalSettings.music_muted)
	
	_panel_border_style = StyleBoxFlat.new()
	_panel_border_style.bg_color = Color(0.12, 0.12, 0.15, 0.3)
	_panel_border_style.border_color = Color(0.35, 0.35, 0.40, 0.6)
	_panel_border_style.border_width_left = 1
	_panel_border_style.border_width_top = 1
	_panel_border_style.border_width_right = 1
	_panel_border_style.border_width_bottom = 1
	_panel_border_style.corner_radius_top_left = 2
	_panel_border_style.corner_radius_top_right = 2
	_panel_border_style.corner_radius_bottom_right = 2
	_panel_border_style.corner_radius_bottom_left = 2
	_panel_border_style.content_margin_left = 14
	_panel_border_style.content_margin_top = 12
	_panel_border_style.content_margin_right = 14
	_panel_border_style.content_margin_bottom = 12
	
	_build_keybind_list()
	_build_graphics_tab()
	_build_game_tab()
	_apply_tab_padding()
	
	if tabs != null:
		tabs.current_tab = 0


func _apply_tab_padding() -> void:
	var audio_vbox := $PanelContainer/VBoxContainer/TabContainer/Audio/VBoxContainer
	if audio_vbox:
		audio_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 12)
		audio_vbox.add_theme_constant_override("separation", 8)
		for child in audio_vbox.get_children():
			if child is PanelContainer:
				child.add_theme_stylebox_override("panel", _panel_border_style)
	var controls_layout := $PanelContainer/VBoxContainer/TabContainer/Controls/ControlsLayout
	if controls_layout:
		controls_layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 12)
		controls_layout.add_theme_constant_override("separation", 10)


# ── Audio ──────────────────────────────────────────────────────────────────────

func _on_master_slider_value_changed(value: float) -> void:
	GlobalSettings.master_volume = value
	GlobalSettings.apply_audio()

func _on_sfx_slider_value_changed(value: float) -> void:
	GlobalSettings.sfx_volume = value
	GlobalSettings.apply_audio()

func _on_music_slider_value_changed(value: float) -> void:
	GlobalSettings.music_volume = value
	GlobalSettings.apply_audio()

func _on_mute_master_toggled(muted: bool) -> void:
	GlobalSettings.master_muted = muted
	GlobalSettings.apply_audio()
	_update_mute_icon(mute_master_check, muted)

func _on_mute_sfx_toggled(muted: bool) -> void:
	GlobalSettings.sfx_muted = muted
	GlobalSettings.apply_audio()
	_update_mute_icon(mute_sfx_check, muted)

func _on_mute_music_toggled(muted: bool) -> void:
	GlobalSettings.music_muted = muted
	GlobalSettings.apply_audio()
	_update_mute_icon(mute_music_check, muted)

func _update_mute_icon(cb: CheckBox, muted: bool) -> void:
	cb.modulate = Color(0.6, 0.25, 0.25) if muted else Color.WHITE


# ── Keybinds ───────────────────────────────────────────────────────────────────

func _build_keybind_list() -> void:
	for child in keybind_list.get_children():
		child.queue_free()
	for action in InputMap.get_actions():
		var action_str := action as String
		if action_str.begins_with("ui_"):
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var lbl := Label.new()
		lbl.text = ACTION_LABELS.get(action_str, action_str.replace("_", " ").capitalize()) + ":"
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.add_theme_color_override("font_color", Color(0.85, 0.80, 0.65, 1.0))
		var btn := Button.new()
		var events := InputMap.action_get_events(action)
		btn.text = _event_text(events[0]) if events.size() > 0 else "(Unbound)"
		btn.custom_minimum_size = Vector2(160, 0)
		btn.pressed.connect(_on_keybind_btn_pressed.bind(action_str, btn))
		row.add_child(lbl)
		row.add_child(btn)
		keybind_list.add_child(_wrap_in_border(row))
	
	# Reset button at the bottom
	var sep := HSeparator.new()
	keybind_list.add_child(sep)
	var reset_row := HBoxContainer.new()
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset_row.add_child(spacer)
	var reset_btn := Button.new()
	reset_btn.text = "Reset to Defaults"
	reset_btn.pressed.connect(_reset_keybinds)
	reset_row.add_child(reset_btn)
	keybind_list.add_child(_wrap_in_border(reset_row))


func _event_text(event: InputEvent) -> String:
	if event == null:
		return "(Unbound)"
	var t := event.as_text()
	return t.trim_suffix(" (Physical)").trim_suffix(" (physical)")


func _on_keybind_btn_pressed(action: String, btn: Button) -> void:
	if _remapping:
		_finish_remap(null)
	_remapping = true
	_remap_action = action
	_remap_button = btn
	btn.text = "[ Press a key... ]"
	btn.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3, 1.0))
	get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if not _remapping:
		return
	if event is InputEventKey:
		if event.pressed and not event.echo:
			_finish_remap(event)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		if event.pressed:
			_finish_remap(event)
			get_viewport().set_input_as_handled()


func _finish_remap(event: InputEvent) -> void:
	if not _remapping:
		return
	var action := _remap_action
	var btn := _remap_button
	_remapping = false
	_remap_action = &""
	_remap_button = null
	if event == null or btn == null:
		_build_keybind_list()
		return
	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, event)
	btn.text = _event_text(event)
	btn.remove_theme_color_override("font_color")
	GlobalSettings.save_keybinds()


func _cancel_remap() -> void:
	_finish_remap(null)


func _reset_keybinds() -> void:
	_cancel_remap()
	GlobalSettings.reset_keybinds()
	_build_keybind_list()


# ── Graphics tab ───────────────────────────────────────────────────────────────

func _build_graphics_tab() -> void:
	var tab := $PanelContainer/VBoxContainer/TabContainer/Graphics
	if tab == null:
		return
	for c in tab.get_children():
		c.queue_free()
	
	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 12)
	tab.add_child(layout)
	
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(scroll)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)
	
	# ── VSync ────────────────────────────────────────────────────────────────
	vbox.add_child(_make_setting("VSync", func():
		var check := CheckBox.new()
		check.button_pressed = GlobalSettings.vsync_enabled
		check.toggled.connect(func(on: bool) -> void:
			GlobalSettings.vsync_enabled = on
			GlobalSettings._apply_vsync()
			GlobalSettings.graphics_settings_changed.emit())
		return check))
	
	# ── Pixelation ───────────────────────────────────────────────────────────
	vbox.add_child(_make_setting("Pixelation", func():
		var check := CheckBox.new()
		check.button_pressed = GlobalSettings.pixelate_enabled
		check.toggled.connect(func(on: bool) -> void:
			GlobalSettings.pixelate_enabled = on
			GlobalSettings.graphics_settings_changed.emit())
		return check))
	
	# ── Pixelation Level ─────────────────────────────────────────────────────
	vbox.add_child(_make_setting("Pixelation Level", func():
		var opt := OptionButton.new()
		opt.custom_minimum_size = Vector2(160, 0)
		opt.add_item("Low (640×360)")
		opt.add_item("Medium (800×450)")
		opt.add_item("High (1152×648)")
		opt.selected = clampi(GlobalSettings.pixelation_level, 0, 2)
		opt.item_selected.connect(func(idx: int) -> void:
			GlobalSettings.pixelation_level = idx
			GlobalSettings.graphics_settings_changed.emit())
		return opt))
	
	# ── CRT Effect ───────────────────────────────────────────────────────────
	vbox.add_child(_make_setting("CRT Effect", func():
		var check := CheckBox.new()
		check.button_pressed = GlobalSettings.crt_enabled
		check.toggled.connect(func(on: bool) -> void:
			GlobalSettings.crt_enabled = on
			GlobalSettings.graphics_settings_changed.emit())
		return check))
	
	# ── Pixel Palette (quantisation) ─────────────────────────────────────────
	var sep := HSeparator.new()
	vbox.add_child(sep)
	
	vbox.add_child(_make_setting("Pixel Palette", func():
		var check := CheckBox.new()
		check.button_pressed = GlobalSettings.quantize_enabled
		check.toggled.connect(func(on: bool) -> void:
			GlobalSettings.quantize_enabled = on
			GlobalSettings.graphics_settings_changed.emit())
		return check))
	
	vbox.add_child(_make_setting("Palette", func():
		var opt := OptionButton.new()
		opt.custom_minimum_size = Vector2(160, 0)
		for pname in GlobalSettings.PALETTE_NAMES:
			opt.add_item(pname)
		opt.selected = clampi(GlobalSettings.quantize_palette_index, 0, GlobalSettings.PALETTE_NAMES.size() - 1)
		opt.item_selected.connect(func(idx: int) -> void:
			GlobalSettings.quantize_palette_index = idx
			GlobalSettings.graphics_settings_changed.emit())
		return opt))
	
	# ── World Fog ────────────────────────────────────────────────────────────
	vbox.add_child(_make_setting("World Fog", func():
		var check := CheckBox.new()
		check.button_pressed = GlobalSettings.fog_enabled
		check.toggled.connect(func(on: bool) -> void:
			GlobalSettings.fog_enabled = on
			GlobalSettings.graphics_settings_changed.emit())
		return check))
	
	# ── Tonemapping ──────────────────────────────────────────────────────────
	vbox.add_child(_make_setting("Tonemapping", func():
		var opt := OptionButton.new()
		opt.custom_minimum_size = Vector2(160, 0)
		for label in ["Linear", "Reinhard", "Filmic", "ACES", "AGX"]:
			opt.add_item(label)
		opt.selected = GlobalSettings.tonemapping_mode
		opt.item_selected.connect(func(idx: int) -> void:
			GlobalSettings.tonemapping_mode = idx
			GlobalSettings.graphics_settings_changed.emit())
		return opt))
	
	# ── Shadows ──────────────────────────────────────────────────────────────
	vbox.add_child(_make_setting("Shadows", func():
		var check := CheckBox.new()
		check.button_pressed = GlobalSettings.shadows_enabled
		check.toggled.connect(func(on: bool) -> void:
			GlobalSettings.shadows_enabled = on
			GlobalSettings.graphics_settings_changed.emit())
		return check))
	
	_style_checkboxes_in(vbox)


# ── Game tab ───────────────────────────────────────────────────────────────────

func _build_game_tab() -> void:
	var tab := $PanelContainer/VBoxContainer/TabContainer/Game
	if tab == null:
		return
	for c in tab.get_children():
		c.queue_free()
	
	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 12)
	tab.add_child(layout)
	
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(scroll)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)
	
	vbox.add_child(_make_setting("Damage Numbers", func():
		var check := CheckBox.new()
		check.button_pressed = GlobalSettings.damage_numbers_enabled
		check.toggled.connect(func(on: bool) -> void:
			GlobalSettings.damage_numbers_enabled = on
			GlobalSettings.game_settings_changed.emit())
		return check))
	
	vbox.add_child(_make_setting("HUD Layout", func():
		var opt := OptionButton.new()
		opt.custom_minimum_size = Vector2(160, 0)
		opt.add_item("Default")
		opt.add_item("Mirrored")
		opt.selected = clampi(GlobalSettings.hud_layout, 0, 1)
		opt.item_selected.connect(func(idx: int) -> void:
			GlobalSettings.hud_layout = idx
			GlobalSettings.game_settings_changed.emit())
		return opt))
	
	_style_checkboxes_in(vbox)


# ── Helpers ────────────────────────────────────────────────────────────────────

func _make_setting(label_text: String, control_factory: Callable) -> PanelContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var lbl := Label.new()
	lbl.text = label_text + ":"
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_color_override("font_color", Color(0.85, 0.80, 0.65, 1.0))
	row.add_child(lbl)
	row.add_child(control_factory.call())
	return _wrap_in_border(row)


func _wrap_in_border(content: Control) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_border_style)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(content)
	return panel


func _style_checkboxes_in(parent: Node) -> void:
	var border := StyleBoxFlat.new()
	border.bg_color = Color(0, 0, 0, 0)
	border.border_color = Color(0.45, 0.45, 0.50, 0.8)
	border.border_width_left = 1
	border.border_width_top = 1
	border.border_width_right = 1
	border.border_width_bottom = 1
	border.corner_radius_top_left = 2
	border.corner_radius_top_right = 2
	border.corner_radius_bottom_right = 2
	border.corner_radius_bottom_left = 2
	border.content_margin_left = 0
	border.content_margin_top = 0
	border.content_margin_right = 0
	border.content_margin_bottom = 0
	for c in parent.find_children("*", "CheckBox", true, false):
		var cb := c as CheckBox
		if cb:
			cb.add_theme_stylebox_override("normal", border)


func _on_close_button_pressed() -> void:
	_cancel_remap()
	GlobalSettings.save_all()
	close_requested.emit()
	hide()
