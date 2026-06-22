extends BaseEnemy
class_name ScoutDrone

## Fast, agile scout drone. Patrols in groups and fires quick bursts.

@export_group("Scout Behavior")
@export var patrol_speed: float = 80.0
@export var chase_speed: float = 150.0
@export var flee_speed: float = 200.0
@export var flee_health_threshold: float = 0.3
@export var strafe_speed: float = 60.0
@export var strafe_change_interval: float = 2.0

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
var _spawn_position: Vector3 = Vector3.ZERO

## Visual components (from scene)
@onready var _body_mesh: MeshInstance3D = $Body/Hull
@onready var _wing_left: MeshInstance3D = $Body/WingLeft
@onready var _wing_right: MeshInstance3D = $Body/WingRight
@onready var _engine_glow: OmniLight3D = $Body/EngineGlow

func _ready() -> void:
	# Scout stats
	max_health = 30.0
	move_speed = patrol_speed
	reward_gems = 3
	projectile_damage = 5.0
	fire_rate = 0.8
	detection_range = 150.0
	attack_range = 120.0
	
	super._ready()
	
	_spawn_position = global_position
	_pick_new_patrol_target()

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

func _update_state() -> void:
	if not is_alive:
		return
	
	var dist_to_player = get_distance_to_player()
	
	# Check for flee condition
	if health / max_health <= flee_health_threshold:
		if state != State.FLEE:
			state = State.FLEE
			_state_timer = 0.0
			return
	
	match state:
		State.PATROL:
			if dist_to_player <= detection_range:
				state = State.CHASE
				_state_timer = 0.0
		
		State.CHASE:
			if dist_to_player > detection_range * 1.5:
				state = State.PATROL
				_state_timer = 0.0
			elif dist_to_player <= attack_range:
				state = State.STRAFE
				_state_timer = 0.0
		
		State.STRAFE:
			if dist_to_player > attack_range * 1.5:
				state = State.CHASE
				_state_timer = 0.0
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
	
	# Setup bullet
	bullet.global_position = global_position + (-global_transform.basis.z * 2.0)
	
	# Aim at target with some lead
	var to_target = target.global_position - global_position
	var predicted_pos = target.global_position
	if "velocity" in target:
		predicted_pos += target.velocity * (to_target.length() / projectile_speed)
	
	var direction = global_position.direction_to(predicted_pos)
	bullet.velocity = direction * projectile_speed
	bullet.damage = projectile_damage
	
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
	
	get_tree().current_scene.add_child(bullet)

func _pick_new_patrol_target() -> void:
	# Pick a random point within patrol radius of spawn
	var angle = randf() * TAU
	var radius = randf_range(20.0, 50.0)
	_patrol_target = _spawn_position + Vector3(cos(angle) * radius, 0, sin(angle) * radius)

func _clamp_to_arena() -> void:
	# Keep enemy from going too far from spawn
	var dist_from_spawn = global_position.distance_to(_spawn_position)
	if dist_from_spawn > 100.0:
		# Steer back toward spawn
		var back_dir = (_spawn_position - global_position).normalized()
		velocity += back_dir * 20.0
		move_and_slide()

func _spawn_death_effect() -> void:
	# Create a simple explosion effect
	var explosion = OmniLight3D.new()
	explosion.light_color = Color(1.0, 0.5, 0.2)
	explosion.light_energy = 5.0
	explosion.omni_range = 10.0
	explosion.global_position = global_position
	get_tree().current_scene.add_child(explosion)
	
	# Animate and remove
	var tween = create_tween()
	tween.tween_property(explosion, "light_energy", 0.0, 0.3)
	tween.tween_callback(explosion.queue_free)
	
	queue_free()
