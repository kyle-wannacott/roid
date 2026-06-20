@tool
extends Control

## Skill Tree Editor for the roid project.
## Right-click any skill node to add children, edit, duplicate, move, or delete.
## All changes are saved to res://resources/skill_tree_data.json.

signal closed
signal data_changed

@onready var nodes_layer: Control = %NodesLayer
@onready var lines_layer: Control = %LinesLayer
@onready var info_panel: PanelContainer = %InfoPanel
@onready var info_name: Label = %InfoName
@onready var info_current_value: Label = %InfoCurrentValue
@onready var info_desc: Label = %InfoDesc
@onready var info_req: Label = %InfoReq
@onready var info_cost: Label = %InfoCost
@onready var unlock_button: Button = %UnlockButton
@onready var skill_points_label: Label = %SkillPointsLabel
@onready var tree_viewport: Control = %TreeViewport
@onready var tree_canvas: Control = %TreeCanvas
@onready var zoom_in_btn: Button = %ZoomInBtn
@onready var zoom_out_btn: Button = %ZoomOutBtn
@onready var zoom_reset_btn: Button = %ZoomResetBtn
@onready var zoom_level_label: Label = %ZoomLevelLabel

const NODE_SPACING: float = 120.0
const NODE_SIZE: float = 64.0
const SKILL_DATA_PATH: String = "res://resources/skill_tree_data.json"

var SKILL_TREE: Array = []

var selected_skill: Dictionary = {}
var skill_buttons: Dictionary = {}
var _context_menu: PopupMenu = null
var _context_skill_id: String = ""
var _edit_dialog: Window = null
var _icon_picker_dialog: Window = null
var _post_build_center_skill: String = ""
var _move_skill_id: String = ""
var _move_hint_label: Label = null
var _undo_stack: Array = []
var _redo_stack: Array = []
const _MAX_UNDO := 50
var _selected_skill_ids: Array[String] = []
var _multi_move_offsets: Dictionary = {}
var _last_positions: Dictionary = {}

# ── Pan / Zoom state ──────────────────────────────────────────────────────────
const ZOOM_MIN  := 0.20
const ZOOM_MAX  := 2.5
const ZOOM_STEP := 0.12
var _zoom: float       = 1.0
var _pan_offset        := Vector2.ZERO
var _dragging          := false
var _drag_start_mouse  := Vector2.ZERO
var _drag_start_pan    := Vector2.ZERO
var _sb_press_pos      := Vector2.ZERO
var _sb_btn_dragging   := false
var _was_button_drag   := false
const _DRAG_THRESHOLD  := 8.0

func _ready() -> void:
	info_panel.top_level = true
	info_panel.z_index = 200
	_load_skill_data()
	if SKILL_TREE.is_empty():
		SKILL_TREE = [
			{"id": "root", "name": "Core", "icon": "RPG_Crossed_Swords_Duel_PvP_Combat_Battle_War.png",
			 "desc": "The foundation of your power.", "effects": {}, "cost": 0, "parent": "",
			 "unlock_color": "#ffffff", "x": 500.0, "y": 200.0}
		]
		_save_skill_data()
	_normalize_skill_tree_parent_fields()
	zoom_in_btn.pressed.connect(func():
		_zoom_at_point(tree_viewport.global_position + tree_viewport.size * 0.5, ZOOM_STEP))
	zoom_out_btn.pressed.connect(func():
		_zoom_at_point(tree_viewport.global_position + tree_viewport.size * 0.5, -ZOOM_STEP))
	zoom_reset_btn.pressed.connect(_center_view)
	call_deferred("_setup_header")
	_update_gems_label()
	if PlayerSkills:
		PlayerSkills.gems_changed.connect(_on_gems_changed)
	build_tree()

func _setup_header() -> void:
	# Reposition zoom buttons to the right side
	var header := get_node_or_null("Header") as HBoxContainer
	if header == null:
		return
	# Add spacer before zoom buttons
	var spacer := Control.new()
	spacer.name = "ZoomSpacer"
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	header.move_child(spacer, header.get_children().find(zoom_out_btn))
	for zoom_button in [zoom_out_btn, zoom_in_btn, zoom_reset_btn, zoom_level_label]:
		if zoom_button != null and zoom_button.get_parent() != header:
			if zoom_button.get_parent() != null:
				zoom_button.get_parent().remove_child(zoom_button)
			header.add_child(zoom_button)
	# Add "Add Root Child" button
	var add_btn := Button.new()
	add_btn.text = "+ Add Skill"
	add_btn.tooltip_text = "Add a new child skill to the root node"
	add_btn.pressed.connect(func(): _open_edit_dialog("root", true))
	header.add_child(add_btn)
	# Add Undo/Redo buttons
	var undo_btn := Button.new()
	undo_btn.text = "↩"
	undo_btn.tooltip_text = "Undo (Ctrl+Z)"
	undo_btn.pressed.connect(_undo)
	header.add_child(undo_btn)
	var redo_btn := Button.new()
	redo_btn.text = "↪"
	redo_btn.tooltip_text = "Redo (Ctrl+Y)"
	redo_btn.pressed.connect(_redo)
	header.add_child(redo_btn)
	# Debug / convenience buttons
	var unlock_all_btn := Button.new()
	unlock_all_btn.text = "Unlock All"
	unlock_all_btn.tooltip_text = "Unlock every skill (debug)"
	unlock_all_btn.pressed.connect(_unlock_all_skills)
	header.add_child(unlock_all_btn)
	var relock_all_btn := Button.new()
	relock_all_btn.text = "Relock All"
	relock_all_btn.tooltip_text = "Relock all skills and refund gems (debug)"
	relock_all_btn.pressed.connect(_relock_all_skills)
	header.add_child(relock_all_btn)
	var add_gems_btn := Button.new()
	add_gems_btn.text = "+10 Gems"
	add_gems_btn.tooltip_text = "Add 10 gems for testing (debug)"
	add_gems_btn.pressed.connect(_add_debug_gems)
	header.add_child(add_gems_btn)
	_update_zoom_level_label()

# ── Data loading / saving ─────────────────────────────────────────────────────

func _load_skill_data() -> void:
	if not FileAccess.file_exists(SKILL_DATA_PATH):
		return
	var f := FileAccess.open(SKILL_DATA_PATH, FileAccess.READ)
	if f == null:
		return
	var json := JSON.new()
	if json.parse(f.get_as_text()) == OK:
		var loaded: Variant = json.data
		if loaded is Array:
			SKILL_TREE = loaded

func _save_skill_data() -> void:
	var dir_path := SKILL_DATA_PATH.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)
	var f := FileAccess.open(SKILL_DATA_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(SKILL_TREE, "\t"))
	data_changed.emit()

# ── Undo / Redo ───────────────────────────────────────────────────────────────

func _push_undo_state() -> void:
	_undo_stack.append(SKILL_TREE.duplicate(true))
	if _undo_stack.size() > _MAX_UNDO:
		_undo_stack.pop_front()
	_redo_stack.clear()

func _undo() -> void:
	if _undo_stack.is_empty():
		return
	_redo_stack.append(SKILL_TREE.duplicate(true))
	SKILL_TREE = _undo_stack.pop_back()
	_save_skill_data()
	build_tree()

