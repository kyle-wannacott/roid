extends Node3D
class_name Missile
## A simple homing missile fired from the ship's wing pods.
## Flies forward in a straight line (or slowly steers toward the
## ship's facing direction), expires after `lifetime` seconds, or
## when it hits something. Deals damage to enemies on contact.

@export var lifetime: float = 3.0
@export var speed: float = 80.0
@export var damage: float = 25.0
@export var shooter: Node3D = null  # who fired it (for direction reference)

var _age: float = 0.0
var _velocity: Vector3 = Vector3.ZERO
var _trail_emitter: CPUParticles3D = null
var _hit_enemies: Array = []  # Track enemies already hit to prevent multi-hit


func _ready() -> void:
	# Build a small rocket mesh in code: tip + body + fins.
	_build_visual()
	# Set initial velocity now
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
	# Missile Root Node for clean rotation
	var model := Node3D.new()
	add_child(model)

	# 1) Rocket Nozzle (at the rear)
	var nozzle := MeshInstance3D.new()
	var nozzle_mesh := CylinderMesh.new()
	nozzle_mesh.top_radius = 0.05
	nozzle_mesh.bottom_radius = 0.07
	nozzle_mesh.height = 0.1
	nozzle.mesh = nozzle_mesh
	nozzle.rotation = Vector3(PI * 0.5, 0, 0)
	nozzle.position = Vector3(0, 0, 0.22)
	var nozzle_mat := StandardMaterial3D.new()
	nozzle_mat.albedo_color = Color(0.15, 0.15, 0.18, 1)
	nozzle_mat.metallic = 0.8
	nozzle_mat.roughness = 0.5
	nozzle.material_override = nozzle_mat
	model.add_child(nozzle)

	# 2) Body (sleek cylindrical fuselage with carbon/white plating)
	var body := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.05
	cyl.bottom_radius = 0.05
	cyl.height = 0.45
	body.mesh = cyl
	body.rotation = Vector3(PI * 0.5, 0, 0)
	body.position = Vector3(0, 0, -0.05)
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.85, 0.85, 0.9, 1) # sleek military white
	body_mat.metallic = 0.8
	body_mat.roughness = 0.2
	body.material_override = body_mat
	model.add_child(body)

	# 3) Carbon Accent Ring
	var accent := MeshInstance3D.new()
	var accent_mesh := CylinderMesh.new()
	accent_mesh.top_radius = 0.052
	accent_mesh.bottom_radius = 0.052
	accent_mesh.height = 0.08
	accent.mesh = accent_mesh
	accent.rotation = Vector3(PI * 0.5, 0, 0)
	accent.position = Vector3(0, 0, -0.1)
	var accent_mat := StandardMaterial3D.new()
	accent_mat.albedo_color = Color(0.1, 0.1, 0.12, 1) # dark carbon fibre accent
	accent_mat.metallic = 0.9
	accent_mat.roughness = 0.4
	accent.material_override = accent_mat
	model.add_child(accent)

	# 4) Target sensor dome (glowing red tip at the front)
	var nose := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.05
	cone.height = 0.12
	nose.mesh = cone
	nose.rotation = Vector3(PI * 0.5, 0, 0)
	nose.position = Vector3(0, 0, -0.32)
	var nose_mat := StandardMaterial3D.new()
	nose_mat.albedo_color = Color(1.0, 0.1, 0.2, 1) # danger red sensor tip
	nose_mat.metallic = 0.5
	nose_mat.roughness = 0.1
	nose_mat.emission_enabled = true
	nose_mat.emission = Color(1.0, 0.2, 0.2, 1)
	nose_mat.emission_energy_multiplier = 3.0
	nose.material_override = nose_mat
	model.add_child(nose)

	# 5) Swept-back fins (4 wings)
	for i in 4:
		var fin := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.12, 0.015, 0.12)
		fin.mesh = box
		var fin_mat := StandardMaterial3D.new()
		fin_mat.albedo_color = Color(0.2, 0.2, 0.25, 1)
		fin_mat.metallic = 0.7
		fin_mat.roughness = 0.4
		fin.material_override = fin_mat
		# Shift fins slightly backward and tilt them for aerodynamic swept-back look
		var angle: float = i * PI * 0.5
		fin.position = Vector3(cos(angle) * 0.08, sin(angle) * 0.08, 0.12)
		fin.rotation = Vector3(0, 0, angle)
		fin.rotate_x(0.3) # sweep back
		model.add_child(fin)

	# 6) Engine core flare (constant small intense glow sphere at nozzle exit)
	var glow := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.05
	sphere.height = 0.1
	glow.mesh = sphere
	glow.position = Vector3(0, 0, 0.27)
	var glow_mat := StandardMaterial3D.new()
	glow_mat.albedo_color = Color(1, 0.7, 0.3, 1)
	glow_mat.emission_enabled = true
	glow_mat.emission = Color(1, 0.5, 0.1, 1)
	glow_mat.emission_energy_multiplier = 6.0
	glow.material_override = glow_mat
	model.add_child(glow)

	# 7) Dynamic fire & smoke exhaust trail
	_trail_emitter = CPUParticles3D.new()
	_trail_emitter.amount = 45
	_trail_emitter.lifetime = 0.35
	_trail_emitter.explosiveness = 0.0
	_trail_emitter.randomness = 0.2
	_trail_emitter.position = Vector3(0, 0, 0.28)
	
	var part_mesh := SphereMesh.new()
	part_mesh.radius = 0.05
	part_mesh.height = 0.1
	_trail_emitter.mesh = part_mesh
	
	_trail_emitter.direction = Vector3(0, 0, 1) # shoot straight back
	_trail_emitter.spread = 8.0
	_trail_emitter.gravity = Vector3.ZERO
	_trail_emitter.initial_velocity_min = 6.0
	_trail_emitter.initial_velocity_max = 10.0
	
	# Fades size as it moves away
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 1.0))
	scale_curve.add_point(Vector2(0.2, 1.4))
	scale_curve.add_point(Vector2(1.0, 0.1))
	_trail_emitter.scale_amount_curve = scale_curve
	
	# Color gradient: blue core -> bright orange -> dark gray smoke -> transparent
	var gradient := Gradient.new()
	gradient.add_point(0.0, Color(0.4, 0.8, 1.0, 1.0))  # super hot blue plume at nozzle
	gradient.add_point(0.15, Color(1.0, 0.7, 0.2, 0.9)) # fiery orange-yellow
	gradient.add_point(0.4, Color(0.9, 0.3, 0.1, 0.6))  # cooling red-orange
	gradient.add_point(0.7, Color(0.25, 0.25, 0.25, 0.3)) # grey smoke trail
	gradient.add_point(1.0, Color(0.1, 0.1, 0.1, 0.0))  # complete fadeout
	_trail_emitter.color_ramp = gradient
	
	var part_mat := StandardMaterial3D.new()
	part_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	part_mat.vertex_color_use_as_albedo = true
	part_mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	_trail_emitter.material_override = part_mat
	
	add_child(_trail_emitter)
	_trail_emitter.emitting = true
	
	# Create collision area for detecting enemy hits
	var hitbox := Area3D.new()
	hitbox.collision_layer = 0
	hitbox.collision_mask = 8  # Layer 4 (enemy hurtbox layer)
	var hitbox_shape := CollisionShape3D.new()
	var hitbox_sphere := SphereShape3D.new()
	hitbox_sphere.radius = 1.0  # Larger hitbox for missiles
	hitbox_shape.shape = hitbox_sphere
	hitbox.add_child(hitbox_shape)
	hitbox.body_entered.connect(_on_hitbox_body_entered)
	add_child(hitbox)


