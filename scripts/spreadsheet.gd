class_name Spreadsheet
extends Control

## Data source configuration. Keys are used as OptionButton item identifiers.
const DATA_SOURCES := {
	"skill_tree": {
		"title": "Skill Tree Data",
		"entries_as_rows": true,
	},
}

## Properties to skip in the grid.
const SKIP_PROPERTIES := {
	script = true,
	resource_path = true,
	resource_name = true,
	resource_local_to_scene = true,
	resource_scene_unique_id = true,
}

## Ordered display names for property columns.
const PROPERTY_DISPLAY_NAMES := {
	"skill_id": "ID",
	"name": "Name",
	"icon": "Icon",
	"desc": "Description",
	"cost": "Cost",
	"parent": "Parent",
	"parent_skill_id": "Required",
	"direction": "Direction",
	"effects": "Effects",
	"exclusive_children": "Exclusive",
	"unlock_color": "Color",
	"x": "X",
	"y": "Y",
}

## Property order for columns.
const PROPERTY_ORDER := [
	"skill_id", "name", "icon", "desc", "cost", "parent", "parent_skill_id",
	"direction", "effects", "exclusive_children", "unlock_color", "x", "y",
]

## If cell text exceeds this many characters, expand the cell on focus.
const CELL_EXPAND_CHAR_LIMIT := 30

var _collection: Resource = null
var _stat_keys: PackedStringArray = []
var _value_types: Dictionary = {}
var _cells: Dictionary = {}
var _needs_save := false
var _current_source := "skill_tree"

@onready var _source_option: OptionButton = %SourceOption
@onready var _title_label: Label = %Title
@onready var _save_button: Button = %SaveButton
@onready var _status_label: Label = %StatusLabel
@onready var _top_hbox: HBoxContainer = %TopHBox
@onready var _top_scroll: ScrollContainer = %TopScroll
@onready var _data_grid: GridContainer = %DataGrid
@onready var _data_scroll: ScrollContainer = %DataScroll

func _ready() -> void:
	_populate_source_option()
	_source_option.item_selected.connect(_on_source_selected)
	_load_data()
	_build_grid()
	_save_button.pressed.connect(_on_save)
	_data_scroll.get_h_scroll_bar().value_changed.connect(_sync_top_scroll)

func _populate_source_option() -> void:
	_source_option.clear()
	var keys: PackedStringArray = DATA_SOURCES.keys()
	for key in keys:
		var info: Dictionary = DATA_SOURCES[key]
		_source_option.add_item(info.get("title", key), _source_option.item_count)
	_source_option.selected = 0
	_current_source = keys[0]

func _on_source_selected(index: int) -> void:
	var keys: PackedStringArray = DATA_SOURCES.keys()
	if index >= keys.size():
		return
	_current_source = keys[index]
	_load_data()
	_build_grid()

func _sync_top_scroll(v: float) -> void:
	_top_scroll.scroll_horizontal = int(v)

func _load_data() -> void:
	# Build SkillDataCollection from the JSON file
	var col := SkillDataCollection.new()
	var json_path := "res://resources/skill_tree_data.json"
	if not FileAccess.file_exists(json_path):
		printerr("Spreadsheet: skill tree JSON not found at ", json_path)
		_collection = col
		return
	var f := FileAccess.open(json_path, FileAccess.READ)
	if f == null:
		_collection = col
		return
	var json := JSON.new()
	if json.parse(f.get_as_text()) != OK:
		printerr("Spreadsheet: failed to parse skill tree JSON")
		_collection = col
		return
	var data: Array = json.data
	if data.is_empty():
		_collection = col
		return
	var skill_resources: Array[SkillData] = []
	for entry in data:
		var sd := SkillData.new()
		sd.skill_id = str(entry.get("id", ""))
		sd.name = str(entry.get("name", ""))
		sd.icon = str(entry.get("icon", ""))
		sd.desc = str(entry.get("desc", ""))
		sd.cost = float(entry.get("cost", 1))
		sd.parent = str(entry.get("parent", ""))
		sd.parent_skill_id = str(entry.get("parent_skill_id", ""))
		sd.direction = str(entry.get("direction", ""))
		var effects_val = entry.get("effects", {})
		if effects_val is Dictionary:
			sd.effects = effects_val
		sd.exclusive_children = bool(entry.get("exclusive_children", false))
		sd.unlock_color = str(entry.get("unlock_color", "#aaaaaa"))
		sd.x = float(entry.get("x", 0.0))
		sd.y = float(entry.get("y", 0.0))
		skill_resources.append(sd)
	col.types = skill_resources
	_collection = col
	_title_label.text = "Skill Tree Data"

