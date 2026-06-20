extends CanvasLayer
## Top-left status panel: fuel, gems, speed, station, health, mining.

@onready var fuel_label: Label = $Root/TopLeft/Panel/Margin/VBox/FuelRow/FuelValue
@onready var fuel_bar: ProgressBar = $Root/TopLeft/Panel/Margin/VBox/FuelBar
@onready var gem_label: Label = $Root/TopLeft/Panel/Margin/VBox/GemRow/GemValue
@onready var speed_label: Label = $Root/TopLeft/Panel/Margin/VBox/SpeedRow/SpeedValue
@onready var station_label: Label = $Root/TopLeft/Panel/Margin/VBox/StationRow/StationValue
@onready var mine_label: Label = $Root/TopLeft/Panel/Margin/VBox/MineRow/MineValue
@onready var health_label: Label = $Root/TopLeft/Panel/Margin/VBox/HealthRow/HealthValue
@onready var health_bar: ProgressBar = $Root/TopLeft/Panel/Margin/VBox/HealthBar
@onready var state_label: Label = $Root/TopLeft/Panel/Margin/VBox/StateRow/StateValue
@onready var controls_label: Label = $Root/Bottom/Center/Controls
@onready var reticle: Control = $Root/Reticle
@onready var shield_label: Label = $Root/TopLeft/Panel/Margin/VBox/ShieldRow/ShieldValue

@export var reticle_attack_color: Color = Color(1.0, 0.35, 0.35)
@export var reticle_idle_color: Color = Color(0.8, 0.85, 1.0, 0.6)
@export var reticle_stranded_color: Color = Color(1.0, 0.6, 0.2)


func _process(_delta: float) -> void:
	pass


func set_fuel(fuel: float, max_fuel: float) -> void:
	fuel_label.text = "%d / %d" % [int(round(fuel)), int(round(max_fuel))]
	fuel_bar.max_value = max_fuel
	fuel_bar.value = fuel
	if fuel / max_fuel < 0.25:
		fuel_bar.modulate = Color(1.0, 0.5, 0.5)
	else:
		fuel_bar.modulate = Color(1.0, 1.0, 1.0)


func set_gems(count: int) -> void:
	# Show current/max if we have a max available (passed in as second arg
	# via set_gems(count, max)); otherwise just show count.
	if gem_label:
		gem_label.text = str(count)


func set_gem_capacity(current: int, max_capacity: int) -> void:
	if gem_label:
		gem_label.text = "%d / %d" % [current, max_capacity]
		if current >= max_capacity:
			gem_label.modulate = Color(1.0, 0.8, 0.2)
		else:
			gem_label.modulate = Color(1, 1, 1)


func set_speed(speed: float) -> void:
	speed_label.text = "%5.1f" % speed


func set_station_distance(dist: float, docked: bool) -> void:
	if docked:
		station_label.text = "DOCKED — refueling"
		station_label.modulate = Color(0.5, 1.0, 0.6)
	else:
		station_label.text = "%5.1f" % dist
		station_label.modulate = Color(1.0, 1.0, 1.0)


func set_health(health: float, max_hp: float) -> void:
	health_label.text = "%d / %d" % [int(round(health)), int(round(max_hp))]
	health_bar.max_value = max_hp
	health_bar.value = health
	var pct: float = health / max_hp
	if pct > 0.6:
		health_bar.modulate = Color(0.4, 1.0, 0.5)
	elif pct > 0.3:
		health_bar.modulate = Color(1.0, 0.9, 0.3)
	else:
		health_bar.modulate = Color(1.0, 0.4, 0.4)


func set_shield(ready: bool, cooldown: float) -> void:
	if ready:
		shield_label.text = "READY"
		shield_label.modulate = Color(0.3, 0.7, 1.0)
	elif cooldown > 0:
		shield_label.text = "%.1fs" % cooldown
		shield_label.modulate = Color(0.6, 0.6, 0.6)
	else:
		shield_label.text = "INACTIVE"
		shield_label.modulate = Color(0.4, 0.4, 0.4)


func set_state(state: int) -> void:
	# State values: 0=FLYING 1=STRANDED 2=HARPOON_FLY 3=HARPOON_REEL 4=DOCKED
	match state:
		0:
			state_label.text = "FLYING"
			state_label.modulate = Color(0.7, 1.0, 0.7)
		1:
			state_label.text = "STRANDED — F to fire harpoon"
			state_label.modulate = Color(1.0, 0.7, 0.3)
		2:
			state_label.text = "HARPOON LAUNCHED"
			state_label.modulate = Color(1.0, 0.9, 0.3)
		3:
			state_label.text = "BEING REELLED IN"
			state_label.modulate = Color(0.6, 0.9, 1.0)
		4:
			state_label.text = "DOCKED"
			state_label.modulate = Color(0.5, 1.0, 0.6)
		_:
			state_label.text = "—"


func set_mining(mining: bool, can_mine: bool) -> void:
	if mining and can_mine:
		mine_label.text = "FIRING"
		mine_label.modulate = Color(1.0, 0.4, 0.4)
		reticle.modulate = reticle_attack_color
	elif can_mine:
		mine_label.text = "READY"
		mine_label.modulate = Color(0.6, 1.0, 0.6)
		reticle.modulate = reticle_idle_color
	else:
		mine_label.text = "OUT OF RANGE"
		mine_label.modulate = Color(0.7, 0.7, 0.7)
		reticle.modulate = reticle_idle_color


func show_message(text: String, duration: float = 2.5) -> void:
	var msg: Label = $Root/Message
	msg.text = text
	msg.modulate.a = 1.0
	msg.show()
	var tween := create_tween()
	tween.tween_interval(duration)
	tween.tween_property(msg, "modulate:a", 0.0, 0.6)
	tween.tween_callback(msg.hide)
