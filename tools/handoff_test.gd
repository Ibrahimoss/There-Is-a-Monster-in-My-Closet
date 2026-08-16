extends Node
## The one seam in the game that is not allowed to be a seam: the dream's
## endless corridor becoming the chase.
##
## The bathroom is taken away behind a shut door and the hallways are built out
## of that same doorway, so opening it a second time reveals the chase with no
## fade, no cut and nobody moved. This drives the whole corridor beat and then
## checks exactly that.
## Run:
##   godot --headless --path . res://tools/HandoffTest.tscn
## Prints HANDOFF OK / HANDOFF FAIL. Never shipped.

const LEVEL := "res://real_world.tscn"
const Rooms := preload("res://scripts/dream_rooms.gd")

var _level: Node
var _player: CharacterBody3D
var _dream: Node
var _chase: Node
var _fail := 0


func _ready() -> void:
	_run()


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _check(check_name: String, ok: bool, detail := "") -> void:
	if not ok:
		_fail += 1
	print("  %-46s %s %s" % [check_name, "ok" if ok else "FAIL", detail])


func _run_room() -> Dictionary:
	return _dream.get("run") as Dictionary


func _fwd() -> Vector3:
	return ((_run_room()["root"] as Node3D).transform.basis * Vector3(0, 0, 1)).normalized()


func _face(dir: Vector3) -> void:
	var d := Vector3(dir.x, 0.0, dir.z)
	if d.length() < 0.001:
		return
	d = d.normalized()
	_player.rotation.y = atan2(-d.x, -d.z)
	_player.sync_look_from_transform()


func _hold(dir: Vector3, secs: float, run := true) -> void:
	var t := 0.0
	while t < secs:
		_face(dir)
		_player.test_input = Vector2(0.0, -1.0)
		_player.test_run = run
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	_player.test_input = Vector2.ZERO
	_player.test_run = false


func _fade_alpha() -> float:
	var rect := Fade.get("_rect") as ColorRect
	return rect.color.a if rect != null else -1.0


func _run() -> void:
	print("HANDOFF TEST")
	AudioBus.unlock()
	Engine.time_scale = 4.0
	OS.set_environment("DREAM", "hall")
	OS.set_environment("CHASE", "")
	await get_tree().process_frame

	_level = (load(LEVEL) as PackedScene).instantiate()
	get_tree().root.add_child(_level)
	await _wait(1.5)
	_player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	_dream = _level.get_node_or_null("Dream")
	_chase = _level.get_node_or_null("Chase")
	_check("level up, player found", _player != null)
	_check("Dream and Chase both attached", _dream != null and _chase != null)
	if _player == null or _dream == null or _chase == null:
		_done()
		return
	_player.test_drive = true
	Fade.clear_deferred()

	var waited := 0.0
	while int(_dream.get("stage")) != 8 and waited < 12.0:
		await _wait(0.2)
		waited += 0.2
	_check("dropped straight into the corridor", int(_dream.get("stage")) == 8,
		"stage %d" % int(_dream.get("stage")))
	if int(_dream.get("stage")) != 8:
		_done()
		return

	await _the_run()
	await _the_reveal()
	await _the_handoff()
	await _the_first_hallway()
	_done()


## Run at it until the corridor gives up. Nothing should get closer and nothing
## should get further away.
func _the_run() -> void:
	var fwd := _fwd()
	var t := 0.0
	while int(_dream.get("_run_step")) == 0 and t < 60.0:
		_face(fwd)
		_player.test_input = Vector2(0.0, -1.0)
		_player.test_run = true
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	_player.test_input = Vector2.ZERO
	_player.test_run = false
	_check("ran far enough for the corridor to give up",
		int(_dream.get("_run_step")) == 1, "%.0f m" % float(_dream.get("_run_far")))


## Look back — the way out of the pillow hall is a few strides away — and the
## bathroom is set down close while your eyes are off it.
func _the_reveal() -> void:
	var r := _run_room()
	var kept := (_dream.get("hall") as Dictionary)["exit_door"] as MeshInstance3D
	if kept != null and is_instance_valid(kept):
		var behind := _player.global_position.distance_to(kept.global_position)
		_check("the door you started at is right behind you", behind < 9.0, "%.1f m" % behind)
	_face(-_fwd())
	var waited := 0.0
	while int(_dream.get("_run_step")) != 2 and waited < 6.0:
		await _wait(0.1)
		waited += 0.1
	_check("looking back moves the bathroom up", int(_dream.get("_run_step")) == 2)

	_face(_fwd())
	waited = 0.0
	while not bool(_dream.get("_door_stopped")) and waited < 6.0:
		await _wait(0.1)
		waited += 0.1
	_check("and it is standing there when you turn round", bool(_dream.get("_door_stopped")))

	# walk into it until it shuts
	var node := (r["bath"] as Dictionary)["node"] as Node3D
	waited = 0.0
	while int(_dream.get("stage")) != 9 and waited < 20.0:
		_face(node.global_position - _player.global_position)
		_player.test_input = Vector2(0.0, -1.0)
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	_player.test_input = Vector2.ZERO
	_check("it shuts before you reach it", int(_dream.get("stage")) == 9,
		"stage %d" % int(_dream.get("stage")))


