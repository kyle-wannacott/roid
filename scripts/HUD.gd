extends CanvasLayer
## Ship HUD.
## Bottom-right diagetic cockpit instrument panel + dynamic crosshair + pilot portrait.
## Left-side ship radar (tactical) replaces the old "Safe / Enemies" labels.
##
## Bottom-right panel layout (from HUD.tscn):
##   BottomRight/VBox
##     ├ Header         (title, PWR LED, bolts)
##     ├ BodyMargin/Body
##     │   ├ FuelCell   (small FUEL speedo + label/value)
##     │   ├ GemsCell   (small CARGO speedo + label/value)
##     │   └ SpeedCell  (large VELOCITY speedo + label/value)
##     └ LCDMargin/LCD  (phosphor-green: STN, STATE, LED row, HULL bar)
##
## Left-side radar (Root/Radar):
##   RadarVBox
##     ├ RadarTitle     ("◢ TACTICAL ◣")
##     ├ RadarCanvas    (custom _draw: range rings, sweep, blips)
##     └ Status row     (DANGER + ENEMY COUNT)
##
## Speedo face has 0 at the bottom (6 o'clock) and 8 at the right (3 o'clock).
## The needle image has the bulb at the top and the tip at the bottom.
## We anchor the pivot at the bulb and the rotation = 0 (natural orientation)
## puts the tip at "0". Rotating CW by 3*PI/2 (270°) sweeps the long way
## through 1, 2, 3, 4, 5, 6, 7 to "8".

# ── Reticle references ─────────────────────────────────────────────────────
@onready var reticle: Control = $Root/Reticle
@onready var controls_label: Label = $Root/Bottom/Center/Controls
@onready var _pilot_portrait: TextureRect = $Root/PilotPortrait
@onready var _pilot_viewport: SubViewport = $PilotViewport
@onready var _pilot: Node3D = $PilotViewport/PilotCharacter if has_node("PilotViewport/PilotCharacter") else null

# ── Bottom-right instrument panel ──────────────────────────────────────────
# Main speedo
@onready var speedo_needle: TextureRect = %SpeedoNeedle
@onready var speedo_value: Label = %SpeedoValue
# Small speedos
@onready var fuel_needle: TextureRect = %FuelNeedle
@onready var fuel_value: Label = %FuelValue
@onready var gems_needle: TextureRect = %GemsNeedle
@onready var gems_value: RichTextLabel = %GemsValue
# Hull bar (now inside the LCD)
@onready var hull_value: Label = %HullValue
@onready var hull_bar: ProgressBar = %HullBar
# Status LEDs (now inside the LCD)
@onready var armed_dot: ColorRect = %ArmedDot
@onready var shield_dot: ColorRect = %ShieldDot
@onready var dock_dot: ColorRect = %DockDot
@onready var harp_dot: ColorRect = %HarpDot
@onready var warn_dot: ColorRect = %WarnDot
@onready var pwr_led: ColorRect = %PwrLED
# LCD
@onready var station_value: Label = %StationValue
@onready var state_value: Label = %StateValue

# ── Radar (left side, above pilot portrait) ────────────────────────────────
@onready var radar_canvas: Control = %RadarCanvas
@onready var radar_danger_label: Label = %DangerValue
@onready var radar_enemy_count: Label = %EnemyCount

# ── Reticle settings ───────────────────────────────────────────────────────
@export var reticle_attack_color: Color = Color(1.0, 0.35, 0.35)
@export var reticle_idle_color: Color = Color(0.8, 0.85, 1.0, 0.6)
@export var reticle_stranded_color: Color = Color(1.0, 0.6, 0.2)

# ── Speedometer needle constants ──────────────────────────────────────────
# Rotation 0 → tip at "0" (DOWN).
# Rotation 3*PI/2 (270° CW) → tip at "8" (RIGHT, after sweeping the long way).
const NEEDLE_REST: float = 0.0
const NEEDLE_SWEEP: float = 3.0 * PI / 2.0

# ── Calibration ────────────────────────────────────────────────────────────
const MAX_SPEED: float = 35.0
const RADAR_RANGE: float = 100.0  # World units shown on the radar (threat scope — matches enemy leash)
const RADAR_SWEEP_SPEED: float = 1.8  # Radians per second
var _gem_capacity: int = 50
var _last_docked: bool = false

