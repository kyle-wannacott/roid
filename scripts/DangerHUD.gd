extends CanvasLayer

## HUD element that shows danger level and enemy count.

@onready var danger_label: Label = $DangerLabel
@onready var enemy_count_label: Label = $EnemyCountLabel

var _ship: Node3D = null
var _enemy_mgr: Node3D = null

func _ready() -> void:
	# Find ship and enemy manager
	_ship = get_tree().get_first_node_in_group("player_ship")
	_enemy_mgr = get_tree().get_first_node_in_group("enemy_managers")
	
	if _enemy_mgr == null:
		# Try to find by name
		var root = get_tree().root
		_enemy_mgr = _find_node_by_name(root, "EnemyManager")

func _process(_delta: float) -> void:
	if _ship == null or _enemy_mgr == null:
		return
	
	# Update enemy count
	var count = _enemy_mgr.get_enemy_count()
	enemy_count_label.text = "Enemies: %d" % count
	
	# Update danger level based on distance from station
	var distance = _ship.global_position.length()
	var danger_level = "Safe"
	var danger_color = Color(0.2, 1.0, 0.2)  # Green
	
	if distance > 1500.0:
		danger_level = "EXTREME DANGER"
		danger_color = Color(1.0, 0.2, 0.2)  # Red
	elif distance > 1000.0:
		danger_level = "High Danger"
		danger_color = Color(1.0, 0.5, 0.2)  # Orange
	elif distance > 500.0:
		danger_level = "Moderate Danger"
		danger_color = Color(1.0, 1.0, 0.2)  # Yellow
	
	danger_label.text = danger_level
	danger_label.add_theme_color_override("font_color", danger_color)

func _find_node_by_name(node: Node, target_name: String) -> Node:
	if node.name == target_name:
		return node
	for child in node.get_children():
		var result = _find_node_by_name(child, target_name)
		if result:
			return result
	return null
