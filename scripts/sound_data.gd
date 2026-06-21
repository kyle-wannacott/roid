class_name SoundDataCollection
extends Resource

## All game sound entries, referenced by id throughout the codebase.
## Edit entries here or through the spreadsheet UI.
@export var entries: Array = []

## Fast lookup by id.
var _by_id: Dictionary = {}

func get_sound(id: String) -> AudioStream:
	if _by_id.is_empty():
		_build_index()
	var entry = _by_id.get(id)
	return entry.stream if entry != null else null

func get_entry(id: String):
	if _by_id.is_empty():
		_build_index()
	return _by_id.get(id)

func _build_index() -> void:
	_by_id.clear()
	for entry in entries:
		if entry != null and not entry.id.is_empty():
			_by_id[entry.id] = entry
