extends Node3D
class_name DamageNumberManager

## Pooled damage number system using Label3D nodes.
## Reuses nodes from a pool to avoid constant creation/destruction.

static var instance: DamageNumberManager = null

@export var rise_speed: float = 2.0
@export var fade_delay: float = 0.3
@export var lifetime: float = 1.0
@export var spawn_offset: float = 1.5

const POOL_SIZE = 32  # Max simultaneous damage numbers

var _pool: Array[Label3D] = []
var _active: Array[Dictionary] = []
var _last_spawn_time: float = 0.0
var _spawn_interval: float = 1.0

func _ready() -> void:
	instance = self
	add_to_group("damage_numbers")
	_init_pool()

func _exit_tree() -> void:
	if instance == self:
		instance = null

func _init_pool() -> void:
	for i in POOL_SIZE:
		var label := Label3D.new()
		label.font_size = 24
		label.pixel_size = 0.001
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.fixed_size = true
		label.visible = false
		add_child(label)
		_pool.append(label)

func _process(delta: float) -> void:
	# Update active numbers
	var to_remove: Array[int] = []
	for i in range(_active.size() - 1, -1, -1):
		var entry: Dictionary = _active[i]
		var label: Label3D = entry["label"]
		var age: float = entry["age"] + delta
		entry["age"] = age
		
		# Rise up
		label.position.y += rise_speed * delta
		
		# Fade out after delay
		if age > fade_delay:
			var alpha: float = 1.0 - (age - fade_delay) / (lifetime - fade_delay)
			label.modulate.a = max(0.0, alpha)
		
		# Remove when expired
		if age >= lifetime:
			label.visible = false
			_pool.append(label)
			to_remove.append(i)
	
	# Clean up expired entries
	for i in to_remove:
		_active.remove_at(i)

## Spawn a damage number at the given world position.
func spawn(text: String, world_pos: Vector3, color: Color = Color.WHITE) -> void:
	if _pool.is_empty():
		return
	
	# Rate limit
	var current_time = Time.get_ticks_msec() / 1000.0
	if current_time - _last_spawn_time < _spawn_interval:
		return
	_last_spawn_time = current_time
	
	var label: Label3D = _pool.pop_back()
	label.text = text
	label.modulate = color
	label.modulate.a = 1.0
	label.visible = true
	
	# Position with slight random offset
	var offset = Vector3(
		randf_range(-0.2, 0.2),
		spawn_offset,
		randf_range(-0.2, 0.2)
	)
	label.position = world_pos + offset
	
	_active.append({
		"label": label,
		"age": 0.0,
	})

## Spawn damage number with automatic color based on damage amount.
func spawn_damage(amount: float, world_pos: Vector3, is_critical: bool = false) -> void:
	if amount <= 0:
		return
	
	# Crits bypass rate limit and always show
	if is_critical:
		_last_spawn_time = 0.0
	
	var text: String
	var color: Color
	
	if is_critical:
		text = str(int(amount)) + "!"
		color = Color(1.0, 0.2, 0.1)  # Red for crits
	elif amount >= 50:
		text = str(int(amount))
		color = Color(1.0, 0.8, 0.2)  # Yellow for big hits
	elif amount >= 20:
		text = str(int(amount))
		color = Color(1.0, 1.0, 1.0)  # White for medium
	else:
		text = str(int(amount))
		color = Color(0.7, 0.7, 0.7)  # Grey for small hits
	
	spawn(text, world_pos, color)

## Force show a damage number (bypasses rate limit)
func spawn_force(text: String, world_pos: Vector3, color: Color = Color.WHITE) -> void:
	_last_spawn_time = 0.0
	spawn(text, world_pos, color)
