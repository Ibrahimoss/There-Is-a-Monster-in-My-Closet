class_name ChaseRooms
extends RefCounted
## The rooms the chase is chained out of. Every builder is static, takes the
## world transform the room will sit at, and returns the same dictionary:
##
##   root          Node3D, NOT yet in the tree (the director adds it once the
##                 footprint test passes, so a rejected candidate costs nothing)
##   type          "long" | "donut" | "stairs" | "garden" | "vestibule" |
##                 "threshold"
##   exit_portal   LOCAL Transform3D: the next room's frame. origin sits two
##                 wall thicknesses past the exit wall's inner face, basis
##                 turns local +z onto the exit heading
##   exit_door     the Door hung on the junction plane (null in the threshold)
##   fake_doors    dead ends, locked and boarded
##   doors         every Door built here, for Presence to register on accept
##   entry_trigger Area3D that fires room_entered (null in the vestibule)
##   spawn         LOCAL respawn point, facing +z
##   graph         NavGraph in LOCAL coordinates
##   footprint     LOCAL AABB of everything solid, for the overlap test
##   lights        every OmniLight3D the monster can eat
##   spill_light   the lamp just inside the entry, so light leaks back through
##                 the door into the room you came from
##   loops         [sound, LOCAL pos, dB] the director starts once in the tree
##   crawls        LOCAL AABBs you have to crouch through
##   events        {trigger: Area3D, play: Callable} the director fires once
##   head_start    seconds between entering and the door bursting open
##
## `opts.depth` (0 at the first hallway, 1 at the last) is how far into the
## nightmare the room sits: deeper rooms are darker, dirtier, more broken and
## more in the way.
##
## Local frame: origin at the centre of the entry doorway on the floor, +z into
## the room, +x right. See chase_kit.gd.

const Kit := preload("res://scripts/chase_kit.gd")
const NavGraphScript := preload("res://scripts/nav_graph.gd")

const HEAD_START := {"long": 2.4, "donut": 3.0, "stairs": 2.8, "garden": 2.6}
## Extra head start when the room makes you crouch through something.
const CRAWL_HEAD_START := 1.2

## Corridor half-widths and the octagon's two apothems.
const LONG_W := 1.7
const DONUT_R_OUT := 6.4
const DONUT_R_IN := 3.6
const STAIR_W := 1.7
## Metres of corridor kept free of solid junk either side of a barrier gap and
## in front of a way out. Sized off the widest hall prop laid on its side.
const JUNK_CLEAR := 1.6
const GARDEN_W := 3.4

## Real corridor faces around the bathroom door, measured off the level.
const VEST_FLOOR_Y := 3.7316
const VEST_CEIL_Y := 6.8667
const VEST_WEST_X := 4.9098
const VEST_EAST_X := 5.9798
const VEST_SOUTH_Z := -7.90
const VEST_NORTH_Z := -4.6061
const VEST_DOOR_POINT := Vector3(6.047014, 3.7316, -6.186702)
const VEST_NORTH_DOOR_POINT := Vector3(5.402207, 3.7316, -4.656059)

## What gets knocked over in the hallways, and what fits where.
const JUNK_SMALL: Array[String] = ["Box", "Chair_01", "Trash_can_002", "Broom", "Books_002"]
const JUNK_BIG: Array[String] = ["Box", "Chair_01", "Chest_drawers_03", "Trash_can_002"]
const JUNK_GARDEN: Array[String] = ["Box", "Chair_01", "Trash_can_002", "Broom"]
## Things that actually fit a corridor. This list used to be armchairs and
## tables: measured, `Armchair_15_001` is 2.11 m across against a hall that is
## often 1.7 m wide, so it was clipping through the walls, and being walk-
## through on top of that is what made a hallway read as sealed when it was not.
## Everything here is small enough to stand against a wall and leave the run
## open, which is what lets it be solid.
const JUNK_HALL: Array[String] = ["Chair_01", "Box", "Trash_can_002", "Broom", "Books_002"]
## `Flowers_01` is 5.85 m wide and `Flowers` 2.72: planted behind a hedge they
## cut straight through it and hang over the path with no stem and no ground
## under them. Only the one that is actually shrub-sized survives.
const FLOWERS: Array[String] = ["Plants"]


static func build(type: String, frame_xf: Transform3D, opts: Dictionary) -> Dictionary:
	match type:
		"long":
			return build_long(frame_xf, opts)
		"donut":
			return build_donut(frame_xf, opts)
		"stairs":
			return build_stairs(frame_xf, opts)
		"garden":
			return build_garden(frame_xf, opts)
		"vestibule":
			return build_vestibule(frame_xf, opts)
		_:
			return build_threshold(frame_xf, opts)


## Every builder starts here so no room forgets a key.
static func _blank(type: String, room_name: String, frame_xf: Transform3D) -> Dictionary:
	var root := Node3D.new()
	root.name = room_name
	root.transform = frame_xf
	return {
		"root": root,
		"type": type,
		"exit_portal": Transform3D.IDENTITY,
		"exit_door": null,
		"fake_doors": [],
		"doors": [],
		"entry_trigger": null,
		"spawn": Vector3(0.0, 0.0, 1.0),
		"graph": NavGraphScript.new(),
		"footprint": AABB(),
		"lights": [],
		"spill_light": null,
		"loops": [],
		"crawls": [],
		"events": [],
		## window panes, for the director's rain and lightning
		"panes": [],
		## light shafts, driven with their lamps
		"shafts": [],
		"head_start": float(HEAD_START.get(type, 2.6)),
	}


## A doorway hole in the far wall plus the real house door hung in it, at the
## junction plane. Registers the door in the room's list.
## The way on is the one thing the player must never have to guess at, so it is
## always the brightest thing in the room: a warm lamp over it and a shaft
## leaning off the frame. Every dead end is left dark on purpose, which is what
## makes this read at a glance from the far end of a hall.
static func _exit_doorway(room: Dictionary, frame_xf: Transform3D, point: Vector3,
		heading: Vector3, house: Node, door_name: String, depth := 0.0) -> MeshInstance3D:
	var root := room["root"] as Node3D
	var d := Kit.doorway(root, frame_xf, point, heading, house,
		{"name": door_name, "swing_time": 0.5, "open_angle": 105.0})
	if d != null:
		(room["doors"] as Array).append(d)
		room["exit_door"] = d
	var h := Vector3(heading.x, 0.0, heading.z).normalized()
	var over := point - h * 0.85 + Vector3(0.0, Kit.CEIL - 0.28, 0.0)
	# every material drifts colder and dirtier with depth; this one lamp goes the
	# other way and warms up, so however deep the room is there is always exactly
	# one warm thing in the frame and it is the way out
	var lamp := Kit.lamp(root, over, 1.15 + 0.4 * depth, 5.2, true, false)
	lamp.set_meta("exit_marker", true)
	(room["lights"] as Array).append(lamp)
	(room["shafts"] as Array).append(
		Kit.shaft(root, over, Kit.CEIL - 0.4, 0.85, Color(1.0, 0.88, 0.66), 0.75 + 0.35 * depth))
	# dust turning over in the doorway light. In a corridor where nothing else
	# moves, the eye goes straight to it, and it is over the way out
	Kit.motes(root, over - Vector3(0.0, 0.95, 0.0), 0.5, 14)
	return d


