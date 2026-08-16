extends Node
## Headless run of the dream act on the real level: the pillow hall's geometry,
## the spiral flight walked step by step, the toy burning off, the fall, the
## dark, and the corridor that repeats itself.
## Run:
##   godot --headless --path . res://tools/DreamTest.tscn
## Prints DREAM OK / DREAM FAIL. Never shipped.

const LEVEL := "res://real_world.tscn"
const Rooms := preload("res://scripts/dream_rooms.gd")
const Kit := preload("res://scripts/chase_kit.gd")

var _level: Node
var _player: CharacterBody3D
var _dream: Node
var _fail := 0
var _finished := false


func _ready() -> void:
	_run()


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _check(check_name: String, ok: bool, detail := "") -> void:
	if not ok:
		_fail += 1
	print("  %-44s %s %s" % [check_name, "ok" if ok else "FAIL", detail])


func _hall() -> Dictionary:
	return _dream.get("hall") as Dictionary


func _run_room() -> Dictionary:
	return _dream.get("run") as Dictionary


func _world(room: Dictionary, local: Vector3) -> Vector3:
	return (room["root"] as Node3D).transform * local


func _local(room: Dictionary, at: Vector3) -> Vector3:
	return (room["root"] as Node3D).transform.affine_inverse() * at


# --- autoplayer ---------------------------------------------------------------

func _face(dir: Vector3) -> void:
	var d := Vector3(dir.x, 0.0, dir.z)
	if d.length() < 0.001:
		return
	d = d.normalized()
	_player.rotation.y = atan2(-d.x, -d.z)
	_player.sync_look_from_transform()


func _walk_to(pos: Vector3, timeout: float, stop_at := 0.55, report := true) -> bool:
	var t := 0.0
	while t < timeout:
		var to := pos - _player.global_position
		to.y = 0.0
		if to.length() < stop_at:
			_player.test_input = Vector2.ZERO
			return true
		_face(to)
		_player.test_input = Vector2(0.0, -1.0)
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	_player.test_input = Vector2.ZERO
	if report:
		print("    stuck short of %s at %s: %s" % [pos, _player.global_position, _overlaps()])
	return false


## What the capsule last slid against and what it is standing inside, for when
## a walk does not get where it was sent.
func _overlaps() -> String:
	var out := "v=%.2f cin=%s move=%s" % [_player.velocity.length(),
		_player.get("cinematic"), _player.can_move]
	for i in _player.get_slide_collision_count():
		var c := _player.get_slide_collision(i)
		var col := c.get_collider() as Node3D
		out += " hit[%s n=%s]" % [col.name if col != null else "?", c.get_normal()]
	return out


## A ray straight down onto whatever the world layer has there.
func _ground(at: Vector3, from_up := 2.0, reach := 6.0) -> float:
	var q := PhysicsRayQueryParameters3D.create(
		at + Vector3(0.0, from_up, 0.0), at + Vector3(0.0, from_up - reach, 0.0))
	q.collision_mask = 1
	q.exclude = [_player.get_rid()]
	var hit := _player.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return -9999.0
	return (hit["position"] as Vector3).y


# --- checks -------------------------------------------------------------------

func _run() -> void:
	print("DREAM TEST")
	AudioBus.unlock()
	Engine.time_scale = 4.0
	OS.set_environment("DREAM", "1")
	OS.set_environment("CHASE", "")
	await get_tree().process_frame

	_level = (load(LEVEL) as PackedScene).instantiate()
	get_tree().root.add_child(_level)
	await _wait(1.2)

	_player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	_dream = _level.get_node_or_null("Dream")
	_check("level up, player found", _player != null)
	_check("Dream attached", _dream != null)
	if _player == null or _dream == null:
		_done()
		return
	_dream.set("test_no_handoff", true)
	_player.test_drive = true
	_dream.connect("finished", func() -> void: _finished = true)

	# the world is built inside begin(), which fades first
	var waited := 0.0
	while (_dream.get("hall") as Dictionary).is_empty() and waited < 12.0:
		await _wait(0.2)
		waited += 0.2
	_check("world built", not (_dream.get("hall") as Dictionary).is_empty(), "%.1fs" % waited)
	if (_dream.get("hall") as Dictionary).is_empty():
		_done()
		return
	Fade.clear_deferred()

	_perf(_dream.get("world") as Node)
	await _geometry()
	await _floor()
	await _flight()
	await _climb()
	await _take_toy()
	await _after_fall()
	await _dark()
	await _corridor()
	_done()


