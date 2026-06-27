extends Node3D
class_name GemManager
## Central gem manager. Renders all alive gems via a single
## MultiMeshInstance3D (faceted diamond shape with flat shading),
## manages per‑instance colours, and keeps a parallel array of
## physics‑body references so the gems still tumble and can be
## collected by the ship.

signal gem_collected( slot_idx: int )

@export var max_gems: int = 16384
## Optional custom gem mesh.  If left null, the manager builds a
## procedural round‑cut brilliant diamond at startup.  Assign any
## ArrayMesh here (e.g. one imported from a .glb) and the manager
## will use it for every gem instance.
@export var gem_mesh: ArrayMesh

# Pre‑baked gem mesh (flat‑shaded octahedron).  Built once in _ready.
var _gem_mesh: ArrayMesh

# Gem material: ShaderMaterial that reads the per‑instance colour
# from the built‑in COLOR variable (set via set_instance_color).
var _gem_material: ShaderMaterial

# Parallel arrays.
var positions: PackedVector3Array
var colors: PackedColorArray
var gem_types: Array[String]  # gem type name per instance
var alive: PackedByteArray
var rb_refs: Array  # RigidBody3D refs, nullable
var _count: int = 0
var _live: int = 0
var _pool: Array[int] = []

@onready var mmi: MultiMeshInstance3D = $MultiMeshInstance
@onready var rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group("gem_manager")
	rng.randomize()
	positions.resize(max_gems)
	colors.resize(max_gems)
	gem_types.resize(max_gems)
	alive.resize(max_gems)
	rb_refs.resize(max_gems)
	_setup_multimesh()


func _setup_multimesh() -> void:
	_gem_mesh = gem_mesh if gem_mesh != null else _build_gem_mesh()
	_gem_material = ShaderMaterial.new()
	_gem_material.shader = preload("res://shaders/gem_instance.gdshader")

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true  # per‑instance COLOR built‑in
	mm.mesh = _gem_mesh
	mm.instance_count = max_gems
	mmi.multimesh = mm
	mmi.material_override = _gem_material


## Swap the gem mesh at runtime (or from the editor after export).
## Rebuilds the MultiMesh so all gems use the new shape.
func set_gem_mesh(new_mesh: ArrayMesh) -> void:
	gem_mesh = new_mesh
	_setup_multimesh()
	# Re‑push existing alive instances so their transforms still apply
	# against the new mesh.
	for i in _count:
		if alive[i]:
			mmi.multimesh.set_instance_transform(i, Transform3D(Basis(), positions[i]))


# ── Spawn / collect ────────────────────────────────────────────

func _alloc() -> int:
	if _pool.size() > 0: return _pool.pop_back()
	var idx: int = _count; _count += 1; return idx


func spawn_gem(at: Vector3, gem_type: String = "green") -> int:
	var idx: int = _alloc()
	var color: Color = GemTypeData.get_color(gem_type)
	positions[idx] = at
	colors[idx] = color
	gem_types[idx] = gem_type
	alive[idx] = 1
	# Write the per‑instance colour so the shader reads it from COLOR.
	mmi.multimesh.set_instance_color(idx, color)
	mmi.multimesh.set_instance_transform(idx, Transform3D.IDENTITY.translated(at))
	_live += 1
	return idx


func collect_gem(idx: int) -> void:
	if idx < 0 or idx >= _count or not alive[idx]: return
	alive[idx] = 0
	_live -= 1
	# Hide the instance by setting its transform to an invisible scale.
	mmi.multimesh.set_instance_transform(idx, Transform3D.IDENTITY.scaled(Vector3.ZERO))
	_pool.append(idx)
	# Note: the RigidBody3D is freed by the Gem script itself.


## Return the gem type string for a given slot index.
func get_gem_type(idx: int) -> String:
	if idx < 0 or idx >= _count or not alive[idx]:
		return "green"
	return gem_types[idx]


# ── Per‑frame: update transforms from physics bodies ───────────

