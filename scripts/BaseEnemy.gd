extends CharacterBody3D
class_name BaseEnemy

## Abstract base class for all enemies.
## Provides common functionality for health, damage, death, and rewards.

## Distance from station (origin) at which enemies break off approach.
## Enemies inside this radius will be redirected to patrol instead.
const STATION_INNER_SAFETY: float = 200.0

signal health_changed(new_health: float, max_health: float)
signal died()
signal took_damage(amount: float)

@export_group("Stats")
@export var max_health: float = 100.0
@export var move_speed: float = 100.0
@export var rotation_speed: float = 2.0
@export var collision_damage: float = 10.0

@export_group("Rewards")
## Dictionary of gem type → count, e.g. {"green": 2, "blue": 1}.
## Each gem becomes a physical pickup in the world.
@export var reward_gem_table: Dictionary = {"green": 1}
@export var reward_skill_points: int = 0

@export_group("Combat")
@export var fire_rate: float = 1.0
@export var projectile_damage: float = 10.0
@export var projectile_speed: float = 300.0
@export var detection_range: float = 200.0
@export var attack_range: float = 150.0

@export_group("Visual")
@export var damage_flash_duration: float = 0.15

## Runtime state
var health: float
var target: Node3D = null
var is_alive: bool = true
var _spawn_position: Vector3 = Vector3.ZERO
var _fire_timer: float = 0.0
var _damage_flash_timer: float = 0.0

## Frost slow state (set by Bullet.gd via set_meta)
var _frost_slow_factor: float = 1.0
var _frost_slow_timer: float = 0.0

## Mesh references for damage flash
var _mesh_instances: Array[MeshInstance3D] = []
var _original_materials: Array[Material] = []

## Reference to ship
var _ship: Node3D = null

func _ready() -> void:
	health = max_health
	add_to_group("enemies")
	_find_ship()
	# Set target to the player ship so enemies can detect/chase/attack
	target = _ship
	_collect_meshes()
	_ensure_collision()
	_ensure_hurtbox()

func _find_ship() -> void:
	_ship = get_tree().get_first_node_in_group("player_ship")
	# Also set target so subclasses can use it for chase/attack
	if _ship != null and target == null:
		target = _ship

func _collect_meshes() -> void:
	# Collect all mesh instances for damage flash effect
	for child in get_children():
		if child is MeshInstance3D:
			_mesh_instances.append(child)
			_original_materials.append(child.material_override)
		elif child.has_method("get_children"):
			for grandchild in child.get_children():
				if grandchild is MeshInstance3D:
					_mesh_instances.append(grandchild)
					_original_materials.append(grandchild.material_override)

func _physics_process(delta: float) -> void:
	if not is_alive:
		return
	
	# Update damage flash
	if _damage_flash_timer > 0:
		_damage_flash_timer -= delta
		if _damage_flash_timer <= 0:
			_reset_flash()
	
	# Update fire timer
	if _fire_timer > 0:
		_fire_timer -= delta
	
	# Update frost slow
	if _frost_slow_timer > 0.0:
		_frost_slow_timer = max(0.0, _frost_slow_timer - delta)
		# Check for externally-set slow (from Bullet.gd)
		var ext_factor = get_meta("frost_slow_factor", 1.0)
		var ext_timer = get_meta("frost_slow_timer", 0.0)
		if ext_timer > _frost_slow_timer:
			_frost_slow_factor = ext_factor
			_frost_slow_timer = ext_timer
			remove_meta("frost_slow_factor")
			remove_meta("frost_slow_timer")
	if _frost_slow_timer <= 0.0:
		_frost_slow_factor = 1.0
	
	# Call subclass update
	_update_enemy(delta)

func _ensure_collision() -> void:
	# Ensure we have a collision shape
	var has_collision = false
	for child in get_children():
		if child is CollisionShape3D:
			has_collision = true
			break
	
	if not has_collision:
		# Create a default collision shape
		var collision = CollisionShape3D.new()
		var shape = BoxShape3D.new()
		shape.size = Vector3(1.0, 0.5, 1.5)
		collision.shape = shape
		add_child(collision)

