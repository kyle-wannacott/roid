@tool
extends CharacterBody3D
## Player-controlled spaceship — 2D-ish ground-level flight.
##
## The ship is locked to a single altitude (`ground_height`) and
## steers with W/S (thrust), A/D (yaw) and Q/E (roll). It mines
## asteroids with the laser, runs out of fuel, and gets reeled back
## to the station by a harpoon when stranded.

@export_group("Editor Preview")
@export var preview_fully_upgraded: bool = false: ## Toggle in editor to see fully upgraded ship
	set(value):
		preview_fully_upgraded = value
		if Engine.is_editor_hint():
			_update_editor_preview()

@export_group("Movement")
##
## Controls (project.godot):
##   W / Up     — forward thrust
##   S / Down   — reverse thrust
##   A / Left   — yaw left
##   D / Right  — yaw right
##   Q          — roll left
##   E          — roll right
##   1 / LMB    — fire mining laser (or fire harpoon when out of fuel)
##   Z          — fire harpoon (when out of fuel)
##   F          — fire flares (break homing missile lock-on)
##   MiddleBtn  — fire wing-pod missiles
##   RMB        — fire turret
##   R / Esc    — respawn at station
##
## Feel:
##   • Body pitches nose-down when accelerating, nose-up when reversing.
##   • Wings bank into turns.
##   • Beacon flashes green→yellow→red as health drops.
##   • Wing-tip lights form a diagetic fuel bar.
##   • State machine: FLYING / STRANDED / HARPOON_FLY / HARPOON_REEL / DOCKED.

signal fuel_changed(fuel: float, max_fuel: float)
signal gems_changed(inventory: Dictionary)
signal speed_changed(speed: float)
signal mining_state_changed(mining: bool, can_mine: bool)
signal station_distance_changed(distance: float, docked: bool)
signal health_changed(health: float, max_health: float)
signal state_changed(new_state: int)
signal shield_changed(ready: bool, cooldown: float)

enum State { FLYING, STRANDED, HARPOON_FLY, HARPOON_REEL, DOCKED }

@export_group("Movement")
@export var forward_thrust: float = 18.0
@export var reverse_thrust: float = 12.0
@export var yaw_speed: float = 1.6
@export var drag: float = 0.6
@export var max_speed: float = 30.0
## Y position the ship is locked to (no vertical flight).
@export var ground_height: float = 1.5

@export_group("Tilt Animation")
@export var thrust_pitch_max: float = 0.45
@export var reverse_pitch_max: float = 0.30
@export var bank_max: float = 0.65
@export var tilt_smooth: float = 6.0

@export_group("Fuel")
@export var fuel_max: float = 100.0
@export var fuel_per_thrust: float = 4.0
@export var fuel_per_mine: float = 6.0
@export var fuel_idle_drain: float = 0.25
@export var dock_refuel_rate: float = 30.0

@export_group("Mining")
@export var laser_range: float = 40.0
@export var laser_damage_per_sec: float = 35.0
@export var mining_cone_dot: float = 0.92
@export var asteroid_manager_path: NodePath

@export_group("Collection")
@export var gem_attract_radius: float = 7.0
@export var gem_pickup_radius: float = 1.4

@export_group("Health")
@export var max_health: float = 100.0
@export var asteroid_hit_damage: float = 25.0
@export var dock_heal_rate: float = 60.0

# ── Skill-powered state (overridden by PlayerSkills) ──────────────────────────
var _eff_max_health: float = 100.0
var _eff_fuel_max: float = 100.0
var _eff_forward_thrust: float = 30.0
var _eff_reverse_thrust: float = 18.0
var _eff_yaw_speed: float = 1.6
var _eff_max_speed: float = 55.0
var _eff_laser_range: float = 50.0
var _eff_laser_width: float = 0.22
var _eff_laser_chain_count: int = 0
var _eff_laser_damage_mult: float = 1.0
var _eff_mining_cone_dot: float = 0.92
var _eff_harpoon_reel_speed: float = 18.0
var _eff_fuel_per_thrust: float = 4.0
var _eff_fuel_per_mine: float = 6.0
var _eff_gem_heal: int = 0
var _eff_bonus_gems: int = 0
## Per-type gem inventory. Keys: green, blue, yellow, purple, red.
var gem_inventory: Dictionary = {"green": 0, "blue": 0, "yellow": 0, "purple": 0, "red": 0}
var _eff_solar_regen: float = 0.0
var _eff_turret_cool_rate: float = 0.35  # base cool rate (overridden by skills)
var _eff_nanobot_heal: float = 0.0
var _eff_nanobot_interval: float = 0.0
var _eff_shield_cooldown: float = 0.0
var _eff_afterburner_speed_pct: float = 0.0
var _eff_afterburner_fuel_cost: float = 0.0
var _eff_afterburner_efficiency_pct: float = 0.0
var _eff_flare_unlocked: bool = false  # When unlocked, ship can fire flares to break enemy missile lock-on
var _eff_laser_combat: bool = false  # When unlocked, mining laser also damages enemy ships
var _eff_spike_ram: bool = false	   # When unlocked, front spikes damage enemies on contact
var _eff_spike_ram_damage_pct: float = 0.0  # Speed fraction dealt as damage
var _eff_stunt_pilot: bool = false  # Faster barrel roll
var _eff_barrel_roll_speed_pct: float = 0.0
var _eff_bullet_time: bool = false  # Slow time during barrel roll
var _eff_bullet_time_scale: float = 1.0

# Shield, afterburner, nanobot runtime state
var _shield_ready: bool = false
var _shield_timer: float = 0.0
var _damage_cooldown: float = 0.0  # Brief invincibility after taking/absorbing damage
@export_group("Harpoon")
@export var harpoon_fly_duration: float = 0.6
@export var harpoon_reel_speed: float = 45.0
@export var harpoon_target_offset: Vector3 = Vector3(0, 0, 0)

@export_group("Docking")
## Speed below which the auto-dock will trigger. Flying through the
## dock zone at high speed won't grab the ship.
@export var auto_dock_speed: float = 4.0
## Push given to the ship on launch so it can clear the dock zone.
@export var launch_push: float = 16.0
## After the ship is refueled to 100 / healed to 100, or after a
## manual launch, auto-dock is disabled for this many seconds. This
## prevents the ship from being dragged straight back into the
## station the moment the player tries to fly away.
@export var dock_cooldown_duration: float = 2.5

var fuel: float = 100.0
var health: float = 100.0
## Total gem count across all types (virtual property for backward compat).
## When set, adds to Green.
var gems: int:
	get: return _get_total_gems()
	set(value):
		var diff: int = value - _get_total_gems()
		if diff > 0:
			_add_to_inventory("green", diff)
		elif diff < 0:
			_remove_from_inventory(-diff)
var _eff_gem_capacity: int = 50  # Base max gems before skills
var _eff_gem_pickup_bonus: float = 0.0
var _eff_gem_attract_bonus: float = 0.0
var _eff_magnet_speed_mult: float = 1.0
var mining_active: bool = false
var can_mine: bool = false
var current_target: Node3D = null
var state: State = State.FLYING
var harpoon_station: Node3D = null
# The specific bay pivot the harpoon is pulling us toward.  Refreshed each
# frame during the reel so the anchor tracks the rotating station.
var harpoon_bay: Node3D = null
var harpoon_anchor: Vector3 = Vector3.ZERO
var harpoon_progress: float = 0.0
var dock_cooldown: float = 0.0
var _afterburner_active: bool = false
var _nanobot_timer: float = 0.0

# Gem pickup pitch combo system
var _gem_combo_count: int = 0
var _gem_combo_timer: float = 0.0
var _gem_combo_timeout: float = 1.5  # Reset after 1.5 seconds of no gems
var _gem_pitch_base: float = 1.0
var _gem_pitch_max: float = 2.0
var _gem_pitch_increment: float = 0.08  # Each gem raises pitch by this

# Diagetic visual nodes (created in _ready)
var _shield_mesh: MeshInstance3D = null
var _shield_shader_mat: ShaderMaterial = null
@export var shield_color: Color = Color(0.3, 0.6, 1.0)
var _solar_panel_left: MeshInstance3D = null
var _solar_panel_right: MeshInstance3D = null
var _turret_mount: MeshInstance3D = null
var _missile_pod_left: Node3D = null
var _missile_pod_right: Node3D = null
var _missile_tubes_left: Array[MeshInstance3D] = []
var _missile_tubes_right: Array[MeshInstance3D] = []
var _last_rendered_max_capacity_left: int = -1
var _last_rendered_ammo_left: int = -1
var _last_rendered_max_capacity_right: int = -1
var _last_rendered_ammo_right: int = -1
var _missile_ammo_left: int = 0
var _missile_ammo_right: int = 0
var _eff_missile_max_per_pod: int = 1  # per pod, set by skills
var _missile_cooldown: float = 0.0
@export var missile_scene: PackedScene = preload("res://scenes/Missile.tscn")
@export var missile_fire_cooldown: float = 0.5
@export var missile_speed: float = 120.0
@export var missile_lifetime: float = 4.0
@export var bullet_scene: PackedScene = preload("res://scenes/Bullet.tscn")

# Turret heat system.  Continuous fire builds heat; the turret
# cools down when idle.  Above `overheat_threshold` the turret
# is locked out and the barrels glow red.  Skills reduce the
# cool‑down rate and the heat build‑up rate.  Hysteresis: once
# overheated, fire stays locked until heat drops below
# `re_enable_threshold` so the red glow is a real lockout, not
# a flicker at the threshold.
var _turret_heat: float = 0.0
var _turret_barrel_pick: int = 0
var _turret_locked_out: bool = false
@export var turret_overheat_threshold: float = 1.0
@export var turret_re_enable_threshold: float = 0.35
@export var turret_heat_per_shot: float = 0.09
@export var turret_cool_per_sec: float = 0.25
@export var turret_fire_rate: float = 0.10
var _turret_fire_remaining: float = 0.0
var _turret_barrel_mats: Array[StandardMaterial3D] = []
var _turret_barrels: Array[MeshInstance3D] = []

# Accuracy system - turret spread based on ship movement
var _current_accuracy: float = 1.0  # 1.0 = perfect, 0.0 = max spread
@export var accuracy_smoothing: float = 4.0
@export var max_turret_spread: float = 0.15  # ~8.6 degrees max spread
var _hud: CanvasLayer = null
var _turret_default_color: Color = Color(0.2, 0.2, 0.25, 1)
var _afterburner_particles: CPUParticles3D = null
var _thruster_particles_left: CPUParticles3D = null
var _thruster_particles_right: CPUParticles3D = null
var _afterburner_trail: MeshInstance3D = null
var _cargo_bay: MeshInstance3D = null
var _magnet_ring: Node3D = null
var _magnet_field: MeshInstance3D = null
var _spike_root: Node3D = null  # Spike Ram visual root

@onready var body_root: Node3D = $Body
@onready var wing_left: Node3D = $Body/WingLeft
@onready var wing_right: Node3D = $Body/WingRight
@onready var engine_glow_main: MeshInstance3D = $Body/EngineGlowMain
@onready var laser: MeshInstance3D = $Laser
@onready var laser_hit: OmniLight3D = $Laser/HitLight
@onready var collection_area: Area3D = $CollectionArea
@onready var start_transform: Transform3D

@onready var beacon: OmniLight3D = $Beacon/Light
@onready var beacon_mesh: MeshInstance3D = $Beacon/BeaconMesh
@onready var wing_bar_left: MeshInstance3D = $Body/WingLeft/WingBar
@onready var wing_bar_right: MeshInstance3D = $Body/WingRight/WingBar

@onready var harpoon_claw: Node3D = $Harpoon/Claw
@onready var harpoon_cable: MeshInstance3D = $Harpoon/Cable
@onready var asteroid_mgr: Node = get_node(asteroid_manager_path) if not asteroid_manager_path.is_empty() else null

# ── Editor-assignable upgrade nodes ──────────────────────────────
# Pre-create these in Ship.tscn to edit them directly in the editor.
# If a path is empty or the node doesn't exist, the ship creates them
# procedurally at runtime.
@export var editor_solar_panel_parent_left: NodePath = ""
@export var editor_solar_panel_parent_right: NodePath = ""
@export var editor_turret_root: NodePath = ""
@export var editor_cargo_bay: NodePath = ""
@export var editor_magnet_ring: NodePath = ""
@export var editor_missile_pod_left: NodePath = ""
@export var editor_missile_pod_right: NodePath = ""

var engine_glow_mat: StandardMaterial3D
var beacon_mat: StandardMaterial3D
var wing_bar_left_mat: StandardMaterial3D
var wing_bar_right_mat: StandardMaterial3D
var harpoon_cable_mat: StandardMaterial3D

var current_pitch_tilt: float = 0.0
var current_bank: float = 0.0
var _last_want_forward: float = 0.0
var _last_yaw_input: float = 0.0
var _last_chain_hit_index: int = -1  # Track when the chain already fired for this main hit
# Throttle timers for sound playback (use ticks_msec since SceneTreeTimer
# has no is_stopped() method)
var _afterburner_sound_until_ms: int = 0
var _laser_sound_until_ms: int = 0
var _turret_fire_until_ms: int = 0  # Throttle turret fire rate

# Docking / Launching Hangar Animation States
var is_docking_animation: bool = false
var is_launching_animation: bool = false
var dock_animation_time: float = 0.0
var dock_start_pos: Vector3 = Vector3.ZERO
var dock_start_rot_y: float = 0.0

# Barrel-roll state (Q/E one-shot 360° spins).
var _barrel_roll_dir: int = 0   # 0 = none, 1 = left, -1 = right
var _barrel_roll_progress: float = 0.0
@export var barrel_roll_duration: float = 0.9  # Base duration (slower), reduced by Stunt Pilot skill

# Editor preview state
var _preview_initialized: bool = false


func _update_editor_preview() -> void:
	"""Show/hide all upgrade visuals in editor based on preview_fully_upgraded toggle."""
	if not Engine.is_editor_hint():
		return
	
	if not _preview_initialized:
		# Ensure visuals are created on first toggle
		if not has_node("Body"):
			return
		_preview_initialized = true
	
	# Show/hide all upgrade visuals
	# Shield visual
	if _shield_mesh:
		_shield_mesh.visible = preview_fully_upgraded
	
	# Solar panels
	if _solar_panel_left:
		_solar_panel_left.visible = preview_fully_upgraded
	if _solar_panel_right:
		_solar_panel_right.visible = preview_fully_upgraded
	
	# Turret mount
	for node in get_tree().get_nodes_in_group("ship_turret_parts"):
		node.visible = preview_fully_upgraded
	
	# Missile pods - show with full ammo
	if preview_fully_upgraded:
		_eff_missile_max_per_pod = 6
		_missile_ammo_left = 6
		_missile_ammo_right = 6
		_show_missile_ammo(true, _missile_pod_left, _missile_tubes_left, 6)
		_show_missile_ammo(true, _missile_pod_right, _missile_tubes_right, 6)
	else:
		_eff_missile_max_per_pod = 0
		_missile_ammo_left = 0
		_missile_ammo_right = 0
		if _missile_pod_left:
			_missile_pod_left.visible = false
		if _missile_pod_right:
			_missile_pod_right.visible = false
	
	# Cargo bay
	if _cargo_bay:
		_cargo_bay.visible = preview_fully_upgraded
		if preview_fully_upgraded:
			_cargo_bay.scale = Vector3(1.4, 1.4, 1.4)
	
	# Tractor magnet
	if _magnet_ring:
		_magnet_ring.visible = preview_fully_upgraded
		if preview_fully_upgraded:
			_magnet_ring.scale = Vector3(1.35, 1.35, 1.35)
	
	# Shield glow on hull
	if _shield_shader_mat:
		var strength: float = 1.0 if preview_fully_upgraded else 0.0
		_shield_shader_mat.set_shader_parameter("shield_strength", strength)
	
	# Spike Ram
	if _spike_root:
		_spike_root.visible = preview_fully_upgraded


func _ready() -> void:
	add_to_group("ship")
	
	# Editor preview mode - skip game logic
	if Engine.is_editor_hint():
		_create_diagetic_visuals()
		_upgrade_ship_visuals()
		if preview_fully_upgraded:
			_update_editor_preview()
		return
	
	_apply_skill_stats()
	start_transform = global_transform
	# Listen for skill unlocks
	if PlayerSkills:
		PlayerSkills.skill_unlocked.connect(_on_skill_unlocked)
		PlayerSkills.skills_reset.connect(_on_skills_reset)

	engine_glow_mat = _ensure_material(engine_glow_main)
	beacon_mat = _ensure_material(beacon_mesh)
	wing_bar_left_mat = _ensure_material(wing_bar_left)
	wing_bar_right_mat = _ensure_material(wing_bar_right)
	harpoon_cable_mat = _ensure_material(harpoon_cable)

	_set_engine_glow(0.0)
	_update_beacon(1.0)
	_update_wing_bars(1.0)

	_create_diagetic_visuals()
	_upgrade_ship_visuals()
	_update_diagetic_visuals()  # Apply current skill states to new visuals

	# Find HUD for accuracy updates
	_hud = get_tree().get_first_node_in_group("hud")

	# Initial HUD gem capacity display
	gems_changed.emit(gem_inventory)


