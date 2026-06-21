extends Node3D
class_name Bullet
## A simple fast-moving projectile fired from the ship's turret.
## Flies in a straight line in its local -Z direction, expires
## after `lifetime` seconds.  No collision — damage is handled
## by the calling system (e.g. Asteroid proximity check).

@export var speed: float = 120.0
@export var lifetime: float = 1.5

var _age: float = 0.0


func _ready() -> void:
	# Build a small glowing tracer.
	var body := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.04
	cyl.bottom_radius = 0.04
	cyl.height = 0.4
	body.mesh = cyl
	body.rotation = Vector3(PI * 0.5, 0, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.8, 0.2, 1)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.9, 0.3, 1)
	mat.emission_energy_multiplier = 5.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	body.material_override = mat
	add_child(body)


func _physics_process(delta: float) -> void:
	_age += delta
	if _age > lifetime:
		queue_free()
		return
	global_position += -global_transform.basis.z * speed * delta
