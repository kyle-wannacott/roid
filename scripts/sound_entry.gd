class_name SoundEntry
extends Resource

## Unique identifier used in code to reference this sound (e.g. "sfx_laser_beam").
@export var id: String = ""

## Human-readable name shown in the spreadsheet dropdown.
@export var display_name: String = ""

## The actual audio file to play. If null, no sound is played for this event.
@export var stream: AudioStream = null

## Category derived from the sounds/ subdirectory (e.g. "player", "ui", "weapons").
## Used in the spreadsheet to group and filter sound effects.
@export var category: String = ""
