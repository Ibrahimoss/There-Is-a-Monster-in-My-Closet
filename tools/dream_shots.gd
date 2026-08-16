extends Node
## Self-review tool for the dream act: boots into the pillow hall, stands the
## kid at every beat of it, saves PNGs, quits. Run windowed (it needs a GPU
## context, headless cannot screenshot):
##   godot --path . res://tools/DreamShots.tscn
## REVIEW_OUT picks the folder. Never shipped.

const LEVEL := "res://real_world.tscn"
const Rooms := preload("res://scripts/dream_rooms.gd")

var out_dir := ""
var _level: Node
var _player: CharacterBody3D
var _dream: Node


func _ready() -> void:
	out_dir = OS.get_environment("REVIEW_OUT")
	if out_dir.is_empty():
		out_dir = "user://dream_review"
	OS.set_environment("DREAM", "1")
	OS.set_environment("CHASE", "")
	AudioBus.unlock()
	_run()


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _hall() -> Dictionary:
	return _dream.get("hall") as Dictionary


func _world(room: Dictionary, local: Vector3) -> Vector3:
	return (room["root"] as Node3D).transform * local


## Stand the kid somewhere and point them at something. Pitch is set on the head
## directly, which is the only way to aim up at a beam thirty metres over you.
func _look(pos: Vector3, at: Vector3, pitch_limit := 1.2) -> void:
	_player.teleport_to(pos)
	var d := at - pos
	d.y = 0.0
	if d.length() > 0.01:
		d = d.normalized()
		_player.rotation.y = atan2(-d.x, -d.z)
	_player.sync_look_from_transform()
	var head: Node3D = _player.get("_head")
	if head != null:
		head.rotation.x = clampf(atan2(at.y - (pos.y + 1.1), Vector2(d.x, d.z).length() * 0.0
			+ (at - pos).length()), -pitch_limit, pitch_limit)


func _shot(shot_name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await _wait(0.4)
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(shot_name + ".png"))
	print("  ", shot_name)


