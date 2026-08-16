class_name DreamRooms
extends RefCounted
## The two rooms of the dream act, built at runtime like the chase ones.
##
## Same frame convention as chase_rooms.gd: a room's origin is the centre of its
## entry doorway at floor level on the room's side of the entry wall, +z runs
## into the room, +x is right facing +z. A room's own transform IS its world
## transform; the director hangs them off a ChaseWorld-style node left at the
## origin and bakes the offset into the frames.
##
## Both builders return a plain Dictionary of handles. Nothing here keeps state
## and nothing here runs per frame - the director drives all of it.

const Kit := preload("res://scripts/chase_kit.gd")
const PillowTexScript := preload("res://scripts/pillow_tex.gd")
const VOID_SHADER := preload("res://scripts/void_wall.gdshader")

# --- the pillow hall ---------------------------------------------------------

## Freakishly large is the whole point, so these are not corridor numbers.
const HALL_W := 46.0
const HALL_L := 46.0
const HALL_H := 30.0
## The stub you arrive in. Low and tight, so the doorway out of it is the reveal.
const STUB_L := 3.4
const STUB_W := 1.9

const PILLAR_C := Vector3(0.0, 0.0, 23.0)
const PILLAR_R := 1.9
const STAIR_W := 1.4
const STEP_RISE := 0.19
const STEP_COUNT := 89
## Radians per step. About seventy centimetres of tread at the walked radius,
## which puts the flight at fifteen degrees: a climb, not a scramble. The exact
## value is picked so the top of the flight lands a hundred degrees round from
## +x, which is what puts the solid half of the landing where the fall needs it.
const STEP_TURN := 0.28044
const START_ANGLE := -PI * 0.5
const TOP_Y := STEP_RISE * float(STEP_COUNT)
## Steps that come up through the stairwell rather than into the landing's
## underside. Eleven of them clears the last two metres of climb, and leaves the
## step below the landing with 1.8 m of headroom.
const WELL_STEPS := 11
const PLATFORM_R := 3.5
const PLATFORM_T := 0.34
const PLINTH_T := 0.55
## Slices in the landing ring, and the pieces of tongue that carry the top of
## the flight onto it.
const RING_SIDES := 24
const TONGUE_PIECES := 5
const TONGUE_W := 0.9
const TONGUE_STEP := 0.18
## Where the toy stands.
const TOY_Y := TOP_Y + PLINTH_T

## Exit is on the +x wall near the entry end, so once the dark starts sweeping
## down the room the way out is the way away from it.
const EXIT_Z := 6.0
const WIN_W := 7.0
const WIN_H := 11.0
const WIN_Y := 7.5
const WIN_Z := [15.0, 31.0]

# --- the endless hall --------------------------------------------------------

const RUN_W := 1.9
## Short segments, laid on a grid the director slides along under the player.
## Short because the band of them has to stop cleanly just short of the door,
## and the granularity of "just short" is one segment.
const RUN_SEG := 6.0
const RUN_SEGS := 7
## How far ahead the door sits while it is running away from you.
const RUN_GAP := 32.0
## Corridor the door carries with it, so there is never a gap between the last
## segment and the wall it is set in.
const RUN_PLUG := 7.0
const BATH_W := 3.5
const BATH_L := 4.0


static func _blank(type: String, room_name: String, frame_xf: Transform3D) -> Dictionary:
	var root := Node3D.new()
	root.name = room_name
	root.transform = frame_xf
	return {
		"root": root,
		"type": type,
		"spawn": Vector3.ZERO,
		"doors": [],
		"lights": [],
		"panes": [],
		"shafts": [],
		"motes": [],
	}


## A basis whose +y points along `up`. The kit has one of these but it is
## private, and a light shaft aimed out of a window needs it.
static func _aim_up(up: Vector3) -> Basis:
	var y := up.normalized()
	var ref := Vector3(1, 0, 0) if absf(y.x) < 0.9 else Vector3(0, 0, 1)
	var z := ref.cross(y).normalized()
	var x := y.cross(z).normalized()
	return Basis(x, y, z)


## A light cone aimed anywhere, not just straight down. `shaft` places its cone
## by dropping it below the source and only then turning it, which is fine for a
## bulb and wrong for a window.
static func _aimed_shaft(parent: Node3D, from: Vector3, dir: Vector3, drop: float, spread: float,
		tint: Color, energy: float) -> MeshInstance3D:
	var s := Kit.shaft(parent, from, drop, spread, tint, energy)
	var d := dir.normalized()
	s.basis = _aim_up(-d)
	s.position = from + d * (drop * 0.5)
	return s


