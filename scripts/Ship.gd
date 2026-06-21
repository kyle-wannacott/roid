extends CharacterBody3D
## Player-controlled spaceship — 2D-ish ground-level flight.
##
## The ship is locked to a single altitude (`ground_height`) and
## steers with W/S (thrust), A/D (yaw) and Q/E (roll). It mines
## asteroids with the laser, runs out of fuel, and gets reeled back
## to the station by a harpoon when stranded.
##
## Controls (project.godot):
##   W / Up     — forward thrust
##   S / Down   — reverse thrust
##   A / Left   — yaw left
##   D / Right  — yaw right
##   Q          — roll left
##   E          — roll right
##   F / LMB    — fire mining laser (or fire harpoon when out of fuel)
##   H          — fire harpoon (when out of fuel)
##   R / Esc    — respawn at station
##
## Feel:
##   • Body pitches nose-down when accelerating, nose-up when reversing.
##   • Wings bank into turns.
##   • Beacon flashes green→yellow→red as health drops.
##   • Wing-tip lights form a diagetic fuel bar.
##   • State machine: FLYING / STRANDED / HARPOON_FLY / HARPOON_REEL / DOCKED.

signal fuel_changed(fuel: float, max_fuel: float)
signal gems_changed(count: int)
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
@export var laser_range: float = 15.0
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
var _eff_laser_range: float = 35.0
var _eff_laser_width: float = 0.22
var _eff_laser_chain_count: int = 0
var _eff_laser_damage_mult: float = 1.0
var _eff_mining_cone_dot: float = 0.92
var _eff_harpoon_reel_speed: float = 18.0
var _eff_fuel_per_thrust: float = 4.0
var _eff_fuel_per_mine: float = 6.0
var _eff_gem_heal: int = 0
var _eff_bonus_gems: int = 0
var _eff_solar_regen: float = 0.0
var _eff_turret_cool_rate: float = 0.35  # base cool rate (overridden by skills)
var _eff_nanobot_heal: float = 0.0
var _eff_nanobot_interval: float = 0.0
var _eff_shield_cooldown: float = 0.0
var _eff_afterburner_speed_pct: float = 0.0
var _eff_afterburner_fuel_cost: float = 0.0
var _eff_afterburner_efficiency_pct: float = 0.0

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
var gems: int = 0
var _eff_gem_capacity: int = 50  # Base max gems before skills
var _eff_gem_pickup_bonus: float = 0.0
var _eff_gem_attract_bonus: float = 0.0
var _eff_magnet_speed_mult: float = 1.0
var mining_active: bool = false
var can_mine: bool = false
var current_target: Node3D = null
var state: State = State.FLYING
var harpoon_station: Node3D = null
var harpoon_anchor: Vector3 = Vector3.ZERO
var harpoon_progress: float = 0.0
var dock_cooldown: float = 0.0
var _afterburner_active: bool = false
var _nanobot_timer: float = 0.0

# Diagetic visual nodes (created in _ready)
var _shield_mesh: MeshInstance3D = null
var _shield_shader_mat: ShaderMaterial = null
@export var shield_color: Color = Color(0.3, 0.6, 1.0)
var _solar_panel_left: MeshInstance3D = null
var _solar_panel_right: MeshInstance3D = null
var _turret_mount: MeshInstance3D = null
var _missile_pod_left: MeshInstance3D = null
var _missile_pod_right: MeshInstance3D = null
var _missile_ammo_left: bool = false
var _missile_ammo_right: bool = false
var _missile_cooldown: float = 0.0
@export var missile_scene: PackedScene = preload("res://scenes/Missile.tscn")
@export var missile_fire_cooldown: float = 0.5
@export var missile_speed: float = 80.0
@export var missile_lifetime: float = 3.0
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
@export var turret_heat_per_shot: float = 0.06
@export var turret_cool_per_sec: float = 0.35
@export var turret_fire_rate: float = 0.10
var _turret_fire_remaining: float = 0.0
var _turret_barrel_mats: Array[StandardMaterial3D] = []
var _turret_default_color: Color = Color(0.2, 0.2, 0.25, 1)
var _afterburner_particles: GPUParticles3D = null
var _afterburner_trail: MeshInstance3D = null
var _cargo_bay: MeshInstance3D = null
var _magnet_ring: MeshInstance3D = null
var _magnet_field: MeshInstance3D = null

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

