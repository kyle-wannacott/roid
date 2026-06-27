extends Node
## Manages unlocked skills and gem-based purchases for the skill tree.
## Tracks per-type gem inventory (green, blue, yellow, purple, red).
## Saved to user://player_skills.json

## When true, the skill tree editor dialog is open — ship should ignore input.
var editor_modal_open: bool = false

const SAVE_PATH := "user://player_skills.json"

var unlocked_skills: Dictionary = {}  # {skill_id: true}
var gem_inventory: Dictionary = {}    # {"green": 0, "blue": 0, "yellow": 0, "purple": 0, "red": 0}

signal skill_unlocked(skill_id: String)
signal skills_reset
## Emitted whenever the gem inventory changes.
## Passes the full inventory dictionary so listeners can display per-type counts.
signal gems_changed(inventory: Dictionary)


## Virtual property for backward compatibility.
## Returns the total number of gems across all types.
## When set, adds/removes from the "green" (common) count.
var gems: int:
	get: return get_total_gems()
	set(value):
		var diff: int = value - get_total_gems()
		if diff > 0:
			add_gems("green", diff)
		elif diff < 0:
			# Subtract from green first, then from other types if needed
			var remaining: int = -diff
			for type in GemTypeData.TYPES:
				var available: int = gem_inventory.get(type, 0)
				var take: int = mini(available, remaining)
				gem_inventory[type] -= take
				remaining -= take
				if remaining <= 0:
					break
			save_data()
			gems_changed.emit(gem_inventory)


func _ready() -> void:
	load_data()


func load_data() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		# Start with root unlocked and empty inventory
		unlocked_skills = {"root": true}
		gem_inventory = GemTypeData.empty_inventory()
		save_data()
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		unlocked_skills = {"root": true}
		gem_inventory = GemTypeData.empty_inventory()
		return
	var json := JSON.new()
	if json.parse(f.get_as_text()) == OK:
		var data: Dictionary = json.data
		unlocked_skills = data.get("unlocked", {"root": true})
		
		# Migration: old save had a single "gems" int field
		if data.has("gems") and not data.has("gem_inventory"):
			# Convert old format: all old gems become Green (common)
			var old_gems: int = data.get("gems", 0)
			gem_inventory = GemTypeData.empty_inventory()
			gem_inventory["green"] = old_gems
			save_data()  # immediately save migrated format
		else:
			gem_inventory = data.get("gem_inventory", GemTypeData.empty_inventory())
			# Ensure all keys exist (in case a new type was added)
			var empty := GemTypeData.empty_inventory()
			for key in empty:
				if not gem_inventory.has(key):
					gem_inventory[key] = 0
	else:
		unlocked_skills = {"root": true}
		gem_inventory = GemTypeData.empty_inventory()


func save_data() -> void:
	var data := {
		"unlocked": unlocked_skills,
		"gem_inventory": gem_inventory,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))


# ── Typed gem inventory helpers ───────────────────────────────────

## Get the count of a specific gem type. Returns 0 for unknown types.
func get_gem_count(type: String) -> int:
	return gem_inventory.get(type, 0)


## Get the full inventory dictionary (keys are gem type strings).
func get_all_gem_counts() -> Dictionary:
	return gem_inventory.duplicate()


## Get total number of gems across all types.
func get_total_gems() -> int:
	var total := 0
	for count in gem_inventory.values():
		total += count
	return total


## Add a number of gems of a specific type.
func add_gems(type: String, count: int) -> void:
	if count <= 0:
		return
	if not gem_inventory.has(type):
		gem_inventory[type] = 0
	gem_inventory[type] += count
	save_data()
	gems_changed.emit(gem_inventory)


## Spend gems according to a cost dictionary (e.g. {"green": 2, "blue": 1}).
## Returns true if the cost could be fully paid, false if insufficient.
func spend_gems(cost: Dictionary) -> bool:
	if not has_enough_gems(cost):
		return false
	for type in cost:
		var amount: int = cost[type]
		if amount > 0 and gem_inventory.has(type):
			gem_inventory[type] -= amount
	save_data()
	gems_changed.emit(gem_inventory)
	return true


