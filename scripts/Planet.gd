extends Node3D
class_name Planet

## A planet with gravity that pulls in nearby ships and enemies.
## Spawns mineable orbiting asteroids for visual flair and gameplay.

signal body_entered_gravity(body: Node3D)
signal body_exited_gravity(body: Node3D)

@export_group("Planet Visuals")
@export var planet_radius: float = 100.0:
	set(v):
		planet_radius = v
		if is_inside_tree():
			_rebuild_mesh()
@export var rim_color: Color = Color(0.7, 0.5, 0.3)
@export var animation_speed: float = 0.25
@export var distortion_strength: float = 0.3
@export var rim_brightness: float = 1.0

@export_group("Gravity")
## Radius at which gravity starts affecting bodies
@export var gravity_radius: float = 400.0
## Gravitational strength multiplier (higher = stronger pull)
@export var gravity_strength: float = 500.0
## How much the gravity affects the player (0.0 = none, 1.0 = full)
@export var player_gravity_factor: float = 0.7

@export_group("Orbital Asteroids")
@export var asteroid_count: int = 30
## Minimum orbit radius as a multiple of planet_radius (1.5 = 1.5x planet size)
@export var orbit_radius_min_factor: float = 1.5
## Maximum orbit radius as a multiple of planet_radius
@export var orbit_radius_max_factor: float = 3.5
@export var asteroid_scale_min: float = 1.5
@export var asteroid_scale_max: float = 4.0
## Health for orbital asteroids
@export var asteroid_health: float = 30.0
## Max gems dropped per orbital asteroid
@export var asteroid_gem_count: int = 2

## Bodies currently within the gravity field
var _tracked_bodies: Array[Node3D] = []
var _tracked_rigids: Array[RigidBody3D] = []

## Orbital asteroid data: [{node, body, angle, radius, speed, tilt, health, alive}]
var _orbital_asteroids: Array[Dictionary] = []

## Visual mesh
var _mesh_instance: MeshInstance3D
var _shader_material: ShaderMaterial
var _gravity_area: Area3D

## Planet collision body
var _collision_body: StaticBody3D
var _collision_shape: CollisionShape3D

## RNG
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	
	# Build the planet sphere with shader
	_rebuild_mesh()
	
	# Planet collision body (so the player/enemies can't fly through)
	_collision_body = StaticBody3D.new()
	_collision_body.name = "PlanetCollision"
	_collision_body.collision_layer = 2    # match ship's collision_mask
	_collision_body.collision_mask = 1     # detect ship on layer 1
	add_child(_collision_body)
	
	_collision_shape = CollisionShape3D.new()
	var col_sphere := SphereShape3D.new()
	col_sphere.radius = planet_radius
	_collision_shape.shape = col_sphere
	_collision_body.add_child(_collision_shape)
	
	# Gravity detection area
	_gravity_area = Area3D.new()
	_gravity_area.name = "GravityArea"
	_gravity_area.collision_layer = 0       # doesn't need to be detected
	_gravity_area.collision_mask = 1 | 4    # detect ship (layer 1) and enemies (layer 4)
	add_child(_gravity_area)
	
	var area_shape := CollisionShape3D.new()
	var detect_sphere := SphereShape3D.new()
	detect_sphere.radius = gravity_radius
	area_shape.shape = detect_sphere
	_gravity_area.add_child(area_shape)
	
	_gravity_area.body_entered.connect(_on_body_entered)
	_gravity_area.body_exited.connect(_on_body_exited)
	
	# Spawn orbital asteroids
	_spawn_orbital_asteroids()
	
	add_to_group("planets")


func _rebuild_mesh() -> void:
	# Remove old mesh if it exists
	if _mesh_instance:
		_mesh_instance.queue_free()
	
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "PlanetMesh"
	var sphere := SphereMesh.new()
	sphere.radius = planet_radius
	sphere.height = planet_radius * 2.0
	_mesh_instance.mesh = sphere
	
	# Apply shader — shader radius matches the mesh exactly
	_shader_material = ShaderMaterial.new()
	var shader := preload("res://shaders/planet_shader.gdshader")
	_shader_material.shader = shader
	_shader_material.set_shader_parameter("radius", planet_radius)
	_shader_material.set_shader_parameter("rimColor", rim_color)
	_shader_material.set_shader_parameter("animationSpeed", animation_speed)
	_shader_material.set_shader_parameter("distortionStrength", distortion_strength)
	_shader_material.set_shader_parameter("rimBrightness", rim_brightness)
	_mesh_instance.material_override = _shader_material
	add_child(_mesh_instance)
	
	# Also update collision if it exists
	if _collision_shape and _collision_shape.shape is SphereShape3D:
		(_collision_shape.shape as SphereShape3D).radius = planet_radius


