extends Node3D
## Root scene. Wires up the ship, station, asteroid field, and HUD,
## and keeps the HUD's "distance to station" readout up to date.

@export var station_path: NodePath
@export var ship_path: NodePath
@export var hud_path: NodePath

@onready var asteroids_root: Node3D = $AsteroidManager
@onready var asteroid_mgr: AsteroidManager = $AsteroidManager
@onready var ship: Node3D = get_node(ship_path)
@onready var station: Node3D = get_node(station_path)
@onready var hud: CanvasLayer = get_node(hud_path)
@onready var camera: Camera3D = $ChaseCamera
@onready var _skill_tree: Control = $ToolsLayer/SkillTree
@onready var _spreadsheet: Control = $ToolsLayer/Spreadsheet
@onready var _settings: Control = $SettingsLayer/Settings
@onready var _pixelation_rect: ColorRect = $PostProcessLayer/PixelationRect
@onready var _crt_rect: ColorRect = $PostProcessLayer/CRTRect
@onready var enemy_mgr: Node3D = $EnemyManager
@onready var spawn_gen: Node3D = $SpawnPointGenerator

## Preloaded gem scene so enemies drop physical pickups instead of
## directly awarding gems to the player's inventory.
const GEM_SCENE: PackedScene = preload("res://scenes/Gem.tscn")


var _was_docked := false

func _ready() -> void:
	randomize()
	# The AsteroidManager spawns all asteroids in its _ready().
	if asteroid_mgr:
		asteroid_mgr.asteroid_destroyed.connect(_on_asteroid_destroyed)
	_wire_signals()
	# Sync initial gems to PlayerSkills
	if ship.has_method("get_gem_inventory"):
		PlayerSkills.set_gem_inventory(ship.get_gem_inventory())
	elif ship.has_method("get_gems"):
		PlayerSkills.set_gems(ship.get_gems())
	
	# Setup enemy manager
	if enemy_mgr:
		enemy_mgr.enemy_destroyed.connect(_on_enemy_destroyed)
		enemy_mgr.encounter_started.connect(_on_encounter_started)
		enemy_mgr.encounter_completed.connect(_on_encounter_completed)
	
	# ── Settings ──────────────────────────────────────────────────────
	GlobalSettings.apply_audio()
	if _settings:
		_settings.visible = false
		_settings.close_requested.connect(_on_settings_closed)
	
	# Wire graphics changes to the post-processing rects
	GlobalSettings.graphics_settings_changed.connect(_apply_graphics_settings)
	_apply_graphics_settings()
	
	# Set up process mode so settings pauses game
	process_mode = PROCESS_MODE_ALWAYS
	
	# Start the ship docked inside the hangar
	call_deferred("_initial_dock")
	
	# Spawn planets in the distance
	_spawn_planets()


func _wire_signals() -> void:
	if ship.has_signal("fuel_changed"):
		ship.fuel_changed.connect(hud.set_fuel)
	if ship.has_signal("gems_changed"):
		ship.gems_changed.connect(hud.set_gems)
		ship.gems_changed.connect(_on_ship_gems_changed)
		ship.gems_changed.connect(_on_gems_changed)
	if ship.has_signal("speed_changed"):
		ship.speed_changed.connect(hud.set_speed)
		ship.speed_changed.connect(_on_speed_for_reticle)
	if ship.has_signal("mining_state_changed"):
		ship.mining_state_changed.connect(hud.set_mining)
	if ship.has_signal("station_distance_changed"):
		ship.station_distance_changed.connect(hud.set_station_distance)
	if ship.has_signal("health_changed"):
		ship.health_changed.connect(hud.set_health)
	if ship.has_signal("state_changed"):
		ship.state_changed.connect(hud.set_state)
	if ship.has_signal("shield_changed"):
		ship.shield_changed.connect(hud.set_shield)