# Barrel-roll state (Q/E one-shot 360° spins).
var _barrel_roll_dir: int = 0   # 0 = none, 1 = left, -1 = right
var _barrel_roll_progress: float = 0.0
@export var barrel_roll_duration: float = 0.6


func _ready() -> void:
	add_to_group("ship")
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
	_update_diagetic_visuals()  # Apply current skill states to new visuals

	# Initial HUD gem capacity display
	gems_changed.emit(gems)

	laser.visible = false
	laser_hit.visible = false
	harpoon_claw.visible = false
	harpoon_cable.visible = false

	# Snap to the ground height on start.
	global_position.y = ground_height

	fuel_changed.emit(fuel, _eff_fuel_max)
	gems_changed.emit(gems)
	health_changed.emit(health, _eff_max_health)
	state_changed.emit(state)


func _physics_process(delta: float) -> void:
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
		var spin: float = TAU * _barrel_roll_dir * delta / barrel_roll_duration
		rotate_object_local(Vector3.FORWARD, spin)
		_barrel_roll_progress += delta / barrel_roll_duration
		if _barrel_roll_progress >= 1.0:
			_barrel_roll_dir = 0
			_barrel_roll_progress = 0.0
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
		# Solar regen only when not thrusting
		var any_thrust_input: bool = thrust_forward > 0.01 or thrust_back > 0.01
		if not any_thrust_input:
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
		elif roll_right_just:
			_barrel_roll_dir = -1
			_barrel_roll_progress = 0.0

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
		_turret_heat = min(1.0, _turret_heat + turret_heat_per_shot)
		_turret_fire_remaining = turret_fire_rate

	# --- Wing‑pod missiles (separate from turret) ---------------
	# Missiles are fired on the `missile_fire` action (G key) so the
	# player has both weapons without one stealing the other.
	_missile_cooldown = max(0.0, _missile_cooldown - delta)
	if Input.is_action_just_pressed("missile_fire") \
			and turret_unlocked_now \
			and _missile_cooldown <= 0.0:
		var any_missile: bool = false
		if _missile_ammo_left and _missile_pod_left:
			_fire_missile_from_pod(_missile_pod_left)
			_missile_ammo_left = false
			any_missile = true
		if _missile_ammo_right and _missile_pod_right:
			_fire_missile_from_pod(_missile_pod_right)
			_missile_ammo_right = false
			any_missile = true
		if any_missile:
			SoundManager.play_by_id("sfx_turret_fire")
			_missile_cooldown = missile_fire_cooldown

	# Refill missile ammo when docked at the station.
	if state == State.DOCKED:
		_missile_ammo_left = true
		_missile_ammo_right = true

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

	_update_mining(want_mine, delta)
	_set_engine_glow(abs(want_forward))
	_attract_nearby_gems()

	# Out of fuel → strand the ship.
	if fuel <= 0.0:
		fuel = 0.0
		_set_state(State.STRANDED)

	# Auto-dock only when the ship has slowed down inside the station
	# zone. Flying through at speed won't grab it.
	_try_auto_dock()

	fuel_changed.emit(fuel, _eff_fuel_max)
	speed_changed.emit(velocity.length())
	can_mine = current_target != null and state == State.FLYING
	mining_state_changed.emit(mining_active and can_mine, can_mine)


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
	var to_anchor: Vector3 = harpoon_anchor - global_position
	to_anchor.y = 0.0
	var dist: float = to_anchor.length()
	if dist < 1.2:
		velocity = Vector3.ZERO
		global_position = harpoon_anchor
		global_position.y = ground_height
		harpoon_claw.visible = false
		harpoon_cable.visible = false
		fuel = _eff_fuel_max
		health = _eff_max_health
		_shield_ready = _eff_shield_cooldown > 0.0
		_shield_timer = 0.0
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
	# Keep the ship pinned to the dock.
	if harpoon_station != null and is_instance_valid(harpoon_station):
		global_position = harpoon_station.global_position + harpoon_target_offset
		global_position.y = ground_height

	# Refuel + heal while docked.
	var prev_fuel: float = fuel
	var prev_health: float = health
	fuel = min(_eff_fuel_max, fuel + dock_refuel_rate * delta)
	health = min(_eff_max_health, health + dock_heal_rate * delta)

	# As soon as we're topped up, start the dock cooldown so the
	# player can fly away without being immediately dragged back.
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

	# Manual launch: any forward/back thrust input pushes the ship
	# clear of the dock and hands control back. This prevents the
	# FLYING/DOCKED flicker when the player is just trying to fly
	# past the station.
	# Don't launch while the skill tree or any editor overlay is
	# visible — prevents accidental input while editing skills.
	if not _can_launch():
		return
	var thrust_forward: float = Input.get_action_strength("thrust_forward")
	var thrust_back: float = Input.get_action_strength("thrust_back")
	if abs(thrust_forward) > 0.01 or abs(thrust_back) > 0.01:
		_launch()

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
		_missile_ammo_left = true
		_missile_ammo_right = true


