class_name Door
extends MeshInstance3D

## A hinged door the player can open and close with the interact key.
##
## Put this on the door's own node — the one whose origin sits at the hinge
## edge — and give it a child body with a collider so it blocks the way when
## shut. The player's raycast walks up from the collider looking for a node
## with an interact() method, so it finds this from the AnimatableBody3D.
##
## Swings around world up through the node's origin, so it does not care how
## the mesh was authored or how the parent is oriented.
##
## Player presses swing the panel away from the side the player stands on
## (swing_away), locked doors rattle, and the door exposes get_prompt /
## get_prompt_anchor / set_focused for the world prompt.

signal opened
signal closed
signal refused  ## tried while locked — good hook for a rattle and a scare

## Degrees to swing. Flip the sign if the door opens into the wall.
@export_range(-180.0, 180.0) var open_angle := 90.0
## Seconds for a full swing. Partial swings are proportionally quicker.
@export var swing_time := 1.4
@export var locked := false
## Use if the door was placed ajar and you want that angle treated as shut.
## Set it to minus the angle it currently sits at.
@export_range(-180.0, 180.0) var closed_offset := 0.0
## Degrees along the opening direction the door hangs at before it is ever
## touched. It swings fully open from here on the first interact, and from
## then on closing lands on the true shut pose, never back on this one.
@export_range(0.0, 180.0) var ajar_angle := 0.0
## Player opens pick the swing sign so the panel moves away from the player.
## Off, every open uses open_angle's own sign.
@export var swing_away := true

@export_group("Audio (optional)")
@export var open_sound: AudioStream
@export var close_sound: AudioStream
@export var locked_sound: AudioStream
## Volume for this door's sounds. 0 is the file as-is; -6 is roughly half as
## loud, -12 quarter; -80 is silence.
@export_range(-80.0, 6.0, 0.1, "suffix:dB") var volume_db := -14.0
## What the prompt says while locked. A closet the kid will not open says
## "Open" and refuses on the press instead of announcing a lock.
@export var locked_prompt := "Locked"

const GLOW_COLOR := Color(1.0, 0.86, 0.55)
const GLOW_ENERGY := 0.16
const HANDLE_HEIGHT := 1.0
const JIGGLE_DEG := 1.3
## Opening: a latch click and a hair of give, then the swing (fast off the
## line, long settle). Closing: accelerates into the frame, hits, rebounds a
## touch. All inside swing_time so scripted timings hold.
const HANDLE_BEAT := 0.11
const PRE_GIVE_DEG := 0.35
const CLOSE_SNAP_DEG := 0.6
const REBOUND_DEG := 0.3
## Free swing when unlatched and shoved: an angular velocity that bleeds off,
## bounces at the open stop, latches when it finds the frame.
const SWING_DAMPING := 2.2
const RESTITUTION := 0.18
const PUSH_BLEND := 0.35
const OPENED_BY_PUSH_DEG := 10.0
## Seconds for a full swing when shouldered open at a run.
const BARGE_TIME := 0.28

var is_open := false
## rad/s of world hinge angle while coasting after a shove
var _ang_vel := 0.0
var _next_rattle_ms := 0
var _last_world_angle := 0.0

var _shut := Transform3D.IDENTITY
var _swing := 0.0  # 0 = shut, 1 = fully open
## +1/-1 on top of open_angle's sign, chosen per open by swing_away.
var _dir := 1.0
## Extra hinge angle for the locked rattle. Setter re-applies the pose.
var _jiggle := 0.0:
	set(value):
		_jiggle = value
		_apply(_swing)
var _tween: Tween
var _jiggle_tween: Tween
var _glow_tween: Tween
var _voice: AudioStreamPlayer3D
var _glow_mats: Array[StandardMaterial3D] = []
var _focused := false
## Shut-pose geometry in world space: hinge origin to panel centre (flat),
## the axis the panel is thin along, and where the handle sits above the floor.
var _hinge_to_center := Vector3(1, 0, 0)
var _normal := Vector3(0, 0, 1)
var _handle_y := 1.0


