extends BaseEnemy
class_name HeavyGunship

## Slow, tanky gunship with multiple turrets. Fires sustained volleys.

@export_group("Gunship Behavior")
@export var patrol_speed: float = 15.0  # Slow tanky ship
@export var chase_speed: float = 30.0   # Slow pursuit
@export var optimal_distance: float = 120.0
@export var turret_count: int = 2
@export var burst_count: int = 5
@export var burst_delay: float = 0.15
@export var volley_cooldown: float = 2.0

## Patrol radius (and leash): the enemy guards a 100m bubble around its
## spawn. If the player strays beyond `leash_distance` from `_spawn_position`
## the enemy breaks off chase and returns to its spawn to resume patrolling.
const LEASH_DISTANCE: float = 110.0

## Movement states
enum State {
	PATROL,
	APPROACH,
	FIRE,
	REPOSITION,
}

var state: State = State.PATROL
var _patrol_target: Vector3 = Vector3.ZERO
var _state_timer: float = 0.0
var _burst_counter: int = 0
var _burst_timer: float = 0.0
var _is_firing: bool = false
var _current_turret: int = 0

## Visual components (from scene)
@onready var _hull_mesh: MeshInstance3D = $Body/Hull
@onready var _turret_left: Node3D = $Body/TurretLeft
@onready var _turret_right: Node3D = $Body/TurretRight
@onready var _shield_ring: MeshInstance3D = $Body/ShieldRing
@onready var _engine_left: MeshInstance3D = $Body/EngineLeft
@onready var _engine_right: MeshInstance3D = $Body/EngineRight

var _turret_nodes: Array[Node3D] = []

func _ready() -> void:
	# Gunship stats
	max_health = 80.0
	move_speed = patrol_speed
	reward_gem_table = {"green": 2, "blue": 1}
	projectile_damage = 8.0
	fire_rate = 2.0  # Shots per second
	detection_range = LEASH_DISTANCE  # See the player at the leash boundary
	attack_range = 50.0
	
	super._ready()
	
	# Collect turret nodes
	_turret_nodes = [_turret_left, _turret_right]

	_upgrade_visuals()
	# NOTE: `_spawn_position` is set by the EnemyManager AFTER positioning
	# the enemy, via `set_spawn_position()`. It cannot be captured here in
	# `_ready()` because `global_position` is still the manager's position
	# (origin) at this point — the manager hasn't set the real position yet.


func _upgrade_visuals() -> void:
	var body_root = get_node_or_null("Body")
	if body_root == null:
		return

	# 1) Heavy weathered steel plate material for hull
	var hull_mat := StandardMaterial3D.new()
	hull_mat.albedo_color = Color(0.24, 0.25, 0.28, 1.0)
	hull_mat.metallic = 0.9
	hull_mat.roughness = 0.45
	if _hull_mesh != null:
		_hull_mesh.material_override = hull_mat

	# 2) Gold/Bronze metallic trim material
	var trim_mat := StandardMaterial3D.new()
	trim_mat.albedo_color = Color(0.7, 0.55, 0.25, 1.0) # bronze-gold trim
	trim_mat.metallic = 0.95
	trim_mat.roughness = 0.35

	# 3) Heavy gun turrets - dark graphite titanium
	var turret_mat := StandardMaterial3D.new()
	turret_mat.albedo_color = Color(0.15, 0.15, 0.18, 1.0)
	turret_mat.metallic = 0.95
	turret_mat.roughness = 0.3
	
	for turret in _turret_nodes:
		if turret != null:
			var base = turret.get_node_or_null("Base") as MeshInstance3D
			var barrel = turret.get_node_or_null("Barrel") as MeshInstance3D
			if base != null:
				base.material_override = turret_mat
			if barrel != null:
				barrel.material_override = turret_mat

	# 4) Shield generator ring - electric blue energy field
	if _shield_ring != null:
		var shield_mat := StandardMaterial3D.new()
		shield_mat.albedo_color = Color(0.1, 0.5, 1.0, 0.15)
		shield_mat.metallic = 0.1
		shield_mat.roughness = 0.1
		shield_mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
		shield_mat.cull_mode = StandardMaterial3D.CULL_DISABLED
		shield_mat.emission_enabled = true
		shield_mat.emission = Color(0.0, 0.6, 1.0, 1.0)
		shield_mat.emission_energy_multiplier = 1.8
		_shield_ring.material_override = shield_mat

	# 5) Glowing engines
	var engine_mat := StandardMaterial3D.new()
	engine_mat.albedo_color = Color(0.0, 0.6, 1.0, 1.0)
	engine_mat.metallic = 0.5
	engine_mat.roughness = 0.2
	engine_mat.emission_enabled = true
	engine_mat.emission = Color(0.0, 0.7, 1.0, 1.0)
	engine_mat.emission_energy_multiplier = 3.5
	if _engine_left != null:
		_engine_left.material_override = engine_mat
	if _engine_right != null:
		_engine_right.material_override = engine_mat

	# 6) Large rocket engine exhaust nozzles (dark graphite steel)
	var nozzle_mat := StandardMaterial3D.new()
	nozzle_mat.albedo_color = Color(0.1, 0.1, 0.12, 1.0)
	nozzle_mat.metallic = 0.95
	nozzle_mat.roughness = 0.4
	
	for offset_x in [-0.8, 0.8]:
		var nozzle := MeshInstance3D.new()
		var nozzle_mesh := CylinderMesh.new()
		nozzle_mesh.top_radius = 0.22
		nozzle_mesh.bottom_radius = 0.28
		nozzle_mesh.height = 0.3
		nozzle.mesh = nozzle_mesh
		nozzle.material_override = nozzle_mat
		nozzle.position = Vector3(offset_x, 0, 1.6)
		nozzle.rotation = Vector3(PI * 0.5, 0, 0)
		body_root.add_child(nozzle)

	# 7) Add heavy armor plates on top of the hull for structural detail
	for offset_x in [-0.9, 0.9]:
		var plate := MeshInstance3D.new()
		var plate_mesh := BoxMesh.new()
		plate_mesh.size = Vector3(0.18, 0.3, 1.6)
		plate.mesh = plate_mesh
		plate.material_override = trim_mat
		plate.position = Vector3(offset_x, 0.3, 0.0)
		body_root.add_child(plate)