static func _fake_doorway(room: Dictionary, frame_xf: Transform3D, point: Vector3,
		heading: Vector3, house: Node, door_name: String, rng: RandomNumberGenerator) -> void:
	var d := Kit.doorway(room["root"] as Node3D, frame_xf, point, heading, house,
		{"name": door_name, "swing_time": 0.6, "open_angle": 105.0,
		"locked": true, "locked_prompt": "Blocked"})
	if d == null:
		return
	(room["doors"] as Array).append(d)
	(room["fake_doors"] as Array).append(d)
	Kit.planks(room["root"] as Node3D, frame_xf, point, -heading, house, rng)
	# The boards were always here. Nobody could see them, because a dead end is
	# deliberately left unlit and boards in the dark read as nothing at all. A
	# dim COLD light on them says blocked in the same glance the warm lamp over
	# the real door says go, without the two ever competing.
	var h := Vector3(heading.x, 0.0, heading.z).normalized()
	# low and weak on purpose: enough to pick the boards out of the dark, never
	# enough to out-light the warm lamp over the way on. At 0.5/2.8 it flooded
	# the panel and made the dead end the brightest thing in the room.
	var glow := Kit.lamp(room["root"] as Node3D, point - h * 0.7 + Vector3(0.0, 1.45, 0.0),
		0.3, 2.1, false, false, 0.0, 0.0, false)
	(room["lights"] as Array).append(glow)


static func _entry(room: Dictionary, at := Vector3(0.0, 1.1, 0.5)) -> Area3D:
	var a := Kit.trigger(room["root"] as Node3D, Vector3(1.2, 2.2, 0.6), at, "EntryTrigger")
	room["entry_trigger"] = a
	return a


## The lamp just inside the door, whose spill through the opening is the only
## thing telling the player which way is on.
static func _spill(room: Dictionary, at: Vector3, range_m := 3.5) -> void:
	var l := Kit.lamp(room["root"] as Node3D, at, 0.7, range_m, true, false)
	room["spill_light"] = l
	(room["lights"] as Array).append(l)


## A ceiling lamp that may be dead, may hang crooked, may flicker: all of it
## more likely the deeper the room is.
static func _lamp(room: Dictionary, at: Vector3, rng: RandomNumberGenerator, depth: float,
		energy := 0.85, range_m := 4.4, warm := true, keep_alive := false) -> OmniLight3D:
	var sway := 0.0
	if rng.randf() < depth * 0.9:
		sway = rng.randf_range(0.08, 0.32) * depth
	var l := Kit.lamp(room["root"] as Node3D, at, energy, range_m, warm, true, sway, rng.randf_range(0.0, TAU))
	# deeper rooms lose more bulbs, but not so many that the mess on the floor
	# becomes invisible: being blindsided by a crate is not the scare
	if not keep_alive and rng.randf() < lerpf(0.2, 0.5, depth):
		l.visible = false
		(l.get_meta("bulb") as Node3D).visible = false
	else:
		if rng.randf() < lerpf(0.15, 0.6, depth):
			l.set_meta("flicker", true)
		var s := Kit.shaft(room["root"] as Node3D, l.position, at.y - 0.15, 0.62,
			l.light_color, 0.34 + 0.1 * energy)
		l.set_meta("shaft", s)
		(room["shafts"] as Array).append(s)
	(room["lights"] as Array).append(l)
	return l


## Junk against the walls, more of it deeper in, some of it on its side. `spots`
## are LOCAL floor points already clear of the doorways; `solid` ones block.
static func _junk(room: Dictionary, frame_xf: Transform3D, house: Node, rng: RandomNumberGenerator,
		depth: float, spots: Array[Vector3], solid: bool, names: Array[String] = JUNK_SMALL) -> void:
	var root := room["root"] as Node3D
	var count := mini(spots.size(), int(round(lerpf(0.6, 4.2, depth) + rng.randf() * 0.8)))
	var pool := spots.duplicate()
	for i in count:
		if pool.is_empty():
			break
		var idx := rng.randi_range(0, pool.size() - 1)
		var p: Vector3 = pool[idx]
		pool.remove_at(idx)
		var n := names[rng.randi_range(0, names.size() - 1)]
		var tip := 0.0
		if rng.randf() < depth * 0.6 and n != "Box":
			tip = PI * 0.5 * (1.0 if rng.randf() < 0.5 else -1.0)
		Kit.dressing_dup(house, n, root, frame_xf, p, rng.randf_range(0.0, TAU), tip, solid)
	# and planks, deeper in
	for i in int(round(depth * 3.0 * rng.randf())):
		if pool.is_empty():
			break
		var idx := rng.randi_range(0, pool.size() - 1)
		Kit.plank_litter(root, pool[idx], rng.randf_range(0.0, TAU), rng, depth)
		pool.remove_at(idx)


