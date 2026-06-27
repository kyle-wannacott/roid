extends CanvasLayer
## Debug console — toggled with backtick (`).
## Supports /commands with tab-completion and command history.

@onready var command_line:      LineEdit       = %CommandLine
@onready var output_log:        RichTextLabel  = %OutputLog
@onready var suggestions_panel: PanelContainer = %SuggestionsPanel
@onready var suggestions_list:  VBoxContainer  = %SuggestionsList

const HISTORY_FILE := "user://debug_history.txt"
const HISTORY_MAX  := 100

var _commands:      Dictionary    = {}
var _spawn_types:   Array[String] = []
var _history:       Array[String] = []
var _history_index: int           = 0

func _ready() -> void:
	if not (OS.is_debug_build() or Engine.is_editor_hint()):
		queue_free()
		return
	add_to_group("debug_console")
	visible = false
	_register_commands()
	_register_spawn_types()
	_load_history()

func _register_commands() -> void:
	_commands = {
		"/help":      "/help  -- Show all available commands",
		"/distance":  "/distance <meters>  -- Place ship N meters from station",
		"/spawn":     "/spawn <type> [count]  -- Spawn enemies in front of the ship",
		"/kill_all":  "/kill_all  -- Kill all active enemies",
		"/gems":      "/gems <amount>  -- Add gems to the player",
		"/fuel":      "/fuel <amount>  -- Set fuel level",
		"/health":    "/health <amount>  -- Set health level",
		"/god":       "/god  -- Toggle god mode (invincibility)",
		"/refill":    "/refill  -- Full refuel, repair, and re-arm",
		"/time":      "/time <scale>  -- Set time scale (1=normal, 0=pause)",
	}

func _register_spawn_types() -> void:
	_spawn_types = [
		"scout_drone",
		"heavy_gunship",
		"missile_cruiser",
		"serpent_boss",
	]

func _load_history() -> void:
	var file := FileAccess.open(HISTORY_FILE, FileAccess.READ)
	if not file:
		return
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if not line.is_empty():
			_history.append(line)
	if _history.size() > HISTORY_MAX:
		_history = _history.slice(_history.size() - HISTORY_MAX)
	_history_index = _history.size()

func _append_history(cmd: String) -> void:
	if _history.is_empty() or _history.back() != cmd:
		_history.append(cmd)
		if _history.size() > HISTORY_MAX:
			_history = _history.slice(1)
		var file := FileAccess.open(HISTORY_FILE, FileAccess.READ_WRITE)
		if not file:
			file = FileAccess.open(HISTORY_FILE, FileAccess.WRITE)
		if file:
			file.seek_end()
			file.store_line(cmd)
	_history_index = _history.size()

func _history_up() -> void:
	if _history.is_empty():
		return
	_history_index = maxi(_history_index - 1, 0)
	command_line.text = _history[_history_index]
	command_line.caret_column = command_line.text.length()
	_update_suggestions(command_line.text)

func _history_down() -> void:
	if _history.is_empty():
		return
	_history_index += 1
	if _history_index >= _history.size():
		_history_index = _history.size()
		command_line.text = ""
	else:
		command_line.text = _history[_history_index]
	command_line.caret_column = command_line.text.length()
	_update_suggestions(command_line.text)

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	if event.keycode == KEY_QUOTELEFT and not event.echo:
		_toggle_console()
		get_viewport().set_input_as_handled()
		return
	if not visible:
		return
	match event.keycode:
		KEY_ESCAPE:
			_toggle_console()
		KEY_UP:
			_history_up()
		KEY_DOWN:
			_history_down()
		KEY_TAB:
			if not event.echo:
				_tab_complete()
	get_viewport().set_input_as_handled()

func _toggle_console() -> void:
	visible = not visible
	if visible:
		command_line.grab_focus()
	else:
		command_line.release_focus()
		_hide_suggestions()

func _on_command_changed(text: String) -> void:
	_update_suggestions(text)

func _tab_complete() -> void:
	var first := suggestions_list.get_child(0) as Button
	if first:
		first.emit_signal("pressed")