func _redo() -> void:
	if _redo_stack.is_empty():
		return
	_undo_stack.append(SKILL_TREE.duplicate(true))
	SKILL_TREE = _redo_stack.pop_back()
	_save_skill_data()
	build_tree()

# ── Multi-select glow ─────────────────────────────────────────────────────────

func _set_skill_glow(skill_id: String, glowing: bool) -> void:
	var btn: Button = skill_buttons.get(skill_id, null)
	if btn == null:
		return
	if glowing:
		btn.modulate = Color(1.5, 1.5, 0.3, 1.0)
	else:
		btn.modulate = Color(1.0, 1.0, 1.0, 1.0)

func _clear_selection() -> void:
	for sid in _selected_skill_ids:
		_set_skill_glow(sid, false)
	_selected_skill_ids.clear()

# ── Parent ID helpers ─────────────────────────────────────────────────────────

func _parse_parent_ids(value: Variant) -> Array[String]:
	var ids: Array[String] = []
	if value is String:
		for raw_id in str(value).split(","):
			var skill_id := raw_id.strip_edges()
			if not skill_id.is_empty() and not ids.has(skill_id):
				ids.append(skill_id)
	elif value is Array:
		for raw_id in value:
			var skill_id := str(raw_id).strip_edges()
			if not skill_id.is_empty() and not ids.has(skill_id):
				ids.append(skill_id)
	return ids

func _get_primary_parent_id(skill: Dictionary) -> String:
	var parent_ids := _parse_parent_ids(skill.get("parent", ""))
	return parent_ids[0] if not parent_ids.is_empty() else ""

func _get_secondary_parent_ids(skill: Dictionary) -> Array[String]:
	var required: Array[String] = []
	var parent_ids := _parse_parent_ids(skill.get("parent", ""))
	for i in range(1, parent_ids.size()):
		var required_id := parent_ids[i]
		if not required.has(required_id):
			required.append(required_id)
	for required_id in _parse_parent_ids(skill.get("parent_skill_id", "")):
		if not required.has(required_id):
			required.append(required_id)
	return required

func _normalize_parent_fields(parent_text: Variant, required_text: Variant) -> Dictionary:
	var primary_parent := ""
	var required_ids: Array[String] = []
	var parent_ids := _parse_parent_ids(parent_text)
	if not parent_ids.is_empty():
		primary_parent = parent_ids[0]
		for i in range(1, parent_ids.size()):
			var parent_id := parent_ids[i]
			if not required_ids.has(parent_id):
				required_ids.append(parent_id)
	for required_id in _parse_parent_ids(required_text):
		if required_id == primary_parent:
			continue
		if not required_ids.has(required_id):
			required_ids.append(required_id)
	if primary_parent.is_empty() and not required_ids.is_empty():
		primary_parent = required_ids[0]
		required_ids.remove_at(0)
	return {
		"parent": primary_parent,
		"parent_skill_id": ", ".join(required_ids),
	}

func _normalize_skill_tree_parent_fields() -> void:
	for i in range(SKILL_TREE.size()):
		var normalized := _normalize_parent_fields(SKILL_TREE[i].get("parent", ""), SKILL_TREE[i].get("parent_skill_id", ""))
		SKILL_TREE[i]["parent"] = str(normalized.get("parent", ""))
		SKILL_TREE[i]["parent_skill_id"] = str(normalized.get("parent_skill_id", ""))

# ── Move helpers ──────────────────────────────────────────────────────────────

func _collect_move_branch_ids(parent_id: String) -> Array[String]:
	var ids: Array[String] = [parent_id]
	for i in SKILL_TREE.size():
		if _get_primary_parent_id(SKILL_TREE[i]) != parent_id:
			continue
		var child_id: String = str(SKILL_TREE[i].get("id", ""))
		if child_id.is_empty():
			continue
		ids.append_array(_collect_move_branch_ids(child_id))
	return ids

func _capture_move_offsets(primary_id: String, include_selected_branches: bool) -> void:
	_multi_move_offsets.clear()
	var primary_skill := _find_skill(primary_id)
	var primary_pos = _last_positions.get(primary_id, Vector2(
		float(primary_skill.get("x", 0.0)),
		float(primary_skill.get("y", 0.0))
	))
	var root_ids: Array[String] = [primary_id]
	if include_selected_branches:
		for sid in _selected_skill_ids:
			if sid != primary_id and not root_ids.has(sid):
				root_ids.append(sid)
	var seen: Dictionary = {primary_id: true}
	for root_id in root_ids:
		for branch_id in _collect_move_branch_ids(root_id):
			if seen.has(branch_id):
				continue
			seen[branch_id] = true
			_multi_move_offsets[branch_id] = _last_positions.get(branch_id, Vector2(
				float(_find_skill(branch_id).get("x", 0.0)),
				float(_find_skill(branch_id).get("y", 0.0))
			)) - primary_pos

func _start_multi_move(primary_id: String) -> void:
	_move_skill_id = primary_id
	_capture_move_offsets(primary_id, true)
	if _move_hint_label == null:
		_move_hint_label = Label.new()
		_move_hint_label.add_theme_color_override("font_color", Color(1, 1, 0))
		add_child(_move_hint_label)
	_move_hint_label.text = "Click to place %d linked skills  (Right-click to cancel)" % (1 + _multi_move_offsets.size())
	_move_hint_label.position = Vector2(8, 8)
	_move_hint_label.visible = true

# ── Keyboard shortcuts ────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	# Don't intercept shortcuts when typing in a text field
	var focus_owner := get_viewport().gui_get_focus_owner()
	if focus_owner != null and (focus_owner is LineEdit or focus_owner is TextEdit):
		return
	var ke := event as InputEventKey
	if ke.ctrl_pressed and ke.keycode == KEY_Z:
		_undo()
		get_viewport().set_input_as_handled()
	elif ke.ctrl_pressed and (ke.keycode == KEY_Y or (ke.shift_pressed and ke.keycode == KEY_Z)):
		_redo()
		get_viewport().set_input_as_handled()

# ── Tree building ─────────────────────────────────────────────────────────────

