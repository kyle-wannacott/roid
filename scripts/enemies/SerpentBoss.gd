extends BaseEnemy
class_name SerpentBoss

## A chain of spheres forming a snake boss with turrets on each segment.
## Acts like a hammerhead shark - tries to ram the player with its head.
## Each segment has its own health and turret. When segment health reaches 0,
## that turret is destroyed but the segment remains (dead weight).

@export_group("Movement")
@export var chase_speed: float = 50.0
@export var turn_speed: float = 2.0
@export var ram_speed: float = 70.0
@export var ram_cooldown: float = 4.0
@export var ram_charge_time: float = 1.5

@export_group("Segment Stats")
@export var segment_count: int = 8
@export var segment_health: float = 100.0
@export var segment_spacing: float = 4.0
@export var head_ram_damage: float = 40.0
@export var turret_damage: float = 8.0
@export var turret_fire_rate: float = 1.5

## Movement states
enum State {
	CHASE,
	AIM_RAM,
	RAMMING,
	ORBIT,
}

var state: State = State.CHASE
var _state_timer: float = 0.0
var _ram_timer: float = 0.0
var _ram_direction: Vector3 = Vector3.FORWARD

## Segment data
var _segments: Array[Dictionary] = []  # Each: {node, health, max_health, turret_node, turret_alive, fire_timer}
var _head_node: Node3D = null
var _body_root: Node3D = null
var _follow_points: Array[Vector3] = []  # Trail for segments to follow

## Visual components
var _laser_beam: MeshInstance3D = null

func _ready() -> void:
	# Serpent boss stats - health is total of all segments
	max_health = segment_count * segment_health
	move_speed = chase_speed
	reward_gem_table = {"yellow": 3, "purple": 2, "red": 1}
	fire_rate = turret_fire_rate
	detection_range = 100.0
	attack_range = 80.0
	
	# Build the serpent body
	_build_serpent()
	
	# Initialize health to max (sum of all segments)
	health = max_health
	
	# Initialize follow points
	for i in range(segment_count * 3):
		_follow_points.append(global_position + Vector3(0, 0, i * segment_spacing))
	
	super._ready()
	
	print("SerpentBoss spawned with ", segment_count, " segments")


func _build_serpent() -> void:
	_body_root = Node3D.new()
	_body_root.name = "Body"
	add_child(_body_root)
	
	# Create segments (chain of spheres)
	for i in range(segment_count):
		var segment_data = _create_segment(i)
		_segments.append(segment_data)
		
		# Position segment behind the head
		var segment_pos = Vector3(0, 0, i * segment_spacing)
		segment_data.node.position = segment_pos
		_body_root.add_child(segment_data.node)
	
	# Head is the first segment
	_head_node = _segments[0].node


func _create_segment(index: int) -> Dictionary:
	var segment_node = Node3D.new()
	segment_node.name = "Segment_%d" % index
	
	# Main sphere body
	var sphere := MeshInstance3D.new()
	var sphere_mesh := SphereMesh.new()
	
	# Head is larger, body segments get slightly smaller toward tail
	var radius: float
	if index == 0:
		radius = 3.0  # Head - larger
	else:
		radius = 2.0 - (float(index) / float(segment_count)) * 0.5
		radius = max(radius, 1.2)
	
	sphere_mesh.radius = radius
	sphere_mesh.height = radius * 2.0
	sphere.mesh = sphere_mesh
	
	# Material - dark metallic with red accents for head
	var mat := StandardMaterial3D.new()
	if index == 0:
		# Head - darker with red glow
		mat.albedo_color = Color(0.2, 0.1, 0.1, 1.0)
		mat.emission_enabled = true
		mat.emission = Color(0.3, 0.05, 0.05, 1.0)
		mat.emission_energy_multiplier = 0.5
	else:
		# Body - dark grey metallic
		var shade = 0.15 + (float(index) / float(segment_count)) * 0.1
		mat.albedo_color = Color(shade, shade + 0.05, shade, 1.0)
		mat.emission_enabled = true
		mat.emission = Color(0.1, 0.15, 0.1, 1.0)
		mat.emission_energy_multiplier = 0.2
	mat.metallic = 0.8
	mat.roughness = 0.3
	sphere.material_override = mat
	segment_node.add_child(sphere)
	
	# Add turret on top (except head - head rams instead)
	var turret_node: MeshInstance3D = null
	if index > 0:
		turret_node = _create_turret(segment_node, radius)
	
	# Add glowing eyes on head
	if index == 0:
		_create_eyes(segment_node)
	
	# Add health indicator (small sphere on top)
	var health_indicator := MeshInstance3D.new()
	var health_mesh := SphereMesh.new()
	health_mesh.radius = 0.3
	health_mesh.height = 0.6
	health_indicator.mesh = health_mesh
	var health_mat := StandardMaterial3D.new()
	health_mat.albedo_color = Color(0.0, 1.0, 0.2, 1.0)
	health_mat.emission_enabled = true
	health_mat.emission = Color(0.0, 1.0, 0.2, 1.0)
	health_mat.emission_energy_multiplier = 2.0
	health_indicator.material_override = health_mat
	health_indicator.position = Vector3(0, radius + 0.4, 0)
	segment_node.add_child(health_indicator)
	
	# Create collision for this segment
	var collision := CollisionShape3D.new()
	var collision_shape := SphereShape3D.new()
	collision_shape.radius = radius
	collision.shape = collision_shape
	segment_node.add_child(collision)
	
	return {
		"node": segment_node,
		"health": segment_health,
		"max_health": segment_health,
		"radius": radius,
		"turret_node": turret_node,
		"turret_alive": true,
		"fire_timer": randf() * turret_fire_rate,  # Stagger initial fire times
		"health_indicator": health_indicator,
		"alive": true,
	}