func _geometry() -> void:
	var h := _hall()
	var r := _run_room()
	_check("hall root in tree", (h["root"] as Node3D).is_inside_tree())
	_check("run root in tree", (r["root"] as Node3D).is_inside_tree())
	_check("entry door hung", h["entry_door"] != null)
	_check("exit door hung", h["exit_door"] != null)
	var bath: Dictionary = r["bath"]
	_check("bath door hung", bath["door"] != null)
	_check("triggers built", h["entry_trigger"] != null and h["top_trigger"] != null)

	# the doorway bug the chase test caught: a panel hung across its own hole.
	# Measure which axis it is thin along rather than trusting its centre
	var door := h["exit_door"] as MeshInstance3D
	if door != null:
		var aabb := MeshUtil.world_aabb(door)
		var want := _world(h, Vector3(Rooms.HALL_W * 0.5 + Kit.WALL, 1.2526, Rooms.EXIT_Z))
		_check("exit door at its hole", aabb.get_center().distance_to(want) < 0.4,
			"%.2f m off" % aabb.get_center().distance_to(want))
		var fwd := (h["root"] as Node3D).transform.basis * Vector3(1, 0, 0)
		var across := (h["root"] as Node3D).transform.basis * Vector3(0, 0, 1)
		var thin := absf(aabb.size.x * fwd.x) + absf(aabb.size.y * fwd.y) + absf(aabb.size.z * fwd.z)
		var wide := absf(aabb.size.x * across.x) + absf(aabb.size.y * across.y) + absf(aabb.size.z * across.z)
		_check("exit door faces the right way", thin < 0.3 and wide > 0.7,
			"thin %.2f wide %.2f" % [thin, wide])

	# the corridor has to start where the hall's exit leaves off, or the seam
	# between them is a hole in the world
	# The bear stands ON its plinth. The placement is measured in world axes and
	# written to a local position, and the toy is turned to face the room, so
	# without the basis in between the correction lands on the wrong side and
	# doubles the offset it was meant to remove - three quarters of a metre off,
	# hanging in the air beside the thing it is supposed to be standing on.
	var toy := _dream.get("toy") as Node3D
	if toy != null and toy.has_method("get_meshes"):
		var meshes: Array = toy.call("get_meshes")
		if not meshes.is_empty():
			var box: AABB = MeshUtil.world_aabb(meshes[0] as MeshInstance3D)
			for m in range(1, meshes.size()):
				box = box.merge(MeshUtil.world_aabb(meshes[m] as MeshInstance3D))
			var want := _world(h, h["toy_at"] as Vector3)
			var off := Vector2(box.get_center().x - want.x, box.get_center().z - want.z).length()
			_check("the bear stands on its plinth",
				off < 0.2 and absf(box.position.y - want.y) < 0.02,
				"%.3f m off centre, %.3f m off the top" % [off, box.position.y - want.y])

	var junction := _world(h, Vector3(Rooms.HALL_W * 0.5 + Kit.WALL * 2.0, 0.0, Rooms.EXIT_Z))
	_check("corridor meets the hall", (r["root"] as Node3D).transform.origin.distance_to(junction) < 0.01)
	var run_fwd := (r["root"] as Node3D).transform.basis * Vector3(0, 0, 1)
	var hall_x := (h["root"] as Node3D).transform.basis * Vector3(1, 0, 0)
	_check("corridor runs along the hall's x", run_fwd.dot(hall_x) > 0.999)


func _floor() -> void:
	var h := _hall()
	var worst := 0.0
	for spot: Vector3 in [Vector3(0, 0, 6), Vector3(-16, 0, 20), Vector3(15, 0, 38),
			Vector3(-8, 0, 43), Vector3(19, 0, 3)]:
		var y := _ground(_world(h, spot))
		var off := absf(y - _world(h, spot).y)
		worst = maxf(worst, off)
	_check("pillow floor is walkable everywhere", worst < 0.05, "worst %.3f m" % worst)
	# and there really is nothing on it: the pillows are a multimesh with no
	# body at all, which is what lets you push through them
	var mm := 0
	for n in (h["root"] as Node3D).get_children():
		if n is MultiMeshInstance3D:
			mm += 1
	_check("pillow scatter present, no collision", mm >= 20, "%d tiles" % mm)


