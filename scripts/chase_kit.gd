class_name ChaseKit
extends RefCounted
## Static builders the chase rooms are made of: materials, boxes, a wall with a
## doorway hole in it, a real house door hung in that hole, lamps, stairs,
## triggers, planks. Nothing here keeps per-room state.
##
## Room convention (see chase_rooms.gd): origin is the centre of the entry
## doorway at floor level on the room's side of the entry wall, +z runs into
## the room, +x is right when facing +z. The entry wall fills z -WALL..0, the
## exit wall z L..L+WALL, and the next room's origin sits at z L + 2*WALL.
##
## Scripts are preloaded by path: this file is reachable from an autoload's
## preload chain, where the global class cache does not exist yet.

const MeshUtilScript := preload("res://scripts/mesh_util.gd")
const DoorScript := preload("res://scripts/door.gd")
const RAIN_SHADER := preload("res://scripts/rain_window.gdshader")
const SHAFT_SHADER := preload("res://scripts/light_shaft.gdshader")

const TEX := {
	"wall": preload("res://assets/House/House/Textures/PlasterWhite.jpg"),
	"wall_cold": preload("res://assets/House/House/Textures/PlasterWhite.jpg"),
	"floor": preload("res://assets/House/House/Textures/Wood.jpg"),
	"ceil": preload("res://assets/House/House/Textures/Ceiling.jpg"),
	"plank": preload("res://assets/House/House/Textures/WoodPlanks_01.jpg"),
	"hedge": preload("res://assets/House/House/Textures/Hedges.jpg"),
	"grass": preload("res://assets/House/House/Textures/Grass.jpg"),
	"path": preload("res://assets/House/House/Textures/ConcreteBare_01.png"),
	"soil": preload("res://assets/House/House/Textures/SoilBeach.jpg"),
	"shelf": preload("res://assets/House/House/Textures/Wood_06.jpg"),
	"rubble": preload("res://assets/House/House/Textures/ConcreteBare_01.png"),
	# Wood.jpg is a dark walnut and the palette crush takes it straight to black
	# under anything but a lamp overhead. The dream corridors want boards you can
	# still see at the far end of one.
	"boards": preload("res://assets/House/House/Textures/WoodFine_01.jpg"),
	"pillow": preload("res://assets/House/House/Textures/Fabric.jpg"),
	"linen": preload("res://assets/House/House/Textures/bed_01.png"),
	"tile": preload("res://assets/House/House/Textures/TilesSmall_01.jpg"),
	# Marble.jpg is black marble: a pillar made of it is a hole in the room no
	# matter what you point at it. Plaster at a coarser scale reads as pale stone
	"stone": preload("res://assets/House/House/Textures/PlasterWhite.jpg"),
}
## key -> [tint, triplanar scale, tint at full nightmare depth]. The deeper
## rooms drift toward the second colour: dirtier, colder, less like a house.
const MAT_SPEC := {
	"wall": [Color(0.80, 0.79, 0.77), 0.5, Color(0.52, 0.55, 0.62)],
	"wall_cold": [Color(0.66, 0.70, 0.78), 0.5, Color(0.42, 0.48, 0.60)],
	"floor": [Color(0.95, 0.90, 0.82), 0.55, Color(0.58, 0.52, 0.48)],
	"ceil": [Color(0.80, 0.79, 0.77), 0.5, Color(0.46, 0.46, 0.50)],
	"plank": [Color(0.72, 0.62, 0.48), 1.0, Color(0.50, 0.42, 0.34)],
	# the garden has no walls to bounce anything, and the palette crush takes
	# whatever the lamps miss straight to black, so it starts brighter
	"hedge": [Color(0.90, 1.05, 0.80), 0.6, Color(0.52, 0.62, 0.48)],
	"grass": [Color(1.00, 1.05, 0.80), 0.35, Color(0.58, 0.60, 0.48)],
	"path": [Color(0.70, 0.68, 0.64), 0.8, Color(0.42, 0.42, 0.42)],
	"soil": [Color(0.62, 0.56, 0.48), 0.6, Color(0.36, 0.33, 0.30)],
	"shelf": [Color(0.42, 0.34, 0.27), 0.6, Color(0.30, 0.25, 0.21)],
	"rubble": [Color(0.44, 0.42, 0.40), 0.7, Color(0.30, 0.30, 0.31)],
	"boards": [Color(1.00, 0.98, 0.94), 0.5, Color(0.62, 0.60, 0.58)],
	"pillow": [Color(0.88, 0.85, 0.80), 0.9, Color(0.60, 0.58, 0.58)],
	"linen": [Color(0.82, 0.80, 0.82), 0.8, Color(0.52, 0.52, 0.56)],
	"tile": [Color(0.86, 0.88, 0.88), 0.7, Color(0.56, 0.58, 0.60)],
	"stone": [Color(0.94, 0.93, 0.98), 0.28, Color(0.56, 0.56, 0.62)],
}
## Depth is bucketed so the material cache stays small.
const DEPTH_STEPS := 4

## Interior height, floor top to ceiling underside. The real house runs 3.13;
## the nightmare corridors are deliberately tighter, but not so tight that the
## 2.55 doorway leaves a hairline lintel.
const CEIL := 2.85
const WALL := 0.15
const SLAB := 0.2
const DOOR_W := 1.04
const DOOR_H := 2.55
## Upstairs floor top in the real house, measured.
const HOUSE_FLOOR_Y := 3.7316

static var _mats := {}
static var _boxes := {}


static func mat(key: String, depth := 0.0) -> StandardMaterial3D:
	var step := clampi(int(round(clampf(depth, 0.0, 1.0) * float(DEPTH_STEPS - 1))), 0, DEPTH_STEPS - 1)
	var cache_key := key if step == 0 else "%s@%d" % [key, step]
	if _mats.has(cache_key):
		return _mats[cache_key] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.roughness = 1.0
	m.metallic = 0.0
	if key == "black":
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(0.005, 0.005, 0.006)
	elif key == "bulb" or key == "moon":
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(1.0, 0.85, 0.6) if key == "bulb" else Color(0.85, 0.9, 1.0)
		m.emission_enabled = true
		m.emission = m.albedo_color
		m.emission_energy_multiplier = 2.5 if key == "bulb" else 3.0
	elif MAT_SPEC.has(key):
		var spec: Array = MAT_SPEC[key]
		m.albedo_texture = TEX[key] as Texture2D
		var t := float(step) / float(DEPTH_STEPS - 1)
		m.albedo_color = (spec[0] as Color).lerp(spec[2] as Color, t)
		var s := float(spec[1])
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3(s, s, s)
	else:
		m.albedo_color = Color(0.5, 0.5, 0.5)
	_mats[cache_key] = m
	return m