func _spawn_orbital_asteroids() -> void:
	var orbit_min: float = planet_radius * orbit_radius_min_factor
	var orbit_max: float = planet_radius * orbit_radius_max_factor
	
	for i in asteroid_count:
		var orbit_r: float = _rng.randf_range(orbit_min, orbit_max)
		var angle: float = _rng.randf_range(0.0, TAU)
		var speed: float = _rng.randf_range(0.08, 0.20) * sqrt(200.0 / orbit_r)
		
		# Build the asteroid as a StaticBody3D so it has collision
		var asteroid_body := StaticBody3D.new()
		asteroid_body.name = "OrbitalAsteroid_%d" % i
		
		# Visual mesh (child of the body)
		var asteroid_mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		var sz: float = _rng.randf_range(asteroid_scale_min, asteroid_scale_max)
		box.size = Vector3(sz, sz * _rng.randf_range(0.6, 1.4), sz * _rng.randf_range(0.6, 1.4))
		asteroid_mesh.mesh = box
		
		var mat := StandardMaterial3D.new()
		var palette: Array[Color] = [
			Color(0.45, 0.40, 0.35),
			Color(0.55, 0.50, 0.42),
			Color(0.35, 0.32, 0.30),
			Color(0.50, 0.35, 0.25),
		]
		mat.albedo_color = palette[_rng.randi() % palette.size()]
		mat.metallic = 0.1
		mat.roughness = 0.9
		asteroid_mesh.material_override = mat
		asteroid_body.add_child(asteroid_mesh)
		
		# Collision shape (layer 16 = orbital asteroids)
		asteroid_body.collision_layer = 16
		asteroid_body.collision_mask = 0
		var col_shape := CollisionShape3D.new()
		var sphere_shape := SphereShape3D.new()
		sphere_shape.radius = sz * 0.6
		col_shape.shape = sphere_shape
		asteroid_body.add_child(col_shape)
		
		# Tilt
		var tilt: float = _rng.randf_range(-0.3, 0.3)
		
		add_child(asteroid_body)
		
		_orbital_asteroids.append({
			"body": asteroid_body,
			"mesh": asteroid_mesh,
			"angle": angle,
			"radius": orbit_r,
			"speed": speed,
			"tilt": tilt,
			"rot_speed": Vector3(
				_rng.randf_range(-0.5, 0.5),
				_rng.randf_range(-0.5, 0.5),
				_rng.randf_range(-0.5, 0.5)
			),
			"health": asteroid_health,
			"max_health": asteroid_health,
			"alive": true,
			"mat": mat,
		})


func _physics_process(delta: float) -> void:
	# Apply gravity to all tracked bodies
	_apply_gravity(delta)
	
	# Update orbital asteroid positions
	_update_orbital_asteroids(delta)


func _apply_gravity(delta: float) -> void:
	var center: Vector3 = global_position
	
	# Remove dead bodies
	_tracked_bodies = _tracked_bodies.filter(func(b): return is_instance_valid(b) and b.is_inside_tree())
	_tracked_rigids = _tracked_rigids.filter(func(b): return is_instance_valid(b) and b.is_inside_tree())
	
	for body in _tracked_bodies:
		var diff: Vector3 = center - body.global_position
		diff.y = 0.0  # gravity is horizontal (both ship and planet are at Y≈0)
		var dist_sq: float = diff.length_squared()
		if dist_sq < 1.0:
			continue
		
		var dist: float = sqrt(dist_sq)
		var direction: Vector3 = diff / dist
		
		# Newtonian gravity: F = G * M / r²
		var force_mag: float = gravity_strength / max(dist_sq, 100.0)
		force_mag = min(force_mag, gravity_strength / 100.0)
		
		var factor: float = 1.0
		if body.is_in_group("player_ship"):
			factor = player_gravity_factor
		
		# Apply as a continuous acceleration (velocity change per physics tick)
		var accel: Vector3 = direction * force_mag * factor * delta * 60.0
		body.velocity += accel
		
		# Visual tilt: bank the ship's body_root toward the planet
		if body.is_in_group("player_ship"):
			var forward: Vector3 = -body.global_transform.basis.z
			forward.y = 0.0
			var fwd_len: float = forward.length()
			if fwd_len > 0.01:
				forward /= fwd_len
				# Cross = dot of perpendicular: positive = planet is to the right
				var cross: float = forward.x * direction.z - forward.z * direction.x
				# Target bank: up to ~15 degrees based on gravity strength
				var grav_norm: float = min(force_mag * factor / 4.0, 0.3)
				var target_bank: float = cross * grav_norm
				# Apply to the visual body_root node
				var body_root: Node3D = body.get_node_or_null("Body")
				if body_root:
					# Smoothly interpolate the gravity bank
					var current_z: float = body_root.get_meta("gravity_bank", 0.0)
					var new_z: float = lerp(current_z, target_bank, clamp(4.0 * delta, 0.0, 1.0))
					body_root.set_meta("gravity_bank", new_z)
					body_root.rotation.z = new_z
	
	for body in _tracked_rigids:
		if not is_instance_valid(body):
			continue
		var diff: Vector3 = center - body.global_position
		diff.y = 0.0
		var dist_sq: float = diff.length_squared()
		if dist_sq < 1.0:
			continue
		var force_mag: float = gravity_strength / max(dist_sq, 100.0)
		force_mag = min(force_mag, gravity_strength / 100.0)
		body.apply_central_force(diff.normalized() * force_mag)


