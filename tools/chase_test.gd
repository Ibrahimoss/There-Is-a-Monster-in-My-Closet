extends Node
## Headless run of the chase on the real level: room generation over many
## seeds, the vestibule against the corridor it copies, then an autoplayer that
## walks the whole thing - out of the bedroom, through the seam, down every
## hallway, once into the monster's arms, and out into the bathroom.
## Run:
##   godot --headless --path . res://tools/ChaseTest.tscn
## Prints CHASE OK / CHASE FAIL. Never shipped.

const LEVEL := "res://real_world.tscn"
const Rooms := preload("res://scripts/chase_rooms.gd")
const Kit := preload("res://scripts/chase_kit.gd")
const BedtimeScript := preload("res://scripts/bedtime.gd")

const OFFSET := Vector3(150.0, 0.0, 0.0)
## CHASE_TEST_SEEDS trims the generation sweep while iterating on something
## else; the full run does thirty.
const SEEDS := 30
## The monster is not what this test is about: pin it in place so traversal,
## doors and triggers are what fails when something fails. The one catch that
## matters is staged by hand.
const TEST_ASSIST := 0.0

var _level: Node
var _player: CharacterBody3D
var _chase: Node
var _fail := 0
var _entered: Array[int] = []
var _finished := false


func _ready() -> void:
	_run()


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _check(check_name: String, ok: bool, detail := "") -> void:
	if not ok:
		_fail += 1
	print("  %-42s %s %s" % [check_name, "ok" if ok else "FAIL", detail])


# --- autoplayer ---------------------------------------------------------------

func _face(dir: Vector3) -> void:
	var d := Vector3(dir.x, 0.0, dir.z)
	if d.length() < 0.001:
		return
	d = d.normalized()
	_player.rotation.y = atan2(-d.x, -d.z)
	_player.sync_look_from_transform()


func _walk_to(pos: Vector3, timeout: float, stop_at := 0.5) -> bool:
	var t := 0.0
	while t < timeout:
		var to := pos - _player.global_position
		to.y = 0.0
		if to.length() < stop_at:
			_player.test_input = Vector2.ZERO
			return true
		_face(to)
		_player.test_input = Vector2(0.0, -1.0)
		# duck when the way on is a gap under something
		_player.test_crouch = _near_crawl(1.9)
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	_player.test_input = Vector2.ZERO
	return false


## Is a crawl gap in the current room within `pad` of the player?
func _near_crawl(pad: float) -> bool:
	if _chase == null or int(_chase.get("current_room")) < 1:
		return false
	var rooms: Array = _chase.get("rooms")
	var i := int(_chase.get("current_room"))
	if i >= rooms.size():
		return false
	var p := _player.global_position
	for c: Dictionary in (rooms[i]["crawls_world"] as Array):
		var a := c["aabb"] as AABB
		if a.grow(pad).has_point(Vector3(p.x, a.get_center().y, p.z)):
			return true
	return false


## Follow a room's own graph to the node nearest `goal`, then walk at it.
func _walk_graph(graph: NavGraph, goal: Vector3, timeout: float) -> bool:
	var goal_node := graph.nearest_node(goal)
	var here := graph.nearest_node(_player.global_position)
	var hops := 0
	while here != goal_node and hops < 40:
		var next := graph.next_node(here, goal_node)
		if next < 0 or next == here:
			break
		if not await _walk_to(graph.points[next], timeout, 0.55):
			return false
		here = next
		hops += 1
	return await _walk_to(goal, timeout, 0.6)


## Park the monster so a sub-check measures geometry, not the chase.
func _freeze_monster() -> void:
	var m := _chase.get("monster") as Node3D
	if m != null and is_instance_valid(m):
		m.set("assist_speed_mul", TEST_ASSIST)
		m.call("freeze")


## What is stopping the player right now, for when a walk gets stuck: what the
## capsule last slid against, and what it is standing inside.
func _overlaps() -> String:
	var out := ""
	for i in _player.get_slide_collision_count():
		var c := _player.get_slide_collision(i)
		var col: Node = c.get_collider()
		out += " hit[%s n=%s]" % [_label(col), c.get_normal()]
	var shape := CapsuleShape3D.new()
	shape.radius = 0.26
	shape.height = 1.25
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis.IDENTITY, _player.global_position + Vector3(0.0, 0.625, 0.0))
	q.collision_mask = 1
	q.exclude = [_player.get_rid()]
	for h: Dictionary in _player.get_world_3d().direct_space_state.intersect_shape(q, 12):
		out += " in[%s]" % _label(h["collider"])
	return "v=%.2f%s" % [_player.velocity.length(), out]


