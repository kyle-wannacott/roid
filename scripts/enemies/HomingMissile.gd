extends EnemyBullet
class_name HomingMissile

## Homing missile that tracks a target.

@export var turn_rate: float = 2.5
@export var homing_strength: float = 2.0

var target: Node3D = null

func _ready() -> void:
	super._ready()
	add_to_group("homing_missiles")

func _physics_process(delta: float) -> void:
	if target and is_instance_valid(target):
		# Calculate direction to target
		var to_target = (target.global_position - global_position).normalized()
		
		# Smoothly rotate toward target
		velocity = velocity.normalized().lerp(to_target, homing_strength * delta) * speed
		
		# Rotate missile to face movement direction
		if velocity.length() > 0.1:
			look_at(global_position + velocity, Vector3.UP)
	
	# Call parent physics process for movement and lifetime
	# But we need to avoid calling super._physics_process since it does its own movement
	global_position += velocity * delta
	lifetime -= delta
	if lifetime <= 0:
		queue_free()

func set_target(new_target: Node3D) -> void:
	target = new_target