func _ensure_hurtbox() -> void:
	# Ensure we have an Area3D for detecting player collisions
	var has_hurtbox = false
	for child in get_children():
		if child is Area3D and child.is_in_group("enemy_hurtbox"):
			has_hurtbox = true
			break
	
	if not has_hurtbox:
		var hurtbox = Area3D.new()
		hurtbox.add_to_group("enemy_hurtbox")
		# Set collision layer to 8 (layer 4) so bullets/missiles can detect us
		hurtbox.collision_layer = 8
		hurtbox.collision_mask = 0  # We don't need to detect anything
		var collision = CollisionShape3D.new()
		var shape = BoxShape3D.new()
		shape.size = Vector3(1.2, 0.6, 1.8)
		collision.shape = shape
		hurtbox.add_child(collision)
		add_child(hurtbox)
		
		# Connect signal
		hurtbox.body_entered.connect(_on_body_entered)

## Override this in subclasses
func _update_enemy(_delta: float) -> void:
	pass

## Called by EnemyManager when the enemy drifts inside the station safety
## zone. The enemy should smoothly break off its approach and return to
## patrolling. Override in subclasses with state-machine awareness.
func break_off_from_station() -> void:
	# Default: pick a new patrol target away from the station
	_pick_new_patrol_target()


## Stub — subclasses override this to pick a patrol target away from the station.
## Subclasses use `_compute_patrol_target(min_radius, max_radius)` to
## generate a random point around `_spawn_position`.
func _pick_new_patrol_target() -> void:
	pass

## Public hook for the EnemyManager to set the spawn anchor AFTER the
## enemy has been positioned in the world. The subclass `_ready()` runs
## when `add_child()` is called, which is BEFORE the manager sets
## `global_position` — so capturing `_spawn_position = global_position`
## in `_ready()` would record the manager's position (the origin) instead
## of the actual spawn point. The manager must call this after positioning.
##
## This is also the right place to re-seed the patrol target now that
## we know the real spawn location.
func set_spawn_position(pos: Vector3) -> void:
	_spawn_position = pos
	_pick_new_patrol_target()

## Returns the distance from `_spawn_position` to the player's current
## position. Used by subclasses to enforce a "leash" — the enemy will
## break off chase and return to its spawn if the player strays beyond
## the patrol radius.
func _distance_player_to_spawn() -> float:
	if target == null or not is_instance_valid(target):
		return INF
	return _spawn_position.distance_to(target.global_position)

## Returns a random patrol position around `_spawn_position` within
## the given radius range. The enemy patrols a circle (not just an
## outward arc) so it guards a real territory. The leash on `_spawn_position`
## (see subclasses' state machines) is what keeps the enemy from
## drifting toward the station — not this helper.
func _compute_patrol_target(min_radius: float, max_radius: float) -> Vector3:
	var radius: float = randf_range(min_radius, max_radius)
	var angle: float = randf() * TAU

	var offset := Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
	return _spawn_position + offset

## Returns true if the enemy is inside the station's inner safety zone.
func is_near_station() -> bool:
	return global_position.length() < STATION_INNER_SAFETY

## Take damage from player
func take_damage(amount: float) -> void:
	if not is_alive:
		return
	
	health -= amount
	health_changed.emit(health, max_health)
	took_damage.emit(amount)
	
	# Spawn damage number
	if DamageNumberManager.instance:
		DamageNumberManager.instance.spawn_damage(amount, global_position)
	
	# Flash effect
	_apply_flash()
	
	if health <= 0:
		die()

## Apply damage flash effect
func _apply_flash() -> void:
	_damage_flash_timer = damage_flash_duration
	for mesh in _mesh_instances:
		if mesh and mesh.material_override:
			var mat = mesh.material_override as StandardMaterial3D
			if mat:
				mat.albedo_color = Color(1.0, 0.3, 0.3)

## Reset flash effect
func _reset_flash() -> void:
	for i in range(_mesh_instances.size()):
		var mesh = _mesh_instances[i]
		if mesh and i < _original_materials.size():
			mesh.material_override = _original_materials[i]

## Die and emit signals
func die() -> void:
	if not is_alive:
		return
	
	is_alive = false
	died.emit()
	
	# Play enemy explosion sound
	SoundManager.play_by_id("sfx_enemy_explode")
	
	# Spawn death effect (override in subclass for custom effects)
	_spawn_death_effect()

func _exit_tree() -> void:
	# Clean up materials to prevent rendering resource leaks
	for i in range(_mesh_instances.size()):
		var mesh = _mesh_instances[i]
		if mesh and is_instance_valid(mesh):
			# Restore original material before freeing
			if i < _original_materials.size():
				mesh.material_override = _original_materials[i]
	_mesh_instances.clear()
	_original_materials.clear()

