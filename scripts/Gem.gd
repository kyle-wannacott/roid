extends RigidBody3D
## Physics body for a single gem.  Visuals are handled by the
## GemManager's MultiMeshInstance3D — this node exists only for
## the physics simulation (rolling, gravity, collision with ship).

@export var lifetime: float = 90.0
@export var pulse_speed: float = 3.0
@export var home_speed: float = 14.0
@export var attraction_radius: float = 8.0

var gem_slot: int = -1       # index in GemManager's arrays
var gem_manager: Node = null
var age: float = 0.0
var being_attracted: bool = false
var target: Node3D = null
var spin_axis: Vector3 = Vector3.ZERO


func _ready() -> void:
	add_to_group("gems")
	gem_manager = get_tree().get_first_node_in_group("gem_manager")
	if gem_manager == null:
		push_warning("Gem spawned with no GemManager in the tree")
		return

	# Spawn a new gem in the manager and remember the slot.
	gem_slot = gem_manager.spawn_gem(global_position)
	if gem_slot >= 0:
		gem_manager.rb_refs[gem_slot] = self

	# Random initial spin axis.
	spin_axis = Vector3(
		randf_range(-1.0, 1.0),
		randf_range(-1.0, 1.0),
		randf_range(-1.0, 1.0)
	).normalized()

	# Small horizontal kick so gems spread out on the ground.
	apply_central_impulse(Vector3(
		randf_range(-1.0, 1.0),
		0.0,
		randf_range(-1.0, 1.0)
	).normalized() * 2.0)
	angular_velocity = spin_axis * randf_range(1.0, 3.0)


func _physics_process(delta: float) -> void:
	age += delta
	if age > lifetime or gem_slot < 0:
		queue_free()
		return

	# Stay on the ground plane.
	global_position.y = 0.3

	# Attracted by the ship.
	if being_attracted and target != null and is_instance_valid(target):
		var to_target: Vector3 = target.global_position - global_position
		to_target.y = 0.0
		var dist: float = to_target.length()
		if dist < 0.6:
			_collect()
			return
		var dir: Vector3 = to_target.normalized()
		var speed_mult: float = 1.0 + max(0.0, (attraction_radius - dist) / attraction_radius) * 2.0
		linear_velocity = dir * home_speed * speed_mult
		angular_velocity = spin_axis * (4.0 + (attraction_radius - dist) * 0.5)
	else:
		linear_velocity = linear_velocity.lerp(Vector3.ZERO, delta * 0.4)
		angular_velocity = spin_axis.lerp(angular_velocity, delta * 0.2)


func attract_to(ship: Node3D) -> void:
	if being_attracted: return
	being_attracted = true
	target = ship
	gravity_scale = 0.0
	collision_layer = 0
	collision_mask = 0


func _collect() -> void:
	if gem_manager != null and is_instance_valid(gem_manager) and gem_slot >= 0:
		gem_manager.collect_gem(gem_slot)
		gem_slot = -1
	queue_free()
