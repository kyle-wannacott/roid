extends Node3D

## Bay depth (same for all bays)
const BAY_DEPTH: float = 4.8

## The player's home base.  Procedurally-built space station with FOUR
## hangar bays (one at each cardinal compass direction) so the harpoon can
## always find a clear approach path regardless of the station's rotation
## or the ship's current position.  The closest bay is auto-selected.
##
## Visual features:
##   • Chunky central hub with titanium plating and glowing neon trim
##   • Four pairs of blast-door panels (one per bay) that slide outward
##   • Interior bay flood-lights and landing-strip LEDs that activate
##   • Rotating ring girder with structural struts
##   • Atmospheric thruster-gas particles venting from RCS ports
##   • Beacon / signal lights that pulse

@export var refuel_radius: float   = 12.0
@export var refuel_rate:   float   = 25.0
@export var spin_speed:    float   = 0.06

## Distance (from station centre) at which the bay doors start to open.
@export var door_open_distance:  float = 16.0
## How far each door panel slides outward when fully open.
@export var door_slide_distance: float = 3.2
## Door open/close speed (openness units per second).  Higher = snappier.
@export var door_speed:          float = 8.0

## How fast the ship gets pulled in / pushed out during docking/deploy.
@export var dock_pull_speed: float = 8.0
## World Y the ship sits at when docked.
@export var ground_height: float = 1.5

# ── Scene-hierarchy nodes (set in _ready from @onready + children) ──────────
@onready var hub_pivot:       Node3D        = $HubPivot
@onready var ring_pivot:      Node3D        = $RingPivot
@onready var beacon:          OmniLight3D   = $Beacon
@onready var refuel_area:     Area3D        = $RefuelArea
@onready var refuel_collision: CollisionShape3D = $RefuelArea/CollisionShape3D
@onready var label_anchor:    Marker3D      = $LabelAnchor

# ── Per-bay data (built in _build_station) ───────────────────────────────────
# Each BayData bundles every node that belongs to a single hangar so we can
# build four hangars around the hub without per-bay globals polluting the
# class.  The harpoon auto-selects the bay whose outward direction best
# matches the ship's position so the ship never has to fly through the hub.
class BayData:
	var bay_pivot: Node3D            = null
	var dock_pos: Marker3D          = null
	var hangar_trigger: Area3D      = null
	var door_left: Node3D           = null
	var door_right: Node3D          = null
	var door_left_base_y: float     = 0.0
	var door_right_base_y: float    = 0.0
	var door_lights_left: Array[OmniLight3D] = []
	var door_lights_right: Array[OmniLight3D] = []
	var floods: Array[OmniLight3D]  = []
	var strip_mat: StandardMaterial3D = null
	var particles: CPUParticles3D   = null
	# World-space direction the door faces (away from the station centre).
	# Refreshed every frame in _process because the station rotates.
	var outward_dir: Vector3        = Vector3.ZERO
	# Per-bay door animation state.  Each bay breathes independently so
	# only the bay the player is approaching actually opens.
	var door_openness: float        = 0.0
	var door_want: float            = 0.0

var _bays: Array[BayData] = []
# Backward-compat alias: the first bay is still the "primary" bay so any
# code (or future tooling) that looks for HubPivot/BayPivot still finds it.
var _bay_pivot: Node3D = null

var ships_in_dock: Array[Node3D] = []