func _update_enemy(delta: float) -> void:
	_state_timer += delta
	
	# Update burst firing
	if _is_firing:
		_burst_timer -= delta
		if _burst_timer <= 0:
			_fire_from_turret(_current_turret)
			_burst_counter += 1
			_current_turret = (_current_turret + 1) % turret_count
			
			if _burst_counter >= burst_count:
				_is_firing = false
				_burst_counter = 0
				_fire_timer = volley_cooldown
			else:
				_burst_timer = burst_delay
	
	# Update state
	_update_state()
	
	# Execute state behavior
	match state:
		State.PATROL:
			_update_patrol(delta)
		State.APPROACH:
			_update_approach(delta)
		State.FIRE:
			_update_fire(delta)
		State.REPOSITION:
			_update_reposition(delta)
	
	# Maintain correct height (same as player ship)
	global_position.y = 1.5

func _update_state() -> void:
	if not is_alive:
		return

	var dist_to_player = get_distance_to_player()
	# Leash check: how far is the player from our spawn point? If the
	# player strays beyond LEASH_DISTANCE the enemy gives up entirely
	# and returns to patrol, no matter what state it was in.
	var dist_player_to_spawn: float = _distance_player_to_spawn()
	var out_of_leash: bool = dist_player_to_spawn > LEASH_DISTANCE

	match state:
		State.PATROL:
			# Only engage if the player is both visible AND inside our
			# patrol bubble. Otherwise stay on patrol.
			if dist_to_player <= detection_range and not out_of_leash:
				state = State.APPROACH
				_state_timer = 0.0

		State.APPROACH:
			if out_of_leash:
				state = State.PATROL
				_state_timer = 0.0
				_pick_new_patrol_target()
			elif dist_to_player <= optimal_distance:
				state = State.FIRE
				_state_timer = 0.0
			elif dist_to_player > detection_range * 1.5:
				state = State.PATROL
				_state_timer = 0.0

		State.FIRE:
			if out_of_leash or dist_to_player > optimal_distance * 1.5:
				state = State.PATROL
				_state_timer = 0.0
				_pick_new_patrol_target()
			elif _state_timer > 4.0:
				state = State.REPOSITION
				_state_timer = 0.0

		State.REPOSITION:
			if out_of_leash:
				state = State.PATROL
				_state_timer = 0.0
				_pick_new_patrol_target()
			elif _state_timer > 2.0:
				if dist_to_player <= attack_range:
					state = State.FIRE
				else:
					state = State.APPROACH
				_state_timer = 0.0