func _create_turret(parent: Node3D, segment_radius: float) -> MeshInstance3D:
	# Turret base
	var turret := MeshInstance3D.new()
	var turret_mesh := CylinderMesh.new()
	turret_mesh.top_radius = 0.4
	turret_mesh.bottom_radius = 0.5
	turret_mesh.height = 0.4
	turret.mesh = turret_mesh
	var turret_mat := StandardMaterial3D.new()
	turret_mat.albedo_color = Color(0.3, 0.3, 0.35, 1.0)
	turret_mat.metallic = 0.9
	turret_mat.roughness = 0.3
	turret.material_override = turret_mat
	turret.position = Vector3(0, segment_radius + 0.2, 0)
	parent.add_child(turret)
	
	# Turret barrel
	var barrel := MeshInstance3D.new()
	var barrel_mesh := CylinderMesh.new()
	barrel_mesh.top_radius = 0.1
	barrel_mesh.bottom_radius = 0.12
	barrel_mesh.height = 0.8
	barrel.mesh = barrel_mesh
	var barrel_mat := StandardMaterial3D.new()
	barrel_mat.albedo_color = Color(0.2, 0.2, 0.25, 1.0)
	barrel_mat.metallic = 0.9
	barrel_mat.roughness = 0.4
	barrel.material_override = barrel_mat
	barrel.position = Vector3(0, 0.5, -0.3)
	barrel.rotation = Vector3(PI * 0.4, 0, 0)  # Angle forward
	turret.add_child(barrel)
	
	return turret


func _create_eyes(parent: Node3D) -> void:
	for side in [-1, 1]:
		var eye := MeshInstance3D.new()
		var eye_mesh := SphereMesh.new()
		eye_mesh.radius = 0.5
		eye_mesh.height = 1.0
		eye.mesh = eye_mesh
		var eye_mat := StandardMaterial3D.new()
		eye_mat.albedo_color = Color(1.0, 0.1, 0.1, 1.0)
		eye_mat.emission_enabled = true
		eye_mat.emission = Color(1.0, 0.2, 0.1, 1.0)
		eye_mat.emission_energy_multiplier = 4.0
		eye.material_override = eye_mat
		eye.position = Vector3(1.0 * side, 0.8, -2.0)
		parent.add_child(eye)


func _update_enemy(delta: float) -> void:
	if not is_alive:
		return
	
	_state_timer += delta
	
	# Update segment health indicators
	_update_segment_visuals()
	
	# Update turret firing
	_update_turret_firing(delta)
	
	# Calculate total remaining health
	_update_total_health()
	
	# Update state
	_update_state()
	
	# Execute state behavior
	match state:
		State.CHASE:
			_update_chase(delta)
		State.AIM_RAM:
			_update_aim_ram(delta)
		State.RAMMING:
			_update_ramming(delta)
		State.ORBIT:
			_update_orbit(delta)
	
	# Update follow points for body segments
	_update_follow_points(delta)
	
	# Update body segment positions (follow the head)
	_update_body_segments(delta)