## Where the corridor closes up, and how. One obstacle by default, two in a
## long hall deeper in; sides alternate so the run weaves. Shallow rooms only
## make you go round, deeper ones make you go under.
static func _obstacle_plan(rng: RandomNumberGenerator, depth: float, length: float,
		collapsed: bool, width: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var count := 1
	if length > 20.0 and depth > 0.35 and rng.randf() < lerpf(0.25, 0.8, depth):
		count = 2
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	for i in count:
		var span := length / float(count + 1)
		var z := span * float(i + 1) + rng.randf_range(-1.2, 1.2)
		var crouch := collapsed and i == 0
		if not crouch:
			crouch = rng.randf() < lerpf(0.1, 0.6, depth)
		out.append({
			"z": clampf(z, 4.0, length - 3.5),
			"side": side,
			# a wide hall leaves a proper doorway-sized way past; a narrow one
			# barely lets you by
			"gap": clampf(width * rng.randf_range(0.34, 0.46), 0.78, 1.5),
			"crouch": crouch,
		})
		side = -side
	return out


## Nothing else gets placed within `pad` of an obstacle.
static func _clear_of(bars: Array[Dictionary], z: float, pad: float) -> bool:
	for b: Dictionary in bars:
		if absf(z - float(b["z"])) < pad:
			return false
	return true


## Windows down one wall of a corridor running along +z, with the rain on them.
static func _windows(room: Dictionary, rng: RandomNumberGenerator, depth: float, half: float,
		length: float, cold: bool) -> void:
	var root := room["root"] as Node3D
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	var z := rng.randf_range(3.0, 5.5)
	while z < length - 2.5:
		var at := Vector3(side * (half - 0.02), 1.45, z)
		var normal := Vector3(-side, 0.0, 0.0)
		var pane := Kit.window(root, at, normal, rng.randf_range(0.9, 1.15), 1.3, depth)
		(room["panes"] as Array).append(pane)
		z += rng.randf_range(5.0, 7.5)
		# the odd one on the far wall keeps it from reading as a pattern
		if rng.randf() < 0.3:
			side = -side


# --- LONG ---------------------------------------------------------------------

## A straight corridor. Variant 0 is plain, 2 is the cold one (blue plaster,
## blue-white bulbs), 3 has come down in the middle and you crawl under it.
## Deep in, crates and chairs alternate sides so the run becomes a slalom.
static func build_long(frame_xf: Transform3D, opts: Dictionary) -> Dictionary:
	var rng := opts["rng"] as RandomNumberGenerator
	var house := opts["house"] as Node
	var variant := int(opts.get("variant", 0))
	var depth := float(opts.get("depth", 0.0))
	var room := _blank("long", "RoomLong", frame_xf)
	var root := room["root"] as Node3D

	var length := rng.randf_range(18.0, 24.0)
	var cold := variant == 2
	var collapsed := variant == 3
	var wall_key := "wall_cold" if cold else "wall"
	# wide halls have room for the way past to be off to one side; narrow ones
	# stay tight and get squeezes instead
	var w := LONG_W
	if collapsed:
		w = rng.randf_range(2.8, 3.2)
	elif rng.randf() < 0.45:
		w = rng.randf_range(2.2, 3.0)
	var half := w * 0.5
	var outer := half + Kit.WALL
	var z0 := -0.16
	var z1 := length + 0.16
	var span := z1 - z0
	var mid := (z0 + z1) * 0.5

	Kit.split_box(root, Vector3(outer * 2.0, Kit.SLAB, span), Vector3(0.0, -Kit.SLAB * 0.5, mid), "floor", 0.0, true, depth)
	Kit.split_box(root, Vector3(outer * 2.0, Kit.SLAB, span), Vector3(0.0, Kit.CEIL + Kit.SLAB * 0.5, mid), "ceil", 0.0, true, depth)
	for s in [-1.0, 1.0]:
		Kit.split_box(root, Vector3(Kit.WALL, Kit.CEIL, span),
			Vector3(s * (half + Kit.WALL * 0.5), Kit.CEIL * 0.5, mid), wall_key, 0.0, true, depth)
		# baseboard, in pieces where the deeper rooms have lost bits of it
		var z := z0 + 0.1
		while z < z1 - 0.2:
			var seg := rng.randf_range(2.0, 5.0)
			var end := minf(z + seg, z1 - 0.1)
			if rng.randf() > depth * 0.5:
				Kit.box(root, Vector3(0.03, 0.09, end - z), Vector3(s * (half - 0.015), 0.045, (z + end) * 0.5),
					"plank", 0.0, false, depth)
			z = end + rng.randf_range(0.0, depth * 0.6)
	Kit.wall_with_door(root, outer * 2.0, Vector3(0.0, 0.0, -Kit.WALL * 0.5), 0.0, wall_key, Kit.CEIL, depth)
	Kit.wall_with_door(root, outer * 2.0, Vector3(0.0, 0.0, length + Kit.WALL * 0.5), 0.0, wall_key, Kit.CEIL, depth)
	_exit_doorway(room, frame_xf, Vector3(0.0, 0.0, length + Kit.WALL), Vector3(0, 0, 1), house, "long exit", depth)

	# a wider hall needs the lamps to reach further or the walls and floor fall
	# away into nothing
	var reach := 4.0 + (w - LONG_W) * 1.5
	var lit := (0.7 if cold else 0.85) + (w - LONG_W) * 0.12
	_spill(room, Vector3(0.0, Kit.CEIL - 0.3, 1.2), reach)
	var lz := 4.6
	# spaced a little further apart than they reach, so the corridor comes in
	# pools with dark between them. Closer than this and the pools merge into one
	# even wash, which lights the hall perfectly well and is worth nothing.
	while lz < length - 1.0:
		_lamp(room, Vector3(0.0, Kit.CEIL - 0.3, lz), rng, depth, lit, reach, not cold)
		lz += 5.6

	# What is in the way. One or two of them, spaced out, each shoving the run
	# to one side or the other; deeper halls make you go under rather than round.
	var bars := _obstacle_plan(rng, depth, length, collapsed, w)
	for bar: Dictionary in bars:
		var o := Kit.barrier(root, Vector3(0.0, 0.0, float(bar["z"])), Vector3(1, 0, 0), w, 0.0,
			float(bar["side"]), float(bar["gap"]), bool(bar["crouch"]), house, rng, depth)
		bar["point"] = o["gap_point"]
		(room["lights"] as Array).append(o["light"])
		if bool(bar["crouch"]):
			(room["crawls"] as Array).append({"aabb": o["aabb"], "through": o["through"]})
			room["head_start"] = float(room["head_start"]) + CRAWL_HEAD_START
		else:
			room["head_start"] = float(room["head_start"]) + 0.5

	# a bookcase that comes down across the hall as you reach it
	if length > 15.0 and rng.randf() < lerpf(0.55, 0.9, depth):
		var tz := length * rng.randf_range(0.28, 0.72)
		if _clear_of(bars, tz, 3.4):
			var tside := 1.0 if rng.randf() < 0.5 else -1.0
			var tp := Kit.topple(root, Vector3(tside * (half - 0.2), 0.0, tz),
				Vector3(tside, 0, 0), 0.0, house, rng, depth)
			var trig := Kit.trigger(root, Vector3(w + 0.3, 2.2, 1.0),
				Vector3(0.0, 1.1, tz - 3.0), "ToppleTrigger")
			(room["events"] as Array).append(
				{"trigger": trig, "play": Callable(Kit, "play_topple").bind(tp)})
			(room["lights"] as Array).append(
				Kit.lamp(root, Vector3(tside * (half - 0.5), Kit.CEIL - 0.4, tz), 0.5, 3.4, not cold, false))

	# windows down one wall, and something to walk past
	_windows(room, rng, depth, half, length, cold)
	var spots: Array[Vector3] = []
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	var sz := 3.2
	while sz < length - 2.4:
		if _clear_of(bars, sz, 2.4):
			spots.append(Vector3(side * (half - 0.34), 0.0, sz))
			side = -side
		sz += rng.randf_range(2.8, 4.0)
	_junk(room, frame_xf, house, rng, depth, spots, true, JUNK_HALL)

	_entry(room)
	room["spawn"] = Vector3(0.0, 0.0, 1.0)

	# the graph bends to each gap, so the thing behind you takes the same way
	var graph := room["graph"] as NavGraphScript
	var pts: Array[Vector3] = [Vector3(0.0, 0.0, 0.6)]
	var g := 4.0
	while g < length - 0.8:
		pts.append(Vector3(0.0, 0.0, g))
		g += 4.0
	pts.append(Vector3(0.0, 0.0, length - 0.5))
	for bar: Dictionary in bars:
		var p: Vector3 = bar["point"]
		# drop any straight-line node the barrier now stands on
		for i in range(pts.size() - 1, -1, -1):
			if absf(pts[i].z - p.z) < 1.6:
				pts.remove_at(i)
		pts.append(p - Vector3(0.0, 0.0, 1.0))
		pts.append(p)
		pts.append(p + Vector3(0.0, 0.0, 1.0))
	pts.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.z < b.z)
	graph.chain(pts)

	room["exit_portal"] = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, length + Kit.WALL * 2.0))
	room["footprint"] = AABB(Vector3(-outer - 0.25, -0.3, z0 - 0.05),
		Vector3((outer + 0.25) * 2.0, Kit.CEIL + Kit.SLAB + 0.6, span + 0.1))
	return room


# --- DONUT --------------------------------------------------------------------