# Docking state
var _docked_ship: Node3D = null     # ship currently resting at the dock
var _docking_ship: Node3D = null    # ship currently being pulled in
var _docking_start: Vector3 = Vector3.ZERO
var _docking_target: Vector3 = Vector3.ZERO
var _docking_progress: float = 0.0
# Which bay the docking ship is being pulled into.  Required so the docking
# animation faces the right door when there are four to choose from.
var _active_docking_bay: BayData = null
# Which bay the docked ship is parked in (so deploy launches from the right door).
var _active_docked_bay: BayData = null

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
	# 2.  Four hangar bays at the cardinal compass positions
	# ------------------------------------------------------------------
	# The station has FOUR hangars (E, N, W, S) instead of the original
	# single +X bay.  The harpoon auto-selects the bay whose outward
	# direction best matches the ship's position, so the ship never has
	# to fly through the hub to reach a door.
	#
	# Per-bay layout: each bay is a box that protrudes from the hub along
	# the bay's local +X axis, with the blast doors on the local -Z face.
	# We rotate the bay around Y so the door faces outward, away from the
	# station centre.
	var bay_depth   : float = 4.8   # how far the bay protrudes
	var bay_width   : float = 4.5   # interior opening width
	var bay_height  : float = 5.0   # interior opening height (raised for ship clearance)
	var wall_thick  : float = 0.35  # wall panel thickness

	var bay_offset : float = 5.5 + bay_depth * 0.5
	# (position, rotation_y, label).  rot_y=0 means door faces local -Z
	# (which equals world -Z before the station spins).  rot_y=PI flips
	# the bay so the door faces local +Z instead.
	var bay_specs : Array = [
		[Vector3( bay_offset, 0,  0),        0.0,  "E"],
		[Vector3( 0,          0,  bay_offset), PI,  "N"],
		[Vector3(-bay_offset, 0,  0),        0.0,  "W"],
		[Vector3( 0,          0, -bay_offset), 0.0, "S"],
	]
	for spec in bay_specs:
		_build_bay(spec[0], spec[1], spec[2],
				bay_depth, bay_width, bay_height, wall_thick,
				hull_mat, door_mat, door_edge_mat)

	# Expose the +X bay's pivot under the legacy name so any external code
	# (HUD label lookups, the initial-dock helper in Main.gd, the Ship's
	# harpoon fallback) that searches for HubPivot/BayPivot still finds it.
	if _bays.size() > 0:
		_bay_pivot = _bays[0].bay_pivot

	# ------------------------------------------------------------------
	# 3.  Ring girder (separate pivot so it counter-rotates nicely)
	# ------------------------------------------------------------------
	var ring_mat := _mat(Color(0.38, 0.40, 0.45), 0.7, 0.45)
	var ring_accent := _emit_mat(Color(0.25, 0.5, 1.0), 1.8)
	var arm_mat := _mat(Color(0.38, 0.40, 0.45), 0.8, 0.4)

	_add_mesh(ring_pivot, _torus_mesh(11.5, 0.55, 8, 48), ring_mat, Vector3.ZERO)
	_add_mesh(ring_pivot, _torus_mesh(11.5, 0.22, 8, 48), ring_accent, Vector3.ZERO)

	# Structural struts connecting hub to ring
	for i in range(8):
		var angle : float = (float(i) / 8.0) * TAU
		var strut := _add_mesh(ring_pivot, _box_mesh(0.3, 0.3, 6.7), arm_mat, Vector3.ZERO)
		strut.rotation.y = angle
		strut.position   = Vector3(sin(angle) * 8.0, 0, cos(angle) * 8.0)

	# ------------------------------------------------------------------
	# 4.  RCS vents / antenna
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
	# 5.  Collision body — solid walls, four open hangar doors
	# ------------------------------------------------------------------
	_build_station_collision(bay_width, bay_height, bay_depth, wall_thick)


