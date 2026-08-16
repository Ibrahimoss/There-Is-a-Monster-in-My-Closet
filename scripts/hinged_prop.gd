class_name HingedProp
extends "res://scripts/prop.gd"
## Anything on a hinge that is not a full door: cabinet doors, a toilet lid
## and seat, a tap lever. Rotates the pivot about a world axis by a signed
## angle. Opens fast off the line and settles, closes with weight and lands.

var axis := Vector3.UP
var open_deg := 90.0
var open_time := 0.55
var close_time := 0.45
var open_sound := ""
var close_sound := ""
var thunk_sound := ""
var open_db := -14.0
var close_db := -14.0
## Optional gate: another prop that must be in a given state (a seat only
## lifts with the lid up).
var needs: Prop = null
var needs_open := true
## Small overshoot past the open pose, in degrees, settled back.
var overshoot_deg := 0.0
var recoil_amount := 0.0
## Fire the thunk at the end of the open swing instead of the close (a lid
## whose authored pose is up lands when it "opens" downward).
var thunk_on_open := false

var _tween_angle := 0.0


func _can() -> bool:
	if needs != null and needs.is_open != needs_open:
		return false
	return true


func _animate(open: bool) -> void:
	is_open = open
	toggled.emit(open)
	var t := _begin()
	t.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	if open:
		if open_sound != "":
			AudioBus.sfx_at(open_sound, global_position, open_db, 0.06)
		if overshoot_deg > 0.0:
			t.tween_method(_set_angle, _tween_angle, open_deg + overshoot_deg * signf(open_deg), open_time * 0.7) \
				.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
			t.tween_method(_set_angle, open_deg + overshoot_deg * signf(open_deg), open_deg, open_time * 0.3) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		elif thunk_on_open:
			t.tween_method(_set_angle, _tween_angle, open_deg, open_time) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			t.tween_callback(_thunk)
		else:
			t.tween_method(_set_angle, _tween_angle, open_deg, open_time) \
				.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	else:
		if close_sound != "":
			AudioBus.sfx_at(close_sound, global_position, close_db, 0.06)
		if thunk_on_open:
			t.tween_method(_set_angle, _tween_angle, 0.0, close_time) \
				.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		else:
			t.tween_method(_set_angle, _tween_angle, 0.0, close_time) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			t.tween_callback(_thunk)
	t.tween_callback(_done)


func _set_angle(deg: float) -> void:
	_tween_angle = deg
	pivot.transform.basis = Basis(axis.normalized(), deg_to_rad(deg))


func _thunk() -> void:
	if thunk_sound != "":
		AudioBus.sfx_at(thunk_sound, global_position, close_db, 0.08, 1.4)
	if recoil_amount > 0.0:
		var p := Presence.get_player()
		if p != null and p.global_position.distance_to(global_position) < 1.6 and p.has_method("recoil"):
			p.call("recoil", recoil_amount)