## Every step of the helix has to be stood on. A gap of more than a few
## centimetres anywhere in it and the climb catches.
func _flight() -> void:
	var h := _hall()
	var pts := h["stair_points"] as Array
	_check("flight has its steps", pts.size() == Rooms.STEP_COUNT, "%d" % pts.size())
	var worst := 0.0
	var misses := 0
	var worst_at := -1
	for i in pts.size():
		var p := _world(h, pts[i] as Vector3)
		# tight: from just over the tread, or near the top it finds the landing
		# above instead of the step under it
		var y := _ground(p, 0.35, 0.95)
		if y < -9000.0:
			misses += 1
			continue
		var off := absf(y - p.y)
		if off > worst:
			worst = off
			worst_at = i
	_check("no gaps in the flight", misses == 0 and worst < 0.1,
		"%d misses, worst %.3f m at step %d" % [misses, worst, worst_at])

	# the last turn has to come up through the landing, not into it
	var arc := h["well_arc"] as Vector2
	var blocked := 0
	for i in pts.size():
		var p := pts[i] as Vector3
		var a := atan2(p.z - Rooms.PILLAR_C.z, p.x - Rooms.PILLAR_C.x)
		var head := (Rooms.TOP_Y - Rooms.PLATFORM_T) - p.y
		if head < 1.35 and head > -0.05 and not Kit.angle_in(a, arc.x, arc.y):
			blocked += 1
	_check("headroom under the landing", blocked == 0, "%d steps sealed" % blocked)


## Walk it, rather than trusting the rays: the capsule is what has to get up.
func _climb() -> void:
	var h := _hall()
	var stub := _world(h, Vector3(0.0, 0.0, 2.0))
	# the first one walks into a shut door on purpose, so it is not a failure
	await _walk_to(stub, 3.0, 0.8, false)
	var door := h["entry_door"] as MeshInstance3D
	if door != null:
		door.call("snap_open", true)
	await _walk_to(stub, 8.0, 0.8)
	_check("through the stub into the hall", _local(h, _player.global_position).z > 0.5,
		"z %.1f" % _local(h, _player.global_position).z)

	var pts := h["stair_points"] as Array
	# on at the foot, not straight at the side of the flight: the rail is a wall
	_check("walked to the foot of the flight",
		await _walk_to(_world(h, h["stair_foot"] as Vector3), 30.0, 0.7))
	await _walk_to(_world(h, pts[0] as Vector3), 6.0, 0.6)
	var i := 0
	while i < pts.size():
		var tight := i >= pts.size() - 8
		if not await _walk_to(_world(h, pts[i] as Vector3), 4.0, 0.3 if tight else 0.85):
			break
		i += 1 if tight else 3
	await _wait(0.3)
	var y := _local(h, _player.global_position).y
	_check("climbed to the top of the flight", y > Rooms.TOP_Y - 0.45,
		"y %.2f of %.2f" % [y, Rooms.TOP_Y])

	# And off it onto the landing, which is the half of the climb that used to
	# fail. The ring's slices are rectangles laid on a coarse arc, so the first
	# one past the top of the flight hangs back over the last half step, where
	# the helix is still short of TOP_Y. A capsule cannot step up a lip: the
	# climb dead-ended one stride from the toy behind nothing you could see.
	var a_end := Rooms.START_ANGLE + Rooms.STEP_TURN * float(Rooms.STEP_COUNT)
	var r_mid := Rooms.PILLAR_R + Rooms.STAIR_W * 0.5
	for step: float in [0.25, 0.55]:
		var a := a_end + step
		await _walk_to(_world(h, Rooms.PILLAR_C + Vector3(cos(a), 0.0, sin(a)) * r_mid
			+ Vector3(0.0, Rooms.TOP_Y, 0.0)), 6.0, 0.35)
	y = _local(h, _player.global_position).y
	_check("stepped onto the landing", y > Rooms.TOP_Y - 0.1, "y %.2f of %.2f" % [y, Rooms.TOP_Y])
	_check("and walked in to the plinth",
		await _walk_to(_world(h, h["platform_at"] as Vector3), 12.0, 0.85))
	# the toy survives the climb now: it goes when it is picked up, not before
	_check("toy still there at the top", _dream.get("toy") != null)
	_check("still climbing, nothing has fired", int(_dream.get("stage")) == 2,
		"stage %d" % int(_dream.get("stage")))