func _exit_tree() -> void:
	# Clean up particle systems and visual resources
	if _afterburner_particles and is_instance_valid(_afterburner_particles):
		_afterburner_particles.queue_free()
	if _thruster_particles_left and is_instance_valid(_thruster_particles_left):
		_thruster_particles_left.queue_free()
	if _thruster_particles_right and is_instance_valid(_thruster_particles_right):
		_thruster_particles_right.queue_free()
	if _shield_mesh and is_instance_valid(_shield_mesh):
		_shield_mesh.queue_free()
	if _magnet_ring and is_instance_valid(_magnet_ring):
		_magnet_ring.queue_free()


func _upgrade_ship_visuals() -> void:
	# 1) Sleek titanium hull material
	var hull_mat := StandardMaterial3D.new()
	hull_mat.albedo_color = Color(0.68, 0.72, 0.8, 1.0) # Sleek grey-blue titanium
	hull_mat.metallic = 0.85
	hull_mat.roughness = 0.22
	
	# Apply to main hull parts
	for node_name in ["Hull", "Nose", "WingLeft/WingMesh", "WingRight/WingMesh"]:
		var part := body_root.get_node_or_null(node_name) as MeshInstance3D
		if part != null:
			part.material_override = hull_mat

	# 2) Glowing energy accent material (cyan neon theme)
	var accent_mat := StandardMaterial3D.new()
	accent_mat.albedo_color = Color(0.1, 0.3, 0.5, 1.0)
	accent_mat.metallic = 0.6
	accent_mat.roughness = 0.3
	accent_mat.emission_enabled = true
	accent_mat.emission = Color(0.0, 0.8, 1.0, 1.0) # Electric cyan glow
	accent_mat.emission_energy_multiplier = 1.5
	
	for node_name in ["HullAccent", "NoseCone", "TopFin", "WingLeft/WingTipLight", "WingRight/WingTipLight"]:
		var part := body_root.get_node_or_null(node_name) as MeshInstance3D
		if part != null:
			part.material_override = accent_mat

	# 3) Cockpit - glossy gold-tinted reflective glass
	var cockpit := body_root.get_node_or_null("Cockpit") as MeshInstance3D
	if cockpit != null:
		var glass_mat := StandardMaterial3D.new()
		glass_mat.albedo_color = Color(0.1, 0.12, 0.18, 1.0)
		glass_mat.metallic = 0.95
		glass_mat.roughness = 0.05 # highly reflective
		glass_mat.emission_enabled = true
		glass_mat.emission = Color(0.05, 0.3, 0.6, 1.0) # internal blue instrumentation glow
		glass_mat.emission_energy_multiplier = 0.5
		cockpit.material_override = glass_mat

	# 4) Add thruster nozzle bells
	var nozzle_mat := StandardMaterial3D.new()
	nozzle_mat.albedo_color = Color(0.15, 0.15, 0.18, 1) # dark titanium
	nozzle_mat.metallic = 0.9
	nozzle_mat.roughness = 0.35
	
	# Main center thruster nozzle
	var nozzle_center := MeshInstance3D.new()
	var nozzle_center_mesh := CylinderMesh.new()
	nozzle_center_mesh.top_radius = 0.24
	nozzle_center_mesh.bottom_radius = 0.32
	nozzle_center_mesh.height = 0.35
	nozzle_center_mesh.radial_segments = 16
	nozzle_center.mesh = nozzle_center_mesh
	nozzle_center.material_override = nozzle_mat
	nozzle_center.position = Vector3(0, 0, 0.95)
	nozzle_center.rotation = Vector3(PI * 0.5, 0, 0)
	body_root.add_child(nozzle_center)
	
	# Left side thruster nozzle
	var nozzle_left := MeshInstance3D.new()
	var nozzle_left_mesh := CylinderMesh.new()
	nozzle_left_mesh.top_radius = 0.18
	nozzle_left_mesh.bottom_radius = 0.24
	nozzle_left_mesh.height = 0.25
	nozzle_left_mesh.radial_segments = 12
	nozzle_left.mesh = nozzle_left_mesh
	nozzle_left.material_override = nozzle_mat
	nozzle_left.position = Vector3(-0.5, 0, 0.98)
	nozzle_left.rotation = Vector3(PI * 0.5, 0, 0)
	body_root.add_child(nozzle_left)
	
	# Right side thruster nozzle
	var nozzle_right := MeshInstance3D.new()
	var nozzle_right_mesh := CylinderMesh.new()
	nozzle_right_mesh.top_radius = 0.18
	nozzle_right_mesh.bottom_radius = 0.24
	nozzle_right_mesh.height = 0.25
	nozzle_right_mesh.radial_segments = 12
	nozzle_right.mesh = nozzle_right_mesh
	nozzle_right.material_override = nozzle_mat
	nozzle_right.position = Vector3(0.5, 0, 0.98)
	nozzle_right.rotation = Vector3(PI * 0.5, 0, 0)
	body_root.add_child(nozzle_right)

	# 5) Add details like cooling intakes and copper power conduits
	# Left cooling intake
	var intake_left := MeshInstance3D.new()
	var intake_mesh := BoxMesh.new()
	intake_mesh.size = Vector3(0.25, 0.08, 0.4)
	intake_left.mesh = intake_mesh
	var intake_mat := StandardMaterial3D.new()
	intake_mat.albedo_color = Color(0.1, 0.1, 0.12, 1)
	intake_mat.metallic = 0.8
	intake_mat.roughness = 0.4
	intake_mat.emission_enabled = true
	intake_mat.emission = Color(0.8, 0.2, 0.1, 1) # glowing hot exhaust internal
	intake_mat.emission_energy_multiplier = 0.6
	intake_left.material_override = intake_mat
	intake_left.position = Vector3(-0.85, 0.08, -0.1)
	body_root.add_child(intake_left)

	# Right cooling intake
	var intake_right := MeshInstance3D.new()
	intake_right.mesh = intake_mesh
	intake_right.material_override = intake_mat
	intake_right.position = Vector3(0.85, 0.08, -0.1)
	body_root.add_child(intake_right)

	# Copper power conduits running along the top of the ship
	for i in [-1, 1]:
		var pipe := MeshInstance3D.new()
		var pipe_mesh := CylinderMesh.new()
		pipe_mesh.top_radius = 0.02
		pipe_mesh.bottom_radius = 0.02
		pipe_mesh.height = 1.4
		pipe.mesh = pipe_mesh
		var pipe_mat := StandardMaterial3D.new()
		pipe_mat.albedo_color = Color(0.85, 0.45, 0.2, 1) # shiny copper
		pipe_mat.metallic = 1.0
		pipe_mat.roughness = 0.25
		pipe.material_override = pipe_mat
		pipe.position = Vector3(0.25 * i, 0.25, 0.1)
		pipe.rotation = Vector3(PI * 0.5, 0, 0)
		body_root.add_child(pipe)

	laser.visible = false
	laser_hit.visible = false
	harpoon_claw.visible = false
	harpoon_cable.visible = false

	# Snap to the ground height on start.
	global_position.y = ground_height

	fuel_changed.emit(fuel, _eff_fuel_max)
	gems_changed.emit(gem_inventory)
	health_changed.emit(health, _eff_max_health)
	state_changed.emit(state)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	dock_cooldown = max(0.0, dock_cooldown - delta)

	match state:
		State.FLYING:
			_physics_flying(delta)
		State.STRANDED:
			_physics_stranded(delta)
		State.HARPOON_FLY:
			_physics_harpoon_fly(delta)
		State.HARPOON_REEL:
			_physics_harpoon_reel(delta)
		State.DOCKED:
			_physics_docked(delta)

	# --- Barrel roll update (runs in any state) ----------------
	if _barrel_roll_dir != 0:
		# Apply Stunt Pilot speed boost
		var eff_duration: float = barrel_roll_duration * (1.0 - _eff_barrel_roll_speed_pct / 100.0)
		eff_duration = maxf(eff_duration, 0.2)
		var spin: float = TAU * _barrel_roll_dir * delta / eff_duration
		rotate_object_local(Vector3.FORWARD, spin)
		_barrel_roll_progress += delta / eff_duration
		if _barrel_roll_progress >= 1.0:
			_barrel_roll_dir = 0
			_barrel_roll_progress = 0.0
			# Restore time scale after barrel roll ends
			if _eff_bullet_time:
				Engine.time_scale = 1.0
			# Play barrel roll sound when the roll completes
			SoundManager.play_by_id("sfx_barrel_roll")

	# Lock the ship to the ground altitude. Vertical movement is not
	# part of this game.
	global_position.y = ground_height

	_update_visual_tilts(_last_want_forward, _last_yaw_input, delta)
	_update_wing_bars(fuel / _eff_fuel_max)
	_update_beacon(health / _eff_max_health)


func _physics_flying(delta: float) -> void:
	var thrust_forward: float = Input.get_action_strength("thrust_forward")
	var thrust_back: float = Input.get_action_strength("thrust_back")
	var turn_left: float = Input.get_action_strength("turn_left")
	var turn_right: float = Input.get_action_strength("turn_right")
	var want_mine: bool = Input.is_action_pressed("mine")
	var want_reset: bool = Input.is_action_just_pressed("reset")

	if want_reset:
		respawn_at_station()
		return

	# --- Idle drain + solar regen --------------------------------
	fuel = max(0.0, fuel - fuel_idle_drain * delta)
	if _eff_solar_regen > 0.0:
		# Solar regen only when not thrusting (unless upgraded skill)
		var solar_while_moving: bool = PlayerSkills != null and PlayerSkills.is_unlocked("solar_while_moving")
		var any_thrust_input: bool = thrust_forward > 0.01 or thrust_back > 0.01
		if not any_thrust_input or solar_while_moving:
			fuel = min(_eff_fuel_max, fuel + _eff_solar_regen * delta)

	# --- Afterburner (Space key) ---------------------------------
	_afterburner_active = false
	if _eff_afterburner_speed_pct > 0.0 and Input.is_action_pressed("thrust_up"):
		var ab_fuel_cost: float = _eff_afterburner_fuel_cost if _eff_afterburner_fuel_cost > 0.0 else 8.0
		if _eff_afterburner_efficiency_pct > 0.0:
			ab_fuel_cost *= (1.0 - _eff_afterburner_efficiency_pct / 100.0)
		if fuel > ab_fuel_cost * delta:
			fuel -= ab_fuel_cost * delta
			_afterburner_active = true
			# Play afterburner sound (throttled to every 0.5s)
			var now_ms: int = Time.get_ticks_msec()
			if now_ms >= _afterburner_sound_until_ms:
				SoundManager.play_by_id("sfx_afterburner")
				_afterburner_sound_until_ms = now_ms + 500
	_update_afterburner_visuals()

	# --- Thrust (horizontal only) --------------------------------
	var want_forward: float = thrust_forward - thrust_back
	_last_want_forward = want_forward
	_last_yaw_input = turn_left - turn_right
	var any_thrust: bool = abs(want_forward) > 0.01

	if any_thrust:
		fuel = max(0.0, fuel - _eff_fuel_per_thrust * delta)
		if abs(want_forward) > 0.01:
			var f_dir: Vector3 = -transform.basis.z
			var mag: float = _eff_forward_thrust if want_forward > 0.0 else _eff_reverse_thrust
			velocity += f_dir * mag * want_forward * delta

	# --- Rotate (yaw) ------------------------------------------
	var yaw_input: float = turn_left - turn_right
	rotate(Vector3.UP, yaw_input * _eff_yaw_speed * delta)

	# --- Barrel roll (one-shot 360° on Q/E) ---------------------
	var roll_left_just: bool = Input.is_action_just_pressed("roll_left")
	var roll_right_just: bool = Input.is_action_just_pressed("roll_right")
	if _barrel_roll_dir == 0:
		if roll_left_just:
			_barrel_roll_dir = 1
			_barrel_roll_progress = 0.0
			# Bullet Time: slow game time during barrel roll
			if _eff_bullet_time:
				Engine.time_scale = _eff_bullet_time_scale
		elif roll_right_just:
			_barrel_roll_dir = -1
			_barrel_roll_progress = 0.0
			# Bullet Time: slow game time during barrel roll
			if _eff_bullet_time:
				Engine.time_scale = _eff_bullet_time_scale

	# --- Turret fire (right click held) ---------------------------
	# Unlimited ammo, but the turret overheats with continuous fire.
	# Overheated turrets glow red diagetically and lock out until
	# they cool BELOW the re‑enable threshold (hysteresis: the
	# lockout is a real, visible period, not a flicker).
	_turret_fire_remaining = max(0.0, _turret_fire_remaining - delta)
	var turret_unlocked_now: bool = PlayerSkills != null and PlayerSkills.is_unlocked("turret_unlock")
	var turret_cooling: float = turret_cool_per_sec
	if PlayerSkills != null and PlayerSkills.is_unlocked("turret_rapid_fire"):
		turret_cooling = _eff_turret_cool_rate
	# Cool down at full rate when idle; slower when overheated so
	# the red glow lingers visibly.
	if _turret_heat > 0.0:
		if _turret_heat >= turret_overheat_threshold:
			_turret_heat = max(0.0, _turret_heat - turret_cooling * 0.4 * delta)
		else:
			_turret_heat = max(0.0, _turret_heat - turret_cooling * delta)
	# Hysteresis: once overheated, stay locked out until heat
	# drops well below the threshold.
	if _turret_heat >= turret_overheat_threshold:
		_turret_locked_out = true
	elif _turret_heat <= turret_re_enable_threshold:
		_turret_locked_out = false
	# Update the diagetic barrel colour.
	_update_turret_barrel_color()
	# Fire while the right mouse button is held, when not locked
	# out, and the fire‑rate cooldown is ready.
	var firing: bool = Input.is_action_pressed("turret_fire")
	var can_fire: bool = (
		turret_unlocked_now
		and not _turret_locked_out
		and firing
		and _turret_fire_remaining <= 0.0
	)
	if can_fire:
		_fire_turret_shot()
		# Barrel recoil: push the barrel back then return it.
		var barrel_idx: int = _turret_barrel_pick % _turret_barrels.size()
		var barrel_node: MeshInstance3D = _turret_barrels[barrel_idx]
		if is_instance_valid(barrel_node):
			var recoil_tween := create_tween()
			recoil_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			# Push back along the barrel's local forward axis (+Y in local space).
			recoil_tween.tween_method(func(v: Vector3): barrel_node.position = v, \
				barrel_node.position, barrel_node.position + Vector3(0, 0, 0.06), 0.04)
			recoil_tween.tween_method(func(v: Vector3): barrel_node.position = v, \
				barrel_node.position + Vector3(0, 0, 0.06), barrel_node.position, 0.08)
		_turret_heat = min(1.0, _turret_heat + turret_heat_per_shot)
		_turret_fire_remaining = turret_fire_rate
		# Lockout check MUST run after the heat increase above,
		# otherwise heat always peaks at 1.0 after the shot then
		# cools just below 1.0 before the next frame's check.
		if _turret_heat >= turret_overheat_threshold:
			_turret_locked_out = true

	# --- Wing‑pod missiles (separate from turret) ---------------
	# Missiles are fired on the `missile_fire` action (G key) so the
	# player has both weapons without one stealing the other.
	_missile_cooldown = max(0.0, _missile_cooldown - delta)
	if Input.is_action_just_pressed("missile_fire") \
			and turret_unlocked_now \
			and _missile_cooldown <= 0.0:
		var any_missile: bool = false
		if _missile_ammo_left > 0 and _missile_pod_left:
			_fire_missile_from_pod(_missile_pod_left)
			_missile_ammo_left -= 1
			any_missile = true
		if _missile_ammo_right > 0 and _missile_pod_right:
			_fire_missile_from_pod(_missile_pod_right)
			_missile_ammo_right -= 1
			any_missile = true
		if any_missile:
			SoundManager.play_by_id("sfx_turret_fire")
			_missile_cooldown = missile_fire_cooldown

	# --- Flare countermeasures ---------------
	# Fires flares to break enemy homing missile lock-on.
	# Homing missiles not yet implemented — this is a placeholder.
	if Input.is_action_just_pressed("flare_fire") and _eff_flare_unlocked:
		SoundManager.play_by_id("sfx_turret_fire")  # TODO: replace with dedicated flare sound
		# Future: spawn flare particles, mark ship as invisible to homing missiles for a duration
		pass

	# --- Harpoon return (Z key) — available any time in FLYING state --------
	if Input.is_action_just_pressed("harpoon"):
		_fire_harpoon()
		return

	# Refill missile ammo when docked at the station.
	if state == State.DOCKED:
		_missile_ammo_left = _eff_missile_max_per_pod
		_missile_ammo_right = _eff_missile_max_per_pod

	var current_max_speed: float = _eff_max_speed
	if _afterburner_active:
		current_max_speed *= (1.0 + _eff_afterburner_speed_pct / 100.0)
	velocity = velocity.lerp(Vector3.ZERO, clamp(drag * delta, 0.0, 1.0))
	if velocity.length() > current_max_speed:
		velocity = velocity.normalized() * current_max_speed

	# Flatten velocity to the ground plane (no vertical motion).
	velocity.y = 0.0

	move_and_slide()

	# Proximity damage: if the ship flies too close to an asteroid,
	# the manager applies collision damage (no physics contact needed).
	if asteroid_mgr != null:
		var dmg: float = asteroid_mgr.check_ship_collision(
			global_position, 0.8, asteroid_hit_damage)
		if dmg > 0.0:
			take_damage(dmg)
	
	# Spike Ram: damage enemies on contact
	if _eff_spike_ram:
		var slide_count := get_slide_collision_count()
		for s in range(slide_count):
			var col := get_slide_collision(s)
			if col == null:
				continue
			var collider := col.get_collider() as Node
			if collider == null:
				continue
			# Check if we collided with an enemy
			if collider.is_in_group("enemies") or collider.is_in_group("enemy_hurtbox"):
				var enemy := collider
				# If we hit a hurtbox area, get the enemy parent
				if collider is Area3D:
					enemy = collider.get_parent()
				if enemy != null and enemy.has_method("take_damage"):
					var ram_damage := velocity.length() * _eff_spike_ram_damage_pct
					enemy.take_damage(ram_damage)
					SoundManager.play_by_id("sfx_ship_hit")

	_update_mining(want_mine, delta)
	_set_engine_glow(abs(want_forward))
	_attract_nearby_gems()
	
	# Update crosshair offset based on thrust
	if _hud and _hud.has_method("set_crosshair_thrust_offset"):
		_hud.set_crosshair_thrust_offset(want_forward)

	# Out of fuel → strand the ship.
	if fuel <= 0.0:
		fuel = 0.0
		if state != State.STRANDED:
			SoundManager.play_by_id("sfx_out_of_fuel")
		_set_state(State.STRANDED)

	# Auto-dock only when the ship has slowed down inside the station
	# zone. Flying through at speed won't grab it.
	_try_auto_dock()

	fuel_changed.emit(fuel, _eff_fuel_max)
	speed_changed.emit(velocity.length())
	can_mine = current_target != null and state == State.FLYING
	mining_state_changed.emit(mining_active and can_mine, can_mine)
	
	# Update accuracy based on speed
	_update_accuracy(delta)