func _save_collection_to_json() -> void:
	if _collection == null:
		return
	var types: Array = _get_types()
	var json_array: Array[Dictionary] = []
	for t in types:
		var sd: SkillData = t as SkillData
		if sd == null:
			continue
		var entry := {
			"id": sd.skill_id,
			"name": sd.name,
			"icon": sd.icon,
			"desc": sd.desc,
			"cost": sd.cost,
			"parent": sd.parent,
			"parent_skill_id": sd.parent_skill_id,
			"direction": sd.direction,
			"effects": sd.effects,
			"exclusive_children": sd.exclusive_children,
			"unlock_color": sd.unlock_color,
			"x": sd.x,
			"y": sd.y,
		}
		json_array.append(entry)
	var json_str := JSON.stringify(json_array, "\t")
	var f := FileAccess.open("res://resources/skill_tree_data.json", FileAccess.WRITE)
	if f:
		f.store_string(json_str)
		_set_status("Saved!")

func _get_types() -> Array:
	if _collection == null:
		return []
	if _collection.get("types") is Array:
		return _collection.get("types") as Array
	return []

func _gather_stat_keys() -> void:
	var seen := {}
	var USAGE_STORAGE := 2
	for t in _get_types():
		var entry: Resource = t
		for prop in entry.get_property_list():
			if not (prop.usage & USAGE_STORAGE):
				continue
			var name: String = prop.name
			if name in SKIP_PROPERTIES or name in seen:
				continue
			seen[name] = true

	var keys := PackedStringArray()
	for k in seen:
		keys.append(k)
	keys.sort()

	# Sort by PROPERTY_ORDER
	var sorted := PackedStringArray()
	for k in PROPERTY_ORDER:
		if k in seen:
			sorted.append(k)
	for k in keys:
		if k not in PROPERTY_ORDER:
			sorted.append(k)

	_stat_keys = sorted

	for key in _stat_keys:
		if key in _value_types:
			continue
		var types := _get_types()
		if types.is_empty():
			_value_types[key] = "String"
			continue
		var first: Resource = types[0]
		var val = first.get(key)
		if val is int:
			_value_types[key] = "int"
		elif val is float:
			_value_types[key] = "float"
		elif val is Dictionary:
			_value_types[key] = "Dictionary"
		elif val is Array:
			_value_types[key] = "Array"
		else:
			_value_types[key] = "String"

func _make_label(text: String, color: Color, tooltip: String = "") -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.modulate = color
	lbl.mouse_filter = Control.MOUSE_FILTER_PASS
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.custom_minimum_size = Vector2(0, 24)
	if tooltip:
		lbl.tooltip_text = tooltip
	return lbl

func _make_cell(entry: Resource, key: String, entry_name: String, ei: int) -> LineEdit:
	var cell := LineEdit.new()
	cell.text = _value_to_string(entry, key)
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.editable = (key != "name")
	cell.tooltip_text = key + " ; " + entry_name
	cell.custom_minimum_size = Vector2(0, 24)

	if key != "name" and cell.text.length() > CELL_EXPAND_CHAR_LIMIT:
		cell.focus_entered.connect(func(): _on_cell_expand(cell))
		cell.focus_exited.connect(func(): _on_cell_contract(cell))

	return cell