func _process(_delta: float) -> void:
	# ── Settings toggle (Escape) ──────────────────────────────────────
	if Input.is_action_just_pressed("toggle_settings"):
		_toggle_settings()
	
	# ── Skill tree toggle (T, only when docked) ──────────────────────
	if Input.is_action_just_pressed("toggle_skill_tree") and _was_docked:
		_toggle_skill_tree()
	
	if not is_instance_valid(station) or not is_instance_valid(ship):
		return

	# Update the "distance to station" readout every frame.
	var d: float = ship.global_position.distance_to(station.global_position)
	var docked: bool = false
	# Treat "docking in progress" the same as "docked" so the skill tree
	# opens as soon as the ship enters a bay (not just when the animation
	# finishes) and gems sync at the same time.
	if station.has_method("is_ship_docking_or_docked"):
		docked = station.is_ship_docking_or_docked(ship)
	elif station.has_method("is_ship_docked"):
		docked = station.is_ship_docked(ship)
	if ship.has_signal("station_distance_changed"):
		ship.emit_signal("station_distance_changed", d, docked)
	
	# Auto-show skill tree on dock, auto-hide on undock
	if docked != _was_docked:
		_was_docked = docked
		if docked:
			# Sync gems to PlayerSkills FIRST so the skill tree shows the
			# correct inventory the moment it opens (instead of briefly
			# showing 0 before the gems stream in).
			if ship.has_method("get_gem_inventory"):
				PlayerSkills.set_gem_inventory(ship.get_gem_inventory())
			elif ship.has_method("get_gems"):
				PlayerSkills.set_gems(ship.get_gems())
			_toggle_skill_tree(true)
		else:
			# When undocking, sync gems back to the ship BEFORE closing
			# the skill tree so any pending unlocks are reflected.
			if ship.has_method("set_gem_inventory"):
				ship.set_gem_inventory(PlayerSkills.get_all_gem_counts())
			elif ship.has_method("set_gems"):
				ship.set_gems(PlayerSkills.get_total_gems())
			if _skill_tree and _skill_tree.visible:
				_toggle_skill_tree(false)


func _on_asteroid_destroyed(world_pos: Vector3, gem_count: int) -> void:
	# Could play a sound, spawn particles, etc.
	pass


func _on_enemy_destroyed(enemy: Node3D, position: Vector3, gem_table: Dictionary) -> void:
	# Drop physical gem pickups instead of directly adding to inventory
	# This lets the player fly over them to collect, just like asteroid gems.
	# gem_table is a Dictionary of {type: count} e.g. {"green": 2, "blue": 1}.
	for type in gem_table:
		var count: int = int(gem_table[type])
		for _i in count:
			var gem: Node3D = GEM_SCENE.instantiate() as Node3D
			if gem == null:
				continue
			# Set the gem type before adding to the tree so Gem._ready() reads it.
			gem.gem_type = type
			# Scatter gems around the death position
			var offset := Vector3(
				randf_range(-2.0, 2.0),
				0.5,
				randf_range(-2.0, 2.0)
			)
			add_child(gem)
			gem.global_position = position + offset
	
	var total: int = 0
	for type in gem_table:
		total += int(gem_table[type])
	print("Enemy destroyed at ", position, ", dropped ", total, " gems (", gem_table, ")")


func _on_encounter_started(encounter_id: int) -> void:
	print("Boss encounter started: ", encounter_id)
	# Could show boss health bar, play music, etc.


func _on_encounter_completed(encounter_id: int) -> void:
	print("Boss encounter completed: ", encounter_id)
	# Could award bonus rewards, play victory fanfare, etc.


