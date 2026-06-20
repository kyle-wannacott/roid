extends Node3D
## The player's home base. Slowly rotates, has a beacon, and refuels
## the ship while it is inside the refuel area. The docking-bay
## doors slide open when a ship approaches.

@export var refuel_radius: float = 12.0
@export var refuel_rate: float = 25.0
@export var spin_speed: float = 0.08

## Distance at which the bay doors start to open.
@export var door_open_distance: float = 14.0
## How far the doors slide when fully open (along the bay axis).
@export var door_slide_distance: float = 2.2
## Door open/close speed.
@export var door_speed: float = 4.0

@onready var hub_pivot: Node3D = $HubPivot
@onready var ring_pivot: Node3D = $RingPivot
@onready var beacon: OmniLight3D = $Beacon
@onready var refuel_area: Area3D = $RefuelArea
@onready var refuel_collision: CollisionShape3D = $RefuelArea/CollisionShape3D
@onready var label_anchor: Marker3D = $LabelAnchor
@onready var door_left: MeshInstance3D = $HubPivot/DoorLeft
@onready var door_right: MeshInstance3D = $HubPivot/DoorRight

var ships_in_dock: Array[Node3D] = []
var door_left_closed_x: float = 0.0
var door_right_closed_x: float = 0.0
var door_openness: float = 0.0  # 0 = closed, 1 = fully open


func _ready() -> void:
	add_to_group("station")
	if refuel_collision.shape is SphereShape3D:
		(refuel_collision.shape as SphereShape3D).radius = refuel_radius
	# Cache the closed X positions so the lerp is relative.
	door_left_closed_x = door_left.position.x
	door_right_closed_x = door_right.position.x
	refuel_area.body_entered.connect(_on_body_entered)
	refuel_area.body_exited.connect(_on_body_exited)


func _process(delta: float) -> void:
	hub_pivot.rotate_y(delta * spin_speed)
	ring_pivot.rotate_x(delta * spin_speed * 0.5)
	var t: float = Time.get_ticks_msec() / 1000.0
	beacon.light_energy = 1.5 + sin(t * 3.0) * 1.0

	_update_doors(delta)


func _update_doors(delta: float) -> void:
	# Find the closest ship in the "ship" group and see if it's near
	# the docking bay. If so, open the doors.
	var target: float = 0.0
	for s in get_tree().get_nodes_in_group("ship"):
		if not is_instance_valid(s):
			continue
		var d: float = global_position.distance_to(s.global_position)
		if d < door_open_distance:
			# 0 at door_open_distance, 1 right on top of us.
			var closeness: float = 1.0 - clamp(d / door_open_distance, 0.0, 1.0)
			target = max(target, closeness)

	door_openness = move_toward(door_openness, target, delta * door_speed)

	# Slide the doors outward along the bay axis (X in hub-local space).
	# door_left is at negative X, door_right is at positive X; we push
	# them further out when open.
	var left_x: float = door_left_closed_x - door_slide_distance * door_openness
	var right_x: float = door_right_closed_x + door_slide_distance * door_openness
	door_left.position.x = left_x
	door_right.position.x = right_x


func is_ship_docked(ship: Node3D) -> bool:
	return ships_in_dock.has(ship)


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("ship") and not ships_in_dock.has(body):
		ships_in_dock.append(body)


func _on_body_exited(body: Node) -> void:
	if ships_in_dock.has(body):
		ships_in_dock.erase(body)