func _physics_stranded(delta: float) -> void:
	velocity = velocity.lerp(Vector3.ZERO, clamp(drag * 2.0 * delta, 0.0, 1.0))
	velocity.y = 0.0
	if velocity.length() < 0.1:
		velocity = Vector3.ZERO
	move_and_slide()

	_last_want_forward = 0.0
	_last_yaw_input = 0.0
	_set_engine_glow(0.0)

	var want_harpoon: bool = Input.is_action_just_pressed("mine") \
		or Input.is_action_just_pressed("harpoon")
	if want_harpoon:
		_fire_harpoon()
		return

	if Input.is_action_just_pressed("reset"):
		respawn_at_station()
		return

	# If the ship happens to be inside the dock zone, dock it.
	_try_auto_dock()

	fuel_changed.emit(fuel, _eff_fuel_max)
	speed_changed.emit(velocity.length())
	can_mine = false
	mining_state_changed.emit(false, false)


func _physics_harpoon_fly(delta: float) -> void:
	harpoon_progress += delta / harpoon_fly_duration
	if harpoon_progress >= 1.0:
		harpoon_progress = 1.0
		_set_state(State.HARPOON_REEL)
		return

	var t: float = harpoon_progress
	var eased: float = 1.0 - (1.0 - t) * (1.0 - t)
	harpoon_claw.global_position = global_position.lerp(harpoon_anchor, eased)
	harpoon_claw.global_position.y = ground_height
	_update_cable(global_position, harpoon_claw.global_position)

	velocity = Vector3.ZERO
	move_and_slide()
	_last_want_forward = 0.0
	_last_yaw_input = 0.0
	_set_engine_glow(0.0)

	speed_changed.emit(0.0)
	can_mine = false
	mining_state_changed.emit(false, false)


func _physics_harpoon_reel(delta: float) -> void:
	# Dynamically refresh the anchor so the ship always aims at the door's
	# CURRENT world position (the station keeps spinning during the reel).
	if harpoon_bay != null and is_instance_valid(harpoon_bay):
		var local_offset := Vector3(0, 0, -2.8)
		harpoon_anchor = harpoon_bay.global_position + harpoon_bay.global_transform.basis * local_offset
		harpoon_anchor.y = ground_height

	var to_anchor: Vector3 = harpoon_anchor - global_position
	to_anchor.y = 0.0
	var dist: float = to_anchor.length()
	if dist < 1.5:
		velocity = Vector3.ZERO
		global_position = harpoon_anchor
		global_position.y = ground_height
		harpoon_claw.visible = false
		harpoon_claw.global_position = Vector3.ZERO
		harpoon_cable.visible = false
		harpoon_cable.global_position = Vector3.ZERO
		fuel = _eff_fuel_max
		health = _eff_max_health
		_shield_ready = _eff_shield_cooldown > 0.0
		_shield_timer = 0.0
		# Start the docking pull-in animation (ship is now at the hangar entrance)
		if harpoon_station != null and is_instance_valid(harpoon_station):
			if harpoon_station.has_method("_do_start_docking"):
				# Set state to DOCKED immediately so the ship stops running harpoon physics
				_set_state(State.DOCKED)
				# Pass the bay we're at so the station knows which hangar to dock into.
				# _do_start_docking accepts a BayData or a Node3D; we pass the pivot
				# and let the station resolve it.
				if "get_bay_data" in harpoon_station:
					var bay_data = harpoon_station.get_bay_data(harpoon_bay)
					harpoon_station._do_start_docking(self, bay_data)
				else:
					harpoon_station._do_start_docking(self)
			else:
				# Fallback: register directly
				if harpoon_station.has_method("register_docked_ship"):
					# Pass the bay pivot so the station can associate the docked ship
					# with the correct hangar for deploy.
					harpoon_station.register_docked_ship(self, harpoon_bay)
				_set_state(State.DOCKED)
		else:
			_set_state(State.DOCKED)
		return

	var dir: Vector3 = to_anchor / dist
	var step: float = min(_eff_harpoon_reel_speed * delta, dist)
	velocity = dir * _eff_harpoon_reel_speed
	velocity.y = 0.0
	global_position += dir * step
	global_position.y = ground_height
	move_and_slide()

	_update_cable(global_position, harpoon_anchor)
	harpoon_claw.global_position = harpoon_anchor
	harpoon_claw.global_position.y = ground_height

	_last_want_forward = 0.0
	_last_yaw_input = 0.0
	_set_engine_glow(0.0)

	speed_changed.emit(velocity.length())
	can_mine = false
	mining_state_changed.emit(false, false)


func _physics_docked(delta: float) -> void:
	velocity = Vector3.ZERO
	# Keep the ship pinned to the dock position set by the station.
	# The station handles positioning during the docking animation.

	# Refuel + heal while docked.
	var prev_fuel: float = fuel
	var prev_health: float = health
	fuel = min(_eff_fuel_max, fuel + dock_refuel_rate * delta)
	health = min(_eff_max_health, health + dock_heal_rate * delta)

	# Top-up cooldown (prevents instant re-dock after deploy)
	if (fuel >= _eff_fuel_max and prev_fuel < _eff_fuel_max) or (health >= _eff_max_health and prev_health < _eff_max_health):
		dock_cooldown = dock_cooldown_duration

	_last_want_forward = 0.0
	_last_yaw_input = 0.0
	_set_engine_glow(0.0)

	# Recharge shield while docked
	if _eff_shield_cooldown > 0.0 and not _shield_ready:
		_shield_timer = max(0.0, _shield_timer - delta)
		if _shield_timer <= 0.0:
			_shield_ready = true

	# Launch is now handled by the skill tree's Deploy button,
	# NOT by thrust inputs. This prevents accidental launch.
	if Input.is_action_just_pressed("reset"):
		respawn_at_station()
		return

	fuel_changed.emit(fuel, _eff_fuel_max)
	health_changed.emit(health, _eff_max_health)
	speed_changed.emit(0.0)
	can_mine = false
	mining_state_changed.emit(false, false)


func _set_state(new_state: State) -> void:
	if state == new_state:
		return
	state = new_state
	state_changed.emit(new_state)
	if new_state != State.HARPOON_FLY and new_state != State.HARPOON_REEL:
		harpoon_claw.visible = false
		harpoon_cable.visible = false
	# Rearm missiles whenever the ship reaches the station.
	if new_state == State.DOCKED:
		_missile_ammo_left = _eff_missile_max_per_pod
		_missile_ammo_right = _eff_missile_max_per_pod


# ---------------------------------------------------------------------
# Docking logic
# ---------------------------------------------------------------------

func _try_auto_dock() -> void:
	# Auto-docking is now handled by the station's hangar door trigger.
	# The ship must fly through the hangar doors to dock.
	# We keep this function as a stub so callers don't break.
	pass


func _can_launch() -> bool:
	# Don't allow launching while any editor modal window is open.
	# This prevents accidental launch while typing in the skill tree
	# edit dialog or icon picker.
	# Walk up to find the ToolsLayer under Main, then check for
	# visible Window children anywhere beneath it.
	var main := get_parent()
	if main and main.has_node("ToolsLayer"):
		var tools := main.get_node("ToolsLayer")
		if _has_visible_window(tools):
			return false
	return true

func _has_visible_window(from: Node) -> bool:
	if from is Window and from.visible and from != get_tree().root:
		return true
	for child in from.get_children():
		if _has_visible_window(child):
			return true
	return false


func _launch() -> void:
	# Push the ship forward (in its current facing) so it clears the
	# dock zone, then hand control back. The dock cooldown prevents
	# the auto-dock from immediately grabbing us again.
	var launch_dir: Vector3 = -transform.basis.z
	launch_dir.y = 0.0
	if launch_dir.length() < 0.01:
		launch_dir = Vector3(0, 0, -1)
	launch_dir = launch_dir.normalized()
	velocity = launch_dir * launch_push
	harpoon_station = null
	harpoon_bay = null
	dock_cooldown = dock_cooldown_duration
	_set_state(State.FLYING)


# ---------------------------------------------------------------------
# Hangar door docking (called by SpaceStation)
# ---------------------------------------------------------------------

## Called by the station when the docking animation finishes.
## The ship is already positioned inside the bay.
func dock_at_station(station: Node3D) -> void:
	harpoon_station = station
	harpoon_claw.visible = false
	harpoon_cable.visible = false
	velocity = Vector3.ZERO
	set_freezing(false)
	_set_state(State.DOCKED)


## Called by the station when the Deploy button is pressed.
## Launches the ship out of the hangar doors in the given direction.
func deploy_from_station(station: Node3D, direction: Vector3) -> void:
	if state != State.DOCKED:
		return
	# Tell the station we're leaving so it can reset its state
	if station.has_method("undock_ship"):
		station.undock_ship()
	var launch_dir := direction.normalized()
	launch_dir.y = 0.0
	if launch_dir.length() < 0.01:
		launch_dir = Vector3(0, 0, -1)
	velocity = launch_dir * launch_push
	harpoon_station = null
	harpoon_bay = null
	dock_cooldown = dock_cooldown_duration
	_set_state(State.FLYING)
	SoundManager.play_by_id("sfx_dock")


## Freeze/unfreeze the ship for docking animation.
func set_freezing(frozen: bool) -> void:
	set_physics_process(not frozen)
	if frozen:
		velocity = Vector3.ZERO


## Returns the numeric state for the station to check.
func get_state() -> int:
	return state as int


## Returns the current velocity (for station speed check).
func get_ship_velocity() -> Vector3:
	return velocity


# ---------------------------------------------------------------------
# Harpoon
# ---------------------------------------------------------------------

func _fire_harpoon() -> void:
	var stations := get_tree().get_nodes_in_group("station")
	if stations.is_empty():
		return
	# Play harpoon fire sound
	SoundManager.play_by_id("sfx_harpoon_fire")
	var best: Node3D = null
	var best_d: float = INF
	for s in stations:
		if not is_instance_valid(s):
			continue
		var d: float = global_position.distance_to(s.global_position)
		if d < best_d:
			best_d = d
			best = s
	if best == null:
		return
	harpoon_station = best
	# Pick the bay whose outward direction best matches the ship's
	# current position.  The four-bay design means we never have to fly
	# through the station to reach a door.  _physics_harpoon_reel re-queries
	# this anchor every frame so the reel tracks the rotating door.
	harpoon_bay = null
	if best.has_method("get_bay_for_ship"):
		harpoon_bay = best.get_bay_for_ship(global_position)
	if harpoon_bay == null:
		# Fallback to the legacy single BayPivot lookup
		harpoon_bay = best.get_node_or_null("HubPivot/BayPivot") as Node3D
	if harpoon_bay != null:
		# Position just outside the blast doors in the direction the door faces
		# (door faces local -Z in the bay's local space).  _physics_harpoon_reel
		# will recompute this every frame so the anchor follows the rotating
		# station during the reel.
		var local_offset := Vector3(0, 0, -2.8)
		harpoon_anchor = harpoon_bay.global_position + harpoon_bay.global_transform.basis * local_offset
	else:
		harpoon_anchor = best.global_position + harpoon_target_offset
	harpoon_anchor.y = ground_height
	harpoon_progress = 0.0
	harpoon_claw.visible = true
	harpoon_cable.visible = true
	harpoon_claw.global_position = global_position
	_set_state(State.HARPOON_FLY)


func _update_cable(from_world: Vector3, to_world: Vector3) -> void:
	var mid: Vector3 = (from_world + to_world) * 0.5
	var dist: float = max(0.01, from_world.distance_to(to_world))
	harpoon_cable.global_position = mid
	harpoon_cable.look_at(to_world, Vector3.UP)
	harpoon_cable.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	harpoon_cable.scale = Vector3(1.0, dist, 1.0)


# ---------------------------------------------------------------------
# Mining
# ---------------------------------------------------------------------

