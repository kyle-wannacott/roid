extends StaticBody3D
class_name Asteroid
## Mineable asteroid. Has health, takes laser damage, breaks into gems.
## The mesh is generated procedurally in `_ready()` for a rocky look.

signal destroyed( position: Vector3, gem_count: int )

@export var max_health: float = 100.0
@export var gem_count: int = 5
@export var min_scale: float = 1.2
@export var max_scale: float = 3.0
@export var damage_flash_duration: float = 0.08
@export var gem_scene: PackedScene  # assigned by Main.gd when spawning

var health: float = 0.0
var flash_timer: float = 0.0
var base_color: Color = Color(0.5, 0.45, 0.4)
var asteroid_seed: int = 0
var _is_destroyed: bool = false

@onready var mesh_instance: MeshInstance3D = $Mesh
@onready var collision_shape: CollisionShape3D = $CollisionShape
@onready var material: StandardMaterial3D


func _ready() -> void:
	asteroid_seed = randi()
	# Random scale for the whole asteroid.
	var s: float = randf_range(min_scale, max_scale)
	scale = Vector3.ONE * s
	# Random initial orientation.
	rotate_y(randf_range(0.0, TAU))
	rotate_x(randf_range(0.0, TAU))

	# Random rocky palette: brown / grey / rust.
	var palette: Array[Color] = [
		Color(0.45, 0.40, 0.35),
		Color(0.55, 0.50, 0.42),
		Color(0.35, 0.32, 0.30),
		Color(0.50, 0.35, 0.25),
		Color(0.42, 0.45, 0.40),
	]
	base_color = palette[randi() % palette.size()]

	material = StandardMaterial3D.new()
	material.albedo_color = base_color
	material.metallic = 0.05
	material.roughness = 0.95
	material.emission_enabled = false
	mesh_instance.material_override = material

	_build_rocky_mesh()
	_build_collision_shape()

	health = max_health
	add_to_group("asteroids")


func _process(delta: float) -> void:
	if flash_timer > 0.0:
		flash_timer -= delta
		var t: float = clamp(flash_timer / damage_flash_duration, 0.0, 1.0)
		material.emission_enabled = t > 0.0
		material.emission = base_color
		material.emission_energy_multiplier = 3.0 * t
	else:
		material.emission_enabled = false

	# Slow continuous spin.
	rotate_y(delta * 0.05)
	rotate_x(delta * 0.02)


func take_damage(amount: float) -> void:
	health -= amount
	flash_timer = damage_flash_duration
	material.emission_enabled = true
	material.emission = base_color
	material.emission_energy_multiplier = 3.0
	if health <= 0.0:
		_destroy()


func _destroy() -> void:
	if _is_destroyed:
		return
	_is_destroyed = true

	# Apply bonus gems from skill tree
	var total_gems: int = gem_count
	if PlayerSkills:
		if PlayerSkills.is_unlocked("mining_yield"): total_gems += 1
		if PlayerSkills.is_unlocked("mining_yield_2"): total_gems += 2

	destroyed.emit(global_position, total_gems)
	if gem_scene != null:
		var parent: Node = get_parent()
		for i in total_gems:
			var gem: Node3D = gem_scene.instantiate() as Node3D
			var spawn_pos: Vector3 = global_position + Vector3(
				randf_range(-0.5, 0.5),
				0.0,
				randf_range(-0.5, 0.5)
			)
			spawn_pos.y = 0.3
			parent.add_child(gem)
			gem.global_position = spawn_pos
	queue_free()


# ---------------------------------------------------------------------
# Procedural geometry: build a chunky displaced sphere from scratch
# using an icosphere (subdivided icosahedron). Each vertex is pushed
# outward by a deterministic noise function based on its direction.
# ---------------------------------------------------------------------

func _build_rocky_mesh() -> void:
	# Subdivision count: 2 = 162 verts, 320 faces; 3 = 642 verts / 1280 faces.
	var subdivisions: int = 2
	var radius: float = 1.0

	var vertices: PackedVector3Array = _make_icosphere(subdivisions)
	var rng := RandomNumberGenerator.new()
	rng.seed = asteroid_seed

	# Displace each vertex outward by a deterministic, smooth noise.
	for i in vertices.size():
		var n: Vector3 = vertices[i].normalized()
		var wobble: float = (
			sin(n.x * 3.7 + rng.randf() * 0.3) * 0.18 +
			cos(n.y * 4.3 + rng.randf() * 0.3) * 0.18 +
			sin(n.z * 2.9 + rng.randf() * 0.3) * 0.18 +
			rng.randf_range(-0.12, 0.12)
		)
		var disp: float = 1.0 + wobble
		vertices[i] = n * radius * disp

	# Build triangle indices (every group of 3 verts in the icosphere
	# generator is already a triangle).
	var indices: PackedInt32Array = PackedInt32Array()
	for i in vertices.size():
		indices.append(i)

	# Compute per-face flat normals (gives the rock a faceted look).
	# We also flip any normal that ends up pointing inward — the
	# displacement can otherwise fold a face back on itself, which is
	# what was making the asteroids look like they had backface culling
	# on (the "back" of the folded face was the only side being lit).
	var normals: PackedVector3Array = PackedVector3Array()
	normals.resize(vertices.size())
	for t in vertices.size() / 3:
		var a: Vector3 = vertices[t * 3 + 0]
		var b: Vector3 = vertices[t * 3 + 1]
		var c: Vector3 = vertices[t * 3 + 2]
		var face_n: Vector3 = (b - a).cross(c - a).normalized()
		var face_center: Vector3 = (a + b + c) / 3.0
		if face_n.dot(face_center) < 0.0:
			face_n = -face_n
		normals[t * 3 + 0] = face_n
		normals[t * 3 + 1] = face_n
		normals[t * 3 + 2] = face_n

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices

	var new_mesh := ArrayMesh.new()
	new_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh_instance.mesh = new_mesh


