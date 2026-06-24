extends Node3D
## The player's home base.  Procedurally-built space station with a dramatic
## hangar bay that opens its heavy blast-doors when the ship approaches.
##
## Visual features:
##   • Chunky central hub with titanium plating and glowing neon trim
##   • Two large blast-door panels that slide outward on approach
##   • Interior bay flood-lights and landing-strip LEDs that activate
##   • Rotating ring girder with structural struts
##   • Solar arrays that slowly track the sun
##   • Atmospheric thruster-gas particles venting from RCS ports
##   • Beacon / signal lights that pulse

@export var refuel_radius: float   = 12.0
@export var refuel_rate:   float   = 25.0
@export var spin_speed:    float   = 0.06

## Distance (from station centre) at which the bay doors start to open.
@export var door_open_distance:  float = 16.0
## How far each door panel slides outward when fully open.
@export var door_slide_distance: float = 3.2
## Door open/close speed (openness units per second).
@export var door_speed:          float = 3.0

# ── Scene-hierarchy nodes (set in _ready from @onready + children) ──────────
@onready var hub_pivot:       Node3D        = $HubPivot
@onready var ring_pivot:      Node3D        = $RingPivot
@onready var beacon:          OmniLight3D   = $Beacon
@onready var refuel_area:     Area3D        = $RefuelArea
@onready var refuel_collision: CollisionShape3D = $RefuelArea/CollisionShape3D
@onready var label_anchor:    Marker3D      = $LabelAnchor

# ── Procedurally-created nodes ───────────────────────────────────────────────
var _door_left:   Node3D = null   # left blast door assembly
var _door_right:  Node3D = null   # right blast door assembly
var _door_light_left:  Array[OmniLight3D]  = []
var _door_light_right: Array[OmniLight3D]  = []
var _bay_floods:  Array[OmniLight3D]        = []
var _landing_strip_mat: StandardMaterial3D  = null   # cycled LED color
var _bay_particles: CPUParticles3D          = null
var _door_left_base_x:  float = 0.0
var _door_right_base_x: float = 0.0

var _door_openness:  float = 0.0   # 0=closed 1=fully open
var _door_want:      float = 0.0   # target openness this frame

var ships_in_dock: Array[Node3D] = []

# ── Timing helpers ───────────────────────────────────────────────────────────
var _time: float = 0.0


# ────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	add_to_group("station")

	# Resize the refuel sphere from script so the export var is the truth.
	if refuel_collision and refuel_collision.shape is SphereShape3D:
		(refuel_collision.shape as SphereShape3D).radius = refuel_radius

	refuel_area.body_entered.connect(_on_body_entered)
	refuel_area.body_exited.connect(_on_body_exited)

	_build_station()