## Box meshes are shared between instances of the same size; the material rides
## on the instance, so one mesh can serve a wall and a plank.
static func _box_mesh(size: Vector3) -> BoxMesh:
	var key := "%.3f_%.3f_%.3f" % [size.x, size.y, size.z]
	if _boxes.has(key):
		return _boxes[key] as BoxMesh
	var bm := BoxMesh.new()
	bm.size = size
	_boxes[key] = bm
	return bm


## A box of `size` centred on `pos` in `parent`'s frame. Solid ones are static
## bodies on the world layer; the rest are meshes only. Nothing in the chase
## casts shadows - GL compatibility with sixty lights cannot afford it.
static func box(parent: Node3D, size: Vector3, pos: Vector3, key: String, yaw := 0.0, solid := true,
		depth := 0.0) -> Node3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _box_mesh(size)
	mi.material_override = mat(key, depth)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if not solid:
		mi.position = pos
		mi.rotation.y = yaw
		parent.add_child(mi)
		return mi
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = pos
	body.rotation.y = yaw
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	body.add_child(mi)
	parent.add_child(body)
	return body


## Same as `box`, cut into chunks along its longest horizontal axis.
##
## GL compatibility only lights a mesh with the handful of lamps nearest it, so
## a twenty metre floor drawn as one box loses every light past the cap and goes
## black. Split it and each chunk keeps the lamps that actually reach it.
static func split_box(parent: Node3D, size: Vector3, pos: Vector3, key: String, yaw := 0.0,
		solid := true, depth := 0.0, seg := 5.0) -> void:
	var long_x := size.x >= size.z
	var length := size.x if long_x else size.z
	var count := maxi(1, int(ceil(length / seg)))
	if count == 1:
		box(parent, size, pos, key, yaw, solid, depth)
		return
	var step := length / float(count)
	var b := Basis(Vector3.UP, yaw)
	var piece := Vector3(step, size.y, size.z) if long_x else Vector3(size.x, size.y, step)
	for i in count:
		var off := (float(i) + 0.5) * step - length * 0.5
		var local := Vector3(off, 0.0, 0.0) if long_x else Vector3(0.0, 0.0, off)
		box(parent, piece, pos + b * local, key, yaw, solid, depth)


## Collision with nothing to see: what makes a piece of house scenery solid.
static func blocker(parent: Node3D, size: Vector3, pos: Vector3, basis := Basis.IDENTITY) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.transform = Transform3D(basis, pos)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	parent.add_child(body)
	return body


## A wall `width` long, WALL thick, CEIL tall, standing on the floor with its
## centre at `centre` and running along its own x after `yaw`, with a doorway
## hole punched in the middle: two jambs and a lintel.
static func wall_with_door(parent: Node3D, width: float, centre: Vector3, yaw: float,
		key: String, height := CEIL, depth := 0.0) -> void:
	var b := Basis(Vector3.UP, yaw)
	var side := maxf((width - DOOR_W) * 0.5, 0.0)
	if side > 0.005:
		var ox := (DOOR_W + side) * 0.5
		box(parent, Vector3(side, height, WALL), centre + b * Vector3(-ox, height * 0.5, 0.0), key, yaw, true, depth)
		box(parent, Vector3(side, height, WALL), centre + b * Vector3(ox, height * 0.5, 0.0), key, yaw, true, depth)
	var lintel := height - DOOR_H
	if lintel > 0.005:
		box(parent, Vector3(DOOR_W, lintel, WALL), centre + b * Vector3(0.0, DOOR_H + lintel * 0.5, 0.0),
			key, yaw, true, depth)


## Plain wall, no hole.
static func wall(parent: Node3D, width: float, centre: Vector3, yaw: float, key: String, height := CEIL,
		depth := 0.0) -> Node3D:
	return box(parent, Vector3(width, height, WALL), centre + Basis(Vector3.UP, yaw) * Vector3(0.0, height * 0.5, 0.0),
		key, yaw, true, depth)


# --- doors ------------------------------------------------------------------

## The house's bathroom door and its frame, duplicated and hung in a hole.
## `floor_point` and `heading` are local to `frame_xf` (the room's world
## transform); the panel swings on the axis `heading` runs through.
##
## The template pair is measured live: the frame's world AABB centre against
## the door's shut origin, so the hinge offset never has to be typed in.
static func doorway(parent: Node3D, frame_xf: Transform3D, floor_point: Vector3,
		heading: Vector3, house: Node, opts: Dictionary) -> MeshInstance3D:
	var door_tmpl := house.find_child("Door_005", true, false) as MeshInstance3D
	var frame_tmpl := house.find_child("Door_frame_006", true, false) as MeshInstance3D
	if door_tmpl == null or frame_tmpl == null:
		return null
	var shut: Transform3D = door_tmpl.get("_shut")
	var fc := MeshUtilScript.world_aabb(frame_tmpl).get_center()
	var hinge_off := shut.origin - fc
	var frame_y := fc.y - HOUSE_FLOOR_Y

	# the template hangs along world +x, and the pose below is built in world
	# space, so the turn has to come from the heading in WORLD terms - the room
	# frame's own rotation included - not from the local one
	var h := frame_xf.basis * Vector3(heading.x, 0.0, heading.z).normalized()
	h.y = 0.0
	h = h.normalized()
	var ang := Vector3(1, 0, 0).signed_angle_to(h, Vector3.UP)
	var r := Basis(Vector3.UP, ang)
	var inv := frame_xf.affine_inverse()
	var centre_world := frame_xf * (floor_point + Vector3(0.0, frame_y, 0.0))

	var frame := frame_tmpl.duplicate() as MeshInstance3D
	_strip(frame)
	frame.name = String(opts.get("name", "chase door")) + " frame"
	# the template's origin is not its centre, so aim the centre at the hole
	var frame_off := fc - frame_tmpl.global_transform.origin
	frame.transform = inv * Transform3D(r * frame_tmpl.global_transform.basis, centre_world - r * frame_off)
	frame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(frame)

	var door := door_tmpl.duplicate(Node.DUPLICATE_SCRIPTS) as MeshInstance3D
	_strip_audio(door)
	door.name = String(opts.get("name", "chase door"))
	door.transform = inv * Transform3D(r * shut.basis, centre_world + r * hinge_off)
	door.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# exports before add_child: the Door reads its shut pose in _ready
	door.set("swing_time", float(opts.get("swing_time", 0.5)))
	door.set("open_angle", float(opts.get("open_angle", 105.0)))
	door.set("locked", bool(opts.get("locked", false)))
	door.set("locked_prompt", String(opts.get("locked_prompt", "Locked")))
	door.set("volume_db", float(opts.get("volume_db", -16.0)))
	door.set("ajar_angle", 0.0)
	door.set("closed_offset", 0.0)
	door.set("swing_away", true)
	door.set("locked_sound", AudioBus.stream("door_locked"))
	parent.add_child(door)
	return door


