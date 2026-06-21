extends Node3D
class_name AsteroidManager

signal asteroid_destroyed( world_pos: Vector3, gem_count: int )

@export var max_asteroids: int = 8192
@export var field_radius: float = 400.0
@export var exclusion_radius: float = 35.0
@export var min_spacing: float = 4.0
@export var default_health: float = 100.0
@export var gem_scene: PackedScene = preload("res://scenes/Gem.tscn")
@export var instance_shader: Shader = preload("res://shaders/asteroid_instance.gdshader")
@export var gem_manager_path: NodePath

enum Size { LARGE, MEDIUM, SMALL }
static var SIZE_DEFS := [
	[ Size.LARGE,  2.0,  3.5, 100.0, 3, 0 ],
	[ Size.MEDIUM, 1.2,  2.0,  40.0, 3, 0 ],
	[ Size.SMALL,  0.5,  1.2,  15.0, 0, 3 ],
]

var positions: PackedVector3Array
var base_scale: PackedFloat32Array
var yaw_angle: PackedFloat32Array
var health: PackedFloat32Array
var alive: PackedByteArray
var size_idx: PackedByteArray

var _count: int = 0
var _live: int = 0
var _pool: Array[int] = []

@onready var mmi: MultiMeshInstance3D = $MultiMeshInstance
@onready var rng := RandomNumberGenerator.new()
var _gem_manager: Node = null


func _get_gem_manager() -> Node:
	if _gem_manager != null and is_instance_valid(_gem_manager): return _gem_manager
	if not gem_manager_path.is_empty():
		_gem_manager = get_node_or_null(gem_manager_path)
	if _gem_manager == null:
		_gem_manager = get_tree().get_first_node_in_group("gem_manager")
	return _gem_manager


func _ready() -> void:
	rng.randomize()
	positions.resize(max_asteroids); base_scale.resize(max_asteroids)
	yaw_angle.resize(max_asteroids); health.resize(max_asteroids)
	alive.resize(max_asteroids); size_idx.resize(max_asteroids)
	_setup_multimesh()
	_spawn_initial()
	_refresh_all()


func _setup_multimesh() -> void:
	var mesh: ArrayMesh = _build_mesh()
	var mat := ShaderMaterial.new(); mat.shader = instance_shader
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh; mm.instance_count = max_asteroids
	mmi.multimesh = mm; mmi.material_override = mat


func _spawn_initial() -> void:
	for _i in 2500:
		var sz: int
		var roll: float = rng.randf()
		if   roll < 0.40: sz = Size.SMALL
		elif roll < 0.75: sz = Size.MEDIUM
		else:             sz = Size.LARGE
		var min_r: float = exclusion_radius + 5.0
		var max_r: float = field_radius
		if sz == Size.SMALL:
			max_r = field_radius * 0.4
		elif sz == Size.MEDIUM:
			min_r = exclusion_radius + 10.0
			max_r = field_radius * 0.7
		var r: float = sqrt(rng.randf_range(min_r * min_r, max_r * max_r))
		var t: float = rng.randf_range(0.0, TAU)
		var pos: Vector3 = Vector3(r * cos(t), 0.8, r * sin(t))
		if _is_too_close(pos): continue
		_add_asteroid(pos, sz)


func _is_too_close(pos: Vector3) -> bool:
	if pos.length() < exclusion_radius: return true
	for i in _count:
		if not alive[i]: continue
		if pos.distance_squared_to(positions[i]) < min_spacing * min_spacing: return true
	return false


func _alloc() -> int:
	if _pool.size() > 0: return _pool.pop_back()
	var idx: int = _count; _count += 1; return idx


func _add_asteroid(pos: Vector3, sz: int) -> int:
	var idx: int = _alloc()
	var def: Array = SIZE_DEFS[sz]
	positions[idx] = pos
	base_scale[idx] = rng.randf_range(def[1], def[2])
	health[idx] = def[3]
	alive[idx] = 1
	size_idx[idx] = sz
	yaw_angle[idx] = rng.randf_range(0.0, TAU)
	_live += 1
	return idx


