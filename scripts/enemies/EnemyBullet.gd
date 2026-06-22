extends MeshInstance3D
class_name EnemyBullet

## Simple enemy projectile that moves in a straight line.

@export var speed: float = 300.0
@export var damage: float = 10.0
@export var lifetime: float = 3.0

var velocity: Vector3 = Vector3.ZERO

func _ready() -> void:
	add_to_group("enemy_projectiles")
	_ensure_collision()

func _ensure_collision() -> void:
	# Check if we already have collision
	for child in get_children():
		if child is Area3D:
			# Connect signal if not already connected
			if not child.body_entered.is_connected(_on_body_entered):
				child.body_entered.connect(_on_body_entered)
			if not child.area_entered.is_connected(_on_area_entered):
				child.area_entered.connect(_on_area_entered)
			return
	
	# Create area for collision
	var area = Area3D.new()
	area.add_to_group("enemy_projectiles")
	var collision = CollisionShape3D.new()
	var shape = SphereShape3D.new()
	shape.radius = 0.2
	collision.shape = shape
	area.add_child(collision)
	add_child(area)
	
	# Connect signals
	area.body_entered.connect(_on_body_entered)
	area.area_entered.connect(_on_area_entered)

func _physics_process(delta: float) -> void:
	global_position += velocity * delta
	
	lifetime -= delta
	if lifetime <= 0:
		queue_free()

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player_ship"):
		if body.has_method("take_damage"):
			body.take_damage(damage)
		queue_free()

func _on_area_entered(area: Area3D) -> void:
	if area.is_in_group("player_hurtbox"):
		if area.owner and area.owner.has_method("take_damage"):
			area.owner.take_damage(damage)
		queue_free()

func get_damage() -> float:
	return damage