## Take it off the plinth. That is what starts everything after it.
func _take_toy() -> void:
	var spot := _dream.get("_toy_spot") as Area3D
	_check("something to interact with on the plinth", spot != null)
	if spot == null:
		return
	# the ray has to find it the way a player's would
	await _walk_to(_world(_hall(), (_hall()["platform_at"] as Vector3)) + Vector3(0.0, 0.0, 0.0),
		6.0, 1.6, false)
	_face((_hall()["toy_at"] as Vector3) + (_hall()["root"] as Node3D).transform.origin
		- _player.global_position)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_player.call("_update_target")
	var got: Node = _player.get_target()
	_check("the toy is what the ray finds", got == spot,
		"got %s" % (String(got.name) if got != null else "nothing"))
	spot.call("interact", _player)
	await _wait(0.3)
	_check("taking it starts the burn", int(_dream.get("stage")) == 3,
		"stage %d" % int(_dream.get("stage")))
	var waited := 0.0
	while _dream.get("toy") != null and waited < 12.0:
		await _wait(0.25)
		waited += 0.25
	_check("and it burns away in your hands", _dream.get("toy") == null, "%.1fs" % waited)


## The window, the shout and the drop. The monster must never move: it has no
## graph, so its brain returns before it does anything but breathe.
func _after_fall() -> void:
	_player.test_input = Vector2.ZERO
	var waited := 0.0
	while int(_dream.get("stage")) < 4 and waited < 12.0:
		await _wait(0.2)
		waited += 0.2
	_check("the peek fired", int(_dream.get("stage")) >= 4, "stage %d" % int(_dream.get("stage")))

	# the flight has to come off the pillar, or the windows stay hidden behind it
	waited = 0.0
	while (_dream.get("_debris") as Array).is_empty() and waited < 6.0:
		await _wait(0.2)
		waited += 0.2
	_check("the flight starts coming down", not (_dream.get("_debris") as Array).is_empty())
	_check("and the steps are handed over", (_hall()["stair_parts"] as Array).is_empty())

	var m := _dream.get("monster") as Node3D
	_check("monster spawned", m != null)
	if m != null:
		_check("monster is frozen with no graph", int(m.get("state")) == 3 and m.get("graph") == null)
		# it rises into the window on a tween; what must never happen is it
		# hunting once it is up
		await _wait(2.2)
		var was := m.global_position
		await _wait(1.0)
		_check("monster never hunts", m.global_position.distance_to(was) < 0.2,
			"%.2f m" % m.global_position.distance_to(was))

	# stage 7 is DARK: the fall, the black and coming round all have to land
	waited = 0.0
	while int(_dream.get("stage")) != 7 and waited < 50.0:
		await _wait(0.25)
		waited += 0.25
	_check("fell, blacked out and came round", int(_dream.get("stage")) == 7,
		"stage %d after %.1fs" % [int(_dream.get("stage")), waited])
	var p := _local(_hall(), _player.global_position)
	_check("landed in the pillows", absf(p.y) < 0.4, "y %.2f" % p.y)
	# The fall drives the head's roll and yaw straight onto the node, and mouse
	# look only ever writes pitch: anything left in the other two stays written
	# for the rest of the game, and the kid plays the chase at a tilt.
	var head := _player.get_node_or_null("Head") as Node3D
	_check("and the view came back level",
		head != null and absf(head.rotation.z) < 0.02 and absf(head.rotation.y) < 0.02,
		"roll %.1f deg, yaw %.1f deg" % [
			rad_to_deg(head.rotation.z if head != null else 0.0),
			rad_to_deg(head.rotation.y if head != null else 0.0)])
	# and the way down went with the stairs
	_check("the flight is gone", (_dream.get("_debris") as Array).size() < 40,
		"%d pieces left" % (_dream.get("_debris") as Array).size())