func _label(col: Object) -> String:
	var n := col as Node3D
	if n == null:
		return "?"
	var p := n.get_parent() as Node3D
	if p == null:
		return "%s@%s" % [n.name, n.global_position]
	return "%s/%s@%s" % [p.get_parent().name if p.get_parent() != null else "", p.name, p.global_position]


## Look at a door and press interact the way a player would: the ray has to
## find it before anything else does.
func _use(target: Node, from_dir: Vector3, label: String) -> void:
	_face(from_dir)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_player.call("_update_target")
	var got: Node = _player.get_target()
	if got != target:
		_check("ray finds %s" % label, false, "got %s" % (String(got.name) if got != null else "nothing"))
	target.call("interact", _player)


# --- checks -------------------------------------------------------------------

func _run() -> void:
	print("CHASE TEST")
	AudioBus.unlock()
	Engine.time_scale = 4.0
	OS.set_environment("CHASE", "1")
	if OS.get_environment("CHASE_SEED").is_empty():
		OS.set_environment("CHASE_SEED", "7")
	await get_tree().process_frame
	_level = (load(LEVEL) as PackedScene).instantiate()
	get_tree().root.add_child(_level)
	await _wait(1.0)
	_player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	_chase = _level.get_node_or_null("Chase")
	_check("chase director attached", _chase != null)
	if _chase == null or _player == null:
		_done()
		return
	_check("bedtime skipped by the dev entry", _level.get_node_or_null("Bedtime") == null)
	_chase.set("test_no_scene_change", true)
	_player.test_drive = true

	await _generation()
	# the dev entry starts the chase once the eye-open intro is done
	var waited := 0.0
	while int(_chase.get("stage")) < 2 and waited < 20.0:
		await _wait(0.25)
		waited += 0.25
	_check("chase reached the house stage", int(_chase.get("stage")) == 2,
		"stage=%d" % int(_chase.get("stage")))
	if int(_chase.get("stage")) != 2:
		_done()
		return

	_chase.connect("room_entered", func(i: int) -> void: _entered.append(i))
	_chase.connect("finished", func() -> void: _finished = true)
	await _vestibule()
	await _house_stage()
	await _autoplay()
	_perf()
	_freed_room_zero()
	_done()


