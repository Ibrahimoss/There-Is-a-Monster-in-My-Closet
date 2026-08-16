extends Node
## Global run state, autoloaded as `GameState`.
##
## The "nightmare is assembled from Act 0" rule lives here: Act 0 writes flags,
## Acts 2 and 3 read them back. Keep this file boring - it is the one thing
## every other scene touches.

signal language_changed(lang: String)
signal act_changed(act: Act)
signal toy_taken

enum Act { BEDTIME, CLOSET, NIGHTMARE, BATHROOM, WAKE }

## Where the kid put the toy back at the end of act 0. Sequence 2.2 checks
## this exact spot and finds it empty.
enum ToySpot { BEHIND_PANEL, UNDER_SINK, IN_CISTERN }

var current_act := Act.BEDTIME
## Prompt language for code-built interactables. Arabic by default; the
## start screen can still put it back to English.
var language := "ar"
var toy_location := ToySpot.BEHIND_PANEL

## Set when the kid takes the toy at the top of the hoard. One bool, and it's
## what flips the beams from sweeping to hunting.
var has_toy := false

## Act 0 → later callbacks. Deliberately tiny: every entry here costs authored
## content somewhere downstream, so resist adding more.
var flags := {
	"bathroom_light_on": false,
	"tap_running": false,
	"teeth_brushed": false,
}

## Player settings, saved to user://. Volumes are linear 0..1, sensitivity a
## multiplier on the player's base rate. Applied to the buses / window from
## apply_settings(); the player reads sensitivity and invert_y directly.
const SETTINGS_PATH := "user://settings.cfg"
const SETTINGS_DEFAULT := {
	"master": 0.8,
	"sfx": 1.0,
	"ambience": 1.0,
	"sensitivity": 1.0,
	"invert_y": false,
	"fullscreen": false,
	"language": "ar",
}
var settings := SETTINGS_DEFAULT.duplicate()

var _checkpoint := Vector3.ZERO
var _checkpoint_set := false


func _ready() -> void:
	load_settings()
	# buses are built by AudioBus, which loads after this autoload
	apply_settings.call_deferred()


func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) != OK:
		return
	for k: String in SETTINGS_DEFAULT.keys():
		settings[k] = cf.get_value("settings", k, SETTINGS_DEFAULT[k])


func save_settings() -> void:
	var cf := ConfigFile.new()
	for k: String in settings.keys():
		cf.set_value("settings", k, settings[k])
	cf.save(SETTINGS_PATH)


func set_setting(key: String, value: Variant) -> void:
	settings[key] = value
	apply_settings()


func apply_settings() -> void:
	for pair: Array in [["Master", "master"], ["SFX", "sfx"], ["Ambience", "ambience"]]:
		var idx := AudioServer.get_bus_index(pair[0])
		if idx < 0:
			continue
		var v := clampf(float(settings[pair[1]]), 0.0, 1.0)
		AudioServer.set_bus_mute(idx, v <= 0.001)
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.001)))
	if not OS.has_feature("web"):
		var want := DisplayServer.WINDOW_MODE_FULLSCREEN if bool(settings["fullscreen"]) else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != want:
			DisplayServer.window_set_mode(want)
	set_language(String(settings["language"]))


func set_language(lang: String) -> void:
	settings["language"] = lang
	if language == lang:
		return
	language = lang
	language_changed.emit(lang)


func set_act(act: Act) -> void:
	if current_act == act:
		return
	current_act = act
	act_changed.emit(act)


func take_toy() -> void:
	if has_toy:
		return
	has_toy = true
	toy_taken.emit()


## Checkpoints sit at the head of each beam sequence. Getting caught costs a
## few seconds, never a restart. Jam raters close the tab on harsh deaths.
func set_checkpoint(pos: Vector3) -> void:
	_checkpoint = pos
	_checkpoint_set = true


func has_checkpoint() -> bool:
	return _checkpoint_set


func get_checkpoint() -> Vector3:
	return _checkpoint


func clear_checkpoint() -> void:
	_checkpoint_set = false


func reset() -> void:
	current_act = Act.BEDTIME
	has_toy = false
	toy_location = ToySpot.BEHIND_PANEL
	flags = {
		"bathroom_light_on": false,
		"tap_running": false,
		"teeth_brushed": false,
	}
	_checkpoint_set = false