## The pillow hall, and the corridor stub you walk out of into it.
##
## opts: {"house": Node, "rng": RandomNumberGenerator}
static func build_pillow_hall(frame_xf: Transform3D, opts: Dictionary) -> Dictionary:
	var room := _blank("pillow", "PillowHall", frame_xf)
	var root := room["root"] as Node3D
	var house: Node = opts.get("house")
	var rng := opts.get("rng") as RandomNumberGenerator
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.seed = 20260816

	var half := HALL_W * 0.5
	var lights: Array[OmniLight3D] = []
	var shafts: Array[MeshInstance3D] = []
	var panes: Array[MeshInstance3D] = []

	_build_stub(root, frame_xf, house, room)
	_build_shell(root, half)
	_build_floor(root, half, rng)
	_build_pillar(root, lights, shafts, room)
	_build_windows(root, lights, shafts, panes, room)
	var exit_door := _build_exit(root, frame_xf, house, lights, shafts, room)

	# a little warm light over the way up, or finding it is a walk round a black
	# pillar with a railing on it
	var foot := Kit.lamp(root, (room["stair_foot"] as Vector3) + Vector3(0.0, 3.6, 0.0),
		0.7, 10.0, true, false, 0.0, 0.0, false)
	lights.append(foot)

	room["lights"] = lights
	room["shafts"] = shafts
	room["panes"] = panes
	room["exit_door"] = exit_door
	room["spawn"] = Vector3(0.0, 0.0, -STUB_L + 1.0)
	room["fall_spawn"] = PILLAR_C + Vector3(0.0, 0.0, -PILLAR_R - 1.6)
	room["toy_at"] = PILLAR_C + Vector3(0.0, TOY_Y, 0.0)
	room["platform_at"] = PILLAR_C + Vector3(0.0, TOP_Y, 0.0)
	room["entry_trigger"] = Kit.trigger(root, Vector3(1.6, 2.4, 1.0), Vector3(0.0, 1.2, 0.8), "hall entry")
	room["stair_trigger"] = Kit.trigger(root, Vector3(2.6, 2.4, 2.6),
		(room["stair_foot"] as Vector3) + Vector3(0.0, 1.2, 0.0), "stair foot")
	room["top_trigger"] = Kit.trigger(root, Vector3(5.4, 2.6, 5.4),
		PILLAR_C + Vector3(0.0, TOP_Y + 1.3, 0.0), "platform")
	room["footprint"] = AABB(Vector3(-half - 0.4, -1.0, -STUB_L - 0.4),
		Vector3(HALL_W + 0.8, HALL_H + 1.6, HALL_L + STUB_L + 0.8))
	return room


static func _build_stub(root: Node3D, frame_xf: Transform3D, house: Node, room: Dictionary) -> void:
	var mid := -STUB_L * 0.5
	var hw := STUB_W * 0.5
	Kit.box(root, Vector3(STUB_W + 0.3, Kit.SLAB, STUB_L + 0.3), Vector3(0.0, -Kit.SLAB * 0.5, mid), "boards")
	Kit.box(root, Vector3(STUB_W + 0.3, Kit.SLAB, STUB_L + 0.3),
		Vector3(0.0, Kit.CEIL + Kit.SLAB * 0.5, mid), "ceil")
	for s in [-1.0, 1.0]:
		Kit.box(root, Vector3(Kit.WALL, Kit.CEIL, STUB_L + 0.3),
			Vector3(s * (hw + Kit.WALL * 0.5), Kit.CEIL * 0.5, mid), "wall")
	Kit.box(root, Vector3(STUB_W + 0.3, Kit.CEIL, Kit.WALL),
		Vector3(0.0, Kit.CEIL * 0.5, -STUB_L - Kit.WALL * 0.5), "wall")
	var l := Kit.lamp(root, Vector3(0.0, 2.5, mid), 0.4, 3.4)
	(room["lights"] as Array).append(l)

	# the door into the hall, hung in the hall's entry wall
	var door := Kit.doorway(root, frame_xf, Vector3.ZERO, Vector3(0, 0, 1), house, {
		"name": "pillow door", "swing_time": 0.7, "open_angle": 100.0, "volume_db": -15.0,
	})
	if door != null:
		(room["doors"] as Array).append(door)
	room["entry_door"] = door