func _ready() -> void:
	_shut = global_transform
	if not is_zero_approx(closed_offset):
		_shut.basis = _shut.basis.rotated(Vector3.UP, deg_to_rad(closed_offset))
		global_transform = _shut
	_measure()

	# sync_to_physics re-asserts the body's own transform every physics tick,
	# which silently cancels rotation applied through a parent — the mesh
	# swings while the collider stays in the doorway. This script moves the
	# whole hierarchy itself, so the body must follow its parent instead.
	var has_body := false
	for child in get_children():
		if child is AnimatableBody3D:
			child.sync_to_physics = false
			child.collision_mask = 0
			child.set_meta("door", self)
			has_body = true

	# A door without a hand-made collider builds one from its own mesh bounds,
	# so attaching this script is all a new door needs.
	if not has_body:
		_build_collider()
	# hang ajar if asked, whether the collider was hand-made or built here
	if not is_zero_approx(ajar_angle) and not is_zero_approx(open_angle):
		_apply(ajar_angle / open_angle)
	set_physics_process(false)
	set_process(false)


func _world_angle() -> float:
	return deg_to_rad(open_angle) * _swing * _dir


## Coasting after a shove: damped angular velocity, bounce at the stop, latch
## at the frame. Only runs while unlatched and not being driven by a tween.
func _physics_process(dt: float) -> void:
	if _tween != null and _tween.is_valid() and _tween.is_running():
		_ang_vel = 0.0
		set_physics_process(false)
		return
	if absf(_ang_vel) < 0.002:
		_ang_vel = 0.0
		set_physics_process(false)
		return
	_ang_vel *= exp(-SWING_DAMPING * dt)
	var a := _world_angle()
	var na := a + _ang_vel * dt
	var lim := deg_to_rad(absf(open_angle))
	# crossed or reached the frame: latch
	if (a != 0.0 and signf(na) != signf(a)) or (absf(na) < deg_to_rad(0.2) and absf(na) < absf(a)):
		_latch(absf(_ang_vel))
		return
	if absf(na) > lim:
		na = lim * signf(na)
		AudioBus.sfx_at("closet_thump", get_prompt_anchor(), -22.0 + 8.0 * clampf(absf(_ang_vel), 0.0, 1.5), 0.1, 1.4)
		_ang_vel = -_ang_vel * RESTITUTION
	var denom := deg_to_rad(open_angle) * _dir
	_swing = na / denom if denom != 0.0 else 0.0
	_apply(_swing)
	if not is_open and absf(na) > deg_to_rad(OPENED_BY_PUSH_DEG):
		is_open = true
		opened.emit()


func _latch(speed: float) -> void:
	_ang_vel = 0.0
	set_physics_process(false)
	_swing = 0.0
	is_open = false
	_apply(0.0)
	if speed > 0.4:
		_play_close()
	AudioBus.sfx_at("door_latch", get_prompt_anchor(), -16.0 + 4.0 * clampf(speed, 0.0, 1.5), 0.06, 1.0)
	closed.emit()


## The player walked into the panel at `point` with velocity `vel`. Latched
## doors are walls, locked ones rattle, anything else takes the shove as
## angular velocity matched to the player's speed at that lever arm.
func push_from(point: Vector3, vel: Vector3) -> void:
	if _tween != null and _tween.is_valid() and _tween.is_running():
		return
	if locked:
		var now := Time.get_ticks_msec()
		if now >= _next_rattle_ms:
			jiggle(0.35)
			_next_rattle_ms = now + 600
		return
	if is_zero_approx(_swing):
		return
	var a := _world_angle()
	var panel_dir := _hinge_to_center.rotated(Vector3.UP, a).normalized()
	# a positive hinge rate moves the panel toward +n
	var n := panel_dir.rotated(Vector3.UP, PI * 0.5)
	var into := Vector3(vel.x, 0.0, vel.z).dot(n)
	if absf(into) < 0.15:
		return
	var width := maxf(_hinge_to_center.length() * 2.0, 0.3)
	var lever := clampf((point - _shut.origin).dot(panel_dir), 0.15, width)
	_ang_vel = lerpf(_ang_vel, into / lever, PUSH_BLEND)
	set_physics_process(true)