## Thirty seeds through the real chain builder.
func _generation() -> void:
	var bad_overlap := 0
	var bad_shape := 0
	var bad_graph := 0
	var bad_door := 0
	var missing_type := 0
	var adjacent := 0
	var wrong_head := 0
	var no_crawl := 0
	var crawl_rooms := 0
	var event_rooms := 0
	var runs := SEEDS
	var trim := OS.get_environment("CHASE_TEST_SEEDS")
	if trim.is_valid_int():
		runs = maxi(1, int(trim))

	for s in runs:
		var probe: Node = load("res://scripts/chase.gd").new()
		probe.name = "ChaseProbe%d" % s
		probe.set("force_seed", 1000 + s)
		_level.add_child(probe)
		probe.call("setup", _level, _level.get_node("house"), _player)
		probe.call("_build_world")
		var rooms: Array = probe.get("rooms")
		var seq: Array = probe.get("seq")

		if seq.size() != 10 or String(seq[0]) != "long" or String(seq[1]) != "donut":
			wrong_head += 1
		if not seq.has("stairs") or not seq.has("garden"):
			missing_type += 1
		for i in range(1, seq.size()):
			if String(seq[i]) == String(seq[i - 1]):
				adjacent += 1

		var boxes: Array[AABB] = []
		var seed_crawls := 0
		for i in rooms.size():
			var r: Dictionary = rooms[i]
			var root := r["root"] as Node3D
			boxes.append(root.transform * (r["footprint"] as AABB))
			var cr := (r["crawls"] as Array).size()
			seed_crawls += cr
			if cr > 0:
				crawl_rooms += 1
			if not (r["events"] as Array).is_empty():
				event_rooms += 1
			if i > 0 and r["entry_trigger"] == null:
				bad_shape += 1
			if i < rooms.size() - 1 and r["exit_door"] == null:
				bad_shape += 1
			var g := r["world_graph"] as NavGraph
			if g.size() < 2 or not g.connected():
				bad_graph += 1
			# the panel has to land on the junction plane it was asked for
			var door := r["exit_door"] as MeshInstance3D
			if door != null:
				var portal := r["exit_portal"] as Transform3D
				var fwd := (root.transform.basis * portal.basis) * Vector3(0, 0, 1)
				var want := root.transform * portal.origin - fwd * Kit.WALL + Vector3(0.0, 1.2526, 0.0)
				var box := MeshUtil.world_aabb(door)
				if box.get_center().distance_to(want) > 0.35:
					bad_door += 1
				# a panel that hung across its own opening would still centre
				# on the junction, so measure which way it is thin
				elif absf(box.size.dot(fwd.abs())) > 0.3 or box.size.dot(Vector3(1, 0, 1) - fwd.abs()) < 0.7:
					bad_door += 1
		# rooms touch their neighbour on purpose; anything else must not
		for i in boxes.size():
			for j in range(i + 2, boxes.size()):
				if boxes[i].grow(-0.3).intersects(boxes[j].grow(-0.3)):
					bad_overlap += 1
		if seed_crawls == 0:
			no_crawl += 1
		# take back only this probe's doors: the real chase may have registered
		# its own while these were building, and truncating would drop them
		var registry := Presence.get_doors()
		for r: Dictionary in rooms:
			for d: MeshInstance3D in (r["doors"] as Array):
				var at := registry.find(d)
				if at >= 0:
					registry.remove_at(at)
		probe.queue_free()
		await get_tree().process_frame

	_check("generation: every run has something to crawl under", no_crawl == 0,
		"runs without one=%d/%d" % [no_crawl, runs])
	_check("generation: collapses and crawls are built", crawl_rooms > 0 and event_rooms > 0,
		"crawl rooms=%d, collapse events=%d" % [crawl_rooms, event_rooms])
	_check("generation: room 1 long, room 2 ring", wrong_head == 0, "bad=%d/%d" % [wrong_head, runs])
	_check("generation: a staircase and a garden", missing_type == 0, "bad=%d/%d" % [missing_type, runs])
	_check("generation: no two the same in a row", adjacent == 0, "clashes=%d" % adjacent)
	_check("generation: no rooms inside each other", bad_overlap == 0, "overlaps=%d" % bad_overlap)
	_check("generation: every room has door + trigger", bad_shape == 0, "bad=%d" % bad_shape)
	_check("generation: every graph is connected", bad_graph == 0, "bad=%d" % bad_graph)
	_check("generation: doors land on the junction", bad_door == 0, "bad=%d" % bad_door)


## The copy the seam warps into has to be the corridor, to the millimetre.
func _vestibule() -> void:
	var real := Presence.get_door("Door_005")
	var copy := Presence.get_door("vest door")
	_check("vestibule door built", copy != null)
	if real == null or copy == null:
		return
	var rs: Transform3D = real.get("_shut")
	var cs: Transform3D = copy.get("_shut")
	_check("vestibule door offset is exact", (cs.origin - rs.origin - OFFSET).length() < 0.001,
		"d=%s" % (cs.origin - rs.origin - OFFSET))
	var basis_err := 0.0
	for i in 3:
		basis_err = maxf(basis_err, (cs.basis[i] - rs.basis[i]).length())
	_check("vestibule door hangs the same way", basis_err < 0.01, "err=%.4f" % basis_err)

	var house := _level.get_node("house")
	var real_frame := house.find_child("Door_frame_006", true, false) as MeshInstance3D
	var copy_frame := (_chase.get("rooms")[0]["root"] as Node3D).get_node_or_null("vest door frame") as MeshInstance3D
	_check("vestibule frame built", copy_frame != null)
	if copy_frame != null and real_frame != null:
		var d := MeshUtil.world_aabb(copy_frame).get_center() - MeshUtil.world_aabb(real_frame).get_center() - OFFSET
		_check("vestibule frame offset is exact", d.length() < 0.002, "d=%s" % d)

	var space := _player.get_world_3d().direct_space_state
	var base := Vector3(5.4448, 4.5, -6.186702) + OFFSET
	var down := space.intersect_ray(PhysicsRayQueryParameters3D.create(base, base - Vector3(0, 2.5, 0), 1))
	_check("vestibule floor is at house height", not down.is_empty()
		and absf((down["position"] as Vector3).y - 3.7316) < 0.02,
		"y=%s" % (str((down["position"] as Vector3).y) if not down.is_empty() else "none"))
	var up := space.intersect_ray(PhysicsRayQueryParameters3D.create(base, base + Vector3(0, 3.0, 0), 1))
	_check("vestibule ceiling is at house height", not up.is_empty()
		and absf((up["position"] as Vector3).y - 6.8667) < 0.05,
		"y=%s" % (str((up["position"] as Vector3).y) if not up.is_empty() else "none"))