# ────────────────────────────────────────────────────────────────────────────
# Build a single hangar bay at the given local position/rotation on the hub.
# All walls, doors, lights, trigger and dock marker are created and stored in
# the returned BayData record.
func _build_bay(local_pos: Vector3, rot_y: float, label: String,
		bay_depth: float, bay_width: float, bay_height: float, wall_thick: float,
		hull_mat: Material, door_mat: Material, door_edge_mat: Material) -> BayData:
	var bay := BayData.new()

	# Bay housing pivot — a child of hub_pivot so it rotates with the station.
	bay.bay_pivot = Node3D.new()
	# The first bay keeps the legacy name "BayPivot" so older code that
	# looked up HubPivot/BayPivot still finds it.  The other bays use
	# compass-based suffixes (E/N/W/S) to keep the scene tree readable.
	if _bays.is_empty():
		bay.bay_pivot.name = "BayPivot"
	else:
		bay.bay_pivot.name = "BayPivot_%s" % label
	hub_pivot.add_child(bay.bay_pivot)
	bay.bay_pivot.position = local_pos
	bay.bay_pivot.rotation.y = rot_y

	# ── Walls (5 sides; the front door face is intentionally open) ───────
	# Top wall
	_add_mesh(bay.bay_pivot, _box_mesh(bay_width + wall_thick * 2, wall_thick, bay_depth),
			hull_mat, Vector3(0,  bay_height * 0.5 + wall_thick * 0.5, 0))
	# Bottom wall
	_add_mesh(bay.bay_pivot, _box_mesh(bay_width + wall_thick * 2, wall_thick, bay_depth),
			hull_mat, Vector3(0, -bay_height * 0.5 - wall_thick * 0.5, 0))
	# Left wall (local -X side)
	_add_mesh(bay.bay_pivot, _box_mesh(wall_thick, bay_height + wall_thick * 2, bay_depth),
			hull_mat, Vector3(-bay_width * 0.5 - wall_thick * 0.5, 0, 0))
	# Right wall (local +X side)
	_add_mesh(bay.bay_pivot, _box_mesh(wall_thick, bay_height + wall_thick * 2, bay_depth),
			hull_mat, Vector3( bay_width * 0.5 + wall_thick * 0.5, 0, 0))
	# Back wall (far end of bay, local +Z)
	_add_mesh(bay.bay_pivot, _box_mesh(bay_width + wall_thick * 2, bay_height + wall_thick * 2, wall_thick),
			hull_mat, Vector3(0, 0, bay_depth * 0.5))

	# Bay interior floor (faint yellow landing strip)
	var floor_mat := _emit_mat(Color(0.9, 0.75, 0.2), 0.4)
	_add_mesh(bay.bay_pivot, _box_mesh(bay_width - 0.1, 0.05, bay_depth - 0.1),
			floor_mat, Vector3(0, -bay_height * 0.5 + 0.05, 0))

	# Landing-strip LED line down the centre of the floor
	bay.strip_mat = StandardMaterial3D.new()
	bay.strip_mat.albedo_color = Color(0.3, 1.0, 0.5)
	bay.strip_mat.metallic = 0.0
	bay.strip_mat.roughness = 0.3
	bay.strip_mat.emission_enabled = true
	bay.strip_mat.emission = Color(0.3, 1.0, 0.5)
	bay.strip_mat.emission_energy_multiplier = 2.0
	var strip_count : int = 6
	for s in range(strip_count):
		var pct : float = float(s) / float(strip_count - 1)
		var sz : float = bay_depth / float(strip_count) * 0.6
		var strip_mi := _add_mesh(bay.bay_pivot, _box_mesh(0.3, 0.06, sz),
				bay.strip_mat,
				Vector3(0, -bay_height * 0.5 + 0.08,
						lerp(-bay_depth * 0.5 + sz, bay_depth * 0.5 - sz, pct)))
		strip_mi.name = "Strip_%s_%d" % [label, s]

	# ── Blast-door panels (top slides up, bottom slides down) ────────────
	var door_h : float = bay_height * 0.5 + wall_thick   # half-height of each panel
	var door_thickness : float = 0.30
	var door_z_offset : float = -bay_depth * 0.5 + door_thickness * 0.5

	# LEFT panel (slides UP when opening)
	bay.door_left = Node3D.new()
	bay.door_left.name = "DoorLeft_%s" % label
	bay.bay_pivot.add_child(bay.door_left)
	bay.door_left.position = Vector3(0, door_h * 0.5, door_z_offset)
	bay.door_left_base_y = bay.door_left.position.y   # we slide on Y

	var dl_mesh := _add_mesh(bay.door_left, _box_mesh(bay_width + wall_thick * 2, door_h, door_thickness),
			door_mat, Vector3.ZERO)
	dl_mesh.name = "DoorLeftMesh"
	_add_mesh(bay.door_left, _box_mesh(bay_width + wall_thick * 2, 0.18, door_thickness + 0.04),
			door_edge_mat, Vector3(0, -door_h * 0.5 + 0.09, 0))
	for ri in range(3):
		var rx : float = lerp(-1.4, 1.4, float(ri) / 2.0)
		_add_mesh(bay.door_left, _box_mesh(0.8, door_h * 0.7, 0.04), hull_mat, Vector3(rx, 0, -door_thickness * 0.5 - 0.02))

	for li in range(3):
		var dl_light := OmniLight3D.new()
		dl_light.light_energy = 0.0
		dl_light.omni_range   = 2.5
		dl_light.light_color  = Color(1, 0.25, 0.1)
		bay.door_left.add_child(dl_light)
		dl_light.position = Vector3(lerp(-1.5, 1.5, float(li) / 2.0), -door_h * 0.5 + 0.25, -door_thickness * 0.5 - 0.1)
		bay.door_lights_left.append(dl_light)

	# RIGHT panel (slides DOWN when opening)
	bay.door_right = Node3D.new()
	bay.door_right.name = "DoorRight_%s" % label
	bay.bay_pivot.add_child(bay.door_right)
	bay.door_right.position = Vector3(0, -door_h * 0.5, door_z_offset)
	bay.door_right_base_y = bay.door_right.position.y

	var dr_mesh := _add_mesh(bay.door_right, _box_mesh(bay_width + wall_thick * 2, door_h, door_thickness),
			door_mat, Vector3.ZERO)
	dr_mesh.name = "DoorRightMesh"
	_add_mesh(bay.door_right, _box_mesh(bay_width + wall_thick * 2, 0.18, door_thickness + 0.04),
			door_edge_mat, Vector3(0, door_h * 0.5 - 0.09, 0))
	for ri in range(3):
		var rx : float = lerp(-1.4, 1.4, float(ri) / 2.0)
		_add_mesh(bay.door_right, _box_mesh(0.8, door_h * 0.7, 0.04), hull_mat, Vector3(rx, 0, -door_thickness * 0.5 - 0.02))

	for li in range(3):
		var dr_light := OmniLight3D.new()
		dr_light.light_energy = 0.0
		dr_light.omni_range   = 2.5
		dr_light.light_color  = Color(1, 0.25, 0.1)
		bay.door_right.add_child(dr_light)
		dr_light.position = Vector3(lerp(-1.5, 1.5, float(li) / 2.0), door_h * 0.5 - 0.25, -door_thickness * 0.5 - 0.1)
		bay.door_lights_right.append(dr_light)

	# ── Bay flood-lights (4 per bay, active when door is open) ──────────
	for fi in range(4):
		var flood := OmniLight3D.new()
		flood.light_energy = 0.0
		flood.omni_range   = 8.0
		flood.light_color  = Color(0.8, 0.92, 1.0)  # cool white
		bay.bay_pivot.add_child(flood)
		var fx : float = lerp(-bay_width * 0.4, bay_width * 0.4, float(fi) / 3.0)
		flood.position = Vector3(fx, bay_height * 0.4, 0)
		bay.floods.append(flood)

	# ── Bay atmosphere particles (light haze inside hangar when open) ──
	bay.particles = CPUParticles3D.new()
	bay.particles.amount   = 40
	bay.particles.lifetime = 3.0
	bay.particles.explosiveness = 0.0
	bay.particles.randomness    = 0.8
	bay.particles.direction = Vector3(0, 0.1, 1)
	bay.particles.spread    = 60.0
	bay.particles.gravity   = Vector3.ZERO
	bay.particles.initial_velocity_min = 0.2
	bay.particles.initial_velocity_max = 0.8
	bay.particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	bay.particles.emission_box_extents = Vector3(bay_width * 0.4, bay_height * 0.4, bay_depth * 0.4)
	bay.particles.emitting = false
	var haze_grad := Gradient.new()
	haze_grad.set_color(0, Color(0.7, 0.85, 1.0, 0.0))
	haze_grad.add_point(0.3, Color(0.7, 0.85, 1.0, 0.12))
	haze_grad.add_point(1.0, Color(0.6, 0.75, 1.0, 0.0))
	bay.particles.color_ramp = haze_grad
	var haze_mat := StandardMaterial3D.new()
	haze_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	haze_mat.vertex_color_use_as_albedo = true
	haze_mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	bay.particles.material_override = haze_mat
	bay.particles.mesh = _sphere_mesh(0.25)
	bay.bay_pivot.add_child(bay.particles)
	bay.particles.position = Vector3(0, 0, 0)

	# ── Hangar door trigger area (sits just outside the blast doors) ───
	bay.hangar_trigger = Area3D.new()
	bay.hangar_trigger.name = "HangarTrigger_%s" % label
	bay.hangar_trigger.collision_layer = 0
	bay.bay_pivot.add_child(bay.hangar_trigger)
	bay.hangar_trigger.position = Vector3(0, 0, -bay_depth * 0.5 - 1.0)
	var trigger_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(bay_width * 0.8, bay_height * 0.8, 2.0)
	trigger_shape.shape = box
	bay.hangar_trigger.add_child(trigger_shape)
	bay.hangar_trigger.body_entered.connect(_on_hangar_body_entered.bind(bay))

	# ── Dock position marker (centre of the bay) ───────────────────────
	bay.dock_pos = Marker3D.new()
	bay.dock_pos.name = "DockPosition_%s" % label
	bay.bay_pivot.add_child(bay.dock_pos)
	bay.dock_pos.position = Vector3(0, 0, 0)

	_bays.append(bay)
	return bay