func _update_suggestions(text: String) -> void:
	_clear_suggestions()
	if text.is_empty():
		return
	var parts := text.split(" ", false)
	var matches: Array[String] = []
	if parts.size() <= 1:
		var query := parts[0] if not parts.is_empty() else ""
		for cmd in _commands.keys():
			if _fuzzy_match(query, cmd):
				matches.append(cmd)
	elif parts[0] == "/spawn" and parts.size() == 2:
		for type_name: String in _spawn_types:
			if _fuzzy_match(parts[1], type_name):
				matches.append(type_name)
	if matches.is_empty():
		return
	for m in matches:
		var btn := Button.new()
		btn.text      = m
		btn.flat      = true
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_color_override("font_color",       Color(0.75, 0.9, 1.0))
		btn.add_theme_color_override("font_hover_color", Color(1.0,  1.0, 1.0))
		btn.add_theme_font_size_override("font_size", 13)
		var cm := m
		var cp := parts.duplicate()
		btn.pressed.connect(func() -> void:
			if cp.size() >= 1 and cp[0] in ["/spawn"] and cp.size() == 2:
				command_line.text = cp[0] + " " + cm + " "
			else:
				command_line.text = cm + " "
			command_line.caret_column = command_line.text.length()
			_hide_suggestions()
			command_line.grab_focus()
			_update_suggestions(command_line.text)
		)
		suggestions_list.add_child(btn)
	suggestions_panel.visible = true

func _clear_suggestions() -> void:
	for child in suggestions_list.get_children():
		child.queue_free()

func _hide_suggestions() -> void:
	suggestions_panel.visible = false
	_clear_suggestions()

func _fuzzy_match(query: String, candidate: String) -> bool:
	if query.is_empty():
		return true
	query     = query.to_lower()
	candidate = candidate.to_lower()
	var qi := 0
	for i in range(candidate.length()):
		if qi < query.length() and candidate[i] == query[qi]:
			qi += 1
	return qi == query.length()

func _on_command_submitted(text: String) -> void:
	var trimmed := text.strip_edges()
	if trimmed.is_empty():
		return
	_log("[color=#5eaad4]> %s[/color]" % trimmed)
	_execute_command(trimmed)
	_append_history(trimmed)
	command_line.text = ""
	_hide_suggestions()

func _execute_command(cmd: String) -> void:
	var parts := cmd.split(" ", false)
	if parts.is_empty():
		return
	match parts[0].to_lower():
		"/help":      _cmd_help()
		"/distance":  _cmd_distance(parts)
		"/spawn":     _cmd_spawn(parts)
		"/kill_all":  _cmd_kill_all()
		"/gems":      _cmd_gems(parts)
		"/fuel":      _cmd_fuel(parts)
		"/health":    _cmd_health(parts)
		"/god":       _cmd_god()
		"/refill":    _cmd_refill()
		"/time":      _cmd_time(parts)
		_:
			_log("[color=#e05050]Unknown command: %s   (try /help)[/color]" % parts[0])

func _get_ship() -> Node:
	var ship: Node = get_tree().get_first_node_in_group("player_ship")
	return ship

func _get_enemy_manager() -> Node:
	return get_tree().get_first_node_in_group("enemy_managers")

func _get_station() -> Node:
	return get_tree().get_first_node_in_group("station")

# ── Command implementations ───────────────────────────────────────────────────

func _cmd_help() -> void:
	_log("[color=#5eaad4]=== Debug Console Commands ===[/color]")
	for desc in _commands.values():
		_log("[color=#cccccc]  %s[/color]" % desc)
	_log("[color=#888]Spawn types: %s[/color]" % ", ".join(_spawn_types))
	_log("[color=#888]Up/Down=history  Tab=complete  Esc=close[/color]")