## Children a duplicated house mesh should not carry into the chase.
static func _strip(n: Node) -> void:
	for c in n.get_children():
		n.remove_child(c)
		c.queue_free()


static func _strip_audio(n: Node) -> void:
	for c in n.get_children():
		if c is AudioStreamPlayer3D:
			n.remove_child(c)
			c.queue_free()


## Boards nailed across a dead door, plus a crate at its foot.
static func planks(parent: Node3D, frame_xf: Transform3D, floor_point: Vector3,
		heading: Vector3, house: Node, rng: RandomNumberGenerator) -> void:
	var h := Vector3(heading.x, 0.0, heading.z).normalized()
	var yaw := Vector3(0, 0, 1).signed_angle_to(h, Vector3.UP)
	var heights := [0.82, 1.42, 1.98]
	var count := rng.randi_range(2, 3)
	for i in count:
		var y := float(heights[i])
		var b := box(parent, Vector3(1.34, 0.115, 0.032),
			floor_point + Vector3(0.0, y, 0.0) - h * 0.09, "plank", yaw)
		b.rotation = Vector3(0.0, yaw, deg_to_rad(rng.randf_range(12.0, 22.0) * (1.0 if i % 2 == 0 else -1.0)))
	if rng.randf() < 0.7:
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var right := h.rotated(Vector3.UP, -PI * 0.5)
		dressing_dup(house, "Box", parent, frame_xf,
			floor_point - h * 0.45 + right * side * 0.42, rng.randf_range(0.0, TAU))


## A house mesh copied into the chase as scenery: no script, no children, and
## the 100x import basis kept intact (only the rotation is replaced). `tip`
## rolls it over onto its side; whatever the pose, it is dropped so its lowest
## point sits on the floor at `pos`. Solid ones get a box body over their
## bounds so the mess is something you have to get around.
static func dressing_dup(house: Node, mesh_name: String, parent: Node3D,
		frame_xf: Transform3D, pos: Vector3, yaw: float, tip := 0.0, solid := false) -> MeshInstance3D:
	if house == null:
		return null
	var tmpl := house.find_child(mesh_name, true, false) as MeshInstance3D
	if tmpl == null:
		return null
	var dup := tmpl.duplicate() as MeshInstance3D
	dup.set_script(null)
	_strip(dup)
	dup.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# spin about the local up, then tip about the local x, then place; the
	# tip happens after the yaw so a chair on its side lies along the wall
	var turn := Basis(Vector3.UP, yaw)
	if absf(tip) > 0.001:
		turn = Basis(turn * Vector3(1, 0, 0), tip) * turn
	var world := Transform3D(frame_xf.basis * turn * tmpl.global_transform.basis, frame_xf * pos)
	dup.transform = frame_xf.affine_inverse() * world
	parent.add_child(dup)
	# ground it: the template's origin is wherever the modeller left it
	var local_box := local_aabb(dup)
	dup.position.y += pos.y - local_box.position.y
	if solid:
		local_box.position.y = pos.y
		blocker(parent, local_box.size, local_box.get_center())
	return dup


## A mesh's bounds in its parent's frame, from all eight corners. Works before
## the room is in the tree, which is when the builders run.
static func local_aabb(mi: MeshInstance3D) -> AABB:
	var xf := mi.transform
	var local: AABB = mi.mesh.get_aabb()
	var out := AABB(xf * local.get_endpoint(0), Vector3.ZERO)
	for i in range(1, 8):
		out = out.expand(xf * local.get_endpoint(i))
	return out


## Bounds of a house mesh as it would stand at yaw 0, so a builder can decide
## how much floor a chair or a crate takes before it places one.
static func dressing_size(house: Node, mesh_name: String) -> Vector3:
	if house == null:
		return Vector3.ZERO
	var tmpl := house.find_child(mesh_name, true, false) as MeshInstance3D
	if tmpl == null:
		return Vector3.ZERO
	return MeshUtilScript.world_aabb(tmpl).size


## Nightmare litter: a plank lying on the floor, or leaning up a wall.
static func plank_litter(parent: Node3D, pos: Vector3, yaw: float, rng: RandomNumberGenerator, depth := 0.0) -> void:
	var b := box(parent, Vector3(1.2 + rng.randf() * 0.5, 0.03, 0.11), pos + Vector3(0.0, 0.015, 0.0),
		"plank", yaw, false, depth)
	(b as MeshInstance3D).rotation.z = deg_to_rad(rng.randf_range(-2.0, 2.0))


# --- windows ------------------------------------------------------------------

## Night at the glass. `centre` is on the wall face, `normal` points into the
## room. Built as a recess rather than a hole: from a dark corridor a lit pane
## in a frame reads as a window, and nothing behind it has to exist. Returns
## the pane so the director can drive its rain and lightning.
static func window(parent: Node3D, centre: Vector3, normal: Vector3, w := 1.0, h := 1.25,
		depth := 0.0) -> MeshInstance3D:
	var n := Vector3(normal.x, 0.0, normal.z).normalized()
	var yaw := Vector3(0, 0, 1).signed_angle_to(n, Vector3.UP)
	var b := Basis(Vector3.UP, yaw)
	var jamb := 0.09

	# The wall behind stays solid, so the pane has to sit just proud of its face
	# or it is simply buried and invisible. Frame and sill stand further out
	# again, which is what sells it as a recess.
	var pane := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(w, h)
	pane.mesh = quad
	var m := ShaderMaterial.new()
	m.shader = RAIN_SHADER
	pane.material_override = m
	pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pane.position = centre + n * 0.02
	pane.basis = b
	parent.add_child(pane)

	# frame around it, and a sill
	for s in [-1.0, 1.0]:
		box(parent, Vector3(jamb, h + jamb * 2.0, 0.1),
			centre + b * Vector3(s * (w + jamb) * 0.5, 0.0, 0.05), "shelf", yaw, false, depth)
	for s in [-1.0, 1.0]:
		box(parent, Vector3(w + jamb * 2.0, jamb, 0.1),
			centre + b * Vector3(0.0, s * (h + jamb) * 0.5, 0.05), "shelf", yaw, false, depth)
	box(parent, Vector3(w + jamb * 3.0, 0.06, 0.18),
		centre + b * Vector3(0.0, -(h + jamb) * 0.5 - 0.03, 0.09), "shelf", yaw, false, depth)
	# a mullion, because a bare rectangle reads as a screen
	box(parent, Vector3(0.045, h, 0.04), centre + b * Vector3(0.0, 0.0, 0.045), "shelf", yaw, false, depth)
	return pane