static func _build_shell(root: Node3D, half: float) -> void:
	# entry wall, with the hole the stub door hangs in
	Kit.wall_with_door(root, HALL_W, Vector3(0.0, 0.0, -Kit.WALL * 0.5), 0.0, "wall", HALL_H)
	# far wall
	Kit.split_box(root, Vector3(HALL_W + 0.3, HALL_H, Kit.WALL),
		Vector3(0.0, HALL_H * 0.5, HALL_L + Kit.WALL * 0.5), "wall", 0.0, true, 0.0, 8.0)
	_window_wall(root, -half - Kit.WALL * 0.5)
	# exit wall, in two pieces: the near stretch carries the doorway
	Kit.wall_with_door(root, EXIT_Z * 2.0, Vector3(half + Kit.WALL * 0.5, 0.0, EXIT_Z),
		PI * 0.5, "wall", HALL_H)
	var rest := HALL_L - EXIT_Z * 2.0 + 0.3
	Kit.split_box(root, Vector3(Kit.WALL, HALL_H, rest),
		Vector3(half + Kit.WALL * 0.5, HALL_H * 0.5, EXIT_Z * 2.0 + rest * 0.5 - 0.15),
		"wall", 0.0, true, 0.0, 8.0)
	# nothing up there but dark. Unshaded, so it costs no light budget at all
	Kit.box(root, Vector3(HALL_W + 0.6, Kit.SLAB, HALL_L + 0.6),
		Vector3(0.0, HALL_H + Kit.SLAB * 0.5, HALL_L * 0.5), "black", 0.0, false)


## The window wall, built round the openings rather than over them. The kit's
## `window` is a recess with a solid pane, which is right for a corridor and
## useless here: the thing at the glass has to be behind actual holes or it is
## simply behind a wall.
static func _window_wall(root: Node3D, x: float) -> void:
	var y0 := WIN_Y - WIN_H * 0.5
	var y1 := WIN_Y + WIN_H * 0.5
	var half_w := WIN_W * 0.5
	var edges: Array[float] = [-0.3]
	for z: float in WIN_Z:
		edges.append(z - half_w)
		edges.append(z + half_w)
	edges.append(HALL_L + 0.3)
	# the solid stretches are the gaps between one opening and the next
	for i in range(0, edges.size(), 2):
		var a := edges[i]
		var b := edges[i + 1]
		if b - a > 0.01:
			Kit.split_box(root, Vector3(Kit.WALL, HALL_H, b - a),
				Vector3(x, HALL_H * 0.5, (a + b) * 0.5), "wall", 0.0, true, 0.0, 8.0)
	# sill and lintel across each one
	for z: float in WIN_Z:
		Kit.split_box(root, Vector3(Kit.WALL, y0, WIN_W), Vector3(x, y0 * 0.5, z),
			"wall", 0.0, true, 0.0, 8.0)
		Kit.split_box(root, Vector3(Kit.WALL, HALL_H - y1, WIN_W),
			Vector3(x, (HALL_H + y1) * 0.5, z), "wall", 0.0, true, 0.0, 8.0)


## The three layers, bottom up: a black slab to fall into, a baked pile of
## pillows with the crevices punched through to it, and a scatter of real ones
## with no collision on them at all.
static func _build_floor(root: Node3D, half: float, rng: RandomNumberGenerator) -> void:
	var mid := Vector3(0.0, 0.0, HALL_L * 0.5)
	Kit.box(root, Vector3(HALL_W + 0.6, 0.4, HALL_L + 0.6), mid + Vector3(0.0, -0.72, 0.0),
		"black", 0.0, false)

	var tex_mat := PillowTexScript.floor_material(2.4)
	var tile := 7.7
	var nx := int(ceil(HALL_W / tile))
	var nz := int(ceil(HALL_L / tile))
	var sx := HALL_W / float(nx)
	var sz := HALL_L / float(nz)
	for tz in nz:
		for tx in nx:
			var pm := PlaneMesh.new()
			pm.size = Vector2(sx, sz)
			pm.subdivide_width = 1
			pm.subdivide_depth = 1
			var mi := MeshInstance3D.new()
			mi.mesh = pm
			mi.material_override = tex_mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.position = Vector3(
				(float(tx) + 0.5) * sx - half,
				0.006,
				(float(tz) + 0.5) * sz)
			root.add_child(mi)

	PillowTexScript.scatter(root, Vector2(HALL_W, HALL_L), mid, 26, 7.7, rng,
		Kit.mat("pillow"))

	# the surface you actually stand on, flush with the stub floor so there is
	# no lip to trip over in the doorway. The pillows sit above it and you push
	# through them
	Kit.blocker(root, Vector3(HALL_W + 0.6, 0.5, HALL_L + 0.6), mid + Vector3(0.0, -0.25, 0.0))


## How far back of its own centre a ring slice reaches, measured at the inner
## radius where a rectangle laid on an arc overhangs the most.
static func _slice_reach() -> float:
	return atan(TAU * PLATFORM_R / float(RING_SIDES) * 1.08 * 0.5 / PILLAR_R)


