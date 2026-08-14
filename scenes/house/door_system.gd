class_name DoorSystem
extends Node3D
## Builds a functional Door rig for every swing panel in the house model, and
## plain collision for the panels that never move (garage doors, shower slider).
##
## Swing signs were derived from each panel's hinge edge and the room it should
## open into; they get one in-game tuning pass. Spill sides are world directions
## pointing into the room that sees the glow.

## Per door: panel (mesh name in house.fbx), then optional:
## locked, script_locked, blocked_line, swing (+1/-1 about world Y), open_deg,
## ajar (initial degrees), spill (Vector3 side), spill_energy, spill_on.
const SWING_DOORS: Array[Dictionary] = [
	# Kid's bedroom door. First door the player ever opens; dad's door in Act 1.
	{"panel": "Door_006", "swing": -1.0, "open_deg": 105.0,
		"spill": Vector3(0, 0, -1), "spill_energy": 0.75, "spill_on": true},
	# The closet. Player can't open it themselves. Cold spill rig, stays off
	# until the director wants it in act 1.
	{"panel": "closet_door_03", "swing": -1.0, "open_deg": 100.0,
		"script_locked": true, "blocked_line": "kid_no_way",
		"spill": Vector3(0, 0, -1), "spill_energy": 0.3,
		"spill_color": Color(0.60, 0.72, 0.98), "spill_on": false},
	# Dad's bedroom. Locked forever, faint glow under the door so you know
	# he's in there. Glow faces the approach side (south of the z=-8.73 wall).
	{"panel": "Door_002", "locked": true,
		"spill": Vector3(0, 0, -1), "spill_energy": 0.35, "spill_on": true},
	# Kid's bathroom. Ajar and lit, this is the act 0 guidance. Needs the wide
	# ajar angle or the lit gap doesn't read from across the landing.
	{"panel": "Door_003", "swing": -1.0, "open_deg": 100.0, "ajar": 25.0,
		"spill": Vector3(0, 0, 1), "spill_energy": 1.4, "spill_on": true},
	{"panel": "Door_001", "swing": 1.0, "open_deg": 105.0},   # third bedroom
	{"panel": "Door_004", "swing": 1.0, "open_deg": 100.0},   # linen closet
	{"panel": "Door_005", "swing": 1.0, "open_deg": 105.0},   # bathtub bathroom
	{"panel": "Door_008", "swing": 1.0, "open_deg": 105.0},   # ground bathroom
	{"panel": "Door", "locked": true},                        # front door, night
	{"panel": "Door_009", "locked": true},                    # rear door, night
	{"panel": "closet_door", "swing": -1.0, "open_deg": 100.0},     # under-stairs L
	{"panel": "closet_door_01", "swing": 1.0, "open_deg": 100.0},   # under-stairs R
	{"panel": "closet_door_02", "swing": -1.0, "open_deg": 95.0},   # under-stairs
]

const STATIC_PANELS: Array[String] = ["Garage_Door", "Garage_Door_01", "Shower_Door"]

var _doors := {}


func build(house_visual: Node3D) -> void:
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
		door.open_deg = float(cfg.get("open_deg", 105.0))
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


func get_door(panel_name: String) -> Door:
	return _doors.get(panel_name) as Door