func _build_station_collision(bay_width: float, bay_height: float, bay_depth: float, wall_thick: float) -> void:
	# StaticBody that rotates with the hub so collision matches the visuals.
	var col_body := StaticBody3D.new()
	col_body.name = "StationCollision"
	col_body.collision_layer = 2  # Ship's collision_mask includes layer 2
	hub_pivot.add_child(col_body)

	# ── Central hub cylinder ──────────────────────────────────────────────
	_add_col_shape(col_body, CylinderShape3D.new(), Vector3(5.5, 10.0, 5.5), Vector3.ZERO)

	# ── Four bay wall blocks (all sides EXCEPT the front door opening) ──
	# We mirror the wall geometry we built visually for each BayData.  All
	# shapes are children of hub_pivot so they rotate with the station.
	for bay in _bays:
		var bay_pos: Vector3 = bay.bay_pivot.position
		# Top wall
		_add_col_shape(col_body, BoxShape3D.new(),
			Vector3(bay_width + wall_thick * 2, wall_thick, bay_depth),
			bay_pos + Vector3(0, bay_height * 0.5 + wall_thick * 0.5, 0))
		# Bottom wall
		_add_col_shape(col_body, BoxShape3D.new(),
			Vector3(bay_width + wall_thick * 2, wall_thick, bay_depth),
			bay_pos + Vector3(0, -bay_height * 0.5 - wall_thick * 0.5, 0))
		# Left wall
		_add_col_shape(col_body, BoxShape3D.new(),
			Vector3(wall_thick, bay_height + wall_thick * 2, bay_depth),
			bay_pos + Vector3(-bay_width * 0.5 - wall_thick * 0.5, 0, 0))
		# Right wall
		_add_col_shape(col_body, BoxShape3D.new(),
			Vector3(wall_thick, bay_height + wall_thick * 2, bay_depth),
			bay_pos + Vector3(bay_width * 0.5 + wall_thick * 0.5, 0, 0))
		# Back wall (far end of bay)
		_add_col_shape(col_body, BoxShape3D.new(),
			Vector3(bay_width + wall_thick * 2, bay_height + wall_thick * 2, wall_thick),
			bay_pos + Vector3(0, 0, bay_depth * 0.5))

	# Note: The front face (z = -bay_depth/2) is intentionally left open
	# — that's the hangar door opening the ship flies through.

	# Note: the old ±Z solar-array arms have been removed because the
	# new four-bay design places a hangar on each cardinal axis.