## The piece of landing the last step arrives on. Slabs rather than ring slices,
## each turned so its back face is a radial plane: nothing hangs back over the
## flight, so the helix runs into the landing flush and the climb finishes.
static func _landing_tongue(root: Node3D, a_end: float) -> void:
	# a little inside the pillar, so the seam is buried in something solid
	var r_in := PILLAR_R - 0.2
	var mid_r := (r_in + PLATFORM_R) * 0.5
	for i in TONGUE_PIECES:
		var a := a_end + float(i) * TONGUE_STEP
		var radial := Vector3(cos(a), 0.0, sin(a))
		var tangent := Vector3(-sin(a), 0.0, cos(a))
		Kit.box(root, Vector3(TONGUE_W, PLATFORM_T, PLATFORM_R - r_in),
			PILLAR_C + radial * mid_r + tangent * (TONGUE_W * 0.5)
				+ Vector3(0.0, TOP_Y - PLATFORM_T * 0.5, 0.0),
			"stone", PI * 0.5 - a)


static func _build_pillar(root: Node3D, lights: Array[OmniLight3D], shafts: Array[MeshInstance3D],
		room: Dictionary) -> void:
	# the pillar runs the whole way up, so its top face IS the middle of the
	# landing and the last step arrives flush with it
	Kit.column(root, PILLAR_R, TOP_Y, PILLAR_C, "stone", true, 16)
	# the landing round it, with the stairwell left open. Without the hole the
	# last turn of the flight would come up into the floor and seal the climb
	var a_end := START_ANGLE + STEP_TURN * float(STEP_COUNT)
	var well_from := a_end - STEP_TURN * float(WELL_STEPS)
	# A ring slice is a rectangle laid on a coarse arc, so its trailing corners
	# reach back well past its own centre - a quarter of a radian of it down at
	# the inner radius. Left to fall where it likes, the first slice past the top
	# of the flight hangs over the last half step, where the helix is still seven
	# centimetres short of TOP_Y, and a capsule cannot step up a lip: the landing
	# becomes an invisible wall in the last stride of the climb. So the bite is
	# taken wider than the well and the notch is filled with slabs whose back
	# face IS the radial plane the flight ends on.
	Kit.ring(root, PILLAR_R, PLATFORM_R, PLATFORM_T,
		PILLAR_C + Vector3(0.0, TOP_Y - PLATFORM_T, 0.0), "stone", RING_SIDES,
		well_from, a_end + _slice_reach() + 0.05)
	_landing_tongue(root, a_end)
	Kit.column(root, 0.42, PLINTH_T, PILLAR_C + Vector3(0.0, TOP_Y, 0.0), "stone", true, 12)

	# facing -z at the bottom, so the flight opens toward whoever walks in. The
	# first four steps carry no rail: one round the entrance is a fence across it.
	# The last two carry none either - a rail there is a post standing in the
	# middle of the landing you are stepping onto, and the fall wants the edge
	# open anyway
	var flight := Kit.spiral_stairs(root, PILLAR_C, PILLAR_R, STAIR_W, STEP_COUNT,
		STEP_RISE, START_ANGLE, STEP_TURN, 4, 2, "boards")
	room["stair_points"] = flight["points"]
	room["stair_parts"] = flight["parts"]
	room["well_arc"] = Vector2(well_from, a_end)
	# where you get on: a little back round the pillar from the first step, at
	# floor level, so the way up is walked into rather than climbed onto
	var r_mid := PILLAR_R + STAIR_W * 0.5
	var foot_a := START_ANGLE - 0.55
	room["stair_foot"] = PILLAR_C + Vector3(cos(foot_a), 0.0, sin(foot_a)) * r_mid

	# the light from above. One lamp doing the work, a cone doing the look, and
	# dust so the eye has something moving to go to
	var beam := Kit.lamp(root, PILLAR_C + Vector3(0.0, TOY_Y + 2.4, 0.0), 3.2, 16.0,
		true, false, 0.0, 0.0, false)
	beam.set_meta("beam", true)
	lights.append(beam)
	room["beam_light"] = beam
	# and a small one on the toy itself, so from the floor there is a point of
	# warmth at the top of the pillar and a reason to go up
	lights.append(Kit.lamp(root, PILLAR_C + Vector3(0.0, TOY_Y + 0.45, 0.0), 0.8, 4.0,
		true, false, 0.0, 0.0, false))

	# three cones nested rather than one wide one: see the note on Kit.shaft.
	# Together they give a bright core with something soft round it
	var top := PILLAR_C + Vector3(0.0, HALL_H - 1.2, 0.0)
	var drop := HALL_H - 1.2 - TOY_Y + 0.4
	var cone: MeshInstance3D = null
	# the wider ones are nearly all rim, so they take more energy to show at all
	var spreads: Array[float] = [1.5, 2.9, 4.3, 5.6]
	var powers: Array[float] = [2.6, 2.2, 3.0, 4.0]
	for i in spreads.size():
		var s := Kit.shaft(root, top + Vector3(0.0, float(i) * 0.2, 0.0), drop + float(i) * 0.6,
			spreads[i], Color(1.0, 0.89, 0.70), powers[i])
		shafts.append(s)
		if i == 0:
			cone = s
	room["beam_shaft"] = cone
	Kit.column(root, 2.3, 0.12, top + Vector3(0.0, 0.5, 0.0), "bulb", false, 20)

	# the pillar has to be a thing you can see from the floor, not a hole in the
	# dark with a disc floating over it. Lamps stood off it at the height of the
	# flight pick out the helix all the way up
	var lit_at: Array[float] = [1.8, 6.0, 10.4, 14.4]
	for i in lit_at.size():
		var a := START_ANGLE + 1.7 + float(i) * 1.9
		var l := Kit.lamp(root, PILLAR_C + Vector3(cos(a), 0.0, sin(a)) * 4.6
			+ Vector3(0.0, lit_at[i], 0.0), 1.35, 13.0, true, false, 0.0, 0.0, false)
		l.set_meta("pillar", true)
		lights.append(l)

	var wide := Kit.motes(root, PILLAR_C + Vector3(0.0, TOY_Y + 4.0, 0.0), 3.4, 80,
		Color(1.0, 0.90, 0.72), 0.03)
	var tight := Kit.motes(root, PILLAR_C + Vector3(0.0, TOY_Y + 0.7, 0.0), 1.0, 36,
		Color(1.0, 0.92, 0.78), -0.012)
	(room["motes"] as Array).append(wide)
	(room["motes"] as Array).append(tight)