# ── Tool editors toggle ────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F1:
				# Only toggle manually if not docked (auto-shown when docked)
				var docked: bool = false
				if station and station.has_method("is_ship_docked"):
					docked = station.is_ship_docked(ship)
				if not docked:
					_toggle_skill_tree()
				get_viewport().set_input_as_handled()
			KEY_F2:
				_toggle_spreadsheet()
				get_viewport().set_input_as_handled()
			KEY_ESCAPE:
				# Don't close editors if a dialog window is open inside them
				var window_open := false
				for c in get_tree().root.get_children(false):
					if c is Window and c.visible:
						window_open = true
						break
				if not window_open:
					if _skill_tree and _skill_tree.visible:
						_skill_tree.visible = false
						get_viewport().set_input_as_handled()
					elif _spreadsheet and _spreadsheet.visible:
						_spreadsheet.visible = false
						get_viewport().set_input_as_handled()


func _on_ship_gems_changed(inventory: Dictionary) -> void:
	# Sync ship inventory to PlayerSkills.
	# PlayerSkills maintains its own gem_inventory dict.
	if PlayerSkills.has_method("set_gem_inventory"):
		PlayerSkills.set_gem_inventory(inventory)
	else:
		# Fallback: just set total as green
		var total: int = 0
		for type in inventory:
			total += int(inventory.get(type, 0))
		PlayerSkills.set_gems(total)


func _on_speed_for_reticle(speed: float) -> void:
	# Mirror speed into the reticle's accuracy calculation. MAX_SPEED (35.0)
	# matches the constant inside HUD.gd — they're the ship's effective
	# top speed without overdrive.
	if hud and hud.has_method("set_accuracy_from_speed"):
		hud.set_accuracy_from_speed(speed, 35.0)


func _on_gems_changed(_inventory: Dictionary) -> void:
	if ship and hud:
		var cur: int = 0
		if ship.has_method("_get_total_gems"):
			cur = ship._get_total_gems()
		elif "gems" in ship:
			cur = int(ship.gems)
		var cap: int = int(ship._eff_gem_capacity) if "_eff_gem_capacity" in ship else 50
		hud.set_gem_capacity(cur, cap)


func _toggle_skill_tree(show: bool = false) -> void:
	if not _skill_tree:
		return
	if show:
		_skill_tree.visible = true
		_skill_tree.build_tree()
	else:
		_skill_tree.visible = not _skill_tree.visible
		if _skill_tree.visible:
			_skill_tree.build_tree()


func _toggle_spreadsheet() -> void:
	if not _spreadsheet:
		return
	_spreadsheet.visible = not _spreadsheet.visible


# ── Settings ───────────────────────────────────────────────────────────────────

func _toggle_settings() -> void:
	if not _settings:
		return
	_settings.visible = not _settings.visible
	get_tree().paused = _settings.visible
	if _settings.visible:
		_settings.mouse_filter = Control.MOUSE_FILTER_STOP
	else:
		_settings.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _on_settings_closed() -> void:
	_settings.visible = false
	get_tree().paused = false
	_settings.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _initial_dock() -> void:
	# Place the ship inside the hangar bay and dock it.
	# This runs deferred so all nodes are fully ready.
	if not is_instance_valid(ship) or not is_instance_valid(station):
		return
	if not station.has_method("_do_start_docking"):
		return
	# Position ship just outside the hangar doors, then trigger docking.
	# Use the first bay (the original "BayPivot" is exposed as _bays[0] for
	# backward compatibility, but get_bays() is the preferred API now that
	# the station has four hangars).
	var bay_pivot: Node3D = null
	if station.has_method("get_bays"):
		var bays: Array[Node3D] = station.get_bays()
		if bays.size() > 0:
			bay_pivot = bays[0]
	if bay_pivot == null:
		bay_pivot = station.get_node_or_null("HubPivot/BayPivot")
	if bay_pivot:
		var door_pos: Vector3 = bay_pivot.global_position + bay_pivot.global_transform.basis * Vector3(0, 0, -2.8)
		door_pos.y = ship.ground_height if "ground_height" in ship else 1.5
		ship.global_position = door_pos
		# Face the ship toward the hangar doors
		var door_dir: Vector3 = -bay_pivot.global_transform.basis.z
		ship.global_rotation.y = atan2(-door_dir.x, -door_dir.z)
	station._do_start_docking(ship, station.get_bay_data(bay_pivot) if station.has_method("get_bay_data") else null)


