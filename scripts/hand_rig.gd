class_name HandRig
extends Node3D
## Held-object mount under the camera. The held node sits on two springs fed
## by the walk cycle and look velocity: bobs with steps, lags on turns, settles
## on stop. No hand mesh, only the object moves.

const BOB_X := 0.010
const BOB_Y := 0.012
const SWAY_YAW_POS := 0.006
const SWAY_PITCH_POS := 0.004
const SWAY_YAW_ROT := 0.035
const SWAY_PITCH_ROT := 0.03
const SWAY_ROLL := 0.02

var item: Node3D
var rest_pos := Vector3.ZERO
var rest_rot := Vector3.ZERO

var _pos := Spring3.new(18.0, 0.75)
var _rot := Spring3.new(14.0, 0.7)
var _settle: Tween


## Takes `n` from wherever it is, keeps its world pose, and eases it into the
## hand over `settle` seconds. `p`/`yaw_deg`/`s` are the rest pose in camera
## space (face the camera with the yaw the model needs). `tilt_deg` leans the
## item's up axis toward the camera (a brush, a bottle).
func hold(n: Node3D, p: Vector3, yaw_deg: float, s: float, settle := 0.7, tilt_deg := 0.0) -> void:
	release()
	item = n
	rest_pos = p
	rest_rot = Vector3(0.0, deg_to_rad(yaw_deg), 0.0)
	_pos.reset()
	_rot.reset()
	position = rest_pos
	rotation = rest_rot
	n.reparent(self, true)
	# shortest way round on yaw so it does not spin
	var ry := n.rotation.y
	var target_rot := Vector3(deg_to_rad(tilt_deg), ry + wrapf(0.0 - ry, -PI, PI), 0.0)
	if _settle != null and _settle.is_valid():
		_settle.kill()
	_settle = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_settle.tween_property(n, "position", Vector3.ZERO, settle)
	_settle.tween_property(n, "rotation", target_rot, settle)
	_settle.tween_property(n, "scale", Vector3.ONE * s, settle)


## Lets go. Returns the node still parented here; the caller reparents it.
func release() -> Node3D:
	if _settle != null and _settle.is_valid():
		_settle.kill()
	var n := item
	item = null
	return n


func is_holding() -> bool:
	return item != null


## Called every render frame by the player.
func drive(bob_phase: float, bob_blend: float, yaw_vel: float, pitch_vel: float, dt: float) -> void:
	if item == null:
		return
	# steps: small figure of eight, slightly behind the head bob
	var ph := bob_phase - 0.3
	var bob := Vector3(sin(ph) * BOB_X, sin(2.0 * ph) * BOB_Y, 0.0) * bob_blend
	# look lag: turning left leaves the object a bit to the right
	var sway := Vector3(
		clampf(yaw_vel * SWAY_YAW_POS, -0.02, 0.02),
		clampf(-pitch_vel * SWAY_PITCH_POS, -0.015, 0.015),
		0.0)
	_pos.target = bob + sway
	_rot.target = Vector3(
		clampf(-pitch_vel * SWAY_PITCH_ROT, -0.12, 0.12),
		clampf(-yaw_vel * SWAY_YAW_ROT, -0.15, 0.15),
		clampf(yaw_vel * SWAY_ROLL, -0.08, 0.08))
	_pos.step(dt)
	_rot.step(dt)
	position = rest_pos + _pos.value
	rotation = rest_rot + _rot.value


## Landing / bump kick on the held object.
func kick(v: Vector3) -> void:
	_pos.kick(v)
