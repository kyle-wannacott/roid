class_name SkillData
extends Resource

## Skill identifier used for connections and lookups.
@export var skill_id: String = ""
## Display name shown in the skill tree UI.
@export var name: String = ""
## Icon texture path.
@export var icon: String = ""
## Description text.
@export var desc: String = ""
## Skill point cost to unlock.
@export var cost: float = 1.0
## Parent node ID in the tree (for positioning/layout).
@export var parent: String = ""
## Skill ID of the parent skill that must be unlocked first.
@export var parent_skill_id: String = ""
## Direction hint for tree layout ("left", "right", "up", "left-up", "right-up", etc.).
@export var direction: String = ""
## Dictionary of effect_id: magnitude pairs.
@export var effects: Dictionary = {}
## If true, only one child branch can be active at a time.
@export var exclusive_children: bool = false
## Hex colour for the unlocked node tint.
@export var unlock_color: String = "#ffffff"
## X position in the tree layout.
@export var x: float = 0.0
## Y position in the tree layout.
@export var y: float = 0.0