func _update_mining(want_mine: bool, delta: float) -> void:
	if state != State.FLYING or asteroid_mgr == null:
		mining_active = false
		laser.visible = false
		laser_hit.visible = false
		# Reset chain tracker so the next mining session can chain again
		_last_chain_hit_index = -1
		return

	# Find the closest asteroid in the forward cone via the manager.
	var forward: Vector3 = -global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var ast_idx: int = asteroid_mgr.find_in_cone(
		global_position, forward, _eff_mining_cone_dot, _eff_laser_range)
	
	# Combat mode: also check for enemies in the laser path
	var enemy_in_range: bool = false
	if _eff_laser_combat and ast_idx < 0:
		# Do a quick ray check for enemies
		var space_state := get_world_3d().direct_space_state
		if space_state:
			var ray_query := PhysicsRayQueryParameters3D.new()
			ray_query.from = global_position + (-global_transform.basis.z * 1.4)
			ray_query.to = ray_query.from + forward * _eff_laser_range
			ray_query.collision_mask = 4 | 8  # Enemy hurtbox layers (scene + base)
			ray_query.collide_with_areas = true  # Enemies use Area3D hurtboxes
			var result := space_state.intersect_ray(ray_query)
			if result:
				var hit_collider := result.get("collider") as Node
				# The hit collider is an Area3D hurtbox — the enemy is its parent
				if hit_collider != null:
					var enemy_parent := hit_collider.get_parent()
					enemy_in_range = enemy_parent != null and (
						enemy_parent.has_method("take_damage") or 
						hit_collider.has_method("take_damage"))
	
	# Also check for orbital asteroids in the laser path
	var orbital_in_range: bool = false
	var orbital_hit_pos: Vector3 = global_position + (-global_transform.basis.z * 1.4)
	orbital_hit_pos.y = max(0.3, ground_height - 0.3)
	var orbital_hit_end: Vector3 = orbital_hit_pos + forward * _eff_laser_range
	if ast_idx < 0 and not enemy_in_range:
		var space_st := get_world_3d().direct_space_state
		if space_st:
			var ray_q := PhysicsRayQueryParameters3D.new()
			ray_q.from = orbital_hit_pos
			ray_q.to = orbital_hit_end
			ray_q.collision_mask = 16
			var ray_res := space_st.intersect_ray(ray_q)
			if ray_res:
				orbital_in_range = true
				orbital_hit_pos = ray_res.position

	var can_fire: bool = want_mine and fuel > _eff_fuel_per_mine * delta and (ast_idx >= 0 or enemy_in_range or orbital_in_range)

	if not can_fire:
		mining_active = false
		laser.visible = false
		laser_hit.visible = false
		return

	mining_active = true
	laser.visible = true
	laser_hit.visible = true

	fuel = max(0.0, fuel - _eff_fuel_per_mine * delta)

	var laser_origin: Vector3 = global_position + (-global_transform.basis.z * 1.4)
	# Lower the laser so it doesn't fly over small asteroids
	laser_origin.y = max(0.3, ground_height - 0.3)

	# Fire the ray through the manager.
	# Apply laser damage multiplier (from laser_power / laser_power_2 skills).
	var dmg: float = laser_damage_per_sec * _eff_laser_damage_mult * delta
	var hit: Variant = asteroid_mgr.hit_asteroid(
		laser_origin, forward, _eff_laser_range, dmg)
	var hit_pos: Vector3 = laser_origin + (-global_transform.basis.z * _eff_laser_range)
	var hit_index: int = -1
	if typeof(hit) == TYPE_DICTIONARY:
		var hd: Dictionary = hit as Dictionary
		hit_pos = hd.get("position", hit_pos)
		hit_index = int(hd.get("index", -1))
	elif typeof(hit) == TYPE_VECTOR3:
		# Backwards compatibility if manager still returns Vector3
		hit_pos = hit as Vector3
	
	# Also check for orbital asteroids (children of Planet nodes)
	# These are StaticBody3D on collision layer 16
	if orbital_in_range:
		var space_st := get_world_3d().direct_space_state
		if space_st:
			var ray_q := PhysicsRayQueryParameters3D.new()
			ray_q.from = laser_origin
			ray_q.to = laser_origin + forward * _eff_laser_range
			ray_q.collision_mask = 16
			var ray_res := space_st.intersect_ray(ray_q)
			if ray_res:
				var hit_col := ray_res.get("collider") as Node
				if hit_col != null:
					var parent: Node = hit_col.get_parent()
					while parent != null and not (parent is Planet):
						parent = parent.get_parent()
					if parent is Planet:
						if parent.hit_orbital_asteroid(ray_res.position, dmg):
							hit_pos = ray_res.position
							hit_index = -2
							SoundManager.play_by_id("sfx_laser_hit_rock")

	laser_hit.global_position = hit_pos
	_laser_stretch(laser_origin, hit_pos)

	# Play laser beam sound (throttled to every 0.15s)
	var now_ms2: int = Time.get_ticks_msec()
	if now_ms2 >= _laser_sound_until_ms:
		SoundManager.play_by_id("sfx_laser_beam")
		_laser_sound_until_ms = now_ms2 + 150

	# Spawn rock chips at the hit point.
	if asteroid_mgr != null and hit_index >= 0:
		asteroid_mgr.spawn_chips(hit_pos)
		
		# Spawn damage number
		if DamageNumberManager.instance:
			DamageNumberManager.instance.spawn_damage(dmg, hit_pos)
		# Show hit indicator on crosshair
		if _hud and _hud.has_method("show_hit_indicator"):
			_hud.show_hit_indicator()
		# Play laser hit rock sound (throttled)
		SoundManager.play_by_id("sfx_laser_hit_rock")

	# Chain laser: if we hit an asteroid and have chain levels, fire
	# additional beams to nearby asteroids in sequence.
	# Only fire the chain when the main hit target changes — this
	# ensures the chain fires ONCE per target (like Diablo 2's chain
	# lightning) instead of forking to multiple asteroids over time
	# as each chain target gets destroyed.
	if _eff_laser_chain_count > 0 and hit_index >= 0 and hit_index != _last_chain_hit_index:
		_last_chain_hit_index = hit_index
		_chain_laser(laser_origin, hit_pos, _eff_laser_chain_count, [hit_index])
	
	# Mining Laser Combat: also damage enemy ships in the laser path
	if _eff_laser_combat:
		var space_state := get_world_3d().direct_space_state
		if space_state:
			var ray_query := PhysicsRayQueryParameters3D.new()
			ray_query.from = laser_origin
			ray_query.to = laser_origin + forward * _eff_laser_range
			ray_query.collision_mask = 4 | 8  # Enemy hurtbox layers (scene + base)
			ray_query.collide_with_areas = true  # Enemies use Area3D hurtboxes
			var result := space_state.intersect_ray(ray_query)
			if result:
				var hit_collider := result.get("collider") as Node
				if hit_collider != null:
					# The ray hits the hurtbox Area3D — get the enemy parent that has take_damage
					var enemy: Node = hit_collider.get_parent()
					if enemy != null and enemy.has_method("take_damage"):
						var enemy_dmg = dmg * 0.5  # Half damage to enemies
						enemy.take_damage(enemy_dmg)
						# Show hit indicator on crosshair
						if _hud and _hud.has_method("show_hit_indicator"):
							_hud.show_hit_indicator()
						# Play hit sound
						SoundManager.play_by_id("sfx_laser_hit_rock")


func _laser_stretch(from_world: Vector3, to_world: Vector3) -> void:
	var mid: Vector3 = (from_world + to_world) * 0.5
	var dist: float = max(0.01, from_world.distance_to(to_world))
	laser.global_position = mid
	laser.look_at(to_world, Vector3.UP)
	laser.scale = Vector3(_eff_laser_width, _eff_laser_width, dist)

## Find the nearest other asteroid in range, draw a thin chain beam
## to it, and apply damage. Used by the Mining Chain skill.
## Damage is 50% weaker per depth level so chain 2 = 25% of normal,
## chain 3 = 12.5% of normal, etc. This means chained asteroids
## take progressively longer to destroy, matching the main laser's
## time-to-kill so the chain doesn't insta-destroy them.
## Works like Diablo 2's chain lightning: the chain only chains to
## asteroids NOT in the visited list, so it never bounces back to
## any previously-hit asteroid (including the initial target).
func _chain_laser(from_world: Vector3, last_hit: Vector3, remaining: int, visited: Array = [], depth: int = 1) -> void:
	if remaining <= 0 or asteroid_mgr == null:
		return
	# Damage is 50% weaker per depth level
	var chain_damage_mult: float = pow(0.5, depth)
	# Use the AsteroidManager to find the nearest live asteroid,
	# EXCLUDING all previously-visited asteroids (Diablo 2 behavior).
	var chain_range: float = 40.0
	var nearest_idx: int = -1
	if asteroid_mgr.has_method("get_nearest_to_excluding_many"):
		nearest_idx = asteroid_mgr.get_nearest_to_excluding_many(last_hit, chain_range, visited)
	elif asteroid_mgr.has_method("get_nearest_to_excluding"):
		# Fallback: only exclude the immediate previous
		var prev := -1
		if not visited.is_empty():
			prev = visited[visited.size() - 1]
		nearest_idx = asteroid_mgr.get_nearest_to_excluding(last_hit, chain_range, prev)
	if nearest_idx < 0:
		return  # No more asteroids in range to chain to
	var nearest_pos: Vector3 = asteroid_mgr.get_asteroid_pos(nearest_idx)
	# Apply damage to the chained asteroid
	# Start the ray slightly outside the asteroid so the ray-sphere
	# intersection works (otherwise origin is inside the sphere).
	var radius: float = asteroid_mgr.get_asteroid_radius(nearest_idx) if asteroid_mgr.has_method("get_asteroid_radius") else 1.0
	var ray_dir := (nearest_pos - last_hit).normalized()
	if ray_dir.length_squared() < 0.001:
		ray_dir = Vector3.UP
	var ray_origin: Vector3 = nearest_pos - ray_dir * (radius + 0.1)
	asteroid_mgr.hit_asteroid(ray_origin, ray_dir, 1.0, laser_damage_per_sec * chain_damage_mult)
	asteroid_mgr.spawn_chips(nearest_pos)
	# Visual chain beam: persistent cylinder mesh that fades out
	_spawn_chain_beam(last_hit, nearest_pos)
	# Add this asteroid to the visited list so the chain doesn't bounce back
	var new_visited: Array = visited.duplicate()
	new_visited.append(nearest_idx)
	# Recurse for multi-chain, excluding all previously-visited asteroids
	_chain_laser(from_world, nearest_pos, remaining - 1, new_visited, depth + 1)

func _spawn_chain_beam(from: Vector3, to: Vector3) -> void:
	# Build a thin cylinder mesh between the two points
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	# Six-sided thin cylinder
	var segs := 6
	var radius := 0.08
	var forward := (to - from).normalized()
	var up := Vector3.UP
	if abs(forward.dot(up)) > 0.95:
		up = Vector3.RIGHT
	var right := forward.cross(up).normalized()
	var u := right.cross(forward).normalized()
	var points_top: Array[Vector3] = []
	var points_bot: Array[Vector3] = []
	for i in segs:
		var a := float(i) / float(segs) * TAU
		var offset := (right * cos(a) + u * sin(a)) * radius
		points_top.append(from + offset)
		points_bot.append(to + offset)
	for i in segs:
		var i2 := (i + 1) % segs
		im.surface_add_vertex(points_top[i])
		im.surface_add_vertex(points_top[i2])
		im.surface_add_vertex(points_bot[i2])
		im.surface_add_vertex(points_top[i])
		im.surface_add_vertex(points_bot[i2])
		im.surface_add_vertex(points_bot[i])
	im.surface_end()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = 0  # unshaded
	mat.transparency = 1
	mat.albedo_color = Color(1.0, 0.7, 0.2, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.6, 0.1, 1.0)
	mat.emission_energy_multiplier = 4.0
	# Add the mesh to the tree FIRST, then set its transform.
	# Setting global_position before add_child triggers the
	# "!is_inside_tree()" error in Node3D.get_global_transform.
	var mi := MeshInstance3D.new()
	mi.mesh = im
	mi.material_override = mat
	mi.top_level = true  # ignore parent transform; use world coords directly
	get_tree().current_scene.add_child(mi)
	mi.global_position = Vector3.ZERO
	# Auto-cleanup after a brief flash (use instance_id to avoid freed capture)
	var mi_id := mi.get_instance_id()
	var t := get_tree().create_timer(0.25)
	t.timeout.connect(func():
		var node := instance_from_id(mi_id)
		if node != null:
			node.queue_free()
	)


# ---------------------------------------------------------------------
# Visual tilts + engine glow
# ---------------------------------------------------------------------

func _update_visual_tilts(want_forward: float, yaw_input: float, delta: float) -> void:
	var target_pitch: float = 0.0
	if want_forward > 0.01:
		target_pitch = thrust_pitch_max * want_forward
	elif want_forward < -0.01:
		target_pitch = -reverse_pitch_max * abs(want_forward)
	current_pitch_tilt = lerp(current_pitch_tilt, target_pitch, clamp(tilt_smooth * delta, 0.0, 1.0))
	body_root.rotation.x = current_pitch_tilt

	var target_bank: float = -yaw_input * bank_max
	current_bank = lerp(current_bank, target_bank, clamp(tilt_smooth * delta, 0.0, 1.0))
	wing_left.rotation.z = -current_bank
	wing_right.rotation.z = current_bank


func _set_engine_glow(forward: float) -> void:
	var main_e: float = 1.0 + forward * 4.0
	# Afterburner adds a strong boost and changes the engine color
	if _afterburner_active:
		main_e *= 2.5
		# Afterburner: bright orange-white hot exhaust
		if engine_glow_mat:
			engine_glow_mat.emission = Color(1.0, 0.6, 0.2)  # Hot orange
		if wing_bar_left_mat:
			wing_bar_left_mat.emission = Color(0.4, 0.7, 1.0)  # Blue accent
		if wing_bar_right_mat:
			wing_bar_right_mat.emission = Color(0.4, 0.7, 1.0)  # Blue accent
	else:
		if engine_glow_mat:
			engine_glow_mat.emission = Color(0.4, 0.7, 1, 1)  # Normal blue
	if engine_glow_mat:
		engine_glow_mat.emission_energy_multiplier = main_e

	# Drive the CPUParticles3D thruster plumes based on thrust and afterburner.
	# Scale emission amount so idling gives a visible flicker and
	# full thrust / afterburner gives a fat roaring plume.
	var thrust_factor: float = clamp(forward, 0.0, 1.0)
	var ab_factor: float = 2.8 if _afterburner_active else 1.0

	# Per-emitter base settings so side thrusters stay proportionally smaller
	# than the main center thruster (matches the initial setup in _create_diagetic_visuals).
	var emitter_bases = [
		{"emitter": _afterburner_particles, "min_amount": 18.0, "max_amount": 45.0, "min_vel": 4.0, "max_vel": 7.0},
		{"emitter": _thruster_particles_left, "min_amount": 10.0, "max_amount": 25.0, "min_vel": 3.5, "max_vel": 6.0},
		{"emitter": _thruster_particles_right, "min_amount": 10.0, "max_amount": 25.0, "min_vel": 3.5, "max_vel": 6.0},
	]
	for eb in emitter_bases:
		var emitter = eb["emitter"] as CPUParticles3D
		if emitter == null:
			continue
		# Always emitting – just scale amount up/down.
		emitter.amount = int(lerp(eb["min_amount"], eb["max_amount"], thrust_factor) * ab_factor)
		emitter.initial_velocity_min = lerp(eb["min_vel"], eb["max_vel"], thrust_factor) * ab_factor
		emitter.initial_velocity_max = lerp(eb["min_vel"] + 1.0, eb["max_vel"] + 2.0, thrust_factor) * ab_factor
		emitter.spread = lerp(4.0, 10.0, thrust_factor)
		# The particle color_ramp is set up in _create_diagetic_visuals() with
		# a full gradient (blue→orange→red→grey→black). We no longer overwrite
		# it here so the full multi-color gradient is visible at runtime.


# ---------------------------------------------------------------------
# Health beacon
# ---------------------------------------------------------------------

func _update_beacon(health_pct: float) -> void:
	var color: Color
	if health_pct > 0.6:
		color = Color(0.2, 1.0, 0.3)
	elif health_pct > 0.3:
		color = Color(1.0, 0.85, 0.2)
	else:
		color = Color(1.0, 0.2, 0.2)
	beacon.light_color = color
	if beacon_mat:
		beacon_mat.albedo_color = color
		beacon_mat.emission = color
	var pulse: float = 1.0
	if health_pct <= 0.3:
		pulse = 1.0 + 0.6 * sin(Time.get_ticks_msec() * 0.012)
	beacon.light_energy = 2.5 * pulse
	if beacon_mat:
		beacon_mat.emission_energy_multiplier = 3.0 * pulse


# ---------------------------------------------------------------------
# Diagetic fuel bar
# ---------------------------------------------------------------------

func _update_wing_bars(fuel_pct: float) -> void:
	var color: Color
	if fuel_pct > 0.5:
		color = Color(0.2, 1.0, 0.4)
	elif fuel_pct > 0.25:
		color = Color(1.0, 0.9, 0.2)
	else:
		color = Color(1.0, 0.3, 0.2)
	var width_scale: float = clamp(fuel_pct, 0.0, 1.0)
	for mat in [wing_bar_left_mat, wing_bar_right_mat]:
		if mat:
			mat.albedo_color = color
			mat.emission = color
			mat.emission_energy_multiplier = 2.5
	if wing_bar_left:
		wing_bar_left.scale = Vector3(1.0, 1.0, max(0.001, width_scale))
	if wing_bar_right:
		wing_bar_right.scale = Vector3(1.0, 1.0, max(0.001, width_scale))


# ---------------------------------------------------------------------
# Gem collection
# ---------------------------------------------------------------------

