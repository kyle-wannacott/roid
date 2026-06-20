extends RigidBody3D
class_name Gem
## Floating crystal gem that drifts in space and gets sucked into the ship.
## Spawned by asteroids when they break apart; pulses gently while idle.

@export var lifetime: float = 90.0
@export var pulse_speed: float = 3.0
@export var home_speed: float = 14.0
@export var attraction_radius: float = 8.0

var target: Node3D = null
var age: float = 0.0
var being_attracted: bool = false

@onready var mesh_instance: MeshInstance3D = $Mesh
@onready var glow: OmniLight3D = $Glow

var base_color: Color = Color(0.3, 0.9, 1.0)
var base_scale: float = 1.0
var spin_axis: Vector3 = Vector3.ZERO


func _ready() -> void:
	add_to_group("gems")

	# Random hue per gem for variety (cyan, magenta, gold, lime, purple).
	var hues: Array[float] = [0.50, 0.85, 0.13, 0.32, 0.72]
	var hue: float = hues[randi() % hues.size()]
	base_color = Color.from_hsv(hue, 0.8, 1.0)

	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = base_color
	mat.metallic = 0.1
	mat.roughness = 0.2
	mat.emission_enabled = true
	mat.emission = base_color
	mat.emission_energy_multiplier = 2.5
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var albedo: Color = base_color
	albedo.a = 0.9
	mat.albedo_color = albedo
	mesh_instance.material_override = mat

	if glow != null:
		glow.light_color = base_color
		glow.light_energy = 1.5

	base_scale = scale.x

	# Give the gem a random spin axis and initial angular velocity.
	spin_axis = Vector3(
		randf_range(-1.0, 1.0),
		randf_range(-1.0, 1.0),
		randf_range(-1.0, 1.0)
	).normalized()

	# Apply a small horizontal kick so gems spread out on the ground.
	apply_central_impulse(Vector3(
		randf_range(-1.0, 1.0),
		0.0,
		randf_range(-1.0, 1.0)
	).normalized() * 2.0)
	angular_velocity = spin_axis * randf_range(1.0, 3.0)


func _physics_process(delta: float) -> void:
	age += delta
	if age > lifetime:
		queue_free()
		return

	# Gentle bobbing pulse to make gems feel "alive".
	var pulse: float = 1.0 + 0.12 * sin(age * pulse_speed * 2.0)
	mesh_instance.scale = Vector3.ONE * pulse * base_scale

	# Stay on the ground plane — no floating gems.
	global_position.y = 0.3

	# If we have a target (the ship), fly toward it.
	if being_attracted and target != null and is_instance_valid(target):
		var to_target: Vector3 = target.global_position - global_position
		to_target.y = 0.0
		var dist: float = to_target.length()
		if dist < 0.6:
			queue_free()
			return
		var dir: Vector3 = to_target.normalized()
		# Accelerate as we get closer for a "vacuum" feel.
		var speed_mult: float = 1.0 + max(0.0, (attraction_radius - dist) / attraction_radius) * 2.0
		linear_velocity = dir * home_speed * speed_mult
		angular_velocity = spin_axis * (4.0 + (attraction_radius - dist) * 0.5)
	else:
		# Slowly come to rest and idle-spin.
		linear_velocity = linear_velocity.lerp(Vector3.ZERO, delta * 0.4)
		angular_velocity = spin_axis.lerp(angular_velocity, delta * 0.2)


## Called by the ship when it is close enough to attract this gem.
func attract_to(ship: Node3D) -> void:
	if being_attracted:
		return
	being_attracted = true
	target = ship
	gravity_scale = 0.0
	# Stop colliding with other gems / ship hull so we don't get stuck.
	collision_layer = 0
	collision_mask = 0
	if glow != null:
		glow.light_energy = 3.0
