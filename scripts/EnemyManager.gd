extends Node3D
class_name EnemyManager

## Central manager for spawning and tracking all enemies.
## Enemies spawn at predefined points in the asteroid belt.

signal enemy_spawned(enemy: Node3D)
signal enemy_destroyed(enemy: Node3D, position: Vector3, gems: int)
signal encounter_started(encounter_id: int)
signal encounter_completed(encounter_id: int)

@export var ship_path: NodePath
@export var world_seed: int = 42

## Maximum number of active enemies at once
@export var max_active_enemies: int = 25

## Distance from station where enemies can spawn
@export var min_spawn_distance: float = 500.0
@export var max_spawn_distance: float = 2000.0

## Respawn delay after an encounter is cleared
@export var respawn_delay: float = 10.0

## Enemy scenes - preloaded
var scout_drone_scene: PackedScene = preload("res://scenes/enemies/ScoutDrone.tscn")
var heavy_gunship_scene: PackedScene = preload("res://scenes/enemies/HeavyGunship.tscn")
var missile_cruiser_scene: PackedScene = preload("res://scenes/enemies/MissileCruiser.tscn")
var serpent_boss_scene: PackedScene = null  # TODO: Create boss scenes
var laser_boss_scene: PackedScene = null  # TODO: Create boss scenes
var bullet_hell_boss_scene: PackedScene = null  # TODO: Create boss scenes

## Spawn point markers (auto-found at runtime)
var spawn_points: Array[Node3D] = []

## Spawn point positions from generator
var _spawn_positions: Array[Vector3] = []

## Active enemies currently in the scene
var active_enemies: Array[Node3D] = []

## RNG seeded for deterministic spawns
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

## Reference to player ship
var _ship: Node3D = null

## Track which encounters have been completed
var _completed_encounters: Dictionary = {}

## Respawn timers per spawn point
var _respawn_timers: Dictionary = {}

func _ready() -> void:
	_rng.seed = world_seed
	add_to_group("enemy_managers")
	_find_spawn_points()
	_find_spawn_generator()
	_find_ship()
	print("EnemyManager ready: ", spawn_points.size(), " spawn points found")

func _find_spawn_points() -> void:
	# Find all SpawnPoint nodes in the scene tree
	spawn_points.clear()
	var all_points = get_tree().get_nodes_in_group("enemy_spawn_points")
	for point in all_points:
		if point is Node3D:
			spawn_points.append(point)
	spawn_points.sort_custom(_sort_by_distance)

func _find_spawn_generator() -> void:
	# Find SpawnPointGenerator and get its spawn positions
	var generators = get_tree().get_nodes_in_group("spawn_generators")
	print("Found ", generators.size(), " spawn generators")
	
	if generators.size() == 0:
		# Try to find by type
		for node in get_tree().get_nodes_in_group(""):
			if node is SpawnPointGenerator:
				generators.append(node)
				break
		
		# Also try to find by name
		if generators.size() == 0:
			var root = get_tree().root
			_find_node_by_name(root, "SpawnPointGenerator", generators)
	
	for gen in generators:
		if gen.has_method("get_spawn_points_in_range"):
			_spawn_positions = gen.get_spawn_points_in_range(min_spawn_distance, max_spawn_distance)
			print("Got ", _spawn_positions.size(), " spawn positions from generator")

func _find_ship() -> void:
	if not ship_path.is_empty():
		_ship = get_node_or_null(ship_path)
	if _ship == null:
		_ship = get_tree().get_first_node_in_group("player_ship")
	if _ship:
		print("EnemyManager found ship: ", _ship.name)
	else:
		print("EnemyManager WARNING: Ship not found!")

func _sort_by_distance(a: Node3D, b: Node3D) -> bool:
	if _ship == null:
		return false
	var dist_a = a.global_position.distance_to(_ship.global_position)
	var dist_b = b.global_position.distance_to(_ship.global_position)
	return dist_a < dist_b

func _process(delta: float) -> void:
	if _ship == null:
		_find_ship()
		if _ship == null:
			return
	
	# Update respawn timers
	var to_remove = []
	for point_id in _respawn_timers:
		_respawn_timers[point_id] -= delta
		if _respawn_timers[point_id] <= 0:
			to_remove.append(point_id)
	for point_id in to_remove:
		_respawn_timers.erase(point_id)
	
	# Check if we should spawn new enemies
	_try_spawn_enemies()

