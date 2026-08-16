extends Node
## Eyes on the beats that were reported broken: the top of the pillar, the
## corridor's far end, the look back, the bathroom coming up close, the seam
## into the chase, and the break-in. Run windowed (it needs a GPU context,
## headless cannot screenshot):
##   godot --path . res://tools/FixShots.tscn
## REVIEW_OUT picks the folder. Never shipped.

const LEVEL := "res://real_world.tscn"
const Rooms := preload("res://scripts/dream_rooms.gd")

var out_dir := ""
var _level: Node
var _player: CharacterBody3D
var _dream: Node
var _chase: Node


func _ready() -> void:
	out_dir = OS.get_environment("REVIEW_OUT")
	if out_dir.is_empty():
		out_dir = "user://fix_review"
	DirAccess.make_dir_recursive_absolute(out_dir)
	AudioBus.unlock()
	_run()


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(shot_name + ".png"))
	print("  shot %s" % shot_name)


func _run_room() -> Dictionary:
	return _dream.get("run") as Dictionary


func _hall() -> Dictionary:
	return _dream.get("hall") as Dictionary


func _fwd() -> Vector3:
	return ((_run_room()["root"] as Node3D).transform.basis * Vector3(0, 0, 1)).normalized()


func _face(dir: Vector3, pitch := 0.0) -> void:
	var d := Vector3(dir.x, 0.0, dir.z)
	if d.length() > 0.001:
		d = d.normalized()
		_player.rotation.y = atan2(-d.x, -d.z)
	_player.sync_look_from_transform()
	var head: Node3D = _player.get("_head")
	if head != null:
		head.rotation.x = pitch
	_player.set("_pitch", pitch)
	_player.set("_pitch_target", pitch)


## Presence waits out the eyelid intro before it starts any director, so the
## world does not exist for the first few seconds. Wait for it, not for a clock.
func _boot(mode: String) -> void:
	OS.set_environment("DREAM", mode)
	OS.set_environment("CHASE", "")
	await get_tree().process_frame
	_level = (load(LEVEL) as PackedScene).instantiate()
	get_tree().root.add_child(_level)
	await _wait(0.5)
	_player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	_dream = _level.get_node_or_null("Dream")
	_chase = _level.get_node_or_null("Chase")
	_player.test_drive = true
	var waited := 0.0
	while (_dream.get("hall") as Dictionary).is_empty() and waited < 20.0:
		await _wait(0.2)
		waited += 0.2
	Fade.clear_deferred()
	await _wait(0.4)


func _shut_down() -> void:
	if _level != null and is_instance_valid(_level):
		_level.queue_free()
	_level = null
	_dream = null
	_chase = null
	await _wait(0.8)


func _run() -> void:
	print("FIX SHOTS -> %s" % out_dir)
	await _the_platform()
	await _the_corridor()
	await _the_break_in()
	print("done")
	get_tree().quit(0)


## The top of the pillar: the landing you can now step onto, and the bear
## standing on its plinth instead of hanging in the air beside it.
func _the_platform() -> void:
	await _boot("top")
	var h := _hall()
	var root := h["root"] as Node3D
	var a_end := Rooms.START_ANGLE + Rooms.STEP_TURN * float(Rooms.STEP_COUNT)
	var r_mid := Rooms.PILLAR_R + Rooms.STAIR_W * 0.5

	# from the last step, looking across the landing at the plinth
	var a := a_end - 0.30
	_player.teleport_to(root.transform * (Rooms.PILLAR_C
		+ Vector3(cos(a), 0.0, sin(a)) * r_mid + Vector3(0.0, Rooms.TOP_Y - 0.12, 0.0)))
	_face(root.transform * (Rooms.PILLAR_C + Vector3(0.0, Rooms.TOP_Y, 0.0))
		- _player.global_position, -0.25)
	await _wait(0.5)
	await _shot("01_top_of_the_flight")

	# and standing at it
	a = a_end + 0.5
	_player.teleport_to(root.transform * (Rooms.PILLAR_C
		+ Vector3(cos(a), 0.0, sin(a)) * 2.2 + Vector3(0.0, Rooms.TOP_Y + 0.05, 0.0)))
	_face(root.transform * (h["toy_at"] as Vector3) - _player.global_position, -0.30)
	await _wait(0.5)
	await _shot("02_the_bear_on_its_plinth")
	await _shut_down()


## The corridor: what the far end looks like while you run at it, the way back
## when you finally turn round, and the bathroom once it has walked up to you.
func _the_corridor() -> void:
	await _boot("hall")
	var waited := 0.0
	while int(_dream.get("stage")) != 8 and waited < 20.0:
		await _wait(0.2)
		waited += 0.2
	await _wait(0.5)
	await _shot("03_corridor_from_the_start")

	var fwd := _fwd()
	var t := 0.0
	var shot_mid := false
	while int(_dream.get("_run_step")) == 0 and t < 60.0:
		_face(fwd)
		_player.test_input = Vector2(0.0, -1.0)
		_player.test_run = true
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if not shot_mid and float(_dream.get("_run_far")) > 16.0:
			shot_mid = true
			_player.test_input = Vector2.ZERO
			await _wait(0.4)
			await _shot("04_running_at_it")
	_player.test_input = Vector2.ZERO
	_player.test_run = false
	await _wait(0.4)
	await _shot("05_still_running_at_it")

	# turn round
	_face(-fwd)
	await _wait(0.9)
	await _shot("06_the_door_you_started_at")

	# and back
	_face(fwd)
	await _wait(0.9)
	await _shot("07_and_there_it_is")

	# walk into it until it shuts
	var node := (_run_room()["bath"] as Dictionary)["node"] as Node3D
	waited = 0.0
	while int(_dream.get("stage")) != 9 and waited < 20.0:
		_face(node.global_position - _player.global_position)
		_player.test_input = Vector2(0.0, -1.0)
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	_player.test_input = Vector2.ZERO
	await _wait(0.8)
	await _shot("08_shut_in_your_face")

	waited = 0.0
	while not bool(_dream.get("_chase_ready")) and waited < 20.0:
		await _wait(0.2)
		waited += 0.2
	var door := (_run_room()["bath"] as Dictionary)["door"] as MeshInstance3D
	if door != null:
		door.call("interact", _player)
	await _wait(0.5)
	await _shot("09_the_hallway_in_its_place")
	await _shut_down()


## The break-in, frame by frame through the lunge.
func _the_break_in() -> void:
	OS.set_environment("DREAM", "")
	OS.set_environment("CHASE", "rooms")
	await get_tree().process_frame
	_level = (load(LEVEL) as PackedScene).instantiate()
	get_tree().root.add_child(_level)
	await _wait(0.5)
	_player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	_chase = _level.get_node_or_null("Chase")
	if _chase == null:
		return
	var waited := 0.0
	while int(_chase.get("stage")) == 0 and waited < 20.0:
		await _wait(0.2)
		waited += 0.2
	Fade.clear_deferred()
	await _wait(0.4)
	_chase.call("_enter_bathroom")
	await _wait(1.0)
	await _shot("10_cornered_in_the_bathroom")

	var bath := Presence.get_door("Door_005")
	_chase.set("_ending", true)
	_chase.call("_break_in", bath, Vector3(6.05, 4.75, -6.186702), null)
	var at := 0.0
	for i in 8:
		await _wait(0.1)
		at += 0.1
		await _shot("11_break_in_%03d" % int(at * 100.0))