static func _build_windows(root: Node3D, lights: Array[OmniLight3D], shafts: Array[MeshInstance3D],
		panes: Array[MeshInstance3D], room: Dictionary) -> void:
	var half := HALL_W * 0.5
	var sill := WIN_Y - WIN_H * 0.5
	var spots: Array[Vector3] = []
	for z: float in WIN_Z:
		# the night, hung well back so there is real depth through the hole and
		# room for something to stand between the two
		var sky := MeshInstance3D.new()
		var sq := QuadMesh.new()
		sq.size = Vector2(WIN_W + 16.0, WIN_H + 16.0)
		sky.mesh = sq
		var sm := ShaderMaterial.new()
		sm.shader = Kit.RAIN_SHADER
		sm.set_shader_parameter("rain_amount", 0.85)
		sky.material_override = sm
		sky.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sky.position = Vector3(-half - 5.5, WIN_Y, z)
		sky.rotation.y = PI * 0.5
		root.add_child(sky)
		panes.append(sky)

		# bars across the opening, in it rather than on the wall face
		var jamb := -half + Kit.WALL * 0.5
		for i in 3:
			var y := sill + WIN_H * (float(i) + 1.0) * 0.25
			Kit.box(root, Vector3(0.13, 0.13, WIN_W), Vector3(jamb, y, z), "shelf", 0.0, false)
		Kit.box(root, Vector3(0.13, WIN_H, 0.13), Vector3(jamb, WIN_Y, z), "shelf", 0.0, false)
		Kit.box(root, Vector3(0.34, 0.10, WIN_W + 0.5), Vector3(-half + 0.12, sill - 0.05, z),
			"shelf", 0.0, false)

		var l := Kit.lamp(root, Vector3(-half + 3.0, WIN_Y - 1.0, z), 1.5, 19.0,
			false, false, 0.0, 0.0, false)
		l.set_meta("window", true)
		lights.append(l)
		var s := _aimed_shaft(root, Vector3(-half + 0.4, WIN_Y + WIN_H * 0.3, z),
			Vector3(0.66, -0.75, 0.0), 17.0, 6.0, Color(0.66, 0.74, 0.98), 0.9)
		shafts.append(s)
		# where the thing stands: right at the glass and far too big for the
		# opening, feet well below the sill, so the wall crops it and what fills
		# the frame is the top of it looking down at you
		spots.append(Vector3(-half - 1.7, sill - 2.4, z))
	room["window_spots"] = spots


