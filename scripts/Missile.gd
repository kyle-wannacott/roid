extends Node3D
class_name Missile
## A simple homing missile fired from the ship's wing pods.
## Flies forward in a straight line (or slowly steers toward the
## ship's facing direction), expires after `lifetime` seconds, or
## when it hits something.  No collision — this is a visual effect
## only; damage is up to the gameplay layer.

@export var lifetime: float = 3.0
@export var speed: float = 80.0
@export var shooter: Node3D = null  # who fired it (for direction reference)

var _age: float = 0.0
var _velocity: Vector3 = Vector3.ZERO
var _trail_emitter: GPUParticles3D = null


func _ready() -> void:
	# Build a small rocket mesh in code: tip + body + fins.
	_build_visual()
	# Set initial velocity now; if the caller calls set_flight_params
	# before _ready runs, the value is updated by the call below.
	if shooter != null:
		_velocity = -shooter.global_transform.basis.z * speed
	else:
		_velocity = -global_transform.basis.z * speed


## Called by the ship to override the default flight parameters
## (speed, lifetime) just after instantiation.
func set_flight_params(p_speed: float, p_lifetime: float) -> void:
	speed = p_speed
	lifetime = p_lifetime
	if shooter != null:
		_velocity = -shooter.global_transform.basis.z * speed
	else:
		_velocity = -global_transform.basis.z * speed


func _build_visual() -> void:
	# Body (a small cylinder).
	var body := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.06
	cyl.bottom_radius = 0.06
	cyl.height = 0.5
	body.mesh = cyl
	body.rotation = Vector3(PI * 0.5, 0, 0)
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.85, 0.85, 0.9, 1)
	body_mat.metallic = 0.7
	body_mat.roughness = 0.3
	body_mat.emission_enabled = true
	body_mat.emission = Color(0.9, 0.4, 0.1, 1)
	body_mat.emission_energy_multiplier = 1.2
	body.material_override = body_mat
	add_child(body)

	# Nose (small cone at the front).
	var nose := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.06
	cone.height = 0.15
	nose.mesh = cone
	nose.rotation = Vector3(PI * 0.5, 0, 0)
	nose.position = Vector3(0, 0, -0.32)
	nose.material_override = body_mat
	add_child(nose)

	# 4 fins.
	for i in 4:
		var fin := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.12, 0.02, 0.1)
		fin.mesh = box
		var fin_mat := StandardMaterial3D.new()
		fin_mat.albedo_color = Color(0.5, 0.5, 0.55, 1)
		fin.material_override = fin_mat
		fin.position = Vector3(cos(i * PI * 0.5) * 0.07, sin(i * PI * 0.5) * 0.07, 0.15)
		fin.rotation = Vector3(0, 0, i * PI * 0.5)
		add_child(fin)

	# Engine glow (bright sphere behind the body).
	var glow := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.07
	sphere.height = 0.14
	glow.mesh = sphere
	glow.position = Vector3(0, 0, 0.28)
	var glow_mat := StandardMaterial3D.new()
	glow_mat.albedo_color = Color(1, 0.6, 0.2, 1)
	glow_mat.emission_enabled = true
	glow_mat.emission = Color(1, 0.7, 0.2, 1)
	glow_mat.emission_energy_multiplier = 4.0
	glow.material_override = glow_mat
	add_child(glow)


func _physics_process(delta: float) -> void:
	_age += delta
	if _age > lifetime:
		queue_free()
		return
	# Simple straight-line flight.
	global_position += _velocity * delta