func _cmd_distance(parts: Array) -> void:
	if parts.size() < 2 or not parts[1].is_valid_int():
		_log("[color=#e0c050]Usage: /distance <meters>[/color]")
		return
	var dist := float(int(parts[1]))
	var ship := _get_ship()
	var station := _get_station()
	if ship == null or station == null:
		_log("[color=#e05050]Ship or station not found.[/color]")
		return
	
	# Place ship at 'dist' meters from station in the ship's current forward direction
	var forward: Vector3 = -ship.global_transform.basis.z
	forward.y = 0.0
	if forward.length() < 0.01:
		forward = Vector3(0, 0, -1)
	forward = forward.normalized()
	
	var new_pos: Vector3 = station.global_position + forward * dist
	new_pos.y = ship.global_position.y  # Keep same altitude
	ship.global_position = new_pos
	
	_log("[color=#50e080]Ship placed %d meters from station.[/color]" % int(dist))

func _cmd_spawn(parts: Array) -> void:
	if parts.size() < 2:
		_log("[color=#e0c050]Usage: /spawn <type> [count][/color]")
		_log("[color=#888]Types: " + ", ".join(_spawn_types) + "[/color]")
		return
	
	var type_name: String = ""
	var count := 1
	for i in range(1, parts.size()):
		if parts[i].is_valid_int():
			count = clampi(int(parts[i]), 1, 100)
		else:
			type_name = parts[i].to_lower()
	
	if type_name.is_empty() or type_name not in _spawn_types:
		_log("[color=#e05050]Unknown type '%s'.[/color]" % type_name)
		_log("[color=#888]Types: " + ", ".join(_spawn_types) + "[/color]")
		return
	
	var ship := _get_ship()
	if ship == null:
		_log("[color=#e05050]Ship not found — cannot determine spawn position.[/color]")
		return
	
	var enemy_mgr := _get_enemy_manager()
	if enemy_mgr == null:
		_log("[color=#e05050]EnemyManager not found.[/color]")
		return
	
	# Determine scene based on type
	var scene_path: String = ""
	match type_name:
		"scout_drone":    scene_path = "res://scenes/enemies/ScoutDrone.tscn"
		"heavy_gunship":  scene_path = "res://scenes/enemies/HeavyGunship.tscn"
		"missile_cruiser": scene_path = "res://scenes/enemies/MissileCruiser.tscn"
		"serpent_boss":   scene_path = "res://scenes/enemies/SerpentBoss.tscn"
	
	if scene_path.is_empty():
		_log("[color=#e05050]No scene for type '%s'.[/color]" % type_name)
		return
	
	var scene := load(scene_path) as PackedScene
	if scene == null:
		_log("[color=#e05050]Failed to load scene: %s[/color]" % scene_path)
		return
	
	# Spawn enemies in a line in front of the ship, spread out
	var forward: Vector3 = -ship.global_transform.basis.z
	forward.y = 0.0
	if forward.length() < 0.01:
		forward = Vector3(0, 0, -1)
	forward = forward.normalized()
	var right: Vector3 = forward.cross(Vector3.UP).normalized()
	
	var spawned := 0
	for i in range(count):
		var enemy := scene.instantiate() as Node3D
		if enemy == null:
			continue
		
		# Position: in front of ship, with slight horizontal spread
		var offset_forward := 30.0 + i * 5.0  # Spread forward
		var offset_right := (i - (count - 1) * 0.5) * 6.0  # Spread sideways
		var spawn_pos: Vector3 = ship.global_position + forward * offset_forward + right * offset_right
		spawn_pos.y = 1.5  # Ground height
		
		get_tree().current_scene.add_child(enemy)
		enemy.global_position = spawn_pos
		
		spawned += 1
	
	_log("[color=#50e080]Spawned %d x %s[/color]" % [spawned, type_name])

func _cmd_kill_all() -> void:
	var killed := 0
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(enemy) and enemy.has_method("die"):
			enemy.die()
			killed += 1
		elif is_instance_valid(enemy) and enemy.has_method("queue_free"):
			enemy.queue_free()
			killed += 1
	
	# Also clear from EnemyManager
	var enemy_mgr := _get_enemy_manager()
	if enemy_mgr != null and enemy_mgr.has_method("clear_all_enemies"):
		enemy_mgr.clear_all_enemies()
	
	_log("[color=#50e080]Killed %d enemies.[/color]" % killed)