func _apply_graphics_settings() -> void:
	# ── WorldEnvironment ───────────────────────────────────────────────
	var env := $WorldEnvironment
	if env and env.environment:
		env.environment.fog_enabled = GlobalSettings.fog_enabled
		env.environment.tonemap_mode = GlobalSettings.tonemapping_mode as int
	
	# ── Directional shadows ────────────────────────────────────────────
	for sun in get_tree().get_nodes_in_group("sun"):
		if sun is DirectionalLight3D:
			sun.shadow_enabled = GlobalSettings.shadows_enabled
	
	# ── Pixelation shader ──────────────────────────────────────────────
	var res := _current_pixelation_resolution()
	if _pixelation_rect and _pixelation_rect.material is ShaderMaterial:
		var pix_mat := _pixelation_rect.material as ShaderMaterial
		pix_mat.set_shader_parameter("pixelate", GlobalSettings.pixelate_enabled)
		pix_mat.set_shader_parameter("resolution", res)
		pix_mat.set_shader_parameter("quantize_enabled", GlobalSettings.quantize_enabled)
		var pal_idx := clampi(GlobalSettings.quantize_palette_index, 0, GlobalSettings.PALETTES.size() - 1)
		var pal: PackedColorArray = GlobalSettings.PALETTES[pal_idx]
		pix_mat.set_shader_parameter("palette_size", pal.size())
		pix_mat.set_shader_parameter("palette", pal)
	
	# ── CRT shader ─────────────────────────────────────────────────────
	if _crt_rect:
		_crt_rect.visible = GlobalSettings.crt_enabled
		if GlobalSettings.crt_enabled and _crt_rect.material is ShaderMaterial:
			var crt_mat := _crt_rect.material as ShaderMaterial
			crt_mat.set_shader_parameter("resolution", res)


func _current_pixelation_resolution() -> Vector2:
	match GlobalSettings.pixelation_level:
		0:
			return Vector2(640, 360)
		1:
			return Vector2(800, 450)
		_:
			return Vector2(1152, 648)


# ── Planets ────────────────────────────────────────────────────────────────

func _spawn_planets() -> void:
	## Place a few planets at 1000-1500 distance from station.
	## Each planet gets a random color palette.
	const PLANET_SCENE = preload("res://scenes/Planet.tscn")
	var station_pos: Vector3 = station.global_position if is_instance_valid(station) else Vector3.ZERO
	
	var planet_configs: Array[Dictionary] = [
		{
			"angle": 0.0,
			"dist": 1200.0,
			"rim": Color(0.7, 0.5, 0.3),
			"anim": 0.20,
			"distort": 0.35,
			"asteroids": 35,
		},
		{
			"angle": PI * 0.7,
			"dist": 1400.0,
			"rim": Color(0.3, 0.6, 0.8),
			"anim": 0.30,
			"distort": 0.25,
			"asteroids": 25,
		},
		{
			"angle": PI * 1.4,
			"dist": 1100.0,
			"rim": Color(0.5, 0.2, 0.6),
			"anim": 0.15,
			"distort": 0.40,
			"asteroids": 20,
		},
	]
	
	for cfg in planet_configs:
		var planet = PLANET_SCENE.instantiate()
		var pos: Vector3 = station_pos + Vector3(
			cos(cfg.angle) * cfg.dist,
			0.0,
			sin(cfg.angle) * cfg.dist
		)
		pos.y = 0.0
		planet.position = pos
		
		# Customize the planet
		planet.rim_color = cfg.rim
		planet.animation_speed = cfg.anim
		planet.distortion_strength = cfg.distort
		planet.asteroid_count = cfg.asteroids
		
		add_child(planet)
		print("Spawned planet at ", pos)