func _get_entries_as_rows() -> bool:
	var info: Dictionary = DATA_SOURCES.get(_current_source, {})
	return info.get("entries_as_rows", false)

func _build_grid() -> void:
	_cells = {}
	for c in _data_grid.get_children():
		c.queue_free()
	for c in _top_hbox.get_children():
		c.queue_free()
	_stat_keys = []
	_value_types = {}

	_gather_stat_keys()

	var types := _get_types()
	var n_entries: int = types.size()
	var n_stats: int = _stat_keys.size()
	var entries_as_rows := _get_entries_as_rows()

	if entries_as_rows:
		# Transposed layout: entries as rows, stats as columns
		_data_grid.columns = 1

		# Build column headers in TopHBox
		var corner := _make_label("Entry \\ Stat", Color(0.6, 0.6, 0.6))
		corner.custom_minimum_size = Vector2(100, 24)
		_top_hbox.add_child(corner)
		for si in range(n_stats):
			var key: String = _stat_keys[si]
			var display_name: String = PROPERTY_DISPLAY_NAMES.get(key, key)
			var lbl := _make_label(display_name, Color(1, 1, 0.6), key)
			lbl.custom_minimum_size = Vector2(60, 24)
			_top_hbox.add_child(lbl)

		# Container for all rows
		var rows_vbox := VBoxContainer.new()
		_data_grid.add_child(rows_vbox)

		# Add entry rows
		var items: Array = []
		for ei in range(n_entries):
			items.append({"entry": types[ei], "ei": ei})
		_add_entry_rows(rows_vbox, items, n_stats)

		if items.is_empty():
			var empty_lbl := Label.new()
			empty_lbl.text = "No entries loaded."
			empty_lbl.modulate = Color(0.6, 0.6, 0.6)
			rows_vbox.add_child(empty_lbl)
	else:
		# Default layout: stats as rows, entries as columns
		_data_grid.columns = n_entries + 1
		var corner := _make_label("Stat \\ Entry", Color(0.6, 0.6, 0.6))
		corner.custom_minimum_size = Vector2(100, 24)
		_top_hbox.add_child(corner)

		for t in types:
			var entry: Resource = t
			var entry_name := _entry_name(entry)
			var lbl := _make_label(entry_name, Color(1, 1, 0.6), entry_name)
			lbl.custom_minimum_size = Vector2(60, 24)
			_top_hbox.add_child(lbl)

		for si in range(n_stats):
			var key: String = _stat_keys[si]
			var display_name: String = PROPERTY_DISPLAY_NAMES.get(key, key)
			var row_lbl := _make_label(display_name, Color(0.8, 0.8, 1), key)
			_data_grid.add_child(row_lbl)

			for ei in range(n_entries):
				var entry: Resource = types[ei]
				var cell := _make_cell(entry, key, _entry_name(entry), ei)

				if not _cells.has(ei):
					_cells[ei] = {}
				_cells[ei][key] = cell

				if cell.editable:
					var ei_bind := ei
					var key_bind := key
					cell.text_submitted.connect(func(_t: String): _on_text_submitted(ei_bind, key_bind))
					cell.focus_exited.connect(func(): _on_cell_focus_exited(ei_bind, key_bind))

				_data_grid.add_child(cell)

	_data_scroll.scroll_vertical = 0
	_data_scroll.scroll_horizontal = 0
	_top_scroll.scroll_horizontal = 0

