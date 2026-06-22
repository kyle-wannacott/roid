extends Node3D
class_name SpawnPointGenerator

## Generates spawn points procedurally based on a seed.
## Creates visual markers at each spawn location.

@export var world_seed: int = 42
@export var min_distance: float = 600.0
@export var max_distance: float = 2000.0
@export var points_per_ring: int = 8
@export var ring_count: int = 5
@export var show_markers: bool = true

var spawn_points: Array[Vector3] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _markers: Array[Node3D] = []

func _ready() -> void:
	add_to_group("spawn_generators")
	generate_spawn_points()

func generate_spawn_points() -> void:
	_rng.seed = world_seed
	spawn_points.clear()
	
	# Clear old markers
	for marker in _markers:
		if is_instance_valid(marker):
			marker.queue_free()
	_markers.clear()
	
	# Generate spawn points in rings around the station
	for ring in range(ring_count):
		var ring_distance = lerp(min_distance, max_distance, float(ring) / float(ring_count - 1))
		var num_points = points_per_ring + ring * 2  # More points in outer rings
		
		for i in range(num_points):
			var angle = (float(i) / float(num_points)) * TAU + _rng.randf_range(-0.2, 0.2)
			var distance = ring_distance + _rng.randf_range(-30.0, 30.0)
			
			var pos = Vector3(
				cos(angle) * distance,
				0.0,
				sin(angle) * distance
			)
			
			spawn_points.append(pos)
			
			if show_markers:
				_create_marker(pos, ring)

func _create_marker(pos: Vector3, ring: int) -> void:
	var marker = MeshInstance3D.new()
	
	# Create a torus marker
	var torus = TorusMesh.new()
	torus.inner_radius = 2.0
	torus.outer_radius = 3.0
	torus.rings = 16
	torus.ring_segments = 8
	marker.mesh = torus
	
	# Color based on ring (difficulty)
	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	
	match ring:
		0:  # Outer belt - blue
			mat.albedo_color = Color(0.3, 0.5, 1.0, 0.4)
			mat.emission = Color(0.3, 0.5, 1.0, 1.0)
		1:  # Deep belt - yellow
			mat.albedo_color = Color(1.0, 1.0, 0.3, 0.4)
			mat.emission = Color(1.0, 1.0, 0.3, 1.0)
		2:  # Fringe - orange
			mat.albedo_color = Color(1.0, 0.6, 0.2, 0.4)
			mat.emission = Color(1.0, 0.6, 0.2, 1.0)
		_:  # Deep fringe - red
			mat.albedo_color = Color(1.0, 0.3, 0.2, 0.4)
			mat.emission = Color(1.0, 0.3, 0.2, 1.0)
	
	mat.emission_energy_multiplier = 0.5
	marker.material_override = mat
	marker.position = pos
	marker.position.y = 0.5  # Slightly above ground plane
	
	add_child(marker)
	_markers.append(marker)
	
	# Add a center indicator
	var center = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	center.mesh = sphere
	
	var center_mat = StandardMaterial3D.new()
	center_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	center_mat.albedo_color = mat.albedo_color
	center_mat.emission = mat.emission
	center_mat.emission_energy_multiplier = 1.0
	center.material_override = center_mat
	
	center.position = pos
	center.position.y = 0.5
	add_child(center)
	_markers.append(center)

func get_spawn_point(index: int) -> Vector3:
	if index >= 0 and index < spawn_points.size():
		return spawn_points[index]
	return Vector3.ZERO

func get_random_spawn_point() -> Vector3:
	if spawn_points.size() == 0:
		return Vector3.ZERO
	return spawn_points[_rng.randi() % spawn_points.size()]

func get_nearest_spawn_point(pos: Vector3) -> Vector3:
	var nearest = Vector3.ZERO
	var nearest_dist = INF
	
	for point in spawn_points:
		var dist = pos.distance_to(point)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = point
	
	return nearest

func get_spawn_points_in_range(min_dist: float, max_dist: float) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for point in spawn_points:
		var dist = point.length()  # Distance from origin (station)
		if dist >= min_dist and dist <= max_dist:
			result.append(point)
	return result

func set_markers_visible(visible: bool) -> void:
	for marker in _markers:
		if is_instance_valid(marker):
			marker.visible = visible