func _bake(idx: int) -> void:
	var b: Basis = Basis().rotated(Vector3.UP, yaw_angle[idx])
	b = b.scaled(Vector3.ONE * base_scale[idx])
	mmi.multimesh.set_instance_transform(idx, Transform3D(b, positions[idx]))


func _refresh_all() -> void:
	for i in _count:
		if alive[i]: _bake(i)


var _rot_ptr: int = 0

func _process(delta: float) -> void:
	if _count == 0: return
	for _b in 12:
		if _rot_ptr >= _count: _rot_ptr = 0
		if alive[_rot_ptr]:
			yaw_angle[_rot_ptr] += delta * 0.015 * (1.0 + hash(positions[_rot_ptr]) % 3)
			_bake(_rot_ptr)
		_rot_ptr += 1


func hit_asteroid(origin: Vector3, dir: Vector3, max_dist: float, damage: float) -> Variant:
	if _live == 0: return null
	var best: int = -1; var best_hd: float = INF
	for i in _count:
		if not alive[i]: continue
		var hd: float = _ray_sphere_hit(origin, dir, max_dist, positions[i], 0.85 * base_scale[i])
		if hd >= 0.0 and hd < best_hd: best_hd = hd; best = i
	if best < 0: return null
	health[best] -= damage
	if health[best] <= 0.0: _break_asteroid(best)
	# Return both the hit position and the asteroid index so callers
	# (e.g. chain mining) can exclude the just-hit asteroid.
	return {"position": origin + dir * best_hd, "index": best}


## Return the index of the nearest live asteroid to `from`, optionally
## excluding one index. Used by chain mining to avoid re-hitting the
## same asteroid that was just damaged.
func get_nearest_to_excluding(from: Vector3, max_range: float, exclude_idx: int) -> int:
	var best: int = -1
	var best_d: float = max_range
	for i in _count:
		if not alive[i]: continue
		if i == exclude_idx: continue
		var d: float = positions[i].distance_to(from)
		if d > max_range: continue
		if d < best_d:
			best_d = d
			best = i
	return best


## Return the nearest live asteroid excluding a list of indices.
## Used by chain mining (Diablo 2 style) to ensure the chain never
## bounces back to any previously-hit asteroid.
func get_nearest_to_excluding_many(from: Vector3, max_range: float, exclude_indices: Array) -> int:
	var best: int = -1
	var best_d: float = max_range
	for i in _count:
		if not alive[i]: continue
		if i in exclude_indices: continue
		var d: float = positions[i].distance_to(from)
		if d > max_range: continue
		if d < best_d:
			best_d = d
			best = i
	return best


static func _ray_sphere_hit(o: Vector3, d: Vector3, md: float, c: Vector3, r: float) -> float:
	var oc: Vector3 = c - o; var p: float = oc.dot(d)
	if p < 0.0: return -1.0
	var r2: float = r * r; var d2: float = oc.length_squared() - p * p
	if d2 > r2: return -1.0
	var hc: float = sqrt(r2 - d2); var t: float = p - hc
	if t < 0.0: t = p + hc
	if t > md: return -1.0
	return t


func _break_asteroid(idx: int) -> void:
	var sz: int = size_idx[idx]; var def: Array = SIZE_DEFS[sz]
	var pos: Vector3 = positions[idx]
	var children: int = def[4]; var gems: int = def[5]
	alive[idx] = 0; _live -= 1
	mmi.multimesh.set_instance_transform(idx, Transform3D.IDENTITY)
	_pool.append(idx)
	if children > 0 and _live + children < max_asteroids:
		var child_sz: int = mini(sz + 1, Size.SMALL)
		for _c in children:
			var cp: Vector3 = pos + Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0))
			cp.y = 0.8
			var ci: int = _add_asteroid(cp, child_sz)
			_bake(ci)
	if gems > 0 and gem_scene:
		# Prefer the central GemManager (MultiMesh rendering).
		var gm: Node = _get_gem_manager()
		var parent: Node = get_parent() if gm == null else gm
		for _g in gems:
			var gem: Node3D = gem_scene.instantiate() as Node3D
			if gem == null: continue
			var sp: Vector3 = pos + Vector3(rng.randf_range(-0.4, 0.4), 0.0, rng.randf_range(-0.4, 0.4))
			sp.y = 0.3
			parent.add_child(gem); gem.global_position = sp
	asteroid_destroyed.emit(pos, gems)