## The whole point. Behind the shut panel the bathroom goes and ten hallways
## are built out of the doorway; opening it must change nothing else at all.
func _the_handoff() -> void:
	var waited := 0.0
	while not bool(_dream.get("_chase_ready")) and waited < 20.0:
		await _wait(0.2)
		waited += 0.2
	_check("the chase is built behind the shut door", bool(_dream.get("_chase_ready")),
		"%.1fs" % waited)
	if not bool(_dream.get("_chase_ready")):
		return

	var rooms: Array = _chase.get("rooms")
	_check("the whole chain is there", rooms.size() == 12, "%d rooms" % rooms.size())
	_check("its room zero is the corridor you are standing in",
		rooms.size() > 0 and rooms[0]["root"] == (_run_room()["root"] as Node3D))
	var bath_door := (_run_room()["bath"] as Dictionary)["door"] as MeshInstance3D
	_check("and its way out is the bathroom door",
		rooms.size() > 0 and rooms[0]["exit_door"] == bath_door)
	if rooms.size() > 1:
		var portal := (_run_room()["root"] as Node3D).transform \
			* ((_run_room()["bath"] as Dictionary)["node"] as Node3D).position \
			+ (_run_room()["root"] as Node3D).transform.basis * Vector3(0.0, 0.0, 0.15)
		var first := (rooms[1]["root"] as Node3D).global_position
		_check("the first hallway starts at that doorway", first.distance_to(portal) < 0.5,
			"%.2f m off" % first.distance_to(portal))
	_check("nothing has been faded yet", _fade_alpha() < 0.02, "alpha %.2f" % _fade_alpha())
	_check("the chase has not started running", int(_chase.get("stage")) == 0,
		"stage %d" % int(_chase.get("stage")))

	# open it
	var was := _player.global_position
	if bath_door != null:
		bath_door.call("interact", _player)
	await _wait(0.4)
	_check("opening it starts the chase", int(_chase.get("stage")) == 3,
		"stage %d" % int(_chase.get("stage")))
	_check("and nobody was moved", _player.global_position.distance_to(was) < 1.0,
		"%.2f m" % _player.global_position.distance_to(was))
	_check("no fade over the seam", _fade_alpha() < 0.02, "alpha %.2f" % _fade_alpha())
	_check("the dream let go", int(_dream.get("stage")) == 10)
	_check("the corridor is still standing", is_instance_valid(_run_room()["root"] as Node3D)
		and (_run_room()["root"] as Node3D).visible)


## Through the doorway, into hallway one. It has to shut the bathroom door
## behind the kid and start hammering on it.
func _the_first_hallway() -> void:
	var rooms: Array = _chase.get("rooms")
	if rooms.size() < 2:
		return
	var goal := rooms[1]["spawn_world"] as Vector3
	var t := 0.0
	while int(_chase.get("current_room")) < 1 and t < 30.0:
		_face(goal - _player.global_position)
		_player.test_input = Vector2(0.0, -1.0)
		_player.test_run = true
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	_player.test_input = Vector2.ZERO
	_player.test_run = false
	_check("walked out of the corridor into the first hallway",
		int(_chase.get("current_room")) == 1, "room %d" % int(_chase.get("current_room")))

	var door := rooms[0]["exit_door"] as MeshInstance3D
	var waited := 0.0
	while waited < 4.0 and not bool(door.get("locked")):
		await _wait(0.2)
		waited += 0.2
	_check("the way back shuts and locks behind you", bool(door.get("locked")),
		"%.1fs" % waited)

	# and then it comes through it
	waited = 0.0
	var m: Node3D = null
	while waited < 12.0:
		m = _chase.get("monster") as Node3D
		if m != null and is_instance_valid(m) and bool(m.get("visible_now")):
			break
		await _wait(0.25)
		waited += 0.25
	_check("and something comes through it", m != null and bool(m.get("visible_now")),
		"%.1fs" % waited)


func _done() -> void:
	Engine.time_scale = 1.0
	print("HANDOFF OK" if _fail == 0 else "HANDOFF FAIL (%d)" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