func _add_entry_rows(container: VBoxContainer, items: Array, n_stats: int) -> void:
	for item in items:
		var entry: Resource = item["entry"]
		var ei: int = item["ei"]
		var entry_name := _entry_name(entry)

		var row_hbox := HBoxContainer.new()
		row_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var row_lbl := _make_label(entry_name, Color(0.8, 0.8, 1), entry_name)
		row_lbl.custom_minimum_size = Vector2(100, 24)
		row_hbox.add_child(row_lbl)

		for si in range(n_stats):
			var key: String = _stat_keys[si]
			var cell := _make_cell(entry, key, entry_name, ei)

			if not _cells.has(ei):
				_cells[ei] = {}
			_cells[ei][key] = cell

			if cell.editable:
				var ei_bind := ei
				var key_bind := key
				cell.text_submitted.connect(func(_t: String): _on_text_submitted(ei_bind, key_bind))
				cell.focus_exited.connect(func(): _on_cell_focus_exited(ei_bind, key_bind))

			row_hbox.add_child(cell)

		container.add_child(row_hbox)

func _entry_name(entry: Resource) -> String:
	var val = entry.get("name")
	if val != null and str(val) != "":
		return str(val)
	val = entry.get("skill_id")
	if val != null and str(val) != "":
		return str(val)
	val = entry.get("display_name")
	if val != null and str(val) != "":
		return str(val)
	return ""

func _value_to_string(entry: Resource, key: String) -> String:
	var val = entry.get(key)
	if val is Array:
		var parts := PackedStringArray()
		for v in val:
			parts.append(str(v))
		return ",".join(parts)
	elif val is Dictionary:
		var parts := PackedStringArray()
		for k in val:
			parts.append("%s:%s" % [k, str(val[k])])
		return ",".join(parts)
	elif val == null:
		return ""
	return str(val)

func _string_to_value(key: String, text: String):
	var t = _value_types.get(key, "String")
	match t:
		"int":
			return text.to_int()
		"float":
			return text.to_float()
		"Dictionary":
			var d := {}
			if text.strip_edges() != "":
				for part in text.split(",", false):
					var kv := part.split(":", true, 1)
					if kv.size() == 2:
						d[kv[0].strip_edges()] = kv[1].strip_edges().to_float()
			return d
		"Array":
			var a := []
			if text.strip_edges() != "":
				for part in text.split(",", false):
					a.append(part.strip_edges().to_int())
			return a
		_:
			return text

func _on_text_submitted(ei: int, key: String) -> void:
	_apply_cell_edit(ei, key)

func _on_cell_focus_exited(ei: int, key: String) -> void:
	_apply_cell_edit(ei, key)

func _apply_cell_edit(ei: int, key: String) -> void:
	if not _cells.has(ei) or not _cells[ei].has(key):
		return
	var types := _get_types()
	if ei >= types.size():
		return
	var entry: Resource = types[ei]
	var cell: LineEdit = _cells[ei][key]
	var new_val = _string_to_value(key, cell.text)
	entry.set(key, new_val)
	_needs_save = true

func _on_save() -> void:
	_auto_save()

func _auto_save() -> void:
	if not _needs_save:
		return
	_needs_save = false
	_save_collection_to_json()

func _set_status(msg: String, is_error: bool = false) -> void:
	_status_label.text = msg
	_status_label.modulate = Color(0.9, 0.9, 0.9) if not is_error else Color(1, 0.4, 0.4)
	var prev_msg := msg
	get_tree().create_timer(3.0).timeout.connect(func():
		if _status_label.text == prev_msg:
			_status_label.text = ""
	, CONNECT_ONE_SHOT)

# ── Cell expansion for long text ──────────────────────────────────────────────

func _on_cell_expand(cell: LineEdit) -> void:
	var font := cell.get_theme_font("font")
	var font_size := cell.get_theme_font_size("font_size")
	var text_width := font.get_string_size(cell.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var padding := 16.0
	var needed_width := text_width + padding
	cell.set_meta("expand_orig_min_x", cell.custom_minimum_size.x)
	cell.custom_minimum_size.x = maxf(cell.custom_minimum_size.x, needed_width)

func _on_cell_contract(cell: LineEdit) -> void:
	if cell.has_meta("expand_orig_min_x"):
		cell.custom_minimum_size.x = cell.get_meta("expand_orig_min_x", 0.0)
		cell.remove_meta("expand_orig_min_x")