func _house_stage() -> void:
	# it has already started lurching toward the bed by now
	var monster := _chase.get("monster") as Node3D
	_check("monster came out of the closet", monster != null
		and monster.global_position.distance_to(Vector3(6.8, 3.7316, -9.1)) < 2.5
		and bool(monster.get("visible_now")),
		"at %s" % (str(monster.global_position) if monster != null else "none"))
	if monster != null:
		monster.set("assist_speed_mul", TEST_ASSIST)
	_check("warp spot in front of the bathroom door", _level.get_node_or_null("WarpSpot") != null)

	# the route out of the bedroom has to be walkable at chest height
	var space := _player.get_world_3d().direct_space_state
	var path: Array = _chase.get("HOUSE_PATH")
	var blocked := 0
	for i in range(1, path.size()):
		var a: Vector3 = (path[i - 1] as Vector3) + Vector3(0, 0.9, 0)
		var b: Vector3 = (path[i] as Vector3) + Vector3(0, 0.9, 0)
		var q := PhysicsRayQueryParameters3D.create(a, b, 1)
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			var col: Node = hit["collider"]
			# the kid's own door is on the route and opens
			if String(col.name) != "Door_006" and String(col.get_parent().name) != "Door_006":
				blocked += 1
	_check("house route is clear of walls", blocked == 0, "blocked=%d" % blocked)