# ---------------------------------------------------------------------
# Docking logic
# ---------------------------------------------------------------------

func _try_auto_dock() -> void:
	if state != State.FLYING and state != State.STRANDED:
		return
	# Don't auto-dock during the post-refuel/post-launch cooldown —
	# otherwise the ship gets dragged straight back the moment the
	# player tries to fly away.
	if dock_cooldown > 0.0:
		return
	# Only dock if we're moving slowly — flying through the zone at
	# speed shouldn't grab us.
	if velocity.length() > auto_dock_speed:
		return
	for s in get_tree().get_nodes_in_group("station"):
		if not is_instance_valid(s):
			continue
		if s.has_method("is_ship_docked") and s.is_ship_docked(self):
			var dock_pos: Vector3 = s.global_position + harpoon_target_offset
			dock_pos.y = ground_height
			global_position = dock_pos
			velocity = Vector3.ZERO
			harpoon_station = s
			harpoon_claw.visible = false
			harpoon_cable.visible = false
			_set_state(State.DOCKED)
			# Play dock sound
			SoundManager.play_by_id("sfx_dock")
			return


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
	dock_cooldown = dock_cooldown_duration
	_set_state(State.FLYING)


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

	var can_fire: bool = want_mine and fuel > fuel_per_mine * delta and ast_idx >= 0

	if not can_fire:
		mining_active = false
		laser.visible = false
		laser_hit.visible = false
		return

	mining_active = true
	laser.visible = true
	laser_hit.visible = true

	fuel = max(0.0, fuel - fuel_per_mine * delta)

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
	# Auto-cleanup after a brief flash
	var t := get_tree().create_timer(0.25)
	t.timeout.connect(func():
		if is_instance_valid(mi):
			mi.queue_free()
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
		if engine_glow_mat:
			engine_glow_mat.emission = Color(0.4, 0.7, 1.0)
		if wing_bar_left_mat:
			wing_bar_left_mat.emission = Color(0.4, 0.7, 1.0)
		if wing_bar_right_mat:
			wing_bar_right_mat.emission = Color(0.4, 0.7, 1.0)
	else:
		if engine_glow_mat:
			engine_glow_mat.emission = Color(0.4, 0.7, 1, 1)
	if engine_glow_mat:
		engine_glow_mat.emission_energy_multiplier = main_e


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
	for gem in get_tree().get_nodes_in_group("gems"):
		if not is_instance_valid(gem):
			continue
		if not (gem.get("being_attracted") as bool):
			continue
		if global_position.distance_to(gem.global_position) < gem_pickup_radius + _eff_gem_pickup_bonus:
			# Only collect the gem if we have room in the cargo hold.
			# Gems stay orbiting the ship until capacity frees up.
			if gems < _eff_gem_capacity:
				gem.collect()
				# Play gem collect sound
				SoundManager.play_by_id("sfx_gem_collect")
				gems += 1
				gems_changed.emit(gems)
				# Gem heal from nanobot_gem_heal skill (only when actually collected)
				if _eff_gem_heal > 0 and health < _eff_max_health:
					health = min(_eff_max_health, health + _eff_gem_heal)
					health_changed.emit(health, _eff_max_health)
	
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
func _fire_missile_from_pod(pod: MeshInstance3D) -> void:
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
	# Hide the corresponding pod until rearmed.
	pod.visible = false


## Fire one shot from the turret.  Spawns a bullet from each barrel
## (alternating left/right) flying forward in the ship's facing
## direction.  Also plays the muzzle flash and sound.
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
	# Pick a barrel — alternate between the two so fire looks even.
	var idx: int = _turret_barrel_pick % barrels.size()
	var barrel: MeshInstance3D = barrels[idx]
	_turret_barrel_pick += 1
	var b: Node3D = bullet_scene.instantiate() as Node3D
	if b == null:
		return
	# Position the bullet at the barrel tip in world space.
	var tip: Vector3 = barrel.global_position + (-barrel.global_transform.basis.y * 0.3)
	get_tree().current_scene.add_child(b)
	b.global_position = tip
	# Orient the bullet to face the ship's forward direction.
	b.global_rotation = global_rotation
	if b.has_method("set_flight_params"):
		b.set_flight_params(120.0, 1.5)


## Update the diagetic barrel colour to reflect the current heat.
## 0.0  → cool dark‑metal grey
## 0.6+ → warm orange
## 1.0  → bright red (overheated)
func _update_turret_barrel_color() -> void:
	if _turret_barrel_mats.is_empty():
		return
	var hot: Color = Color(1.0, 0.25, 0.1, 1)
	var normal: Color = _turret_default_color
	# Two‑stage ramp: cool → warm orange → red.
	var t: float = clamp(_turret_heat, 0.0, 1.0)
	var col: Color
	if t < 0.5:
		col = normal.lerp(Color(1.0, 0.7, 0.2), t * 2.0)
	else:
		col = Color(1.0, 0.7, 0.2).lerp(hot, (t - 0.5) * 2.0)
	for mat in _turret_barrel_mats:
		if mat == null:
			continue
		mat.albedo_color = col
		mat.emission = col * (0.5 + t * 2.0)
		mat.emission_energy_multiplier = 0.5 + t * 3.0


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
	respawn_at_station()


# ---------------------------------------------------------------------
# Respawn
# ---------------------------------------------------------------------

func respawn_at_station() -> void:
	_apply_skill_stats()
	velocity = Vector3.ZERO
	global_transform = start_transform
	global_position.y = ground_height
	fuel = _eff_fuel_max
	health = _eff_max_health
	harpoon_claw.visible = false
	harpoon_cable.visible = false
	harpoon_station = null
	_set_state(State.FLYING)
	_nanobot_timer = 0.0
	_shield_ready = _eff_shield_cooldown > 0.0
	_shield_timer = 0.0
	fuel_changed.emit(fuel, _eff_fuel_max)
	health_changed.emit(health, _eff_max_health)


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
	for wing in [wing_left, wing_right]:
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
	for panel in [_solar_panel_left, _solar_panel_right]:
		if panel:
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
	
	# --- Missile pods: small boxes on the wing tips ---
	for wing_pos in [Vector3(-1.55, 0.05, 0), Vector3(1.55, 0.05, 0)]:
		var pod := MeshInstance3D.new()
		var pod_mesh := BoxMesh.new()
		pod_mesh.size = Vector3(0.12, 0.12, 0.5)
		pod.mesh = pod_mesh
		var pod_mat := StandardMaterial3D.new()
		pod_mat.albedo_color = Color(0.4, 0.15, 0.15, 1)
		pod_mat.metallic = 0.6
		pod_mat.roughness = 0.4
		pod_mat.emission_enabled = true
		pod_mat.emission = Color(0.6, 0.1, 0.1, 1)
		pod_mat.emission_energy_multiplier = 0.5
		pod.material_override = pod_mat
		pod.position = wing_pos
		pod.visible = false
		body_root.add_child(pod)
		if wing_pos.x < 0:
			_missile_pod_left = pod
		else:
			_missile_pod_right = pod
		# Add 3 small missile tubes inside each pod (visible visual)
		for i in range(3):
			var tube := MeshInstance3D.new()
			var tube_mesh := CylinderMesh.new()
			tube_mesh.top_radius = 0.025
			tube_mesh.bottom_radius = 0.03
			tube_mesh.height = 0.35
			tube.mesh = tube_mesh
			var tube_mat := StandardMaterial3D.new()
			tube_mat.albedo_color = Color(0.7, 0.6, 0.5, 1)
			tube_mat.emission_enabled = true
			tube_mat.emission = Color(0.8, 0.2, 0.1, 1)
			tube_mat.emission_energy_multiplier = 0.3
			tube.material_override = tube_mat
			tube.position = Vector3(0, 0, -0.05 + i * 0.05)
			tube.rotation = Vector3(PI * 0.5, 0, 0)
			pod.add_child(tube)
	
	# --- Afterburner particle trail ---
	_afterburner_particles = GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 0, 1)  # emit backward (ship faces -Z, so behind is +Z)
	pm.spread = 15.0
	pm.initial_velocity_min = 12.0
	pm.initial_velocity_max = 18.0
	pm.gravity = Vector3.ZERO
	pm.damping_min = 1.0
	pm.damping_max = 1.5
	pm.scale_min = 0.15
	pm.scale_max = 0.35
	pm.color = Color(0.4, 0.8, 1.0, 0.9)
	_afterburner_particles.process_material = pm
	var pm_mesh := SphereMesh.new()
	pm_mesh.radius = 0.08
	pm_mesh.height = 0.16
	_afterburner_particles.draw_pass_1 = pm_mesh
	_afterburner_particles.amount = 80
	_afterburner_particles.lifetime = 0.5
	_afterburner_particles.emitting = false
	_afterburner_particles.position = Vector3(0, 0, 1.2)
	body_root.add_child(_afterburner_particles)
	
	# --- Cargo Bay (undercarriage that grows with gem capacity skills) ---
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
	_magnet_ring = MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.13
	ring_mesh.outer_radius = 0.18
	_magnet_ring.mesh = ring_mesh
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(0.9, 0.3, 0.5, 1)
	ring_mat.metallic = 0.6
	ring_mat.roughness = 0.4
	ring_mat.emission_enabled = true
	ring_mat.emission = Color(0.7, 0.2, 0.4, 1)
	ring_mat.emission_energy_multiplier = 0.6
	_magnet_ring.material_override = ring_mat
	# Position it on the front of the ship, above the laser
	_magnet_ring.position = Vector3(0, 0.45, -1.2)
	_magnet_ring.visible = false
	body_root.add_child(_magnet_ring)

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
	# Visible when any missile-related skill is unlocked AND that
	# wing's missile has ammo (hidden after firing until rearm).
	var missile_unlocked := PlayerSkills and (
		PlayerSkills.is_unlocked("missile_unlock") or
		PlayerSkills.is_unlocked("missile_heat_seeking") or
		PlayerSkills.is_unlocked("missile_splash_area") or
		PlayerSkills.is_unlocked("turret_unlock")
	)
	if _missile_pod_left:
		_missile_pod_left.visible = missile_unlocked and _missile_ammo_left
	if _missile_pod_right:
		_missile_pod_right.visible = missile_unlocked and _missile_ammo_right
	
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
	if not _afterburner_particles:
		return
	_afterburner_particles.emitting = _afterburner_active
	# Change particle color based on whether afterburner is active
	var pm: ParticleProcessMaterial = _afterburner_particles.process_material as ParticleProcessMaterial
	if _afterburner_active:
		pm.color = Color(0.5, 0.8, 1.0, 0.9)  # bright blue-white
	else:
		pm.color = Color(0.3, 0.4, 0.6, 0.5)  # dim blue

