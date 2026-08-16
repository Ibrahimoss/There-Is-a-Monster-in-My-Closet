extends Node3D

## The way back up. Reaching this turns the world the right way up again, a
## door shuts somewhere behind him, and he talks himself down from it.
##
## Proximity rather than an Area3D, because this node has no collision shape
## — walk inside `radius` and it fires. Once only.

signal returned

## Horizontal reach. A plain sphere caught him from the sewer running above
## this spot, so the check is a standing-height cylinder instead: he has to
## be beside it AND on roughly the same level.
@export var radius := 1.3
## How far above or below still counts. Keep this under the floor-to-floor
## height or the sewer overhead will trip it again.
@export var height_tolerance := 1.4
## Turn gravity back the right way up on arrival.
@export var restore_gravity := true
## The house was made non-solid for the sewer; make it real again so he does
## not drop through the floor on the way back.
@export var restore_house_collision := true
## Doors the act locked that should open again now he is back. The bathroom
## is where the story goes next, so it stops being a "not here".
@export var unlock_doors: PackedStringArray = ["bathroom door"]
## Whatever was following him goes with the upside-down world.
@export var scare_trigger_path: NodePath = NodePath("../trigger bad")

@export_group("Sound")
## The slam. door_close on its own is a light latch click, so a heavy wood
## impact is layered under it to give the door some weight.
@export var slam_sounds: PackedStringArray = ["door_close", "closet_thump"]
## Played flat rather than positionally: a door slamming behind you should
## land the same wherever you are standing, not fade with distance.
@export var slam_volume_db := 3.0
## The thump lands a hair after the latch, the way a real door does.
@export var slam_layer_delay := 0.05

@export_group("Lines")
## In order, with the pause after each.
@export var lines: PackedStringArray = ["was it......", "dad?", "i need to find squibble"]
## Beat before he says anything at all.
@export var lead_in := 0.9
@export var line_gap := 2.2

var _fired := false
var _player: Node3D


func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player") as Node3D


func _process(_dt: float) -> void:
	if _fired:
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
		return
	var here: Vector3 = _player.global_position
	var flat := Vector2(here.x - global_position.x, here.z - global_position.z).length()
	if flat <= radius and absf(here.y - global_position.y) <= height_tolerance:
		_fired = true
		set_process(false)
		_arrive()


func _arrive() -> void:
	var act := get_parent()

	# the world rights itself first, so the door lands on a steady picture
	if restore_gravity and act != null and act.has_method("set_gravity_flipped"):
		await act.set_gravity_flipped(false)
	if restore_house_collision and act != null and act.has_method("set_house_collision"):
		act.set_house_collision(true)
	_unlock()

	# the right way up, so he is not there any more
	var scare := get_node_or_null(scare_trigger_path)
	if scare != null and scare.has_method("dismiss"):
		scare.dismiss()

	_door()

	await _wait(lead_in)
	for line in lines:
		_say(line)
		await _wait(line_gap)
	returned.emit()


## Open up the doors this act had shut. Goes through Presence's registry when
## it is there, by name otherwise, so it works in a bare scene too.
func _unlock() -> void:
	for door_name in unlock_doors:
		var door := _find_door(door_name)
		if door == null:
			push_warning("ReturnPoint: no door named '%s' to unlock." % door_name)
			continue
		door.set("locked", false)


func _find_door(door_name: String) -> Node:
	var presence := get_node_or_null("/root/Presence")
	if presence != null and presence.has_method("get_door"):
		var d: Node = presence.get_door(door_name)
		if d != null:
			return d
	var found := _level().find_child(door_name, true, false)
	return found if (found != null and "locked" in found) else null


func _door() -> void:
	var bus := get_node_or_null("/root/AudioBus")
	if bus == null or not bus.has_method("sfx"):
		return
	for i in slam_sounds.size():
		if i > 0:
			await _wait(slam_layer_delay)
		# pitched down a little; these samples are small doors by default
		bus.sfx(slam_sounds[i], slam_volume_db, 0.04)


## current_scene is null when the level is loaded by hand, so climb our own
## branch rather than trusting it.
func _level() -> Node:
	var scene: Node = get_tree().current_scene
	if scene != null:
		return scene
	scene = self
	while scene.get_parent() != null and scene.get_parent() != get_tree().root:
		scene = scene.get_parent()
	return scene


func _say(text: String) -> void:
	var scene := _level()
	var ui := scene.find_child("dialouge ui", true, false)
	if ui != null and ui.has_method("play"):
		ui.play([text])
	else:
		push_warning("ReturnPoint: no dialogue ui for '%s'" % text)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
