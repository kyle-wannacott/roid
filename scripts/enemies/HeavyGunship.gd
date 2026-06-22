extends BaseEnemy
class_name HeavyGunship

## Slow, tanky gunship with multiple turrets. Fires sustained volleys.

@export_group("Gunship Behavior")
@export var patrol_speed: float = 40.0
@export var chase_speed: float = 60.0
@export var optimal_distance: float = 120.0
@export var turret_count: int = 2
@export var burst_count: int = 5
@export var burst_delay: float = 0.15
@export var volley_cooldown: float = 2.0

## Movement states
enum State {
	PATROL,
	APPROACH,
	FIRE,
	REPOSITION,
}

var state: State = State.PATROL
var _patrol_target: Vector3 = Vector3.ZERO
var _spawn_position: Vector3 = Vector3.ZERO
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
	reward_gems = 8
	projectile_damage = 8.0
	fire_rate = 2.0  # Shots per second
	detection_range = 180.0
	attack_range = 150.0
	
	super._ready()
	
	# Collect turret nodes
	_turret_nodes = [_turret_left, _turret_right]
	
	_spawn_position = global_position
	_pick_new_patrol_target()

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

func _update_state() -> void:
	if not is_alive:
		return
	
	var dist_to_player = get_distance_to_player()
	
	match state:
		State.PATROL:
			if dist_to_player <= detection_range:
				state = State.APPROACH
				_state_timer = 0.0
		
		State.APPROACH:
			if dist_to_player <= optimal_distance:
				state = State.FIRE
				_state_timer = 0.0
			elif dist_to_player > detection_range * 1.5:
				state = State.PATROL
				_state_timer = 0.0
		
		State.FIRE:
			if dist_to_player > optimal_distance * 1.5:
				state = State.REPOSITION
				_state_timer = 0.0
			elif _state_timer > 4.0:
				state = State.REPOSITION
				_state_timer = 0.0
		
		State.REPOSITION:
			if _state_timer > 2.0:
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
	
	# Circle around player while repositioning
	orbit_around(target.global_position, optimal_distance, 0.5, delta)

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
	
	bullet.global_position = turret_pos
	bullet.velocity = direction * projectile_speed
	bullet.damage = projectile_damage
	
	get_tree().current_scene.add_child(bullet)

func _create_projectile() -> Node3D:
	var bullet = EnemyBullet.new()
	if bullet == null:
		return null
	
	# Create mesh for the bullet
	var mesh = BoxMesh.new()
	mesh.size = Vector3(0.15, 0.15, 0.6)
	bullet.mesh = mesh
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.8, 0.2)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.8, 0.2)
	mat.emission_energy_multiplier = 2.0
	bullet.material_override = mat
	
	bullet.damage = projectile_damage
	bullet.speed = projectile_speed
	
	return bullet

func _pick_new_patrol_target() -> void:
	var angle = randf() * TAU
	var radius = randf_range(30.0, 60.0)
	_patrol_target = _spawn_position + Vector3(cos(angle) * radius, 0, sin(angle) * radius)

func _spawn_death_effect() -> void:
	# Large explosion for gunship
	var explosion = OmniLight3D.new()
	explosion.light_color = Color(1.0, 0.6, 0.2)
	explosion.light_energy = 8.0
	explosion.omni_range = 15.0
	explosion.global_position = global_position
	get_tree().current_scene.add_child(explosion)
	
	var tween = create_tween()
	tween.tween_property(explosion, "light_energy", 0.0, 0.5)
	tween.tween_callback(explosion.queue_free)
	
	queue_free()