## A running shoulder: the panel is thrown open away from `by`, fast, with a
## bang. Locked doors take the hit and rattle. Returns whether it gave.
func barge(by: Node3D) -> bool:
	if _tween != null and _tween.is_valid() and _tween.is_running():
		return false
	var now := Time.get_ticks_msec()
	if locked:
		if now >= _next_rattle_ms:
			_next_rattle_ms = now + 500
			jiggle(1.4)
			AudioBus.sfx_at("closet_thump", get_prompt_anchor(), volume_db + 2.0, 0.08, 0.9)
			_play(locked_sound)
			refused.emit()
		return false
	if is_open:
		return false
	_dir = swing_away_from(by.global_position)
	var keep := swing_time
	swing_time = minf(swing_time, BARGE_TIME)
	set_open(true)
	swing_time = keep
	AudioBus.sfx_at("closet_thump", get_prompt_anchor(), volume_db + 3.0, 0.08, 1.15)
	return true


## While a tween drives the panel through the player, shove them along
## instead of leaving the physics engine to pop the capsule out.
func _process(dt: float) -> void:
	if _tween == null or not _tween.is_valid() or not _tween.is_running():
		set_process(false)
		return
	var body: AnimatableBody3D = null
	for c in get_children():
		if c is AnimatableBody3D:
			body = c as AnimatableBody3D
			break
	if body == null:
		return
	var shape_node: CollisionShape3D = null
	for c in body.get_children():
		if c is CollisionShape3D:
			shape_node = c as CollisionShape3D
			break
	if shape_node == null:
		return
	var a := _world_angle()
	var rate := (a - _last_world_angle) / maxf(dt, 0.0001)
	_last_world_angle = a
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape_node.shape
	q.transform = shape_node.global_transform
	q.collision_mask = 2
	q.exclude = [body.get_rid()]
	var hits := get_world_3d().direct_space_state.intersect_shape(q, 1)
	if hits.is_empty():
		return
	var other: Object = hits[0]["collider"]
	if other == null or not other.has_method("push"):
		return
	var panel_dir := _hinge_to_center.rotated(Vector3.UP, a).normalized()
	var n := panel_dir.rotated(Vector3.UP, PI * 0.5)
	var to_player := (other as Node3D).global_position - (_shut.origin + panel_dir * _hinge_to_center.length())
	var side := signf(to_player.dot(n))
	if side == 0.0:
		side = signf(rate)
	var edge_speed := absf(rate) * _hinge_to_center.length() * 2.0
	other.call("push", n * side * (edge_speed + 0.2))


## World-space shape of the shut panel: which way is thin, where the handle
## side is. Read once in the shut pose so swing_away can pick a side later.
func _measure() -> void:
	if mesh == null:
		return
	var aabb := MeshUtil.world_aabb(self)
	_hinge_to_center = aabb.get_center() - _shut.origin
	_hinge_to_center.y = 0.0
	_normal = Vector3(0, 0, 1) if aabb.size.z < aabb.size.x else Vector3(1, 0, 0)
	_handle_y = aabb.position.y + HANDLE_HEIGHT - _shut.origin.y


