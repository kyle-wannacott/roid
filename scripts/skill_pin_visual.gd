extends Node2D
class_name SkillPinVisual
## Draws gold "pins" around a skill node, like a DIP/QFP semiconductor package.
## Pins are drawn as filled gold rectangles extending outward from the node edges.

var pin_color: Color = Color(1.0, 0.85, 0.3, 1.0)  # Gold
var pin_outline_color: Color = Color(0.6, 0.4, 0.0, 1.0)  # Darker gold outline
var node_size: float = 64.0
var pin_length: float = 8.0
var pin_width: float = 3.0
## Which sides have pins. Valid values: "left", "right", "top", "bottom"
var pin_sides: Array = ["left", "right"]
## How many pins per side
var pins_per_side: int = 4
## Draw with darker outline (gives a more 3D look)
var draw_outline: bool = true

func _draw() -> void:
	var half_size: float = node_size * 0.5
	for side in pin_sides:
		for i in pins_per_side:
			var t: float = (float(i) + 0.5) / float(pins_per_side)
			var pin_rect: Rect2 = _pin_rect(side, t, half_size)
			if draw_outline:
				# Slightly larger dark outline behind the pin
				var outline_rect: Rect2 = pin_rect.grow(0.5)
				draw_rect(outline_rect, pin_outline_color, true)
			draw_rect(pin_rect, pin_color, true)

func _pin_rect(side: String, t: float, half_size: float) -> Rect2:
	match side:
		"left":
			# Pins extend to the LEFT of the node
			var y: float = -half_size + t * node_size - pin_width * 0.5
			return Rect2(-half_size - pin_length, y, pin_length, pin_width)
		"right":
			var y: float = -half_size + t * node_size - pin_width * 0.5
			return Rect2(half_size, y, pin_length, pin_width)
		"top":
			var x: float = -half_size + t * node_size - pin_width * 0.5
			return Rect2(x, -half_size - pin_length, pin_width, pin_length)
		"bottom":
			var x: float = -half_size + t * node_size - pin_width * 0.5
			return Rect2(x, half_size, pin_width, pin_length)
	return Rect2(0, 0, 0, 0)