func _process(_delta: float) -> void:
	for i in _count:
		if alive[i] and rb_refs[i] != null and is_instance_valid(rb_refs[i]):
			positions[i] = (rb_refs[i] as Node3D).global_position
			mmi.multimesh.set_instance_transform(i, Transform3D(Basis().rotated(Vector3.UP, (rb_refs[i] as Node3D).rotation.y), positions[i]))
		elif alive[i] and rb_refs[i] == null:
			# No physics body – just keep the position.
			mmi.multimesh.set_instance_transform(i, Transform3D(Basis(), positions[i]))


# ── Gem mesh: round‑cut brilliant diamond ─────────────────────
# 6‑fold symmetry: flat hexagonal table at top, crown facets sloping
# outward to a wider girdle, then pavilion facets converging to a
# culet (point) at the bottom.  24 flat‑shaded facets total so each
# catches light differently — the classic "fire" of a real gem.

func _build_gem_mesh() -> ArrayMesh:
	var top_y:        float = 0.45   # table height
	var girdle_top_y: float = 0.06   # top of the girdle band
	var girdle_bot_y: float = -0.06  # bottom of the girdle band
	var culet_y:      float = -0.55  # bottom point
	var table_r:      float = 0.24   # radius of the flat top
	var girdle_r:     float = 0.42   # radius at the widest part (girdle)
	var sides:        int = 16       # 16-fold symmetry for a round cut

	var top_center := Vector3(0, top_y, 0)
	var bot_center := Vector3(0, culet_y, 0)

	var table_ring: PackedVector3Array = PackedVector3Array()
	var girdle_top_ring: PackedVector3Array = PackedVector3Array()
	var girdle_bot_ring: PackedVector3Array = PackedVector3Array()
	for i in sides:
		var a: float = TAU * float(i) / float(sides)
		var cos_a: float = cos(a)
		var sin_a: float = sin(a)
		table_ring.append(Vector3(cos_a * table_r, top_y, sin_a * table_r))
		girdle_top_ring.append(Vector3(cos_a * girdle_r, girdle_top_y, sin_a * girdle_r))
		girdle_bot_ring.append(Vector3(cos_a * girdle_r, girdle_bot_y, sin_a * girdle_r))

	var verts: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()

	# 1) Table
	for i in sides:
		_emit_flat_face(verts, normals, top_center, table_ring[i], table_ring[(i + 1) % sides])

	# 2) Crown (Table to Girdle Top)
	for i in sides:
		var tv0 = table_ring[i]
		var tv1 = table_ring[(i + 1) % sides]
		var gv0 = girdle_top_ring[i]
		var gv1 = girdle_top_ring[(i + 1) % sides]
		_emit_flat_face(verts, normals, tv0, gv0, gv1)
		_emit_flat_face(verts, normals, tv0, gv1, tv1)

	# 3) Girdle band (vertical sides)
	for i in sides:
		var gt0 = girdle_top_ring[i]
		var gt1 = girdle_top_ring[(i + 1) % sides]
		var gb0 = girdle_bot_ring[i]
		var gb1 = girdle_bot_ring[(i + 1) % sides]
		_emit_flat_face(verts, normals, gt0, gb0, gb1)
		_emit_flat_face(verts, normals, gt0, gb1, gt1)

	# 4) Pavilion (Girdle Bottom to Culet)
	for i in sides:
		var gb0 = girdle_bot_ring[i]
		var gb1 = girdle_bot_ring[(i + 1) % sides]
		_emit_flat_face(verts, normals, bot_center, gb1, gb0)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


## Helper: append a single flat‑shaded triangle to the growing arrays.
## The winding is auto‑fixed so the normal always points outward from
## the gem's centre line.
func _emit_flat_face(verts: PackedVector3Array, normals: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3) -> void:
	var n: Vector3 = (b - a).cross(c - a).normalized()
	var center: Vector3 = (a + b + c) / 3.0
	# If the normal is pointing inward, flip the winding.
	if n.dot(center) < 0.0:
		var tmp: Vector3 = b
		b = c
		c = tmp
		n = -n
	verts.append(a); verts.append(b); verts.append(c)
	normals.append(n); normals.append(n); normals.append(n)