static func _build_exit(root: Node3D, frame_xf: Transform3D, house: Node,
		lights: Array[OmniLight3D], shafts: Array[MeshInstance3D], room: Dictionary) -> MeshInstance3D:
	var half := HALL_W * 0.5
	var at := Vector3(half + Kit.WALL, 0.0, EXIT_Z)
	var door := Kit.doorway(root, frame_xf, at, Vector3(1, 0, 0), house, {
		"name": "dream exit", "swing_time": 0.5, "open_angle": 100.0, "volume_db": -15.0,
	})
	if door != null:
		(room["doors"] as Array).append(door)

	# dark and ordinary all the way up the pillar. The director lights it the
	# moment there is a reason to run for it
	var l := Kit.lamp(root, Vector3(half - 1.1, 2.5, EXIT_Z), 0.0, 6.0, true, false, 0.0, 0.0, false)
	l.set_meta("base_energy", 1.25)
	l.set_meta("exit_marker", true)
	lights.append(l)
	var s := _aimed_shaft(root, Vector3(half - 0.5, 2.7, EXIT_Z), Vector3(-0.5, -0.86, 0.0),
		3.6, 1.5, Color(1.0, 0.86, 0.62), 0.0)
	shafts.append(s)
	var m := Kit.motes(root, Vector3(half - 1.2, 1.5, EXIT_Z), 0.9, 26, Color(1.0, 0.88, 0.66), 0.02)
	m.emitting = false
	(room["motes"] as Array).append(m)
	room["exit_glow"] = [l, s, m]

	# breadcrumbs. Coming round at the foot of the pillar in a black room forty
	# metres across, the way out has to be something you can see rather than
	# something you have to remember. These come up one after another when the
	# dark starts, pointing.
	var trail: Array[OmniLight3D] = []
	var from := PILLAR_C + Vector3(0.0, 0.0, -PILLAR_R - 2.0)
	var to := Vector3(half - 2.4, 0.0, EXIT_Z)
	for i in 7:
		var t := (float(i) + 1.0) / 8.0
		var p := from.lerp(to, t)
		var tl := Kit.lamp(root, p + Vector3(0.0, 0.55, 0.0), 0.0, 5.5, true, false, 0.0, 0.0, true)
		tl.set_meta("base_energy", 0.75)
		tl.set_meta("trail", i)
		var bulb := tl.get_meta("bulb") as Node3D
		if bulb != null:
			bulb.visible = false
		trail.append(tl)
	room["trail"] = trail
	return door


## The dark coming for the room. Not a wall: a bank of smoke.
##
## One quad reads as a black rectangle sliding at you no matter what the shader
## does to its edge, because a flat thing lit the same everywhere IS a wall. So
## this is six of them at staggered depths, each with its own noise phase and a
## slow sideways crawl, with soft dark puffs rolling out in front and the solid
## mass hidden well behind. The layers slide past each other as you move, and
## that parallax is most of what makes it read as depth rather than as a plane.
static func build_void(parent: Node3D, at_z: float) -> Dictionary:
	var node := Node3D.new()
	node.name = "Void"
	node.position = Vector3(0.0, 0.0, at_z)
	parent.add_child(node)

	var w := HALL_W + 8.0
	# everything behind the bank, so there is never a way to see through to the
	# far wall. Set back, or its hard edge is what you see instead of the smoke
	Kit.box(node, Vector3(w, HALL_H + 2.0, HALL_L), Vector3(0.0, HALL_H * 0.5, HALL_L * 0.5 + 7.0),
		"black", 0.0, false)

	var veils: Array[ShaderMaterial] = []
	var nodes: Array[Node3D] = []
	for i in 6:
		var m := ShaderMaterial.new()
		m.shader = VOID_SHADER
		# solid at the floor, torn along the top, or it is a curtain hanging in
		# front of you rather than something rolling along the ground
		m.set_shader_parameter("flip", true)
		# the near layers are the torn ones; the far ones are nearly solid, so
		# together they go from wisps to a bank of it without a visible edge
		m.set_shader_parameter("ragged", lerpf(0.62, 0.14, float(i) / 5.0))
		m.set_shader_parameter("tile", lerpf(3.5, 9.0, float(i) / 5.0))
		m.set_shader_parameter("wobble", lerpf(1.9, 0.8, float(i) / 5.0))
		m.set_shader_parameter("fringe", Color(0.05, 0.045, 0.08) * (1.0 - float(i) / 7.0))
		var q := QuadMesh.new()
		q.size = Vector2(w, HALL_H * 1.1)
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# quad faces +z; the room is in -z, so turn each one round. Sunk a little
		# so the solid end is under the floor and the tearing happens up in the
		# air where it can be seen against the room
		mi.position = Vector3(0.0, HALL_H * 0.5 - 2.0, float(i) * 1.5)
		mi.rotation.y = PI
		node.add_child(mi)
		veils.append(m)
		nodes.append(mi)

	# and the smoke itself, rolling out ahead of the bank along the pillows
	var p := CPUParticles3D.new()
	p.name = "Roll"
	p.amount = 90
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(HALL_W * 0.5, 3.4, 1.2)
	p.direction = Vector3(0.0, 0.15, -1.0)
	p.spread = 22.0
	p.gravity = Vector3(0.0, 0.06, -0.35)
	p.initial_velocity_min = 0.15
	p.initial_velocity_max = 0.7
	p.damping_min = 0.05
	p.damping_max = 0.25
	p.scale_amount_min = 3.0
	p.scale_amount_max = 8.0
	var pq := QuadMesh.new()
	pq.size = Vector2(1.0, 1.0)
	p.mesh = pq
	# the colour goes on the material, not on the emitter. The kit's point
	# material takes its albedo from the vertex colour, which is right for grit
	# and rain and leaves these as white billboards the size of a bus
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.albedo_color = Color(0.022, 0.020, 0.032, 0.17)
	pm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	pm.billboard_keep_scale = true
	pm.render_priority = 2
	p.material_override = pm
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.position = Vector3(0.0, 2.6, -0.5)
	node.add_child(p)

	return {"node": node, "veils": veils, "layers": nodes, "roll": p}