## Rain you are actually standing in. This used to be three flat sheets hung in
## front of the lens, and it read as exactly that: a picture of rain that slid
## about when you turned. A box of real drops falling through the player instead
## gives parallax for free, because the drops ARE at different distances, and
## they keep falling past you while you run through them.
##
## CPU particles on purpose. GPU ones are the kind of thing that works on the
## machine you built them on and dies on somebody's WebGL2 on jam night.
static func rain_volume(parent: Node3D, count := 850) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "RainVolume"
	p.amount = count
	p.lifetime = 1.5
	# start mid-storm rather than with a bare sky that fills in over a second
	p.preprocess = 1.5
	# world space: moving the emitter must not drag the drops already falling
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(6.0, 0.3, 6.0)
	p.direction = Vector3(0.0, -1.0, 0.0)
	p.spread = 0.0
	# slower than real rain. At -30 the drops cleared the whole play volume in
	# half a second and the air between the hedges read as empty
	p.gravity = Vector3(0.5, -16.0, 0.0)
	p.initial_velocity_min = 5.5
	p.initial_velocity_max = 7.5
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.25
	p.color = Color(0.70, 0.78, 0.92, 0.5)

	var q := QuadMesh.new()
	q.size = Vector2(0.022, 0.5)
	p.mesh = q
	# fixed Y keeps a drop upright instead of pinwheeling to face the camera
	p.material_override = _point_mat(true, 2)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.emitting = false
	parent.add_child(p)
	return p


## Every particle in the chase draws the same way: an unshaded camera-facing
## point that takes its colour from the emitter. Nothing here is lit, which is
## the point - the light budget is already spent.
static func _point_mat(fixed_y: bool, priority: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(1, 1, 1, 1)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y if fixed_y else BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.render_priority = priority
	return m


## A one-shot throw of debris: grit shaken off a ceiling, splinters off a door
## that has just given way. Starts idle; `restart()` fires another lot, so one
## emitter serves every hit in a sequence.
static func burst(parent: Node3D, pos: Vector3, extents: Vector3, dir: Vector3, speed: float,
		count: int, tint: Color, size := 0.022, life := 1.6) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = count
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 0.9
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = extents
	p.direction = dir
	p.spread = 25.0
	p.gravity = Vector3(0.0, -6.5, 0.0)
	p.initial_velocity_min = speed * 0.3
	p.initial_velocity_max = speed
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.4
	p.color = tint
	p.position = pos
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	p.mesh = q
	p.material_override = _point_mat(false, 3)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.emitting = false
	parent.add_child(p)
	return p


## Dust turning over in a shaft of light. Sparse and slow. This is the cheapest
## way to say "through here" without another lamp: the eye goes to the only
## thing in the frame that is moving.
static func motes(parent: Node3D, pos: Vector3, radius: float, count: int,
		tint := Color(1.0, 0.88, 0.66), fall := -0.02) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = count
	p.lifetime = 7.0
	p.preprocess = 7.0
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius
	p.direction = Vector3(0.0, -1.0, 0.0)
	p.spread = 60.0
	p.gravity = Vector3(0.01, fall, 0.0)
	p.initial_velocity_min = 0.01
	p.initial_velocity_max = 0.07
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	p.color = tint
	p.position = pos

	var q := QuadMesh.new()
	q.size = Vector2(0.016, 0.016)
	p.mesh = q
	p.material_override = _point_mat(false, 3)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	return p


# --- lights and triggers ----------------------------------------------------

## A bare bulb on a short cord. Shadowless, short range: GL compatibility caps
## how many lights one mesh can take, so nothing reaches further than it must.
## `show_bulb` false leaves the light with no visible source. The guidance lamps
## (a gap, a crawl, a boarded door) sit at knee height with no fixture to hang
## off, and a bare glowing sphere floating there reads as a bug rather than as a
## bulb: better to see only what it lights.
static func lamp(parent: Node3D, pos: Vector3, energy := 0.9, range_m := 4.5, warm := true,
		cord := true, sway := 0.0, sway_yaw := 0.0, show_bulb := true) -> OmniLight3D:
	# a swaying cord hangs the bulb off to one side; the top stays put
	var top := Vector3(pos.x, CEIL, pos.z)
	var drop := CEIL - pos.y
	var hang := pos
	if cord and absf(sway) > 0.001 and drop > 0.05:
		hang = top + Basis(Vector3.UP, sway_yaw) * Vector3(sin(sway) * drop, -cos(sway) * drop, 0.0)

	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.86, 0.62) if warm else Color(0.72, 0.80, 0.95)
	l.light_energy = energy
	l.omni_range = range_m
	# flatter than the default so the light actually reaches the floor two and a
	# half metres below the bulb instead of dying on the walls
	l.omni_attenuation = 0.85
	l.shadow_enabled = false
	l.position = hang
	parent.add_child(l)
	l.set_meta("base_energy", energy)

	if show_bulb:
		var bulb := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.05
		sm.height = 0.1
		sm.radial_segments = 8
		sm.rings = 4
		bulb.mesh = sm
		bulb.material_override = mat("bulb")
		bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bulb.position = hang - Vector3(0.0, 0.05, 0.0)
		parent.add_child(bulb)
		l.set_meta("bulb", bulb)

	if cord and show_bulb and drop > 0.35:
		var c := box(parent, Vector3(0.03, drop, 0.03), (top + hang) * 0.5, "black", 0.0, false) as MeshInstance3D
		c.basis = _basis_up((top - hang).normalized())
	return l


## The unit vector a yaw points along, for placing things down a corridor.
static func basis_along_v(yaw: float) -> Vector3:
	return Basis(Vector3.UP, yaw) * Vector3(0, 0, 1)


## A basis whose y axis is `up`, for cords and beams that hang along a line.
static func _basis_up(up: Vector3) -> Basis:
	var y := up.normalized()
	var ref := Vector3(1, 0, 0) if absf(y.x) < 0.9 else Vector3(0, 0, 1)
	var z := ref.cross(y).normalized()
	var x := y.cross(z).normalized()
	return Basis(x, y, z)


# --- collapse -----------------------------------------------------------------

## Height under a fallen mass. Standing (1.25) never fits, crouched (0.78) does.
const CRAWL_H := 0.95

