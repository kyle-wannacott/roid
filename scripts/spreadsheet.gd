class_name Spreadsheet
extends Control

## Data source configuration. Keys are used as OptionButton item identifiers.
const DATA_SOURCES := {
	"skill_tree": {
		"title": "Skill Tree Data",
		"entries_as_rows": true,
	},
	"sounds": {
		"title": "Sound Effects",
		"path": "res://resources/sounds_data.tres",
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
	var info: Dictionary = DATA_SOURCES.get(_current_source, {})
	match _current_source:
		"skill_tree":
			_load_skill_tree()
		"sounds":
			_load_sounds()
		_:
			_collection = null


func _load_skill_tree() -> void:
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


func _load_sounds() -> void:
	# Load SoundDataCollection from the .tres resource
	var path := "res://resources/sounds_data.tres"
	if not ResourceLoader.exists(path):
		printerr("Spreadsheet: sounds data not found at ", path)
		_collection = SoundDataCollection.new()
		return
	var res = load(path)
	if res == null or not (res is SoundDataCollection):
		printerr("Spreadsheet: failed to load sounds data")
		_collection = SoundDataCollection.new()
		return
	_collection = res
	_title_label.text = "Sound Effects"

func _save_collection_to_json() -> void:
	if _collection == null:
		return
	match _current_source:
		"skill_tree":
			_save_skill_tree()
		"sounds":
			_save_sounds()


func _save_skill_tree() -> void:
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


func _save_sounds() -> void:
	# Save the SoundDataCollection back to the .tres resource.
	var result := ResourceSaver.save(_collection, "res://resources/sounds_data.tres")
	if result == OK:
		_set_status("Saved!")
	else:
		_set_status("Save failed!", true)

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


## Create a special cell for the "stream" property of a sound entry.
## Shows the current stream path with a "Play" button (to preview) and
## a "Load" button (to browse audio files). The stream is stored on
## the entry as an AudioStream resource.
func _make_sound_cell(entry: Resource, key: String, entry_name: String, ei: int) -> HBoxContainer:
	var hbox := HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Text showing the stream path
	var path_edit := LineEdit.new()
	path_edit.text = _value_to_string(entry, key)
	path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	path_edit.placeholder_text = "(no stream — silent)"
	path_edit.custom_minimum_size = Vector2(0, 24)
	path_edit.tooltip_text = key + " ; " + entry_name
	hbox.add_child(path_edit)

	# Play button
	var play_btn := Button.new()
	play_btn.text = "▶"
	play_btn.tooltip_text = "Preview this sound"
	play_btn.custom_minimum_size = Vector2(28, 24)
	play_btn.pressed.connect(func():
		var stream: AudioStream = entry.get("stream") as AudioStream
		if stream != null and SoundManager:
			SoundManager.play_sfx(stream)
	)
	hbox.add_child(play_btn)

	# Load button
	var load_btn := Button.new()
	load_btn.text = "📂 Load"
	load_btn.tooltip_text = "Browse for an audio file"
	load_btn.custom_minimum_size = Vector2(50, 24)
	load_btn.pressed.connect(func():
		_open_audio_picker_for_sound(entry, path_edit)
	)
	hbox.add_child(load_btn)

	return hbox


## Open the audio file picker to assign a stream to a sound entry.
func _open_audio_picker_for_sound(entry: Resource, path_edit: LineEdit) -> void:
	var win := Window.new()
	win.title = "Select Audio File"
	win.size = Vector2i(620, 540)
	win.wrap_controls = true
	win.exclusive = true
	if PlayerSkills:
		PlayerSkills.editor_modal_open = true
	add_child(win)

	var root := VBoxContainer.new()
	root.anchor_right = 1.0
	root.anchor_bottom = 1.0
	root.offset_left = 8.0; root.offset_right = -8.0
	root.offset_top = 6.0;  root.offset_bottom = -6.0
	root.add_theme_constant_override("separation", 4)
	win.add_child(root)

	var search := LineEdit.new()
	search.placeholder_text = "Filter audio files…"
	root.add_child(search)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)

	var list_vbox := VBoxContainer.new()
	list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list_vbox)

	var loading_label := Label.new()
	loading_label.text = "Loading audio files…"
	list_vbox.add_child(loading_label)

	var bottom_hbox := HBoxContainer.new()
	root.add_child(bottom_hbox)

	var sel_label := Label.new()
	sel_label.text = ""
	sel_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sel_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bottom_hbox.add_child(sel_label)

	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(func():
		if PlayerSkills: PlayerSkills.editor_modal_open = false
		win.queue_free())
	bottom_hbox.add_child(cancel)

	win.close_requested.connect(func():
		if PlayerSkills: PlayerSkills.editor_modal_open = false
		win.queue_free())

	win.popup_centered()

	# Defer the file scan to avoid blocking the UI
	call_deferred("_finish_audio_picker", win, loading_label, list_vbox, search, path_edit, entry)


