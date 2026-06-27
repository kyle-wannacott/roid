extends Node3D

## Test script to verify enemy system is working.
## Attach to Main node for testing.

@onready var enemy_mgr = $EnemyManager
@onready var spawn_gen = $SpawnPointGenerator

func _ready() -> void:
	print("=== Enemy System Test ===")
	
	# Wait for managers to initialize
	await get_tree().process_frame
	
	# Check EnemyManager
	if enemy_mgr:
		print("EnemyManager found")
		print("  Active enemies: ", enemy_mgr.get_enemy_count())
		print("  Spawn points: ", enemy_mgr.spawn_points.size())
	else:
		print("ERROR: EnemyManager not found!")
	
	# Check SpawnPointGenerator
	if spawn_gen:
		print("SpawnPointGenerator found")
		print("  Generated positions: ", spawn_gen.spawn_points.size())
	else:
		print("ERROR: SpawnPointGenerator not found!")
	
	# Check if player ship is in correct group
	var ships = get_tree().get_nodes_in_group("player_ship")
	print("Player ships found: ", ships.size())
	
	# Connect to enemy manager signals for debugging
	if enemy_mgr:
		enemy_mgr.enemy_spawned.connect(_on_enemy_spawned)
		enemy_mgr.enemy_destroyed.connect(_on_enemy_destroyed)
	
	print("=== Test Complete ===")

func _on_enemy_spawned(enemy: Node3D) -> void:
	print("Enemy spawned: ", enemy.name, " at ", enemy.global_position)

func _on_enemy_destroyed(enemy: Node3D, position: Vector3, gem_table: Dictionary) -> void:
	var total: int = 0
	for type in gem_table:
		total += int(gem_table[type])
	print("Enemy destroyed: ", enemy.name, " at ", position, " - Gems: ", total, " (", gem_table, ")")

func _process(_delta: float) -> void:
	# Debug info
	if Input.is_action_just_pressed("ui_accept"):
		_print_debug_info()

func _print_debug_info() -> void:
	print("\n=== Debug Info ===")
	if enemy_mgr:
		print("Active enemies: ", enemy_mgr.get_enemy_count())
		for enemy in enemy_mgr.active_enemies:
			if is_instance_valid(enemy):
				print("  - ", enemy.name, " at ", enemy.global_position, " HP: ", enemy.health)
	print("==================\n")
