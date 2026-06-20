extends Camera3D
## Dual-mode chase camera. Tab toggles between:
##   • ISOMETRIC — camera sits in front of and above the ship, looking
##     back at it. Rotates with the ship's yaw.
##   • TOPDOWN   — camera looks straight down at the ship from high
##     up. Does NOT rotate with the ship — just follows position.

enum Mode { ISOMETRIC, TOPDOWN }

@export var target_path: NodePath
@export var iso_offset: Vector3 = Vector3(0, 5.0, -8.5)
@export var iso_look: Vector3 = Vector3(0, 0, 3.0)
## Top-down: directly above the ship, zoomed out 2×.
@export var top_offset: Vector3 = Vector3(0, 40.0, 0.0)
@export var top_look: Vector3 = Vector3(0, 0, 0)
## Fixed "up" direction for the top-down view (world -Z = screen-up,
## so the ship's forward naturally reads as "up" on screen).
@export var top_up: Vector3 = Vector3(0, 0, -1)
@export var position_smooth: float = 6.0
@export var fov_base_iso: float = 60.0
@export var fov_base_top: float = 55.0
@export var fov_speed_boost: float = 10.0

var ship: Node3D
var mode: int = Mode.ISOMETRIC
var current_pos: Vector3
var current_basis: Basis
var initialized: bool = false

# Cached top-down basis so we never recompute it (avoids the
# looking_at singularity when view-direction is parallel to UP).
var _top_basis: Basis


func _ready() -> void:
	if not target_path.is_empty():
		ship = get_node_or_null(target_path)
	fov = fov_base_iso
	current_pos = global_position
	current_basis = global_basis
	# Pre‑compute the fixed top‑down basis: look straight down with
	# top_up as the hint (keeps the world always "right-side up").
	_top_basis = Basis.looking_at(Vector3(0, -1, 0), top_up)


func _physics_process(delta: float) -> void:
	if ship == null or not is_instance_valid(ship):
		return

	if Input.is_action_just_pressed("camera_toggle"):
		mode = Mode.TOPDOWN if mode == Mode.ISOMETRIC else Mode.ISOMETRIC

	var ideal_pos: Vector3
	var target_basis: Basis

	if mode == Mode.ISOMETRIC:
		var yaw: float = _extract_yaw(ship.global_transform.basis)
		var rot_basis: Basis = Basis().rotated(Vector3.UP, yaw)
		ideal_pos = ship.global_position + rot_basis * iso_offset
		var look_target: Vector3 = ship.global_position + rot_basis * iso_look
		target_basis = Basis().looking_at(look_target - ideal_pos, Vector3.UP)
	else:
		# Top‑down: directly above, fixed orientation, no yaw follow.
		ideal_pos = ship.global_position + top_offset
		target_basis = _top_basis

	if not initialized:
		current_pos = ideal_pos
		current_basis = target_basis
		initialized = true

	current_pos = current_pos.lerp(ideal_pos, clamp(position_smooth * delta, 0.0, 1.0))
	current_basis = current_basis.slerp(target_basis, clamp(position_smooth * delta, 0.0, 1.0))

	global_position = current_pos
	global_basis = current_basis

	var base_fov: float = fov_base_iso if mode == Mode.ISOMETRIC else fov_base_top
	var speed: float = 0.0
	if "velocity" in ship:
		var v = ship.get("velocity")
		if v is Vector3:
			speed = v.length()
	var speed_ratio: float = clamp(speed / 60.0, 0.0, 1.0)
	var target_fov: float = base_fov + fov_speed_boost * speed_ratio
	fov = lerp(fov, target_fov, clamp(3.0 * delta, 0.0, 1.0))


func _extract_yaw(basis: Basis) -> float:
	var forward := -basis.z
	return atan2(forward.x, forward.z)