func build_tree() -> void:
	if not is_inside_tree():
		return
	for child in nodes_layer.get_children():
		child.queue_free()
	for child in lines_layer.get_children():
		child.queue_free()
	skill_buttons.clear()
	var positions: Dictionary = {}
	_layout_node("root", Vector2(500, 100), "", positions)
	_last_positions = positions.duplicate()
	for skill in SKILL_TREE:
		var skill_id: String = str(skill.get("id", ""))
		var parent_id := _get_primary_parent_id(skill)
		for required_parent_id in _get_required_skill_ids(skill):
			if required_parent_id.is_empty() or not positions.has(skill_id) or not positions.has(required_parent_id):
				continue
			var line := Line2D.new()
			line.add_point(positions[required_parent_id] + Vector2(NODE_SIZE * 0.5, NODE_SIZE * 0.5))
			line.add_point(positions[skill_id] + Vector2(NODE_SIZE * 0.5, NODE_SIZE * 0.5))
			line.width = 2.5
			line.default_color = Color(0.9, 0.9, 0.9, 0.7)
			lines_layer.add_child(line)
	for skill in SKILL_TREE:
		var skill_id: String = str(skill.get("id", ""))
		if not positions.has(skill_id):
			continue
		var btn := Button.new()
		btn.position = positions[skill_id]
		btn.size = Vector2(NODE_SIZE, NODE_SIZE)
		btn.name = skill_id
		btn.tooltip_text = str(skill.get("name", skill_id))
		var icon_path := "res://assets/skill_tree_icons/" + str(skill.get("icon", ""))
		if ResourceLoader.exists(icon_path):
			btn.icon = load(icon_path)
		btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.expand_icon = true
		btn.text = ""
		btn.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var is_skill_unlocked := PlayerSkills and PlayerSkills.is_unlocked(skill_id)
		var can_skill_unlock := PlayerSkills and PlayerSkills.can_unlock(skill_id, skill)
		
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.08, 0.08, 0.1, 0.9)
		sb.corner_radius_top_left = 4; sb.corner_radius_top_right = 4
		sb.corner_radius_bottom_left = 4; sb.corner_radius_bottom_right = 4
		for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
			sb.set_border_width(side, 2)
		
		if is_skill_unlocked:
			# Unlocked: green border
			sb.border_color = Color(0.2, 1.0, 0.2, 0.9)
			btn.modulate = Color(1.0, 1.0, 1.0)
			var hex: String = str(skill.get("unlock_color", "#44ff44"))
			btn.modulate = Color.html(hex) if hex.begins_with("#") else Color(0.2, 1.0, 0.2)
		elif can_skill_unlock:
			# Available to unlock: white border with slight glow
			sb.border_color = Color(1.0, 1.0, 1.0, 0.9)
			btn.modulate = Color(1.0, 1.0, 1.0)
		else:
			# Locked: dimmed
			sb.border_color = Color(0.4, 0.4, 0.4, 0.7)
			btn.modulate = Color(0.4, 0.4, 0.4)
		
		btn.add_theme_stylebox_override("normal", sb)
		btn.add_theme_stylebox_override("hover", sb)
		btn.add_theme_stylebox_override("pressed", sb)
		btn.pressed.connect(_on_skill_button_pressed.bind(skill_id))
		btn.gui_input.connect(_on_skill_button_gui_input.bind(skill_id))
		btn.mouse_entered.connect(_on_skill_button_hover.bind(skill_id))
		btn.mouse_exited.connect(_on_skill_button_hover_end)
		nodes_layer.add_child(btn)
		skill_buttons[skill_id] = btn
	for sid in _selected_skill_ids:
		_set_skill_glow(sid, true)
	if _post_build_center_skill != "":
		var _scs := _post_build_center_skill
		_post_build_center_skill = ""
		call_deferred("_center_on_skill", _scs)
	else:
		call_deferred("_open_default_view")

# ── Layout ────────────────────────────────────────────────────────────────────

func _layout_node(node_id: String, pos: Vector2, from_direction: String, positions: Dictionary) -> void:
	var skill_data: Dictionary = {}
	for s in SKILL_TREE:
		if s.get("id", "") == node_id:
			skill_data = s
			break
	if skill_data.has("x") and skill_data.has("y"):
		pos = Vector2(float(skill_data["x"]), float(skill_data["y"]))
	positions[node_id] = pos
	var children := SKILL_TREE.filter(func(s): return _get_primary_parent_id(s) == node_id)
	if children.is_empty():
		return
	var all_dirs := [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]
	var available_dirs: Array = []
	for d in all_dirs:
		if _vec_to_dir(d) != from_direction:
			available_dirs.append(d)
	for i in children.size():
		var child: Dictionary = children[i]
		var child_dir: String = child.get("direction", "auto")
		var dir: Vector2
		if child_dir != "auto":
			dir = _dir_to_vec(child_dir)
		else:
			dir = available_dirs[i % available_dirs.size()]
		var child_pos := pos + dir * NODE_SPACING
		if child_dir == "auto" and i >= available_dirs.size():
			child_pos += _perp(dir) * NODE_SPACING * float(i / available_dirs.size())
		_layout_node(str(child.get("id", "")), child_pos, _vec_to_dir(-dir), positions)

func _vec_to_dir(v: Vector2) -> String:
	if v.y < -0.3 and v.x >  0.3: return "right-up"
	if v.y >  0.3 and v.x >  0.3: return "right-down"
	if v.y < -0.3 and v.x < -0.3: return "left-up"
	if v.y >  0.3 and v.x < -0.3: return "left-down"
	if v.y < -0.5: return "up"
	if v.y >  0.5: return "down"
	if v.x < -0.5: return "left"
	if v.x >  0.5: return "right"
	return ""

func _dir_to_vec(d: String) -> Vector2:
	match d:
		"right":      return Vector2.RIGHT
		"left":       return Vector2.LEFT
		"down":       return Vector2.DOWN
		"up":         return Vector2.UP
		"right-down": return Vector2(1, 1)
		"right-up":   return Vector2(1, -1)
		"left-down":  return Vector2(-1, 1)
		"left-up":    return Vector2(-1, -1)
	return Vector2.RIGHT

func _perp(v: Vector2) -> Vector2:
	return Vector2(-v.y, v.x)

# ── Skill lookup ──────────────────────────────────────────────────────────────

func _find_skill(skill_id: String) -> Dictionary:
	for s in SKILL_TREE:
		if s.get("id", "") == skill_id:
			return s
	return {}


## Return true if a skill with `skill_id` exists in SKILL_TREE.
## (Excludes a given id so you can check whether a NEW id is free
## or whether an EXISTING id is valid for parenting.)
func _skill_id_exists(skill_id: String, exclude_id: String = "") -> bool:
	if skill_id.is_empty():
		return false
	for s in SKILL_TREE:
		var sid: String = str(s.get("id", ""))
		if sid == skill_id and sid != exclude_id:
			return true
	return false


## Show a small modal warning dialog.
func _show_warning(title: String, message: String) -> void:
	var win := Window.new()
	win.title = title
	win.size = Vector2i(420, 140)
	win.wrap_controls = true
	win.exclusive = true
	if PlayerSkills:
		PlayerSkills.editor_modal_open = true
	add_child(win)
	var vb := VBoxContainer.new()
	vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vb.add_theme_constant_override("separation", 8)
	vb.offset_left = 12.0; vb.offset_right = -12.0
	vb.offset_top = 8.0;   vb.offset_bottom = -8.0
	win.add_child(vb)
	var lbl := Label.new()
	lbl.text = message
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(lbl)
	var ok := Button.new()
	ok.text = "OK"
	ok.custom_minimum_size = Vector2(80, 28)
	ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(ok)
	ok.pressed.connect(func():
		if PlayerSkills: PlayerSkills.editor_modal_open = false
		win.queue_free())
	win.close_requested.connect(func():
		if PlayerSkills: PlayerSkills.editor_modal_open = false
		win.queue_free())
	win.popup_centered()

func _get_required_skill_ids(skill: Dictionary) -> Array[String]:
	var required: Array[String] = []
	var primary_parent := _get_primary_parent_id(skill)
	if not primary_parent.is_empty():
		required.append(primary_parent)
	for required_id in _get_secondary_parent_ids(skill):
		if not required.has(required_id):
			required.append(required_id)
	return required

func _depends_on_skill(skill: Dictionary, required_skill_id: String) -> bool:
	return _get_required_skill_ids(skill).has(required_skill_id)

# ── Button interactions ───────────────────────────────────────────────────────