## Something big has come down across the way and jammed at head height: a
## wardrobe or a shelf unit lying flat on a crate pile and a tipped chair. The
## only way on is underneath. Built in the corridor's own frame: `centre` is
## the floor point mid-corridor, `across` the direction from one wall to the
## other, `width` the wall-to-wall distance. Returns the LOCAL AABB of the
## crawl (for the hint and the tests) and the mass node in a dictionary.
static func crawl(parent: Node3D, centre: Vector3, across: Vector3, width: float, along_yaw: float,
		house: Node, rng: RandomNumberGenerator, depth: float, animate := false) -> Dictionary:
	var a := Vector3(across.x, 0.0, across.z).normalized()
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	# the wardrobe: lies across, its far end on the crates, near end on the chair
	var mass_len := width + 0.05
	var mass := box(parent, Vector3(mass_len, 0.5, 0.95), centre + Vector3(0.0, CRAWL_H + 0.25, 0.0),
		"shelf", Vector3(1, 0, 0).signed_angle_to(a, Vector3.UP), true, depth) as StaticBody3D
	# ceiling came down with it: plaster hanging to meet the top of the mass
	box(parent, Vector3(width + 0.1, CEIL - CRAWL_H - 0.5 + 0.02, 0.6),
		centre + Vector3(0.0, (CEIL + CRAWL_H + 0.5) * 0.5, 0.0), "ceil",
		Vector3(1, 0, 0).signed_angle_to(a, Vector3.UP), true, depth)
	# crates under one end
	var crate_side := centre + a * side * (width * 0.5 - 0.42)
	dressing_dup(house, "Box", parent, parent.transform, crate_side, along_yaw + rng.randf_range(-0.2, 0.2), 0.0, true)
	dressing_dup(house, "Box", parent, parent.transform, crate_side + Vector3(0.0, 0.46, 0.0),
		along_yaw + rng.randf_range(-0.4, 0.4), 0.0, false)
	# the chair under the other, on its side
	var chair := dressing_dup(house, "Chair_01", parent, parent.transform,
		centre - a * side * (width * 0.5 - 0.5) + Basis(Vector3.UP, along_yaw) * Vector3(0.0, 0.0, 0.3),
		along_yaw + PI * 0.5, PI * 0.5 * side)
	# books that came off the shelves
	for i in rng.randi_range(2, 4):
		var off := Basis(Vector3.UP, along_yaw) * Vector3(rng.randf_range(-0.35, 0.35) * width, 0.0,
			rng.randf_range(-1.3, 1.3))
		dressing_dup(house, "Books_002", parent, parent.transform, centre + off, rng.randf_range(0.0, TAU),
			PI * 0.5 if rng.randf() < 0.5 else 0.0)
	plank_litter(parent, centre + Basis(Vector3.UP, along_yaw) * Vector3(0.0, 0.0, 0.7), along_yaw + 0.3, rng, depth)

	# a bulb down by the gap: without it the mass is a black bar across a black
	# corridor and there is no reading where the way under it is
	var glow := lamp(parent, centre + basis_along_v(along_yaw) * -1.15 + Vector3(0.0, 0.62, 0.0),
		0.55, 3.0, true, false, 0.0, 0.0, false)
	# dust turning in the hole, so it reads as a way through and not a shadow
	motes(parent, centre + Vector3(0.0, CRAWL_H * 0.55, 0.0), 0.45, 12)

	var basis_along := Basis(Vector3.UP, along_yaw)
	var half := basis_along * Vector3(width * 0.5, 0.0, 0.9)
	var lo := centre - Vector3(absf(half.x), 0.0, absf(half.z))
	var out := {
		"aabb": AABB(lo, Vector3(absf(half.x) * 2.0, CRAWL_H, absf(half.z) * 2.0)),
		# the way through, so a hint or a test knows which way to face
		"through": basis_along * Vector3(0, 0, 1),
		"mass": mass,
		"chair": chair,
		"across": a * side,
		"light": glow,
	}
	if animate and mass != null:
		# start it upright against the crate wall; the director drops it
		out["fallen"] = mass.transform
		var up_pos := centre + a * side * (width * 0.5 - 0.3) + Vector3(0.0, mass_len * 0.5 - 0.06, 0.0)
		var up_basis := Basis(Vector3.UP, Vector3(1, 0, 0).signed_angle_to(a, Vector3.UP)) \
			* Basis(Vector3(0, 0, 1), PI * 0.5)
		mass.transform = Transform3D(up_basis, up_pos)
		if chair != null:
			# it starts out in the way and skids in under the falling end
			out["chair_from"] = chair.position + a * side * 0.7
			out["chair_to"] = chair.position
			chair.position = out["chair_from"]
	return out