func _attract_nearby_gems() -> void:
	for gem in get_tree().get_nodes_in_group("gems"):
		if not is_instance_valid(gem):
			continue
		var d: float = global_position.distance_to(gem.global_position)
		if d <= gem_attract_radius + _eff_gem_attract_bonus:
			# Pass the current magnet speed multiplier so the gem
			# travels at the upgraded speed.
			if "home_speed_mult" in gem:
				gem.home_speed_mult = _eff_magnet_speed_mult
			gem.attract_to(self)


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	for gem in get_tree().get_nodes_in_group("gems"):
		if not is_instance_valid(gem):
			continue
		if not (gem.get("being_attracted") as bool):
			continue
		if global_position.distance_to(gem.global_position) < gem_pickup_radius + _eff_gem_pickup_bonus:
			# Only collect the gem if we have room in the cargo hold.
			# Gems stay orbiting the ship until capacity frees up.
			if _get_total_gems() < _eff_gem_capacity:
				# Read the gem's type before collecting (the gem may be freed during collect).
				var collected_type: String = "green"
				if "gem_type" in gem:
					collected_type = gem.gem_type
				gem.collect()
				
				# Play gem collect sound with increasing pitch for combo
				_gem_combo_count += 1
				_gem_combo_timer = _gem_combo_timeout
				var pitch = _gem_pitch_base + (_gem_combo_count - 1) * _gem_pitch_increment
				pitch = min(pitch, _gem_pitch_max)
				SoundManager.play_by_id_with_pitch("sfx_gem_collect", pitch)
				
				_add_to_inventory(collected_type, 1)
				gems_changed.emit(gem_inventory)
				# Gem heal from nanobot_gem_heal skill (only when actually collected)
				if _eff_gem_heal > 0 and health < _eff_max_health:
					health = min(_eff_max_health, health + _eff_gem_heal)
					health_changed.emit(health, _eff_max_health)
	
	# Gem combo pitch timer - reset combo if no gems collected recently
	if _gem_combo_timer > 0.0:
		_gem_combo_timer -= delta
		if _gem_combo_timer <= 0.0:
			_gem_combo_count = 0
	
	# Nanobot auto-repair
	if _eff_nanobot_heal > 0.0 and _eff_nanobot_interval > 0.0:
		_nanobot_timer += delta
		if _nanobot_timer >= _eff_nanobot_interval:
			_nanobot_timer = 0.0
			if health < _eff_max_health:
				health = min(_eff_max_health, health + _eff_nanobot_heal)
				health_changed.emit(health, _eff_max_health)

	# Damage cooldown (brief invincibility after taking damage)
	if _damage_cooldown > 0.0:
		_damage_cooldown = max(0.0, _damage_cooldown - delta)
	
	# Update diagetic visuals (shield alpha, etc.) each frame
	_update_diagetic_visuals()
	
	# Shield recharge timer (only when not docked)
	if _eff_shield_cooldown > 0.0 and not _shield_ready and state != State.DOCKED:
		_shield_timer += delta
		if _shield_timer >= _eff_shield_cooldown:
			_shield_timer = _eff_shield_cooldown
			_shield_ready = true
			# Play shield recharge sound
			SoundManager.play_by_id("sfx_shield_recharge")
	
	# Emit shield state
	if _eff_shield_cooldown > 0.0:
		var cd: float = max(0.0, _eff_shield_cooldown - _shield_timer) if not _shield_ready else 0.0
		shield_changed.emit(_shield_ready, cd)


func take_damage(amount: float) -> void:
	if state == State.DOCKED or state == State.HARPOON_FLY or state == State.HARPOON_REEL:
		return
	# Damage cooldown prevents multi-hit destruction (e.g. crashing
	# into a cluster of asteroids in the same frame).
	if _damage_cooldown > 0.0:
		return
	# Shield absorbs the hit
	if _shield_ready and _eff_shield_cooldown > 0.0:
		_shield_ready = false
		_shield_timer = 0.0
		_damage_cooldown = 0.4
		_flash_shield_break()
		# Shield blocks all damage — just emit a visual cue
		health_changed.emit(health, _eff_max_health)
		return
	# Play ship-hit sound (only on actual damage, not shield absorb)
	SoundManager.play_by_id("sfx_ship_hit")
	health = max(0.0, health - amount)
	_damage_cooldown = 0.4
	health_changed.emit(health, _eff_max_health)
	if health <= 0.0:
		_on_ship_destroyed()

## Briefly flash the shield bright white when it absorbs a hit, then
## let _update_diagetic_visuals() fade it down to the recharging state.
func _flash_shield_break() -> void:
	if _shield_mesh == null or _shield_mesh.material_override == null:
		return
	var mat: StandardMaterial3D = _shield_mesh.material_override
	mat.albedo_color = Color(1.0, 1.0, 1.0, 0.7)
	mat.emission = Color(1.0, 1.0, 1.0, 1.0)
	mat.emission_energy_multiplier = 5.0


## Spawn a missile from the given wing pod, flying in the ship's
## forward direction.
func _fire_missile_from_pod(pod: Node3D) -> void:
	if missile_scene == null:
		return
	var missile: Node3D = missile_scene.instantiate() as Node3D
	if missile == null:
		return
	# Start the missile at the pod's world position, facing the
	# ship's forward direction.
	get_tree().current_scene.add_child(missile)
	missile.global_position = pod.global_position
	# Rotate the missile to face the ship's forward direction.
	missile.global_rotation = global_rotation
	# Set the owner so the missile knows which way to fly.
	if "shooter" in missile:
		missile.shooter = self
	# Set the missile's flight parameters.
	if missile.has_method("set_flight_params"):
		missile.set_flight_params(missile_speed, missile_lifetime)
	# Force cache invalidation so the visual rebuilds with one fewer missile.
	_last_rendered_ammo_left = -1
	_last_rendered_ammo_right = -1


## Update accuracy based on ship movement speed.
## Accuracy decreases as speed increases, affecting turret spread.
func _update_accuracy(delta: float) -> void:
	# Calculate target accuracy based on speed percentage
	var speed_pct: float = clamp(velocity.length() / max(1.0, _eff_max_speed), 0.0, 1.0)
	var target_accuracy: float = 1.0 - (speed_pct * 0.7)  # Max 70% inaccuracy at full speed
	
	# Smooth interpolation
	_current_accuracy = lerp(_current_accuracy, target_accuracy, accuracy_smoothing * delta)
	
	# Update HUD crosshair if available
	if _hud and _hud.has_method("set_accuracy_from_speed"):
		_hud.set_accuracy_from_speed(velocity.length(), _eff_max_speed)


## Fire one shot from the turret.  Spawns a bullet from each barrel
## (alternating left/right) flying forward in the ship's facing
## direction.  Also plays the muzzle flash and sound.
## When Multi‑Shot is unlocked, fires an additional projectile
## with a slight angular spread.
## Accuracy affects spread: lower accuracy = wider bullet spread.
func _fire_turret_shot() -> void:
	_flash_turret_muzzle()
	SoundManager.play_by_id("sfx_turret_fire")
	if bullet_scene == null:
		return
	var barrels: Array[MeshInstance3D] = []
	for node in get_tree().get_nodes_in_group("ship_turret_parts"):
		if node is MeshInstance3D and node.mesh is CylinderMesh and node.mesh.height < 1.0:
			barrels.append(node)
	if barrels.is_empty():
		return
	
	# Determine projectile count and spread.
	# Without multi‑shot: fires 1 bullet alternating barrels.
	# With multi‑shot:     fires 4 bullets in a spread pattern from both barrels.
	# Spread is affected by accuracy: lower accuracy = wider spread.
	var multi_shot: bool = PlayerSkills != null and PlayerSkills.is_unlocked("multi_shot")
	var count: int = 4 if multi_shot else 1
	var base_spread: float = 0.06  # ~3.4 degrees base spread
	# Apply accuracy: at perfect accuracy (1.0) use base spread, at 0.0 use max_turret_spread
	var spread_rad: float = lerp(max_turret_spread, base_spread, _current_accuracy)
	
	for i in count:
		# Pick a barrel — alternate between the two so fire looks even.
		var idx: int = _turret_barrel_pick % barrels.size()
		var barrel: MeshInstance3D = barrels[idx]
		_turret_barrel_pick += 1
		
		var b: Bullet = bullet_scene.instantiate() as Bullet
		if b == null:
			continue
		# Position the bullet at the barrel tip in world space.
		var tip: Vector3 = barrel.global_position + (-barrel.global_transform.basis.y * 0.3)
		get_tree().current_scene.add_child(b)
		b.global_position = tip
		# Orient the bullet to face the ship's forward direction.
		b.global_rotation = global_rotation
		
		# Apply spread: accuracy affects the random deviation
		if multi_shot:
			# Multi-shot: symmetric fan pattern with accuracy-based spread
			var offset: float = 0.0
			match i:
				0:  offset = -spread_rad * 1.5
				1:  offset = -spread_rad * 0.5
				2:  offset =  spread_rad * 0.5
				3:  offset =  spread_rad * 1.5
			b.rotate_object_local(Vector3.UP, offset)
		else:
			# Single shot: add random spread based on accuracy
			var random_spread: float = randf_range(-spread_rad, spread_rad)
			b.rotate_object_local(Vector3.UP, random_spread)
		
		# ── Apply skill-driven properties to the bullet ──────────────
		if PlayerSkills:
			# Heavy Rounds: bigger bullets
			if PlayerSkills.is_unlocked("turret_big_bullets"):
				b.bullet_scale = 1.5
			# Armor-Piercing Rounds: pierce through enemies
			if PlayerSkills.is_unlocked("turret_projectile_pierce"):
				b.pierce_count = 1
			# Ricochet Rounds: bounce to nearby enemy
			if PlayerSkills.is_unlocked("ricochet_rounds"):
				b.ricochet_chance = 0.3
			# Chain Lightning: chain to nearby enemies
			if PlayerSkills.is_unlocked("chain_lightning"):
				b.chain_chance = 0.2
				b.chain_count = 2
			# Frost Shot: slow enemies on hit
			if PlayerSkills.is_unlocked("frost_shot"):
				b.slow_chance = 0.25
				b.slow_duration = 2.0
				b.slow_factor = 0.5
			# Critical Strike: chance for extra damage
			if PlayerSkills.is_unlocked("critical_chance"):
				b.crit_chance = 0.1
			# Critical Power: bonus damage on crits
			if PlayerSkills.is_unlocked("critical_multiplier"):
				b.crit_damage_mult = 0.25
			# Roll for critical hit
			if b.crit_chance > 0.0 and randf() < b.crit_chance:
				b._is_critical = true
		
		# Apply bullet scale to the transform
		if b.bullet_scale != 1.0:
			b.scale = Vector3(b.bullet_scale, b.bullet_scale, b.bullet_scale)
		
		# High-Velocity Rounds: faster projectiles
		var proj_speed: float = 120.0
		if PlayerSkills and PlayerSkills.is_unlocked("turret_projectile_speed"):
			proj_speed = 180.0
		
		if b.has_method("set_flight_params"):
			b.set_flight_params(proj_speed, 1.5)


## Update the diagetic barrel colour to reflect the current heat.
## 0.0  → cool dark‑metal grey
## 0.3  → warm orange (starting to glow)
## 0.6  → bright orange-red
## 1.0  → white‑hot (overheated)
func _update_turret_barrel_color() -> void:
	if _turret_barrel_mats.is_empty():
		return
	var t: float = clamp(_turret_heat, 0.0, 1.0)
	# Three‑stage ramp: cool grey → orange → red‑orange → white‑hot.
	var col: Color
	if t < 0.01:
		col = _turret_default_color
	elif t < 0.3:
		var p: float = t / 0.3
		col = _turret_default_color.lerp(Color(1.0, 0.5, 0.1), p)
	elif t < 0.6:
		var p: float = (t - 0.3) / 0.3
		col = Color(1.0, 0.5, 0.1).lerp(Color(1.0, 0.15, 0.05), p)
	else:
		col = Color(1.0, 0.3, 0.1)  # bright red-orange at full heat
	var emission_str: float = 1.0 + t * 6.0
	for mat in _turret_barrel_mats:
		if mat == null:
			continue
		mat.albedo_color = col
		mat.emission = col * emission_str
		mat.emission_energy_multiplier = 1.0 + t * 5.0


## Brief muzzle flash on the turret barrels when firing.
## Creates a temporary bright point light + particle burst at the
## barrel tips. Auto-cleans up after a few frames.
func _flash_turret_muzzle() -> void:
	if body_root == null:
		return
	# Find the turret root node (created in _create_diagetic_visuals)
	var turret_root: Node3D = body_root.get_node_or_null("TurretRoot")
	if turret_root == null:
		# Fallback: spawn at body center
		turret_root = body_root
	var flash_light := OmniLight3D.new()
	flash_light.light_color = Color(1.0, 0.9, 0.4, 1)
	flash_light.light_energy = 6.0
	flash_light.omni_range = 4.0
	flash_light.position = Vector3(0, 0.5, -1.4)  # Near the barrels
	turret_root.add_child(flash_light)
	# Auto-cleanup via tween
	var tween := create_tween()
	tween.tween_property(flash_light, "light_energy", 0.0, 0.12)
	tween.tween_callback(flash_light.queue_free)


func _on_ship_destroyed() -> void:
	SoundManager.play_by_id("sfx_ship_destroyed")
	_apply_skill_stats()
	respawn_in_cargo_hold()


# ---------------------------------------------------------------------
# Respawn
# ---------------------------------------------------------------------

func respawn_at_station() -> void:
	# R / Esc — player-requested respawn. Drops the ship docked inside
	# a cargo bay of the station, fully refuelled and repaired, and
	# triggers the skill tree to open so the player can choose upgrades
	# before redeploying. Same flow as being destroyed, just without
	# the explosion sound.
	respawn_in_cargo_hold()


## Docks the ship inside one of the station's cargo bays and refills it.
## The ship's state is set to DOCKED, which makes Main.gd's dock-watcher
## auto-open the skill tree so the player can spend their gems and
## click Deploy. This is the universal "come home" path for both
## destruction and R-respawn.
func respawn_in_cargo_hold() -> void:
	_apply_skill_stats()

	# Find the station.
	var station: Node3D = null
	for s in get_tree().get_nodes_in_group("station"):
		if is_instance_valid(s):
			station = s
			break

	# Pick a bay (the station has four; we just take the first).
	var bay_pivot: Node3D = null
	if station != null:
		if station.has_method("get_bays"):
			var bays: Array[Node3D] = station.get_bays()
			if bays.size() > 0:
				bay_pivot = bays[0]
		if bay_pivot == null:
			bay_pivot = station.get_node_or_null("HubPivot/BayPivot")

	# Park the ship at the bay door, facing into the hangar.
	if bay_pivot != null:
		var door_pos: Vector3 = bay_pivot.global_position + bay_pivot.global_transform.basis * Vector3(0, 0, -2.8)
		door_pos.y = ground_height
		global_position = door_pos
		var door_dir: Vector3 = -bay_pivot.global_transform.basis.z
		global_rotation.y = atan2(-door_dir.x, -door_dir.z)
	else:
		# No station? Fall back to the original spawn transform.
		global_transform = start_transform
		global_position.y = ground_height

	velocity = Vector3.ZERO
	fuel = _eff_fuel_max
	health = _eff_max_health
	harpoon_claw.visible = false
	harpoon_cable.visible = false
	harpoon_station = null
	harpoon_bay = null
	_nanobot_timer = 0.0
	_gem_combo_count = 0
	_gem_combo_timer = 0.0
	_shield_ready = _eff_shield_cooldown > 0.0
	_shield_timer = 0.0
	fuel_changed.emit(fuel, _eff_fuel_max)
	health_changed.emit(health, _eff_max_health)

	# Register as docked WITHOUT animation. register_docked_ship() on
	# the station is the same hook the harpoon uses when it reels the
	# ship home — it tells the station "I'm in, here's my bay" and the
	# station will set up the dock visuals, undock the previous ship
	# if any, etc. The skill tree auto-opens because Main.gd polls the
	# station's docked state every frame.
	if station != null and station.has_method("register_docked_ship"):
		station.register_docked_ship(self, bay_pivot)

	# Finally, set the ship state to DOCKED. The state machine picks
	# up from there (refuel/heal loop, accepts Deploy button, etc.).
	_set_state(State.DOCKED)


func _ensure_material(mi: MeshInstance3D) -> StandardMaterial3D:
	var mat: StandardMaterial3D = mi.get_active_material(0) as StandardMaterial3D
	if mat == null:
		mat = StandardMaterial3D.new()
		mi.material_override = mat
	return mat

# ── Diagetic visuals ──────────────────────────────────────────────────────────