# ── Crosshair accuracy state ───────────────────────────────────────────────
var _current_accuracy: float = 1.0
var _target_accuracy: float = 1.0
@export var accuracy_smoothing: float = 5.0
@export var reticle_min_size: float = 8.0
@export var reticle_max_size: float = 40.0

var _h_line: ColorRect
var _h_line2: ColorRect
var _v_line: ColorRect
var _v_line2: ColorRect
var _dot: ColorRect
var _diag_line: ColorRect
var _diag_line2: ColorRect

var _crosshair_offset_y: float = 0.0
var _crosshair_target_offset: float = 0.0

var _hit_indicator_timer: float = 0.0
var _hit_indicator_duration: float = 0.15
var _hit_flash_active: bool = false

# ── PWR / LED pulse ────────────────────────────────────────────────────────
var _pwr_phase: float = 0.0

# ── Radar state ────────────────────────────────────────────────────────────
var _radar_sweep_angle: float = 0.0
var _radar_ship: Node3D = null
var _radar_station: Node3D = null
var _radar_enemy_mgr: Node3D = null


func _ready() -> void:
	add_to_group("hud")

	# Wire pilot viewport to portrait texture
	if _pilot_portrait and _pilot_viewport:
		_pilot_portrait.texture = _pilot_viewport.get_texture()

	# Reticle components
	_h_line = $Root/Reticle/HLine
	_h_line2 = $Root/Reticle/HLine2
	_v_line = $Root/Reticle/VLine
	_v_line2 = $Root/Reticle/VLine2
	_dot = $Root/Reticle/Dot

	# Diagonal hit indicator lines
	_diag_line = ColorRect.new()
	_diag_line.color = Color(1.0, 0.2, 0.2, 0.8)
	_diag_line.visible = false
	$Root/Reticle.add_child(_diag_line)

	_diag_line2 = ColorRect.new()
	_diag_line2.color = Color(1.0, 0.2, 0.2, 0.8)
	_diag_line2.visible = false
	$Root/Reticle.add_child(_diag_line2)

	# Initial needle state
	_set_needle_rotation(speedo_needle, 0.0)
	_set_needle_rotation(fuel_needle, 1.0)   # full fuel at start
	_set_needle_rotation(gems_needle, 0.0)

	# Wire the radar canvas's draw signal so we can paint the scope
	if radar_canvas:
		radar_canvas.draw.connect(_draw_radar)

	# Radar is a skill-gated UI element — hidden until the "Tactical Radar"
	# skill is unlocked. Listen for unlocks and check current state.
	_apply_radar_unlock()
	if PlayerSkills and not PlayerSkills.skill_unlocked.is_connected(_on_skill_unlocked):
		PlayerSkills.skill_unlocked.connect(_on_skill_unlocked)


func _process(delta: float) -> void:
	# Crosshair accuracy smoothing
	_current_accuracy = lerp(_current_accuracy, _target_accuracy, accuracy_smoothing * delta)
	_crosshair_offset_y = lerp(_crosshair_offset_y, _crosshair_target_offset, 8.0 * delta)

	# Hit indicator timer
	if _hit_flash_active:
		_hit_indicator_timer -= delta
		if _hit_indicator_timer <= 0:
			_hit_flash_active = false
			_diag_line.visible = false
			_diag_line2.visible = false

	_update_reticle_size()

	# PWR LED pulse
	_pwr_phase += delta * 2.4
	if pwr_led:
		var pulse: float = 0.7 + 0.3 * (0.5 + 0.5 * sin(_pwr_phase))
		pwr_led.color = Color(0.3, 1.0, 0.4, pulse)

	# Warn LED pulse (only when something is wrong)
	if warn_dot and warn_dot.color.a > 0.6:
		var wp: float = 0.4 + 0.6 * (0.5 + 0.5 * sin(_pwr_phase * 1.5))
		warn_dot.color.a = wp

	# Radar sweep
	_radar_sweep_angle += RADAR_SWEEP_SPEED * delta
	if _radar_sweep_angle >= TAU:
		_radar_sweep_angle -= TAU

	_update_radar(delta)
	_update_pilot(delta)


# ═══════════════════════════════════════════════════════════════════════════
#  PUBLIC API — called by ship via signals wired in Main.gd
# ═══════════════════════════════════════════════════════════════════════════