# ────────────────────────────────────────────────────────────────────────────
func _build_station() -> void:
	# ------------------------------------------------------------------
	# 1.  Central Hub  (stays still relative to HubPivot which rotates)
	# ------------------------------------------------------------------
	var hull_mat := _mat(Color(0.48, 0.50, 0.56), 0.85, 0.25)
	var accent_mat := _emit_mat(Color(0.18, 0.55, 1.0), 2.5)
	var window_mat := _glass_mat(Color(0.4, 0.8, 1.0, 0.55))
	var door_mat   := _mat(Color(0.40, 0.42, 0.47), 0.9, 0.2)
	var door_edge_mat := _emit_mat(Color(1.0, 0.65, 0.10), 3.5) # amber safety stripe

	# Main hub cylinder
	var hub := _add_mesh(hub_pivot, _cyl_mesh(4.8, 5.5, 3.4, 32), hull_mat, Vector3.ZERO)
	hub.name = "Hub"

	# Top cone
	var top_cone := _add_mesh(hub_pivot, _cone_mesh(4.8, 0.2, 3.2, 32), hull_mat, Vector3(0, 3.3, 0))
	top_cone.name = "TopCone"

	# Bottom cone
	var bot_cone := _add_mesh(hub_pivot, _cone_mesh(5.5, 0.2, 2.0, 32), hull_mat, Vector3(0, -2.7, 0))
	bot_cone.name = "BotCone"

	# Neon accent band around the equator
	var band := _add_mesh(hub_pivot, _torus_mesh(5.6, 0.18, 6, 32), accent_mat, Vector3.ZERO)
	band.name = "AccentBand"

	# Upper neon ring
	var upper_band := _add_mesh(hub_pivot, _torus_mesh(4.9, 0.12, 6, 32), accent_mat, Vector3(0, 1.5, 0))
	upper_band.name = "UpperBand"

	# ------------------------------------------------------------------
	# 2.  Hangar bay protrusion (the box that sticks out the side)
	# ------------------------------------------------------------------
	# The hangar slot is on the +X side of the hub.
	var bay_depth   : float = 4.8   # how far the bay protrudes
	var bay_width   : float = 4.5   # interior opening width
	var bay_height  : float = 3.2   # interior opening height
	var wall_thick  : float = 0.35  # wall panel thickness

	# Bay housing – top / bottom / back walls only; front is the door opening
	var bay_pivot := Node3D.new()
	bay_pivot.name = "BayPivot"
	hub_pivot.add_child(bay_pivot)
	bay_pivot.position = Vector3(5.5 + bay_depth * 0.5, 0, 0)   # offset from hub edge

	# Top wall
	_add_mesh(bay_pivot, _box_mesh(bay_width + wall_thick * 2, wall_thick, bay_depth),
			hull_mat, Vector3(0,  bay_height * 0.5 + wall_thick * 0.5, 0))
	# Bottom wall
	_add_mesh(bay_pivot, _box_mesh(bay_width + wall_thick * 2, wall_thick, bay_depth),
			hull_mat, Vector3(0, -bay_height * 0.5 - wall_thick * 0.5, 0))
	# Left wall (towards viewer)
	_add_mesh(bay_pivot, _box_mesh(wall_thick, bay_height + wall_thick * 2, bay_depth),
			hull_mat, Vector3(-bay_width * 0.5 - wall_thick * 0.5, 0, 0))
	# Right wall
	_add_mesh(bay_pivot, _box_mesh(wall_thick, bay_height + wall_thick * 2, bay_depth),
			hull_mat, Vector3( bay_width * 0.5 + wall_thick * 0.5, 0, 0))
	# Back wall
	_add_mesh(bay_pivot, _box_mesh(bay_width + wall_thick * 2, bay_height + wall_thick * 2, wall_thick),
			hull_mat, Vector3(0, 0, bay_depth * 0.5))

	# Bay interior floor (faint yellow landing strip)
	var floor_mat := _emit_mat(Color(0.9, 0.75, 0.2), 0.4)
	_add_mesh(bay_pivot, _box_mesh(bay_width - 0.1, 0.05, bay_depth - 0.1),
			floor_mat, Vector3(0, -bay_height * 0.5 + 0.05, 0))

	# Landing-strip LED line down the centre of the floor
	_landing_strip_mat = StandardMaterial3D.new()
	_landing_strip_mat.albedo_color = Color(0.3, 1.0, 0.5)
	_landing_strip_mat.metallic = 0.0
	_landing_strip_mat.roughness = 0.3
	_landing_strip_mat.emission_enabled = true
	_landing_strip_mat.emission = Color(0.3, 1.0, 0.5)
	_landing_strip_mat.emission_energy_multiplier = 2.0
	var strip_count : int = 6
	for s in range(strip_count):
		var pct : float = float(s) / float(strip_count - 1)
		var sz : float = bay_depth / float(strip_count) * 0.6
		var strip_mi := _add_mesh(bay_pivot, _box_mesh(0.3, 0.06, sz),
				_landing_strip_mat,
				Vector3(0, -bay_height * 0.5 + 0.08,
						lerp(-bay_depth * 0.5 + sz, bay_depth * 0.5 - sz, pct)))
		strip_mi.name = "Strip%d" % s

	# ------------------------------------------------------------------
	# 3.  Blast-door panels  (built as Node3D assemblies with a mesh + edge strip)
	# ------------------------------------------------------------------
	# Each door panel slides along the Y axis (up/down) – this gives a
	# cinematic split-open effect like a freight lift door.
	var door_h : float = bay_height * 0.5 + wall_thick   # half-height of each panel
	var door_thickness : float = 0.30
	var door_z_offset : float = -bay_depth * 0.5 + door_thickness * 0.5

	# --- LEFT panel (slides UP when opening) ---
	_door_left = Node3D.new()
	_door_left.name = "DoorLeft"
	bay_pivot.add_child(_door_left)
	_door_left.position = Vector3(0, door_h * 0.5, door_z_offset)
	_door_left_base_x = _door_left.position.y   # we slide on Y

	var dl_mesh := _add_mesh(_door_left, _box_mesh(bay_width + wall_thick * 2, door_h, door_thickness),
			door_mat, Vector3.ZERO)
	dl_mesh.name = "DoorLeftMesh"
	# Amber safety stripe along the inner edge (bottom of the top panel)
	_add_mesh(_door_left, _box_mesh(bay_width + wall_thick * 2, 0.18, door_thickness + 0.04),
			door_edge_mat, Vector3(0, -door_h * 0.5 + 0.09, 0))
	# Riveted panel detail (thin recessed boxes)
	for ri in range(3):
		var rx : float = lerp(-1.4, 1.4, float(ri) / 2.0)
		_add_mesh(_door_left, _box_mesh(0.8, door_h * 0.7, 0.04), hull_mat, Vector3(rx, 0, -door_thickness * 0.5 - 0.02))

	# -- door left indicator lights (green = open, red = closed)
	for li in range(3):
		var dl_light := OmniLight3D.new()
		dl_light.light_energy = 0.0
		dl_light.omni_range   = 2.5
		dl_light.light_color  = Color(1, 0.25, 0.1)
		_door_left.add_child(dl_light)
		dl_light.position = Vector3(lerp(-1.5, 1.5, float(li) / 2.0), -door_h * 0.5 + 0.25, -door_thickness * 0.5 - 0.1)
		_door_light_left.append(dl_light)

	# --- RIGHT panel (slides DOWN when opening) ---
	_door_right = Node3D.new()
	_door_right.name = "DoorRight"
	bay_pivot.add_child(_door_right)
	_door_right.position = Vector3(0, -door_h * 0.5, door_z_offset)
	_door_right_base_x = _door_right.position.y

	var dr_mesh := _add_mesh(_door_right, _box_mesh(bay_width + wall_thick * 2, door_h, door_thickness),
			door_mat, Vector3.ZERO)
	dr_mesh.name = "DoorRightMesh"
	_add_mesh(_door_right, _box_mesh(bay_width + wall_thick * 2, 0.18, door_thickness + 0.04),
			door_edge_mat, Vector3(0, door_h * 0.5 - 0.09, 0))
	for ri in range(3):
		var rx : float = lerp(-1.4, 1.4, float(ri) / 2.0)
		_add_mesh(_door_right, _box_mesh(0.8, door_h * 0.7, 0.04), hull_mat, Vector3(rx, 0, -door_thickness * 0.5 - 0.02))

	for li in range(3):
		var dr_light := OmniLight3D.new()
		dr_light.light_energy = 0.0
		dr_light.omni_range   = 2.5
		dr_light.light_color  = Color(1, 0.25, 0.1)
		_door_right.add_child(dr_light)
		dr_light.position = Vector3(lerp(-1.5, 1.5, float(li) / 2.0), door_h * 0.5 - 0.25, -door_thickness * 0.5 - 0.1)
		_door_light_right.append(dr_light)

	# ------------------------------------------------------------------
	# 4.  Bay flood-lights (inside the hangar, active when open)
	# ------------------------------------------------------------------
	for fi in range(4):
		var flood := OmniLight3D.new()
		flood.light_energy = 0.0
		flood.omni_range   = 8.0
		flood.light_color  = Color(0.8, 0.92, 1.0)  # cool white
		bay_pivot.add_child(flood)
		var fx : float = lerp(-bay_width * 0.4, bay_width * 0.4, float(fi) / 3.0)
		flood.position = Vector3(fx, bay_height * 0.4, 0)
		_bay_floods.append(flood)

	# ------------------------------------------------------------------
	# 5.  Solar arrays
	# ------------------------------------------------------------------
	var solar_mat := StandardMaterial3D.new()
	solar_mat.albedo_color = Color(0.12, 0.16, 0.38)
	solar_mat.metallic     = 0.1
	solar_mat.roughness    = 0.25
	solar_mat.emission_enabled = true
	solar_mat.emission = Color(0.15, 0.22, 0.6)
	solar_mat.emission_energy_multiplier = 0.4

	var arm_mat := _mat(Color(0.38, 0.40, 0.45), 0.8, 0.4)

	for side in [-1, 1]:
		# Structural arm
		var arm := _add_mesh(hub_pivot, _box_mesh(0.55, 0.55, 9.0), arm_mat, Vector3(0, 0, side * 9.5))
		arm.name = "SolarArm%d" % side
		# Panel A
		_add_mesh(hub_pivot, _box_mesh(7.5, 0.12, 3.8), solar_mat, Vector3(0, 0, side * 9.5 - side * 3.5))
		# Panel B
		_add_mesh(hub_pivot, _box_mesh(7.5, 0.12, 3.8), solar_mat, Vector3(0, 0, side * 9.5 + side * 3.5))

	# ------------------------------------------------------------------
	# 6.  Ring girder (separate pivot so it counter-rotates nicely)
	# ------------------------------------------------------------------
	var ring_mat := _mat(Color(0.38, 0.40, 0.45), 0.7, 0.45)
	var ring_accent := _emit_mat(Color(0.25, 0.5, 1.0), 1.8)

	_add_mesh(ring_pivot, _torus_mesh(11.5, 0.55, 8, 48), ring_mat, Vector3.ZERO)
	_add_mesh(ring_pivot, _torus_mesh(11.5, 0.22, 8, 48), ring_accent, Vector3.ZERO)

	# Structural struts connecting hub to ring
	for i in range(8):
		var angle : float = (float(i) / 8.0) * TAU
		var strut := _add_mesh(ring_pivot, _box_mesh(0.3, 0.3, 6.7), arm_mat, Vector3.ZERO)
		strut.rotation.y = angle
		strut.position   = Vector3(sin(angle) * 8.0, 0, cos(angle) * 8.0)

	# ------------------------------------------------------------------
	# 7.  RCS vents / antenna
	# ------------------------------------------------------------------
	for i in range(6):
		var ang : float = (float(i) / 6.0) * TAU
		var pos : Vector3 = Vector3(sin(ang) * 5.6, 1.2, cos(ang) * 5.6)
		var vent := _add_mesh(hub_pivot, _cyl_mesh(0.18, 0.22, 0.4, 8), hull_mat, pos)
		vent.name = "Vent%d" % i
		vent.look_at(pos + pos.normalized(), Vector3.UP)
		# Exhaust particle at each vent
		var rcs := CPUParticles3D.new()
		rcs.amount    = 8
		rcs.lifetime  = 0.5
		rcs.explosiveness = 0.0
		rcs.randomness    = 0.5
		rcs.direction = pos.normalized()
		rcs.spread    = 18.0
		rcs.gravity   = Vector3.ZERO
		rcs.initial_velocity_min = 1.5
		rcs.initial_velocity_max = 3.5
		rcs.emitting  = true
		var rcs_grad := Gradient.new()
		rcs_grad.set_color(0, Color(0.8, 0.9, 1.0, 0.6))
		rcs_grad.add_point(1.0, Color(0.5, 0.6, 0.8, 0.0))
		rcs.color_ramp = rcs_grad
		var rcs_mat := StandardMaterial3D.new()
		rcs_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
		rcs_mat.vertex_color_use_as_albedo = true
		rcs_mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
		rcs.material_override = rcs_mat
		rcs.mesh = _sphere_mesh(0.06)
		hub_pivot.add_child(rcs)
		rcs.position = pos + pos.normalized() * 0.3

	# ------------------------------------------------------------------
	# 8.  Bay atmosphere particles (light haze inside hangar when open)
	# ------------------------------------------------------------------
	_bay_particles = CPUParticles3D.new()
	_bay_particles.amount   = 40
	_bay_particles.lifetime = 3.0
	_bay_particles.explosiveness = 0.0
	_bay_particles.randomness    = 0.8
	_bay_particles.direction = Vector3(0, 0.1, 1)
	_bay_particles.spread    = 60.0
	_bay_particles.gravity   = Vector3.ZERO
	_bay_particles.initial_velocity_min = 0.2
	_bay_particles.initial_velocity_max = 0.8
	_bay_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_bay_particles.emission_box_extents = Vector3(bay_width * 0.4, bay_height * 0.4, bay_depth * 0.4)
	_bay_particles.emitting = false
	var haze_grad := Gradient.new()
	haze_grad.set_color(0, Color(0.7, 0.85, 1.0, 0.0))
	haze_grad.add_point(0.3, Color(0.7, 0.85, 1.0, 0.12))
	haze_grad.add_point(1.0, Color(0.6, 0.75, 1.0, 0.0))
	_bay_particles.color_ramp = haze_grad
	var haze_mat := StandardMaterial3D.new()
	haze_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	haze_mat.vertex_color_use_as_albedo = true
	haze_mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	_bay_particles.material_override = haze_mat
	_bay_particles.mesh = _sphere_mesh(0.25)
	bay_pivot.add_child(_bay_particles)
	_bay_particles.position = Vector3(0, 0, 0)


