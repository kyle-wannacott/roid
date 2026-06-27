extends Node3D
class_name EnemyManager

## Central manager for spawning and tracking all enemies.
## Enemies spawn at predefined points in the asteroid belt.

signal enemy_spawned(enemy: Node3D)
signal enemy_destroyed(enemy: Node3D, position: Vector3, gem_table: Dictionary)
signal encounter_started(encounter_id: int)
signal encounter_completed(encounter_id: int)

@export var ship_path: NodePath
@export var world_seed: int = 42

## Maximum number of active enemies at once
@export var max_active_enemies: int = 40

## Distance from station where enemies can spawn
## Enemies spawn in an outer ring (500-1500m) so the player has room
## to explore outward and encounter them, instead of having the belt
## crash into the station.
@export var min_spawn_distance: float = 500.0
@export var max_spawn_distance: float = 1500.0

## Respawn delay after an encounter is cleared
@export var respawn_delay: float = 10.0

## Enemy scenes - preloaded
var scout_drone_scene: PackedScene = preload("res://scenes/enemies/ScoutDrone.tscn")
var heavy_gunship_scene: PackedScene = preload("res://scenes/enemies/HeavyGunship.tscn")
var missile_cruiser_scene: PackedScene = preload("res://scenes/enemies/MissileCruiser.tscn")
var serpent_boss_scene: PackedScene = preload("res://scenes/enemies/SerpentBoss.tscn")
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
	_find_ship()
	
	# Get spawn positions after a frame to ensure all nodes are ready
	await get_tree().process_frame
	_find_spawn_generator()
	_find_spawn_points()
	print("EnemyManager ready: ", spawn_points.size(), " spawn points found")
	
	# Listen for docking signal - clear enemies when player docks
	if _ship and _ship.has_signal("state_changed"):
		_ship.state_changed.connect(_on_ship_state_changed)

func _exit_tree() -> void:
	# Clean up all enemies when node is freed
	for enemy in active_enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	active_enemies.clear()

func _find_spawn_points() -> void:
	# Find all SpawnPoint nodes in the scene tree
	spawn_points.clear()
	var all_points = get_tree().get_nodes_in_group("enemy_spawn_points")
	for point in all_points:
		if point is Node3D:
			spawn_points.append(point)
	spawn_points.sort_custom(_sort_by_distance)

func _find_spawn_generator() -> void:
	# First try to find by group
	var generators = get_tree().get_nodes_in_group("spawn_generators")
	print("Found ", generators.size(), " spawn generators in group")
	
	# If not found, get directly by path (sibling node)
	if generators.size() == 0:
		var gen = get_node_or_null("../SpawnPointGenerator")
		if gen:
			generators.append(gen)
			print("Found SpawnPointGenerator by path")
	
	# If still not found, search by name in root
	if generators.size() == 0:
		_find_by_name(get_tree().root, "SpawnPointGenerator", generators)
	
	for gen in generators:
		if gen.has_method("get_spawn_points_in_range"):
			var all_points = gen.spawn_points
			print("Generator has ", all_points.size(), " total spawn points")
			_spawn_positions = gen.get_spawn_points_in_range(min_spawn_distance, max_spawn_distance)
			print("Got ", _spawn_positions.size(), " spawn positions in range ", min_spawn_distance, "-", max_spawn_distance)
			break

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
	
	# Check if enemies got too close to station
	_check_enemies_near_station()
	
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
	# Distance checks are from the STATION (origin), not the ship.
	# This ensures enemies always spawn in the outer asteroid belt,
	# not near the station where the player starts.
	var spawned_at_node = false
	for point in spawn_points:
		if active_enemies.size() >= max_active_enemies:
			break
		
		var point_id = point.get_instance_id()
		if _respawn_timers.has(point_id):
			continue
		
		# Distance from station (origin), NOT from ship
		var dist_from_station = point.global_position.length()
		
		# Defensive guard: a SpawnPoint node was placed inside the station
		# zone (someone hand-placed a marker in Main.tscn at the wrong
		# position). Warn loudly so it gets fixed instead of silently
		# spawning enemies on top of the player. The next `continue` will
		# skip it; this branch only exists to surface the bug.
		if dist_from_station < min_spawn_distance - 5.0:
			push_warning("EnemyManager: SpawnPoint '%s' is at %.1fm from station (min is %.1fm). Skipping." % [point.name, dist_from_station, min_spawn_distance])
			continue
		
		# Skip if outside the spawn zone (too close to station or too far)
		if dist_from_station < min_spawn_distance or dist_from_station > max_spawn_distance:
			continue
		
		# Also skip if too close to the player (don't spawn on top of them)
		var dist_to_ship = point.global_position.distance_to(_ship.global_position)
		if dist_to_ship < 100.0:
			continue
		
		# Check if this point has an active enemy
		if point.has_meta("active_enemy"):
			var enemy = point.get_meta("active_enemy")
			if is_instance_valid(enemy):
				continue
		
		# Determine what to spawn based on distance from station
		var enemy_scene = _get_enemy_for_zone(dist_from_station)
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
			
			# Distance from station (origin)
			var dist_from_station = pos.length()
			if dist_from_station < min_spawn_distance or dist_from_station > max_spawn_distance:
				continue
			
			# Skip if too close to player
			var dist_to_ship = pos.distance_to(_ship.global_position)
			if dist_to_ship < 100.0:
				continue
			
			var enemy_scene = _get_enemy_for_zone(dist_from_station)
			if enemy_scene == null:
				continue
			
			print("Spawning enemy at distance from station: ", dist_from_station)
			_spawn_enemy_at_position(pos, enemy_scene, null)