## Build an icosphere by subdividing an icosahedron.
## Returns vertex positions in groups of 3 (one triangle per group).
func _make_icosphere(subdivisions: int) -> PackedVector3Array:
	# Start with a regular icosahedron (12 vertices, 20 faces).
	# The classic icosahedron vertex coordinates (golden ratio phi).
	var phi: float = (1.0 + sqrt(5.0)) / 2.0
	var base_verts: Array[Vector3] = [
		Vector3(-1,  phi,  0), Vector3( 1,  phi,  0), Vector3(-1, -phi,  0), Vector3( 1, -phi,  0),
		Vector3( 0, -1,  phi), Vector3( 0,  1,  phi), Vector3( 0, -1, -phi), Vector3( 0,  1, -phi),
		Vector3( phi,  0, -1), Vector3( phi,  0,  1), Vector3(-phi,  0, -1), Vector3(-phi,  0,  1),
	]
	# 20 triangle faces (indices into base_verts).
	var base_faces: Array[Vector3i] = [
		Vector3i(0, 11, 5), Vector3i(0, 5, 1), Vector3i(0, 1, 7), Vector3i(0, 7, 10), Vector3i(0, 10, 11),
		Vector3i(1, 5, 9), Vector3i(5, 11, 4), Vector3i(11, 10, 2), Vector3i(10, 7, 6), Vector3i(7, 1, 8),
		Vector3i(3, 9, 4), Vector3i(3, 4, 2), Vector3i(3, 2, 6), Vector3i(3, 6, 8), Vector3i(3, 8, 9),
		Vector3i(4, 9, 5), Vector3i(2, 4, 11), Vector3i(6, 2, 10), Vector3i(8, 6, 7), Vector3i(9, 8, 1),
	]

	# Normalize base verts to unit length (project to sphere).
	for i in base_verts.size():
		base_verts[i] = base_verts[i].normalized()

	# Subdivide `subdivisions` times, splitting each triangle into 4.
	var faces: Array[Vector3i] = base_faces.duplicate()
	var vert_cache: Dictionary = {}  # midpoint cache to merge shared edges.

	for _sub in subdivisions:
		var new_faces: Array[Vector3i] = []
		for face in faces:
			var a: int = face.x
			var b: int = face.y
			var c: int = face.z
			var ab: int = _midpoint(a, b, base_verts, vert_cache)
			var bc: int = _midpoint(b, c, base_verts, vert_cache)
			var ca: int = _midpoint(c, a, base_verts, vert_cache)
			new_faces.append(Vector3i(a,  ab, ca))
			new_faces.append(Vector3i(b,  bc, ab))
			new_faces.append(Vector3i(c,  ca, bc))
			new_faces.append(Vector3i(ab, bc, ca))
		faces = new_faces

	# Re-normalize all verts (they drift off the sphere during subdivision).
	for i in base_verts.size():
		base_verts[i] = base_verts[i].normalized()

	# Flatten the faces into a packed array (3 verts per triangle).
	var out: PackedVector3Array = PackedVector3Array()
	out.resize(faces.size() * 3)
	var idx: int = 0
	for face in faces:
		out[idx]     = base_verts[face.x]
		out[idx + 1] = base_verts[face.y]
		out[idx + 2] = base_verts[face.z]
		idx += 3
	return out


func _midpoint(a: int, b: int, verts: Array[Vector3], cache: Dictionary) -> int:
	# Use a canonical key for the edge so (a,b) and (b,a) hit the same slot.
	var lo: int = mini(a, b)
	var hi: int = maxi(a, b)
	var key: Vector2i = Vector2i(lo, hi)
	if cache.has(key):
		return cache[key]
	var mid: Vector3 = (verts[a] + verts[b]) * 0.5
	var new_idx: int = verts.size()
	verts.append(mid)
	cache[key] = new_idx
	return new_idx


func _build_collision_shape() -> void:
	# Slightly smaller than the average mesh radius so the player can
	# fly close to the asteroid without the (invisible) collision
	# sphere popping them away.
	var shape := SphereShape3D.new()
	shape.radius = 0.85
	collision_shape.shape = shape
