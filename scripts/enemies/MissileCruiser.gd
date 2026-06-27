extends BaseEnemy
class_name MissileCruiser

## Medium-range ship that fires homing missiles and maintains distance.

@export_group("Cruiser Behavior")
@export var patrol_speed: float = 20.0  # Slow patrol
@export var cruise_speed: float = 35.0  # Moderate approach
@export var retreat_speed: float = 45.0  # Can escape but player can catch
@export var optimal_distance: float = 200.0
@export var missile_damage: float = 15.0
@export var missile_speed: float = 120.0
@export var missile_turn_rate: float = 2.5
@export var missile_lifetime: float = 5.0
@export var missiles_per_volley: int = 2
@export var volley_cooldown: float = 3.0

## Patrol radius (and leash): the enemy guards a 100m bubble around its
## spawn. If the player strays beyond `leash_distance` from `_spawn_position`
## the enemy breaks off chase and returns to its spawn to resume patrolling.
const LEASH_DISTANCE: float = 110.0

## Movement states
enum State {
	PATROL,
	APPROACH,
	MAINTAIN_DISTANCE,
	RETREAT,
}

var state: State = State.PATROL
var _patrol_target: Vector3 = Vector3.ZERO
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
	reward_gem_table = {"blue": 2, "yellow": 1}
	fire_rate = 0.5
	detection_range = LEASH_DISTANCE  # See the player at the leash boundary
	attack_range = 70.0
	
	super._ready()
	
	# Collect missile pods
	_missile_pods = [_missile_pod_left, _missile_pod_right]

	_upgrade_visuals()
	# NOTE: `_spawn_position` is set by the EnemyManager AFTER positioning
	# the enemy, via `set_spawn_position()`. It cannot be captured here in
	# `_ready()` because `global_position` is still the manager's position
	# (origin) at this point — the manager hasn't set the real position yet.


func _upgrade_visuals() -> void:
	var body_root = get_node_or_null("Body")
	if body_root == null:
		return

	# 1) Crimson-red military steel hull
	var hull_mat := StandardMaterial3D.new()
	hull_mat.albedo_color = Color(0.42, 0.16, 0.18, 1.0)
	hull_mat.metallic = 0.9
	hull_mat.roughness = 0.3
	if _hull_mesh != null:
		_hull_mesh.material_override = hull_mat

	# 2) Dark graphite material for pods
	var pod_mat := StandardMaterial3D.new()
	pod_mat.albedo_color = Color(0.18, 0.18, 0.22, 1.0)
	pod_mat.metallic = 0.95
	pod_mat.roughness = 0.3
	
	for pod in _missile_pods:
		if pod != null:
			var pod_mesh = pod.get_node_or_null("Pod") as MeshInstance3D
			if pod_mesh != null:
				pod_mesh.material_override = pod_mat
			
			# Give missile tubes a glowing copper launch interior
			var tube_mat := StandardMaterial3D.new()
			tube_mat.albedo_color = Color(0.85, 0.45, 0.15, 1.0)
			tube_mat.metallic = 1.0
			tube_mat.roughness = 0.2
			tube_mat.emission_enabled = true
			tube_mat.emission = Color(0.7, 0.2, 0.05, 1.0) # ready to launch heat glow
			tube_mat.emission_energy_multiplier = 0.8
			
			for tube_name in ["Tube1", "Tube2"]:
				var tube = pod.get_node_or_null(tube_name) as MeshInstance3D
				if tube != null:
					tube.material_override = tube_mat

	# 3) Radar dish - golden communications array
	if _radar_dish != null:
		var radar_mat := StandardMaterial3D.new()
		radar_mat.albedo_color = Color(0.75, 0.6, 0.25, 1.0)
		radar_mat.metallic = 1.0
		radar_mat.roughness = 0.25
		radar_mat.emission_enabled = true
		radar_mat.emission = Color(0.35, 0.25, 0.05, 1.0)
		radar_mat.emission_energy_multiplier = 0.5
		_radar_dish.material_override = radar_mat
		
		# Add a glowing red radar beacon light on top
		var beacon := MeshInstance3D.new()
		var beacon_mesh := SphereMesh.new()
		beacon_mesh.radius = 0.04
		beacon_mesh.height = 0.08
		beacon.mesh = beacon_mesh
		var beacon_mat := StandardMaterial3D.new()
		beacon_mat.albedo_color = Color(1.0, 0.2, 0.2, 1.0)
		beacon_mat.emission_enabled = true
		beacon_mat.emission = Color(1.0, 0.2, 0.2, 1.0)
		beacon_mat.emission_energy_multiplier = 4.0
		beacon.material_override = beacon_mat
		beacon.position = Vector3(0, 0.15, 0)
		_radar_dish.add_child(beacon)

	# 4) Glowing engines - purple/pink rocket exhaust
	var engine_mat := StandardMaterial3D.new()
	engine_mat.albedo_color = Color(0.8, 0.15, 1.0, 1.0)
	engine_mat.metallic = 0.5
	engine_mat.roughness = 0.2
	engine_mat.emission_enabled = true
	engine_mat.emission = Color(0.6, 0.1, 1.0, 1.0)
	engine_mat.emission_energy_multiplier = 3.5
	if _engine_left != null:
		_engine_left.material_override = engine_mat
	if _engine_right != null:
		_engine_right.material_override = engine_mat

	# 5) Engine nozzles (rocket bells)
	var nozzle_mat := StandardMaterial3D.new()
	nozzle_mat.albedo_color = Color(0.12, 0.12, 0.15, 1.0)
	nozzle_mat.metallic = 0.95
	nozzle_mat.roughness = 0.45
	
	for offset_x in [-0.5, 0.5]:
		var nozzle := MeshInstance3D.new()
		var nozzle_mesh := CylinderMesh.new()
		nozzle_mesh.top_radius = 0.18
		nozzle_mesh.bottom_radius = 0.23
		nozzle_mesh.height = 0.22
		nozzle.mesh = nozzle_mesh
		nozzle.material_override = nozzle_mat
		nozzle.position = Vector3(offset_x, 0, 1.35)
		nozzle.rotation = Vector3(PI * 0.5, 0, 0)
		body_root.add_child(nozzle)

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
				state = State.MAINTAIN_DISTANCE
				_state_timer = 0.0
			elif dist_to_player > detection_range * 1.5:
				state = State.PATROL
				_state_timer = 0.0

		State.MAINTAIN_DISTANCE:
			if out_of_leash:
				state = State.PATROL
				_state_timer = 0.0
				_pick_new_patrol_target()
			elif dist_to_player < optimal_distance * 0.6:
				state = State.RETREAT
				_state_timer = 0.0
			elif dist_to_player > optimal_distance * 1.5:
				state = State.APPROACH
				_state_timer = 0.0

		State.RETREAT:
			if out_of_leash:
				state = State.PATROL
				_state_timer = 0.0
				_pick_new_patrol_target()
			elif dist_to_player >= optimal_distance:
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
	move_to_position(target.global_position, cruise_speed, delta)

