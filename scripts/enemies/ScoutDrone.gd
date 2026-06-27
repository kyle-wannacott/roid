extends BaseEnemy
class_name ScoutDrone

## Fast, agile scout drone. Patrols in groups and fires quick bursts.

@export_group("Scout Behavior")
@export var patrol_speed: float = 25.0  # Slower than player so they can be caught
@export var chase_speed: float = 45.0   # Slightly slower than player max speed
@export var flee_speed: float = 50.0    # Similar to player speed
@export var flee_health_threshold: float = 0.3
@export var strafe_speed: float = 30.0
@export var strafe_change_interval: float = 2.0

## Patrol radius (and leash): the enemy guards a 100m bubble around its
## spawn. If the player strays beyond `leash_distance` from `_spawn_position`
## the enemy breaks off chase and returns to its spawn to resume patrolling.
## This stops enemies from chasing the player all the way back to the
## station — they only care about threats inside their own patch of space.
const LEASH_DISTANCE: float = 110.0

## Movement states
enum State {
	PATROL,
	CHASE,
	STRAFE,
	FLEE,
}

var state: State = State.PATROL
var _patrol_target: Vector3 = Vector3.ZERO
var _strafe_direction: Vector3 = Vector3.FORWARD
var _strafe_timer: float = 0.0
var _state_timer: float = 0.0

## Visual components (from scene)
@onready var _body_mesh: MeshInstance3D = $Body/Hull
@onready var _wing_left: MeshInstance3D = $Body/WingLeft
@onready var _wing_right: MeshInstance3D = $Body/WingRight
@onready var _engine_glow: OmniLight3D = $Body/EngineGlow

func _ready() -> void:
	# Scout stats
	max_health = 30.0
	move_speed = patrol_speed
	reward_gem_table = {"green": 3}
	projectile_damage = 5.0
	fire_rate = 0.8
	detection_range = LEASH_DISTANCE  # See the player at the leash boundary
	attack_range = 60.0

	super._ready()

	_upgrade_visuals()
	# NOTE: `_spawn_position` is set by the EnemyManager AFTER positioning
	# the enemy, via `set_spawn_position()`. It cannot be captured here in
	# `_ready()` because `global_position` is still the manager's position
	# (origin) at this point — the manager hasn't set the real position yet.


