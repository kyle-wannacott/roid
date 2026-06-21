@tool
extends RigidBody3D
## Physics body for a single gem.  Visuals are handled by the
## GemManager's MultiMeshInstance3D during gameplay — this node
## exists mainly for the physics simulation (rolling, gravity,
## collision with ship).
##
## In the editor, a MeshInstance3D child previews the gem with
## the shader material so you can tweak the look interactively.

@export var lifetime: float = 90.0
@export var pulse_speed: float = 3.0
@export var home_speed: float = 14.0
@export var attraction_radius: float = 8.0

var gem_slot: int = -1       # index in GemManager's arrays
var gem_manager: Node = null
var age: float = 0.0
var being_attracted: bool = false
var target: Node3D = null
var spin_axis: Vector3 = Vector3.ZERO


func _ready() -> void:
	if Engine.is_editor_hint():
		# Editor preview — build the faceted gem mesh and show it.
		_setup_editor_preview()
		return

	add_to_group("gems")
	gem_manager = get_tree().get_first_node_in_group("gem_manager")
	if gem_manager == null:
		push_warning("Gem spawned with no GemManager in the tree")
		return

	# Hide the MeshInstance3D preview — the GemManager's MultiMesh
	# handles all gem visuals during gameplay.
	var mi := get_node_or_null("MeshInstance3D")
	if mi != null:
		mi.hide()

	# Spawn a new gem in the manager and remember the slot.
	gem_slot = gem_manager.spawn_gem(global_position)
	if gem_slot >= 0:
		gem_manager.rb_refs[gem_slot] = self

	# Random initial spin axis.
	spin_axis = Vector3(
		randf_range(-1.0, 1.0),
		randf_range(-1.0, 1.0),
		randf_range(-1.0, 1.0)
	).normalized()

	# Small horizontal kick so gems spread out on the ground.
	apply_central_impulse(Vector3(
		randf_range(-1.0, 1.0),
		0.0,
		randf_range(-1.0, 1.0)
	).normalized() * 2.0)
	angular_velocity = spin_axis * randf_range(1.0, 3.0)


func _setup_editor_preview() -> void:
	# Build the same faceted gem mesh that GemManager uses at runtime.
	var mi := get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mi == null:
		return

	# Use the same procedural gem mesh as GemManager.
	mi.mesh = _build_gem_mesh()


# ── Physics ──────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	age += delta
	if age > lifetime:
		_collect()
		return
	if gem_slot < 0:
		queue_free()
		return

	# Stay on the ground plane.
	global_position.y = 0.3

	# Attracted by the ship.
	if being_attracted and target != null and is_instance_valid(target):
		var to_target: Vector3 = target.global_position - global_position
		to_target.y = 0.0
		var dist: float = to_target.length()
		if dist < 0.6:
			_collect()
			return
		var dir: Vector3 = to_target.normalized()
		var speed_mult: float = 1.0 + max(0.0, (attraction_radius - dist) / attraction_radius) * 2.0
		linear_velocity = dir * home_speed * speed_mult
		angular_velocity = spin_axis * (4.0 + (attraction_radius - dist) * 0.5)
	else:
		linear_velocity = linear_velocity.lerp(Vector3.ZERO, delta * 0.4)
		angular_velocity = spin_axis.lerp(angular_velocity, delta * 0.2)


func attract_to(ship: Node3D) -> void:
	if being_attracted: return
	being_attracted = true
	target = ship
	gravity_scale = 0.0
	collision_layer = 0
	collision_mask = 0


func _collect() -> void:
	if gem_manager != null and is_instance_valid(gem_manager) and gem_slot >= 0:
		gem_manager.collect_gem(gem_slot)
		gem_slot = -1
	queue_free()


## Public method called by the Ship when it picks up the gem.
## Properly cleans up through the GemManager so the MultiMesh
## visual is hidden.
func collect() -> void:
	_collect()


# ── Procedural gem mesh (same as GemManager._build_gem_mesh) ─────
# So the editor preview shows the actual faceted shape.

func _build_gem_mesh() -> ArrayMesh:
	var top_y:    float = 0.45
	var girdle_y: float = 0.0
	var culet_y:  float = -0.55
	var table_r:  float = 0.22
	var girdle_r: float = 0.42
	var sides:    int = 6

	var top_center := Vector3(0, top_y, 0)
	var bot_center := Vector3(0, culet_y, 0)

	var table_ring: PackedVector3Array = PackedVector3Array()
	var girdle_ring: PackedVector3Array = PackedVector3Array()
	for i in sides:
		var a: float = TAU * float(i) / float(sides)
		table_ring.append(Vector3(cos(a) * table_r, top_y, sin(a) * table_r))
		girdle_ring.append(Vector3(cos(a) * girdle_r, girdle_y, sin(a) * girdle_r))

	var verts: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()

	# Table
	for i in sides:
		_emit_flat_face(verts, normals, top_center, table_ring[i], table_ring[(i + 1) % sides])

	# Crown
	for i in sides:
		var tv0 = table_ring[i]
		var tv1 = table_ring[(i + 1) % sides]
		var gv0 = girdle_ring[i]
		var gv1 = girdle_ring[(i + 1) % sides]
		_emit_flat_face(verts, normals, tv0, gv0, gv1)
		_emit_flat_face(verts, normals, tv0, gv1, tv1)

	# Pavilion
	for i in sides:
		var gv0 = girdle_ring[i]
		var gv1 = girdle_ring[(i + 1) % sides]
		_emit_flat_face(verts, normals, bot_center, gv1, gv0)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


func _emit_flat_face(verts: PackedVector3Array, normals: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3) -> void:
	var n: Vector3 = (b - a).cross(c - a).normalized()
	var center: Vector3 = (a + b + c) / 3.0
	if n.dot(center) < 0.0:
		var tmp: Vector3 = b
		b = c
		c = tmp
		n = -n
	verts.append(a); verts.append(b); verts.append(c)
	normals.append(n); normals.append(n); normals.append(n)
