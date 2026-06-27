extends Node3D
class_name Bullet
## A projectile fired from the ship's turret.
## Supports pierce, ricochet, chain lightning, frost shot, critical hits,
## and bullet scaling — all driven by skill effects.

@export var speed: float = 150.0
@export var lifetime: float = 2.0
@export var damage: float = 10.0

# Skill-driven properties (set by the ship when firing)
var bullet_scale: float = 1.0       # turret_big_bullets
var pierce_count: int = 0           # turret_projectile_pierce (0 = no pierce)
var ricochet_chance: float = 0.0    # ricochet_rounds (0.0-1.0)
var chain_chance: float = 0.0       # chain_lightning (0.0-1.0)
var chain_count: int = 0            # chain_lightning (how many chains)
var slow_chance: float = 0.0        # frost_shot
var slow_duration: float = 0.0
var slow_factor: float = 0.0
var crit_chance: float = 0.0        # critical_chance (0.0-1.0)
var crit_damage_mult: float = 0.0   # critical_multiplier (added multiplier)

var _age: float = 0.0
var _hit_enemies: Array = []  # Track enemies already hit to prevent multi-hit
var _is_critical: bool = false

# Cached reference to the current scene for spawning effects
var _scene: Node = null


func _ready() -> void:
	# Build mesh based on scale
	var body := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.04 * bullet_scale
	cyl.bottom_radius = 0.04 * bullet_scale
	cyl.height = 0.4 * bullet_scale
	body.mesh = cyl
	body.rotation = Vector3(PI * 0.5, 0, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 1.0, 0.3, 1)  # Green for player bullets
	mat.emission_enabled = true
	mat.emission = Color(0.3, 1.0, 0.4, 1)
	mat.emission_energy_multiplier = 5.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	body.material_override = mat
	add_child(body)
	
	# Critical hit visual: orange glow
	if _is_critical:
		mat.albedo_color = Color(1.0, 0.6, 0.1, 1)
		mat.emission = Color(1.0, 0.7, 0.0, 1)
		mat.emission_energy_multiplier = 8.0
	
	# Scale the collision shape too
	var hitbox := Area3D.new()
	hitbox.collision_layer = 0
	hitbox.collision_mask = 8
	var hitbox_shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.5 * bullet_scale
	hitbox_shape.shape = sphere
	hitbox.add_child(hitbox_shape)
	hitbox.body_entered.connect(_on_hitbox_body_entered)
	add_child(hitbox)
	
	_scene = get_tree().current_scene


func _physics_process(delta: float) -> void:
	_age += delta
	if _age > lifetime:
		queue_free()
		return
	global_position += -global_transform.basis.z * speed * delta
	
	# Check for enemy hits
	_check_enemy_hits()


func _check_enemy_hits() -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		if enemy in _hit_enemies:
			continue
		if not (enemy.get("is_alive") == true):
			continue
		if not enemy.has_method("take_damage"):
			continue
		
		var dist = global_position.distance_to(enemy.global_position)
		if dist < 3.0 * bullet_scale:
			_hit_enemy(enemy)


func _hit_enemy(enemy: Node3D) -> void:
	var hit_pos = global_position
	
	# --- Damage calculation ---
	var final_damage = damage
	if _is_critical:
		final_damage += damage * crit_damage_mult
	
	# Apply damage
	if enemy.has_method("damage_nearest_segment"):
		enemy.damage_nearest_segment(hit_pos, final_damage)
	else:
		enemy.take_damage(final_damage)
	
	_hit_enemies.append(enemy)
	
	# --- Frost Shot: slow the enemy ---
	if slow_chance > 0.0 and randf() < slow_chance:
		_apply_slow(enemy)
	
	# --- Spawn impact effect ---
	_spawn_impact_effect(hit_pos, _is_critical)
	
	# --- Pierce: don't queue_free yet, keep going ---
	if pierce_count > 0 and _hit_enemies.size() <= pierce_count:
		return  # Keep flying
	
	# --- Ricochet: bounce to a nearby enemy ---
	if ricochet_chance > 0.0 and randf() < ricochet_chance:
		var target = _find_nearby_enemy(hit_pos, 30.0)
		if target != null:
			_ricochet_to(target)
			return  # Don't free yet — ricochet continues
	
	# --- Chain Lightning: chain to nearby enemies ---
	if chain_chance > 0.0 and chain_count > 0 and randf() < chain_chance:
		_chain_lightning(hit_pos, chain_count, [enemy])
		# The bullet still dies after chaining
		queue_free()
		return
	
	queue_free()


func _apply_slow(enemy: Node3D) -> void:
	# Store slow properties on the enemy so its movement code can read them
	enemy.set_meta("frost_slow_factor", slow_factor)
	enemy.set_meta("frost_slow_timer", slow_duration)
	# Visual: blue tint
	if enemy.has_method("_flash_frost"):
		enemy._flash_frost()
	elif enemy.has_method("_flash_segment"):
		# For serpent boss, flash the nearest segment
		var seg_idx = _find_nearest_segment_index(enemy)
		if seg_idx >= 0:
			enemy._flash_segment(seg_idx)
	# Spawn a small blue flash
	var flash := OmniLight3D.new()
	flash.light_color = Color(0.3, 0.8, 1.0)
	flash.light_energy = 4.0
	flash.omni_range = 4.0
	if _scene:
		_scene.add_child(flash)
		flash.global_position = enemy.global_position
		var tween := create_tween()
		tween.tween_property(flash, "light_energy", 0.0, 0.3)
		tween.tween_callback(flash.queue_free)