func _upgrade_visuals() -> void:
	var body_root = get_node_or_null("Body")
	if body_root == null:
		return

	# 1) Sleek alien purple-metallic drone body
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.2, 0.18, 0.28, 1.0)
	body_mat.metallic = 0.95
	body_mat.roughness = 0.18
	if _body_mesh != null:
		_body_mesh.material_override = body_mat

	# 2) Wing material
	var wing_mat := StandardMaterial3D.new()
	wing_mat.albedo_color = Color(0.25, 0.25, 0.32, 1.0)
	wing_mat.metallic = 0.9
	wing_mat.roughness = 0.25
	if _wing_left != null:
		_wing_left.material_override = wing_mat
	if _wing_right != null:
		_wing_right.material_override = wing_mat

	# 3) Glowing engine thrusters
	var engine_mat := StandardMaterial3D.new()
	engine_mat.albedo_color = Color(0.1, 0.7, 1.0, 1.0)
	engine_mat.metallic = 0.5
	engine_mat.roughness = 0.2
	engine_mat.emission_enabled = true
	engine_mat.emission = Color(0.0, 0.8, 1.0, 1.0) # bright blue-cyan emission
	engine_mat.emission_energy_multiplier = 3.0

	var engine_l := body_root.get_node_or_null("EngineLeft") as MeshInstance3D
	var engine_r := body_root.get_node_or_null("EngineRight") as MeshInstance3D
	if engine_l != null:
		engine_l.material_override = engine_mat
	if engine_r != null:
		engine_r.material_override = engine_mat

	# 4) Add engine nozzles (rocket thruster housings)
	var nozzle_mat := StandardMaterial3D.new()
	nozzle_mat.albedo_color = Color(0.12, 0.12, 0.15, 1.0)
	nozzle_mat.metallic = 0.95
	nozzle_mat.roughness = 0.3

	for offset_x in [-0.3, 0.3]:
		var nozzle := MeshInstance3D.new()
		var nozzle_mesh := CylinderMesh.new()
		nozzle_mesh.top_radius = 0.16
		nozzle_mesh.bottom_radius = 0.18
		nozzle_mesh.height = 0.18
		nozzle.mesh = nozzle_mesh
		nozzle.material_override = nozzle_mat
		nozzle.position = Vector3(offset_x, 0, 0.55)
		nozzle.rotation = Vector3(PI * 0.5, 0, 0)
		body_root.add_child(nozzle)

	# 5) Front glowing sensor lens (red camera eye)
	var eye := MeshInstance3D.new()
	var eye_mesh := SphereMesh.new()
	eye_mesh.radius = 0.06
	eye_mesh.height = 0.12
	eye.mesh = eye_mesh
	var eye_mat := StandardMaterial3D.new()
	eye_mat.albedo_color = Color(1.0, 0.1, 0.1, 1.0)
	eye_mat.emission_enabled = true
	eye_mat.emission = Color(1.0, 0.2, 0.2, 1.0) # glowing red sensor eye
	eye_mat.emission_energy_multiplier = 4.0
	eye.material_override = eye_mat
	eye.position = Vector3(0, 0, -0.62)
	body_root.add_child(eye)

	# 6) Dual rear-pointing antennas on the wing tips
	for i in [-1, 1]:
		var ant := MeshInstance3D.new()
		var ant_mesh := CylinderMesh.new()
		ant_mesh.top_radius = 0.005
		ant_mesh.bottom_radius = 0.015
		ant_mesh.height = 0.35
		ant.mesh = ant_mesh
		var ant_mat := StandardMaterial3D.new()
		ant_mat.albedo_color = Color(0.85, 0.45, 0.15, 1.0) # copper-plated antenna
		ant_mat.metallic = 1.0
		ant_mat.roughness = 0.3
		ant.material_override = ant_mat
		ant.position = Vector3(1.0 * i, 0, 0.1)
		# Point backwards and slightly angled outwards
		ant.rotation = Vector3(PI * 0.4, 0.15 * i, 0)
		body_root.add_child(ant)

func _update_enemy(delta: float) -> void:
	_state_timer += delta

	# Update state based on conditions
	_update_state()

	# Execute state behavior
	match state:
		State.PATROL:
			_update_patrol(delta)
		State.CHASE:
			_update_chase(delta)
		State.STRAFE:
			_update_strafe(delta)
		State.FLEE:
			_update_flee(delta)

	# Fire at player if in attack range
	_try_fire()
	
	# Keep in bounds
	_clamp_to_arena()
	
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

	# Check for flee condition (don't break out of flee for leash — low
	# HP always takes priority)
	if health / max_health <= flee_health_threshold:
		if state != State.FLEE:
			state = State.FLEE
			_state_timer = 0.0
			return

	match state:
		State.PATROL:
			# Only engage if the player is both visible AND inside our
			# patrol bubble. Otherwise stay on patrol.
			if dist_to_player <= detection_range and not out_of_leash:
				state = State.CHASE
				_state_timer = 0.0

		State.CHASE:
			if out_of_leash or dist_to_player > detection_range * 1.5:
				# Player left our territory — disengage and return to spawn.
				state = State.PATROL
				_state_timer = 0.0
				_pick_new_patrol_target()
			elif dist_to_player <= attack_range:
				state = State.STRAFE
				_state_timer = 0.0

		State.STRAFE:
			if out_of_leash or dist_to_player > attack_range * 1.5:
				# Player left our territory — disengage and return to spawn.
				state = State.PATROL
				_state_timer = 0.0
				_pick_new_patrol_target()
			elif _state_timer > 3.0:
				# Alternate between strafing and chasing
				state = State.CHASE
				_state_timer = 0.0

		State.FLEE:
			if health / max_health > flee_health_threshold + 0.1:
				state = State.CHASE
				_state_timer = 0.0
			elif _state_timer > 4.0:
				# Stop fleeing after a while
				state = State.PATROL
				_state_timer = 0.0