func _cmd_gems(parts: Array) -> void:
	if parts.size() < 2 or not parts[1].is_valid_int():
		_log("[color=#e0c050]Usage: /gems <amount>[/color]")
		return
	var amount := int(parts[1])
	var ship := _get_ship()
	if ship != null and ship.has_method("set_gems"):
		ship.set_gems(amount)
	elif PlayerSkills:
		PlayerSkills.set_gems(amount)
	_log("[color=#50e080]Gems set to %d.[/color]" % amount)

func _cmd_fuel(parts: Array) -> void:
	if parts.size() < 2 or not parts[1].is_valid_int():
		_log("[color=#e0c050]Usage: /fuel <amount>[/color]")
		return
	var amount := int(parts[1])
	var ship := _get_ship()
	if ship != null and ship.has_method("set_fuel"):
		ship.set_fuel(amount)
	elif ship != null:
		ship.fuel = float(amount)
		ship.fuel_changed.emit(ship.fuel, ship._eff_fuel_max)
	_log("[color=#50e080]Fuel set to %d.[/color]" % amount)

func _cmd_health(parts: Array) -> void:
	if parts.size() < 2 or not parts[1].is_valid_int():
		_log("[color=#e0c050]Usage: /health <amount>[/color]")
		return
	var amount := int(parts[1])
	var ship := _get_ship()
	if ship != null:
		ship.health = float(amount)
		ship.health_changed.emit(ship.health, ship._eff_max_health)
	_log("[color=#50e080]Health set to %d.[/color]" % amount)

func _cmd_god() -> void:
	var ship := _get_ship()
	if ship == null:
		_log("[color=#e05050]Ship not found.[/color]")
		return
	if not ship.has_method("is_god_mode"):
		_log("[color=#e0c050]God mode not implemented — adding invincibility.[/color]")
		# Simple god mode via damage cooldown override
		ship.set_meta("god_mode", not ship.get_meta("god_mode", false))
		var on: bool = ship.get_meta("god_mode", false)
		_log("[color=#50e080]God mode: %s[/color]" % ("ON" if on else "OFF"))
		return
	
	var on: bool = not ship.is_god_mode()
	ship.set_god_mode(on)
	_log("[color=#50e080]God mode: %s[/color]" % ("ON" if on else "OFF"))

func _cmd_refill() -> void:
	var ship := _get_ship()
	if ship == null:
		_log("[color=#e05050]Ship not found.[/color]")
		return
	ship.fuel = ship._eff_fuel_max if "fuel_max" in ship else 100.0
	ship.health = ship._eff_max_health if "max_health" in ship else 100.0
	if "fuel_changed" in ship:
		ship.fuel_changed.emit(ship.fuel, ship._eff_fuel_max)
	if "health_changed" in ship:
		ship.health_changed.emit(ship.health, ship._eff_max_health)
	# Re-arm missiles
	if "_missile_ammo_left" in ship and "_eff_missile_max_per_pod" in ship:
		ship._missile_ammo_left = ship._eff_missile_max_per_pod
		ship._missile_ammo_right = ship._eff_missile_max_per_pod
	_log("[color=#50e080]Ship fully refuelled, repaired, and re-armed.[/color]" % [])

func _cmd_time(parts: Array) -> void:
	if parts.size() < 2 or not parts[1].is_float():
		_log("[color=#e0c050]Usage: /time <scale>  (1=normal, 0.5=half speed, 0=pause)[/color]")
		return
	var scale := float(parts[1])
	Engine.time_scale = clampf(scale, 0.0, 10.0)
	var paused := " (PAUSED)" if scale == 0.0 else ""
	_log("[color=#50e080]Time scale set to %.2f%s[/color]" % [Engine.time_scale, paused])

func _log(text: String) -> void:
	output_log.append_text(text + "\n")
