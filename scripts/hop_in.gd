class_name HopIn
extends Interactable

## The way down into the sewer. An Interactable, so it uses the same world
## prompt and reticle as every door — look at it and the prompt appears,
## press interact and the kid drops through.
##
## The drop is done under a fade: the sewer sits ~40m away from the house, so
## an actual fall would be a long trip through empty space.

signal hopped

## Where he lands. Point this at a marker you can drag in the editor; the
## fallback vector is only used if the path is empty.
@export var landing_path: NodePath = NodePath("../SewerLanding")
@export var landing_position := Vector3(-1.7, 6.5, -0.2)
## Stepping up to the mouth of the hole.
@export var step_in_time := 0.45
## And dropping through to the landing. He is carried the whole way, so the
## move reads as one motion instead of a cut.
@export var drop_time := 0.7
## 0 means no blackout at all — he simply walks in. Raise it if you ever want
## the cut back.
@export var fade_time := 0.0
## Off: he stays upside down through the sewer. Turning this on would put him
## back on his feet, which also shifts him off the landing spot on the way.
@export var restore_gravity := false


func _can_interact() -> bool:
	return not _used


func _on_interact(by: Node3D) -> void:
	_drop(by)


func _drop(who: Node3D) -> void:
	var player: Node3D = who
	if player == null or not player is CharacterBody3D:
		player = get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		push_warning("HopIn: no player to drop.")
		return

	if player.has_method("begin_cinematic"):
		player.begin_cinematic()

	var fade := get_node_or_null("/root/Fade")
	var use_fade: bool = fade != null and fade_time > 0.0 and fade.has_method("fade_out")
	if use_fade:
		await fade.fade_out(fade_time)

	# Un-roll first: turning gravity back over nudges his position, so doing
	# it after the move would shove him off the landing spot.
	if restore_gravity:
		var act_node := get_parent()
		if act_node != null and act_node.has_method("set_gravity_flipped"):
			await act_node.set_gravity_flipped(false)

	# down here the house's collision is invisible but still solid, so it
	# reads as walls in the middle of the pipe
	var act := get_parent()
	if act != null and act.has_method("set_house_collision"):
		act.set_house_collision(false)

	# One move, no cut: he steps into the mouth of the hole and carries on
	# through to the landing, so the camera travels the whole way.
	player.velocity = Vector3.ZERO
	var t := create_tween().set_trans(Tween.TRANS_SINE)
	t.tween_property(player, "global_position", global_position, step_in_time) \
		.set_ease(Tween.EASE_IN_OUT)
	t.tween_property(player, "global_position", _landing(), drop_time) \
		.set_ease(Tween.EASE_OUT)
	await t.finished
	player.velocity = Vector3.ZERO

	if use_fade:
		fade.fade_in(fade_time)
	if player.has_method("end_cinematic"):
		player.end_cinematic()
	hopped.emit()


func _landing() -> Vector3:
	if landing_path != NodePath():
		var m := get_node_or_null(landing_path) as Node3D
		if m != null:
			return m.global_position
	return landing_position