func _create_diagetic_visuals() -> void:
	# --- Shield: a fresnel/hex shader applied as a next‑pass on
	# the hull mesh.  This paints the energy shield directly on
	# the ship's hull rather than a separate bubble sphere.
	_shield_shader_mat = ShaderMaterial.new()
	_shield_shader_mat.shader = preload("res://shaders/ship_shield.gdshader")
	_shield_shader_mat.set_shader_parameter("shield_color",
		Color(shield_color.r, shield_color.g, shield_color.b, 1.0))
	# Attach the shield as a material overlay on the hull (Hull is
	# the first child of body_root).  material_overlay renders an
	# additional material on top of the base material, which is
	# perfect for painting a shield effect onto the hull surface
	# without changing the hull's own metallic appearance.
	var hull: MeshInstance3D = body_root.get_node_or_null("Hull") as MeshInstance3D
	if hull != null:
		hull.material_overlay = _shield_shader_mat
		hull.material_overlay.set_shader_parameter("shield_strength", 0.0)
	# Keep the old bubble shield as a fallback for when we want the
	# classic dome — but it's hidden by default.
	_shield_mesh = MeshInstance3D.new()
	var shield_sphere := SphereMesh.new()
	shield_sphere.radius = 1.6
	shield_sphere.height = 3.2
	shield_sphere.radial_segments = 24
	shield_sphere.rings = 12
	_shield_mesh.mesh = shield_sphere
	var shield_mat := StandardMaterial3D.new()
	shield_mat.albedo_color = Color(0.3, 0.6, 1.0, 0.25)
	shield_mat.emission_enabled = true
	shield_mat.emission = Color(0.3, 0.6, 1.0, 0.8)
	shield_mat.emission_energy_multiplier = 1.5
	shield_mat.transparency = 1
	shield_mat.cull_mode = 2
	shield_mat.shading_mode = 0
	_shield_mesh.material_override = shield_mat
	_shield_mesh.visible = false
	add_child(_shield_mesh)
	
	# --- Solar panels: thin boxes on top of the wings ---
	# Check if the user has assigned editor nodes for solar panels.
	# If so, use those instead of creating procedurally.
	var editor_solar_l := get_node_or_null(editor_solar_panel_parent_left) as Node3D
	var editor_solar_r := get_node_or_null(editor_solar_panel_parent_right) as Node3D
	
	for wing in [wing_left, wing_right]:
		# Determine if we should use an editor node
		var editor_node: Node3D = editor_solar_l if wing == wing_left else editor_solar_r
		if editor_node != null:
			if wing == wing_left:
				_solar_panel_left = editor_node
			else:
				_solar_panel_right = editor_node
			continue
		
		var panel := MeshInstance3D.new()
		var panel_mesh := BoxMesh.new()
		panel_mesh.size = Vector3(1.2, 0.04, 0.7)
		panel.mesh = panel_mesh
		var panel_mat := StandardMaterial3D.new()
		panel_mat.albedo_color = Color(0.1, 0.15, 0.35, 1)
		panel_mat.metallic = 0.0
		panel_mat.roughness = 0.1
		panel_mat.emission_enabled = true
		panel_mat.emission = Color(0.15, 0.25, 0.7, 1)
		panel_mat.emission_energy_multiplier = 0.3
		panel.material_override = panel_mat
		panel.position = Vector3(0, 0.12, 0)
		panel.visible = false
		wing.add_child(panel)
		if wing == wing_left:
			_solar_panel_left = panel
		else:
			_solar_panel_right = panel
	# Add a thin blue line on each solar panel to show cell divisions
	# Only do this for procedurally-created panels (editor panels are user-edited)
	for panel in [_solar_panel_left, _solar_panel_right]:
		if panel and not (panel == editor_solar_l or panel == editor_solar_r):
			for i in range(3):
				var line := MeshInstance3D.new()
				var line_mesh := BoxMesh.new()
				line_mesh.size = Vector3(0.02, 0.05, 0.7)
				line.mesh = line_mesh
				var line_mat := StandardMaterial3D.new()
				line_mat.albedo_color = Color(0.05, 0.1, 0.2, 1)
				line.material_override = line_mat
				line.position = Vector3(-0.3 + i * 0.3, 0.04, 0)
				panel.add_child(line)
	
	# --- Turret mount: small cylinder + box on the ship's nose (above the laser) ---
	# Check for editor-assigned turret root first
	var editor_turret := get_node_or_null(editor_turret_root) as Node3D
	if editor_turret != null:
		# Use editor-assigned turret; find its barrels for heat effects
		_turret_barrel_mats.clear()
		_turret_barrels.clear()
		for child in editor_turret.get_children():
			child.add_to_group("ship_turret_parts")
			if child is MeshInstance3D:
				var mi := child as MeshInstance3D
				if mi.mesh is CylinderMesh and (mi.mesh as CylinderMesh).height < 1.0:
					_turret_barrels.append(mi)
					var mat = mi.material_override as StandardMaterial3D
					if mat:
						_turret_barrel_mats.append(mat)
					else:
						_turret_barrel_mats.append(null)
		_turret_mount = editor_turret.get_child(0) if editor_turret.get_child_count() > 0 else null
		_turret_default_color = Color(0.2, 0.2, 0.25, 1)
	else:
		_turret_mount = MeshInstance3D.new()
		var turret_root := Node3D.new()
		turret_root.name = "TurretRoot"
		turret_root.position = Vector3(0, 0.35, -1.0)
		body_root.add_child(turret_root)
		var turret_base := CylinderMesh.new()
		turret_base.top_radius = 0.18
		turret_base.bottom_radius = 0.22
		turret_base.height = 0.2
		_turret_mount.mesh = turret_base
		var turret_mat := StandardMaterial3D.new()
		turret_mat.albedo_color = Color(0.3, 0.3, 0.35, 1)
		turret_mat.metallic = 0.8
		turret_mat.roughness = 0.3
		_turret_mount.material_override = turret_mat
		_turret_mount.position = Vector3(0, 0, 0)
		turret_root.add_child(_turret_mount)
		# Add barrel(s) to the turret and remember their materials so
		# we can swap the colour between cool and overheated.
		_turret_barrel_mats.clear()
		_turret_default_color = Color(0.2, 0.2, 0.25, 1)
		for i in [-1, 1]:
			var barrel := MeshInstance3D.new()
			var barrel_mesh := CylinderMesh.new()
			barrel_mesh.top_radius = 0.04
			barrel_mesh.bottom_radius = 0.05
			barrel_mesh.height = 0.6
			barrel.mesh = barrel_mesh
			var barrel_mat := StandardMaterial3D.new()
			barrel_mat.albedo_color = _turret_default_color
			barrel_mat.metallic = 0.9
			barrel_mat.roughness = 0.4
			barrel_mat.emission_enabled = true
			barrel_mat.emission = _turret_default_color * 0.3
			barrel_mat.emission_energy_multiplier = 0.5
			barrel.material_override = barrel_mat
			barrel.position = Vector3(0.08 * i, 0.1, -0.3)
			barrel.rotation = Vector3(PI * 0.5, 0, 0)
			turret_root.add_child(barrel)
			_turret_barrels.append(barrel)
			_turret_barrel_mats.append(barrel_mat)
		_turret_mount.visible = false
		for child in turret_root.get_children():
			child.visible = false
		turret_root.set_meta("all_children", true)
		# Use a group to find all the turret-related visuals
		for child in turret_root.get_children():
			child.add_to_group("ship_turret_parts")
			child.visible = false
		turret_root.add_to_group("ship_turret_parts")
		turret_root.visible = false
	
	# --- Missile pods: undercarriage pylons on left and right wings ---
	# Check for editor-assigned missile pods first
	var editor_mp_l := get_node_or_null(editor_missile_pod_left) as Node3D
	var editor_mp_r := get_node_or_null(editor_missile_pod_right) as Node3D
	if editor_mp_l != null:
		_missile_pod_left = editor_mp_l
	else:
		_missile_pod_left = Node3D.new()
		_missile_pod_left.name = "MissilePodLeft"
		_missile_pod_left.position = Vector3(-0.7, -0.12, -0.1)
		wing_left.add_child(_missile_pod_left)
	
	if editor_mp_r != null:
		_missile_pod_right = editor_mp_r
	else:
		_missile_pod_right = Node3D.new()
		_missile_pod_right.name = "MissilePodRight"
		_missile_pod_right.position = Vector3(0.7, -0.12, -0.1)
		wing_right.add_child(_missile_pod_right)

	# --- Always-visible missile pylon structures under wings ---
	# These show the missile launch system even when no missiles are loaded.
	# We put them in a "StaticStructure" node so _show_missile_ammo() doesn't
	# destroy them when it rebuilds the ammo display.
	# Skip if using editor-assigned pods (user controls the structure)
	for pod in [_missile_pod_left, _missile_pod_right]:
		if pod == editor_mp_l or pod == editor_mp_r:
			continue
		var static_node := Node3D.new()
		static_node.name = "StaticStructure"
		pod.add_child(static_node)
		
		# Main pylon rail (dark titanium)
		var pylon := MeshInstance3D.new()
		var pylon_mesh := BoxMesh.new()
		pylon_mesh.size = Vector3(0.06, 0.04, 0.5)
		pylon.mesh = pylon_mesh
		var pylon_mat := StandardMaterial3D.new()
		pylon_mat.albedo_color = Color(0.15, 0.15, 0.18, 1.0)
		pylon_mat.metallic = 0.9
		pylon_mat.roughness = 0.3
		pylon.material_override = pylon_mat
		pylon.position = Vector3(0, -0.02, 0)
		static_node.add_child(pylon)
		
		# Launch tube housing (cylindrical)
		var tube_housing := MeshInstance3D.new()
		var tube_mesh := CylinderMesh.new()
		tube_mesh.top_radius = 0.06
		tube_mesh.bottom_radius = 0.07
		tube_mesh.height = 0.35
		tube_housing.mesh = tube_mesh
		var tube_mat := StandardMaterial3D.new()
		tube_mat.albedo_color = Color(0.22, 0.22, 0.25, 1.0)
		tube_mat.metallic = 0.85
		tube_mat.roughness = 0.35
		tube_housing.material_override = tube_mat
		tube_housing.position = Vector3(0, -0.06, 0)
		tube_housing.rotation = Vector3(PI * 0.5, 0, 0)
		static_node.add_child(tube_housing)
		
		# Glowing orange launch indicator ring
		var indicator := MeshInstance3D.new()
		var indicator_mesh := TorusMesh.new()
		indicator_mesh.inner_radius = 0.04
		indicator_mesh.outer_radius = 0.065
		indicator.mesh = indicator_mesh
		var indicator_mat := StandardMaterial3D.new()
		indicator_mat.albedo_color = Color(1.0, 0.4, 0.1, 1.0)
		indicator_mat.emission_enabled = true
		indicator_mat.emission = Color(1.0, 0.3, 0.05, 1.0)
		indicator_mat.emission_energy_multiplier = 1.5
		indicator.material_override = indicator_mat
		indicator.position = Vector3(0, -0.06, -0.15)
		indicator.rotation = Vector3(PI * 0.5, 0, 0)
		static_node.add_child(indicator)
		
		# Structural support struts connecting pylon to wing
		for side in [-1, 1]:
			var strut := MeshInstance3D.new()
			var strut_mesh := BoxMesh.new()
			strut_mesh.size = Vector3(0.02, 0.08, 0.02)
			strut.mesh = strut_mesh
			var strut_mat := StandardMaterial3D.new()
			strut_mat.albedo_color = Color(0.18, 0.18, 0.2, 1.0)
			strut_mat.metallic = 0.85
			strut_mat.roughness = 0.4
			strut.material_override = strut_mat
			strut.position = Vector3(0.08 * side, 0.02, 0.15)
			static_node.add_child(strut)

	# --- Triple Thruster Engine Plume Particles ---
	var engines_info = [
		{"pos": Vector3(0, 0, 1.22), "size": 0.09, "amount": 45},      # Main center engine
		{"pos": Vector3(-0.5, 0, 1.20), "size": 0.065, "amount": 25},  # Left side engine
		{"pos": Vector3(0.5, 0, 1.20), "size": 0.065, "amount": 25}    # Right side engine
	]
	
	var part_mat := StandardMaterial3D.new()
	part_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	part_mat.vertex_color_use_as_albedo = true
	part_mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	
	var emitters: Array[CPUParticles3D] = []
	for i in range(3):
		var info = engines_info[i]
		var emitter := CPUParticles3D.new()
		emitter.amount = info["amount"]
		emitter.lifetime = 0.35
		emitter.explosiveness = 0.0
		emitter.randomness = 0.2
		emitter.position = info["pos"]
		
		var p_mesh := SphereMesh.new()
		p_mesh.radius = info["size"]
		p_mesh.height = info["size"] * 2.0
		emitter.mesh = p_mesh
		
		emitter.direction = Vector3(0, 0, 1) # shoot straight back
		emitter.spread = 8.0
		emitter.gravity = Vector3.ZERO
		emitter.initial_velocity_min = 4.0
		emitter.initial_velocity_max = 7.0
		
		var scale_curve := Curve.new()
		scale_curve.add_point(Vector2(0.0, 1.0))
		scale_curve.add_point(Vector2(0.3, 1.2))
		scale_curve.add_point(Vector2(1.0, 0.1))
		emitter.scale_amount_curve = scale_curve
		
		# Classic rocket fuel fire gradient: blue core -> orange -> red -> grey smoke
		var gradient := Gradient.new()
		gradient.add_point(0.0, Color(0.2, 0.7, 1.0, 1.0))  # blue core
		gradient.add_point(0.15, Color(1.0, 0.6, 0.15, 0.9)) # orange fire
		gradient.add_point(0.4, Color(0.9, 0.25, 0.05, 0.6)) # red-orange
		gradient.add_point(0.7, Color(0.25, 0.25, 0.25, 0.3)) # smoke
		gradient.add_point(1.0, Color(0.1, 0.1, 0.1, 0.0))
		emitter.color_ramp = gradient
		emitter.material_override = part_mat
		
		body_root.add_child(emitter)
		emitter.emitting = true
		emitters.append(emitter)
		
	_afterburner_particles = emitters[0] # main
	_thruster_particles_left = emitters[1]
	_thruster_particles_right = emitters[2]
	
	# --- Cargo Bay (undercarriage that grows with gem capacity skills) ---
	var editor_cb := get_node_or_null(editor_cargo_bay) as MeshInstance3D
	if editor_cb != null:
		_cargo_bay = editor_cb
	else:
		_cargo_bay = MeshInstance3D.new()
		var cargo_box := BoxMesh.new()
		cargo_box.size = Vector3(0.7, 0.3, 0.6)
		_cargo_bay.mesh = cargo_box
		var cargo_mat := StandardMaterial3D.new()
		cargo_mat.albedo_color = Color(0.55, 0.4, 0.25, 1)
		cargo_mat.metallic = 0.5
		cargo_mat.roughness = 0.6
		cargo_mat.emission_enabled = true
		cargo_mat.emission = Color(0.7, 0.5, 0.1, 1)
		cargo_mat.emission_energy_multiplier = 0.2
		_cargo_bay.material_override = cargo_mat
		_cargo_bay.position = Vector3(0, -0.4, 0)
		_cargo_bay.visible = false
		body_root.add_child(_cargo_bay)
		# Add a "lid" detail line
		var lid := MeshInstance3D.new()
		var lid_mesh := BoxMesh.new()
		lid_mesh.size = Vector3(0.72, 0.04, 0.62)
		lid.mesh = lid_mesh
		var lid_mat := StandardMaterial3D.new()
		lid_mat.albedo_color = Color(0.35, 0.25, 0.15, 1)
		lid_mat.metallic = 0.6
		lid_mat.roughness = 0.5
		lid.material_override = lid_mat
		lid.position = Vector3(0, 0.16, 0)
		_cargo_bay.add_child(lid)
	
	# --- Small Tractor Magnet on the ship's nose ---
	# A small horseshoe magnet that appears when gem_magnet is unlocked.
	# Grows slightly with each tier. Just a small mesh, no field sphere.
	_magnet_ring = Node3D.new()
	# Position it on the front of the ship, above the laser
	_magnet_ring.position = Vector3(0, 0.45, -1.2)
	_magnet_ring.visible = false
	body_root.add_child(_magnet_ring)

	# 1) Base cylindrical mount (dark steel/carbon)
	var base := MeshInstance3D.new()
	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = 0.1
	base_mesh.bottom_radius = 0.12
	base_mesh.height = 0.15
	base.mesh = base_mesh
	base.rotation = Vector3(PI * 0.5, 0, 0)
	var base_mat := StandardMaterial3D.new()
	base_mat.albedo_color = Color(0.12, 0.12, 0.15, 1)
	base_mat.metallic = 0.9
	base_mat.roughness = 0.3
	base.material_override = base_mat
	_magnet_ring.add_child(base)

	# 2) Dual heavy electromagnetic prongs (curved/angled)
	for i in [-1, 1]:
		var prong := MeshInstance3D.new()
		var prong_mesh := BoxMesh.new()
		prong_mesh.size = Vector3(0.05, 0.05, 0.2)
		prong.mesh = prong_mesh
		var prong_mat := StandardMaterial3D.new()
		prong_mat.albedo_color = Color(0.7, 0.7, 0.75, 1)
		prong_mat.metallic = 0.9
		prong_mat.roughness = 0.2
		prong.material_override = prong_mat
		prong.position = Vector3(0.12 * i, 0, -0.06)
		# Angle them slightly inward
		prong.rotation = Vector3(0, -0.2 * i, 0)
		_magnet_ring.add_child(prong)
		
		# Copper wire coil details on each prong
		var coil := MeshInstance3D.new()
		var coil_mesh := CylinderMesh.new()
		coil_mesh.top_radius = 0.06
		coil_mesh.bottom_radius = 0.06
		coil_mesh.height = 0.1
		coil.mesh = coil_mesh
		coil.rotation = Vector3(PI * 0.5, 0, 0)
		coil.position = Vector3(0, 0, -0.02)
		var coil_mat := StandardMaterial3D.new()
		coil_mat.albedo_color = Color(0.9, 0.45, 0.15, 1) # bright copper coil
		coil_mat.metallic = 0.9
		coil_mat.roughness = 0.3
		coil.material_override = coil_mat
		prong.add_child(coil)

		# Tip emitters (glowing blue balls)
		var tip := MeshInstance3D.new()
		var tip_mesh := SphereMesh.new()
		tip_mesh.radius = 0.03
		tip_mesh.height = 0.06
		tip.mesh = tip_mesh
		tip.position = Vector3(0, 0, -0.1)
		var tip_mat := StandardMaterial3D.new()
		tip_mat.albedo_color = Color(0.2, 0.8, 1.0, 1)
		tip_mat.emission_enabled = true
		tip_mat.emission = Color(0.1, 0.7, 1.0, 1)
		tip_mat.emission_energy_multiplier = 4.0
		tip.material_override = tip_mat
		prong.add_child(tip)

	# 3) Inner energy core (glowing floating sphere in the center)
	var core := MeshInstance3D.new()
	var core_mesh := SphereMesh.new()
	core_mesh.radius = 0.06
	core_mesh.height = 0.12
	core.mesh = core_mesh
	core.position = Vector3(0, 0, -0.08)
	var core_mat := StandardMaterial3D.new()
	core_mat.albedo_color = Color(0.2, 0.8, 1.0, 1)
	core_mat.emission_enabled = true
	core_mat.emission = Color(0.1, 0.7, 1.0, 1)
	core_mat.emission_energy_multiplier = 5.0
	core.material_override = core_mat
	_magnet_ring.add_child(core)

	# 4) Dynamic Tractor Beam Particle Intake
	var part_emitter := CPUParticles3D.new()
	part_emitter.name = "TractorParticles"
	part_emitter.amount = 25
	part_emitter.lifetime = 0.6
	part_emitter.explosiveness = 0.0
	part_emitter.randomness = 0.3
	
	# Spawn particles in front of the magnet
	part_emitter.position = Vector3(0, 0, -2.5)
	
	# Emit towards the magnet (along +Z)
	part_emitter.direction = Vector3(0, 0, 1)
	part_emitter.spread = 15.0
	part_emitter.gravity = Vector3.ZERO
	part_emitter.initial_velocity_min = 3.5
	part_emitter.initial_velocity_max = 5.5
	
	# Emit in a box volume in front of the ship
	part_emitter.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	part_emitter.emission_box_extents = Vector3(0.5, 0.5, 1.0)
	
	var part_mesh := SphereMesh.new()
	part_mesh.radius = 0.03
	part_mesh.height = 0.06
	part_emitter.mesh = part_mesh
	
	# Shrink as they get closer to the magnet core
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.2))
	scale_curve.add_point(Vector2(0.3, 1.0))
	scale_curve.add_point(Vector2(0.8, 0.8))
	scale_curve.add_point(Vector2(1.0, 0.0))
	part_emitter.scale_amount_curve = scale_curve
	
	# Soft blue/cyan energy glow fading out at the core
	var gradient := Gradient.new()
	gradient.add_point(0.0, Color(0.2, 0.5, 1.0, 0.0)) # fade in
	gradient.add_point(0.2, Color(0.2, 0.8, 1.0, 0.8)) # bright cyan
	gradient.add_point(0.8, Color(0.8, 0.2, 1.0, 0.8)) # purple shift near core
	gradient.add_point(1.0, Color(1.0, 0.2, 1.0, 0.0)) # fade out at destination
	part_emitter.color_ramp = gradient
	
	var part_mat2 := StandardMaterial3D.new()
	part_mat2.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	part_mat2.vertex_color_use_as_albedo = true
	part_mat2.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	part_emitter.material_override = part_mat2
	
	_magnet_ring.add_child(part_emitter)
	part_emitter.emitting = true

	# --- Spike Ram: a wall of spikes on the front of the ship ---
	# Visible only when the spike_ram skill is unlocked.
	var spike_root := Node3D.new()
	spike_root.name = "SpikeRoot"
	spike_root.position = Vector3(0, 0.1, -1.6)  # Front of ship
	spike_root.visible = false
	body_root.add_child(spike_root)
	
	# Mounting bar (dark steel)
	var bar := MeshInstance3D.new()
	var bar_mesh := BoxMesh.new()
	bar_mesh.size = Vector3(0.9, 0.08, 0.08)
	bar.mesh = bar_mesh
	var bar_mat := StandardMaterial3D.new()
	bar_mat.albedo_color = Color(0.12, 0.12, 0.14, 1.0)
	bar_mat.metallic = 0.9
	bar_mat.roughness = 0.3
	bar.material_override = bar_mat
	bar.position = Vector3(0, 0, -0.1)
	spike_root.add_child(bar)
	
	# Spikes — a row of sharp cones across the front
	for i in range(7):
		var spike := MeshInstance3D.new()
		var spike_mesh := CylinderMesh.new()
		spike_mesh.top_radius = 0.01
		spike_mesh.bottom_radius = 0.06
		spike_mesh.height = 0.35
		spike.mesh = spike_mesh
		var spike_mat := StandardMaterial3D.new()
		spike_mat.albedo_color = Color(0.6, 0.55, 0.5, 1.0)  # Worn steel
		spike_mat.metallic = 0.85
		spike_mat.roughness = 0.4
		spike_mat.emission_enabled = true
		spike_mat.emission = Color(0.8, 0.3, 0.1, 1.0)  # Red-hot tips
		spike_mat.emission_energy_multiplier = 0.3
		spike.material_override = spike_mat
		var x_offset := (i - 3) * 0.13
		spike.position = Vector3(x_offset, 0, 0)
		spike.rotation = Vector3(-PI * 0.5, 0, 0)  # Point forward (-Z)
		spike_root.add_child(spike)
	
	# Store reference for visibility toggle
	spike_root.set_meta("is_spike_ram", true)
	_spike_root = spike_root