func check_ship_collision(sp: Vector3, sr: float, dmg: float) -> float:
	for i in _count:
		if not alive[i]: continue
		if sp.distance_squared_to(positions[i]) < (0.85 * base_scale[i] + sr) * (0.85 * base_scale[i] + sr): return dmg
	return 0.0


func find_in_cone(origin: Vector3, forward: Vector3, cone_dot: float, range: float) -> int:
	var best: int = -1; var bd: float = INF
	for i in _count:
		if not alive[i]: continue
		var to: Vector3 = positions[i] - origin; var d: float = to.length()
		if d > range: continue
		if forward.dot(to / max(d, 0.0001)) < cone_dot: continue
		if d < bd: bd = d; best = i
	return best


func get_asteroid_pos(idx: int) -> Vector3:
	if idx < 0 or idx >= max_asteroids: return Vector3.ZERO
	return positions[idx]

## Find the index of the nearest live asteroid to `from` within `max_range`.
## Returns -1 if none found. Used by the chain-mining skill.
func get_nearest_to(from: Vector3, max_range: float) -> int:
	var best: int = -1
	var best_d: float = max_range
	for i in _count:
		if not alive[i]: continue
		var d: float = positions[i].distance_to(from)
		if d > max_range: continue
		if d < best_d:
			best_d = d
			best = i
	return best

## Get the radius of the asteroid at idx (used for visual chain targets).
func get_asteroid_radius(idx: int) -> float:
	if idx < 0 or idx >= max_asteroids: return 0.85
	return 0.85 * base_scale[idx]


var _chip_pool: Array[MeshInstance3D] = []

func spawn_chips(at: Vector3, count: int = 4) -> void:
	for _c in count:
		var mi: MeshInstance3D
		if _chip_pool.size() > 0:
			mi = _chip_pool.pop_back()
		else:
			mi = MeshInstance3D.new()
			mi.mesh = BoxMesh.new()
			(mi.mesh as BoxMesh).size = Vector3(0.06, 0.06, 0.06)
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.5 + rng.randf() * 0.2, 0.45 + rng.randf() * 0.15, 0.35 + rng.randf() * 0.15)
			mat.metallic = 0.1; mat.roughness = 0.8
			mi.material_override = mat
		add_child(mi)
		mi.global_position = at + Vector3(rng.randf_range(-0.15, 0.15), 0.0, rng.randf_range(-0.15, 0.15))
		mi.rotation = Vector3(rng.randf_range(0, TAU), rng.randf_range(0, TAU), rng.randf_range(0, TAU))
		mi.scale = Vector3.ONE
		var tw := create_tween()
		tw.tween_interval(0.4 + rng.randf() * 0.3)
		tw.tween_property(mi, "scale", Vector3.ZERO, 0.2)
		tw.tween_callback(_recycle_chip.bind(mi))


func _recycle_chip(mi: MeshInstance3D) -> void:
	mi.get_parent().remove_child(mi)
	_chip_pool.append(mi)