## Helper: add a CollisionShape3D to a StaticBody.
func _add_col_shape(parent: StaticBody3D, shape: Shape3D, size: Vector3, pos: Vector3) -> void:
	if shape is BoxShape3D:
		(shape as BoxShape3D).size = size
	elif shape is CylinderShape3D:
		var c := shape as CylinderShape3D
		c.radius = size.x
		c.height = size.y
	var cs := CollisionShape3D.new()
	cs.shape = shape
	parent.add_child(cs)
	cs.position = pos


# ────────────────────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	_time += delta

	# Slow rotation of the whole hub and the ring
	hub_pivot.rotate_y(delta * spin_speed)
	ring_pivot.rotate_x(delta * spin_speed * 0.3)
	ring_pivot.rotate_y(delta * spin_speed * 0.15)

	# Beacon pulse
	beacon.light_energy = 1.8 + sin(_time * 2.8) * 1.2

	# Refresh each bay's outward direction (it changes as the station rotates).
	# We also drive the per-bay landing-strip LED animation here.
	for bay in _bays:
		bay.outward_dir = (bay.bay_pivot.global_transform.basis * Vector3(0, 0, -1)).normalized()
		if bay.strip_mat:
			var bright := 1.5 + sin(_time * 8.0) * 0.5
			bay.strip_mat.emission_energy_multiplier = bright * bay.door_openness

	# Docking animation: smoothly pull the ship into the active bay
	if _docking_ship != null and is_instance_valid(_docking_ship):
		_docking_progress += delta * dock_pull_speed / 2.0
		var active_bay := _active_docking_bay
		if active_bay == null or active_bay.dock_pos == null:
			# Safety fallback if a bay was freed mid-docking
			active_bay = _bays[0] if _bays.size() > 0 else null
		var current_target := active_bay.dock_pos.global_position if active_bay != null else _docking_target
		current_target.y = ground_height
		if _docking_progress >= 1.0:
			_docking_progress = 1.0
			_docking_ship.global_position = current_target
			_do_finish_docking()
		else:
			var t := ease(_docking_progress, 0.4)  # ease-in
			_docking_ship.global_position = _docking_start.lerp(current_target, t)
			_docking_ship.global_position.y = ground_height
			# Rotate to face out the door (-Z in the active bay's pivot space)
			if active_bay != null:
				var door_dir := -active_bay.bay_pivot.global_transform.basis.z
				_docking_ship.global_rotation.y = atan2(-door_dir.x, -door_dir.z)

	_update_doors(delta)
	_update_door_lights()


