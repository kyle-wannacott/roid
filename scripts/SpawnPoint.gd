extends Node3D
class_name SpawnPoint

## Visual marker for enemy spawn locations.
## Place these in Main.tscn to define where enemies can appear.

@export var spawn_type: SpawnType = SpawnType.ANY
@export var show_marker: bool = true

enum SpawnType {
	ANY,          # Can spawn any enemy for the zone
	SCOUT_ONLY,  # Only scouts
	GUNSHIP_ONLY, # Only gunships
	BOSS_ONLY,   # Only bosses
}

## Visual properties
var _ring_mesh: MeshInstance3D = null
var _indicator_mesh: MeshInstance3D = null
var _material: StandardMaterial3D = null
var _time: float = 0.0

func _ready() -> void:
	add_to_group("enemy_spawn_points")
	_create_visuals()
	_update_visual()

func _process(delta: float) -> void:
	if not show_marker or _ring_mesh == null:
		return
	
	_time += delta
	
	# Rotate the ring slowly
	_ring_mesh.rotation.y += delta * 0.5
	
	# Pulse the indicator
	var pulse = 0.8 + sin(_time * 2.0) * 0.2
	_indicator_mesh.scale = Vector3.ONE * pulse

func _create_visuals() -> void:
	# Create the ring mesh
	_ring_mesh = MeshInstance3D.new()
	var torus = TorusMesh.new()
	torus.inner_radius = 3.0
	torus.outer_radius = 4.0
	torus.rings = 32
	torus.ring_segments = 16
	_ring_mesh.mesh = torus
	
	# Create material
	_material = StandardMaterial3D.new()
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.albedo_color = Color(0.0, 1.0, 0.5, 0.3)
	_material.emission_enabled = true
	_material.emission = Color(0.0, 1.0, 0.5, 1.0)
	_material.emission_energy_multiplier = 0.5
	_ring_mesh.material_override = _material
	
	add_child(_ring_mesh)
	
	# Create center indicator (small sphere)
	_indicator_mesh = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	_indicator_mesh.mesh = sphere
	
	var indicator_mat = StandardMaterial3D.new()
	indicator_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	indicator_mat.albedo_color = Color(0.0, 1.0, 0.5, 0.5)
	indicator_mat.emission_enabled = true
	indicator_mat.emission = Color(0.0, 1.0, 0.5, 1.0)
	indicator_mat.emission_energy_multiplier = 1.0
	_indicator_mesh.material_override = indicator_mat
	
	add_child(_indicator_mesh)

func _update_visual() -> void:
	if _material == null:
		return
	
	match spawn_type:
		SpawnType.ANY:
			_material.albedo_color = Color(0.0, 1.0, 0.5, 0.3)
			_material.emission = Color(0.0, 1.0, 0.5, 1.0)
		SpawnType.SCOUT_ONLY:
			_material.albedo_color = Color(0.5, 0.5, 1.0, 0.3)
			_material.emission = Color(0.5, 0.5, 1.0, 1.0)
		SpawnType.GUNSHIP_ONLY:
			_material.albedo_color = Color(1.0, 0.5, 0.0, 0.3)
			_material.emission = Color(1.0, 0.5, 0.0, 1.0)
		SpawnType.BOSS_ONLY:
			_material.albedo_color = Color(1.0, 0.0, 0.0, 0.3)
			_material.emission = Color(1.0, 0.0, 0.0, 1.0)

func set_marker_visible(visible: bool) -> void:
	show_marker = visible
	if _ring_mesh:
		_ring_mesh.visible = visible
	if _indicator_mesh:
		_indicator_mesh.visible = visible

## Get distance from station (origin)
func get_distance_from_station() -> float:
	return global_position.distance_to(Vector3.ZERO)

## Get distance from a target
func get_distance_from(target: Vector3) -> float:
	return global_position.distance_to(target)
