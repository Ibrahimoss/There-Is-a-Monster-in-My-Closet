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

@export_group("Audio (optional)")
@export var open_sound: AudioStream
@export var close_sound: AudioStream
@export var locked_sound: AudioStream
## Volume for this door's sounds. 0 is the file as-is; -6 is roughly half as
## loud, -12 quarter; -80 is silence.
@export_range(-80.0, 6.0, 0.1, "suffix:dB") var volume_db := -6.0

var is_open := false

var _shut := Transform3D.IDENTITY
var _swing := 0.0  # 0 = shut, 1 = fully open
var _tween: Tween


func _ready() -> void:
	_shut = global_transform
	if not is_zero_approx(closed_offset):
		_shut.basis = _shut.basis.rotated(Vector3.UP, deg_to_rad(closed_offset))
		global_transform = _shut

	# sync_to_physics re-asserts the body's own transform every physics tick,
	# which silently cancels rotation applied through a parent — the mesh
	# swings while the collider stays in the doorway. This script moves the
	# whole hierarchy itself, so the body must follow its parent instead.
	var has_body := false
	for child in get_children():
		if child is AnimatableBody3D:
			child.sync_to_physics = false
			has_body = true

	# A door without a hand-made collider builds one from its own mesh bounds,
	# so attaching this script is all a new door needs.
	if not has_body:
		_build_collider()


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
	body.add_child(shape)
	add_child(body)

	if not is_zero_approx(ajar_angle) and not is_zero_approx(open_angle):
		_apply(ajar_angle / open_angle)


## Called by the player's interact raycast.
func interact(_by: Node = null) -> void:
	if locked:
		_play(locked_sound)
		refused.emit()
		return
	set_open(not is_open)


func set_open(value: bool) -> void:
	is_open = value
	_play(open_sound if value else close_sound)

	var target := 1.0 if value else 0.0
	if _tween != null and _tween.is_valid():
		_tween.kill()

	# Scale the duration to how far is actually left, so interrupting a swing
	# half way does not make the rest of it crawl.
	var duration := swing_time * absf(target - _swing)
	if is_zero_approx(duration):
		_apply(target)
		_announce()
		return

	_tween = create_tween()
	# Physics step, not idle: the collider is an AnimatableBody3D, and moving it
	# out of sync with the physics tick makes it stutter and miss contacts.
	_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_tween.tween_method(_apply, _swing, target, duration) \
		.set_trans(Tween.TRANS_CUBIC) \
		.set_ease(Tween.EASE_OUT if value else Tween.EASE_IN)
	_tween.tween_callback(_announce)


## Snap to a state with no animation — for level setup or a jump scare.
func snap_open(value: bool) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	is_open = value
	_apply(1.0 if value else 0.0)
	_announce()


func _apply(t: float) -> void:
	_swing = t
	# Rebuild from the shut pose every frame rather than accumulating rotations,
	# so the hinge cannot drift and the mesh's 100x import scale is preserved.
	global_transform = Transform3D(
		_shut.basis.rotated(Vector3.UP, deg_to_rad(open_angle * t)),
		_shut.origin)


func _announce() -> void:
	if is_open:
		opened.emit()
	else:
		closed.emit()


func _play(stream: AudioStream) -> void:
	if stream == null:
		return
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.volume_db = volume_db
	add_child(player)
	player.play()
	player.finished.connect(player.queue_free)