func _on_skill_button_pressed(skill_id: String) -> void:
	if _was_button_drag:
		_was_button_drag = false
		return
	var skill: Dictionary = _find_skill(skill_id)
	if skill.is_empty():
		return
	selected_skill = skill
	# Try to unlock if it's available
	if PlayerSkills and PlayerSkills.can_unlock(skill_id, skill):
		_on_unlock_button_pressed()
		get_viewport().set_input_as_handled()

func _on_skill_button_hover(skill_id: String) -> void:
	if info_panel == null:
		return
	var skill: Dictionary = _find_skill(skill_id)
	if skill.is_empty():
		return
	selected_skill = skill
	info_name.text = str(skill.get("name", skill_id))
	info_desc.text = _format_skill_description(skill)
	info_req.text = _build_skill_requirement_text(skill)
	info_cost.text = "Cost: %d SP" % int(skill.get("cost", 1))
	info_current_value.text = ""
	info_panel.move_to_front()
	# Update unlock button state
	var is_ui_unlocked: bool = PlayerSkills and PlayerSkills.is_unlocked(skill_id)
	var can_ui_unlock: bool = PlayerSkills and PlayerSkills.can_unlock(skill_id, skill)
	if is_ui_unlocked:
		info_cost.text = "Unlocked"
		unlock_button.text = "Unlocked"
		unlock_button.disabled = true
	elif can_ui_unlock:
		info_cost.text = "Cost: %d gems" % int(skill.get("cost", 1))
		unlock_button.text = "Unlock (%d gems)" % int(skill.get("cost", 1))
		unlock_button.disabled = false
	else:
		var reason: String = _build_unlock_status_text(skill)
		info_cost.text = reason if reason != "" else "Cost: %d gems" % int(skill.get("cost", 1))
		unlock_button.text = "Locked"
		unlock_button.disabled = true
	
	info_panel.reset_size()
	var btn: Button = skill_buttons.get(skill_id, null)
	if btn:
		var vp_size := get_viewport_rect().size
		var panel_size := info_panel.get_combined_minimum_size().max(info_panel.custom_minimum_size)
		var panel_w := panel_size.x
		var panel_h := panel_size.y
		var bx := btn.global_position.x + (NODE_SIZE * _zoom - panel_w) * 0.5
		var by := btn.global_position.y - panel_h - 10.0
		if by < 0.0:
			by = btn.global_position.y + NODE_SIZE * _zoom + 10.0
		bx = clamp(bx, 0.0, vp_size.x - panel_w)
		by = clamp(by, 0.0, vp_size.y - panel_h)
		info_panel.global_position = Vector2(bx, by)
	info_panel.visible = true

func _on_skill_button_hover_end() -> void:
	if info_panel:
		info_panel.visible = false

func _format_skill_description(skill: Dictionary) -> String:
	var desc: String = str(skill.get("desc", ""))
	var effects: Dictionary = skill.get("effects", {})
	var result := desc
	var regex := RegEx.new()
	regex.compile(r"\{([^}]+)\}")
	var matches: Array = []
	var m: RegExMatch = regex.search(result)
	while m != null:
		matches.append(m)
		m = regex.search(result, m.get_end())
	for i in range(matches.size() - 1, -1, -1):
		m = matches[i] as RegExMatch
		var key := m.get_string(1)
		if effects.has(key):
			var raw = effects[key]
			var formatted: String = str(raw)
			var is_pct := false
			if m.get_end() < desc.length() and desc[m.get_end()] == '%':
				is_pct = true
			if is_pct and typeof(raw) == TYPE_FLOAT and raw < 1.0:
				formatted = str(int(round(raw * 100.0)))
			result = result.substr(0, m.get_start()) + formatted + result.substr(m.get_end())
	return result

func _build_skill_requirement_text(skill: Dictionary) -> String:
	var lines: Array[String] = []
	var required_ids := _get_required_skill_ids(skill)
	if required_ids.is_empty():
		lines.append("Requirements: none")
	else:
		var required_names: Array[String] = []
		for required_id in required_ids:
			var parent_skill := _find_skill(required_id)
			required_names.append(str(parent_skill.get("name", required_id)))
		lines.append("Requires: %s" % ", ".join(required_names))
		var parent_id := _get_primary_parent_id(skill)
		var parent_skill := _find_skill(parent_id)
		if not parent_skill.is_empty() and parent_skill.get("exclusive_children", false):
			lines.append("Choice node: this branch locks out its siblings.")
	return "\n".join(lines)

# ── Skill unlock (game mode) ────────────────────────────────────────────────────

func _build_unlock_status_text(skill: Dictionary) -> String:
	if PlayerSkills == null:
		return ""
	var cost := int(skill.get("cost", 1))
	if PlayerSkills.gems < cost:
		return "Need %d gems (have %d)" % [cost, PlayerSkills.gems]
	var required_ids := _get_required_skill_ids(skill)
	for required_id in required_ids:
		if not PlayerSkills.is_unlocked(required_id):
			var parent_skill := _find_skill(required_id)
			return "Unlock %s first" % parent_skill.get("name", required_id)
	return ""

func _on_unlock_button_pressed() -> void:
	if selected_skill.is_empty():
		return
	var skill_id: String = str(selected_skill.get("id", ""))
	if PlayerSkills == null or not PlayerSkills.can_unlock(skill_id, selected_skill):
		return
	if PlayerSkills.unlock_skill(skill_id, selected_skill):
		_update_gems_label()
		build_tree()

func _update_gems_label() -> void:
	if skill_points_label and PlayerSkills:
		skill_points_label.text = "Gems: %d" % PlayerSkills.gems

func _on_gems_changed(_amount: int) -> void:
	_update_gems_label()
	build_tree()

# ── Debug: unlock all / relock all / add gems ─────────────────────────────────

func _unlock_all_skills() -> void:
	if not PlayerSkills:
		return
	for s in SKILL_TREE:
		var sid: String = str(s.get("id", ""))
		if sid != "root" and not PlayerSkills.unlocked_skills.has(sid):
			PlayerSkills.unlocked_skills[sid] = true
	PlayerSkills.save_data()
	_update_gems_label()
	build_tree()

func _relock_all_skills() -> void:
	if not PlayerSkills:
		return
	var to_refund: Array[String] = []
	for sid in PlayerSkills.unlocked_skills.keys():
		if sid != "root":
			to_refund.append(sid)
	for sid in to_refund:
		var skill_data := _find_skill(sid)
		if not skill_data.is_empty():
			PlayerSkills.gems += int(skill_data.get("cost", 1))
		PlayerSkills.unlocked_skills.erase(sid)
	PlayerSkills.save_data()
	if PlayerSkills.has_signal("skills_reset"):
		PlayerSkills.skills_reset.emit()
	_update_gems_label()
	build_tree()

func _add_debug_gems() -> void:
	if PlayerSkills:
		PlayerSkills.add_gems(10)
		_update_gems_label()

# ── Pan / Zoom ─────────────────────────────────────────────────────────────────

func _apply_canvas_transform() -> void:
	if tree_canvas == null:
		return
	tree_canvas.position = _pan_offset
	tree_canvas.scale = Vector2(_zoom, _zoom)
	_update_zoom_level_label()