func _build_collider() -> void:
	var aabb := get_aabb()
	var box := BoxShape3D.new()
	# Floor of 2cm per axis (in WORLD units) keeps the thin axis of a door
	# panel raycastable. The aabb is in local units, and imported meshes here
	# carry a 100x node scale, so the floor must be divided back into local
	# space per axis — a flat 0.02 local floor would become a 2m slab.
	var world_scale := global_transform.basis.get_scale().abs()
	var floor_local := Vector3(
		0.02 / maxf(world_scale.x, 0.001),
		0.02 / maxf(world_scale.y, 0.001),
		0.02 / maxf(world_scale.z, 0.001))
	box.size = aabb.size.max(floor_local)

	var shape := CollisionShape3D.new()
	shape.shape = box
	shape.position = aabb.get_center()

	var body := AnimatableBody3D.new()
	body.sync_to_physics = false
	body.collision_mask = 0
	body.set_meta("door", self)
	body.add_child(shape)
	add_child(body)


## Called by the player's interact raycast.
func interact(by: Node = null) -> void:
	if locked:
		_play(locked_sound)
		jiggle()
		refused.emit()
		return
	if not is_open and swing_away and by is Node3D:
		var new_dir := swing_away_from((by as Node3D).global_position)
		if new_dir != _dir:
			# keep the current world angle continuous under the new sign, so an
			# ajar door swings back through the frame instead of snapping
			_swing = -_swing
			_dir = new_dir
	set_open(not is_open)


func set_open(value: bool) -> void:
	is_open = value
	_ang_vel = 0.0
	set_physics_process(false)

	var target := 1.0 if value else 0.0
	if _tween != null and _tween.is_valid():
		_tween.kill()

	# Scale the duration to how far is actually left, so interrupting a swing
	# half way does not make the rest of it crawl.
	var start := _swing
	var duration := swing_time * absf(target - start)
	if is_zero_approx(duration):
		_apply(target)
		_announce()
		return

	# degrees to swing units
	var frac := 1.0 / maxf(absf(open_angle), 1.0)

	_tween = create_tween()
	# Physics step, not idle: the collider is an AnimatableBody3D, and moving it
	# out of sync with the physics tick makes it stutter and miss contacts.
	_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	# watch for the panel meeting the player while it swings
	_last_world_angle = _world_angle()
	set_process(true)
	if value:
		var beat := minf(HANDLE_BEAT, duration * 0.2)
		var give := start + PRE_GIVE_DEG * frac
		AudioBus.sfx_at("door_latch", get_prompt_anchor(), -18.0, 0.06, 1.15)
		_tween.tween_method(_apply, start, give, beat * 0.6) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_tween.tween_interval(beat * 0.4)
		# a short swing gets a quieter creak, a nudge none
		var travel := absf(target - start)
		if travel > 0.12:
			_tween.tween_callback(_play.bind(open_sound, -8.0 * (1.0 - clampf(travel, 0.0, 1.0))))
		_tween.tween_method(_apply, give, target, duration - beat) \
			.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	else:
		var side := signf(start)
		if side == 0.0:
			side = 1.0
		var snap := CLOSE_SNAP_DEG * frac * side
		var rebound := REBOUND_DEG * frac * side
		_tween.tween_method(_apply, start, snap, duration * 0.85) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_tween.tween_callback(_impact)
		_tween.tween_method(_apply, snap, rebound, duration * 0.06)
		_tween.tween_method(_apply, rebound, 0.0, duration * 0.09) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_callback(_announce)


func _impact() -> void:
	_play_close()
	AudioBus.sfx_at("door_latch", get_prompt_anchor(), -14.0, 0.06, 1.0)


## Snap to a state with no animation — for level setup or a jump scare.
func snap_open(value: bool) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_ang_vel = 0.0
	set_physics_process(false)
	is_open = value
	_apply(1.0 if value else 0.0)
	_announce()