# ────────────────────────────────────────────────────────────────────────────
func _update_doors(delta: float) -> void:
	# Per-bay door control.  Each bay only opens when a ship is approaching
	# IT (within door_open_distance of that bay's outward position) or is
	# currently docking/docked in it.  This stops every door from opening
	# at once when the player approaches any one bay.
	var ship: Node3D = null
	for s in get_tree().get_nodes_in_group("ship"):
		if is_instance_valid(s):
			ship = s
			break

	for bay in _bays:
		bay.door_want = 0.0
		# Keep the bay fully open while a ship is docking/docked inside it
		if (_docked_ship != null and _active_docked_bay == bay) \
				or (_docking_ship != null and _active_docking_bay == bay):
			bay.door_want = 1.0
		elif ship != null:
			# Distance from the ship to the bay's outward face (the door)
			var door_world_pos: Vector3 = bay.bay_pivot.global_position \
					+ bay.bay_pivot.global_transform.basis * Vector3(0, 0, -BAY_DEPTH * 0.5 - 0.5)
			var d: float = ship.global_position.distance_to(door_world_pos)
			if d < door_open_distance:
				bay.door_want = max(bay.door_want, 1.0 - clamp(d / door_open_distance, 0.0, 1.0))

		# Smooth approach
		bay.door_openness = move_toward(bay.door_openness, bay.door_want, delta * door_speed)

		# Animate this bay's doors / particles / floods
		# TOP panel slides UP (positive Y)
		if bay.door_left:
			bay.door_left.position.y = bay.door_left_base_y + door_slide_distance * bay.door_openness
		# BOTTOM panel slides DOWN (negative Y)
		if bay.door_right:
			bay.door_right.position.y = bay.door_right_base_y - door_slide_distance * bay.door_openness
		# Bay particles / flood-lights follow the door openness
		if bay.particles:
			bay.particles.emitting = bay.door_openness > 0.05
		for fl in bay.floods:
			fl.light_energy = bay.door_openness * 3.5