func _try_spawn_enemies() -> void:
	if active_enemies.size() >= max_active_enemies:
		return
	
	# Debug: print ship position
	if _ship:
		var ship_dist = _ship.global_position.length()
		if ship_dist > 400.0 and ship_dist < 600.0:  # Only print when entering danger zone
			print("Ship distance from station: ", ship_dist)
			print("Spawn positions available: ", _spawn_positions.size())
			print("Active enemies: ", active_enemies.size())
	
	# Try to spawn at SpawnPoint nodes first
	var spawned_at_node = false
	for point in spawn_points:
		if active_enemies.size() >= max_active_enemies:
			break
		
		var point_id = point.get_instance_id()
		if _respawn_timers.has(point_id):
			continue
		
		var dist_to_ship = point.global_position.distance_to(_ship.global_position)
		
		# Skip if too close or too far
		if dist_to_ship < min_spawn_distance or dist_to_ship > max_spawn_distance:
			continue
		
		# Check if this point has an active enemy
		if point.has_meta("active_enemy"):
			var enemy = point.get_meta("active_enemy")
			if is_instance_valid(enemy):
				continue
		
		# Determine what to spawn based on zone
		var enemy_scene = _get_enemy_for_zone(dist_to_ship)
		if enemy_scene == null:
			continue
		
		_spawn_enemy_at_position(point.global_position, enemy_scene, point)
		spawned_at_node = true
	
	# If we didn't spawn from nodes, try generated positions
	if not spawned_at_node and _spawn_positions.size() > 0:
		for pos in _spawn_positions:
			if active_enemies.size() >= max_active_enemies:
				break
			
			var point_id = hash(pos)
			if _respawn_timers.has(point_id):
				continue
			
			var dist_to_ship = pos.distance_to(_ship.global_position)
			if dist_to_ship < min_spawn_distance or dist_to_ship > max_spawn_distance:
				continue
			
			var enemy_scene = _get_enemy_for_zone(dist_to_ship)
			if enemy_scene == null:
				continue
			
			print("Spawning enemy at distance: ", dist_to_ship)
			_spawn_enemy_at_position(pos, enemy_scene, null)
			break  # Spawn one at a time

func _get_enemy_for_zone(distance: float) -> PackedScene:
	var roll = _rng.randf()
	
	if distance < 800.0:
		# Outer belt - scouts only
		if roll < 0.8:
			return scout_drone_scene
		return null
	
	elif distance < 1200.0:
		# Deep belt - scouts and gunships
		if roll < 0.5:
			return scout_drone_scene
		elif roll < 0.85:
			return heavy_gunship_scene
		else:
			return missile_cruiser_scene
	
	else:
		# Fringe - all enemy types including bosses
		if roll < 0.3:
			return scout_drone_scene
		elif roll < 0.55:
			return heavy_gunship_scene
		elif roll < 0.75:
			return missile_cruiser_scene
		elif roll < 0.92:
			# Mini-boss encounter
			return serpent_boss_scene if _rng.randf() < 0.5 else laser_boss_scene
		else:
			# Rare bullet hell boss
			return bullet_hell_boss_scene

func _spawn_enemy_at_position(pos: Vector3, scene: PackedScene, point: Node3D = null) -> void:
	if scene == null:
		return
	
	var enemy = scene.instantiate() as Node3D
	if enemy == null:
		return
	
	# Position at spawn point with slight random offset
	var offset = Vector3(
		_rng.randf_range(-10.0, 10.0),
		0.0,
		_rng.randf_range(-10.0, 10.0)
	)
	enemy.global_position = pos + offset
	
	# Connect signals
	if enemy.has_signal("died"):
		enemy.died.connect(_on_enemy_died.bind(enemy, point))
	elif enemy.has_signal("enemy_died"):
		enemy.enemy_died.connect(_on_enemy_died.bind(enemy, point))
	
	# Add to scene
	add_child(enemy)
	active_enemies.append(enemy)
	if point:
		point.set_meta("active_enemy", enemy)
	
	enemy_spawned.emit(enemy)
	
	# If enemy is a boss, emit encounter started
	if enemy.is_in_group("bosses"):
		var encounter_id = point.get_instance_id() if point else hash(pos)
		encounter_started.emit(encounter_id)

func _on_enemy_died(enemy: Node3D, point: Node3D = null) -> void:
	if enemy in active_enemies:
		active_enemies.erase(enemy)
	
	var pos = enemy.global_position
	var gems = 0
	if enemy.has_method("get_reward_gems"):
		gems = enemy.get_reward_gems()
	elif "reward_gems" in enemy:
		gems = enemy.reward_gems
	
	enemy_destroyed.emit(enemy, pos, gems)
	
	# Clear active enemy from spawn point
	if point and point.has_meta("active_enemy"):
		if point.get_meta("active_enemy") == enemy:
			point.set_meta("active_enemy", null)
			_respawn_timers[point.get_instance_id()] = respawn_delay
			
			# If this was a boss, emit encounter completed
			if enemy.is_in_group("bosses"):
				encounter_completed.emit(point.get_instance_id())
	else:
		# Find the spawn point for this enemy
		for p in spawn_points:
			if p.has_meta("active_enemy") and p.get_meta("active_enemy") == enemy:
				p.set_meta("active_enemy", null)
				_respawn_timers[p.get_instance_id()] = respawn_delay
				if enemy.is_in_group("bosses"):
					encounter_completed.emit(p.get_instance_id())
				break
	
	# Clean up enemy
	enemy.queue_free()

func get_spawn_points_in_range(min_dist: float, max_dist: float) -> Array[Node3D]:
	var result: Array[Node3D] = []
	for point in spawn_points:
		if _ship == null:
			continue
		var dist = point.global_position.distance_to(_ship.global_position)
		if dist >= min_dist and dist <= max_dist:
			result.append(point)
	return result

func get_enemy_count() -> int:
	return active_enemies.size()

func clear_all_enemies() -> void:
	for enemy in active_enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	active_enemies.clear()
	for point in spawn_points:
		point.set_meta("active_enemy", null)

func _find_node_by_name(node: Node, name: String, result: Array) -> void:
	if node.name == name:
		result.append(node)
	for child in node.get_children():
		_find_node_by_name(child, name, result)
