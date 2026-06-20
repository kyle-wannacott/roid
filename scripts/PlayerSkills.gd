extends Node
## Manages unlocked skills and gem-based purchases for the skill tree.
## Saved to user://player_skills.json

## When true, the skill tree editor dialog is open — ship should ignore input.
var editor_modal_open: bool = false

const SAVE_PATH := "user://player_skills.json"

var unlocked_skills: Dictionary = {}  # {skill_id: true}
var gems: int = 0  # Current gem balance (synced with ship)

signal skill_unlocked(skill_id: String)
signal skills_reset
signal gems_changed(amount: int)

func _ready() -> void:
	load_data()

func load_data() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		# Start with root unlocked
		unlocked_skills = {"root": true}
		save_data()
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		unlocked_skills = {"root": true}
		return
	var json := JSON.new()
	if json.parse(f.get_as_text()) == OK:
		var data: Dictionary = json.data
		unlocked_skills = data.get("unlocked", {"root": true})
		gems = data.get("gems", 0)

func save_data() -> void:
	var data := {
		"unlocked": unlocked_skills,
		"gems": gems,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))

func is_unlocked(skill_id: String) -> bool:
	return unlocked_skills.has(skill_id)

func can_unlock(skill_id: String, skill_data: Dictionary) -> bool:
	if unlocked_skills.has(skill_id):
		return false
	var cost: int = int(skill_data.get("cost", 1))
	if gems < cost:
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
	var cost: int = int(skill_data.get("cost", 1))
	gems -= cost
	unlocked_skills[skill_id] = true
	save_data()
	skill_unlocked.emit(skill_id)
	gems_changed.emit(gems)
	return true

func refund_skill(skill_id: String, skill_data: Dictionary) -> void:
	if not unlocked_skills.has(skill_id):
		return
	unlocked_skills.erase(skill_id)
	var cost: int = int(skill_data.get("cost", 1))
	gems += cost
	save_data()
	gems_changed.emit(gems)

func reset_all() -> void:
	unlocked_skills = {"root": true}
	gems = 0
	save_data()
	skills_reset.emit()
	gems_changed.emit(gems)

func add_gems(amount: int) -> void:
	gems += amount
	save_data()
	gems_changed.emit(gems)

func set_gems(amount: int) -> void:
	gems = amount
	save_data()
	gems_changed.emit(gems)