## Check if the player has enough gems to pay a cost dictionary.
func has_enough_gems(cost: Dictionary) -> bool:
	for type in cost:
		var amount: int = cost[type]
		if amount <= 0:
			continue
		if gem_inventory.get(type, 0) < amount:
			return false
	return true


# ── Skill accessors ──────────────────────────────────────────────

func is_unlocked(skill_id: String) -> bool:
	return unlocked_skills.has(skill_id)


## Get the gem cost for a skill as a dictionary.
## If the skill has a "gem_cost" field, returns that.
## Otherwise, falls back to the old single "cost" field:
##   cost 1 → {"green": 1}, cost 2 → {"green": 2}, etc.
func get_skill_gem_cost(skill_data: Dictionary) -> Dictionary:
	if skill_data.has("gem_cost") and typeof(skill_data["gem_cost"]) == TYPE_DICTIONARY:
		var cost_dict: Dictionary = skill_data["gem_cost"].duplicate()
		for type in cost_dict:
			cost_dict[type] = int(cost_dict[type])
		return cost_dict
	# Fallback: single cost field → all Green
	var cost: int = int(skill_data.get("cost", 1))
	if cost <= 0:
		return {}
	return {"green": cost}


func can_unlock(skill_id: String, skill_data: Dictionary) -> bool:
	if unlocked_skills.has(skill_id):
		return false
	var cost: Dictionary = get_skill_gem_cost(skill_data)
	if not cost.is_empty() and not has_enough_gems(cost):
		return false
	# Check parent requirements
	var parent_id: String = str(skill_data.get("parent", ""))
	if parent_id != "" and not unlocked_skills.has(parent_id):
		return false
	# Check additional required skills
	var parent_skill_ids: String = str(skill_data.get("parent_skill_id", ""))
	if parent_skill_ids != "":
		for req_id in parent_skill_ids.split(",", false):
			req_id = req_id.strip_edges()
			if req_id != "" and not unlocked_skills.has(req_id):
				return false
	return true


func unlock_skill(skill_id: String, skill_data: Dictionary) -> bool:
	if not can_unlock(skill_id, skill_data):
		return false
	var cost: Dictionary = get_skill_gem_cost(skill_data)
	if not spend_gems(cost):
		return false
	unlocked_skills[skill_id] = true
	save_data()
	skill_unlocked.emit(skill_id)
	gems_changed.emit(gem_inventory)
	return true


func refund_skill(skill_id: String, skill_data: Dictionary) -> void:
	if not unlocked_skills.has(skill_id):
		return
	unlocked_skills.erase(skill_id)
	var cost: Dictionary = get_skill_gem_cost(skill_data)
	# Refund the gems
	for type in cost:
		var amount: int = cost[type]
		if amount > 0:
			if not gem_inventory.has(type):
				gem_inventory[type] = 0
			gem_inventory[type] += amount
	save_data()
	gems_changed.emit(gem_inventory)


func reset_all() -> void:
	unlocked_skills = {"root": true}
	gem_inventory = GemTypeData.empty_inventory()
	save_data()
	skills_reset.emit()
	gems_changed.emit(gem_inventory)


# ── Backward-compatibility shims ─────────────────────────────────

## Legacy compat: add a flat number of gems → all go to Green.
## Used by skill tree debug buttons and old code.
func add_gems_deprecated(amount: int) -> void:
	add_gems("green", amount)


## Legacy compat: set a flat gem count → fills Green.
## Used by Main.gd when syncing ship → PlayerSkills.
func set_gems(amount: int) -> void:
	gem_inventory = GemTypeData.empty_inventory()
	gem_inventory["green"] = amount
	save_data()
	gems_changed.emit(gem_inventory)


## Set the full inventory from a dictionary (e.g. when syncing from ship).
func set_gem_inventory(inventory: Dictionary) -> void:
	gem_inventory = inventory.duplicate()
	# Ensure all keys exist
	var empty := GemTypeData.empty_inventory()
	for key in empty:
		if not gem_inventory.has(key):
			gem_inventory[key] = 0
	save_data()
	gems_changed.emit(gem_inventory)