func _find_nearby_enemy(from_pos: Vector3, max_range: float) -> Node3D:
	var best: Node3D = null
	var best_d: float = max_range
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		if enemy in _hit_enemies:
			continue
		if not (enemy.get("is_alive") == true):
			continue
		var d = enemy.global_position.distance_to(from_pos)
		if d < best_d:
			best_d = d
			best = enemy
	return best


func _ricochet_to(target: Node3D) -> void:
	# Redirect toward the new target
	var dir = (target.global_position - global_position).normalized()
	dir.y = 0.0
	if dir.length() < 0.01:
		dir = Vector3(0, 0, -1)
	look_at(global_position + dir, Vector3.UP)
	# Visual: spawn a spark at the ricochet point
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.9, 0.3)
	flash.light_energy = 3.0
	flash.omni_range = 3.0
	if _scene:
		_scene.add_child(flash)
		flash.global_position = global_position
		var tween := create_tween()
		tween.tween_property(flash, "light_energy", 0.0, 0.1)
		tween.tween_callback(flash.queue_free)
	# Reset lifetime so the ricochet bullet travels further
	_age = 0.0


func _chain_lightning(from_pos: Vector3, remaining: int, visited: Array) -> void:
	if remaining <= 0:
		return
	var target = _find_nearby_enemy(from_pos, 25.0)
	if target == null:
		return
	# Damage the chained target (half damage for chains)
	var chain_dmg = damage * 0.5
	if target.has_method("damage_nearest_segment"):
		target.damage_nearest_segment(from_pos, chain_dmg)
	else:
		target.take_damage(chain_dmg)
	# Frost shot can also apply on chains
	if slow_chance > 0.0 and randf() < slow_chance:
		_apply_slow(target)
	# Visual: lightning beam between points
	_spawn_chain_beam(from_pos, target.global_position)
	# Recurse
	visited.append(target)
	_chain_lightning(target.global_position, remaining - 1, visited)


func _spawn_chain_beam(from: Vector3, to: Vector3) -> void:
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 6
	var radius := 0.06
	var forward := (to - from).normalized()
	var up := Vector3.UP
	if abs(forward.dot(up)) > 0.95:
		up = Vector3.RIGHT
	var right := forward.cross(up).normalized()
	var u := right.cross(forward).normalized()
	var points_top: Array[Vector3] = []
	var points_bot: Array[Vector3] = []
	for i in segs:
		var a := float(i) / float(segs) * TAU
		var offset := (right * cos(a) + u * sin(a)) * radius
		points_top.append(from + offset)
		points_bot.append(to + offset)
	for i in segs:
		var i2 := (i + 1) % segs
		im.surface_add_vertex(points_top[i])
		im.surface_add_vertex(points_top[i2])
		im.surface_add_vertex(points_bot[i2])
		im.surface_add_vertex(points_top[i])
		im.surface_add_vertex(points_bot[i2])
		im.surface_add_vertex(points_bot[i])
	im.surface_end()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = 0
	mat.transparency = 1
	mat.albedo_color = Color(0.3, 0.8, 1.0, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(0.2, 0.7, 1.0, 1.0)
	mat.emission_energy_multiplier = 4.0
	var mi := MeshInstance3D.new()
	mi.mesh = im
	mi.material_override = mat
	mi.top_level = true
	if _scene:
		_scene.add_child(mi)
		mi.global_position = Vector3.ZERO
		# Use instance ID to avoid lambda capture of freed node
		var mi_id := mi.get_instance_id()
		var t := get_tree().create_timer(0.2)
		t.timeout.connect(func():
			var node := instance_from_id(mi_id)
			if node != null:
				node.queue_free())


func _find_nearest_segment_index(enemy: Node3D) -> int:
	if enemy.has_method("get_nearest_segment_index"):
		return enemy.get_nearest_segment_index(global_position)
	return -1


func _on_hitbox_body_entered(body: Node3D) -> void:
	# Area3D collision fallback — mostly handled by _check_enemy_hits
	pass


func _spawn_impact_effect(pos: Vector3, critical: bool = false) -> void:
	var color := Color(0.3, 1.0, 0.4)  # Green normal
	if critical:
		color = Color(1.0, 0.7, 0.1)  # Orange for crits
	var flash := OmniLight3D.new()
	flash.light_color = color
	flash.light_energy = 3.0
	flash.omni_range = 3.0
	if _scene:
		_scene.add_child(flash)
		flash.global_position = pos
		var tween := create_tween()
		tween.tween_property(flash, "light_energy", 0.0, 0.1)
		tween.tween_callback(flash.queue_free)