func set_speed(speed: float) -> void:
	var pct: float = clamp(speed / MAX_SPEED, 0.0, 1.0)
	_set_needle_rotation(speedo_needle, pct)
	speedo_value.text = "%5.1f" % speed
	if pct > 0.85:
		speedo_value.modulate = Color(1.0, 0.4, 0.35)
	elif pct > 0.6:
		speedo_value.modulate = Color(1.0, 0.85, 0.35)
	else:
		speedo_value.modulate = Color(0.6, 1.0, 0.85)


func set_fuel(fuel: float, max_fuel: float) -> void:
	var pct: float = (fuel / max_fuel) if max_fuel > 0.0 else 0.0
	_set_needle_rotation(fuel_needle, pct)
	fuel_value.text = "%d / %d" % [int(round(fuel)), int(round(max_fuel))]
	if pct < 0.2:
		fuel_value.modulate = Color(1.0, 0.35, 0.3)
	elif pct < 0.45:
		fuel_value.modulate = Color(1.0, 0.85, 0.35)
	else:
		fuel_value.modulate = Color(0.6, 1.0, 0.85)


func set_gems(inventory) -> void:
	var total: int = 0
	var parts: Array[String] = []
	if inventory is Dictionary:
		for type in GemTypeData.TYPES:
			var c: int = int(inventory.get(type, 0))
			total += c
			if c > 0:
				var hex: String = GemTypeData.get_hex(type)
				parts.append("[color=#%s]%d[/color]" % [hex, c])
	else:
		total = int(inventory)

	if parts.is_empty():
		gems_value.text = "0"
	else:
		gems_value.text = "  ".join(parts)

	# Needle reflects total / capacity
	var pct: float = float(total) / float(max(1, _gem_capacity))
	_set_needle_rotation(gems_needle, clamp(pct, 0.0, 1.0))

	# Display: prefer showing the per-type BBCode if any; otherwise "0 / cap"
	if total > 0 and not parts.is_empty():
		# Show the BBCode breakdown in the value field
		gems_value.bbcode_enabled = true
		gems_value.text = "  ".join(parts)
		gems_value.modulate = Color(1, 1, 1)
	else:
		gems_value.bbcode_enabled = false
		gems_value.text = "0 / %d" % _gem_capacity
		gems_value.modulate = Color(0.7, 0.85, 0.95)

	# Elastic pulse on update
	if gems_value:
		var tween := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)
		tween.tween_method(func(v: float): gems_value.scale = Vector2(v, v), 1.25, 1.0, 0.35)


func set_gem_capacity(current: int, max_capacity: int) -> void:
	_gem_capacity = max_capacity
	var pct: float = float(current) / float(max(1, max_capacity))
	_set_needle_rotation(gems_needle, clamp(pct, 0.0, 1.0))
	# Only set plain text here — the BBCode breakdown is handled in set_gems.
	gems_value.bbcode_enabled = false
	gems_value.text = "%d / %d" % [current, max_capacity]
	gems_value.modulate = (Color(1.0, 0.8, 0.3) if current >= max_capacity
			else Color(0.7, 0.85, 0.95))


func set_station_distance(dist: float, docked: bool) -> void:
	_last_docked = docked
	if docked:
		station_value.text = "DOCKED"
		station_value.modulate = Color(0.4, 1.0, 0.55)
	else:
		station_value.text = "%7.1f m" % dist
		var closeness: float = clamp(1.0 - (dist - 50.0) / 800.0, 0.35, 1.0)
		station_value.modulate = Color(0.45, 1.0, 0.65, 0.7 + closeness * 0.3)


func set_health(health: float, max_hp: float) -> void:
	hull_value.text = "%d/%d" % [int(round(health)), int(round(max_hp))]
	hull_bar.max_value = max_hp
	hull_bar.value = health
	var pct: float = (health / max_hp) if max_hp > 0.0 else 0.0
	if pct > 0.6:
		hull_bar.modulate = Color(0.4, 1.0, 0.55)
	elif pct > 0.3:
		hull_bar.modulate = Color(1.0, 0.9, 0.35)
	else:
		hull_bar.modulate = Color(1.0, 0.4, 0.4)
	hull_value.modulate = hull_bar.modulate


