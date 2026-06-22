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
@onready var enemy_mgr: Node3D = $EnemyManager
@onready var spawn_gen: Node3D = $SpawnPointGenerator


var _was_docked := false

func _ready() -> void:
	randomize()
	# The AsteroidManager spawns all asteroids in its _ready().
	if asteroid_mgr:
		asteroid_mgr.asteroid_destroyed.connect(_on_asteroid_destroyed)
	_wire_signals()
	# Sync initial gems to PlayerSkills
	if ship.has_method("get_gems"):
		PlayerSkills.set_gems(ship.get_gems())
	
	# Setup enemy manager
	if enemy_mgr:
		enemy_mgr.enemy_destroyed.connect(_on_enemy_destroyed)
		enemy_mgr.encounter_started.connect(_on_encounter_started)
		enemy_mgr.encounter_completed.connect(_on_encounter_completed)


func _wire_signals() -> void:
	if ship.has_signal("fuel_changed"):
		ship.fuel_changed.connect(hud.set_fuel)
	if ship.has_signal("gems_changed"):
		ship.gems_changed.connect(hud.set_gems)
		ship.gems_changed.connect(_on_ship_gems_changed)
		ship.gems_changed.connect(_on_gems_changed)
	if ship.has_signal("speed_changed"):
		ship.speed_changed.connect(hud.set_speed)
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
	if not is_instance_valid(station) or not is_instance_valid(ship):
		return

	# Update the "distance to station" readout every frame.
	var d: float = ship.global_position.distance_to(station.global_position)
	var docked: bool = false
	if station.has_method("is_ship_docked"):
		docked = station.is_ship_docked(ship)
	if ship.has_signal("station_distance_changed"):
		ship.emit_signal("station_distance_changed", d, docked)
	
	# Auto-show skill tree on dock, auto-hide on undock
	if docked != _was_docked:
		_was_docked = docked
		if docked:
			_toggle_skill_tree(true)
			# Sync gems to PlayerSkills when docking
			if ship.has_method("get_gems"):
				PlayerSkills.set_gems(ship.get_gems())
		else:
			# When undocking, close skill tree and sync gems back
			if _skill_tree and _skill_tree.visible:
				_toggle_skill_tree(false)
			if ship.has_method("set_gems"):
				ship.set_gems(PlayerSkills.gems)


func _on_asteroid_destroyed(world_pos: Vector3, gem_count: int) -> void:
	# Could play a sound, spawn particles, etc.
	pass


func _on_enemy_destroyed(enemy: Node3D, position: Vector3, gems: int) -> void:
	# Award gems to player
	if ship and ship.has_method("add_gems"):
		ship.add_gems(gems)
	elif ship and "gems" in ship:
		ship.gems += gems
		if ship.has_signal("gems_changed"):
			ship.gems_changed.emit(ship.gems)
	
	# Play explosion sound
	# TODO: Add sound effect here
	print("Enemy destroyed at ", position, ", awarded ", gems, " gems")


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


func _on_ship_gems_changed(amount: int) -> void:
	PlayerSkills.set_gems(amount)


func _on_gems_changed(_amount: int) -> void:
	if ship and hud:
		var cur: int = int(ship.gems) if "gems" in ship else 0
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