## An octagonal ring around a solid core. Four of the eight outer segments have
## doorways: the one you came in by, and three ahead. Two of those three are
## boarded, and only the third has a room behind it. With `collapse` on, one
## way round is jammed solid with rubble and the other comes down on you as you
## arrive: a shelf unit off the wall, a chair under it, and a gap beneath.
static func build_donut(frame_xf: Transform3D, opts: Dictionary) -> Dictionary:
	var rng := opts["rng"] as RandomNumberGenerator
	var house := opts["house"] as Node
	var exit_k := int(opts.get("exit_choice", 2))
	var depth := float(opts.get("depth", 0.0))
	var collapse := bool(opts.get("collapse", false))
	var room := _blank("donut", "RoomDonut", frame_xf)
	var root := room["root"] as Node3D

	var c := Vector3(0.0, 0.0, DONUT_R_OUT)
	var seg_out := 2.0 * DONUT_R_OUT * tan(PI / 8.0)
	var seg_in := 2.0 * DONUT_R_IN * tan(PI / 8.0)
	var door_ks := [0, 2, 4]

	# the ring's floor and ceiling go down in strips for the same reason the
	# corridors do: one big slab loses its lamps to the per-mesh cap
	var floor_w := (DONUT_R_OUT + Kit.WALL) * 2.0 + 0.4
	var strips := 5
	var strip := floor_w / float(strips)
	for i in strips:
		var off := (float(i) + 0.5) * strip - floor_w * 0.5
		Kit.split_box(root, Vector3(floor_w, Kit.SLAB, strip),
			c + Vector3(0.0, -Kit.SLAB * 0.5, off), "floor", 0.0, true, depth, 4.0)
		Kit.split_box(root, Vector3(floor_w, Kit.SLAB, strip),
			c + Vector3(0.0, Kit.CEIL + Kit.SLAB * 0.5, off), "ceil", 0.0, true, depth, 4.0)

	for k in 8:
		var d := _dir_of(k)
		var yaw := Vector3(0, 0, 1).signed_angle_to(d, Vector3.UP)
		var out_centre := c + d * (DONUT_R_OUT + Kit.WALL * 0.5)
		if k == 6 or door_ks.has(k):
			Kit.wall_with_door(root, seg_out + 0.3, out_centre, yaw, "wall", Kit.CEIL, depth)
		else:
			Kit.box(root, Vector3(seg_out + 0.3, Kit.CEIL, Kit.WALL),
				out_centre + Vector3(0.0, Kit.CEIL * 0.5, 0.0), "wall", yaw, true, depth)
		Kit.box(root, Vector3(seg_in + 0.3, Kit.CEIL, Kit.WALL),
			c + d * (DONUT_R_IN - Kit.WALL * 0.5) + Vector3(0.0, Kit.CEIL * 0.5, 0.0), "wall", yaw, true, depth)
		# posts at the vertices, hiding the mitre where two segments meet
		var vd := _dir_of_angle(float(k) * PI / 4.0 + PI / 8.0)
		var vyaw := Vector3(0, 0, 1).signed_angle_to(vd, Vector3.UP)
		Kit.box(root, Vector3(0.26, Kit.CEIL, 0.26),
			c + vd * ((DONUT_R_OUT + Kit.WALL * 0.5) / cos(PI / 8.0)) + Vector3(0.0, Kit.CEIL * 0.5, 0.0),
			"wall", vyaw, true, depth)
		Kit.box(root, Vector3(0.24, Kit.CEIL, 0.24),
			c + vd * ((DONUT_R_IN - Kit.WALL * 0.5) / cos(PI / 8.0)) + Vector3(0.0, Kit.CEIL * 0.5, 0.0),
			"wall", vyaw, true, depth)

	var exit_d := _dir_of(exit_k)
	_exit_doorway(room, frame_xf, c + exit_d * (DONUT_R_OUT + Kit.WALL), exit_d, house, "donut exit", depth)
	var fake := 0
	for k: int in door_ks:
		if k == exit_k:
			continue
		var d := _dir_of(k)
		_fake_doorway(room, frame_xf, c + d * (DONUT_R_OUT + Kit.WALL), d, house,
			"donut dead %d" % fake, rng)
		fake += 1

	# which way round is blocked: the short way if there is one, so the room
	# costs the full loop; otherwise whichever
	var block_side := 0.0
	if collapse:
		if exit_k == 0:
			block_side = 1.0
		elif exit_k == 4:
			block_side = -1.0
		else:
			block_side = 1.0 if rng.randf() < 0.5 else -1.0
	var open_side := -block_side
	var r_mid := (DONUT_R_OUT + DONUT_R_IN) * 0.5
	var ring_w := DONUT_R_OUT - DONUT_R_IN

	_spill(room, Vector3(0.0, Kit.CEIL - 0.3, 1.3))
	for k in 8:
		var d := _dir_of(k)
		# only the working door is lit head on; the boarded ones sit in the dark
		var near_exit := d.dot(exit_d) > 0.9
		var alive := near_exit or (k % 2 == 1 and k != 5)
		# the collapse is lit so you see what to duck under; the rubble is not
		if collapse and (k == 5 or k == 7):
			alive = signf(d.x) == open_side
		var l := _lamp(room, c + d * (DONUT_R_OUT - 0.55) + Vector3(0.0, Kit.CEIL - 0.3, 0.0), rng, depth,
			0.85 if near_exit else 0.6, 4.2, true, alive)
		if not alive:
			l.visible = false
			(l.get_meta("bulb") as Node3D).visible = false

	_entry(room, Vector3(0.0, 1.1, 0.6))
	room["spawn"] = Vector3(0.0, 0.0, 1.0)

	var graph := room["graph"] as NavGraphScript
	var ring: Array[int] = []
	for i in 16:
		ring.append(graph.add(c + _dir_of_angle(float(i) * PI / 8.0) * r_mid))
	for i in 16:
		# the rubble sits between ring nodes 10 and 11 (left) or 13 and 14 (right)
		if collapse and ((block_side < 0.0 and i == 10) or (block_side > 0.0 and i == 13)):
			continue
		graph.link(ring[i], ring[(i + 1) % 16])
	var entry_node := graph.add(Vector3(0.0, 0.0, 0.7))
	_link_nearest(graph, entry_node, ring, 2)
	var exit_node := graph.add(c + exit_d * (DONUT_R_OUT - 0.8))
	_link_nearest(graph, exit_node, ring, 2)

	if collapse:
		# rubble: a full jam across the ring one segment round on the blocked
		# side; the collapse one segment round on the open side. block_side is
		# the sign of local x the jam sits on, and +34 degrees off the entry
		# direction (270) is the +x side, so the offsets carry that sign.
		var a_block := deg_to_rad(270.0 + block_side * 34.0)
		var a_fall := deg_to_rad(270.0 + open_side * 30.0)
		var a_trig := deg_to_rad(270.0 + open_side * 13.0)
		var d_block := _dir_of_angle(a_block)
		var d_fall := _dir_of_angle(a_fall)
		Kit.rubble(root, c + d_block * r_mid, d_block, ring_w + 0.2, 0.9, house, rng, depth)
		# the way under it runs around the ring, away from the entry: that is
		# the tangent taken in the direction the player is already going
		var tangent := d_fall.rotated(Vector3.UP, -PI * 0.5 * open_side)
		var along_yaw := Vector3(0, 0, 1).signed_angle_to(tangent, Vector3.UP)
		var cr := Kit.crawl(root, c + d_fall * r_mid, d_fall, ring_w, along_yaw, house, rng, depth, true)
		(room["crawls"] as Array).append({"aabb": cr["aabb"], "through": cr["through"]})
		(room["lights"] as Array).append(cr["light"])
		var trig := Kit.trigger(root, Vector3(ring_w + 0.4, 2.2, 1.2), c + _dir_of_angle(a_trig) * r_mid + Vector3(0.0, 1.1, 0.0),
			"CollapseTrigger")
		trig.rotation.y = Vector3(0, 0, 1).signed_angle_to(_dir_of_angle(a_trig).rotated(Vector3.UP, PI * 0.5), Vector3.UP)
		(room["events"] as Array).append({"trigger": trig, "play": Callable(Kit, "play_collapse").bind(cr)})
		room["head_start"] = float(room["head_start"]) + CRAWL_HEAD_START + 0.6
	else:
		var spots: Array[Vector3] = []
		for k in [1, 3, 5, 7]:
			var d := _dir_of(k)
			spots.append(c + d * (DONUT_R_OUT - 0.55) + d.rotated(Vector3.UP, PI * 0.5) * rng.randf_range(-1.5, 1.5))
		_junk(room, frame_xf, house, rng, depth, spots, true, JUNK_BIG)

	var ang := Vector3(0, 0, 1).signed_angle_to(exit_d, Vector3.UP)
	room["exit_portal"] = Transform3D(Basis(Vector3.UP, ang), c + exit_d * (DONUT_R_OUT + Kit.WALL * 2.0))
	var reach := DONUT_R_OUT + Kit.WALL + 0.25
	room["footprint"] = AABB(c - Vector3(reach, 0.3, reach),
		Vector3(reach * 2.0, Kit.CEIL + Kit.SLAB + 0.6, reach * 2.0))
	return room


