extends Node
## Self-review tool for the chase: boots straight into the hallways, stands the
## kid in each room type, saves PNGs, quits. Run windowed (it needs a GPU
## context, headless cannot screenshot):
##   godot --path . res://tools/ChaseShots.tscn
## REVIEW_OUT picks the folder, CHASE_SEQ the room order. Never shipped.

const LEVEL := "res://real_world.tscn"
const SEQ := "long,donut,stairs,garden,long,donut,stairs,garden,long,donut"

var out_dir := ""
var _level: Node
var _player: CharacterBody3D
var _chase: Node


func _ready() -> void:
	out_dir = OS.get_environment("REVIEW_OUT")
	if out_dir.is_empty():
		out_dir = "user://chase_review"
	OS.set_environment("CHASE", "rooms")
	if OS.get_environment("CHASE_SEQ").is_empty():
		OS.set_environment("CHASE_SEQ", SEQ)
	AudioBus.unlock()
	_run()


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _look(pos: Vector3, at: Vector3) -> void:
	_player.teleport_to(pos)
	var d := at - pos
	d.y = 0.0
	if d.length() > 0.01:
		d = d.normalized()
		_player.rotation.y = atan2(-d.x, -d.z)
	_player.sync_look_from_transform()
	var head: Node3D = _player.get("_head")
	if head != null:
		head.rotation.x = clampf(atan2(at.y - (pos.y + 1.1), (at - pos).length()), -0.6, 0.6)


func _shot(shot_name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await _wait(0.35)
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(shot_name + ".png"))
	print("  ", shot_name)


func _room_of(type: String, skip := 0) -> Dictionary:
	var rooms: Array = _chase.get("rooms")
	var seen := 0
	for r: Dictionary in rooms:
		if String(r["type"]) == type:
			if seen == skip:
				return r
			seen += 1
	return {}


func _world(r: Dictionary, local: Vector3) -> Vector3:
	return (r["root"] as Node3D).transform * local


## The director keeps only the rooms either side of you in the picture, and it
## does that off the entry triggers. This tool teleports instead of walking, so
## it has to say where it is or every shot past the first room comes out black.
func _enter(r: Dictionary) -> void:
	if r.is_empty() or _chase == null:
		return
	var rooms: Array = _chase.get("rooms")
	var i := rooms.find(r)
	if i >= 0:
		_chase.set("current_room", i)
		_chase.call("_cull_rooms", i)


## The last room of its type in the chain, i.e. the most rotted one.
func _deepest_of(type: String) -> Dictionary:
	var rooms: Array = _chase.get("rooms")
	var out := {}
	for r: Dictionary in rooms:
		if String(r["type"]) == type:
			out = r
	return out


