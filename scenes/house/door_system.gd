class_name DoorSystem
extends Node3D
## Builds a functional Door rig for every swing panel in the house model, and
## plain collision for the panels that never move (garage doors, shower slider).
##
## `swing` is the direction the DIRECTOR opens a door (+1/-1 about world Y);
## player opens swing away from the player's side instead, see Door. Panels sit
## centred in a 0.2 m frame, so 90 degrees is flat to the wall with clearance;
## anything past that clips the far edge into the wall. Spill sides are world
## directions pointing into the room that sees the glow.

## Per door: panel (mesh name in house.fbx), then optional:
## locked, script_locked, blocked_line, swing, open_deg (default 90),
## ajar (initial degrees), spill (Vector3 side), spill_energy, spill_on.
const SWING_DOORS: Array[Dictionary] = [
	# Kid's bedroom door. First door the player ever opens; dad's door in Act 1
	# (he opens it into the room, swing -1).
	{"panel": "Door_006", "swing": -1.0,
		"spill": Vector3(0, 0, -1), "spill_energy": 0.75, "spill_on": true},
	# The closet. Player can't open it themselves. Cold spill rig, stays off
	# until the director wants it in act 1.
	{"panel": "closet_door_03", "swing": -1.0,
		"script_locked": true, "blocked_line": "kid_no_way",
		"spill": Vector3(0, 0, -1), "spill_energy": 0.3,
		"spill_color": Color(0.60, 0.72, 0.98), "spill_on": false},
	# Walk-in closet inside the parents' room. Behind the parents' door now, so
	# just locked. Dad's actual door is built in _build_parents_door.
	{"panel": "Door_002", "locked": true},
	# Kid's bathroom, off the west hall. Ajar and lit, this is the act 0
	# guidance. Ajar swings into the bathroom (swing -1).
	{"panel": "Door_003", "swing": -1.0, "ajar": 25.0,
		"spill": Vector3(0, 0, 1), "spill_energy": 1.4, "spill_on": true},
	{"panel": "Door_001", "swing": 1.0},    # third bedroom
	# Hall door between the landing and the west hall (bathroom, parents' room).
	{"panel": "Door_004", "swing": 1.0},
	{"panel": "Door_005", "swing": 1.0},    # bathtub bathroom
	{"panel": "Door_008", "swing": 1.0},    # ground bathroom
	{"panel": "Door", "locked": true},      # front door, night
	{"panel": "Door_009", "locked": true},  # rear door, night
	{"panel": "closet_door", "swing": -1.0},     # under-stairs L
	{"panel": "closet_door_01", "swing": 1.0},   # under-stairs R
	# under-stairs: the collider shell is solid around this one, it cannot swing
	{"panel": "closet_door_02", "locked": true},
]

const STATIC_PANELS: Array[String] = ["Garage_Door", "Garage_Door_01", "Shower_Door"]

## The pack leaves the parents' room open to the west hall (no panel, no
## frame, a 1.19 m gap at the hall's west end). A door is built there from
## Door_002's panel and Door_frame_010, widened to fill the gap. This is the
## door dad is behind.
const PARENTS_DOOR_NAME := "parents_door"
const PARENTS_DOOR_X := 1.12
const PARENTS_DOOR_Z_MIN := -8.66
const PARENTS_DOOR_Z_MAX := -7.47
const PARENTS_DOOR_CEILING := 6.87

var _doors := {}