func set_shield(ready: bool, cooldown: float) -> void:
	if ready:
		shield_dot.color = Color(0.3, 0.85, 1.0, 0.95)
	else:
		shield_dot.color = Color(0.3, 0.3, 0.3, 0.5)


func set_state(state: int) -> void:
	# State values: 0=FLYING 1=STRANDED 2=HARPOON_FLY 3=HARPOON_REEL 4=DOCKED
	match state:
		0:
			state_value.text = "FLYING"
			state_value.modulate = Color(0.4, 1.0, 0.55)
			harp_dot.color = Color(0.3, 0.3, 0.3, 0.4)
			warn_dot.color = Color(0.3, 0.3, 0.3, 0.4)
		1:
			state_value.text = "STRANDED"
			state_value.modulate = Color(1.0, 0.7, 0.3)
			harp_dot.color = Color(1.0, 0.85, 0.3, 0.95)
			warn_dot.color = Color(1.0, 0.7, 0.2, 0.95)
		2:
			state_value.text = "HARPOON OUT"
			state_value.modulate = Color(1.0, 0.9, 0.3)
			harp_dot.color = Color(1.0, 0.85, 0.3, 0.95)
		3:
			state_value.text = "REELING"
			state_value.modulate = Color(0.6, 0.9, 1.0)
			harp_dot.color = Color(1.0, 0.3, 0.2, 0.95)
			warn_dot.color = Color(1.0, 0.4, 0.3, 0.9)
		4:
			state_value.text = "DOCKED"
			state_value.modulate = Color(0.5, 1.0, 0.65)
			dock_dot.color = Color(0.3, 1.0, 0.45, 0.95)
		_:
			state_value.text = "—"
			state_value.modulate = Color(0.5, 0.5, 0.5)


func set_mining(mining: bool, can_mine: bool) -> void:
	if mining and can_mine:
		armed_dot.color = Color(1.0, 0.35, 0.3, 0.95)
		reticle.modulate = reticle_attack_color
	elif can_mine:
		armed_dot.color = Color(0.4, 1.0, 0.5, 0.95)
		reticle.modulate = reticle_idle_color
	else:
		armed_dot.color = Color(0.3, 0.3, 0.3, 0.4)
		reticle.modulate = reticle_idle_color


func set_accuracy_from_speed(speed: float, max_speed: float) -> void:
	var speed_pct: float = clamp(speed / max(1.0, max_speed), 0.0, 1.0)
	_target_accuracy = 1.0 - (speed_pct * 0.7)


# ── Misc helpers ──────────────────────────────────────────────────────────

func show_message(text: String, duration: float = 2.5) -> void:
	var msg: Label = $Root/Message
	msg.text = text
	msg.modulate.a = 1.0
	msg.show()
	var tween := create_tween()
	tween.tween_interval(duration)
	tween.tween_property(msg, "modulate:a", 0.0, 0.6)
	tween.tween_callback(msg.hide)


func set_crosshair_thrust_offset(thrust_input: float) -> void:
	_crosshair_target_offset = thrust_input * -6.0


func show_hit_indicator() -> void:
	_hit_flash_active = true
	_hit_indicator_timer = _hit_indicator_duration
	_diag_line.visible = true
	_diag_line2.visible = true


# ═══════════════════════════════════════════════════════════════════════════
#  INTERNAL
# ═══════════════════════════════════════════════════════════════════════════

func _set_needle_rotation(needle: TextureRect, pct: float) -> void:
	if needle == null:
		return
	needle.rotation = NEEDLE_REST + clamp(pct, 0.0, 1.0) * NEEDLE_SWEEP


# ═══════════════════════════════════════════════════════════════════════════
#  SKILL-GATED RADAR
# ═══════════════════════════════════════════════════════════════════════════

const RADAR_SKILL_ID: StringName = &"tactical_radar"

func _apply_radar_unlock() -> void:
	var radar: Control = get_node_or_null("Root/Radar")
	if radar == null:
		return
	var unlocked: bool = PlayerSkills != null and PlayerSkills.is_unlocked(RADAR_SKILL_ID)
	radar.visible = unlocked


func _on_skill_unlocked(skill_id: String) -> void:
	if skill_id == RADAR_SKILL_ID:
		_apply_radar_unlock()