func _update_diagetic_visuals() -> void:
	# --- Shield visual ---
	if _shield_mesh:
		# Direct check of unlock state. Shield is ONLY visible when
		# the skill is unlocked AND the shield is fully charged. While
		# recharging, the shield is completely hidden (not faded).
		var shield_unlocked := PlayerSkills and PlayerSkills.is_unlocked("shield_unlock")
		_shield_mesh.visible = false
	# Drive the hull‑shield shader parameter: 0 when not ready,
	# 1 when fully charged, so the hex‑pattern emission fades on
	# the hull when the shield is down.
	if _shield_shader_mat != null:
		var strength: float = 1.0 if (PlayerSkills and PlayerSkills.is_unlocked("shield_unlock") and _shield_ready) else 0.0
		_shield_shader_mat.set_shader_parameter("shield_strength", strength)
	
	# --- Spike Ram visual ---
	if _spike_root:
		_spike_root.visible = _eff_spike_ram
	
	# --- Solar panels visual ---
	if _solar_panel_left:
		_solar_panel_left.visible = _eff_solar_regen > 0.0
	if _solar_panel_right:
		_solar_panel_right.visible = _eff_solar_regen > 0.0
	
	# --- Turret mount visual ---
	# Visible if any turret-related skill is unlocked
	var turret_unlocked := PlayerSkills and (
		PlayerSkills.is_unlocked("turret_unlock") or
		PlayerSkills.is_unlocked("turret_rapid_fire") or
		PlayerSkills.is_unlocked("turret_projectile_speed") or
		PlayerSkills.is_unlocked("turret_projectile_pierce") or
		PlayerSkills.is_unlocked("ricochet_rounds") or
		PlayerSkills.is_unlocked("critical_chance") or
		PlayerSkills.is_unlocked("critical_multiplier") or
		PlayerSkills.is_unlocked("multi_shot") or
		PlayerSkills.is_unlocked("chain_lightning") or
		PlayerSkills.is_unlocked("frost_shot")
	)
	for node in get_tree().get_nodes_in_group("ship_turret_parts"):
		node.visible = turret_unlocked
	
	# --- Missile pod visual ---
	# Visible when any missile-related skill is unlocked.
	# The pod itself stays visible as long as there's capacity.
	# Individual tubes show/hide based on remaining ammo count.
	var missile_unlocked := PlayerSkills and (
		PlayerSkills.is_unlocked("missile_unlock") or
		PlayerSkills.is_unlocked("missile_heat_seeking") or
		PlayerSkills.is_unlocked("missile_splash_area") or
		PlayerSkills.is_unlocked("turret_unlock")
	)
	_show_missile_ammo(missile_unlocked, _missile_pod_left, _missile_tubes_left, _missile_ammo_left)
	_show_missile_ammo(missile_unlocked, _missile_pod_right, _missile_tubes_right, _missile_ammo_right)
	
	# --- Cargo bay visual: grows with gem_capacity skills ---
	if _cargo_bay:
		var has_cargo := PlayerSkills and (
			PlayerSkills.is_unlocked("gem_capacity") or
			PlayerSkills.is_unlocked("gem_capacity_2") or
			PlayerSkills.is_unlocked("gem_capacity_3")
		)
		_cargo_bay.visible = has_cargo
		if has_cargo:
			# Scale grows with each tier (0.6, 0.85, 1.1, 1.4)
			var scale_factor := 0.6
			if PlayerSkills.is_unlocked("gem_capacity"): scale_factor = 0.85
			if PlayerSkills.is_unlocked("gem_capacity_2"): scale_factor = 1.1
			if PlayerSkills.is_unlocked("gem_capacity_3"): scale_factor = 1.4
			_cargo_bay.scale = Vector3(scale_factor, scale_factor, scale_factor)
			# Color shift: dim -> glowing gold as it gets bigger
			var mat: StandardMaterial3D = _cargo_bay.material_override
			if mat:
				mat.emission_energy_multiplier = 0.2 + (scale_factor - 0.6) * 0.6
	
	# --- Tractor magnet visual: ring and field that grow with magnet skills ---
	var has_magnet := PlayerSkills and (
		PlayerSkills.is_unlocked("gem_magnet") or
		PlayerSkills.is_unlocked("gem_magnet_2") or
		PlayerSkills.is_unlocked("gem_magnet_3")
	)
	if _magnet_ring:
		_magnet_ring.visible = has_magnet
		if has_magnet:
			# Small magnet grows slightly with each tier
			var magnet_scale := 1.0
			if PlayerSkills.is_unlocked("gem_magnet"): magnet_scale = 1.1
			if PlayerSkills.is_unlocked("gem_magnet_2"): magnet_scale = 1.2
			if PlayerSkills.is_unlocked("gem_magnet_3"): magnet_scale = 1.35
			_magnet_ring.scale = Vector3(magnet_scale, magnet_scale, magnet_scale)

func _update_afterburner_visuals() -> void:
	# The thruster plumes are now always emitting; the afterburner visual
	# difference is handled in _set_engine_glow by scaling amount/velocity.
	# Nothing extra to do here — just leave the emitters running.
	pass

# ── Skill integration ──────────────────────────────────────────────────────────

func _on_skill_unlocked(_skill_id: String) -> void:
	_apply_skill_stats()


## Show/hide missile pod and its tubes based on remaining ammo.
func _show_missile_ammo(unlocked: bool, pod: Node3D, tubes: Array[MeshInstance3D], ammo: int) -> void:
	if pod == null:
		return
	
	pod.visible = unlocked and _eff_missile_max_per_pod > 0
	if not pod.visible:
		return

	# Determine cache keys to see if we need to rebuild
	var is_left = (pod == _missile_pod_left)
	var last_capacity = _last_rendered_max_capacity_left if is_left else _last_rendered_max_capacity_right
	var last_ammo = _last_rendered_ammo_left if is_left else _last_rendered_ammo_right
	
	var current_capacity = _eff_missile_max_per_pod
	
	if last_capacity == current_capacity and last_ammo == ammo:
		return # No change, skip rebuild!
		
	# Update cache
	if is_left:
		_last_rendered_max_capacity_left = current_capacity
		_last_rendered_ammo_left = ammo
	else:
		_last_rendered_max_capacity_right = current_capacity
		_last_rendered_ammo_right = ammo
		
	# Clear previous ammo-related children (but preserve StaticStructure)
	for child in pod.get_children():
		if child.name != "StaticStructure":
			child.queue_free()
		
	# Common materials
	var rail_mat := StandardMaterial3D.new()
	rail_mat.albedo_color = Color(0.18, 0.18, 0.2, 1) # dark rails
	rail_mat.metallic = 0.9
	rail_mat.roughness = 0.35
	
	var missile_body_mat := StandardMaterial3D.new()
	missile_body_mat.albedo_color = Color(0.85, 0.85, 0.9, 1) # sleek military white
	missile_body_mat.metallic = 0.8
	missile_body_mat.roughness = 0.2
	
	var missile_tip_mat := StandardMaterial3D.new()
	missile_tip_mat.albedo_color = Color(1.0, 0.3, 0.15, 1) # target red orange glow
	missile_tip_mat.emission_enabled = true
	missile_tip_mat.emission = Color(1.0, 0.3, 0.15, 1)
	missile_tip_mat.emission_energy_multiplier = 2.0
	
	var missile_fin_mat := StandardMaterial3D.new()
	missile_fin_mat.albedo_color = Color(0.2, 0.2, 0.25, 1)
	missile_fin_mat.metallic = 0.7
	missile_fin_mat.roughness = 0.4

	# Calculate slot positions based on capacity
	var offsets: Array[Vector3] = []
	if current_capacity <= 1:
		offsets.append(Vector3(0, 0, 0))
	elif current_capacity == 2:
		offsets.append(Vector3(-0.08, 0, 0))
		offsets.append(Vector3(0.08, 0, 0))
	elif current_capacity == 4:
		offsets.append(Vector3(-0.08, 0, 0.08))
		offsets.append(Vector3(0.08, 0, 0.08))
		offsets.append(Vector3(-0.08, -0.08, -0.08))
		offsets.append(Vector3(0.08, -0.08, -0.08))
	else: # 6 missiles
		offsets.append(Vector3(-0.15, 0, 0.1))
		offsets.append(Vector3(0, 0, 0.1))
		offsets.append(Vector3(0.15, 0, 0.1))
		offsets.append(Vector3(-0.15, -0.08, -0.1))
		offsets.append(Vector3(0, -0.08, -0.1))
		offsets.append(Vector3(0.15, -0.08, -0.1))
		
	# Draw pylons and missiles
	for i in range(offsets.size()):
		var slot_pos = offsets[i]
		
		# 1) Tiny launch rail bracket
		var rail := MeshInstance3D.new()
		var rail_mesh := BoxMesh.new()
		rail_mesh.size = Vector3(0.02, 0.02, 0.35)
		rail.mesh = rail_mesh
		rail.material_override = rail_mat
		rail.position = slot_pos
		pod.add_child(rail)
		
		# 2) Loaded missile model (if index < ammo)
		if i < ammo:
			var m_model := Node3D.new()
			# Move missile slightly forward and below the rail
			m_model.position = slot_pos + Vector3(0, -0.04, -0.05)
			pod.add_child(m_model)
			
			# Missile fuselage
			var body := MeshInstance3D.new()
			var body_mesh := CapsuleMesh.new()
			body_mesh.radius = 0.032
			body_mesh.height = 0.28
			body.mesh = body_mesh
			body.material_override = missile_body_mat
			body.rotation = Vector3(PI * 0.5, 0, 0)
			m_model.add_child(body)
			
			# Missile target tip
			var tip := MeshInstance3D.new()
			var tip_mesh := SphereMesh.new()
			tip_mesh.radius = 0.033
			tip_mesh.height = 0.065
			tip.mesh = tip_mesh
			tip.material_override = missile_tip_mat
			tip.position = Vector3(0, 0, -0.13)
			m_model.add_child(tip)
			
			# 4 fins at the back
			for f in range(4):
				var fin := MeshInstance3D.new()
				var fin_mesh := BoxMesh.new()
				fin_mesh.size = Vector3(0.08, 0.012, 0.08)
				fin.mesh = fin_mesh
				fin.material_override = missile_fin_mat
				var angle = f * PI * 0.5
				fin.position = Vector3(cos(angle) * 0.05, sin(angle) * 0.05, 0.1)
				fin.rotation = Vector3(0, 0, angle)
				fin.rotate_x(0.3) # sweep back
				m_model.add_child(fin)