static func _dir_of(k: int) -> Vector3:
	return _dir_of_angle(float(k) * PI / 4.0)


static func _dir_of_angle(a: float) -> Vector3:
	return Vector3(cos(a), 0.0, sin(a))


static func _link_nearest(graph: NavGraphScript, node: int, pool: Array[int], count: int) -> void:
	var by_dist := pool.duplicate()
	var here := graph.points[node]
	by_dist.sort_custom(func(a: int, b: int) -> bool:
		return graph.points[a].distance_squared_to(here) < graph.points[b].distance_squared_to(here))
	for i in mini(count, by_dist.size()):
		graph.link(node, by_dist[i])


# --- STAIRS -------------------------------------------------------------------

## A short hall with a boarded door dead ahead and an opening in one wall: the
## stairs go down to a second hall running the same way, one storey lower.
## `mirror` puts the branch on -x. (The climbing variant is not built yet.)
static func build_stairs(frame_xf: Transform3D, opts: Dictionary) -> Dictionary:
	var rng := opts["rng"] as RandomNumberGenerator
	var house := opts["house"] as Node
	var depth := float(opts.get("depth", 0.0))
	var sx := -1.0 if int(opts.get("variant", 0)) % 2 == 1 else 1.0
	var room := _blank("stairs", "RoomStairs", frame_xf)
	var root := room["root"] as Node3D

	var half := STAIR_W * 0.5
	var outer := half + Kit.WALL
	# hall A runs z 0..A_LEN, the branch leaves through its side at z 3.4..4.6
	var a_len := 6.4
	var op0 := 3.4
	var op1 := 4.6
	var steps := 8
	var rise := -0.18
	var run := 0.28
	var drop := rise * steps
	var x_flight := half + 1.2
	var x_bot := x_flight + run * steps
	var b_centre := x_bot + 0.85
	var b_z0 := 2.8
	var b_len := 9.2

	# --- hall A
	Kit.split_box(root, Vector3((outer + x_flight) , Kit.SLAB, a_len + 0.46),
		Vector3(sx * (x_flight - outer) * 0.5, -Kit.SLAB * 0.5, (a_len + 0.46) * 0.5 - 0.16), "floor", 0.0, true, depth)
	Kit.split_box(root, Vector3(outer * 2.0, Kit.SLAB, a_len + 0.46),
		Vector3(0.0, Kit.CEIL + Kit.SLAB * 0.5, (a_len + 0.46) * 0.5 - 0.16), "ceil", 0.0, true, depth)
	Kit.split_box(root, Vector3(Kit.WALL, Kit.CEIL, a_len + 0.46),
		Vector3(-sx * (half + Kit.WALL * 0.5), Kit.CEIL * 0.5, (a_len + 0.46) * 0.5 - 0.16), "wall", 0.0, true, depth)
	# the branch side, in two pieces around the opening
	Kit.box(root, Vector3(Kit.WALL, Kit.CEIL, op0 + 0.16),
		Vector3(sx * (half + Kit.WALL * 0.5), Kit.CEIL * 0.5, (op0 - 0.16) * 0.5), "wall", 0.0, true, depth)
	Kit.split_box(root, Vector3(Kit.WALL, Kit.CEIL, a_len + 0.3 - op1),
		Vector3(sx * (half + Kit.WALL * 0.5), Kit.CEIL * 0.5, (op1 + a_len + 0.3) * 0.5), "wall", 0.0, true, depth)
	Kit.wall_with_door(root, outer * 2.0, Vector3(0.0, 0.0, -Kit.WALL * 0.5), 0.0, "wall", Kit.CEIL, depth)
	# the dead end: a double wall so the frame is buried, and it is boarded
	Kit.wall_with_door(root, outer * 2.0, Vector3(0.0, 0.0, a_len + Kit.WALL * 0.5), 0.0, "wall", Kit.CEIL, depth)
	Kit.wall_with_door(root, outer * 2.0, Vector3(0.0, 0.0, a_len + Kit.WALL * 1.5), 0.0, "wall", Kit.CEIL, depth)
	_fake_doorway(room, frame_xf, Vector3(0.0, 0.0, a_len + Kit.WALL), Vector3(0, 0, 1), house,
		"stairs dead", rng)

	# --- the branch: landing, flight, and the walls either side of both
	var branch_h := Kit.CEIL + absf(drop) + 0.4
	for s in [-1.0, 1.0]:
		var wz := (op0 - Kit.WALL * 0.5) if s < 0.0 else (op1 + Kit.WALL * 0.5)
		Kit.box(root, Vector3(x_bot - half + 0.3, branch_h, Kit.WALL),
			Vector3(sx * (half + (x_bot - half) * 0.5), Kit.CEIL - branch_h * 0.5, wz), "wall", 0.0, true, depth)
	# butts against hall A's ceiling at the wall line rather than overlapping it
	Kit.box(root, Vector3(x_flight - outer, Kit.SLAB, op1 - op0 + Kit.WALL * 2.0),
		Vector3(sx * (outer + (x_flight - outer) * 0.5), Kit.CEIL + Kit.SLAB * 0.5, (op0 + op1) * 0.5), "ceil", 0.0, true, depth)
	var flight_from := Vector3(sx * x_flight, 0.0, (op0 + op1) * 0.5)
	Kit.stairs(root, flight_from, Vector3(sx, 0.0, 0.0), op1 - op0, steps, rise, run)
	# a sloped ceiling following the flight down, so the stairwell stays a hall
	var slope_len := Vector2(run * steps, drop).length()
	var pitch := atan2(drop, run * steps)
	var slope := MeshInstance3D.new()
	var slope_mesh := BoxMesh.new()
	slope_mesh.size = Vector3(op1 - op0 + Kit.WALL * 2.0, Kit.SLAB, slope_len)
	slope.mesh = slope_mesh
	slope.material_override = Kit.mat("ceil", depth)
	slope.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	slope.basis = Basis(Vector3.UP, Vector3(0, 0, 1).signed_angle_to(Vector3(sx, 0, 0), Vector3.UP)) \
		* Basis(Vector3(1, 0, 0), -pitch)
	slope.position = flight_from + Vector3(sx * run * steps * 0.5, Kit.CEIL + drop * 0.5 + Kit.SLAB * 0.5,
		0.0)
	root.add_child(slope)

	# --- hall B, one storey down and running the same way
	var b_span := b_len + 0.46 - b_z0
	var b_mid := (b_z0 + b_len + 0.3) * 0.5
	Kit.split_box(root, Vector3(outer * 2.0, Kit.SLAB, b_span), Vector3(sx * b_centre, drop - Kit.SLAB * 0.5, b_mid), "floor", 0.0, true, depth)
	Kit.split_box(root, Vector3(outer * 2.0, Kit.SLAB, b_span),
		Vector3(sx * b_centre, drop + Kit.CEIL + Kit.SLAB * 0.5, b_mid), "ceil", 0.0, true, depth)
	Kit.split_box(root, Vector3(Kit.WALL, Kit.CEIL, b_span),
		Vector3(sx * (b_centre + half + Kit.WALL * 0.5), drop + Kit.CEIL * 0.5, b_mid), "wall", 0.0, true, depth)
	# the stair side, opened where the flight arrives
	Kit.box(root, Vector3(Kit.WALL, Kit.CEIL, op0 - b_z0 + Kit.WALL),
		Vector3(sx * (b_centre - half - Kit.WALL * 0.5), drop + Kit.CEIL * 0.5, (b_z0 - Kit.WALL + op0) * 0.5), "wall", 0.0, true, depth)
	Kit.split_box(root, Vector3(Kit.WALL, Kit.CEIL, b_len + 0.3 - op1),
		Vector3(sx * (b_centre - half - Kit.WALL * 0.5), drop + Kit.CEIL * 0.5, (op1 + b_len + 0.3) * 0.5), "wall", 0.0, true, depth)
	Kit.box(root, Vector3(outer * 2.0, Kit.CEIL, Kit.WALL),
		Vector3(sx * b_centre, drop + Kit.CEIL * 0.5, b_z0 - Kit.WALL * 0.5), "wall", 0.0, true, depth)
	Kit.wall_with_door(root, outer * 2.0, Vector3(sx * b_centre, drop, b_len + Kit.WALL * 0.5), 0.0, "wall", Kit.CEIL, depth)
	_exit_doorway(room, frame_xf, Vector3(sx * b_centre, drop, b_len + Kit.WALL), Vector3(0, 0, 1),
		house, "stairs exit", depth)

	_spill(room, Vector3(0.0, Kit.CEIL - 0.3, 1.3))
	# the one live lamp over the top of the flight is the whole cue
	_lamp(room, Vector3(sx * (half + 0.6), Kit.CEIL - 0.3, (op0 + op1) * 0.5), rng, depth, 0.9, 4.6, true, true)
	var dead := Kit.lamp(root, Vector3(0.0, Kit.CEIL - 0.3, a_len - 1.2), 0.8, 4.0)
	dead.visible = false
	(dead.get_meta("bulb") as Node3D).visible = false
	(room["lights"] as Array).append(dead)
	_lamp(room, Vector3(sx * b_centre, drop + Kit.CEIL - 0.3, 6.4), rng, depth, 0.75, 4.4, true, true)

	# the way out of hall B closes up too: you come off the stairs and the far
	# end is half gone
	var bar_z := rng.randf_range(6.2, 7.6)
	var bar_side := 1.0 if rng.randf() < 0.5 else -1.0
	var bar_crouch := rng.randf() < lerpf(0.25, 0.7, depth)
	var bar := Kit.barrier(root, Vector3(sx * b_centre, drop, bar_z), Vector3(1, 0, 0), STAIR_W, 0.0,
		bar_side, clampf(STAIR_W * 0.46, 0.78, 1.2), bar_crouch, house, rng, depth)
	(room["lights"] as Array).append(bar["light"])
	if bar_crouch:
		(room["crawls"] as Array).append({"aabb": bar["aabb"], "through": bar["through"]})
		room["head_start"] = float(room["head_start"]) + CRAWL_HEAD_START
	else:
		room["head_start"] = float(room["head_start"]) + 0.5
	var bar_point: Vector3 = bar["gap_point"]

	# windows: one in hall A by the flight, a couple down hall B
	for wz in [2.2, a_len - 1.5]:
		var at := Vector3(-sx * (half - 0.02), 1.45, float(wz))
		(room["panes"] as Array).append(Kit.window(root, at, Vector3(sx, 0, 0), 1.0, 1.3, depth))
	for wz in [4.4, 8.4]:
		var at := Vector3(sx * (b_centre + half - 0.02), drop + 1.45, float(wz))
		(room["panes"] as Array).append(Kit.window(root, at, Vector3(-sx, 0, 0), 1.0, 1.3, depth))

	# junk in the dead end and along hall B, never on the flight
	var spots: Array[Vector3] = [
		Vector3(-sx * (half - 0.35), 0.0, a_len - 0.9),
		Vector3(sx * (half - 0.35), 0.0, a_len - 1.6),
		Vector3(sx * (b_centre + half - 0.35), drop, 4.4),
		Vector3(sx * (b_centre - half + 0.35), drop, 5.2),
		Vector3(-sx * (half - 0.35), 0.0, 1.9),
	]
	# Hall B is only STAIR_W wide and this junk is solid, dropped at a random
	# yaw and sometimes tipped on its side, so a piece near the way out or in
	# the barrier's gap can span what is left and seal the corridor. Hold it
	# off both -- the same rule build_long applies through _clear_of. Hall A
	# spots sit at y 0 and are not in the running lane, so they are left alone.
	var bar_plan: Array[Dictionary] = [{"z": bar_z}]
	var placeable: Array[Vector3] = []
	for spot in spots:
		if is_equal_approx(spot.y, drop):
			if not _clear_of(bar_plan, spot.z, JUNK_CLEAR):
				continue
			if spot.z > b_len - JUNK_CLEAR:
				continue
		placeable.append(spot)
	_junk(room, frame_xf, house, rng, depth, placeable, true, JUNK_HALL)

	_entry(room)
	room["spawn"] = Vector3(0.0, 0.0, 1.0)

	var graph := room["graph"] as NavGraphScript
	var mid_z := (op0 + op1) * 0.5
	graph.chain([
		Vector3(0.0, 0.0, 0.6),
		Vector3(0.0, 0.0, mid_z),
		Vector3(sx * (half + 0.5), 0.0, mid_z),
		Vector3(sx * x_flight, 0.0, mid_z),
		Vector3(sx * x_bot, drop, mid_z),
		Vector3(sx * b_centre, drop, mid_z),
		Vector3(sx * b_centre, drop, bar_z - 1.2),
		bar_point,
		Vector3(sx * b_centre, drop, bar_z + 1.2),
		Vector3(sx * b_centre, drop, b_len - 0.6),
	])
	var dead_end := graph.add(Vector3(0.0, 0.0, a_len - 0.9))
	graph.link(dead_end, 1)

	room["exit_portal"] = Transform3D(Basis.IDENTITY,
		Vector3(sx * b_centre, drop, b_len + Kit.WALL * 2.0))
	var x_lo := minf(-outer, sx * (b_centre + outer))
	var x_hi := maxf(outer, sx * (b_centre + outer))
	room["footprint"] = AABB(
		Vector3(x_lo - 0.25, drop - 0.3, -0.25),
		Vector3(x_hi - x_lo + 0.5, Kit.CEIL + Kit.SLAB + absf(drop) + 0.6, b_len + 0.55))
	return room