## Populate the audio picker with actual file rows.
func _finish_audio_picker(win: Window, loading_label: Label, list_vbox: VBoxContainer,
		search: LineEdit, path_edit: LineEdit, entry: Resource) -> void:
	if is_instance_valid(loading_label):
		loading_label.queue_free()
	if not is_instance_valid(win):
		return
	# Collect and display files
	var all_files: Array[Dictionary] = []
	_collect_audio_files("res://sounds", all_files)
	all_files.sort_custom(func(a, b): return a.name.naturalnocasecmp_to(b.name) < 0)

	var rows: Array = []
	for af: Dictionary in all_files:
		if not is_instance_valid(list_vbox):
			return
		var row_hbox := HBoxContainer.new()
		row_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var af_path: String = af.path
		var play_btn := Button.new()
		play_btn.text = "▶"
		play_btn.tooltip_text = "Preview this sound"
		play_btn.custom_minimum_size = Vector2(24, 22)
		play_btn.pressed.connect(func():
			var loaded := load(af_path)
			if loaded is AudioStream and SoundManager:
				SoundManager.play_sfx(loaded)
		)
		row_hbox.add_child(play_btn)

		var name_btn := Button.new()
		name_btn.text = af.name
		name_btn.tooltip_text = af_path.trim_prefix("res://")
		name_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_btn.pressed.connect(func():
			if not is_instance_valid(win): return
			var loaded := load(af_path)
			if loaded is AudioStream:
				entry.set("stream", loaded)
				path_edit.text = af_path
				_needs_save = true
				_auto_save()
			if PlayerSkills: PlayerSkills.editor_modal_open = false
			win.queue_free()
		)
		row_hbox.add_child(name_btn)
		list_vbox.add_child(row_hbox)
		rows.append(row_hbox)

	# Search filter
	search.text_changed.connect(func(t: String):
		var f := t.to_lower()
		for r in rows:
			if not is_instance_valid(r): continue
			# Find the name label in the row
			for c in r.get_children():
				if c is Button and not c.text.begins_with("▶") and not c.text.begins_with("📂"):
					c.visible = f.is_empty() or c.text.to_lower().contains(f)
	)


func build_deferred() -> void:
	# Sound audio picker: scan res://sounds/ and let user pick a file.
	# The picker was opened by _open_audio_picker_for_sound. The window
	# and its layout are stored as class members via the build closure.
	pass  # actual picker implementation handled by _build_audio_picker()


## Build the audio file list for a sound entry's stream picker.
func _build_audio_picker(picker: Window, list_vbox: VBoxContainer, sel_label: Label,
		search: LineEdit, path_edit: LineEdit, entry: Resource) -> void:
	# Scan res://sounds/ for .ogg/.wav/.mp3 files
	var all_files: Array[Dictionary] = []
	_collect_audio_files("res://sounds", all_files)
	all_files.sort_custom(func(a, b): return a.name.naturalnocasecmp_to(b.name) < 0)

	# Build rows
	for af: Dictionary in all_files:
		if not is_instance_valid(list_vbox):
			return
		var row_hbox := HBoxContainer.new()
		row_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var af_path: String = af.path
		var play_btn := Button.new()
		play_btn.text = "▶"
		play_btn.tooltip_text = "Preview this sound"
		play_btn.custom_minimum_size = Vector2(24, 22)
		play_btn.pressed.connect(func():
			var loaded := load(af_path)
			var stream: AudioStream = loaded as AudioStream if loaded is AudioStream else null
			if stream != null and SoundManager:
				SoundManager.play_sfx(stream)
		)
		row_hbox.add_child(play_btn)

		var name_btn := Button.new()
		name_btn.text = af.name
		name_btn.tooltip_text = af_path.trim_prefix("res://")
		name_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_btn.pressed.connect(func():
			if not is_instance_valid(picker): return
			sel_label.text = af_path.trim_prefix("res://")
			var loaded := load(af_path)
			if loaded is AudioStream:
				entry.set("stream", loaded as AudioStream)
				path_edit.text = af_path
				_needs_save = true
				_auto_save()
			if PlayerSkills: PlayerSkills.editor_modal_open = false
			picker.queue_free()
		)
		row_hbox.add_child(name_btn)

		list_vbox.add_child(row_hbox)


## Recursively collect audio files under a directory.
func _collect_audio_files(dir_path: String, result: Array[Dictionary]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname == "." or fname == "..":
			fname = dir.get_next()
			continue
		var full := dir_path.path_join(fname)
		if dir.current_is_dir():
			_collect_audio_files(full, result)
		elif fname.ends_with(".ogg") or fname.ends_with(".wav") or fname.ends_with(".mp3"):
			result.append({"path": full, "name": fname})
		fname = dir.get_next()
	dir.list_dir_end()

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
			# Use the sound cell for the "stream" field of sound entries
			var cell: Control
			if _current_source == "sounds" and key == "stream":
				cell = _make_sound_cell(entry, key, entry_name, ei)
			else:
				cell = _make_cell(entry, key, entry_name, ei)

			if not _cells.has(ei):
				_cells[ei] = {}
			_cells[ei][key] = cell

			if cell is LineEdit and (cell as LineEdit).editable:
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