# ────────────────────────────────────────────────────────────────────────────
func _update_door_lights() -> void:
	# When closed → red warning lights; when fully open → green go-lights.
	# Per-bay so each bay's lights track its own door state.
	var green_color : Color = Color(0.1, 1.0, 0.35)
	var red_color   : Color = Color(1.0, 0.25, 0.1)

	for bay in _bays:
		var light_color : Color = red_color.lerp(green_color, bay.door_openness)
		var energy      : float = 1.2 + sin(_time * 4.0 + bay.door_openness * PI) * 0.4
		for l in bay.door_lights_left + bay.door_lights_right:
			l.light_color  = light_color
			l.light_energy = energy * clamp(bay.door_openness * 3.0 + 0.3, 0.0, 2.0)


# ────────────────────────────────────────────────────────────────────────────
func is_ship_docked(ship: Node3D) -> bool:
	return _docked_ship == ship


## Returns true if the ship is currently in a hangar bay — either being
## pulled in by the docking animation, or fully docked.  Used by the main
## loop to open the skill tree as soon as the ship enters a bay (not just
## when the docking animation completes).
func is_ship_docking_or_docked(ship: Node3D) -> bool:
	return _docking_ship == ship or _docked_ship == ship


## Returns all hangar bay pivots.  Most callers will want get_bay_for_ship()
## instead of picking a specific one.
func get_bays() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for bay in _bays:
		out.append(bay.bay_pivot)
	return out


## Returns the bay pivot whose outward direction best matches the ship's
## current position.  Used by the harpoon so the ship never has to fly
## through the station to reach a door.
func get_bay_for_ship(ship_global_pos: Vector3) -> Node3D:
	if _bays.is_empty():
		return null
	# Direction from station centre to ship, in world space.
	var ship_dir_world := (ship_global_pos - global_position)
	ship_dir_world.y = 0.0
	if ship_dir_world.length_squared() < 0.0001:
		return _bays[0].bay_pivot
	ship_dir_world = ship_dir_world.normalized()
	# Convert to hub_pivot local space (the bays live as children of hub_pivot).
	var to_local := hub_pivot.global_transform.basis.transposed()
	var ship_dir_local := (to_local * ship_dir_world).normalized()

	var best_bay: BayData = null
	var best_dot: float = -2.0
	for bay in _bays:
		var outward_local := bay.bay_pivot.position
		outward_local.y = 0.0
		if outward_local.length_squared() < 0.0001:
			continue
		outward_local = outward_local.normalized()
		var dot := outward_local.dot(ship_dir_local)
		if dot > best_dot:
			best_dot = dot
			best_bay = bay
	return best_bay.bay_pivot if best_bay != null else _bays[0].bay_pivot


## World-space position of the door for a given bay pivot (just outside the
## blast doors in the direction they open).  Safe to call every frame — the
## bay rotates with the station so the result tracks the live position.
func get_door_anchor_for_bay(bay_pivot: Node3D, offset: float = 2.8) -> Vector3:
	for bay in _bays:
		if bay.bay_pivot == bay_pivot:
			var local_offset := Vector3(0, 0, -offset)  # door faces local -Z
			return bay_pivot.global_position + bay_pivot.global_transform.basis * local_offset
	return bay_pivot.global_position if bay_pivot != null else global_position


## World-space direction the given bay's door opens (away from the station).
func get_door_dir_for_bay(bay_pivot: Node3D) -> Vector3:
	if bay_pivot == null:
		return Vector3.FORWARD
	return (bay_pivot.global_transform.basis * Vector3(0, 0, -1)).normalized()


## World-space dock position for the given bay pivot (where the ship rests
## once docking animation completes).
func get_dock_pos_for_bay(bay_pivot: Node3D) -> Vector3:
	for bay in _bays:
		if bay.bay_pivot == bay_pivot and bay.dock_pos != null:
			return bay.dock_pos.global_position
	return global_position


## Returns the BayData record for the given bay pivot, or null if not found.
func get_bay_data(bay_pivot: Node3D) -> BayData:
	for bay in _bays:
		if bay.bay_pivot == bay_pivot:
			return bay
	return null