# --- GARDEN -------------------------------------------------------------------

## A hedge corridor under the night sky: grass, a concrete path, three low
## lamps and a moon. Trees over the hedges, bushes poking through them, and
## flowers at their feet. No ceiling, which is the whole point of it.
static func build_garden(frame_xf: Transform3D, opts: Dictionary) -> Dictionary:
	var rng := opts["rng"] as RandomNumberGenerator
	var house := opts["house"] as Node
	var depth := float(opts.get("depth", 0.0))
	var room := _blank("garden", "RoomGarden", frame_xf)
	var root := room["root"] as Node3D
	var lights := room["lights"] as Array

	var length := rng.randf_range(16.0, 20.0)
	var half := GARDEN_W * 0.5
	var z0 := -0.16
	var z1 := length + 0.16
	var span := z1 - z0
	var mid := (z0 + z1) * 0.5
	var hedge_x := half + 0.3
	var hedge_h := 2.4

	Kit.split_box(root, Vector3(GARDEN_W + 2.4, Kit.SLAB, span), Vector3(0.0, -Kit.SLAB * 0.5, mid), "grass", 0.0, true, depth)
	Kit.box(root, Vector3(1.2, 0.03, length - 1.0), Vector3(0.0, 0.005, length * 0.5), "path", 0.0, false, depth)
	for s in [-1.0, 1.0]:
		Kit.box(root, Vector3(0.05, 0.05, length - 1.0), Vector3(s * 0.63, 0.02, length * 0.5), "plank", 0.0, false, depth)
		Kit.split_box(root, Vector3(0.6, hedge_h, span), Vector3(s * hedge_x, hedge_h * 0.5, mid), "hedge", 0.0, true, depth)
		# trees behind the hedge line, bushes pushing up through it, flowers at
		# its foot on the path side
		var tz := rng.randf_range(2.0, 5.0)
		while tz < length - 2.0:
			var tree := "Tree_04_059" if rng.randf() < 0.6 else "Tree_03_008"
			Kit.dressing_dup(house, tree, root, frame_xf, Vector3(s * rng.randf_range(4.6, 5.4), -0.4, tz),
				rng.randf_range(0.0, TAU))
			tz += rng.randf_range(5.0, 8.0)
		var bz := rng.randf_range(1.0, 3.0)
		while bz < length - 1.0:
			Kit.dressing_dup(house, "Bush", root, frame_xf, Vector3(s * (hedge_x + 0.35), 0.5, bz),
				rng.randf_range(0.0, TAU))
			bz += rng.randf_range(2.6, 4.2)
		# at the hedge foot on the path side, standing on the grass where the
		# whole plant is visible. Behind the hedge they were either hidden
		# outright or, at bed size, hanging through it with no ground under them
		var fz := rng.randf_range(1.5, 4.0)
		while fz < length - 1.5:
			var flower: String = FLOWERS[rng.randi_range(0, FLOWERS.size() - 1)]
			Kit.dressing_dup(house, flower, root, frame_xf, Vector3(s * 1.45, 0.0, fz),
				rng.randf_range(0.0, TAU))
			fz += rng.randf_range(4.5, 6.5)

	Kit.wall_with_door(root, GARDEN_W + 1.2, Vector3(0.0, 0.0, -Kit.WALL * 0.5), 0.0, "wall", Kit.CEIL, depth)
	Kit.wall_with_door(root, GARDEN_W + 1.2, Vector3(0.0, 0.0, length + Kit.WALL * 0.5), 0.0, "wall", Kit.CEIL, depth)
	_exit_doorway(room, frame_xf, Vector3(0.0, 0.0, length + Kit.WALL), Vector3(0, 0, 1), house, "garden exit", depth)

	# the moon: a lit sphere far enough back to read as sky, no light of its own
	var moon := MeshInstance3D.new()
	var ms := SphereMesh.new()
	ms.radius = 1.4
	ms.height = 2.8
	ms.radial_segments = 16
	ms.rings = 8
	moon.mesh = ms
	moon.material_override = Kit.mat("moon")
	moon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	moon.position = Vector3(3.0, 24.0, length * 0.5 + 8.0)
	root.add_child(moon)
	# Moonlight comes down the whole length rather than from one point: a single
	# lamp nine metres up is too far from the ground to reach it, and the far
	# end of the garden ends up in the dark.
	var mz := 2.0
	while mz < length:
		var moonlight := Kit.lamp(root, Vector3(0.0, 5.5, mz), lerpf(1.3, 0.85, depth), 11.0, false, false)
		moonlight.light_color = Color(0.62, 0.68, 0.9)
		lights.append(moonlight)
		mz += 6.0

	_spill(room, Vector3(0.0, 2.4, 1.2), 4.5)
	# the path lamps are the only thing telling you where the path runs, so
	# they never die: they flicker at worst
	for f in [0.2, 0.4, 0.6, 0.8]:
		var z := length * float(f)
		var side := 1.0 if int(f * 10.0) % 4 == 0 else -1.0
		var lean := rng.randf_range(-0.25, 0.25) * depth
		var post := Kit.box(root, Vector3(0.09, 1.05, 0.09), Vector3(side * 1.4, 0.525, z), "black") as Node3D
		post.rotation.z = lean
		var l := Kit.lamp(root, Vector3(side * 1.4 - sin(lean) * 1.05, 1.12, z), 0.95, 5.0, true, false)
		if f == 0.4 or rng.randf() < depth:
			l.set_meta("flicker", true)
		lights.append(l)
		(room["shafts"] as Array).append(
			Kit.shaft(root, l.position, 1.0, 0.5, Color(1.0, 0.88, 0.66), 0.3))

	# junk on the grass edges, deeper in
	var spots: Array[Vector3] = []
	var jz := 3.0
	while jz < length - 2.5:
		spots.append(Vector3((1.0 if rng.randf() < 0.5 else -1.0) * rng.randf_range(0.9, 1.3), 0.0, jz))
		jz += rng.randf_range(3.0, 4.5)
	_junk(room, frame_xf, house, rng, depth, spots, true, JUNK_GARDEN)

	_entry(room)
	room["spawn"] = Vector3(0.0, 0.0, 1.0)
	(room["loops"] as Array).append(["room_tone", Vector3(0.0, 1.6, length * 0.5), -26.0])
	(room["loops"] as Array).append(["rain", Vector3(0.0, 2.6, length * 0.5), -18.0])

	var graph := room["graph"] as NavGraphScript
	var pts: Array[Vector3] = [Vector3(0.0, 0.0, 0.6)]
	var g := 4.0
	while g < length - 0.8:
		pts.append(Vector3(0.0, 0.0, g))
		g += 4.0
	pts.append(Vector3(0.0, 0.0, length - 0.5))
	graph.chain(pts)

	room["exit_portal"] = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, length + Kit.WALL * 2.0))
	# wide on purpose: with no ceiling, anything placed close would be visible
	# over the hedges
	room["footprint"] = AABB(Vector3(-5.5, -0.3, z0 - 0.05), Vector3(11.0, Kit.CEIL + 0.6, span + 0.1))
	return room