func _on_skills_reset() -> void:
	# Re-apply stats (e.g. when user clicks "Relock All" in the skill tree)
	_apply_skill_stats()

func _apply_skill_stats() -> void:
	if not PlayerSkills:
		_reset_effective_stats()
		return
	
	# Start from base values
	_reset_effective_stats()
	
	# Fuel Capacity: +fuel_max_bonus each level
	var fuel_bonus := 0
	if PlayerSkills.is_unlocked("fuel_capacity"): fuel_bonus += 25
	if PlayerSkills.is_unlocked("fuel_capacity_2"): fuel_bonus += 25
	if PlayerSkills.is_unlocked("fuel_capacity_3"): fuel_bonus += 50
	_eff_fuel_max = fuel_max + fuel_bonus
	
	# Fuel Efficiency: -fuel_efficiency_pct% fuel consumption (each level stacks)
	var eff_pct := 0
	if PlayerSkills.is_unlocked("fuel_efficiency"): eff_pct += 10
	if PlayerSkills.is_unlocked("fuel_efficiency_2"): eff_pct += 10
	var eff_mult := 1.0 - float(eff_pct) / 100.0
	_eff_fuel_per_thrust = fuel_per_thrust * eff_mult
	_eff_fuel_per_mine = fuel_per_mine * eff_mult
	
	# Solar Panels: passive regen when not thrusting
	if PlayerSkills.is_unlocked("solar_panels"):
		_eff_solar_regen = 2.0
	
	# Ion Thrusters: speed and yaw
	var speed_bonus_pct := 0
	var yaw_bonus_pct := 0
	# Base engine tuning skills add to the base max_speed
	var base_speed_mult := 1.0
	if PlayerSkills.is_unlocked("engine_tuning_1"): base_speed_mult += 0.20
	if PlayerSkills.is_unlocked("engine_tuning_2"): base_speed_mult += 0.20
	if PlayerSkills.is_unlocked("ion_thrusters"):
		speed_bonus_pct += 15
		yaw_bonus_pct += 15
	if PlayerSkills.is_unlocked("ion_thrusters_2"):
		speed_bonus_pct += 15
		yaw_bonus_pct += 15
	_eff_max_speed = max_speed * base_speed_mult * (1.0 + float(speed_bonus_pct) / 100.0)
	_eff_yaw_speed = yaw_speed * (1.0 + float(yaw_bonus_pct) / 100.0)
	_eff_forward_thrust = forward_thrust * base_speed_mult
	
	# Reverse Thrusters
	if PlayerSkills.is_unlocked("reverse_thrusters"):
		_eff_reverse_thrust = reverse_thrust * 1.3
	else:
		_eff_reverse_thrust = reverse_thrust
	
	# Afterburner
	if PlayerSkills.is_unlocked("afterburner"):
		_eff_afterburner_speed_pct = 25.0
		_eff_afterburner_fuel_cost = 8.0
	if PlayerSkills.is_unlocked("afterburner_speed"):
		_eff_afterburner_speed_pct += 15.0
	if PlayerSkills.is_unlocked("afterburner_efficiency"):
		_eff_afterburner_efficiency_pct = 25.0
	
	# Armor Plating
	var hp_bonus := 0
	if PlayerSkills.is_unlocked("armor_plating"): hp_bonus += 25
	if PlayerSkills.is_unlocked("armor_plating_2"): hp_bonus += 25
	if PlayerSkills.is_unlocked("armor_plating_3"): hp_bonus += 50
	_eff_max_health = max_health + hp_bonus
	
	# Nanorobots
	if PlayerSkills.is_unlocked("nanorobots"):
		_eff_nanobot_heal = 3.0
		_eff_nanobot_interval = 5.0
	
	# Gem Heal
	if PlayerSkills.is_unlocked("nanobot_gem_heal"):
		_eff_gem_heal = 2
	
	# Shield
	_shield_ready = false
	_shield_timer = 0.0
	_eff_shield_cooldown = 0.0
	if PlayerSkills.is_unlocked("shield_unlock"):
		_eff_shield_cooldown = 15.0
		_shield_ready = true
		if PlayerSkills.is_unlocked("shield_recharge"):
			_eff_shield_cooldown -= 3.0
		if PlayerSkills.is_unlocked("shield_recharge_2"):
			_eff_shield_cooldown -= 3.0
		_eff_shield_cooldown = max(_eff_shield_cooldown, 5.0)
	
	# Mining Efficiency
	var mining_fuel_red := 0
	if PlayerSkills.is_unlocked("mining_efficiency"): mining_fuel_red += 2
	if PlayerSkills.is_unlocked("mining_efficiency_2"): mining_fuel_red += 2
	if PlayerSkills.is_unlocked("laser_fuel_efficiency"): mining_fuel_red += 1
	if PlayerSkills.is_unlocked("laser_fuel_efficiency_2"): mining_fuel_red += 2
	_eff_fuel_per_mine = max(1.0, _eff_fuel_per_mine - float(mining_fuel_red))

	# Turret cool rate — base 0.25/s, improved by skills.
	_eff_turret_cool_rate = 0.25
	if PlayerSkills.is_unlocked("turret_rapid_fire"):
		_eff_turret_cool_rate += 0.05
	if PlayerSkills.is_unlocked("turret_rapid_fire_2"):
		_eff_turret_cool_rate += 0.05
	if PlayerSkills.is_unlocked("turret_rapid_fire_3"):
		_eff_turret_cool_rate += 0.05
	# Turret heat‑per‑shot — skills reduce heat build‑up.
	if PlayerSkills.is_unlocked("turret_rapid_fire"):
		turret_heat_per_shot = 0.06
	if PlayerSkills.is_unlocked("turret_rapid_fire_2"):
		turret_heat_per_shot = 0.055
	if PlayerSkills.is_unlocked("turret_rapid_fire_3"):
		turret_heat_per_shot = 0.05
	
	# Gem Yield - now affects drop chance instead of guaranteed gems
	var gem_chance_bonus: float = 0.0
	if PlayerSkills.is_unlocked("mining_yield"): gem_chance_bonus += 0.15  # +15% chance
	if PlayerSkills.is_unlocked("mining_yield_2"): gem_chance_bonus += 0.25  # +25% chance (total 40%)
	# Update AsteroidManager with the new chance bonus
	var asteroid_mgr = get_tree().get_first_node_in_group("asteroid_managers")
	if asteroid_mgr == null:
		asteroid_mgr = get_node_or_null("../AsteroidManager")
	if asteroid_mgr and asteroid_mgr.has_method("update_gem_chance_bonus"):
		asteroid_mgr.update_gem_chance_bonus(gem_chance_bonus)
	
	# Gem Capacity (cargo hold)
	var gem_cap_bonus := 0
	if PlayerSkills.is_unlocked("gem_capacity"): gem_cap_bonus += 25
	if PlayerSkills.is_unlocked("gem_capacity_2"): gem_cap_bonus += 50
	if PlayerSkills.is_unlocked("gem_capacity_3"): gem_cap_bonus += 100
	_eff_gem_capacity = 50 + gem_cap_bonus
	# Clamp current gems to new capacity
	_clamp_inventory_to_capacity()
	
	# Gem Magnet (Tractor) - only affects ATTRACT (pull) range.
	# The actual pickup (collect) range stays small so you can see
	# the gems flying toward the ship before they're collected.
	_eff_gem_pickup_bonus = 0.0
	_eff_gem_attract_bonus = 0.0
	if PlayerSkills.is_unlocked("gem_magnet"):
		_eff_gem_attract_bonus += 15.0
	if PlayerSkills.is_unlocked("gem_magnet_2"):
		_eff_gem_attract_bonus += 25.0
	if PlayerSkills.is_unlocked("gem_magnet_3"):
		_eff_gem_attract_bonus += 40.0
	
	# Extended Laser
	var laser_range_bonus := 0
	if PlayerSkills.is_unlocked("laser_range"): laser_range_bonus += 10
	if PlayerSkills.is_unlocked("laser_range_2"): laser_range_bonus += 10
	_eff_laser_range = laser_range + laser_range_bonus
	# Laser Width — scales with Laser Power skills (Wide Beam skills removed, folded into Laser Power)
	_eff_laser_width = 0.22
	_eff_mining_cone_dot = 0.92
	if PlayerSkills.is_unlocked("laser_power"):
		_eff_laser_width = 0.50
		_eff_mining_cone_dot = 0.78
	if PlayerSkills.is_unlocked("laser_power_2"):
		_eff_laser_width = 0.75
		_eff_mining_cone_dot = 0.62
	# Laser Chain
	_eff_laser_chain_count = 0
	if PlayerSkills.is_unlocked("laser_chain"): _eff_laser_chain_count = 1
	if PlayerSkills.is_unlocked("laser_chain_2"): _eff_laser_chain_count = 2
	# Laser Power (multiplicative damage bonus)
	_eff_laser_damage_mult = 1.0
	if PlayerSkills.is_unlocked("laser_power"): _eff_laser_damage_mult += 0.5
	if PlayerSkills.is_unlocked("laser_power_2"): _eff_laser_damage_mult += 1.0
	
	# Mining Laser Combat — mining laser damages enemy ships
	_eff_laser_combat = PlayerSkills.is_unlocked("mining_laser_combat")
	
	# Harpoon upgrades
	_eff_harpoon_reel_speed = harpoon_reel_speed
	if PlayerSkills.is_unlocked("harpoon_speed"): _eff_harpoon_reel_speed += 5
	if PlayerSkills.is_unlocked("harpoon_speed_2"): _eff_harpoon_reel_speed += 5
	
	# Flare Countermeasures — breaks enemy homing missile lock-on when activated
	_eff_flare_unlocked = PlayerSkills.is_unlocked("flare_system")
	
	# Spike Ram — front spikes damage enemies on contact
	_eff_spike_ram = PlayerSkills.is_unlocked("spike_ram")
	_eff_spike_ram_damage_pct = 0.2 if _eff_spike_ram else 0.0
	
	# Stunt Pilot — faster barrel roll
	_eff_stunt_pilot = PlayerSkills.is_unlocked("stunt_pilot")
	_eff_barrel_roll_speed_pct = 40.0 if _eff_stunt_pilot else 0.0
	
	# Bullet Time — slow time during barrel roll
	_eff_bullet_time = PlayerSkills.is_unlocked("bullet_time")
	_eff_bullet_time_scale = 0.3 if _eff_bullet_time else 1.0
	
	# Missile capacity — extra missiles per wing pod
	_eff_missile_max_per_pod = 1
	if PlayerSkills.is_unlocked("missile_capacity"): _eff_missile_max_per_pod = 2
	if PlayerSkills.is_unlocked("missile_capacity_2"): _eff_missile_max_per_pod = 4
	if PlayerSkills.is_unlocked("missile_capacity_3"): _eff_missile_max_per_pod = 6
	
	# Ensure current missile counts don't exceed new capacity
	_missile_ammo_left = mini(_missile_ammo_left, _eff_missile_max_per_pod)
	_missile_ammo_right = mini(_missile_ammo_right, _eff_missile_max_per_pod)
	
	# Ensure current fuel/health don't exceed new max
	fuel = min(fuel, _eff_fuel_max)
	health = min(health, _eff_max_health)
	
	# Emit updates
	fuel_changed.emit(fuel, _eff_fuel_max)
	health_changed.emit(health, _eff_max_health)
	if _eff_shield_cooldown > 0.0:
		shield_changed.emit(_shield_ready, 0.0)
	_update_diagetic_visuals()

func _reset_effective_stats() -> void:
	_eff_max_health = max_health
	_eff_fuel_max = fuel_max
	_eff_forward_thrust = forward_thrust
	_eff_reverse_thrust = reverse_thrust
	_eff_yaw_speed = yaw_speed
	_eff_max_speed = max_speed
	_eff_laser_range = laser_range
	_eff_laser_width = 0.22
	_eff_laser_chain_count = 0
	_eff_laser_damage_mult = 1.0
	_eff_mining_cone_dot = 0.92
	_eff_harpoon_reel_speed = harpoon_reel_speed
	_eff_fuel_per_thrust = fuel_per_thrust
	_eff_fuel_per_mine = fuel_per_mine
	_eff_gem_heal = 0
	_eff_bonus_gems = 0
	_eff_gem_capacity = 50
	_eff_gem_pickup_bonus = 0.0
	_eff_gem_attract_bonus = 0.0
	_eff_magnet_speed_mult = 1.0
	_eff_solar_regen = 0.0
	_eff_nanobot_heal = 0.0
	_eff_nanobot_interval = 0.0
	_eff_shield_cooldown = 0.0
	_eff_afterburner_speed_pct = 0.0
	_eff_afterburner_fuel_cost = 0.0
	_eff_afterburner_efficiency_pct = 0.0
	_eff_flare_unlocked = false
	_eff_laser_combat = false
	_eff_spike_ram = false
	_eff_spike_ram_damage_pct = 0.0
	_eff_stunt_pilot = false
	_eff_barrel_roll_speed_pct = 0.0
	_eff_bullet_time = false
	_eff_bullet_time_scale = 1.0
	_eff_turret_cool_rate = 0.25
	turret_heat_per_shot = 0.09
	_shield_ready = false
	_shield_timer = 0.0

# ── Gem sync for skill tree ────────────────────────────────────────────────────

## Get total gem count across all types.
func _get_total_gems() -> int:
	var total: int = 0
	for type in gem_inventory:
		total += int(gem_inventory.get(type, 0))
	return total

## Add gems of a specific type with capacity check.
func _add_to_inventory(type: String, count: int) -> void:
	if count <= 0:
		return
	var current_total: int = _get_total_gems()
	if current_total >= _eff_gem_capacity:
		return  # Cargo full
	var room: int = _eff_gem_capacity - current_total
	var to_add: int = mini(count, room)
	if not gem_inventory.has(type):
		gem_inventory[type] = 0
	gem_inventory[type] += to_add

## Remove gems from inventory (preferring common types first).
func _remove_from_inventory(count: int) -> void:
	var remaining: int = count
	for type in GemTypeData.TYPES:
		var available: int = gem_inventory.get(type, 0)
		var take: int = mini(available, remaining)
		if take > 0:
			gem_inventory[type] = available - take
			remaining -= take
		if remaining <= 0:
			break

## Clamp the gem inventory to the current capacity, removing from common types first.
func _clamp_inventory_to_capacity() -> void:
	var total: int = _get_total_gems()
	if total > _eff_gem_capacity:
		_remove_from_inventory(total - _eff_gem_capacity)
		gems_changed.emit(gem_inventory)

func get_gems() -> int:
	return _get_total_gems()

## Get the full inventory dictionary.
func get_gem_inventory() -> Dictionary:
	return gem_inventory.duplicate()

## Add gems of a specific type.
func add_gems_of_type(type: String, count: int) -> void:
	var prev_total: int = _get_total_gems()
	_add_to_inventory(type, count)
	if _get_total_gems() != prev_total:
		gems_changed.emit(gem_inventory)

## Legacy: add a flat number of gems (all go to Green).
func add_gems(amount: int) -> void:
	add_gems_of_type("green", amount)

## Set the full inventory from a dictionary (e.g. when syncing from PlayerSkills).
func set_gem_inventory(inventory: Dictionary) -> void:
	gem_inventory = inventory.duplicate()
	# Ensure all keys exist
	for type in GemTypeData.TYPES:
		if not gem_inventory.has(type):
			gem_inventory[type] = 0
	gems_changed.emit(gem_inventory)

## Legacy: set a flat gem count (replaces inventory with all Green).
func set_gems(amount: int) -> void:
	var new_inv: Dictionary = GemTypeData.empty_inventory()
	new_inv["green"] = clamp(amount, 0, _eff_gem_capacity)
	gem_inventory = new_inv
	gems_changed.emit(gem_inventory)