func _update_zoom_level_label() -> void:
	if zoom_level_label == null:
		return
	zoom_level_label.text = "%d%%" % maxi(int(round(_zoom * 100.0)), 20)

func _zoom_at_point(screen_pos: Vector2, delta: float) -> void:
	if tree_viewport == null:
		return
	var old_zoom := _zoom
	_zoom = clampf(_zoom + delta, ZOOM_MIN, ZOOM_MAX)
	if absf(_zoom - old_zoom) < 0.0001:
		return
	var origin := tree_viewport.get_global_rect().position
	var canvas_pt := (screen_pos - origin - _pan_offset) / old_zoom
	_pan_offset = screen_pos - origin - canvas_pt * _zoom
	_apply_canvas_transform()

func _center_view() -> void:
	if tree_canvas == null or tree_viewport == null or skill_buttons.is_empty():
		return
	var min_pos := Vector2(INF, INF)
	var max_pos := Vector2(-INF, -INF)
	for btn in skill_buttons.values():
		min_pos = min_pos.min(btn.position)
		max_pos = max_pos.max(btn.position + Vector2(NODE_SIZE, NODE_SIZE))
	var content_center := (min_pos + max_pos) * 0.5
	var content_size := (max_pos - min_pos).max(Vector2.ONE)
	var focus_center := content_center
	var root_button := skill_buttons.get("root", null) as Control
	if root_button != null:
		focus_center = root_button.position + Vector2(NODE_SIZE * 0.5, NODE_SIZE * 0.5)
	var vp_center := tree_viewport.size * 0.5
	var fit_zoom_x := (tree_viewport.size.x - 96.0) / content_size.x
	var fit_zoom_y := (tree_viewport.size.y - 96.0) / content_size.y
	var fit_zoom := minf(fit_zoom_x, fit_zoom_y)
	_zoom = clampf(minf(fit_zoom, 0.94), ZOOM_MIN, ZOOM_MAX)
	_pan_offset = vp_center - focus_center * _zoom
	_apply_canvas_transform()

func _open_default_view() -> void:
	if tree_canvas == null or tree_viewport == null or skill_buttons.is_empty():
		return
	_center_view()
	var root_button := skill_buttons.get("root", null) as Control
	if root_button == null:
		return
	_zoom = 0.5
	var root_center := root_button.position + Vector2(NODE_SIZE * 0.5, NODE_SIZE * 0.5)
	_pan_offset = tree_viewport.size * 0.5 - root_center * _zoom
	_apply_canvas_transform()

func _center_on_skill(skill_id: String) -> void:
	if tree_canvas == null or tree_viewport == null:
		return
	var btn: Button = skill_buttons.get(skill_id, null)
	if btn == null:
		return
	var btn_center := btn.position + Vector2(NODE_SIZE * 0.5, NODE_SIZE * 0.5)
	var vp_center := tree_viewport.size * 0.5
	_pan_offset = vp_center - btn_center * _zoom
	_apply_canvas_transform()

func _is_over_skill_button(screen_pos: Vector2) -> bool:
	for btn in skill_buttons.values():
		if btn is Control and btn.is_visible_in_tree() and btn.get_global_rect().has_point(screen_pos):
			return true
	return false

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or tree_viewport == null:
		return
	var vp_rect := tree_viewport.get_global_rect()
	if event is InputEventMouseButton:
		var mbe := event as InputEventMouseButton
		var in_vp := vp_rect.has_point(mbe.global_position)
		# Move-skill mode: left click places the skill, right click cancels
		if _move_skill_id != "" and mbe.pressed and in_vp:
			if mbe.button_index == MOUSE_BUTTON_LEFT:
				var origin := tree_viewport.global_position
				var canvas_pos := (mbe.global_position - origin - _pan_offset) / _zoom
				_push_undo_state()
				var new_x := snappedf(canvas_pos.x, 1.0)
				var new_y := snappedf(canvas_pos.y, 1.0)
				for i in SKILL_TREE.size():
					if SKILL_TREE[i].get("id", "") == _move_skill_id:
						SKILL_TREE[i]["x"] = new_x
						SKILL_TREE[i]["y"] = new_y
						break
				for sid in _multi_move_offsets:
					var off: Vector2 = _multi_move_offsets[sid]
					for i in SKILL_TREE.size():
						if SKILL_TREE[i].get("id", "") == sid:
							SKILL_TREE[i]["x"] = new_x + off.x
							SKILL_TREE[i]["y"] = new_y + off.y
							break
				_multi_move_offsets.clear()
				_save_skill_data()
				_move_skill_id = ""
				if _move_hint_label:
					_move_hint_label.visible = false
				call_deferred("build_tree")
				get_viewport().set_input_as_handled()
				return
			elif mbe.button_index == MOUSE_BUTTON_RIGHT:
				_move_skill_id = ""
				_multi_move_offsets.clear()
				if _move_hint_label:
					_move_hint_label.visible = false
				get_viewport().set_input_as_handled()
				return
		if mbe.button_index == MOUSE_BUTTON_LEFT:
			if mbe.pressed and in_vp and not _is_over_skill_button(mbe.global_position):
				_dragging = true
				_drag_start_mouse = mbe.global_position
				_drag_start_pan = _pan_offset
				get_viewport().set_input_as_handled()
			elif not mbe.pressed:
				_dragging = false
		elif in_vp and mbe.pressed:
			if mbe.button_index == MOUSE_BUTTON_WHEEL_UP:
				_zoom_at_point(mbe.global_position, ZOOM_STEP)
				get_viewport().set_input_as_handled()
			elif mbe.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_at_point(mbe.global_position, -ZOOM_STEP)
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _dragging:
		_pan_offset = _drag_start_pan + (event.global_position - _drag_start_mouse)
		_apply_canvas_transform()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and visible:
		if _move_skill_id != "" and event.keycode == KEY_ESCAPE:
			_move_skill_id = ""
			if _move_hint_label:
				_move_hint_label.visible = false

# ── Right-click context menu ──────────────────────────────────────────────────

func _on_skill_button_gui_input(event: InputEvent, skill_id: String) -> void:
	if not is_visible_in_tree():
		return
	# Mouse motion while held → pan
	if event is InputEventMouseMotion:
		if _sb_press_pos != Vector2.ZERO:
			var delta = event.global_position - _sb_press_pos
			if not _sb_btn_dragging and delta.length() > _DRAG_THRESHOLD:
				_sb_btn_dragging = true
				_drag_start_mouse = _sb_press_pos
				_drag_start_pan = _pan_offset
			if _sb_btn_dragging:
				_pan_offset = _drag_start_pan + (event.global_position - _drag_start_mouse)
				_apply_canvas_transform()
				get_viewport().set_input_as_handled()
		return
	if not (event is InputEventMouseButton):
		return
	var mbe := event as InputEventMouseButton
	# Ctrl+click to add/remove from multi-selection
	if mbe.button_index == MOUSE_BUTTON_LEFT and mbe.pressed and mbe.ctrl_pressed:
		if _selected_skill_ids.has(skill_id):
			_selected_skill_ids.erase(skill_id)
			_set_skill_glow(skill_id, false)
		else:
			_selected_skill_ids.append(skill_id)
			_set_skill_glow(skill_id, true)
		get_viewport().set_input_as_handled()
		return
	# Left button: track press for drag detection
	if mbe.button_index == MOUSE_BUTTON_LEFT:
		if mbe.pressed:
			_sb_press_pos = mbe.global_position
			_sb_btn_dragging = false
		else:
			var was_drag := _sb_btn_dragging
			_sb_press_pos = Vector2.ZERO
			_sb_btn_dragging = false
			if was_drag:
				_was_button_drag = true
				get_viewport().set_input_as_handled()
		return
	if mbe.button_index != MOUSE_BUTTON_RIGHT or not mbe.pressed:
		return
	_context_skill_id = skill_id
	_show_context_menu(skill_id)
	get_viewport().set_input_as_handled()