func _update_patrol(delta: float) -> void:
	# Move toward patrol target
	var dist = global_position.distance_to(_patrol_target)
	if dist < 10.0:
		_pick_new_patrol_target()

	move_to_position(_patrol_target, patrol_speed, delta)

func _update_chase(delta: float) -> void:
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
	move_to_position(target.global_position, chase_speed, delta)

func _update_strafe(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return

	_strafe_timer -= delta
	if _strafe_timer <= 0:
		_strafe_timer = strafe_change_interval
		# Random strafe direction perpendicular to player
		var to_player = (target.global_position - global_position).normalized()
		_strafe_direction = Vector3(-to_player.z, 0, to_player.x)
		if randf() > 0.5:
			_strafe_direction = -_strafe_direction

	# Move sideways while facing player
	face_target(delta)
	var move_dir = _strafe_direction

	# Also maintain optimal distance
	var dist = get_distance_to_player()
	if dist > attack_range * 1.2:
		move_dir += (target.global_position - global_position).normalized() * 0.3
	elif dist < attack_range * 0.8:
		move_dir -= (target.global_position - global_position).normalized() * 0.3

	velocity = move_dir.normalized() * strafe_speed
	move_and_slide()

func _update_flee(delta: float) -> void:
	if _ship == null or not is_instance_valid(_ship):
		return

	move_from_position(_ship.global_position, flee_speed, delta)

func _try_fire() -> void:
	if _fire_timer > 0:
		return

	if not is_target_in_range(attack_range):
		return

	if target == null or not is_instance_valid(target):
		return

	# Check if facing target
	var to_target = (target.global_position - global_position).normalized()
	var forward = -global_transform.basis.z
	var dot = forward.dot(to_target)

	if dot > 0.8:  # Roughly facing target
		_fire_projectile()
		_fire_timer = 1.0 / fire_rate

func _fire_projectile() -> void:
	var bullet = EnemyBullet.new()
	if bullet == null:
		return

	# Create mesh for the bullet
	var mesh = SphereMesh.new()
	mesh.radius = 0.2
	mesh.height = 0.4
	bullet.mesh = mesh

	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.2, 0.2)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.2, 0.2)
	mat.emission_energy_multiplier = 2.0
	bullet.material_override = mat

	# Add to scene FIRST, then set global_position
	get_tree().current_scene.add_child(bullet)
	bullet.global_position = global_position + (-global_transform.basis.z * 2.0)

	# Aim at target with some lead
	var to_target = target.global_position - global_position
	var predicted_pos = target.global_position
	if "velocity" in target:
		predicted_pos += target.velocity * (to_target.length() / projectile_speed)

	var direction = global_position.direction_to(predicted_pos)
	bullet.velocity = direction * projectile_speed
	bullet.damage = projectile_damage

func _pick_new_patrol_target() -> void:
	# Patrol a ~100m bubble around the spawn (80-120m for slight variation).
	# The leash on `LEASH_DISTANCE` in `_update_state` keeps the enemy
	# inside this territory — it breaks off chase and returns here the
	# moment the player strays beyond the leash.
	_patrol_target = _compute_patrol_target(80.0, 120.0)

func _clamp_to_arena() -> void:
	# No longer clamping - enemies now freely chase the player
	pass


## Redirect away from station — switch to patrol and pick a target
## that heads back outward.
func break_off_from_station() -> void:
	state = State.PATROL
	_state_timer = 0.0
	_pick_new_patrol_target()

func _spawn_death_effect() -> void:
	# Create a simple explosion effect
	var explosion = OmniLight3D.new()
	explosion.light_color = Color(1.0, 0.5, 0.2)
	explosion.light_energy = 5.0
	explosion.omni_range = 10.0
	# Add to scene FIRST, then set global_position
	get_tree().current_scene.add_child(explosion)
	explosion.global_position = global_position

	# Animate and remove
	var tween = create_tween()
	tween.tween_property(explosion, "light_energy", 0.0, 0.3)
	tween.tween_callback(explosion.queue_free)

	queue_free()
