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
## Prompt language for code-built interactables. Captions are English only.
var language := "en"
var toy_location := ToySpot.BEHIND_PANEL

## Set when the kid takes the toy at the top of the hoard. One bool, and it's
## what flips the beams from sweeping to hunting.
var has_toy := false

## Act 0 → later callbacks. Deliberately tiny: every entry here costs authored
## content somewhere downstream, so resist adding more.
var flags := {
	"bathroom_light_on": false,
	"tap_running": false,
}

var _checkpoint := Vector3.ZERO
var _checkpoint_set := false


func set_language(lang: String) -> void:
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
	}
	_checkpoint_set = false