func _update_patrol(delta: float) -> void:
	var dist = global_position.distance_to(_patrol_target)
	if dist < 10.0:
		_pick_new_patrol_target()
	
	move_to_position(_patrol_target, patrol_speed, delta)

func _update_approach(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	
	# Only break off if WE have entered the station zone — not just
	# because the player happens to be near the station. The player
	# should be able to engage enemies even while flying near the hub.
	# EnemyManager._check_enemies_near_station handles the case where
	# we follow the player all the way in.
	if is_near_station():
		state = State.PATROL
		_state_timer = 0.0
		_pick_new_patrol_target()
		return
	
	face_target(delta)
	
	# Move to optimal distance
	var dist = get_distance_to_player()
	if dist > optimal_distance:
		move_to_position(target.global_position, chase_speed, delta)

func _update_fire(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	
	# Face target
	face_target(delta)
	
	# Start firing if ready
	if not _is_firing and _fire_timer <= 0:
		_is_firing = true
		_burst_counter = 0
		_current_turret = 0
		_burst_timer = 0.0

func _update_reposition(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	
	# Move to a new position at optimal distance (not continuous orbiting)
	var to_player = (target.global_position - global_position)
	to_player.y = 0.0
	var dist = to_player.length()
	
	# If too far, approach; if too close, retreat
	if dist > optimal_distance * 1.2:
		move_to_position(target.global_position, chase_speed, delta)
	elif dist < optimal_distance * 0.8:
		move_from_position(target.global_position, chase_speed, delta)
	else:
		# Strafe sideways
		var perpendicular = Vector3(-to_player.z, 0, to_player.x).normalized()
		velocity = perpendicular * chase_speed * 0.5
		move_and_slide()
	
	# Maintain correct height
	global_position.y = 1.5

func _fire_from_turret(turret_idx: int) -> void:
	if turret_idx >= _turret_nodes.size():
		return
	
	var turret = _turret_nodes[turret_idx]
	var turret_pos = turret.global_position
	
	# Create projectile
	var bullet = _create_projectile()
	if bullet == null:
		return
	
	# Aim at target
	var to_target = target.global_position - turret_pos
	# Add some lead
	if "velocity" in target:
		to_target += target.velocity * (to_target.length() / projectile_speed)
	
	var direction = to_target.normalized()
	
	# Add slight spread
	direction.x += randf_range(-0.05, 0.05)
	direction.z += randf_range(-0.05, 0.05)
	direction = direction.normalized()
	
	# Add to scene FIRST, then set global_position
	get_tree().current_scene.add_child(bullet)
	bullet.global_position = turret_pos
	bullet.velocity = direction * projectile_speed
	bullet.damage = projectile_damage

func _create_projectile() -> Node3D:
	var bullet = EnemyBullet.new()
	if bullet == null:
		return null
	
	# Create mesh for the bullet
	var mesh = BoxMesh.new()
	mesh.size = Vector3(0.15, 0.15, 0.6)
	bullet.mesh = mesh
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.2, 0.2)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.2, 0.2)
	mat.emission_energy_multiplier = 2.0
	bullet.material_override = mat
	
	bullet.damage = projectile_damage
	bullet.speed = projectile_speed
	
	return bullet

func _pick_new_patrol_target() -> void:
	# Patrol a ~100m bubble around the spawn (80-120m for slight variation).
	# The leash on `LEASH_DISTANCE` in `_update_state` keeps the enemy
	# inside this territory — it breaks off chase and returns here the
	# moment the player strays beyond the leash.
	_patrol_target = _compute_patrol_target(80.0, 120.0)


## Redirect away from station — switch to patrol.
func break_off_from_station() -> void:
	state = State.PATROL
	_state_timer = 0.0
	_pick_new_patrol_target()

func _spawn_death_effect() -> void:
	# Large explosion for gunship
	var explosion = OmniLight3D.new()
	explosion.light_color = Color(1.0, 0.6, 0.2)
	explosion.light_energy = 8.0
	explosion.omni_range = 15.0
	# Add to scene FIRST, then set global_position
	get_tree().current_scene.add_child(explosion)
	explosion.global_position = global_position
	
	var tween = create_tween()
	tween.tween_property(explosion, "light_energy", 0.0, 0.5)
	tween.tween_callback(explosion.queue_free)
	
	queue_free()