func _dark() -> void:
	var h := _hall()
	var node := (h["root"] as Node3D).get_node_or_null("Void") as Node3D
	_check("the dark is up", node != null and node.visible)
	var glow: Array = h["exit_glow"]
	_check("the way out lit up", (glow[0] as OmniLight3D).light_energy > 0.5)

	# the guide walks the camera round onto the door first, then lights the way
	var lit := 0.0
	while int(_dream.get("_trail_lit")) == 0 and lit < 8.0:
		await _wait(0.2)
		lit += 0.2
	_check("the way out is signposted", int(_dream.get("_trail_lit")) > 0,
		"%d lamps lit after %.1fs" % [int(_dream.get("_trail_lit")), lit])

	# stand in it on purpose
	var deaths := int(_dream.get("_deaths"))
	_player.teleport_to(_world(h, Vector3(0.0, 0.0, float(_dream.get("_dark_z")) + 1.0)))
	await _wait(2.5)
	_check("it takes you if you let it", int(_dream.get("_deaths")) > deaths,
		"%d deaths" % int(_dream.get("_deaths")))
	_check("respawned at the pillar", _local(h, _player.global_position).z < Rooms.PILLAR_C.z,
		"z %.1f" % _local(h, _player.global_position).z)
	# the assist: each death restarts the sweep further back
	var margin := float(_dream.get("_dark_z")) - _local(h, _player.global_position).z
	_check("and given more room to try again", margin > 12.0, "%.1f m of head start" % margin)

	# out through the door rather than racing it
	var door := h["exit_door"] as MeshInstance3D
	_player.teleport_to(_world(h, Vector3(Rooms.HALL_W * 0.5 - 1.4, 0.0, Rooms.EXIT_Z)))
	await _wait(0.2)
	if door != null:
		door.call("interact", _player)
	await _wait(0.6)
	_check("the exit opens", int(_dream.get("stage")) == 8, "stage %d" % int(_dream.get("stage")))