# --- the endless hall --------------------------------------------------------

## The corridor that goes nowhere.
##
## No teleporting. The segments are identical and laid on a grid the director
## re-anchors under the player, so the walls really do stream past and the
## corridor behind is genuinely cut and reused; and the door, with the bathroom
## behind it, is slid forward at exactly your speed, so the gap never closes.
## Nothing about it can be caught out by looking down or turning round.
static func build_endless_hall(frame_xf: Transform3D, opts: Dictionary) -> Dictionary:
	var room := _blank("endless", "EndlessHall", frame_xf)
	var root := room["root"] as Node3D
	var house: Node = opts.get("house")
	var half := RUN_W * 0.5
	var lights: Array[OmniLight3D] = []
	var segs: Array[Node3D] = []

	# the way in. No door of its own: the hall's exit door is moved over here
	# when the hall goes, so there is only ever one door in the world
	Kit.wall_with_door(root, RUN_W + 0.3, Vector3(0.0, 0.0, -Kit.WALL * 0.5), 0.0, "wall")

	for i in RUN_SEGS:
		var seg := Node3D.new()
		seg.name = "Seg%d" % i
		root.add_child(seg)
		_corridor_run(seg, RUN_SEG, lights, true)
		segs.append(seg)

	var bath := _build_bath(root, frame_xf, house, lights, room)
	room["segs"] = segs
	room["bath"] = bath
	room["lights"] = lights
	room["spawn"] = Vector3(0.0, 0.0, 1.2)
	room["seg"] = RUN_SEG
	room["gap"] = RUN_GAP
	room["plug"] = RUN_PLUG
	room["footprint"] = AABB(Vector3(-half - 0.5, -0.5, -0.4),
		Vector3(RUN_W + 1.0, Kit.CEIL + 1.0, RUN_GAP + BATH_L + 12.0))
	return room


## One stretch of corridor, built from its own origin forward. Fixed lamp
## positions and fixed energy: the segments have to be interchangeable.
static func _corridor_run(node: Node3D, length: float, lights: Array[OmniLight3D],
		lamp: bool, out := 0.0) -> void:
	var half := RUN_W * 0.5 + out
	var mid := length * 0.5
	Kit.split_box(node, Vector3(RUN_W + 0.3 + out * 2.0, Kit.SLAB, length),
		Vector3(0.0, -Kit.SLAB * 0.5, mid), "boards")
	Kit.split_box(node, Vector3(RUN_W + 0.3 + out * 2.0, Kit.SLAB, length),
		Vector3(0.0, Kit.CEIL + Kit.SLAB * 0.5 + out * 2.0, mid), "ceil")
	for s in [-1.0, 1.0]:
		Kit.split_box(node, Vector3(Kit.WALL, Kit.CEIL + out * 2.0, length),
			Vector3(s * (half + Kit.WALL * 0.5), Kit.CEIL * 0.5, mid), "wall")
	if lamp:
		lights.append(Kit.lamp(node, Vector3(0.0, 2.42, mid), 0.62, 4.6))