func _update_reticle_size() -> void:
	if _h_line == null:
		return
	var spread: float = lerp(reticle_max_size, reticle_min_size, _current_accuracy)
	var center: float = 12.0
	var line_width: float = 2.0
	var gap: float = spread
	var line_length: float = 8.0 + (1.0 - _current_accuracy) * 4.0
	var offset_y: float = _crosshair_offset_y

	_h_line.position.x = center + gap
	_h_line.position.y = center - line_width / 2.0 + offset_y
	_h_line.size.x = line_length
	_h_line.size.y = line_width
	_h_line2.position.x = center - gap - line_length
	_h_line2.position.y = center - line_width / 2.0 + offset_y
	_h_line2.size.x = line_length
	_h_line2.size.y = line_width
	_v_line.position.x = center - line_width / 2.0
	_v_line.position.y = center + gap + offset_y
	_v_line.size.x = line_width
	_v_line.size.y = line_length
	_v_line2.position.x = center - line_width / 2.0
	_v_line2.position.y = center - gap - line_length + offset_y
	_v_line2.size.x = line_width
	_v_line2.size.y = line_length

	if _dot:
		var dot_size: float = 2.0 + (1.0 - _current_accuracy) * 2.0
		_dot.position.x = center - dot_size / 2.0
		_dot.position.y = center - dot_size / 2.0 + offset_y
		_dot.size.x = dot_size
		_dot.size.y = dot_size
		_dot.color = Color.GREEN.lerp(Color.RED, 1.0 - _current_accuracy)

	if _hit_flash_active:
		var diag_length: float = 6.0
		var diag_width: float = 1.5
		_diag_line.position.x = center - 4.0
		_diag_line.position.y = center - 4.0 + offset_y
		_diag_line.size = Vector2(diag_length, diag_width)
		_diag_line.rotation = PI / 4.0
		_diag_line2.position.x = center + 4.0 - diag_length
		_diag_line2.position.y = center - 4.0 + offset_y
		_diag_line2.size = Vector2(diag_length, diag_width)
		_diag_line2.rotation = -PI / 4.0


# ── Radar drawing ─────────────────────────────────────────────────────────

func _update_radar(_delta: float) -> void:
	if radar_canvas == null:
		return
	# Lazily resolve the scene nodes
	if _radar_ship == null or not is_instance_valid(_radar_ship):
		_radar_ship = get_tree().get_first_node_in_group("player_ship")
	if _radar_enemy_mgr == null or not is_instance_valid(_radar_enemy_mgr):
		_radar_enemy_mgr = get_tree().get_first_node_in_group("enemy_managers")
		if _radar_enemy_mgr == null:
			# Fall back to name lookup
			_radar_enemy_mgr = _find_node_by_name(get_tree().root, "EnemyManager")
	# Station: a sibling of the ship under Main
	if _radar_station == null or not is_instance_valid(_radar_station):
		_radar_station = _find_node_by_name(get_tree().root, "SpaceStation")
	# Update labels
	_update_radar_labels()
	# Trigger redraw
	radar_canvas.queue_redraw()