func _build_mesh() -> ArrayMesh:
	var verts: PackedVector3Array = _icosphere(2)
	rng.seed = 12345
	for i in verts.size():
		var n: Vector3 = verts[i].normalized()
		var w: float = sin(n.x * 3.7 + 0.2) * 0.18 + cos(n.y * 4.3 + 0.4) * 0.18 + sin(n.z * 2.9 + 0.6) * 0.18 + 0.05
		verts[i] = n * (1.0 + w)
	var nmls: PackedVector3Array = PackedVector3Array()
	nmls.resize(verts.size())
	for t in verts.size() / 3:
		var a: Vector3 = verts[t * 3]; var b: Vector3 = verts[t * 3 + 1]; var c: Vector3 = verts[t * 3 + 2]
		var fn: Vector3 = (b - a).cross(c - a).normalized()
		if fn.dot((a + b + c) / 3.0) < 0.0: fn = -fn
		nmls[t * 3] = fn; nmls[t * 3 + 1] = fn; nmls[t * 3 + 2] = fn
	var ind: PackedInt32Array = PackedInt32Array()
	for i in verts.size(): ind.append(i)
	var aa: Array = []; aa.resize(Mesh.ARRAY_MAX)
	aa[Mesh.ARRAY_VERTEX] = verts; aa[Mesh.ARRAY_NORMAL] = nmls; aa[Mesh.ARRAY_INDEX] = ind
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, aa)
	return m


func _icosphere(sub: int) -> PackedVector3Array:
	var phi: float = (1.0 + sqrt(5.0)) / 2.0
	var bv: Array[Vector3] = [
		Vector3(-1, phi, 0), Vector3(1, phi, 0), Vector3(-1, -phi, 0), Vector3(1, -phi, 0),
		Vector3(0, -1, phi), Vector3(0, 1, phi), Vector3(0, -1, -phi), Vector3(0, 1, -phi),
		Vector3(phi, 0, -1), Vector3(phi, 0, 1), Vector3(-phi, 0, -1), Vector3(-phi, 0, 1)]
	var bf: Array[Vector3i] = [
		Vector3i(0, 11, 5), Vector3i(0, 5, 1), Vector3i(0, 1, 7), Vector3i(0, 7, 10), Vector3i(0, 10, 11),
		Vector3i(1, 5, 9), Vector3i(5, 11, 4), Vector3i(11, 10, 2), Vector3i(10, 7, 6), Vector3i(7, 1, 8),
		Vector3i(3, 9, 4), Vector3i(3, 4, 2), Vector3i(3, 2, 6), Vector3i(3, 6, 8), Vector3i(3, 8, 9),
		Vector3i(4, 9, 5), Vector3i(2, 4, 11), Vector3i(6, 2, 10), Vector3i(8, 6, 7), Vector3i(9, 8, 1)]
	for i in bv.size(): bv[i] = bv[i].normalized()
	var fcs: Array[Vector3i] = bf.duplicate(); var cache: Dictionary = {}
	for _s in sub:
		var nf: Array[Vector3i] = []
		for fc in fcs:
			var a: int = fc.x; var b: int = fc.y; var c: int = fc.z
			var ab: int = _mid(a, b, bv, cache); var bc: int = _mid(b, c, bv, cache); var ca: int = _mid(c, a, bv, cache)
			nf.append(Vector3i(a, ab, ca)); nf.append(Vector3i(b, bc, ab)); nf.append(Vector3i(c, ca, bc)); nf.append(Vector3i(ab, bc, ca))
		fcs = nf
	for i in bv.size(): bv[i] = bv[i].normalized()
	var out: PackedVector3Array = PackedVector3Array()
	out.resize(fcs.size() * 3); var idx: int = 0
	for fc in fcs: out[idx] = bv[fc.x]; out[idx + 1] = bv[fc.y]; out[idx + 2] = bv[fc.z]; idx += 3
	return out


static func _mid(a: int, b: int, verts: Array[Vector3], cache: Dictionary) -> int:
	var lo: int = mini(a, b); var hi: int = maxi(a, b)
	var key: Vector2i = Vector2i(lo, hi)
	if cache.has(key): return cache[key]
	var m: Vector3 = ((verts[a] + verts[b]) * 0.5).normalized()
	var ni: int = verts.size(); verts.append(m)
	cache[key] = ni; return ni