# ────────────────────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	_time += delta

	# Slow rotation of the whole hub and the ring
	hub_pivot.rotate_y(delta * spin_speed)
	ring_pivot.rotate_x(delta * spin_speed * 0.3)
	ring_pivot.rotate_y(delta * spin_speed * 0.15)

	# Beacon pulse
	beacon.light_energy = 1.8 + sin(_time * 2.8) * 1.2

	# Landing-strip LED animation (cycling green chase)
	if _landing_strip_mat:
		var chase := fmod(_time * 3.0, 1.0)
		var bright := 1.5 + sin(_time * 8.0) * 0.5
		_landing_strip_mat.emission_energy_multiplier = bright * _door_openness

	_update_doors(delta)
	_update_door_lights()


# ────────────────────────────────────────────────────────────────────────────
func _update_doors(delta: float) -> void:
	# Find closest ship; compute how open we want the doors.
	_door_want = 0.0
	for s in get_tree().get_nodes_in_group("ship"):
		if not is_instance_valid(s):
			continue
		var d : float = global_position.distance_to(s.global_position)
		if d < door_open_distance:
			var closeness : float = 1.0 - clamp(d / door_open_distance, 0.0, 1.0)
			_door_want = max(_door_want, closeness)

	# Smooth approach
	_door_openness = move_toward(_door_openness, _door_want, delta * door_speed)

	# TOP panel slides UP (positive Y)
	if _door_left:
		_door_left.position.y  = _door_left_base_x  + door_slide_distance * _door_openness
	# BOTTOM panel slides DOWN (negative Y)
	if _door_right:
		_door_right.position.y = _door_right_base_x - door_slide_distance * _door_openness

	# Bay particles / flood-lights follow the door openness
	if _bay_particles:
		_bay_particles.emitting = _door_openness > 0.05
	for fl in _bay_floods:
		fl.light_energy = _door_openness * 3.5