func _physics_process(delta: float) -> void:
	_age += delta
	if _age > lifetime:
		queue_free()
		return
	# Simple straight-line flight.
	global_position += _velocity * delta
	
	# Check for enemy hits
	_check_enemy_hits()


func _check_enemy_hits() -> void:
	# Manual distance check against all enemies for more reliable hit detection
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		if enemy in _hit_enemies:
			continue
		if enemy.has_method("take_damage") and enemy.get("is_alive") == true:
			var dist = global_position.distance_to(enemy.global_position)
			if dist < 4.0:  # Close enough to hit (larger radius for missiles)
				# Store position BEFORE damage (enemy might die and free itself)
				var hit_pos = global_position
				# Use position-based damage if available (for multi-segment enemies like SerpentBoss)
				if enemy.has_method("damage_nearest_segment"):
					enemy.damage_nearest_segment(hit_pos, damage)
				else:
					enemy.take_damage(damage)
				_hit_enemies.append(enemy)
				# Spawn explosion effect at the stored position
				_spawn_explosion(hit_pos)
				queue_free()
				return


func _on_hitbox_body_entered(body: Node3D) -> void:
	# Area3D collision fallback
	if body.is_in_group("enemies") and body.has_method("take_damage"):
		if body not in _hit_enemies and body.get("is_alive") == true:
			var hit_pos = body.global_position
			body.take_damage(damage)
			_hit_enemies.append(body)
			_spawn_explosion(hit_pos)
			queue_free()


func _spawn_explosion(pos: Vector3) -> void:
	# Medium explosion effect for missile impact
	var explosion := OmniLight3D.new()
	explosion.light_color = Color(1.0, 0.5, 0.1)
	explosion.light_energy = 8.0
	explosion.omni_range = 8.0
	# Add to scene FIRST, then set global_position (node must be in tree)
	get_tree().current_scene.add_child(explosion)
	explosion.global_position = pos
	var tween := create_tween()
	tween.tween_property(explosion, "light_energy", 0.0, 0.3)
	tween.tween_callback(explosion.queue_free)
	
	# Play explosion sound
	if has_node("/root/SoundManager"):
		SoundManager.play_by_id("sfx_explosion")
