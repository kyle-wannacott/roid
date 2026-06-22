extends BaseEnemy
class_name MissileCruiser

## Medium-range ship that fires homing missiles and maintains distance.

@export_group("Cruiser Behavior")
@export var patrol_speed: float = 50.0
@export var cruise_speed: float = 80.0
@export var retreat_speed: float = 120.0
@export var optimal_distance: float = 200.0
@export var missile_damage: float = 15.0
@export var missile_speed: float = 120.0
@export var missile_turn_rate: float = 2.5
@export var missile_lifetime: float = 5.0
@export var missiles_per_volley: int = 2
@export var volley_cooldown: float = 3.0

## Movement states
enum State {
	PATROL,
	APPROACH,
	MAINTAIN_DISTANCE,
	RETREAT,
}

var state: State = State.PATROL
var _patrol_target: Vector3 = Vector3.ZERO
var _spawn_position: Vector3 = Vector3.ZERO
var _state_timer: float = 0.0
var _missiles_fired: int = 0

## Visual components (from scene)
@onready var _hull_mesh: MeshInstance3D = $Body/Hull
@onready var _missile_pod_left: Node3D = $Body/MissilePodLeft
@onready var _missile_pod_right: Node3D = $Body/MissilePodRight
@onready var _radar_dish: MeshInstance3D = $Body/RadarDish
@onready var _engine_left: MeshInstance3D = $Body/EngineLeft
@onready var _engine_right: MeshInstance3D = $Body/EngineRight

var _missile_pods: Array[Node3D] = []

func _ready() -> void:
	# Cruiser stats
	max_health = 60.0
	move_speed = patrol_speed
	reward_gems = 10
	fire_rate = 0.5
	detection_range = 250.0
	attack_range = 200.0
	
	super._ready()
	
	# Collect missile pods
	_missile_pods = [_missile_pod_left, _missile_pod_right]
	
	_spawn_position = global_position
	_pick_new_patrol_target()

func _update_enemy(delta: float) -> void:
	_state_timer += delta
	
	# Update radar rotation
	if _radar_dish:
		_radar_dish.rotation.y += delta * 3.0
	
	# Update state
	_update_state()
	
	# Execute state behavior
	match state:
		State.PATROL:
			_update_patrol(delta)
		State.APPROACH:
			_update_approach(delta)
		State.MAINTAIN_DISTANCE:
			_update_maintain_distance(delta)
		State.RETREAT:
			_update_retreat(delta)
	
	# Try to fire missiles
	_try_fire_missiles()

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
				state = State.MAINTAIN_DISTANCE
				_state_timer = 0.0
			elif dist_to_player > detection_range * 1.5:
				state = State.PATROL
				_state_timer = 0.0
		
		State.MAINTAIN_DISTANCE:
			if dist_to_player < optimal_distance * 0.6:
				state = State.RETREAT
				_state_timer = 0.0
			elif dist_to_player > optimal_distance * 1.5:
				state = State.APPROACH
				_state_timer = 0.0
		
		State.RETREAT:
			if dist_to_player >= optimal_distance:
				state = State.MAINTAIN_DISTANCE
				_state_timer = 0.0
			elif _state_timer > 3.0:
				state = State.MAINTAIN_DISTANCE
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
	move_to_position(target.global_position, cruise_speed, delta)

func _update_maintain_distance(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	
	face_target(delta)
	
	# Circle while maintaining distance
	orbit_around(target.global_position, optimal_distance, 0.3, delta)

func _update_retreat(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	
	# Move away from player
	move_from_position(target.global_position, retreat_speed, delta)

func _try_fire_missiles() -> void:
	if _fire_timer > 0:
		return
	
	if not is_target_in_range(attack_range):
		return
	
	if target == null or not is_instance_valid(target):
		return
	
	# Fire volley of missiles
	_missiles_fired = 0
	_fire_missile_volley()

func _fire_missile_volley() -> void:
	if _missiles_fired >= missiles_per_volley:
		_missiles_fired = 0
		_fire_timer = volley_cooldown
		return
	
	# Fire one missile
	_fire_homing_missile()
	_missiles_fired += 1
	
	# Schedule next missile
	if _missiles_fired < missiles_per_volley:
		get_tree().create_timer(0.3).timeout.connect(_fire_missile_volley)

func _fire_homing_missile() -> void:
	var missile = HomingMissile.new()
	if missile == null:
		return
	
	# Create mesh for the missile
	var mesh = CylinderMesh.new()
	mesh.top_radius = 0.05
	mesh.bottom_radius = 0.1
	mesh.height = 0.8
	missile.mesh = mesh
	missile.rotation.x = PI / 2
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 0.2, 0.2)
	mat.metallic = 0.5
	missile.material_override = mat
	
	# Engine glow
	var glow = OmniLight3D.new()
	glow.light_color = Color(1.0, 0.5, 0.2)
	glow.light_energy = 1.0
	glow.omni_range = 2.0
	glow.position = Vector3(0, 0, 0.5)
	missile.add_child(glow)
	
	# Find a missile pod to fire from
	var pod_pos = global_position
	if _missile_pods.size() > 0:
		var pod = _missile_pods[_missiles_fired % _missile_pods.size()]
		pod_pos = pod.global_position
	
	missile.global_position = pod_pos
	
	# Initial direction toward target
	var direction = (target.global_position - pod_pos).normalized()
	missile.velocity = direction * missile_speed
	missile.set_target(target)
	missile.damage = missile_damage
	missile.turn_rate = missile_turn_rate
	missile.lifetime = missile_lifetime
	missile.speed = missile_speed
	
	get_tree().current_scene.add_child(missile)

func _pick_new_patrol_target() -> void:
	var angle = randf() * TAU
	var radius = randf_range(40.0, 80.0)
	_patrol_target = _spawn_position + Vector3(cos(angle) * radius, 0, sin(angle) * radius)

func _spawn_death_effect() -> void:
	# Medium explosion
	var explosion = OmniLight3D.new()
	explosion.light_color = Color(1.0, 0.4, 0.1)
	explosion.light_energy = 6.0
	explosion.omni_range = 12.0
	explosion.global_position = global_position
	get_tree().current_scene.add_child(explosion)
	
	var tween = create_tween()
	tween.tween_property(explosion, "light_energy", 0.0, 0.4)
	tween.tween_callback(explosion.queue_free)
	
	queue_free()