func _show_context_menu(skill_id: String) -> void:
	if _context_menu == null:
		_context_menu = PopupMenu.new()
		_context_menu.id_pressed.connect(_on_context_menu_id_pressed)
		add_child(_context_menu)
	_context_menu.clear()
	_context_menu.add_item("Edit Skill", 0)
	_context_menu.add_item("Add Child Skill", 1)
	_context_menu.add_item("Duplicate", 6)
	_context_menu.add_separator()
	_context_menu.add_item("Move Skill", 4)
	if _selected_skill_ids.size() > 1 and _selected_skill_ids.has(skill_id):
		_context_menu.add_item("Move Selected (%d)" % _selected_skill_ids.size(), 5)
	if skill_id != "root":
		_context_menu.add_separator()
		_context_menu.add_item("Delete Skill", 2)
	var btn_global := Vector2i(0, 0)
	if skill_buttons.has(skill_id):
		btn_global = Vector2i(skill_buttons[skill_id].global_position) + Vector2i(0, int(NODE_SIZE))
	_context_menu.popup(Rect2i(btn_global, Vector2i(0, 0)))

func _on_context_menu_id_pressed(id: int) -> void:
	match id:
		0: _open_edit_dialog(_context_skill_id, false)
		1: _open_edit_dialog(_context_skill_id, true)
		2: _delete_skill(_context_skill_id)
		4: _start_move_skill(_context_skill_id)
		5: _start_multi_move(_context_skill_id)
		6: _duplicate_skill(_context_skill_id)

func _start_move_skill(skill_id: String) -> void:
	_move_skill_id = skill_id
	_capture_move_offsets(skill_id, false)
	if _move_hint_label == null:
		_move_hint_label = Label.new()
		_move_hint_label.add_theme_color_override("font_color", Color(1, 1, 0))
		_move_hint_label.add_theme_font_size_override("font_size", 14)
		_move_hint_label.z_index = 100
		add_child(_move_hint_label)
	var sk := _find_skill(skill_id)
	_move_hint_label.text = "Click to place: %s  (Right-click to cancel)" % sk.get("name", skill_id)
	_move_hint_label.position = Vector2(8, 8)
	_move_hint_label.visible = true

# ── Delete / Duplicate ────────────────────────────────────────────────────────

func _delete_skill(skill_id: String) -> void:
	if skill_id == "root":
		return
	_push_undo_state()
	for i in SKILL_TREE.size():
		if SKILL_TREE[i].get("id", "") == skill_id:
			SKILL_TREE.remove_at(i)
			break
	# Recursively remove orphaned children
	var orphans: Array = []
	for s in SKILL_TREE:
		if _depends_on_skill(s, skill_id):
			orphans.append(s.get("id", ""))
	for oid in orphans:
		_delete_skill(oid)
	_save_skill_data()
	if _context_skill_id != "" and _context_skill_id != skill_id:
		_post_build_center_skill = _context_skill_id
	call_deferred("build_tree")

func _duplicate_skill(skill_id: String) -> void:
	if skill_id.is_empty() or skill_id == "root":
		return
	var source := _find_skill(skill_id)
	if source.is_empty():
		return
	var duplicate_skill := source.duplicate(true)
	var next_rank := _get_skill_rank_index(source) + 1
	var new_id := _build_ranked_skill_id(str(source.get("id", skill_id)), next_rank)
	while not _find_skill(new_id).is_empty():
		next_rank += 1
		new_id = _build_ranked_skill_id(str(source.get("id", skill_id)), next_rank)
	duplicate_skill["id"] = new_id
	duplicate_skill["name"] = _build_ranked_skill_name(str(source.get("name", skill_id)), next_rank)
	duplicate_skill["parent"] = skill_id
	duplicate_skill.erase("x")
	duplicate_skill.erase("y")
	_push_undo_state()
	SKILL_TREE.append(duplicate_skill)
	_save_skill_data()
	_post_build_center_skill = new_id
	call_deferred("build_tree")

func _get_skill_rank_index(skill_data: Dictionary) -> int:
	var skill_id := str(skill_data.get("id", ""))
	var parts := skill_id.split("_")
	if not parts.is_empty():
		var suffix := parts[parts.size() - 1]
		if suffix.is_valid_int():
			return maxi(int(suffix), 1)
	var skill_name := str(skill_data.get("name", ""))
	var name_parts := skill_name.split(" ", false)
	if not name_parts.is_empty():
		var token := String(name_parts[name_parts.size() - 1]).to_upper()
		if _is_roman_numeral(token):
			return maxi(_roman_to_int(token), 1)
	return 1

func _build_ranked_skill_id(skill_id: String, rank: int) -> String:
	var parts := skill_id.split("_")
	if not parts.is_empty() and parts[parts.size() - 1].is_valid_int():
		parts.remove_at(parts.size() - 1)
	var base_id := "_".join(parts)
	if base_id.is_empty():
		base_id = skill_id
	return "%s_%d" % [base_id, maxi(rank, 1)]

func _build_ranked_skill_name(skill_name: String, rank: int) -> String:
	var parts := skill_name.split(" ", false)
	if not parts.is_empty() and _is_roman_numeral(String(parts[parts.size() - 1]).to_upper()):
		parts.remove_at(parts.size() - 1)
	var base_name := " ".join(parts)
	if base_name.is_empty():
		base_name = skill_name
	return "%s %s" % [base_name, _int_to_roman(maxi(rank, 1))]

func _is_roman_numeral(token: String) -> bool:
	if token.is_empty():
		return false
	for ch in token:
		if ch not in ["I", "V", "X", "L", "C", "D", "M"]:
			return false
	return true

func _roman_to_int(token: String) -> int:
	var values := {"I": 1, "V": 5, "X": 10, "L": 50, "C": 100, "D": 500, "M": 1000}
	var total := 0
	var previous := 0
	for i in range(token.length() - 1, -1, -1):
		var value := int(values.get(token.substr(i, 1), 0))
		if value < previous:
			total -= value
		else:
			total += value
			previous = value
	return total

func _int_to_roman(value: int) -> String:
	var numerals := [
		{"value": 1000, "token": "M"},
		{"value": 900, "token": "CM"},
		{"value": 500, "token": "D"},
		{"value": 400, "token": "CD"},
		{"value": 100, "token": "C"},
		{"value": 90, "token": "XC"},
		{"value": 50, "token": "L"},
		{"value": 40, "token": "XL"},
		{"value": 10, "token": "X"},
		{"value": 9, "token": "IX"},
		{"value": 5, "token": "V"},
		{"value": 4, "token": "IV"},
		{"value": 1, "token": "I"},
	]
	var remaining := maxi(value, 1)
	var result := ""
	for entry in numerals:
		var numeral_value := int(entry["value"])
		var numeral_token := str(entry["token"])
		while remaining >= numeral_value:
			result += numeral_token
			remaining -= numeral_value
	return result