## Run at the bathroom and get nowhere. The corridor is a treadmill: every
## segment of forward progress puts the kid back one segment and takes the
## bathroom with them, so the walls stream past, the distance never changes, and
## the door out of the pillow hall stays a few strides behind the whole way.
## Then you look back, and that is the joke.
func _corridor() -> void:
	var r := _run_room()
	var bath: Dictionary = r["bath"]
	var node := bath["node"] as Node3D
	var fwd := (r["root"] as Node3D).transform.basis * Vector3(0, 0, 1)
	_player.teleport_to(_world(r, r["spawn"] as Vector3))
	_face(fwd)
	await _wait(0.2)

	# the room behind has to be freed and the door you came in by kept
	var waited := 0.0
	while (_hall()["root"] != null) and waited < 8.0:
		await _wait(0.2)
		waited += 0.2
	_check("the pillow hall is unloaded behind you", _hall()["root"] == null, "%.1fs" % waited)
	var kept := _hall()["exit_door"] as MeshInstance3D
	_check("and the door you came through is kept",
		kept != null and is_instance_valid(kept) and kept.is_inside_tree())
	if kept != null and is_instance_valid(kept):
		_check("moved over to the corridor", kept.get_parent() == r["root"])

	# the dark stops being your problem the moment you are through
	var deaths := int(_dream.get("_deaths"))
	await _wait(3.0)
	_check("the dark cannot reach you in here", int(_dream.get("_deaths")) == deaths,
		"%d deaths" % int(_dream.get("_deaths")))

	# chase it. `_run_far` is the ground actually covered; local z barely moves,
	# which is the point
	var start_gap := _local(r, node.global_position).z - _local(r, _player.global_position).z
	var back_from := 9999.0
	var t := 0.0
	var checked_gap := false
	while int(_dream.get("_run_step")) == 0 and t < 90.0:
		_face(fwd)
		_player.test_input = Vector2(0.0, -1.0)
		_player.test_run = true
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if not checked_gap and float(_dream.get("_run_far")) > 14.0:
			checked_gap = true
			var g := _local(r, node.global_position).z - _local(r, _player.global_position).z
			_check("the gap never closes while you run",
				absf(g - start_gap) < 4.0, "%.1f m vs %.1f m" % [g, start_gap])
			if kept != null and is_instance_valid(kept):
				back_from = _local(r, _player.global_position).z - _local(r, kept.global_position).z
	_player.test_input = Vector2.ZERO
	_player.test_run = false
	var ran := float(_dream.get("_run_far"))
	_check("the corridor gives up eventually", int(_dream.get("_run_step")) > 0, "after %.0f m" % ran)
	_check("you actually travelled to get there", ran > 25.0, "%.1f m" % ran)
	_check("and the way back never got further off", back_from < 8.0, "%.1f m behind" % back_from)
	_check("still inside the corridor", absf(_local(r, _player.global_position).x) < 1.2,
		"x %.2f" % _local(r, _player.global_position).x)

	# look back. It is right there, and while your eyes are on it the bathroom
	# is set down a few metres the other way
	_face(-fwd)
	waited = 0.0
	while int(_dream.get("_run_step")) != 2 and waited < 6.0:
		await _wait(0.1)
		waited += 0.1
	_check("looking back brings the bathroom up", int(_dream.get("_run_step")) == 2,
		"step %d" % int(_dream.get("_run_step")))
	var near_gap := _local(r, node.global_position).z - _local(r, _player.global_position).z
	_check("and it is close enough to walk to now", near_gap > 2.0 and near_gap < 12.0,
		"%.1f m" % near_gap)
	var door := bath["door"] as MeshInstance3D
	_check("standing open, so you can see what it is", door != null and bool(door.get("is_open")))

	# and back round to it
	_face(fwd)
	waited = 0.0
	while not bool(_dream.get("_door_stopped")) and waited < 6.0:
		await _wait(0.1)
		waited += 0.1
	_check("turning back round stops it running", bool(_dream.get("_door_stopped")))

	await _walk_to(node.global_position, 30.0, 2.2, false)
	waited = 0.0
	while int(_dream.get("stage")) != 9 and waited < 8.0:
		_player.test_input = Vector2(0.0, -1.0)
		await _wait(0.1)
		waited += 0.1
	_player.test_input = Vector2.ZERO
	_check("you get to see what it is, then it shuts", int(_dream.get("stage")) == 9,
		"stage %d" % int(_dream.get("stage")))
	_check("shut in your face", door != null and not bool(door.get("is_open")))
	_check("and you never got inside",
		_local(r, _player.global_position).z < _local(r, node.global_position).z)

	# the room behind it goes while the door is shut, so what opens next is
	# whatever has been built in its place
	waited = 0.0
	while bath.get("room") != null and waited < 4.0:
		await _wait(0.2)
		waited += 0.2
	_check("the bathroom is taken away behind the shut door", bath.get("room") == null,
		"%.1fs" % waited)

	if door != null:
		door.call("interact", _player)
	waited = 0.0
	while not _finished and waited < 6.0:
		await _wait(0.2)
		waited += 0.2
	_check("opening it ends the dream", _finished)
	_check("dream cleaned up after itself", _dream.get("world") == null)


## Counted while the dream is still standing. Doing it at the end would sweep up
## the chase's ten hallways, which by then have been built on top.
func _perf(where: Node) -> void:
	if where == null:
		_check("counted the dream's world", false)
		return
	var meshes := 0
	var lights := 0
	var bodies := 0
	var stack: Array[Node] = [where]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D or n is MultiMeshInstance3D:
			meshes += 1
		elif n is Light3D:
			lights += 1
		elif n is StaticBody3D:
			bodies += 1
		for c in n.get_children():
			stack.append(c)
	print("  dream world: meshes %d, lights %d, static bodies %d" % [meshes, lights, bodies])
	_check("mesh count sane", meshes < 1200, "%d" % meshes)
	_check("light count sane", lights < 100, "%d" % lights)
	_check("body count sane", bodies < 700, "%d" % bodies)


func _done() -> void:
	Engine.time_scale = 1.0
	print("DREAM OK" if _fail == 0 else "DREAM FAIL (%d)" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
