class_name SlidingProp
extends "res://scripts/prop.gd"
## Drawers. Slides the pivot along a world direction by `distance`, with a
## little overshoot on the way out and a thunk on the way in.

var direction := Vector3(-1, 0, 0)
var distance := 0.26
var open_time := 0.55
var close_time := 0.4
var overshoot := 0.006
var slide_sound := "drawer_slide"
var thunk_sound := "closet_thump"
var recoil_amount := 0.01

var _tween_pos := 0.0


func _animate(open: bool) -> void:
	is_open = open
	toggled.emit(open)
	var t := _begin()
	t.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	if slide_sound != "":
		AudioBus.sfx_at(slide_sound, global_position, -12.0, 0.08, 1.0 if open else 1.15)
	if open:
		t.tween_method(_set_pos, _tween_pos, distance + overshoot, open_time * 0.75) \
			.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		t.tween_method(_set_pos, distance + overshoot, distance, open_time * 0.25) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	else:
		t.tween_method(_set_pos, _tween_pos, 0.0, close_time) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		t.tween_callback(_thunk)
	t.tween_callback(_done)


func _set_pos(d: float) -> void:
	_tween_pos = d
	pivot.position = direction.normalized() * d


func _thunk() -> void:
	if thunk_sound != "":
		AudioBus.sfx_at(thunk_sound, global_position, -24.0, 0.08, 1.6)
	var p := Presence.get_player()
	if p != null and p.global_position.distance_to(global_position) < 1.4 and p.has_method("recoil"):
		p.call("recoil", recoil_amount)
