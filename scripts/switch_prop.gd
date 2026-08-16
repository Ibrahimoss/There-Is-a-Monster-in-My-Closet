class_name SwitchProp
extends "res://scripts/prop.gd"
## A light switch (or a lamp you tap). Rocks the mesh a few degrees about a
## world axis between an on pose and an off pose with a snap, then calls
## `action(on)`. `is_open` means on.

var axis := Vector3(1, 0, 0)
var flick_deg := 14.0
var flick_time := 0.09
var sound := "switch"
var action: Callable = Callable()
## What this switch drives, so a director can read the state back or flip
## it as if a hand did.
var lights: Array[Light3D] = []

var _tween_angle := 0.0


## Put the mesh in the pose for the current state without a sound.
func snap_state(on: bool) -> void:
	is_open = on
	_set_angle(_pose(on))


## Re-read the pose from the first light, after something else changed it.
func sync_from_lights() -> void:
	if not lights.is_empty() and is_instance_valid(lights[0]):
		snap_state(lights[0].visible)


## Flick it as if someone pressed it: sound, motion, action.
func flick(on: bool) -> void:
	if is_open == on:
		return
	_animate(on)


func _animate(open: bool) -> void:
	is_open = open
	toggled.emit(open)
	var t := _begin()
	AudioBus.sfx_at(sound, global_position, -10.0, 0.04, 1.05 if open else 0.95)
	t.tween_method(_set_angle, _tween_angle, _pose(open), flick_time) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_callback(_fire)
	t.tween_callback(_done)


func _pose(on: bool) -> float:
	return (-0.5 if on else 0.5) * flick_deg


func _set_angle(deg: float) -> void:
	_tween_angle = deg
	pivot.transform.basis = Basis(axis.normalized(), deg_to_rad(deg))


func _fire() -> void:
	if action.is_valid():
		action.call(is_open)
	var p := Presence.get_player()
	if p != null and p.global_position.distance_to(global_position) < 1.5 and p.has_method("recoil"):
		p.call("recoil", 0.015)