func _update_maintain_distance(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	
	face_target(delta)
	
	# Maintain distance - strafe sideways, don't orbit
	var to_player = (target.global_position - global_position)
	to_player.y = 0.0
	var dist = to_player.length()
	
	# Move to maintain optimal distance
	if dist > optimal_distance * 1.1:
		move_to_position(target.global_position, cruise_speed * 0.5, delta)
	elif dist < optimal_distance * 0.9:
		move_from_position(target.global_position, cruise_speed * 0.5, delta)
	else:
		# Strafe perpendicular to player
		var perpendicular = Vector3(-to_player.z, 0, to_player.x).normalized()
		velocity = perpendicular * cruise_speed * 0.3
		move_and_slide()
	
	# Maintain correct height
	global_position.y = 1.5

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
	mat.albedo_color = Color(0.65, 0.15, 0.15) # rich military crimson
	mat.metallic = 0.8
	mat.roughness = 0.25
	missile.material_override = mat
	
	# Engine glow
	var glow = OmniLight3D.new()
	glow.light_color = Color(1.0, 0.4, 0.2)
	glow.light_energy = 2.0
	glow.omni_range = 3.0
	glow.position = Vector3(0, 0, 0.5)
	missile.add_child(glow)

	# Homing missile trail particles (fiery red/purple)
	var trail := CPUParticles3D.new()
	trail.amount = 30
	trail.lifetime = 0.3
	trail.explosiveness = 0.0
	trail.randomness = 0.2
	trail.position = Vector3(0, 0, 0.45)
	
	var part_mesh := SphereMesh.new()
	part_mesh.radius = 0.04
	part_mesh.height = 0.08
	trail.mesh = part_mesh
	
	trail.direction = Vector3(0, 0, 1) # shoot straight back
	trail.spread = 10.0
	trail.gravity = Vector3.ZERO
	trail.initial_velocity_min = 4.0
	trail.initial_velocity_max = 6.0
	
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 1.0))
	scale_curve.add_point(Vector2(1.0, 0.1))
	trail.scale_amount_curve = scale_curve
	
	var gradient := Gradient.new()
	gradient.add_point(0.0, Color(1.0, 0.3, 0.1, 1.0))  # red-hot core
	gradient.add_point(0.2, Color(0.6, 0.1, 0.8, 0.8))  # purple flame
	gradient.add_point(0.6, Color(0.25, 0.15, 0.3, 0.3)) # dark smoke
	gradient.add_point(1.0, Color(0.1, 0.1, 0.1, 0.0))  # fade
	trail.color_ramp = gradient
	
	var part_mat := StandardMaterial3D.new()
	part_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	part_mat.vertex_color_use_as_albedo = true
	part_mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	trail.material_override = part_mat
	
	missile.add_child(trail)
	trail.emitting = true
	
	# Find a missile pod to fire from
	var pod_pos = global_position
	if _missile_pods.size() > 0:
		var pod = _missile_pods[_missiles_fired % _missile_pods.size()]
		pod_pos = pod.global_position
	
	# Initial direction toward target
	var direction = (target.global_position - pod_pos).normalized()
	missile.velocity = direction * missile_speed
	missile.set_target(target)
	missile.damage = missile_damage
	missile.turn_rate = missile_turn_rate
	missile.lifetime = missile_lifetime
	missile.speed = missile_speed
	
	# Add to scene FIRST, then set global_position
	get_tree().current_scene.add_child(missile)
	missile.global_position = pod_pos

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
	# Medium explosion
	var explosion = OmniLight3D.new()
	explosion.light_color = Color(1.0, 0.4, 0.1)
	explosion.light_energy = 6.0
	explosion.omni_range = 12.0
	# Add to scene FIRST, then set global_position
	get_tree().current_scene.add_child(explosion)
	explosion.global_position = global_position
	
	var tween = create_tween()
	tween.tween_property(explosion, "light_energy", 0.0, 0.4)
	tween.tween_callback(explosion.queue_free)
	
	queue_free()