func _run() -> void:
	# the root is still adding this tool when _ready runs
	await get_tree().process_frame
	_level = (load(LEVEL) as PackedScene).instantiate()
	get_tree().root.add_child(_level)
	await _wait(1.0)
	_player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	_chase = _level.get_node_or_null("Chase")
	var waited := 0.0
	while (_chase == null or int(_chase.get("stage")) < 2) and waited < 25.0:
		await _wait(0.25)
		waited += 0.25
		_chase = _level.get_node_or_null("Chase")
	if _chase == null or int(_chase.get("stage")) < 2:
		print("CHASE SHOTS: the chase never started")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(out_dir)
	for r: Dictionary in (_chase.get("rooms") as Array):
		var lit := 0
		var energy := 0.0
		for l: OmniLight3D in (r["lights"] as Array):
			if is_instance_valid(l) and l.visible:
				lit += 1
				energy += l.light_energy
		print("  %-10s lights=%d lit=%d energy=%.2f shafts=%d panes=%d" % [
			r["type"], (r["lights"] as Array).size(), lit, energy,
			(r["shafts"] as Array).size(), (r["panes"] as Array).size()])
	# the start screen normally clears this; booting the level straight leaves
	# the screen black
	Fade.clear_deferred()
	# the level's key hint would sit in the middle of every shot
	var info := _level.get_node_or_null("DialogueLayer/info ui")
	if info != null:
		(info as CanvasItem).visible = false
	await _wait(0.3)
	_player.can_move = false
	print("chase shots -> ", out_dir)

	var vest := _room_of("vestibule")
	_look(_world(vest, Vector3(5.44, 3.7316, -7.1)), _world(vest, Vector3(6.05, 4.7, -6.19)))
	await _shot("vestibule")

	var long_room := _room_of("long")
	if not long_room.is_empty():
		_enter(long_room)
		_look(_world(long_room, Vector3(0.0, 0.0, 1.2)), _world(long_room, Vector3(0.0, 1.5, 14.0)))
		await _shot("long")

	var donut := _room_of("donut")
	if not donut.is_empty():
		_enter(donut)
		_look(_world(donut, Vector3(0.0, 0.0, 1.4)), _world(donut, Vector3(0.0, 1.4, 8.0)))
		await _shot("donut_entry")
		_look(_world(donut, Vector3(-4.6, 0.0, 6.4)), _world(donut, Vector3(-4.2, 1.4, 10.5)))
		await _shot("donut_side")
		# what came down, and what is jammed the other way
		for c: Dictionary in (donut["crawls"] as Array):
			var gap := c["aabb"] as AABB
			var thr := (c["through"] as Vector3).normalized()
			for ev: Dictionary in (donut["events"] as Array):
				(ev["play"] as Callable).call(_player)
			await _wait(1.2)
			_look(_world(donut, gap.get_center() - thr * 2.6 - Vector3(0.0, gap.size.y * 0.5, 0.0)),
				_world(donut, gap.get_center()))
			await _shot("donut_collapse")
			break

	# the deepest hallway there is, mess and all
	var deep := _deepest_of("long")
	if not deep.is_empty():
		_enter(deep)
		_look(_world(deep, Vector3(0.0, 0.0, 1.2)), _world(deep, Vector3(0.0, 1.5, 14.0)))
		await _shot("long_deep")
		for c: Dictionary in (deep["crawls"] as Array):
			var gap := c["aabb"] as AABB
			_look(_world(deep, gap.get_center() - Vector3(0.0, gap.size.y * 0.5, 0.0) + Vector3(0.0, 0.0, -2.8)),
				_world(deep, gap.get_center()))
			await _shot("long_crawl")
			break

	var stairs := _room_of("stairs")
	if not stairs.is_empty():
		_enter(stairs)
		# the branch is on either side depending on the variant that fitted
		var sx := signf((stairs["exit_portal"] as Transform3D).origin.x)
		_look(_world(stairs, Vector3(0.0, 0.0, 4.0)), _world(stairs, Vector3(sx * 3.2, -0.5, 4.0)))
		await _shot("stairs_top")
		_look(_world(stairs, Vector3(sx * 5.14, -1.44, 4.4)), _world(stairs, Vector3(sx * 5.14, -0.8, 9.0)))
		await _shot("stairs_lower")

	var garden := _room_of("garden")
	if not garden.is_empty():
		# the rain only falls in the room you are actually standing in, and the
		# shot tool never walks, so tell the director where we are
		_enter(garden)
		_look(_world(garden, Vector3(0.0, 0.0, 1.5)), _world(garden, Vector3(0.0, 2.2, 12.0)))
		await _shot("garden")
		_look(_world(garden, Vector3(0.0, 0.0, 4.0)), _world(garden, Vector3(0.6, 3.0, 9.0)))
		await _shot("garden_rain")
		_chase.set("current_room", -1)

	# the thing itself, three metres off, in a lit hall
	var monster := _chase.get("monster") as Node3D
	if monster != null and not long_room.is_empty():
		_enter(long_room)
		_look(_world(long_room, Vector3(0.0, 0.0, 2.0)), _world(long_room, Vector3(0.0, 1.4, 10.0)))
		monster.call("enter_room", long_room["world_graph"], _world(long_room, Vector3(0.0, 0.0, 5.2)))
		monster.set("state", 3)
		await _wait(0.6)
		monster.global_position = _world(long_room, Vector3(0.0, 0.0, 5.2))
		await _shot("monster_close")
		monster.global_position = _world(long_room, Vector3(0.0, 0.0, 12.0))
		await _shot("monster_far")
		monster.call("vanish", 0.0)

	_chase.call("_enter_bathroom")
	await _wait(1.2)
	_look(Vector3(8.3, 3.7316, -6.0), Vector3(6.05, 4.6, -6.19))
	await _shot("bathroom_end")
	get_tree().quit()
