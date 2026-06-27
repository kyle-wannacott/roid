class_name GemTypeData
## Static definitions for the 5 gem types (Crash/Spyro style).
##
## Provides type lists, display names, colors, and helper methods
## used by GemManager, PlayerSkills, skill_tree UI, and HUD.
##
## Rarity order (lowest to highest): green → blue → yellow → purple → red

const TYPES := ["green", "blue", "yellow", "purple", "red"]

const DISPLAY_NAMES := {
	"green": "Green",
	"blue": "Blue",
	"yellow": "Yellow",
	"purple": "Purple",
	"red": "Red",
}

## Hex colour strings (without #) for BBCode usage in labels.
const HEX_COLORS := {
	"green": "44DD66",
	"blue": "4488FF",
	"yellow": "FFCC22",
	"purple": "AA44FF",
	"red": "FF3344",
}

## Actual Color values for materials / MultiMesh per-instance colours.
const COLORS := {
	"green": Color("#44DD66"),
	"blue": Color("#4488FF"),
	"yellow": Color("#FFCC22"),
	"purple": Color("#AA44FF"),
	"red": Color("#FF3344"),
}

## Rarity index: 0 = common (green), 4 = legendary (red).
const RARITY_INDEX := {
	"green": 0,
	"blue": 1,
	"yellow": 2,
	"purple": 3,
	"red": 4,
}

## Maximum inventory capacity per gem type (soft cap applied by Ship).
const MAX_PER_TYPE := 999

static func get_display_name(type: String) -> String:
	return DISPLAY_NAMES.get(type, "Unknown")

static func get_color(type: String) -> Color:
	return COLORS.get(type, Color.WHITE)

static func get_hex(type: String) -> String:
	return HEX_COLORS.get(type, "FFFFFF")

static func get_rarity_index(type: String) -> int:
	return RARITY_INDEX.get(type, 0)

## Return true if `type_a` is rarer than `type_b`.
static func is_rarer(type_a: String, type_b: String) -> bool:
	return get_rarity_index(type_a) > get_rarity_index(type_b)

## Build a zeroed inventory dictionary.
static func empty_inventory() -> Dictionary:
	return {"green": 0, "blue": 0, "yellow": 0, "purple": 0, "red": 0}