# ────────────────────────────────────────────────────────────────────────────
func _update_door_lights() -> void:
	# When closed → red warning lights; when fully open → green go-lights.
	var green_color : Color = Color(0.1, 1.0, 0.35)
	var red_color   : Color = Color(1.0, 0.25, 0.1)
	var light_color : Color = red_color.lerp(green_color, _door_openness)
	var energy      : float = 1.2 + sin(_time * 4.0 + _door_openness * PI) * 0.4

	for l in _door_light_left + _door_light_right:
		l.light_color  = light_color
		l.light_energy = energy * clamp(_door_openness * 3.0 + 0.3, 0.0, 2.0)


# ────────────────────────────────────────────────────────────────────────────
func is_ship_docked(ship: Node3D) -> bool:
	return ships_in_dock.has(ship)


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("ship") and not ships_in_dock.has(body):
		ships_in_dock.append(body)


func _on_body_exited(body: Node) -> void:
	if ships_in_dock.has(body):
		ships_in_dock.erase(body)


# ────────────────────────────────────────────────────────────────────────────
# ── Procedural mesh helpers ──────────────────────────────────────────────────
func _add_mesh(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	if mat:
		mi.material_override = mat
	parent.add_child(mi)
	mi.position = pos
	return mi


func _mat(col: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic     = metallic
	m.roughness    = roughness
	return m


func _emit_mat(col: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic     = 0.1
	m.roughness    = 0.4
	m.emission_enabled = true
	m.emission         = col
	m.emission_energy_multiplier = energy
	return m


func _glass_mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency   = StandardMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color   = col
	m.metallic       = 0.05
	m.roughness      = 0.05
	m.emission_enabled = true
	m.emission         = Color(col.r, col.g, col.b, 1.0)
	m.emission_energy_multiplier = 1.2
	return m


func _box_mesh(w: float, h: float, d: float) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = Vector3(w, h, d)
	return m


func _cyl_mesh(top_r: float, bot_r: float, height: float, segs: int) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius    = top_r
	m.bottom_radius = bot_r
	m.height        = height
	m.radial_segments = segs
	return m


func _cone_mesh(base_r: float, tip_r: float, height: float, segs: int) -> CylinderMesh:
	return _cyl_mesh(tip_r, base_r, height, segs)


func _torus_mesh(inner_r: float, thickness: float, tube_segs: int, ring_segs: int) -> TorusMesh:
	var m := TorusMesh.new()
	m.inner_radius  = inner_r
	m.outer_radius  = inner_r + thickness * 2.0
	m.rings         = ring_segs
	m.ring_segments = tube_segs
	return m


func _sphere_mesh(radius: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	return m