# ── Edit / Add Skill Dialog ───────────────────────────────────────────────────

func _open_edit_dialog(context_skill_id: String, is_new: bool) -> void:
	if _icon_picker_dialog != null and is_instance_valid(_icon_picker_dialog):
		_icon_picker_dialog.free()
		_icon_picker_dialog = null
	if _edit_dialog != null and is_instance_valid(_edit_dialog):
		_edit_dialog.free()
		_edit_dialog = null
	var skill_data: Dictionary = {}
	if is_new:
		skill_data = {
			"id": "skill_%d" % randi_range(1000, 9999),
			"name": "New Skill",
			"icon": "RPG_Crossed_Swords_Duel_PvP_Combat_Battle_War.png",
			"desc": "Skill description.",
			"effects": {},
			"cost": 1,
			"parent": context_skill_id
		}
	else:
		for s in SKILL_TREE:
			if s.get("id", "") == context_skill_id:
				skill_data = s.duplicate(true)
				break
	if skill_data.is_empty():
		return
	_build_edit_dialog(skill_data, is_new)

func _build_edit_dialog(skill_data: Dictionary, is_new: bool) -> void:
	var win := Window.new()
	win.title = "Add Skill" if is_new else "Edit: " + str(skill_data.get("name", ""))
	win.size = Vector2i(500, 610)
	win.wrap_controls = true
	win.exclusive = true
	_edit_dialog = win
	add_child(win)

	var vb := VBoxContainer.new()
	vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vb.add_theme_constant_override("separation", 6)
	vb.offset_left = 12.0; vb.offset_right = -12.0
	vb.offset_top = 8.0;   vb.offset_bottom = -8.0
	win.add_child(vb)

	var make_row := func(lbl_text: String) -> HBoxContainer:
		var row := HBoxContainer.new()
		var lbl := Label.new()
		lbl.text = lbl_text
		lbl.custom_minimum_size = Vector2(150, 0)
		row.add_child(lbl)
		return row

	var id_row: HBoxContainer = make_row.call("Skill ID:")
	var id_edit = LineEdit.new(); id_edit.text = str(skill_data.get("id", ""))
	id_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL; id_row.add_child(id_edit); vb.add_child(id_row)

	var name_row: HBoxContainer = make_row.call("Name:")
	var name_edit := LineEdit.new(); name_edit.text = str(skill_data.get("name", ""))
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL; name_row.add_child(name_edit); vb.add_child(name_row)

	var icon_row: HBoxContainer = make_row.call("Icon filename:")
	var icon_edit := LineEdit.new(); icon_edit.text = str(skill_data.get("icon", ""))
	icon_edit.placeholder_text = "e.g. RPG_Crossed_Swords.png"
	icon_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL; icon_row.add_child(icon_edit)
	var browse_btn := Button.new(); browse_btn.text = "Browse…"
	browse_btn.pressed.connect(func(): _open_icon_picker(icon_edit))
	icon_row.add_child(browse_btn)
	vb.add_child(icon_row)

	var cost_row: HBoxContainer = make_row.call("Skill Point Cost:")
	var cost_spin := SpinBox.new(); cost_spin.min_value = 0; cost_spin.max_value = 20
	cost_spin.value = int(skill_data.get("cost", 1))
	cost_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL; cost_row.add_child(cost_spin); vb.add_child(cost_row)

	var parent_row: HBoxContainer = make_row.call("Parent Skill ID:")
	var parent_edit := LineEdit.new(); parent_edit.text = str(skill_data.get("parent", ""))
	parent_edit.placeholder_text = "Primary parent; comma-separated is also supported"
	parent_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL; parent_row.add_child(parent_edit); vb.add_child(parent_row)

	var req_row: HBoxContainer = make_row.call("Required Parent Skill IDs:")
	var req_edit := LineEdit.new(); req_edit.text = str(skill_data.get("parent_skill_id", ""))
	req_edit.placeholder_text = "Comma-separated, e.g. strength_2, dodge_chance"
	req_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL; req_row.add_child(req_edit); vb.add_child(req_row)

	var dir_row: HBoxContainer = make_row.call("Direction from parent:")
	var dir_opt := OptionButton.new()
	dir_opt.add_item("auto", 0); dir_opt.add_item("right", 1); dir_opt.add_item("left", 2)
	dir_opt.add_item("down", 3); dir_opt.add_item("up", 4)
	dir_opt.add_item("right-down", 5); dir_opt.add_item("right-up", 6)
	dir_opt.add_item("left-down", 7); dir_opt.add_item("left-up", 8)
	var _dir_map := {"auto": 0, "right": 1, "left": 2, "down": 3, "up": 4, "right-down": 5, "right-up": 6, "left-down": 7, "left-up": 8}
	dir_opt.selected = _dir_map.get(str(skill_data.get("direction", "auto")), 0)
	dir_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL; dir_row.add_child(dir_opt); vb.add_child(dir_row)

	var dl := Label.new(); dl.text = "Description:"; vb.add_child(dl)
	var desc_edit := TextEdit.new(); desc_edit.text = str(skill_data.get("desc", ""))
	desc_edit.custom_minimum_size = Vector2(0, 60); vb.add_child(desc_edit)

	var fl := Label.new(); fl.text = 'Effects JSON  e.g. {"max_health": 20}'; vb.add_child(fl)
	var fx_edit := TextEdit.new(); fx_edit.text = JSON.stringify(skill_data.get("effects", {}))
	fx_edit.custom_minimum_size = Vector2(0, 60); vb.add_child(fx_edit)

	var excl_row: HBoxContainer = make_row.call("Exclusive Children:")
	var excl_check := CheckButton.new()
	excl_check.button_pressed = bool(skill_data.get("exclusive_children", false))
	excl_check.tooltip_text = "Children of this skill are mutually exclusive — only one may be unlocked"
	excl_row.add_child(excl_check)
	vb.add_child(excl_row)

	var color_row: HBoxContainer = make_row.call("Unlock Color:")
	var color_btn := ColorPickerButton.new()
	var _hex: String = str(skill_data.get("unlock_color", "#aaaaaa"))
	color_btn.color = Color.html(_hex) if _hex.begins_with("#") else Color(0.67, 0.67, 0.67)
	color_btn.custom_minimum_size = Vector2(80, 0)
	color_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	color_row.add_child(color_btn)
	vb.add_child(color_row)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	var save_btn := Button.new(); save_btn.text = "Save"
	save_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cancel_btn := Button.new(); cancel_btn.text = "Cancel"
	cancel_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_row.add_child(save_btn); btn_row.add_child(cancel_btn); vb.add_child(btn_row)

	var orig_id: String = str(skill_data.get("id", ""))

	save_btn.pressed.connect(func():
		var new_id     = id_edit.text.strip_edges()
		var new_name   = name_edit.text.strip_edges()
		var new_icon   = icon_edit.text.strip_edges()
		var new_cost   := int(cost_spin.value)
		var new_parent = parent_edit.text.strip_edges()
		var new_required_parents := req_edit.text.strip_edges()
		var normalized_parents := _normalize_parent_fields(new_parent, new_required_parents)

		# Validate parent exists. If the user typed a parent id that
		# doesn't exist in the tree, re-parent to "root" and warn.
		var primary_parent: String = str(normalized_parents.get("parent", ""))
		if primary_parent != "" and not _skill_id_exists(primary_parent, orig_id):
			_show_warning(
				"Invalid Parent",
				"Parent skill \"%s\" does not exist. Re-parenting \"%s\" to root (Command Module)." % [primary_parent, new_id]
			)
			normalized_parents["parent"] = "root"
			primary_parent = "root"

		# Validate each required-parent id also exists
		var req_ids: Array[String] = _parse_parent_ids(str(normalized_parents.get("parent_skill_id", "")))
		var bad_required: Array[String] = []
		for rid in req_ids:
			if not _skill_id_exists(rid, orig_id):
				bad_required.append(rid)
		if not bad_required.is_empty():
			_show_warning(
				"Invalid Required Parent",
				"Required parent skill(s) %s do not exist. Removing them from \"%s\"." % [str(bad_required), new_id]
			)
			normalized_parents["parent_skill_id"] = ""
		var new_desc   = desc_edit.text.strip_edges()
		var new_fx: Dictionary = {}
		var json := JSON.new()
		if json.parse(fx_edit.text) == OK and json.data is Dictionary:
			new_fx = json.data
		var color_hex := "#" + color_btn.color.to_html(false)
		var new_data := {"id": new_id, "name": new_name, "icon": new_icon,
			"cost": new_cost, "parent": normalized_parents.get("parent", ""), "desc": new_desc, "effects": new_fx,
			"parent_skill_id": normalized_parents.get("parent_skill_id", ""),
			"direction": (["auto", "right", "left", "down", "up", "right-down", "right-up", "left-down", "left-up"])[dir_opt.selected],
			"exclusive_children": excl_check.button_pressed,
			"unlock_color": color_hex}
		_push_undo_state()
		if is_new:
			SKILL_TREE.append(new_data)
		else:
			for i in SKILL_TREE.size():
				if SKILL_TREE[i].get("id", "") == orig_id:
					if SKILL_TREE[i].has("x"):
						new_data["x"] = SKILL_TREE[i]["x"]
					if SKILL_TREE[i].has("y"):
						new_data["y"] = SKILL_TREE[i]["y"]
					SKILL_TREE[i] = new_data
					break
			if new_id != orig_id:
				for s in SKILL_TREE:
					var normalized_child := _normalize_parent_fields(s.get("parent", ""), s.get("parent_skill_id", ""))
					var child_parent := str(normalized_child.get("parent", ""))
					if child_parent == orig_id:
						child_parent = new_id
					var updated_required: Array[String] = []
					for required_id in _parse_parent_ids(normalized_child.get("parent_skill_id", "")):
						if required_id == orig_id:
							required_id = new_id
						if not required_id.is_empty():
							updated_required.append(required_id)
					s["parent"] = child_parent
					s["parent_skill_id"] = ", ".join(updated_required)
		_save_skill_data()
		win.queue_free(); _edit_dialog = null
		_post_build_center_skill = new_id
		call_deferred("build_tree"))

	cancel_btn.pressed.connect(func(): win.queue_free(); _edit_dialog = null)
	win.close_requested.connect(func(): win.queue_free(); _edit_dialog = null)
	win.popup_centered()