func _autoplay() -> void:
	var rooms: Array = _chase.get("rooms")
	# out of the bedroom, through the kid's door, up the corridor
	var kid_door := Presence.get_door("Door_006")
	await _walk_to(Vector3(5.5, 3.73, -9.6), 12.0)
	if kid_door != null and not bool(kid_door.get("is_open")):
		await _use(kid_door, Vector3(0, 0, 1), "kid's door")
		await _wait(0.8)
	await _walk_to(Vector3(5.42, 3.73, -7.6), 12.0)
	var reached: bool = await _walk_to(Vector3(5.30, 3.73, -6.19), 12.0)
	_check("autoplay: reached the bathroom door", reached,
		"at %s" % _player.global_position)

	var warp := _level.get_node_or_null("WarpSpot")
	if warp != null:
		await _use(warp, Vector3(1, 0, 0), "warp spot")
	await _wait(0.6)
	_check("seam: the player is in the copy", _player.global_position.x > 100.0,
		"x=%.2f" % _player.global_position.x)
	_check("seam: the vestibule door opened", bool((rooms[0]["exit_door"] as MeshInstance3D).get("is_open")))

	var caught_once := false
	var crawl_tested := false
	var barge_tested := false
	for i in range(1, rooms.size()):
		var r: Dictionary = rooms[i]
		var root := r["root"] as Node3D
		var portal := r["exit_portal"] as Transform3D
		var door_world: Vector3 = root.transform * portal.origin
		var fwd: Vector3 = (root.transform.basis * portal.basis) * Vector3(0, 0, 1)

		# walk in far enough to trip the entry trigger
		if not await _walk_to(root.transform * Vector3(0.0, 0.0, 1.1), 14.0):
			_check("autoplay: entered room %d" % i, false, "stuck at %s" % _player.global_position)
			break
		await _wait(0.3)
		var monster := _chase.get("monster") as Node3D
		if monster != null:
			monster.set("assist_speed_mul", TEST_ASSIST)
		var deaths_here := int(_chase.get("_deaths"))

		if String(r["type"]) == "threshold":
			break

		# one deliberate catch, in the second hallway
		if i == 2 and not caught_once:
			caught_once = true
			var deaths_before := int(_chase.get("_deaths"))
			# wait for it to be hunting in THIS room, not standing frozen in
			# the last one from an earlier sub-check
			var waiting := 0.0
			while int(monster.get("state")) != 2 and waiting < 20.0:
				await _wait(0.25)
				waiting += 0.25
			_player.teleport_to(monster.global_position + Vector3(0.3, 0.0, 0.0))
			await _wait(2.0)
			_check("caught: the count went up", int(_chase.get("_deaths")) > deaths_before,
				"%d -> %d" % [deaths_before, int(_chase.get("_deaths"))])
			_check("caught: respawned at the room's start",
				_player.global_position.distance_to(r["spawn_world"] as Vector3) < 2.5,
				"at %s want %s" % [_player.global_position, r["spawn_world"]])
			monster.set("assist_speed_mul", TEST_ASSIST)

		var walked: bool = await _walk_graph(r["world_graph"] as NavGraph, door_world - fwd * 1.2, 45.0)
		if not walked:
			_check("autoplay: crossed room %d (%s)" % [i, r["type"]], false,
				"stuck at %s" % _player.global_position)
			break
		# the first crawl we meet: a standing kid must not fit, a crouched one must
		if not crawl_tested and not (r["crawls_world"] as Array).is_empty():
			crawl_tested = true
			await _crawl_check(i, r)

		var door := r["exit_door"] as MeshInstance3D
		if door != null and not bool(door.get("is_open")):
			if not barge_tested:
				barge_tested = true
				await _barge_check(i, door, door_world, fwd)
			else:
				await _use(door, fwd, "room %d exit" % i)
			await _wait(1.2)
		if not await _walk_to(door_world + fwd * 1.6, 14.0):
			var nxt: String = String(rooms[i + 1]["type"]) if i + 1 < rooms.size() else "-"
			_check("autoplay: through room %d's door" % i, false,
				"at %s plane=%s next=%s open=%s swing=%.2f locked=%s deaths=%d->%d %s" % [
					_player.global_position, door_world - fwd * Kit.WALL, nxt,
					door.get("is_open"), float(door.get("_swing")), door.get("locked"),
					deaths_here, int(_chase.get("_deaths")), _overlaps()])
			break

	_check("autoplay: rooms entered in order", _entered.size() >= 11
		and _entered[0] == 1 and _entered[_entered.size() - 1] == 11,
		"entered=%s" % str(_entered))

	var t := 0.0
	# sampled while it plays: which way the kid is turned when they land in the
	# bathroom, and where they are the first time they are in the bed
	var faced := -2.0
	var bed_first := Vector3.INF
	while not _finished and t < 60.0:
		if faced < -1.0 and GameState.current_act == GameState.Act.BATHROOM:
			var cam := _player.get_camera() as Camera3D
			if cam != null:
				var to_door := (Vector3(5.95, 3.7316, -6.186702) - _player.global_position)
				if to_door.length() > 0.05:
					faced = (-cam.global_basis.z).dot(to_door.normalized())
		if bed_first == Vector3.INF and bool(_player.get("in_bed")):
			bed_first = _player.global_position
		await _wait(0.5)
		t += 0.5
	_check("ending: the chase finished", _finished, "after %.0fs" % t)
	# backed into the room with the door in front of you. Turned the other way,
	# every beat of the break-in happens off the side of the screen
	_check("ending: cornered facing the door", faced > 0.5, "dot %.2f" % faced)
	# and no slide: the cut to black happens in the bathroom and the picture
	# comes back with the kid already lying down. A tweened move across the
	# house is one the player gets to watch themselves make
	_check("ending: put into the bed rather than slid into it",
		bed_first != Vector3.INF and bed_first.distance_to(BedtimeScript.BED_SPOT) < 0.5,
		"first seen in bed at %s" % bed_first)
	var head := _player.get_node_or_null("Head") as Node3D
	_check("ending: the view is level", head != null and absf(head.rotation.z) < 0.02,
		"roll %.1f deg" % rad_to_deg(head.rotation.z if head != null else 0.0))
	# the bathroom is no longer where it ends. The door goes, the thing comes
	# through it, and the cut lands on the kid awake in their own bed.
	_check("ending: awake in the real bed",
		_player.global_position.distance_to(BedtimeScript.BED_SPOT) < 1.2,
		"at %s" % _player.global_position)
	_check("ending: in bed", bool(_player.get("in_bed")))
	var bath := Presence.get_door("Door_005")
	_check("ending: the bathroom door was broken open",
		bath != null and not bool(bath.get("locked")) and bool(bath.get("is_open")),
		"locked=%s open=%s" % [
			bath.get("locked") if bath != null else "?",
			bath.get("is_open") if bath != null else "?"])
	_check("ending: act is WAKE", GameState.current_act == GameState.Act.WAKE)