## Called by the ship (e.g. after harpoon reel) to register as docked without
## animation.  If `bay_pivot` is provided the ship is associated with that bay
## so deploy launches out the right door.
func register_docked_ship(ship: Node3D, bay_pivot: Node3D = null) -> void:
	_docked_ship = ship
	_docking_ship = null
	_docking_progress = 0.0
	_active_docked_bay = get_bay_data(bay_pivot) if bay_pivot != null else null
	_active_docking_bay = null


## Called when the ship leaves the dock for any reason (deploy, respawn, etc.)
func undock_ship() -> void:
	_docked_ship = null
	if _docking_ship != null:
		_docking_ship = null
		_docking_progress = 0.0
	_active_docking_bay = null
	_active_docked_bay = null


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("ship") and not ships_in_dock.has(body):
		ships_in_dock.append(body)


func _on_body_exited(body: Node) -> void:
	if ships_in_dock.has(body):
		ships_in_dock.erase(body)


# ── Hangar door docking ───────────────────────────────────────────────────────

func _on_hangar_body_entered(body: Node, bay: BayData) -> void:
	if _docked_ship != null or _docking_ship != null:
		return
	if not body.is_in_group("ship"):
		return
	var ship := body as Node3D
	if ship == null:
		return
	# Only dock if the ship is in FLYING state
	if ship.has_method("get_state") and ship.get_state() != 0:  # 0 = FLYING
		return
	# Only dock if this bay's doors are mostly open
	if bay.door_openness < 0.85:
		return
	# Only dock if moving slowly — flying through at speed shouldn't grab
	if ship.has_method("get_ship_velocity"):
		var vel := ship.get_ship_velocity() as Vector3
		if vel.length() > 6.0:
			return

	_do_start_docking(ship, bay)


func _do_start_docking(ship: Node3D, bay: BayData = null) -> void:
	_docking_ship = ship
	_docking_start = ship.global_position
	_active_docking_bay = bay if bay != null else (_bays[0] if _bays.size() > 0 else null)
	if _active_docking_bay != null:
		_docking_target = _active_docking_bay.dock_pos.global_position
	else:
		_docking_target = _docking_start
	_docking_target.y = ground_height
	_docking_progress = 0.0

	# Freeze the ship's velocity and disable its physics while docking
	if ship.has_method("set_freezing"):
		ship.set_freezing(true)

	SoundManager.play_by_id("sfx_dock")


func _do_finish_docking() -> void:
	if _docking_ship == null:
		return
	var ship := _docking_ship
	_docked_ship = ship
	_docking_ship = null
	_docking_progress = 0.0
	_active_docked_bay = _active_docking_bay
	_active_docking_bay = null

	# Snap ship to exact dock position of the bay it was pulled into
	if _active_docked_bay != null and _active_docked_bay.dock_pos != null:
		ship.global_position = _active_docked_bay.dock_pos.global_position
	ship.global_position.y = ground_height
	# Face out the door
	if _active_docked_bay != null:
		var door_dir := -_active_docked_bay.bay_pivot.global_transform.basis.z
		ship.global_rotation.y = atan2(-door_dir.x, -door_dir.z)

	# Tell the ship it's docked
	if ship.has_method("dock_at_station"):
		ship.dock_at_station(self)


## Called by the ship (or skill tree) to deploy / launch.
func deploy_ship() -> void:
	if _docked_ship == null or not is_instance_valid(_docked_ship):
		return
	var ship := _docked_ship
	_docked_ship = null

	# Launch the ship out the hangar door direction of the bay it's docked in
	var launch_dir := Vector3.FORWARD
	if _active_docked_bay != null:
		launch_dir = -_active_docked_bay.bay_pivot.global_transform.basis.z
	launch_dir.y = 0.0
	if launch_dir.length_squared() < 0.0001:
		launch_dir = Vector3.FORWARD
	launch_dir = launch_dir.normalized()

	_active_docked_bay = null

	if ship.has_method("deploy_from_station"):
		ship.deploy_from_station(self, launch_dir)


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