## What waits at the end and never gets closer. Everything is under one node the
## director drags up the corridor, including a length of corridor of its own so
## the segments behind it can stop cleanly without leaving a hole.
##
## It is the house's bathroom, not a tiled box: the basin, the tub and the
## toilet are the real meshes, laid out to be read from the doorway, because
## that is the only place it is ever seen from.
static func _build_bath(root: Node3D, frame_xf: Transform3D, house: Node,
		lights: Array[OmniLight3D], room: Dictionary) -> Dictionary:
	var node := Node3D.new()
	node.name = "BathStub"
	node.position = Vector3(0.0, 0.0, RUN_GAP)
	root.add_child(node)

	# Its own corridor, running back toward the player, so the segments never
	# have to land exactly anywhere. They are on a grid and this is pinned to the
	# door, so the two always overlap by a metre or so; the plug is built one
	# centimetre outside the segments in every direction, which means the
	# segments simply win the depth test over it and the join is invisible
	# instead of being a z-fighting stripe.
	var plug := Node3D.new()
	plug.position = Vector3(0.0, -0.01, -RUN_PLUG)
	node.add_child(plug)
	# It carries a lamp of its own. The director fades the corridor's lamps in
	# with distance, so out at the far end this one is dark like everything else
	# around it; once the bathroom has been walked up to the player's face it is
	# the light in the last stretch of hall before the door.
	_corridor_run(plug, RUN_PLUG, lights, true, 0.02)

	# The bathroom itself hangs off the frame rather than being part of it, so it
	# can be taken away behind a shut door and the chase built in its place -
	# same doorway, same panel, nothing faded and nobody moved.
	var interior := Node3D.new()
	interior.name = "Bath"
	node.add_child(interior)

	var hw := BATH_W * 0.5
	var mid := Kit.WALL + BATH_L * 0.5
	# the wall it is set in spans the whole corridor, so dragging the assembly
	# never leaves a frame standing in mid air. This one stays: it is the wall
	# the door is hung in, and whatever is behind it later still needs it
	Kit.wall_with_door(node, RUN_W + 0.3, Vector3(0.0, 0.0, Kit.WALL * 0.5), 0.0, "tile")
	var side := (BATH_W - RUN_W - 0.3) * 0.5
	for s in [-1.0, 1.0]:
		if side > 0.05:
			Kit.box(interior, Vector3(side, Kit.CEIL, Kit.WALL),
				Vector3(s * (BATH_W - side) * 0.5, Kit.CEIL * 0.5, Kit.WALL * 0.5), "tile")
		Kit.box(interior, Vector3(Kit.WALL, Kit.CEIL, BATH_L + 0.3),
			Vector3(s * (hw - Kit.WALL * 0.5), Kit.CEIL * 0.5, mid), "tile")
	Kit.box(interior, Vector3(BATH_W, Kit.SLAB, BATH_L + 0.3), Vector3(0.0, -Kit.SLAB * 0.5, mid), "tile")
	Kit.box(interior, Vector3(BATH_W, Kit.SLAB, BATH_L + 0.3),
		Vector3(0.0, Kit.CEIL + Kit.SLAB * 0.5, mid), "tile")
	Kit.box(interior, Vector3(BATH_W, Kit.CEIL, Kit.WALL),
		Vector3(0.0, Kit.CEIL * 0.5, Kit.WALL + BATH_L), "tile")

	# the real fittings, arranged to read from the doorway: basin straight
	# ahead under the mirror, tub down the right wall, toilet in the left corner
	var back_z := Kit.WALL + BATH_L - 0.5
	Kit.dressing_dup(house, "Washbasin_07", interior, frame_xf, Vector3(0.0, 0.0, back_z), PI)
	Kit.dressing_dup(house, "bathtub", interior, frame_xf,
		Vector3(hw - 0.55, 0.0, Kit.WALL + BATH_L * 0.5), PI * 0.5)
	Kit.dressing_dup(house, "Toilet_01", interior, frame_xf,
		Vector3(-hw + 0.42, 0.0, Kit.WALL + 0.9), PI * 0.5)
	# a mirror over the basin. Nothing reflects in compatibility, so it is a
	# dark pane in a frame, which from four metres back is what a mirror is
	Kit.box(interior, Vector3(0.78, 0.62, 0.04), Vector3(0.0, 1.62, back_z + 0.42), "black", 0.0, false)
	Kit.box(interior, Vector3(0.86, 0.70, 0.03), Vector3(0.0, 1.62, back_z + 0.45), "shelf", 0.0, false)

	var l := Kit.lamp(interior, Vector3(0.0, 2.55, mid), 1.5, 6.5, true, false, 0.0, 0.0, true)
	# the beacon, and the one lamp the corridor's distance fade must leave alone
	l.set_meta("bath", true)
	lights.append(l)

	var door := Kit.doorway(node, frame_xf, Vector3(0.0, 0.0, Kit.WALL), Vector3(0, 0, 1), house, {
		"name": "bath door", "swing_time": 0.55, "open_angle": 100.0, "volume_db": -14.0,
	})
	if door != null:
		(room["doors"] as Array).append(door)
		# stands open the whole run: you can see what it is from the far end and
		# still never get to it
		door.call_deferred("snap_open", true)
	return {
		"node": node, "room": interior, "door": door, "light": l,
		"drip_at": Vector3(0.0, 1.0, back_z),
	}