## Play the fall: the wardrobe comes off the wall and slams down onto the
## crates, the chair skids in under it, everything shakes. Player first: the
## director binds the crawl and calls with whoever tripped it.
static func play_collapse(player: Node3D, c: Dictionary) -> void:
	var mass := c.get("mass") as StaticBody3D
	if mass == null or not c.has("fallen"):
		return
	var fallen: Transform3D = c["fallen"]
	var t := mass.create_tween()
	t.tween_property(mass, "transform", fallen, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_callback(func() -> void:
		AudioBus.sfx_at("closet_thump", mass.global_position, -5.0, 0.06, 0.55)
		AudioBus.sfx_at("door_close", mass.global_position, -8.0, 0.08, 0.7)
		if player != null and player.has_method("shake"):
			player.call("shake", 1.0))
	var chair := c.get("chair") as MeshInstance3D
	if chair != null and c.has("chair_to"):
		var ct := chair.create_tween()
		ct.tween_interval(0.25)
		ct.tween_callback(func() -> void: AudioBus.sfx_at("drawer_slide", chair.global_position, -14.0, 0.1, 0.8))
		ct.tween_property(chair, "position", c["chair_to"] as Vector3, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	AudioBus.sfx_at("door_locked", mass.global_position, -16.0, 0.1, 0.6)
	c.erase("fallen")


## Half the corridor is gone and the way past is off to one side. `centre` is
## the floor point mid-corridor, `across` points wall to wall, `width` is the
## clear span, `along_yaw` faces down the corridor. `gap_side` is which end the
## way through is (+1 along `across`, -1 the other way), `gap_w` how much of
## the span it takes. `crouch` decides whether that gap is a hole under a
## fallen mass or just a squeeze you can run through standing.
##
## Returns the same shape as `crawl`, with "aabb" covering only the gap, so
## the hint and the tests aim at the part you actually go through.
static func barrier(parent: Node3D, centre: Vector3, across: Vector3, width: float, along_yaw: float,
		gap_side: float, gap_w: float, crouch: bool, house: Node, rng: RandomNumberGenerator,
		depth: float) -> Dictionary:
	var a := Vector3(across.x, 0.0, across.z).normalized()
	var yaw := Vector3(1, 0, 0).signed_angle_to(a, Vector3.UP)
	var along := basis_along_v(along_yaw)
	var gap := clampf(gap_w, 0.7, width - 0.5)
	var block_w := width - gap
	# the blocked part, floor to ceiling, hard against the far wall
	var block_c := centre + a * gap_side * (-(width - block_w) * 0.5)
	box(parent, Vector3(block_w, CEIL + 0.02, 0.85), block_c + Vector3(0.0, CEIL * 0.5, 0.0),
		"rubble", yaw, true, depth)
	# junk piled against its face, so it reads as collapsed rather than built
	for i in rng.randi_range(3, 5):
		var s := Vector3(rng.randf_range(0.3, 0.6), rng.randf_range(0.25, 0.5), rng.randf_range(0.3, 0.5))
		var off := a * rng.randf_range(-block_w * 0.4, block_w * 0.4) \
			+ along * (0.45 + s.z * 0.4) * (1.0 if i % 2 == 0 else -1.0)
		var b := box(parent, s, block_c + off + Vector3(0.0, s.y * 0.5, 0.0),
			"rubble" if i % 3 != 0 else "plank", yaw + rng.randf_range(-0.5, 0.5), false, depth) as MeshInstance3D
		b.rotation.x = rng.randf_range(-0.12, 0.12)
	var lean := "Wardrobe" if rng.randf() < 0.5 else "Shelf_01"
	dressing_dup(house, lean, parent, parent.transform,
		block_c + along * -0.7 + a * gap_side * (-block_w * 0.3), along_yaw, PI * 0.5, false)

	var gap_c := centre + a * gap_side * (block_w * 0.5)
	var out := {}
	if crouch:
		# a beam and the ceiling with it, low over the only way on
		box(parent, Vector3(gap + 0.1, 0.42, 0.8), gap_c + Vector3(0.0, CRAWL_H + 0.21, 0.0),
			"shelf", yaw, true, depth)
		box(parent, Vector3(gap + 0.1, CEIL - CRAWL_H - 0.42 + 0.02, 0.55),
			gap_c + Vector3(0.0, (CEIL + CRAWL_H + 0.42) * 0.5, 0.0), "ceil", yaw, true, depth)
		dressing_dup(house, "Box", parent, parent.transform,
			gap_c + a * gap_side * (gap * 0.5 - 0.3) + along * 0.75, rng.randf_range(0.0, TAU), 0.0, false)
		out["light"] = lamp(parent, gap_c + along * -1.1 + Vector3(0.0, 0.62, 0.0),
			0.5, 2.8, true, false, 0.0, 0.0, false)
		motes(parent, gap_c + Vector3(0.0, CRAWL_H * 0.55, 0.0), 0.42, 12)
		out["aabb"] = _flat_aabb(gap_c, along_yaw, gap, 0.9, CRAWL_H)
	else:
		# nothing overhead, you just have to be on the right side of the hall
		out["light"] = lamp(parent, gap_c + Vector3(0.0, CEIL - 0.45, 0.0),
			0.6, 3.4, true, false, 0.0, 0.0, false)
		motes(parent, gap_c + Vector3(0.0, 1.2, 0.0), 0.5, 12)
		out["aabb"] = _flat_aabb(gap_c, along_yaw, gap, 0.9, CEIL)
	out["through"] = along
	out["crouch"] = crouch
	# the point in the gap the monster and the hint aim at
	out["gap_point"] = gap_c
	return out


## An axis-aligned box around a corridor-aligned rectangle.
static func _flat_aabb(centre: Vector3, along_yaw: float, w: float, d: float, h: float) -> AABB:
	var half := Basis(Vector3.UP, along_yaw) * Vector3(w * 0.5, 0.0, d * 0.5)
	var lo := centre - Vector3(absf(half.x), 0.0, absf(half.z))
	return AABB(lo, Vector3(absf(half.x) * 2.0, h, absf(half.z) * 2.0))


## A bookcase standing against the wall that comes down across your way as you
## reach it, throwing its books and papers over the floor. Built upright and
## tidy; `play_topple` is what knocks it over. The fallen pose leaves the far
## side of the corridor open, so it narrows the way rather than closing it.
static func topple(parent: Node3D, at: Vector3, across: Vector3, along_yaw: float,
		house: Node, rng: RandomNumberGenerator, depth: float) -> Dictionary:
	var a := Vector3(across.x, 0.0, across.z).normalized()
	var yaw := Vector3(1, 0, 0).signed_angle_to(a, Vector3.UP)
	var tall := 1.95
	var wide := 0.95
	var body := box(parent, Vector3(wide, tall, 0.34), at + Vector3(0.0, tall * 0.5, 0.0),
		"shelf", yaw, true, depth) as StaticBody3D
	# shelves inside it, so it is not a slab
	for i in 4:
		box(parent, Vector3(wide - 0.08, 0.04, 0.3),
			at + Vector3(0.0, 0.28 + float(i) * 0.45, 0.0), "plank", yaw, false, depth)

	# Where it ends up: face down ALONG the corridor, not across it. Dropped
	# across, a two metre case seals a two metre hall and there is no way past;
	# dropped lengthwise it lies low against one side and takes half the width,
	# which is the point - it narrows the run, it does not end it.
	var along := basis_along_v(along_yaw)
	var lie := 0.34
	var fallen := Transform3D(
		Basis(Vector3.UP, yaw) * Basis(Vector3(1, 0, 0), PI * 0.5),
		at + along * (tall * 0.5) + Vector3(0.0, lie * 0.5, 0.0))
	var fall_dir := along

	# the books and paper it is about to lose, hidden on the shelves for now
	var spill: Array[Node3D] = []
	var ends: Array[Vector3] = []
	for i in rng.randi_range(5, 8):
		var start := at + Vector3(0.0, 0.35 + rng.randf() * 1.4, 0.0) \
			+ a * rng.randf_range(-wide * 0.35, wide * 0.35)
		var item := dressing_dup(house, "Books_002" if i % 2 == 0 else "Books_003", parent,
			parent.transform, start, rng.randf_range(0.0, TAU),
			PI * 0.5 if rng.randf() < 0.5 else 0.0)
		if item == null:
			continue
		spill.append(item)
		ends.append(at + fall_dir * rng.randf_range(0.4, 2.0)
			+ a * rng.randf_range(-1.1, 1.1) - Vector3(0.0, item.position.y - at.y, 0.0))
	return {
		"body": body,
		"fallen": fallen,
		"spill": spill,
		"ends": ends,
		"at": at,
		"yaw": along_yaw,
	}


## Knock it over: the case swings down, the books go with it and scatter.
static func play_topple(player: Node3D, c: Dictionary) -> void:
	var body := c.get("body") as StaticBody3D
	if body == null or not c.has("fallen"):
		return
	var t := body.create_tween()
	t.tween_property(body, "transform", c["fallen"] as Transform3D, 0.7) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_callback(func() -> void:
		AudioBus.sfx_at("closet_thump", body.global_position, -4.0, 0.06, 0.5)
		AudioBus.sfx_at("door_close", body.global_position, -9.0, 0.08, 0.65)
		if player != null and player.has_method("shake"):
			player.call("shake", 1.3))
	var spill: Array = c.get("spill", [])
	var ends: Array = c.get("ends", [])
	for i in mini(spill.size(), ends.size()):
		var item := spill[i] as Node3D
		if item == null or not is_instance_valid(item):
			continue
		var st := item.create_tween()
		st.tween_interval(0.18 + 0.05 * float(i))
		st.tween_property(item, "position", ends[i] as Vector3, 0.45) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		st.parallel().tween_property(item, "rotation:y",
			item.rotation.y + randf_range(-3.0, 3.0), 0.45)
	AudioBus.sfx_at("cloth", body.global_position, -10.0, 0.12, 1.2)
	c.erase("fallen")


## The other way is gone: a floor-to-ceiling jam of broken masonry and junk
## across a corridor of `width`, `deep` thick, at `centre` (floor point).
static func rubble(parent: Node3D, centre: Vector3, across: Vector3, width: float, deep: float,
		house: Node, rng: RandomNumberGenerator, depth: float) -> void:
	var a := Vector3(across.x, 0.0, across.z).normalized()
	var yaw := Vector3(1, 0, 0).signed_angle_to(a, Vector3.UP)
	var along := a.rotated(Vector3.UP, PI * 0.5)
	box(parent, Vector3(width + 0.1, CEIL + 0.02, deep), centre + Vector3(0.0, CEIL * 0.5, 0.0),
		"rubble", yaw, true, depth)
	# lumps spilling off the face on both sides
	for i in rng.randi_range(5, 8):
		var s := Vector3(rng.randf_range(0.3, 0.7), rng.randf_range(0.2, 0.55), rng.randf_range(0.3, 0.6))
		var off := a * rng.randf_range(-width * 0.45, width * 0.45) \
			+ along * (deep * 0.5 + s.z * 0.35) * (1.0 if i % 2 == 0 else -1.0)
		var b := box(parent, s, centre + off + Vector3(0.0, s.y * 0.5 - 0.02, 0.0),
			"rubble" if i % 3 != 0 else "plank", yaw + rng.randf_range(-0.6, 0.6), false, depth) as MeshInstance3D
		b.rotation.x = rng.randf_range(-0.15, 0.15)
	for n in ["Box", "Chair_01", "Broom"]:
		if rng.randf() < 0.7:
			var off := a * rng.randf_range(-width * 0.4, width * 0.4) + along * (deep * 0.5 + 0.5) * (1.0 if rng.randf() < 0.5 else -1.0)
			dressing_dup(house, n, parent, parent.transform, centre + off, rng.randf_range(0.0, TAU),
				PI * 0.5 if rng.randf() < 0.4 else 0.0)


## The cone of light under a lamp. `from` is the bulb, `drop` how far down it
## reaches, `spread` its radius at the bottom. Returns the mesh so the director
## can animate it with the lamp it belongs to.
##
## Keep `spread` under about a third of `drop`. The shader fades the cone out
## toward its rim, and on a cone the shell sits at a constant fraction 2*spread
## /drop of the way out; open it up much past that and the whole thing is rim,
## which is to say invisible. A wide beam is several narrow ones nested.
static func shaft(parent: Node3D, from: Vector3, drop: float, spread: float,
		tint := Color(1.0, 0.86, 0.62), energy := 0.5, tilt := Vector3.ZERO) -> MeshInstance3D:
	var cone := CylinderMesh.new()
	cone.top_radius = 0.045
	cone.bottom_radius = spread
	cone.height = drop
	cone.radial_segments = 12
	cone.rings = 1
	cone.cap_top = false
	cone.cap_bottom = false

	var mi := MeshInstance3D.new()
	mi.mesh = cone
	var m := ShaderMaterial.new()
	m.shader = SHAFT_SHADER
	m.set_shader_parameter("shaft_color", tint)
	m.set_shader_parameter("energy", energy)
	m.set_shader_parameter("span", drop)
	m.render_priority = 3
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = from - Vector3(0.0, drop * 0.5, 0.0)
	if tilt != Vector3.ZERO:
		mi.rotation = tilt
	parent.add_child(mi)
	return mi


## A box area the player trips. Layer 0, mask 2: it sees the player and
## nothing sees it.
static func trigger(parent: Node3D, size: Vector3, pos: Vector3, trigger_name: String) -> Area3D:
	var a := Area3D.new()
	a.name = trigger_name
	a.collision_layer = 0
	a.collision_mask = 2
	a.monitoring = true
	a.position = pos
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	a.add_child(cs)
	parent.add_child(a)
	return a


# --- stairs -----------------------------------------------------------------

## A flight running from `from` (the floor point where it leaves the landing)
## along `dir`. Visual treads and risers plus ONE tilted slab for collision, so
## the capsule slides down instead of catching every nose. `rise` negative
## descends. The slab meets both landings exactly, and the treads are drawn at
## the middle of each step so the walked surface never floats. Returns
## {top, bottom} floor points.
static func stairs(parent: Node3D, from: Vector3, dir: Vector3, width: float,
		steps: int, rise: float, run: float) -> Dictionary:
	var d := Vector3(dir.x, 0.0, dir.z).normalized()
	var yaw := Vector3(0, 0, 1).signed_angle_to(d, Vector3.UP)
	var bottom := from + d * (run * steps) + Vector3(0.0, rise * steps, 0.0)

	for i in steps:
		var mid_y := from.y + rise * (float(i) + 0.5)
		var centre := from + d * (run * (float(i) + 0.5))
		centre.y = mid_y
		box(parent, Vector3(width, 0.06, run), centre - Vector3(0.0, 0.03, 0.0), "floor", yaw, false)
		var riser_h := absf(rise)
		if riser_h > 0.01:
			var edge := from + d * (run * float(i + 1))
			edge.y = from.y + rise * float(i + 1) + riser_h * 0.5
			box(parent, Vector3(width, riser_h, 0.05), edge, "floor", yaw, false)

	var length := (bottom - from).length()
	var pitch := atan2(rise * steps, run * steps)
	var ramp := StaticBody3D.new()
	ramp.collision_layer = 1
	ramp.collision_mask = 0
	var rb := Basis(Vector3.UP, yaw) * Basis(Vector3(1, 0, 0), -pitch)
	ramp.basis = rb
	# sunk along the slab's own up, so its top face lands exactly on the line
	# from the upper landing to the lower one
	ramp.position = (from + bottom) * 0.5 - rb.y * 0.1
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, 0.2, length)
	cs.shape = shape
	ramp.add_child(cs)
	parent.add_child(ramp)
	return {"top": from, "bottom": bottom}


## An upright cylinder standing on `base` (its bottom centre): pillars, plinths,
## the disc at the top of a flight. Drawn in chunks up its height for the same
## reason split_box exists, with one shape for the whole thing.
static func column(parent: Node3D, radius: float, height: float, base: Vector3, key: String,
		solid := true, sides := 16, depth := 0.0, seg := 5.0) -> Node3D:
	var count := maxi(1, int(ceil(height / seg)))
	var step := height / float(count)
	for i in count:
		var cm := CylinderMesh.new()
		cm.top_radius = radius
		cm.bottom_radius = radius
		cm.height = step
		cm.radial_segments = sides
		cm.rings = 1
		cm.cap_top = i == count - 1
		cm.cap_bottom = i == 0
		var mi := MeshInstance3D.new()
		mi.mesh = cm
		mi.material_override = mat(key, depth)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = base + Vector3(0.0, (float(i) + 0.5) * step, 0.0)
		parent.add_child(mi)
	if not solid:
		return parent
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = base + Vector3(0.0, height * 0.5, 0.0)
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	cs.shape = shape
	body.add_child(cs)
	parent.add_child(body)
	return body


## Is `a` inside the arc that runs from `from` to `to` the positive way round?
static func angle_in(a: float, from: float, to: float) -> bool:
	return fposmod(a - from, TAU) <= fposmod(to - from, TAU)


## A flat ring, optionally with a bite out of it. The bite is what makes a
## landing at the top of a spiral work at all: the last turn of the flight comes
## up through the hole instead of into the underside of the floor.
static func ring(parent: Node3D, r_in: float, r_out: float, thickness: float, base: Vector3,
		key: String, sides := 24, gap_from := 0.0, gap_to := 0.0, depth := 0.0) -> void:
	var span := r_out - r_in
	var mid_r := (r_in + r_out) * 0.5
	var wide := TAU * r_out / float(sides) * 1.08
	var has_gap := absf(fposmod(gap_to - gap_from, TAU)) > 0.001
	for k in sides:
		var a := TAU * (float(k) + 0.5) / float(sides)
		if has_gap and angle_in(a, gap_from, gap_to):
			continue
		# yaw pi/2 - a puts the slice's length along the radius
		box(parent, Vector3(wide, thickness, span),
			base + Vector3(cos(a), 0.0, sin(a)) * mid_r + Vector3(0.0, thickness * 0.5, 0.0),
			key, PI * 0.5 - a, true, depth)


## A flight wound round a pillar. Same bargain as `stairs`: the treads you see
## are loose meshes and the thing you actually walk on is a smooth ramp under
## them, except here the ramp is a helix, so it is one tilted slab per step with
## its ends run long into its neighbours. A capsule glides up it; the sagitta
## across one step is under two centimetres, which is nothing next to the tread
## it is buried in.
##
## `turn` is radians per step, signed. `start` is the angle the first step sits
## at, measured from +x toward +z. Returns {top, bottom, points, parts}:
## `points` walks the centreline, for a nav graph or an autoplayer, and `parts`
## is every node the flight is made of, each carrying a "step" meta, so a
## director can take the whole thing apart from the bottom up.
static func spiral_stairs(parent: Node3D, centre: Vector3, r_in: float, width: float, steps: int,
		rise: float, start := 0.0, turn := 0.22, rail_from := 0, rail_stop := 0,
		key := "floor", depth := 0.0) -> Dictionary:
	var r_mid := r_in + width * 0.5
	var r_out := r_in + width
	# tangential span of one step at the OUTER edge, plus a margin, or the treads
	# gap where they are widest
	var tread := absf(turn) * r_out * 1.06
	var points: Array[Vector3] = []
	var parts: Array[Node3D] = []

	for i in steps:
		var first := parts.size()
		var a0 := start + turn * float(i)
		var a_mid := a0 + turn * 0.5
		var mid_y := rise * (float(i) + 0.5)
		var dir_mid := Vector3(cos(a_mid), 0.0, sin(a_mid))
		var at := centre + dir_mid * r_mid + Vector3(0.0, mid_y, 0.0)
		# yaw -a puts the box's own x along the radius and its z along the tangent
		parts.append(box(parent, Vector3(width, 0.06, tread), at - Vector3(0.0, 0.03, 0.0),
			key, -a_mid, false, depth))

		if absf(rise) > 0.01:
			var dir0 := Vector3(cos(a0), 0.0, sin(a0))
			parts.append(box(parent, Vector3(width, absf(rise), 0.05),
				centre + dir0 * r_mid + Vector3(0.0, mid_y, 0.0), key, -a0, false, depth))

		# the ramp segment, run 12 per cent long at both ends so the joints are
		# buried under the tread rather than sitting in the open as a lip
		var p0 := centre + Vector3(cos(a0), 0.0, sin(a0)) * r_mid + Vector3(0.0, rise * float(i), 0.0)
		var a1 := a0 + turn
		var p1 := centre + Vector3(cos(a1), 0.0, sin(a1)) * r_mid + Vector3(0.0, rise * float(i + 1), 0.0)
		var chord := p1 - p0
		var flat := Vector3(chord.x, 0.0, chord.z)
		if flat.length() > 0.001:
			var yaw := Vector3(0, 0, 1).signed_angle_to(flat.normalized(), Vector3.UP)
			var pitch := atan2(chord.y, flat.length())
			var rb := Basis(Vector3.UP, yaw) * Basis(Vector3(1, 0, 0), -pitch)
			parts.append(blocker(parent, Vector3(width, 0.22, chord.length() * 1.24),
				(p0 + p1) * 0.5 - rb.y * 0.11, rb))

		points.append(at + Vector3(0.0, 0.03, 0.0))

		# open at the foot so there is a way on to the thing at all - a rail round
		# the first step is a fence across the entrance - and open at the top on
		# purpose, so the fall is a fall and not a shove into a wall
		if i >= rail_from and i < steps - rail_stop and i % 2 == 0:
			parts.append(box(parent, Vector3(0.07, 0.86, tread * 2.05),
				centre + Vector3(cos(a_mid), 0.0, sin(a_mid)) * (r_out + 0.04)
					+ Vector3(0.0, mid_y + 0.43, 0.0),
				key, -a_mid, true, depth))

		for p in range(first, parts.size()):
			parts[p].set_meta("step", i)

	return {
		"top": centre + Vector3(cos(start + turn * float(steps)), 0.0, sin(start + turn * float(steps))) * r_mid
			+ Vector3(0.0, rise * float(steps), 0.0),
		"bottom": centre + Vector3(cos(start), 0.0, sin(start)) * r_mid,
		"points": points,
		"parts": parts,
	}


## Something burning away to nothing: fine motes drifting up, heavier flakes
## sagging out of them. Unlike `burst` this one runs for as long as it is left
## emitting, because a thing coming apart takes a few seconds to finish.
static func ash(parent: Node3D, pos: Vector3, extents: Vector3, count: int,
		tint := Color(0.42, 0.40, 0.40), life := 3.4, lift := 0.35) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = count
	p.lifetime = life
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = extents
	p.direction = Vector3(0.0, 1.0, 0.0)
	p.spread = 40.0
	p.gravity = Vector3(0.02, lift, 0.0)
	p.initial_velocity_min = 0.05
	p.initial_velocity_max = 0.42
	p.damping_min = 0.1
	p.damping_max = 0.5
	p.scale_amount_min = 0.4
	p.scale_amount_max = 1.5
	p.color = tint
	p.position = pos
	var q := QuadMesh.new()
	q.size = Vector2(0.018, 0.018)
	p.mesh = q
	p.material_override = _point_mat(false, 3)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.emitting = false
	parent.add_child(p)
	return p