func _update_orbital_asteroids(delta: float) -> void:
	for data in _orbital_asteroids:
		if not data.alive:
			continue
		
		data.angle += data.speed * delta
		
		var x: float = cos(data.angle) * data.radius
		var z: float = sin(data.angle) * data.radius
		var y: float = sin(data.angle * 2.0) * data.tilt * data.radius * 0.1
		
		data.body.position = Vector3(x, y, z)
		data.mesh.rotation += data.rot_speed * delta


## Called when the player's laser hits an orbital asteroid.
## Returns true if the asteroid was hit (still alive).
func hit_orbital_asteroid(hit_pos: Vector3, damage: float) -> bool:
	var best_idx: int = -1
	var best_dist: float = INF
	
	for i in _orbital_asteroids.size():
		var data = _orbital_asteroids[i]
		if not data.alive:
			continue
		var d: float = data.body.global_position.distance_to(hit_pos)
		if d < best_dist and d < 10.0:  # hit threshold
			best_dist = d
			best_idx = i
	
	if best_idx < 0:
		return false
	
	return _damage_orbital_asteroid(best_idx, damage)


func _damage_orbital_asteroid(idx: int, damage: float) -> bool:
	var data = _orbital_asteroids[idx]
	data.health -= damage
	
	# Flash white
	if data.mat:
		data.mat.emission_enabled = true
		data.mat.emission = Color(1.0, 1.0, 1.0)
		data.mat.emission_energy_multiplier = 3.0
		var mat_ref = data.mat
		get_tree().create_timer(0.08).timeout.connect(func():
			if is_instance_valid(mat_ref):
				mat_ref.emission_enabled = false
		, CONNECT_ONE_SHOT)
	
	if data.health <= 0:
		_destroy_orbital_asteroid(idx)
	
	return true


func _destroy_orbital_asteroid(idx: int) -> void:
	var data = _orbital_asteroids[idx]
	data.alive = false
	
	var pos: Vector3 = data.body.global_position
	
	# Drop gems using the gem manager
	var gem_count: int = 0
	for _g in asteroid_gem_count:
		if _rng.randf() < 0.5:
			gem_count += 1
	
	if gem_count > 0:
		var gem_mgr = get_tree().get_first_node_in_group("gem_manager")
		var parent: Node = gem_mgr if gem_mgr else get_parent()
		var gem_scene = preload("res://scenes/Gem.tscn")
		# Planets are far from station, so all gem drops are at least Yellow+ (rare+).
		# Use a planet-specific roll: 30% yellow, 50% purple, 20% red.
		var planet_types: Array[String] = ["yellow", "yellow", "yellow", "purple", "purple", "purple", "purple", "purple", "red", "red"]
		for _g in gem_count:
			var gem = gem_scene.instantiate()
			gem.gem_type = planet_types[_rng.randi() % planet_types.size()]
			var offset := Vector3(
				_rng.randf_range(-1.0, 1.0),
				0.3,
				_rng.randf_range(-1.0, 1.0)
			)
			parent.add_child(gem)
			gem.global_position = pos + offset
	
	# Hide the asteroid
	data.body.visible = false
	data.body.set_process(false)
	data.body.set_physics_process(false)
	
	# Queue free after a short delay
	data.body.queue_free()


func _on_body_entered(body: Node3D) -> void:
	# Track CharacterBody3D (player, enemies)
	if body is CharacterBody3D:
		if body not in _tracked_bodies:
			_tracked_bodies.append(body)
			body_entered_gravity.emit(body)
	
	# Track RigidBody3D
	if body is RigidBody3D:
		if body not in _tracked_rigids:
			_tracked_rigids.append(body)
			body_entered_gravity.emit(body)


func _on_body_exited(body: Node3D) -> void:
	if body is CharacterBody3D:
		var idx: int = _tracked_bodies.find(body)
		if idx >= 0:
			_tracked_bodies.remove_at(idx)
			body_exited_gravity.emit(body)
	
	if body is RigidBody3D:
		var idx: int = _tracked_rigids.find(body)
		if idx >= 0:
			_tracked_rigids.remove_at(idx)
			body_exited_gravity.emit(body)


## Get the distance from this planet's center to a given point
func get_distance_to_planet(point: Vector3) -> float:
	return global_position.distance_to(point)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	if gravity_radius <= planet_radius:
		warnings.append("Gravity radius should be larger than planet radius.")
	return warnings