## Sign (+1/-1) that swings the panel away from `pos`. Which way a positive
## rotation moves the panel depends on where the hinge sits, so it is read
## from the geometry rather than assumed.
func swing_away_from(pos: Vector3) -> float:
	var side := signf((pos - _shut.origin).dot(_normal))
	if side == 0.0:
		side = 1.0
	var plus_moves_to := signf(_hinge_to_center.rotated(Vector3.UP, 0.2).dot(_normal))
	if plus_moves_to == 0.0:
		plus_moves_to = 1.0
	return -side * plus_moves_to * signf(open_angle if open_angle != 0.0 else 1.0)


## Locked-door rattle around the hinge. Sound is the caller's (interact plays
## locked_sound).
func jiggle(intensity := 1.0) -> void:
	if _jiggle_tween != null and _jiggle_tween.is_valid():
		_jiggle_tween.kill()
	var amp := deg_to_rad(JIGGLE_DEG) * intensity
	_jiggle_tween = create_tween()
	_jiggle_tween.tween_property(self, "_jiggle", amp, 0.06)
	_jiggle_tween.tween_property(self, "_jiggle", 0.0, 0.05)
	_jiggle_tween.tween_property(self, "_jiggle", amp * 0.6, 0.05)
	_jiggle_tween.tween_property(self, "_jiggle", 0.0, 0.08)


# --- prompt hooks --------------------------------------------------------

func can_interact() -> bool:
	return true


func get_prompt() -> String:
	if locked:
		return locked_prompt
	return "Close" if is_open else "Open"


## Handle side of the panel at its current angle, about a metre up.
func get_prompt_anchor() -> Vector3:
	var ang := deg_to_rad(open_angle * _swing * _dir) + _jiggle
	var handle := _hinge_to_center.rotated(Vector3.UP, ang) * 1.7
	return _shut.origin + handle + Vector3(0.0, _handle_y, 0.0)


## Hover glow: a little emission on this panel only, faded in and out.
func set_focused(on: bool) -> void:
	if _focused == on:
		return
	_focused = on
	if _glow_mats.is_empty():
		_glow_mats = MeshUtil.make_glow_overrides(self, GLOW_COLOR)
	if _glow_tween != null and _glow_tween.is_valid():
		_glow_tween.kill()
	_glow_tween = create_tween().set_parallel(true)
	for m in _glow_mats:
		_glow_tween.tween_property(m, "emission_energy_multiplier",
			GLOW_ENERGY if on else 0.0, 0.25 if on else 0.35)


# --- internals -----------------------------------------------------------

func _apply(t: float) -> void:
	_swing = t
	# Rebuild from the shut pose every frame rather than accumulating rotations,
	# so the hinge cannot drift and the mesh's 100x import scale is preserved.
	global_transform = Transform3D(
		_shut.basis.rotated(Vector3.UP, deg_to_rad(open_angle * t * _dir) + _jiggle),
		_shut.origin)


func _announce() -> void:
	# the creak stops with the panel, however long the file is
	if _voice != null and is_instance_valid(_voice) and _voice.playing:
		var v := _voice
		var t := create_tween()
		t.tween_property(v, "volume_db", -50.0, 0.3)
		t.tween_callback(v.queue_free)
		_voice = null
	if is_open:
		opened.emit()
	else:
		closed.emit()


## Closing never creaks: a shut is a soft thud unless the door was given its
## own close sound (one that is not just the open sound again).
func _play_close() -> void:
	if close_sound != null and close_sound != open_sound:
		_play(close_sound)
	else:
		AudioBus.sfx_at("door_close", get_prompt_anchor(), volume_db + 2.0, 0.08)


func _play(stream: AudioStream, offset_db := 0.0) -> void:
	if stream == null:
		return
	if _voice != null and is_instance_valid(_voice):
		_voice.queue_free()
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.volume_db = volume_db + offset_db
	player.pitch_scale = randf_range(0.92, 1.08)
	player.unit_size = 3.0
	player.max_distance = 18.0
	if AudioServer.get_bus_index("SFX") >= 0:
		player.bus = "SFX"
	add_child(player)
	player.play()
	player.finished.connect(player.queue_free)
	_voice = player