func _draw_radar() -> void:
	if radar_canvas == null:
		return
	var size_v: Vector2 = radar_canvas.size
	var center: Vector2 = size_v * 0.5
	var radius: float = min(size_v.x, size_v.y) * 0.5 - 6.0

	# Background fill (slightly darker than the surrounding panel)
	radar_canvas.draw_circle(center, radius, Color(0.01, 0.04, 0.025, 0.95))

	# Range rings
	radar_canvas.draw_arc(center, radius * 0.33, 0.0, TAU, 36,
			Color(0.2, 0.55, 0.35, 0.45), 1.0)
	radar_canvas.draw_arc(center, radius * 0.66, 0.0, TAU, 48,
			Color(0.2, 0.55, 0.35, 0.45), 1.0)
	radar_canvas.draw_arc(center, radius, 0.0, TAU, 64,
			Color(0.3, 0.75, 0.45, 0.7), 1.4)

	# Crosshair lines
	var x_color: Color = Color(0.2, 0.55, 0.35, 0.4)
	radar_canvas.draw_line(Vector2(center.x - radius, center.y),
			Vector2(center.x + radius, center.y), x_color, 1.0)
	radar_canvas.draw_line(Vector2(center.x, center.y - radius),
			Vector2(center.x, center.y + radius), x_color, 1.0)

	# FWD label at the top (radar rotates with the ship → top = forward)
	var label_color: Color = Color(0.45, 1, 0.6, 0.85)
	radar_canvas.draw_string(ThemeDB.fallback_font,
			Vector2(center.x - 8, center.y - radius - 2), "FWD",
			HORIZONTAL_ALIGNMENT_CENTER, -1, 10, label_color)

	if not is_instance_valid(_radar_ship):
		return

	# Ship heading: 0 when the ship's forward = world -Z, increases as the
	# ship yaws clockwise (when viewed from above).
	var forward: Vector3 = -_radar_ship.global_transform.basis.z
	forward.y = 0.0
	var heading: float = 0.0
	if forward.length_squared() > 0.0001:
		forward = forward.normalized()
		heading = atan2(forward.x, -forward.z)

	# Sweep beam — fading trail. The sweep angle is independent of the ship
	# (it's the radar dish rotating on top of the ship), so the user always
	# sees the sweep tracing around the world.
	var sweep_color: Color = Color(0.4, 1.0, 0.55, 0.55)
	for i in range(24):
		var a: float = _radar_sweep_angle - i * 0.06
		var end_pt: Vector2 = center + Vector2(cos(a), sin(a)) * radius
		var alpha: float = sweep_color.a * (1.0 - float(i) / 24.0)
		radar_canvas.draw_line(center, end_pt, Color(sweep_color.r, sweep_color.g, sweep_color.b, alpha), 1.4)
	# Bright leading edge
	var leading: Vector2 = center + Vector2(cos(_radar_sweep_angle), sin(_radar_sweep_angle)) * radius
	radar_canvas.draw_line(center, leading, Color(0.6, 1, 0.7, 0.95), 1.8)

	# === Blips are plotted in the SHIP-RELATIVE frame ===
	# angle_rel = atan2(x, -z) - heading  (0 = directly in front of the ship,
	# increases CW as viewed from above). On the screen, angle 0 maps to up.
	# 1 unit of distance on the radar = RADAR_RANGE world units.

	# Station marker (cyan diamond)
	if is_instance_valid(_radar_station):
		var to_station: Vector3 = _radar_station.global_position - _radar_ship.global_position
		to_station.y = 0.0
		var dist_s: float = to_station.length()
		if dist_s < RADAR_RANGE * 1.5:
			var angle_s: float = atan2(to_station.x, -to_station.z) - heading
			var s_pos: Vector2 = center + Vector2(sin(angle_s), -cos(angle_s)) * (dist_s / RADAR_RANGE) * radius
			if s_pos.distance_to(center) <= radius + 2.0:
				var dpts: PackedVector2Array = PackedVector2Array([
					s_pos + Vector2(0, -4),
					s_pos + Vector2(4, 0),
					s_pos + Vector2(0, 4),
					s_pos + Vector2(-4, 0),
				])
				radar_canvas.draw_colored_polygon(dpts, Color(0.3, 0.7, 1.0, 0.95))

	# Enemy blips
	if is_instance_valid(_radar_enemy_mgr) and "active_enemies" in _radar_enemy_mgr:
		for enemy in _radar_enemy_mgr.active_enemies:
			if not is_instance_valid(enemy):
				continue
			var to_e: Vector3 = enemy.global_position - _radar_ship.global_position
			to_e.y = 0.0
			var d: float = to_e.length()
			if d > RADAR_RANGE:
				continue
			var angle_e: float = atan2(to_e.x, -to_e.z) - heading
			var e_pos: Vector2 = center + Vector2(sin(angle_e), -cos(angle_e)) * (d / RADAR_RANGE) * radius
			# Colour shifts red as enemy gets closer
			var t: float = clamp(d / 400.0, 0.0, 1.0)
			var e_col: Color = Color(1.0, 0.3, 0.2).lerp(Color(1.0, 0.85, 0.3), t)
			radar_canvas.draw_circle(e_pos, 2.6, e_col)
			# Sweep-reveal flash
			var d_ang: float = wrapf(angle_e - _radar_sweep_angle, -PI, PI)
			if abs(d_ang) < 0.3:
				radar_canvas.draw_circle(e_pos, 4.0, Color(1, 1, 1, 0.35))

	# === Diagetic "lil radar dish" at the centre ===
	# Outer dome (the dish body)
	radar_canvas.draw_circle(center, 5.5, Color(0.1, 0.35, 0.2, 0.95))
	radar_canvas.draw_arc(center, 5.5, 0.0, TAU, 32,
			Color(0.4, 0.9, 0.55, 0.9), 1.2)
	# Inner feed-horn dot
	radar_canvas.draw_circle(center, 2.2, Color(0.5, 1, 0.7, 1.0))
	# Antenna line that rotates with the sweep
	var ant_len: float = 8.0
	var ant_end: Vector2 = center + Vector2(sin(_radar_sweep_angle), -cos(_radar_sweep_angle)) * ant_len
	radar_canvas.draw_line(center, ant_end, Color(0.7, 1, 0.8, 0.95), 1.6)
	# Counter-weight on the back of the antenna
	var ant_back: Vector2 = center - Vector2(sin(_radar_sweep_angle), -cos(_radar_sweep_angle)) * 3.0
	radar_canvas.draw_line(center, ant_back, Color(0.4, 0.7, 0.5, 0.7), 1.2)