# ── Skill integration ──────────────────────────────────────────────────────────

func _on_skill_unlocked(_skill_id: String) -> void:
	_apply_skill_stats()


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
	_eff_fuel_per_mine = max(1.0, _eff_fuel_per_mine - float(mining_fuel_red))

	# Turret cool rate — base 0.35/s, improved by skills.
	_eff_turret_cool_rate = 0.35
	if PlayerSkills.is_unlocked("turret_rapid_fire"):
		_eff_turret_cool_rate += 0.25
	if PlayerSkills.is_unlocked("turret_rapid_fire_2"):
		_eff_turret_cool_rate += 0.30
	if PlayerSkills.is_unlocked("turret_rapid_fire_3"):
		_eff_turret_cool_rate += 0.50
	# Turret heat‑per‑shot — skills reduce heat build‑up.
	if PlayerSkills.is_unlocked("turret_rapid_fire"):
		turret_heat_per_shot = 0.04
	if PlayerSkills.is_unlocked("turret_rapid_fire_2"):
		turret_heat_per_shot = 0.025
	if PlayerSkills.is_unlocked("turret_rapid_fire_3"):
		turret_heat_per_shot = 0.015
	
	# Gem Yield
	if PlayerSkills.is_unlocked("mining_yield"): _eff_bonus_gems += 1
	if PlayerSkills.is_unlocked("mining_yield_2"): _eff_bonus_gems += 2
	
	# Gem Capacity (cargo hold)
	var gem_cap_bonus := 0
	if PlayerSkills.is_unlocked("gem_capacity"): gem_cap_bonus += 25
	if PlayerSkills.is_unlocked("gem_capacity_2"): gem_cap_bonus += 50
	if PlayerSkills.is_unlocked("gem_capacity_3"): gem_cap_bonus += 100
	_eff_gem_capacity = 50 + gem_cap_bonus
	# Clamp current gems to new capacity
	gems = min(gems, _eff_gem_capacity)
	
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
	# Laser Width
	_eff_laser_width = 0.22
	if PlayerSkills.is_unlocked("laser_width"): _eff_laser_width = 0.45
	if PlayerSkills.is_unlocked("laser_width_2"): _eff_laser_width = 0.70
	# Mining cone gets wider with Wide Beam so off-axis asteroids can be hit
	_eff_mining_cone_dot = 0.92
	if PlayerSkills.is_unlocked("laser_width"): _eff_mining_cone_dot = 0.80
	if PlayerSkills.is_unlocked("laser_width_2"): _eff_mining_cone_dot = 0.65
	# Laser Chain
	_eff_laser_chain_count = 0
	if PlayerSkills.is_unlocked("laser_chain"): _eff_laser_chain_count = 1
	if PlayerSkills.is_unlocked("laser_chain_2"): _eff_laser_chain_count = 2
	# Laser Power (multiplicative damage bonus)
	_eff_laser_damage_mult = 1.0
	if PlayerSkills.is_unlocked("laser_power"): _eff_laser_damage_mult += 0.5
	if PlayerSkills.is_unlocked("laser_power_2"): _eff_laser_damage_mult += 1.0
	
	# Harpoon upgrades
	_eff_harpoon_reel_speed = harpoon_reel_speed
	if PlayerSkills.is_unlocked("harpoon_speed"): _eff_harpoon_reel_speed += 5
	if PlayerSkills.is_unlocked("harpoon_speed_2"): _eff_harpoon_reel_speed += 5
	
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
	_eff_turret_cool_rate = 0.35
	turret_heat_per_shot = 0.06
	_shield_ready = false
	_shield_timer = 0.0

# ── Gem sync for skill tree ────────────────────────────────────────────────────

func get_gems() -> int:
	return gems

func set_gems(amount: int) -> void:
	# Clamp to effective capacity
	gems = clamp(amount, 0, _eff_gem_capacity)
	gems_changed.emit(gems)