func _get_enemy_for_zone(distance: float) -> PackedScene:
	var roll = _rng.randf()
	
	if distance < 700.0:
		# Inner belt (600-700) - easy scouts only
		return scout_drone_scene
	
	elif distance < 1000.0:
		# Mid belt (700-1000) - scouts and gunships
		if roll < 0.6:
			return scout_drone_scene
		else:
			return heavy_gunship_scene
	
	elif distance < 1400.0:
		# Outer belt (1000-1400) - gunships and cruisers
		if roll < 0.4:
			return heavy_gunship_scene
		elif roll < 0.7:
			return missile_cruiser_scene
		else:
			return scout_drone_scene
	
	elif distance < 1800.0:
		# Deep belt (1400-1800) - cruisers and bosses
		if roll < 0.5:
			return missile_cruiser_scene
		elif roll < 0.7:
			return heavy_gunship_scene
		else:
			return serpent_boss_scene
	
	else:
		# Extreme belt (1800+) - bosses and heavy enemies
		if roll < 0.3:
			return missile_cruiser_scene
		elif roll < 0.5:
			return heavy_gunship_scene
		else:
			return serpent_boss_scene

func _spawn_enemy_at_position(pos: Vector3, scene: PackedScene, point: Node3D = null) -> void:
	if scene == null:
		return
	
	var enemy = scene.instantiate() as Node3D
	if enemy == null:
		return
	
	# Connect signals before adding to scene
	if enemy.has_signal("died"):
		enemy.died.connect(_on_enemy_died.bind(enemy, point))
	elif enemy.has_signal("enemy_died"):
		enemy.enemy_died.connect(_on_enemy_died.bind(enemy, point))
	
	# Add to scene FIRST so global_position works
	add_child(enemy)
	active_enemies.append(enemy)

	# Position at spawn point with slight random offset
	# Y position matches the player ship height (1.5)
	var offset = Vector3(
		_rng.randf_range(-10.0, 10.0),
		0.0,
		_rng.randf_range(-10.0, 10.0)
	)
	enemy.global_position = pos + offset
	enemy.global_position.y = 1.5  # Match player ship height

	# CRITICAL: set the spawn anchor AFTER positioning. The enemy's
	# _ready() ran during add_child() above, when global_position was
	# still (0,0,0) (the manager's position). If the enemy captured
	# _spawn_position = global_position in _ready(), it would record
	# the origin (the station) and the leash/patrol would be measured
	# from the wrong anchor. set_spawn_position() both records the
	# real spawn point and seeds a fresh patrol target.
	if enemy.has_method("set_spawn_position"):
		enemy.set_spawn_position(enemy.global_position)
	
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
	# Get the typed gem reward table from the enemy.
	# If the enemy doesn't have the new method, fall back to the legacy reward_gems int.
	var gem_table: Dictionary = {}
	if enemy.has_method("get_reward_gem_table"):
		gem_table = enemy.get_reward_gem_table()
	elif enemy.has_method("get_reward_gems"):
		# Legacy: convert int → all Green
		var total: int = enemy.get_reward_gems()
		gem_table = {"green": total}
	elif "reward_gem_table" in enemy:
		gem_table = enemy.reward_gem_table
	elif "reward_gems" in enemy:
		gem_table = {"green": enemy.reward_gems}
	
	enemy_destroyed.emit(enemy, pos, gem_table)
	
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

func _find_by_name(root: Node, target_name: String, result: Array) -> void:
	if root.name == target_name:
		result.append(root)
	for child in root.get_children():
		if child.name == target_name:
			result.append(child)
		else:
			_find_by_name(child, target_name, result)

func _on_ship_state_changed(new_state: int) -> void:
	# Ship.State.DOCKED = 4
	if new_state == 4:
		# Don't wipe all enemies when the player docks. Instead, send each
		# active enemy back to its patrol behaviour so they stay around
		# their spawn areas instead of following the player to the station.
		print("Ship docked - redirecting enemies to patrol")
		_redirect_enemies_to_patrol()


## Tell every active enemy to break off any current behaviour and return
## to patrolling around its spawn point.  Used when the player docks so
## enemies resume their normal patrol area rather than chasing the
## player's ship to the station.  We also teleport each enemy back to
## its recorded spawn position so the player isn't immediately beset
## by enemies that were in mid-flight toward the station.
func _redirect_enemies_to_patrol() -> void:
	for enemy in active_enemies:
		if not is_instance_valid(enemy):
			continue
		# If the enemy drifted too close to the station (chasing the
		# ship), teleport it back to its recorded spawn position so it
		# resumes patrolling from its home area.
		if "_spawn_position" in enemy:
			var dist_to_station: float = enemy.global_position.length()
			if dist_to_station < min_spawn_distance:
				enemy.global_position = enemy._spawn_position
				# Clear any velocity carried over from chasing the ship so
				# the teleport doesn't have residual momentum.
				if "velocity" in enemy:
					enemy.velocity = Vector3.ZERO
		if enemy.has_method("break_off_from_station"):
			enemy.break_off_from_station()

func _check_enemies_near_station() -> void:
	# If an enemy gets inside the station's safety zone (inside the
	# minimum spawn distance), redirect it so it doesn't follow the
	# player all the way to the hangar.  Patrol ships grazing the belt
	# boundary (just outside min_spawn_distance) are unaffected.
	var station_inner_radius := min_spawn_distance * 0.95  # ~475 units at default 500m spawn min
	
	for enemy in active_enemies:
		if is_instance_valid(enemy):
			var dist_to_station = enemy.global_position.length()
			if dist_to_station < station_inner_radius:
				# Redirect via the enemy's own AI so it transitions smoothly
				if enemy.has_method("break_off_from_station"):
					enemy.break_off_from_station()