func _run() -> void:
	print("DREAM SHOTS -> ", out_dir)
	DirAccess.make_dir_recursive_absolute(out_dir)
	await get_tree().process_frame
	_level = (load(LEVEL) as PackedScene).instantiate()
	get_tree().root.add_child(_level)
	await _wait(1.5)

	_player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	_dream = _level.get_node_or_null("Dream")
	if _player == null or _dream == null:
		print("  no player or no Dream")
		get_tree().quit(1)
		return
	var waited := 0.0
	while (_dream.get("hall") as Dictionary).is_empty() and waited < 15.0:
		await _wait(0.2)
		waited += 0.2
	Fade.clear_deferred()
	var info := _level.get_node_or_null("DialogueLayer/info ui")
	if info != null:
		(info as CanvasItem).visible = false
	_player.can_move = false
	# the triggers would run the sequence out from under the camera
	for key: String in ["entry_trigger", "top_trigger", "stair_trigger"]:
		var a := _hall()[key] as Area3D
		if a != null:
			a.monitoring = false
	_dream.set_process(true)

	var h := _hall()
	var pillar := _world(h, Rooms.PILLAR_C)
	var toy_at := _world(h, h["toy_at"] as Vector3)
	var door := h["entry_door"] as MeshInstance3D
	if door != null:
		door.call("snap_open", true)

	# walking in
	_look(_world(h, Vector3(0.0, 0.0, -2.2)), _world(h, Vector3(0.0, 3.0, 20.0)))
	await _shot("01_stub")
	_look(_world(h, Vector3(0.0, 0.0, 2.5)), pillar + Vector3(0.0, 10.0, 0.0))
	await _shot("02_reveal")
	_look(_world(h, Vector3(0.0, 0.0, 6.0)), _world(h, Vector3(0.0, 0.0, 8.0)))
	var head: Node3D = _player.get("_head")
	if head != null:
		head.rotation.x = -0.85
	await _shot("03_floor")
	_look(_world(h, Vector3(6.0, 0.0, 12.0)), _world(h, Vector3(-Rooms.HALL_W * 0.5, 8.0, 15.0)))
	await _shot("04_windows")
	_look(_world(h, Vector3(-4.0, 0.0, 8.0)), toy_at)
	await _shot("05_beam_from_below")

	# the climb
	_look(_world(h, (h["stair_foot"] as Vector3) + Vector3(0.0, 0.0, -1.6)),
		_world(h, (h["stair_foot"] as Vector3) + Vector3(0.0, 1.5, 0.0)))
	await _shot("06_stair_foot")
	var pts := h["stair_points"] as Array
	_look(_world(h, (pts[40] as Vector3) + Vector3(0.0, 0.02, 0.0)),
		_world(h, (pts[48] as Vector3) + Vector3(0.0, 1.4, 0.0)))
	await _shot("07_stair_mid")
	if _dream.get("toy") != null:
		(_dream.get("toy") as Node3D).call("set_dissolve", 0.55)
	# from across the room, not from under the landing
	_look(_world(h, Vector3(-7.0, 0.0, 12.0)), toy_at)
	await _shot("08_toy_burning")

	# the top
	_look(_world(h, Rooms.PILLAR_C + Vector3(1.4, Rooms.TOP_Y, -1.4)), toy_at)
	await _shot("09_platform")
	if _dream.get("toy") != null:
		(_dream.get("toy") as Node3D).call("set_dissolve", 0.92)
	await _shot("10_toy_gone")
	_look(_world(h, Rooms.PILLAR_C + Vector3(0.0, Rooms.TOP_Y, 0.0)),
		_world(h, Vector3(-Rooms.HALL_W * 0.5, 8.0, 15.0)))
	await _shot("11_from_the_top")

	# the thing at the glass, and the flight going with it
	var spots := h["window_spots"] as Array
	var eye := _world(h, Rooms.PILLAR_C + Vector3(0.0, Rooms.TOP_Y, 0.0))
	var face := _world(h, (spots[0] as Vector3) + Vector3(0.0, 13.0, 0.0))
	_dream.call("_spawn_monster", _world(h, spots[0] as Vector3))
	await _wait(1.8)
	_look(eye, face)
	_dream.set("_roar", 0.0)
	await _shot("12_monster_behind_stairs")
	_dream.call("_collapse_flight")
	await _wait(1.2)
	_look(eye, face)
	await _shot("13_flight_coming_down")
	await _wait(2.4)
	_look(eye, face)
	await _shot("14_full_view")
	_dream.set("_roar", 1.0)
	_dream.set("_dread", 1.0)
	_dream.set("_seen", 1.0)
	await _shot("15_scream")
	_dream.set("_roar", 0.0)
	_dream.set("_dread", 0.0)
	_dream.set("_seen", 0.0)

	# concussed
	_dream.set("_stun", 0.9)
	_dream.set("_stun_want", 0.9)
	_look(_world(h, Vector3(2.0, 0.0, 17.0)), _world(h, Rooms.PILLAR_C + Vector3(0.0, 11.0, 0.0)))
	await _shot("16_stunned")
	_dream.set("_stun", 0.0)
	_dream.set("_stun_want", 0.0)

	# the dark
	_dream.call("_start_dark")
	_dream.set("_dark_z", 30.0)
	await _wait(1.8)
	_look(_world(h, Vector3(8.0, 0.0, 8.0)), _world(h, Vector3(-2.0, 6.0, 28.0)))
	await _shot("17_smoke")
	_look(_world(h, Vector3(2.0, 0.0, 20.0)), _world(h, Vector3(0.0, 3.0, 30.0)))
	await _shot("18_smoke_close")
	_look(_world(h, Vector3(4.0, 0.0, 14.0)),
		_world(h, Vector3(Rooms.HALL_W * 0.5, 1.4, Rooms.EXIT_Z)))
	await _shot("19_way_out")

	# the corridor
	var r := _dream.get("run") as Dictionary
	var bath: Dictionary = r["bath"]
	var node := bath["node"] as Node3D
	_dream.call("_enter_run")
	_player.teleport_to(_world(r, Vector3(0.0, 0.0, 3.0)))
	await _wait(0.6)
	_look(_world(r, Vector3(0.0, 0.0, 3.0)), _world(r, Vector3(0.0, 1.4, 60.0)))
	await _shot("20_corridor")
	# and up close, which is the only place the bathroom is ever seen from
	_dream.set("_door_stopped", true)
	node.position.z = 6.4
	await _wait(0.5)
	_look(_world(r, Vector3(0.0, 0.0, 3.0)), _world(r, Vector3(0.0, 1.25, 12.0)))
	await _shot("21_bathroom")

	print("DREAM SHOTS DONE")
	get_tree().quit(0)