# --- VESTIBULE ----------------------------------------------------------------

## Room 0: the corridor stub in front of the real bathroom door, rebuilt to the
## millimetre and pushed sideways by CHASE_OFFSET. Built in real house
## coordinates - the root carries the offset - so the seam warp is one add.
static func build_vestibule(frame_xf: Transform3D, opts: Dictionary) -> Dictionary:
	var house := opts["house"] as Node
	var room := _blank("vestibule", "RoomVestibule", frame_xf)
	var root := room["root"] as Node3D
	var lights := room["lights"] as Array

	var y := VEST_FLOOR_Y
	var height := VEST_CEIL_Y - VEST_FLOOR_Y
	var x0 := VEST_WEST_X - Kit.WALL
	var x1 := VEST_EAST_X + Kit.WALL
	var z0 := VEST_SOUTH_Z - Kit.WALL
	var z1 := VEST_NORTH_Z
	var cx := (VEST_WEST_X + VEST_EAST_X) * 0.5
	var cz := (z0 + z1) * 0.5
	var w := x1 - x0
	var d := z1 - z0

	Kit.box(root, Vector3(w, Kit.SLAB, d), Vector3((x0 + x1) * 0.5, y - Kit.SLAB * 0.5, cz), "floor")
	Kit.box(root, Vector3(w, Kit.SLAB, d), Vector3((x0 + x1) * 0.5, VEST_CEIL_Y + Kit.SLAB * 0.5, cz), "ceil")
	Kit.box(root, Vector3(Kit.WALL, height, d),
		Vector3(VEST_WEST_X - Kit.WALL * 0.5, y + height * 0.5, cz), "wall")
	Kit.box(root, Vector3(w, height, Kit.WALL),
		Vector3((x0 + x1) * 0.5, y + height * 0.5, VEST_SOUTH_Z - Kit.WALL * 0.5), "wall")
	# east wall: the bathroom door's own wall, hole and all
	Kit.wall_with_door(root, d, Vector3(VEST_EAST_X + Kit.WALL * 0.5, y, VEST_DOOR_POINT.z),
		Vector3(0, 0, 1).signed_angle_to(Vector3(1, 0, 0), Vector3.UP), "wall", height)
	# north wall: another shut door, locked, so the stub reads as a real corridor
	Kit.wall_with_door(root, w, Vector3((x0 + x1) * 0.5, y, VEST_NORTH_DOOR_POINT.z - Kit.WALL * 0.5),
		0.0, "wall", height)

	var vest_door := Kit.doorway(root, frame_xf, VEST_DOOR_POINT, Vector3(1, 0, 0), house,
		{"name": "vest door", "swing_time": 0.5, "open_angle": 105.0})
	if vest_door != null:
		(room["doors"] as Array).append(vest_door)
		room["exit_door"] = vest_door
	var north := Kit.doorway(root, frame_xf, VEST_NORTH_DOOR_POINT, Vector3(0, 0, 1), house,
		{"name": "vest north", "locked": true, "locked_prompt": "Locked"})
	if north != null:
		(room["doors"] as Array).append(north)
		(room["fake_doors"] as Array).append(north)

	# the only light in here is what leaks under the bathroom door
	var spill := Kit.lamp(root, Vector3(VEST_EAST_X - 0.13, y + 0.07, VEST_DOOR_POINT.z), 0.35, 1.6, true, false)
	room["spill_light"] = spill
	lights.append(spill)

	room["spawn"] = Vector3(cx, y, VEST_DOOR_POINT.z - 0.9)
	var graph := room["graph"] as NavGraphScript
	graph.chain([
		Vector3(cx, y, VEST_SOUTH_Z + 0.6),
		Vector3(cx, y, VEST_DOOR_POINT.z),
	])

	var ang := Vector3(0, 0, 1).signed_angle_to(Vector3(1, 0, 0), Vector3.UP)
	room["exit_portal"] = Transform3D(Basis(Vector3.UP, ang),
		Vector3(x1 + Kit.WALL, y, VEST_DOOR_POINT.z))
	room["footprint"] = AABB(Vector3(x0 - 0.2, y - 0.5, z0 - 0.2),
		Vector3(w + 0.4, height + Kit.SLAB + 0.7, d + 0.4))
	room["head_start"] = 99.0
	return room