## Visual feedback when hit by Frost Shot — tints the enemy blue briefly.
func _flash_frost() -> void:
	for i in range(_mesh_instances.size()):
		var mesh = _mesh_instances[i]
		if mesh and i < _original_materials.size() and is_instance_valid(mesh):
			var mat = _original_materials[i] as StandardMaterial3D
			if mat:
				var orig_emission = mat.emission
				var orig_albedo = mat.albedo_color
				mat.albedo_color = Color(0.3, 0.6, 1.0, 1.0)
				mat.emission = Color(0.2, 0.5, 1.0, 1.0)
				mat.emission_energy_multiplier = 3.0
				# Capture index instead of mesh reference to avoid freed-pointer errors
				var idx := i
				var orig_e: Color = orig_emission
				var orig_a: Color = orig_albedo
				get_tree().create_timer(0.4).timeout.connect(func():
					if idx < _mesh_instances.size() and is_instance_valid(_mesh_instances[idx]):
						var m := _mesh_instances[idx]
						if m and m.material_override:
							var restore_mat = m.material_override as StandardMaterial3D
							if restore_mat:
								restore_mat.albedo_color = orig_a
								restore_mat.emission = orig_e
								restore_mat.emission_energy_multiplier = 0.3
				, CONNECT_ONE_SHOT)


## Override in subclass for custom death effects
func _spawn_death_effect() -> void:
	# Default: just queue free after a brief delay
	await get_tree().create_timer(0.1).timeout
	queue_free()

## Get reward gems (called by EnemyManager)
## Returns the effective move speed, factoring in frost slow.
func get_effective_speed() -> float:
	return move_speed * _frost_slow_factor

func get_reward_gems() -> int:
	# Legacy compat: returns total count across all gem types.
	var total: int = 0
	for type in reward_gem_table:
		total += int(reward_gem_table[type])
	return total

## Return the typed gem reward dictionary (e.g. {"green": 2, "blue": 1}).
func get_reward_gem_table() -> Dictionary:
	return reward_gem_table.duplicate()

## Get reward skill points (called by EnemyManager)
func get_reward_skill_points() -> int:
	return reward_skill_points

## Check if target is in range
func is_target_in_range(range: float) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	return global_position.distance_to(target.global_position) <= range

## Face toward target with rotation
func face_target(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	
	var to_target = target.global_position - global_position
	to_target.y = 0  # Stay on horizontal plane
	
	if to_target.length() < 0.01:
		return
	
	var target_rotation = atan2(to_target.x, to_target.z)
	var current_rotation = rotation.y
	var new_rotation = lerp_angle(current_rotation, target_rotation, rotation_speed * delta)
	rotation.y = new_rotation

## Move toward target position
func move_to_position(target_pos: Vector3, speed: float, delta: float) -> void:
	var direction = global_position.direction_to(target_pos)
	direction.y = 0
	velocity = direction * speed * _frost_slow_factor
	move_and_slide()

## Move away from target position
func move_from_position(from_pos: Vector3, speed: float, delta: float) -> void:
	var direction = from_pos - global_position
	direction.y = 0
	if direction.length() > 0:
		direction = direction.normalized()
		velocity = -direction * speed * _frost_slow_factor
	move_and_slide()

## Circle around a position
func orbit_around(center: Vector3, radius: float, speed: float, delta: float) -> void:
	var to_center = center - global_position
	to_center.y = 0
	var distance = to_center.length()
	
	# Perpendicular direction for orbiting
	var perpendicular = Vector3(-to_center.z, 0, to_center.x).normalized()
	
	# Adjust distance
	var distance_error = distance - radius
	var centering_force = to_center.normalized() * distance_error * 0.5
	
	velocity = (perpendicular * speed + centering_force) * speed
	move_and_slide()

## Check collision with player ship
func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player_ship"):
		if body.has_method("take_damage"):
			body.take_damage(collision_damage)
		# Apply knockback to self
		var knockback = (global_position - body.global_position).normalized() * 50.0
		velocity += knockback

## Get distance to player
func get_distance_to_player() -> float:
	if _ship == null or not is_instance_valid(_ship):
		return INF
	return global_position.distance_to(_ship.global_position)

## Check if player is detected
func is_player_detected() -> bool:
	return get_distance_to_player() <= detection_range
