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

# Gem material: ShaderMaterial that reads INSTANCE_CUSTOM for the
# per‑instance colour.
var _gem_material: ShaderMaterial

# Parallel arrays.
var positions: PackedVector3Array
var colors: PackedColorArray
var alive: PackedByteArray
var rb_refs: Array  # RigidBody3D refs, nullable
var _count: int = 0
var _live: int = 0
var _pool: Array[int] = []

@onready var mmi: MultiMeshInstance3D = $MultiMeshInstance
@onready var rng := RandomNumberGenerator.new()


# Gem palette – weighted by rarity.  White is the jackpot.
const PALETTE := [
	[ Color(0.3, 0.85, 1.0), 4.0 ],   # cyan      – common
	[ Color(0.5, 1.0,  0.4), 3.0 ],   # green     – common
	[ Color(0.95, 0.3, 1.0), 2.0 ],   # magenta   – uncommon
	[ Color(1.0,  0.8,  0.3), 1.5 ],   # gold      – uncommon
	[ Color(0.4,  0.7, 1.0), 1.0 ],   # sapphire  – rare
	[ Color(1.0,  1.0,  1.0), 0.3 ],   # white     – very rare
]
var _palette_weights: PackedFloat32Array


func _ready() -> void:
	add_to_group("gem_manager")
	rng.randomize()
	positions.resize(max_gems)
	colors.resize(max_gems)
	alive.resize(max_gems)
	rb_refs.resize(max_gems)

	_setup_multimesh()
	_setup_palette_weights()


func _setup_palette_weights() -> void:
	_palette_weights = PackedFloat32Array()
	for entry in PALETTE:
		_palette_weights.append((entry as Array)[1] as float)


func _setup_multimesh() -> void:
	_gem_mesh = gem_mesh if gem_mesh != null else _build_gem_mesh()
	_gem_material = ShaderMaterial.new()
	_gem_material.shader = preload("res://shaders/gem_instance.gdshader")

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _gem_mesh
	mm.instance_count = max_gems
	mmi.multimesh = mm


## Swap the gem mesh at runtime (or from the editor after export).
## Rebuilds the MultiMesh so all gems use the new shape.
func set_gem_mesh(new_mesh: ArrayMesh) -> void:
	gem_mesh = new_mesh
	_setup_multimesh()
	# Re‑push existing alive instances so their transforms/colours
	# still apply against the new mesh.
	for i in _count:
		if alive[i]:
			mmi.multimesh.set_instance_transform(i, Transform3D(Basis(), positions[i]))
			mmi.multimesh.set_instance_color(i, colors[i])


# ── Spawn / collect ────────────────────────────────────────────

func _alloc() -> int:
	if _pool.size() > 0: return _pool.pop_back()
	var idx: int = _count; _count += 1; return idx


func spawn_gem(at: Vector3) -> int:
	var idx: int = _alloc()
	var color: Color = _pick_palette_color()
	positions[idx] = at
	colors[idx] = color
	alive[idx] = 1
	mmi.multimesh.set_instance_transform(idx, Transform3D.IDENTITY.translated(at))
	mmi.multimesh.set_instance_color(idx, color)
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


func _pick_palette_color() -> Color:
	var total: float = 0.0
	for w in _palette_weights: total += w
	var pick: float = rng.randf_range(0.0, total)
	var acc: float = 0.0
	for i in _palette_weights.size():
		acc += _palette_weights[i]
		if pick <= acc: return (PALETTE[i] as Array)[0]
	return (PALETTE[0] as Array)[0]


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
	var top_y:    float = 0.45   # table height
	var girdle_y: float = 0.0    # widest part
	var culet_y:  float = -0.55  # bottom point
	var table_r:  float = 0.22   # radius of the flat top
	var girdle_r: float = 0.42   # radius at the widest part (girdle)
	var sides:    int = 6        # 6‑fold symmetry

	var top_center := Vector3(0, top_y, 0)
	var bot_center := Vector3(0, culet_y, 0)

	# Table ring (hex) at the top, girdle ring (hex) at the widest part.
	var table_ring: PackedVector3Array = PackedVector3Array()
	var girdle_ring: PackedVector3Array = PackedVector3Array()
	for i in sides:
		var a: float = TAU * float(i) / float(sides)
		table_ring.append(Vector3(cos(a) * table_r, top_y, sin(a) * table_r))
		girdle_ring.append(Vector3(cos(a) * girdle_r, girdle_y, sin(a) * girdle_r))

	# Build faces with duplicated vertices so each is flat‑shaded.
	var verts: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()

	# 1) Table: 6 fan triangles from the table centre to each table‑ring edge.
	for i in sides:
		var v0: Vector3 = top_center
		var v1: Vector3 = table_ring[i]
		var v2: Vector3 = table_ring[(i + 1) % sides]
		_emit_flat_face(verts, normals, v0, v1, v2)

	# 2) Crown: 6 quads (12 triangles) connecting table ring to girdle ring.
	for i in sides:
		var tv0: Vector3 = table_ring[i]
		var tv1: Vector3 = table_ring[(i + 1) % sides]
		var gv0: Vector3 = girdle_ring[i]
		var gv1: Vector3 = girdle_ring[(i + 1) % sides]
		_emit_flat_face(verts, normals, tv0, gv0, gv1)
		_emit_flat_face(verts, normals, tv0, gv1, tv1)

	# 3) Pavilion: 6 fan triangles from the girdle ring down to the culet.
	for i in sides:
		var gv0: Vector3 = girdle_ring[i]
		var gv1: Vector3 = girdle_ring[(i + 1) % sides]
		# Winding: bot → gv1 → gv0 so the normal points outward.
		_emit_flat_face(verts, normals, bot_center, gv1, gv0)

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
