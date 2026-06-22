extends CharacterBody3D
class_name BaseEnemy

## Abstract base class for all enemies.
## Provides common functionality for health, damage, death, and rewards.

signal health_changed(new_health: float, max_health: float)
signal died()
signal took_damage(amount: float)

@export_group("Stats")
@export var max_health: float = 100.0
@export var move_speed: float = 100.0
@export var rotation_speed: float = 2.0
@export var collision_damage: float = 10.0

@export_group("Rewards")
@export var reward_gems: int = 5
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
var _fire_timer: float = 0.0
var _damage_flash_timer: float = 0.0

## Mesh references for damage flash
var _mesh_instances: Array[MeshInstance3D] = []
var _original_materials: Array[Material] = []

## Reference to ship
var _ship: Node3D = null

func _ready() -> void:
	health = max_health
	add_to_group("enemies")
	_find_ship()
	_collect_meshes()
	_ensure_collision()
	_ensure_hurtbox()

func _find_ship() -> void:
	_ship = get_tree().get_first_node_in_group("player_ship")

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

## Take damage from player
func take_damage(amount: float) -> void:
	if not is_alive:
		return
	
	health -= amount
	health_changed.emit(health, max_health)
	took_damage.emit(amount)
	
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
	
	# Spawn death effect (override in subclass for custom effects)
	_spawn_death_effect()

## Override in subclass for custom death effects
func _spawn_death_effect() -> void:
	# Default: just queue free after a brief delay
	await get_tree().create_timer(0.1).timeout
	queue_free()

## Get reward gems (called by EnemyManager)
func get_reward_gems() -> int:
	return reward_gems

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
	velocity = direction * speed
	move_and_slide()

## Move away from target position
func move_from_position(from_pos: Vector3, speed: float, delta: float) -> void:
	var direction = from_pos - global_position
	direction.y = 0
	if direction.length() > 0:
		direction = direction.normalized()
		velocity = -direction * speed
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