func _update_radar_labels() -> void:
	if radar_enemy_count == null or radar_danger_label == null:
		return
	# Enemy count
	var count: int = 0
	if is_instance_valid(_radar_enemy_mgr) and _radar_enemy_mgr.has_method("get_enemy_count"):
		count = _radar_enemy_mgr.get_enemy_count()
	radar_enemy_count.text = "%02d" % count

	# Closest enemy distance for danger level
	var closest: float = INF
	if is_instance_valid(_radar_enemy_mgr) and "active_enemies" in _radar_enemy_mgr:
		for enemy in _radar_enemy_mgr.active_enemies:
			if not is_instance_valid(enemy) or not is_instance_valid(_radar_ship):
				continue
			var d: float = enemy.global_position.distance_to(_radar_ship.global_position)
			if d < closest:
				closest = d

	if closest < 150.0:
		radar_danger_label.text = "DANGER"
		radar_danger_label.modulate = Color(1.0, 0.25, 0.25)
	elif closest < 350.0:
		radar_danger_label.text = "HIGH"
		radar_danger_label.modulate = Color(1.0, 0.6, 0.2)
	elif closest < 600.0:
		radar_danger_label.text = "CAUTION"
		radar_danger_label.modulate = Color(1.0, 0.95, 0.3)
	else:
		radar_danger_label.text = "SAFE"
		radar_danger_label.modulate = Color(0.3, 1.0, 0.5)


func _find_node_by_name(node: Node, target_name: String) -> Node:
	if node == null:
		return null
	if node.name == target_name:
		return node
	for child in node.get_children():
		var found: Node = _find_node_by_name(child, target_name)
		if found != null:
			return found
	return null


# ═══════════════════════════════════════════════════════════════════════════
#  Pilot portrait animation (unchanged)
# ═══════════════════════════════════════════════════════════════════════════

func _update_pilot(_delta: float) -> void:
	if _pilot == null or not is_instance_valid(_pilot):
		_pilot = $PilotViewport/PilotCharacter if has_node("PilotViewport/PilotCharacter") else null
		if _pilot == null:
			return

	var ship := get_tree().get_first_node_in_group("player_ship")
	if ship == null or not is_instance_valid(ship):
		_pilot.set("ship_thrust", 0.0)
		_pilot.set("ship_roll", 0.0)
		_pilot.set("ship_yaw", 0.0)
		return

	var forward: Vector3 = -ship.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()

	var vel: Vector3 = ship.velocity if "velocity" in ship else Vector3.ZERO
	var thrust: float = vel.dot(forward) / 30.0
	thrust = clamp(thrust, -1.0, 1.0)

	var roll: float = 0.0
	if ship.has_method("get_roll_input"):
		roll = ship.get_roll_input() * 0.5
	elif "_last_roll_input" in ship:
		roll = ship._last_roll_input * 0.5

	var yaw: float = 0.0
	if ship.has_method("get_yaw_input"):
		yaw = ship.get_yaw_input() * 0.5
	elif "_last_yaw_input" in ship:
		yaw = ship._last_yaw_input * 0.5

	_pilot.set("ship_thrust", thrust)
	_pilot.set("ship_roll", roll)
	_pilot.set("ship_yaw", yaw)