func _update_state() -> void:
	if target == null or not is_instance_valid(target):
		return
	
	var dist_to_player = get_distance_to_player()
	
	match state:
		State.CHASE:
			# Start ramming when close enough and off cooldown
			if dist_to_player < 200.0 and _ram_timer <= 0:
				state = State.AIM_RAM
				_state_timer = 0.0
			elif dist_to_player > detection_range:
				# Move toward player
				pass
		
		State.AIM_RAM:
			# Brief pause to "aim" before ramming
			if _state_timer > ram_charge_time:
				state = State.RAMMING
				_state_timer = 0.0
		
		State.RAMMING:
			# Ram for a duration, then go back to chase
			if _state_timer > 2.0:
				state = State.CHASE
				_state_timer = 0.0
				_ram_timer = ram_cooldown
		
		State.ORBIT:
			if _state_timer > 3.0:
				state = State.CHASE
				_state_timer = 0.0


func _update_chase(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	
	# Head moves toward player
	var to_target = (target.global_position - global_position)
	to_target.y = 0.0
	
	if to_target.length() > 0.1:
		# Rotate toward player
		var target_angle = atan2(to_target.x, to_target.z)
		var current_angle = rotation.y
		rotation.y = lerp_angle(current_angle, target_angle, turn_speed * delta)
	
	# Move forward
	velocity = -global_transform.basis.z * chase_speed
	velocity.y = 0.0
	move_and_slide()
	
	# Maintain height
	global_position.y = 1.5


func _update_aim_ram(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	
	# Face the player directly
	face_target(delta)
	
	# Slow down while aiming
	velocity = velocity.lerp(Vector3.ZERO, delta * 2.0)
	move_and_slide()


func _update_ramming(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	
	# Calculate ram direction toward player
	_ram_direction = (target.global_position - global_position).normalized()
	_ram_direction.y = 0.0
	
	# Move fast in ram direction
	velocity = _ram_direction * ram_speed
	velocity.y = 0.0
	move_and_slide()
	
	# Maintain height
	global_position.y = 1.5
	
	# Check for collision with player
	var dist_to_player = get_distance_to_player()
	if dist_to_player < 5.0:
		# Ram damage!
		if target.has_method("take_damage"):
			target.take_damage(head_ram_damage)
			# Play impact sound
			SoundManager.play_by_id("sfx_enemy_hit")


func _update_orbit(delta: float) -> void:
	# Slow movement while orbiting
	velocity = velocity.lerp(Vector3.ZERO, delta)
	move_and_slide()


func _update_follow_points(delta: float) -> void:
	# Add current head position to the front of follow points
	_follow_points.insert(0, global_position)
	
	# Keep only enough points for all segments
	var max_points = segment_count * 3
	if _follow_points.size() > max_points:
		_follow_points.resize(max_points)


func _update_body_segments(delta: float) -> void:
	# Each segment follows the one ahead of it
	for i in range(_segments.size()):
		var seg = _segments[i]
		if not seg.alive:
			continue
		
		if i == 0:
			# Head is already positioned (it's the main node)
			seg.node.global_position = global_position
			seg.node.global_rotation = global_rotation
		else:
			# Follow the follow point at index i * spacing
			var follow_index = i * 2
			if follow_index < _follow_points.size():
				var target_pos = _follow_points[follow_index]
				
				# Smoothly move toward target position
				var current_pos = seg.node.global_position
				var new_pos = current_pos.lerp(target_pos, delta * 5.0)
				new_pos.y = 1.5  # Maintain height
				
				# Face the direction of movement
				var direction = (target_pos - current_pos)
				direction.y = 0.0
				if direction.length() > 0.1:
					var target_angle = atan2(direction.x, direction.z)
					seg.node.rotation.y = lerp_angle(seg.node.rotation.y, target_angle, delta * 5.0)
				
				seg.node.global_position = new_pos
			
			# Maintain height
			seg.node.global_position.y = 1.5


func _update_turret_firing(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	
	for i in range(1, _segments.size()):  # Skip head (index 0)
		var seg = _segments[i]
		if not seg.alive or not seg.turret_alive:
			continue
		
		seg.fire_timer -= delta
		if seg.fire_timer <= 0:
			_fire_turret_at_player(seg)
			seg.fire_timer = turret_fire_rate + randf_range(-0.3, 0.3)  # Slight randomness


func _fire_turret_at_player(seg: Dictionary) -> void:
	if target == null or not is_instance_valid(target):
		return
	if not is_inside_tree():
		return
	
	# Verify the turret node still exists and is in the scene tree
	var turret_node = seg.get("turret_node")
	if turret_node == null or not is_instance_valid(turret_node) or not turret_node.is_inside_tree():
		return
	
	# Create red ball projectile
	var projectile = _create_projectile()
	if projectile == null:
		return
	
	# Store position BEFORE any potential frees
	var turret_global_pos: Vector3
	var target_pos: Vector3
	
	# Safely get turret position
	turret_global_pos = global_position + Vector3(0, 2, 0)  # Fallback to boss position
	if turret_node.is_inside_tree():
		turret_global_pos = turret_node.global_position
	
	# Safely get target position  
	target_pos = target.global_position if target.is_inside_tree() else global_position + Vector3(0, 0, -50)
	
	# Add to scene FIRST
	get_tree().current_scene.add_child(projectile)
	projectile.global_position = turret_global_pos
	
	# Aim at player with some lead
	var to_target = target_pos - turret_global_pos
	if "velocity" in target:
		to_target += target.velocity * (to_target.length() / projectile_speed)
	
	var direction = to_target.normalized()
	# Add slight spread
	direction.x += randf_range(-0.05, 0.05)
	direction.z += randf_range(-0.05, 0.05)
	direction = direction.normalized()
	
	# Set projectile properties
	if "velocity" in projectile:
		projectile.velocity = direction * projectile_speed
	if "damage" in projectile:
		projectile.damage = turret_damage


func _create_projectile() -> Node3D:
	# Create a simple red sphere projectile
	var projectile = Node3D.new()
	
	var mesh := MeshInstance3D.new()
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = 0.4
	sphere_mesh.height = 0.8
	mesh.mesh = sphere_mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.2, 0.1, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.3, 0.1, 1.0)
	mat.emission_energy_multiplier = 3.0
	mesh.material_override = mat
	projectile.add_child(mesh)
	
	# Add glow light
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.3, 0.1)
	light.light_energy = 2.0
	light.omni_range = 4.0
	projectile.add_child(light)
	
	# Add collision
	var collision := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.5
	collision.shape = shape
	projectile.add_child(collision)
	
	# Add area for detecting player hits
	var area := Area3D.new()
	area.name = "HitArea"
	area.collision_layer = 0
	area.collision_mask = 1  # Player layer
	var area_collision := CollisionShape3D.new()
	area_collision.shape = shape.duplicate()
	area.add_child(area_collision)
	projectile.add_child(area)
	
	# Simple projectile script
	var script = GDScript.new()
	script.source_code = """
extends Node3D

var velocity: Vector3 = Vector3.FORWARD * 80.0
var damage: float = 8.0
var lifetime: float = 3.0
var age: float = 0.0
@onready var _hit_area: Area3D = $HitArea

func _physics_process(delta: float) -> void:
	age += delta
	if age > lifetime:
		queue_free()
		return
	
	global_position += velocity * delta
	
	# Check for player collision via the child Area3D
	if _hit_area != null:
		for body in _hit_area.get_overlapping_bodies():
			if body.is_in_group("player_ship"):
				if body.has_method("take_damage"):
					body.take_damage(damage)
				queue_free()
				return
"""
	script.reload()
	projectile.set_script(script)
	
	return projectile


func _update_segment_visuals() -> void:
	for i in range(_segments.size()):
		var seg = _segments[i]
		
		# Update health indicator color
		if seg.health_indicator != null:
			var health_pct = seg.health / seg.max_health
			var mat = seg.health_indicator.material_override as StandardMaterial3D
			if mat:
				if health_pct > 0.5:
					mat.albedo_color = Color(0.0, 1.0, 0.2, 1.0)
					mat.emission = Color(0.0, 1.0, 0.2, 1.0)
				elif health_pct > 0.25:
					mat.albedo_color = Color(1.0, 1.0, 0.0, 1.0)
					mat.emission = Color(1.0, 1.0, 0.0, 1.0)
				else:
					mat.albedo_color = Color(1.0, 0.2, 0.1, 1.0)
					mat.emission = Color(1.0, 0.2, 0.1, 1.0)
		
		# Hide turret if destroyed
		if seg.turret_node != null and not seg.turret_alive:
			seg.turret_node.visible = false
		
		# Dim dead segments
		if not seg.alive:
			var sphere = seg.node.get_child(0) as MeshInstance3D
			if sphere and sphere.material_override:
				var mat = sphere.material_override as StandardMaterial3D
				if mat:
					mat.albedo_color = Color(0.05, 0.05, 0.05, 1.0)
					mat.emission_energy_multiplier = 0.0


func _update_total_health() -> void:
	var total = 0.0
	for seg in _segments:
		total += seg.health
	health = total
	
	# Die when all segments are dead
	if health <= 0:
		die()


## Override take_damage to damage specific segments
func take_damage(amount: float) -> void:
	if not is_alive:
		return
	
	# Find the first alive segment and damage it
	# Start from head (index 0) and work backward
	for i in range(_segments.size()):
		if _segments[i].alive:
			_damage_segment(i, amount)
			return


func damage_segment(segment_index: int, amount: float) -> void:
	if segment_index < 0 or segment_index >= _segments.size():
		return
	_damage_segment(segment_index, amount)


## Damage the segment closest to a world position
func damage_nearest_segment(hit_pos: Vector3, amount: float) -> void:
	var nearest_idx = -1
	var nearest_dist = INF
	
	for i in range(_segments.size()):
		if not _segments[i].alive:
			continue
		var dist = _segments[i].node.global_position.distance_to(hit_pos)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest_idx = i
	
	if nearest_idx >= 0 and nearest_idx < _segments.size():
		_damage_segment(nearest_idx, amount)


func _damage_segment(index: int, amount: float) -> void:
	if index < 0 or index >= _segments.size():
		return
	
	var seg = _segments[index]
	if not seg.alive:
		return
	
	seg.health -= amount
	
	# Flash the segment red
	_flash_segment(index)
	
	# Destroy turret if segment health is low
	if seg.health <= seg.max_health * 0.5 and seg.turret_alive:
		seg.turret_alive = false
	
	# Kill segment if health reaches 0
	if seg.health <= 0:
		seg.health = 0
		seg.alive = false
		_kill_segment(index)


func _flash_segment(index: int) -> void:
	if index < 0 or index >= _segments.size():
		return
	var seg = _segments[index]
	if seg.node == null or not is_instance_valid(seg.node):
		return
	var sphere = seg.node.get_child(0) as MeshInstance3D
	if sphere and sphere.material_override:
		var mat = sphere.material_override as StandardMaterial3D
		if mat:
			# Flash white briefly
			var original_color = mat.albedo_color
			mat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
			# Reset after brief delay - check if node still valid (use instance_id)
			var self_id := get_instance_id()
			var seg_node_id: int = seg.node.get_instance_id()
			get_tree().create_timer(0.1).timeout.connect(func():
				var boss := instance_from_id(self_id) as Node
				var node := instance_from_id(seg_node_id) as Node3D
				if boss != null and node != null and mat != null and is_instance_valid(mat):
					mat.albedo_color = original_color
			)


func _kill_segment(index: int) -> void:
	var seg = _segments[index]
	
	# Spawn small explosion
	var explosion = OmniLight3D.new()
	explosion.light_color = Color(1.0, 0.5, 0.2)
	explosion.light_energy = 5.0
	explosion.omni_range = 8.0
	# Add to scene FIRST, then set global_position
	get_tree().current_scene.add_child(explosion)
	explosion.global_position = seg.node.global_position
	
	var tween = create_tween()
	tween.tween_property(explosion, "light_energy", 0.0, 0.3)
	tween.tween_callback(explosion.queue_free)


func _spawn_death_effect() -> void:
	# Massive chain of explosions along the body
	for i in range(_segments.size()):
		var seg = _segments[i]
		if not is_instance_valid(seg.node):
			continue
		
		var explosion = OmniLight3D.new()
		explosion.light_color = Color(1.0, 0.4, 0.1)
		explosion.light_energy = 12.0
		explosion.omni_range = 20.0
		# Add to scene FIRST, then set global_position
		get_tree().current_scene.add_child(explosion)
		explosion.global_position = seg.node.global_position + Vector3(randf_range(-3, 3), randf_range(-2, 2), randf_range(-3, 3))
		
		var tween = create_tween()
		tween.tween_property(explosion, "light_energy", 0.0, 0.4 + randf() * 0.3)
		tween.tween_callback(explosion.queue_free)
		
		# Stagger explosions slightly
		await get_tree().create_timer(0.05).timeout
	
	# Spawn bonus gems (using typed gem table)
	const GEM_SCENE: PackedScene = preload("res://scenes/Gem.tscn")
	var gem_table: Dictionary = get_reward_gem_table()
	for type in gem_table:
		var count: int = int(gem_table[type])
		for _i in count:
			var gem: Node3D = GEM_SCENE.instantiate() as Node3D
			if gem == null:
				continue
			gem.gem_type = type
			var offset := Vector3(
				randf_range(-2.0, 2.0),
				0.5,
				randf_range(-2.0, 2.0)
			)
			get_tree().current_scene.add_child(gem)
			gem.global_position = global_position + offset
	
	queue_free()