# --- THRESHOLD ----------------------------------------------------------------

## Room 11: a black stub with nothing in it. The door shuts, and the next thing
## the kid sees is the bathroom light coming on.
static func build_threshold(frame_xf: Transform3D, _opts: Dictionary) -> Dictionary:
	var room := _blank("threshold", "RoomThreshold", frame_xf)
	var root := room["root"] as Node3D
	var length := 2.4
	var half := 0.85
	var outer := half + Kit.WALL
	var z0 := -0.16
	var span := length + 0.32
	var mid := length * 0.5

	Kit.box(root, Vector3(outer * 2.0, Kit.SLAB, span), Vector3(0.0, -Kit.SLAB * 0.5, mid), "black")
	Kit.box(root, Vector3(outer * 2.0, Kit.SLAB, span), Vector3(0.0, Kit.CEIL + Kit.SLAB * 0.5, mid), "black")
	for s in [-1.0, 1.0]:
		Kit.box(root, Vector3(Kit.WALL, Kit.CEIL, span),
			Vector3(s * (half + Kit.WALL * 0.5), Kit.CEIL * 0.5, mid), "black")
	Kit.wall_with_door(root, outer * 2.0, Vector3(0.0, 0.0, -Kit.WALL * 0.5), 0.0, "black")
	Kit.box(root, Vector3(outer * 2.0, Kit.CEIL, Kit.WALL),
		Vector3(0.0, Kit.CEIL * 0.5, length + Kit.WALL * 0.5), "black")

	_entry(room, Vector3(0.0, 1.1, 0.9))
	room["spawn"] = Vector3(0.0, 0.0, 1.0)
	(room["graph"] as NavGraphScript).chain([Vector3(0.0, 0.0, 0.4), Vector3(0.0, 0.0, length - 0.4)])
	room["exit_portal"] = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, length + Kit.WALL * 2.0))
	room["footprint"] = AABB(Vector3(-outer - 0.2, -0.3, z0 - 0.05),
		Vector3((outer + 0.2) * 2.0, Kit.CEIL + Kit.SLAB + 0.6, span + 0.1))
	room["head_start"] = 99.0
	return room