## Walk at the gap standing (must be stopped by it), then crouched (must get
## through). Run from a spot on the near side, straight at its centre.
##
## Probe only: the player is put back where it found them, so the run carries
## on from where it was.
func _crawl_check(index: int, r: Dictionary) -> void:
	_freeze_monster()
	var resume := _player.global_position
	# if the room's collapse has not been tripped yet, drop it now: the gap
	# only exists once the thing has actually fallen
	for ev: Dictionary in (r["events"] as Array):
		if not bool(ev.get("done", false)):
			ev["done"] = true
			(ev["play"] as Callable).call(_player)
	await _wait(1.2)
	var c: Dictionary = (r["crawls_world"] as Array)[0]
	var gap := c["aabb"] as AABB
	# the hole is off to one side now, so aim at the middle of the gap itself
	var centre := gap.get_center()
	var fwd := (c["through"] as Vector3).normalized()
	var floor_y := gap.position.y
	var near := Vector3(centre.x, floor_y, centre.z) - fwd * 1.8
	var far := Vector3(centre.x, floor_y, centre.z) + fwd * 1.8

	_player.test_crouch = false
	_player.teleport_to(near)
	await get_tree().physics_frame
	var t := 0.0
	while t < 4.0:
		_face(far - _player.global_position)
		_player.test_input = Vector2(0.0, -1.0)
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	_player.test_input = Vector2.ZERO
	var stood := _player.global_position.distance_to(far)
	_check("crawl: standing does not fit", stood > 1.0, "%.2f m short of the far side" % stood)

	_player.teleport_to(near)
	_player.test_crouch = true
	await get_tree().physics_frame
	t = 0.0
	while t < 8.0:
		_face(far - _player.global_position)
		_player.test_input = Vector2(0.0, -1.0)
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	_player.test_input = Vector2.ZERO
	var crouched := _player.global_position.distance_to(far)
	_check("crawl: crouched gets through", crouched < 0.9, "%.2f m short of the far side" % crouched)
	_player.test_crouch = false
	_player.teleport_to(resume)
	await _wait(0.5)


## Run a shut door down instead of pressing interact.
func _barge_check(index: int, door: MeshInstance3D, door_world: Vector3, fwd: Vector3) -> void:
	_freeze_monster()
	var before := int(_player.get("debug_barge_count"))
	_player.teleport_to(door_world - fwd * 3.2)
	await get_tree().physics_frame
	_player.test_run = true
	var t := 0.0
	while t < 5.0 and not bool(door.get("is_open")):
		_face(fwd)
		_player.test_input = Vector2(0.0, -1.0)
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	_player.test_input = Vector2.ZERO
	_player.test_run = false
	_check("barge: running opens room %d's door" % index, bool(door.get("is_open"))
		and int(_player.get("debug_barge_count")) > before,
		"open=%s barges=%d" % [door.get("is_open"), int(_player.get("debug_barge_count"))])

	# the view should have been thrown the way the door was, not at random:
	# hit head on, so forward (-z in body space) and down
	await get_tree().process_frame
	var kick: Vector3 = _player.get("_barge_pos").value
	var spin: Vector3 = _player.get("_barge_rot").value
	_check("barge: view drives into the door and dips",
		kick.z < -0.005 and kick.y < 0.0 and spin.x < 0.0,
		"pos=%s rot=%s" % [kick, spin])
	await _wait(2.5)
	var settled: Vector3 = _player.get("_barge_pos").value
	_check("barge: view settles back", settled.length() < 0.01, "left=%s" % settled)
	await _shoulder_check()
	# leave them on the near side; the run carries on through the doorway
	_player.teleport_to(door_world - fwd * 1.2)