# ── Icon picker ───────────────────────────────────────────────────────────────

func _open_icon_picker(target_edit: LineEdit) -> void:
	if _icon_picker_dialog != null and is_instance_valid(_icon_picker_dialog):
		_icon_picker_dialog.free()
		_icon_picker_dialog = null
	var picker := Window.new()
	picker.title = "Select Icon"
	picker.size = Vector2i(560, 540)
	picker.wrap_controls = true
	picker.exclusive = true
	_icon_picker_dialog = picker
	if _edit_dialog != null and is_instance_valid(_edit_dialog):
		_edit_dialog.add_child(picker)
	else:
		add_child(picker)

	var root := VBoxContainer.new()
	root.anchor_right = 1.0
	root.anchor_bottom = 1.0
	root.offset_left = 8.0; root.offset_right = -8.0
	root.offset_top = 6.0;  root.offset_bottom = -6.0
	root.add_theme_constant_override("separation", 4)
	picker.add_child(root)

	var search := LineEdit.new()
	search.placeholder_text = "Filter icons… (icons shown for first 50 matches)"
	root.add_child(search)

	var hbox := HBoxContainer.new()
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 6)
	root.add_child(hbox)

	var list := ItemList.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.max_columns = 1
	list.fixed_icon_size = Vector2i(28, 28)
	hbox.add_child(list)

	var preview_box := VBoxContainer.new()
	preview_box.custom_minimum_size = Vector2(100, 0)
	hbox.add_child(preview_box)

	var preview_rect := TextureRect.new()
	preview_rect.custom_minimum_size = Vector2(96, 96)
	preview_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	preview_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview_box.add_child(preview_rect)

	var preview_label := Label.new()
	preview_label.text = ""
	preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview_label.add_theme_font_size_override("font_size", 9)
	preview_box.add_child(preview_label)

	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(func():
		if _icon_picker_dialog == picker:
			_icon_picker_dialog = null
		picker.queue_free())
	root.add_child(cancel)

	var all_icons: Array[String] = []
	var dir := DirAccess.open("res://assets/skill_tree_icons")
	if dir:
		dir.list_dir_begin()
		var fname := dir.get_next()
		while fname != "":
			if fname.ends_with(".png") and not fname.ends_with(".png.import"):
				all_icons.append(fname)
			fname = dir.get_next()
		dir.list_dir_end()
	all_icons.sort()

	var icon_cache: Dictionary = {}
	var get_icon := func(icon_name: String) -> Texture2D:
		if icon_cache.has(icon_name):
			return icon_cache[icon_name]
		var ipath := "res://assets/skill_tree_icons/" + icon_name
		if ResourceLoader.exists(ipath):
			var tex := load(ipath) as Texture2D
			icon_cache[icon_name] = tex
			return tex
		return null

	var populate := func(filter: String) -> void:
		list.clear()
		var shown := 0
		for icon_name: String in all_icons:
			if filter.is_empty() or icon_name.to_lower().contains(filter.to_lower()):
				var idx := list.add_item(icon_name)
				if not filter.is_empty() and shown < 50:
					var tex := get_icon.call(icon_name) as Texture2D
					if tex != null:
						list.set_item_icon(idx, tex)
				shown += 1

	populate.call("")
	search.text_changed.connect(func(t: String): populate.call(t))

	list.item_selected.connect(func(idx: int):
		var icon_name: String = list.get_item_text(idx)
		var tex := get_icon.call(icon_name) as Texture2D
		preview_rect.texture = tex
		preview_label.text = icon_name)

	list.item_activated.connect(func(idx: int):
		if PlayerSkills: PlayerSkills.editor_modal_open = false
		target_edit.text = list.get_item_text(idx)
		if _icon_picker_dialog == picker:
			_icon_picker_dialog = null
		picker.queue_free())

	picker.close_requested.connect(func():
		if PlayerSkills: PlayerSkills.editor_modal_open = false
		if _icon_picker_dialog == picker:
			_icon_picker_dialog = null
		picker.queue_free())
	picker.popup_centered()