func build(house_visual: Node3D) -> void:
	# grab source meshes before the loop reparents the originals
	var src_panel := house_visual.find_child("Door_002", true, false) as MeshInstance3D
	var src_frame := house_visual.find_child("Door_frame_010", true, false) as MeshInstance3D
	var wall_src := house_visual.find_child("Home_010", true, false) as MeshInstance3D
	var wall_mat: Material = wall_src.get_active_material(0) if wall_src else null

	for cfg: Dictionary in SWING_DOORS:
		var panel_name := String(cfg["panel"])
		var panel := house_visual.find_child(panel_name, true, false) as MeshInstance3D
		if panel == null:
			push_warning("DoorSystem: panel '%s' not found in house model" % panel_name)
			continue
		var door := Door.new()
		door.name = panel_name + "Rig"
		door.locked = bool(cfg.get("locked", false))
		door.script_locked = bool(cfg.get("script_locked", false))
		door.blocked_line = String(cfg.get("blocked_line", ""))
		door.swing = float(cfg.get("swing", -1.0))
		door.open_deg = float(cfg.get("open_deg", 90.0))
		add_child(door)
		door.setup(panel)
		if cfg.has("spill"):
			door.add_spill(
				cfg["spill"],
				float(cfg.get("spill_energy", 0.7)),
				cfg.get("spill_color", Door.SPILL_COLOR)
			)
			door.set_spill(bool(cfg.get("spill_on", false)))
		if cfg.has("ajar"):
			door.set_ajar_instant(float(cfg["ajar"]))
		_doors[panel_name] = door

	# Panels that never move still need to stop the player.
	for panel_name: String in STATIC_PANELS:
		var mesh := house_visual.find_child(panel_name, true, false) as MeshInstance3D
		if mesh == null:
			push_warning("DoorSystem: static panel '%s' not found" % panel_name)
			continue
		var shape := mesh.mesh.create_trimesh_shape()
		if shape:
			var body := StaticBody3D.new()
			body.collision_layer = 1
			body.collision_mask = 0
			var cs := CollisionShape3D.new()
			cs.shape = shape
			body.add_child(cs)
			mesh.add_child(body)

	if src_panel and src_frame:
		_build_parents_door(house_visual, src_panel, src_frame, wall_mat)
	else:
		push_warning("DoorSystem: parents' door sources missing, west hall stays open")


func get_door(panel_name: String) -> Door:
	return _doors.get(panel_name) as Door


## Copies a mesh into a scaled wrapper so its world AABB centre lands on
## `center`, rotated 90 degrees about Y (the sources face Z, the gap faces X)
## and stretched along world Z by `width_scale`. Returns the mesh instance.
func _place_copy(parent: Node3D, src: MeshInstance3D, center: Vector3, width_scale: float,
		node_name: String) -> MeshInstance3D:
	var rot := Basis(Vector3.UP, PI * 0.5)
	var src_aabb := Door._world_aabb(src)
	var origin_to_center := src_aabb.get_center() - src.global_position
	var wrapper := Node3D.new()
	wrapper.name = node_name + "Wrap"
	parent.add_child(wrapper)
	wrapper.global_position = center
	wrapper.scale = Vector3(1.0, 1.0, width_scale)
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = src.mesh
	for s in src.mesh.get_surface_count():
		var ov := src.get_surface_override_material(s)
		if ov:
			mi.set_surface_override_material(s, ov)
	wrapper.add_child(mi)
	# the wrapper scale applies to this offset too, which is what puts the
	# stretched mesh's centre exactly on `center`
	mi.transform = Transform3D(rot * src.global_basis, -(rot * origin_to_center))
	return mi


func _build_parents_door(house_visual: Node3D, src_panel: MeshInstance3D,
		src_frame: MeshInstance3D, wall_mat: Material) -> void:
	var gap := PARENTS_DOOR_Z_MAX - PARENTS_DOOR_Z_MIN
	var zc := (PARENTS_DOOR_Z_MAX + PARENTS_DOOR_Z_MIN) * 0.5
	var frame_aabb := Door._world_aabb(src_frame)
	var panel_aabb := Door._world_aabb(src_panel)
	var width_scale := gap / frame_aabb.size.x

	_place_copy(house_visual, src_frame,
		Vector3(PARENTS_DOOR_X, frame_aabb.get_center().y, zc), width_scale, "ParentsDoorFrame")
	var panel := _place_copy(house_visual, src_panel,
		Vector3(PARENTS_DOOR_X, panel_aabb.get_center().y, zc), width_scale, "ParentsDoorPanel")

	# wall above the frame up to the ceiling, in the house plaster
	var top := frame_aabb.position.y + frame_aabb.size.y
	if PARENTS_DOOR_CEILING - top > 0.05:
		var header := MeshInstance3D.new()
		header.name = "ParentsDoorHeader"
		var box := BoxMesh.new()
		box.size = Vector3(0.22, PARENTS_DOOR_CEILING - top + 0.02, gap)
		header.mesh = box
		if wall_mat:
			header.material_override = wall_mat
		house_visual.add_child(header)
		header.global_position = Vector3(PARENTS_DOOR_X, (top + PARENTS_DOOR_CEILING) * 0.5, zc)

	var door := Door.new()
	door.name = PARENTS_DOOR_NAME + "Rig"
	door.locked = true
	add_child(door)
	door.setup(panel)
	# dad's light, leaking into the hall
	door.add_spill(Vector3(1, 0, 0), 0.4)
	door.set_spill(true)
	_doors[PARENTS_DOOR_NAME] = door