## The two hits a real run cannot be steered into reliably: a door taken on
## the shoulder, and one backed into. Fed straight to the kick so the mapping
## from contact side to lean is what gets measured.
func _shoulder_check() -> void:
	var pos_spring: Object = _player.get("_barge_pos")
	var rot_spring: Object = _player.get("_barge_rot")

	# door hard on the right: its normal points back at our left shoulder
	pos_spring.call("reset")
	rot_spring.call("reset")
	_player.call("_barge_kick", -_player.global_transform.basis.x, 3.0)
	await get_tree().process_frame
	await get_tree().process_frame
	var kick: Vector3 = pos_spring.get("value")
	var spin: Vector3 = rot_spring.get("value")
	_check("barge: shoulder right throws the view right",
		kick.x > 0.005 and spin.z < 0.0 and spin.y < 0.0,
		"pos=%s rot=%s" % [kick, spin])

	# and the mirror image, so the sign is not baked in
	pos_spring.call("reset")
	rot_spring.call("reset")
	_player.call("_barge_kick", _player.global_transform.basis.x, 3.0)
	await get_tree().process_frame
	await get_tree().process_frame
	var kick_l: Vector3 = pos_spring.get("value")
	var spin_l: Vector3 = rot_spring.get("value")
	_check("barge: shoulder left mirrors it",
		kick_l.x < -0.005 and spin_l.z > 0.0 and spin_l.y > 0.0,
		"pos=%s rot=%s" % [kick_l, spin_l])

	# backing into one: straight down, no lean either way
	pos_spring.call("reset")
	rot_spring.call("reset")
	_player.call("_barge_kick", -_player.global_transform.basis.z, 3.0)
	await get_tree().process_frame
	await get_tree().process_frame
	var kick_b: Vector3 = pos_spring.get("value")
	var spin_b: Vector3 = rot_spring.get("value")
	_check("barge: backing in drops the view, no lean",
		kick_b.y < 0.0 and kick_b.z > 0.005 and spin_b.x < 0.0
			and absf(spin_b.z) < 0.0005 and absf(spin_b.y) < 0.0005,
		"pos=%s rot=%s" % [kick_b, spin_b])
	pos_spring.call("reset")
	rot_spring.call("reset")


func _perf() -> void:
	var world := _chase.get("world") as Node3D
	var meshes := 0
	var lights := 0
	var stack: Array[Node] = [world]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.push_back(c)
		if n is MeshInstance3D:
			meshes += 1
		elif n is Light3D:
			lights += 1
	# the ceiling is generous because floors and walls are deliberately cut into
	# chunks: GL compatibility only lights a mesh with the few lamps nearest it,
	# so one long slab loses the rest and goes black
	_check("perf: mesh count", meshes < 1200, "meshes=%d" % meshes)
	_check("perf: light count", lights < 120, "lights=%d" % lights)


## Regression: the dream frees its corridor -- the chase's room zero -- as soon
## as you are two rooms clear of it, so _cull_rooms walks a freed object from
## room three on. It used to cast first and check validity after, which crashed
## the run a hallway or two into the chase.
func _freed_room_zero() -> void:
	var rooms: Array = _chase.get("rooms")
	if rooms.is_empty():
		_check("cull survives a freed room zero", false, "no rooms built")
		return
	var root := rooms[0]["root"] as Node3D
	if root == null:
		_check("cull survives a freed room zero", false, "room zero has no root")
		return
	# free it the way dream.gd does, and let the frame turn over so it is gone
	root.free()
	_chase.call("_cull_rooms", 2)
	_check("cull survives a freed room zero", true)
	_check("the dead room is blanked, not re-read", rooms[0]["root"] == null)
	# and it stays survivable on the next pass
	_chase.call("_cull_rooms", 3)
	_check("cull survives it twice", true)


func _done() -> void:
	print("CHASE OK" if _fail == 0 else "CHASE FAIL (%d)" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
