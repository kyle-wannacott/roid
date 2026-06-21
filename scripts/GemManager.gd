extends Node3D
class_name GemManager
## Central gem manager. Renders all alive gems via a single
## MultiMeshInstance3D (faceted diamond shape with flat shading),
## manages per‑instance colours, and keeps a parallel array of
## physics‑body references so the gems still tumble and can be
## collected by the ship.

signal gem_collected( slot_idx: int )

@export var max_gems: int = 16384

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
	_gem_mesh = _build_gem_mesh()
	_gem_material = ShaderMaterial.new()
	_gem_material.shader = preload("res://shaders/gem_instance.gdshader")

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _gem_mesh
	mm.instance_count = max_gems
	mmi.multimesh = mm


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


# ── Gem mesh: faceted octahedron (diamond) ─────────────────────

func _build_gem_mesh() -> ArrayMesh:
	var top_y: float = 0.5
	var bot_y: float = -0.3
	var r: float = 0.32

	# 6 unique vertex positions
	var top := Vector3(0, top_y, 0)
	var e := Vector3(r, 0, 0)
	var n := Vector3(0, 0, r)
	var w := Vector3(-r, 0, 0)
	var s := Vector3(0, 0, -r)
	var bot := Vector3(0, bot_y, 0)

	# 8 faces, each with its own 3 duplicated vertices for flat shading
	var faces: Array = [
		# Top cap (4 triangles)
		[top, e, n], [top, n, w], [top, w, s], [top, s, e],
		# Bottom cap (4 triangles) – winding reversed for outward normals
		[bot, n, e], [bot, w, n], [bot, s, w], [bot, e, s],
	]

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	verts.resize(faces.size() * 3)
	normals.resize(faces.size() * 3)
	for fi in faces.size():
		var face: Array = faces[fi]
		var v0: Vector3 = face[0]; var v1: Vector3 = face[1]; var v2: Vector3 = face[2]
		var fn: Vector3 = (v1 - v0).cross(v2 - v0).normalized()
		var base: int = fi * 3
		verts[base]     = v0
		verts[base + 1] = v1
		verts[base + 2] = v2
		normals[base]     = fn
		normals[base + 1] = fn
		normals[base + 2] = fn

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m
