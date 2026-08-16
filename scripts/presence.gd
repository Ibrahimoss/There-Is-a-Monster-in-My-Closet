extends Node
## Runtime decoration of the level scene, autoloaded as `Presence`.
##
## The level scene (real_world.tscn) is edited by hand and stays plain: bare
## player node, door meshes with the Door script, lamps, dialogue triggers.
## Everything mechanical that does not need placing in the editor is attached
## here at runtime, by node name, once the player reports in from _ready:
## door registration, light switches, the small bathroom's drawers, cabinet,
## toilet lid and seat, tap and flush.
##
## Feature flags below so any of it can be switched off from one place.
## Scripts are preloaded by path: autoloads parse before the global class
## cache exists on a fresh clone, so class names are not safe here.

const DoorScript := preload("res://scripts/door.gd")
const PropScript := preload("res://scripts/prop.gd")
const HingedPropScript := preload("res://scripts/hinged_prop.gd")
const SlidingPropScript := preload("res://scripts/sliding_prop.gd")
const SwitchPropScript := preload("res://scripts/switch_prop.gd")
const SimpleInteractableScript := preload("res://scripts/simple_interactable.gd")
const MeshUtilScript := preload("res://scripts/mesh_util.gd")
const BedtimeScript := preload("res://scripts/bedtime.gd")
const ChaseScript := preload("res://scripts/chase.gd")
const DreamScript := preload("res://scripts/dream.gd")

const DECORATE_DOORS := true
const DECORATE_SWITCHES := true
const DECORATE_LAMPS := true
const DECORATE_BATHROOM := true
## Act 0 objective chain (lights, drip, toothbrush, bed, closet). Off if the
## level scene brings its own sequencing for these beats.
const DECORATE_BEDTIME := true
## The dream rooms between act 0 and the chase. The pillow hall is the last of
## them; anything that comes before it hands off to Dream.begin instead of
## Bedtime doing it directly.
const DECORATE_DREAM := true
## Act 1, the chase: takes over from the dream's `finished`, or from Bedtime's
## if the dream is switched off.
const DECORATE_CHASE := true
## A faint cool ambient so unlit rooms are not pure black. Skipped
## if the level scene brings its own WorldEnvironment.
const DECORATE_ENVIRONMENT := true
const NIGHT_AMBIENT := Color(0.62, 0.68, 0.82)
const NIGHT_AMBIENT_ENERGY := 0.12
const NIGHT_SKY := Color(0.015, 0.02, 0.035)

## Small bathroom pieces, by mesh name in the level's `house`.
const DRAWERS: Array[String] = ["Washbasin_drawer_02_001", "Washbasin_drawer_03_001"]
const CABINET_DOORS: Array[String] = ["Bathroom_cabinet_door_001", "Bathroom_cabinet_door_01_001"]
const TOILET_LID := "Toilet_Tapa_01_001"
const TOILET_SEAT := "Toilet_Tapa_02_001"
const TOILET := "Toilet_01_001"
const TAP := "Manija_Washbasin_05_001"

var _player: CharacterBody3D
var _root: Node
var _house: Node
var _doors: Array[MeshInstance3D] = []
var _props: Array[Node3D] = []
var _tap_player: AudioStreamPlayer3D


## Called (deferred) by the player once it is in the tree, so the whole level
## is ready by the time this runs.
func on_player_ready(player: CharacterBody3D) -> void:
	_player = player
	# the level root: the player's scene owner in play, whatever holds it in tests
	_root = player.owner if player.owner != null else get_tree().current_scene
	if _root == null:
		return
	_doors.clear()
	_props.clear()
	_house = _root.get_node_or_null("house")
	if DECORATE_ENVIRONMENT:
		_build_environment()
	if DECORATE_DOORS:
		_collect_doors(_root)
	if _house == null:
		return
	if DECORATE_SWITCHES:
		_build_switches()
	if DECORATE_LAMPS:
		_build_lamp_switches()
	if DECORATE_BATHROOM:
		_build_bathroom()
	# CHASE=1 starts act 1 from the bedroom, CHASE=rooms from the first
	# hallway. Desktop only, and it skips act 0 entirely.
	var dev := "" if OS.has_feature("web") else OS.get_environment("CHASE")
	# DREAM=1|top|dark|hall drops straight into the pillow hall the same way.
	var dream_dev := "" if OS.has_feature("web") else OS.get_environment("DREAM")
	var skip_act0 := not dev.is_empty() or not dream_dev.is_empty()
	if DECORATE_BEDTIME and not skip_act0 and _root.get_node_or_null("Bedtime") == null:
		var d: Node = BedtimeScript.new()
		d.name = "Bedtime"
		_root.add_child(d)
		d.call("setup", _root, _house, _player)
	var dream: Node = null
	if DECORATE_DREAM and _root.get_node_or_null("Dream") == null:
		dream = DreamScript.new()
		dream.name = "Dream"
		_root.add_child(dream)
		dream.call("setup", _root, _house, _player)
	if DECORATE_CHASE and _root.get_node_or_null("Chase") == null:
		var c: Node = ChaseScript.new()
		c.name = "Chase"
		_root.add_child(c)
		c.call("setup", _root, _house, _player)
		# The running order: Bedtime, Ibrahim's act1 (his room, the flip, the
		# sewer, out at the bathroom), then the pillow hall, then the chase.
		#
		# act1 is not built here — it is a node in the level scene carrying
		# its own script, and it arms itself when GameState reaches
		# Act.CLOSET, which is what Bedtime sets on its way out. So Bedtime
		# hands to it without a connection and only what follows is wired
		# here. A level with no act1 (the tool scenes build a bare one)
		# falls back to Bedtime going straight to the pillow hall.
		var bedtime := _root.get_node_or_null("Bedtime")
		var act1 := _root.get_node_or_null("act1")
		var head: Node = dream if dream != null else c
		if act1 != null and act1.has_signal("finished"):
			act1.connect("finished", Callable(head, "begin"))
		elif bedtime != null:
			bedtime.connect("finished", Callable(head, "begin"))
		if dream != null:
			dream.connect("finished", Callable(c, "begin"))
		if bedtime == null and skip_act0:
			if not dream_dev.is_empty() and dream != null:
				_start_dev(dream, dream_dev, true)
			else:
				_start_dev(c, dev, false)


## Dev entry: act 0 never ran, so put the kid where it would have left them,
## take the house lights down to the one behind the bathroom door, and start.
## `dream` picks which director gets the mode string.
func _start_dev(director: Node, mode: String, dream: bool) -> void:
	# act 0's opening line has no business firing here
	var opener := _root.get_node_or_null("start dialouge")
	if opener != null:
		opener.queue_free()
	_player.teleport_to(BedtimeScript.START_POS)
	_player.rotation.y = deg_to_rad(BedtimeScript.START_YAW)
	_player.sync_look_from_transform()
	var lamps := _lamps()
	if lamps != null:
		var by_mesh: Dictionary = lamps.get("lights_by_mesh")
		for k: String in by_mesh.keys():
			var l := by_mesh[k] as Light3D
			if l == null:
				continue
			l.visible = k == "Focus_02_012"
			if l.visible:
				l.light_energy *= 2.2
				if l is OmniLight3D:
					(l as OmniLight3D).omni_range = 6.5
		for c in _root.get_children():
			if c is Light3D:
				(c as Light3D).visible = false
	var intro := _root.get_node_or_null("EyeOpenIntro")
	if intro != null and intro.has_signal("finished"):
		await intro.finished
	else:
		await get_tree().create_timer(1.0).timeout
	_player.cinematic = false
	if dream:
		if mode == "1" or mode.is_empty():
			director.call("begin")
		else:
			director.call("begin_at", mode)
	elif mode == "rooms":
		director.call("begin_at_rooms")
	else:
		director.call("begin")


func get_doors() -> Array[MeshInstance3D]:
	return _doors


func get_door(door_name: String) -> MeshInstance3D:
	for d in _doors:
		if String(d.name) == door_name:
			return d
	return null


func get_prop(mesh_name: String) -> Node3D:
	for p in _props:
		if String(p.name) == mesh_name + "Prop":
			return p
	return null


func get_props() -> Array[Node3D]:
	return _props


func get_player() -> CharacterBody3D:
	return _player


func _build_environment() -> void:
	for c in _root.get_children():
		if c is WorldEnvironment:
			return
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = NIGHT_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = NIGHT_AMBIENT
	env.ambient_light_energy = NIGHT_AMBIENT_ENERGY
	var we := WorldEnvironment.new()
	we.name = "NightEnvironment"
	we.environment = env
	_root.add_child(we)


func _collect_doors(node: Node) -> void:
	if node is DoorScript:
		_doors.append(node as MeshInstance3D)
	for c in node.get_children():
		_collect_doors(c)


func _mesh(name: String) -> MeshInstance3D:
	return _house.find_child(name, true, false) as MeshInstance3D


func _lamps() -> Node:
	return _root.get_node_or_null("LampLights")


func _add_prop(p: Node3D, mi: MeshInstance3D, pivot_mode: int, pad: Vector3, solid := false) -> void:
	p.name = String(mi.name) + "Prop"
	_house.add_child(p)
	p.call("adopt", mi, pivot_mode, pad, solid)
	_props.append(p)


# --- switches ---------------------------------------------------------------

## Every Light_switch_* mesh: which side of its wall faces the room decides
## the room, the nearest ceiling light on that side is what it toggles, plus
## any AreaLight sitting near that ceiling light.
func _build_switches() -> void:
	var lamps := _lamps()
	if lamps == null or not lamps.has_method("ceiling_lights"):
		return
	var ceiling: Dictionary = lamps.call("ceiling_lights")
	var area_lights: Array[Light3D] = []
	for c in _root.get_children():
		if c is Light3D:
			area_lights.append(c as Light3D)
	var space := _player.get_world_3d().direct_space_state

	var stack: Array[Node] = [_house]
	var switches: Array[MeshInstance3D] = []
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.push_back(c)
		if n is MeshInstance3D and String(n.name).begins_with("Light_switch"):
			switches.append(n as MeshInstance3D)

	for sw in switches:
		var aabb := MeshUtilScript.world_aabb(sw)
		var c := aabb.get_center()
		# thin axis is the wall normal; the room is the side with air behind it
		var normal := Vector3(1, 0, 0) if aabb.size.x < aabb.size.z else Vector3(0, 0, 1)
		var facing := normal
		var q := PhysicsRayQueryParameters3D.create(c, c + normal * 0.12, 1)
		if not space.intersect_ray(q).is_empty():
			facing = -normal
		# nearest ceiling light on the room side
		var best: OmniLight3D = null
		var best_d := 1e9
		for k: String in ceiling.keys():
			var l := ceiling[k] as OmniLight3D
			if (l.global_position - c).dot(facing) <= 0.0:
				continue
			var d := l.global_position.distance_to(c)
			if d < best_d:
				best_d = d
				best = l
		if best == null:
			continue
		var group: Array[Light3D] = [best]
		for al in area_lights:
			if al.global_position.distance_to(best.global_position) < 1.6:
				group.append(al)
		var p: Node3D = SwitchPropScript.new()
		# grow the ray box: a switch plate is 2 cm thick
		var pad := Vector3(0.14, 0.12, 0.14)
		_add_prop(p, sw, PropScript.PivotMode.CENTER, pad)
		p.set("axis", Vector3(0, 0, 1) if normal.x != 0.0 else Vector3(1, 0, 0))
		p.set("prompt_open", "Light on")
		p.set("prompt_close", "Light off")
		p.set("prompt_open_ar", "شغّل الضو")
		p.set("prompt_close_ar", "طفّ الضو")
		p.set("action", _toggle_lights.bind(group))
		p.set("lights", group)
		p.call("snap_state", best.visible)


## Desk lamps: tap the lamp itself. Its own light, a nudge of the shade.
func _build_lamp_switches() -> void:
	var lamps := _lamps()
	if lamps == null or not lamps.has_method("get_light"):
		return
	var stack: Array[Node] = [_house]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.push_back(c)
		if not (n is MeshInstance3D and String(n.name).begins_with("Desk_lamp")):
			continue
		var light := lamps.call("get_light", String(n.name)) as OmniLight3D
		if light == null:
			continue
		var p: Node3D = SwitchPropScript.new()
		_add_prop(p, n as MeshInstance3D, PropScript.PivotMode.BOTTOM, Vector3(0.1, 0.05, 0.1))
		p.set("axis", Vector3(0, 0, 1))
		p.set("flick_deg", 5.0)
		p.set("flick_time", 0.16)
		p.set("prompt_open", "Lamp on")
		p.set("prompt_close", "Lamp off")
		p.set("prompt_open_ar", "شغّل اللمبة")
		p.set("prompt_close_ar", "طفّ اللمبة")
		var group: Array[Light3D] = [light]
		p.set("action", _toggle_lights.bind(group))
		p.set("lights", group)
		p.call("snap_state", light.visible)


func _toggle_lights(on: bool, lights: Array[Light3D]) -> void:
	for l in lights:
		if is_instance_valid(l):
			l.visible = on


# --- the small bathroom -------------------------------------------------------

func _build_bathroom() -> void:
	# drawers slide out toward the room (-x)
	for dn in DRAWERS:
		var mi := _mesh(dn)
		if mi == null:
			continue
		var p: Node3D = SlidingPropScript.new()
		_add_prop(p, mi, PropScript.PivotMode.CENTER, Vector3(0.06, 0.02, 0.02))
		p.set("direction", Vector3(-1, 0, 0))
		p.set("distance", 0.26)

	# mirror cabinet doors: hinged at their outer edges, open toward the room
	var cab_a := _mesh(CABINET_DOORS[0])
	if cab_a != null:
		var p: Node3D = HingedPropScript.new()
		_add_prop(p, cab_a, PropScript.PivotMode.ORIGIN, Vector3(0.12, 0.02, 0.02))
		p.set("axis", Vector3.UP)
		p.set("open_deg", 92.0)
		p.set("open_sound", "door_open")
		p.set("open_db", -18.0)
		p.set("close_sound", "")
		p.set("thunk_sound", "door_latch")
		p.set("close_db", -16.0)
	var cab_b := _mesh(CABINET_DOORS[1])
	if cab_b != null:
		var p: Node3D = HingedPropScript.new()
		_add_prop(p, cab_b, PropScript.PivotMode.ORIGIN, Vector3(0.12, 0.02, 0.02))
		p.set("axis", Vector3.UP)
		p.set("open_deg", -92.0)
		p.set("open_sound", "door_open")
		p.set("open_db", -18.0)
		p.set("close_sound", "")
		p.set("thunk_sound", "door_latch")
		p.set("close_db", -16.0)

	# toilet: the lid is authored standing up, the seat lying down, same hinge
	# line along z at the back of the bowl. For the lid "open" means lowered
	# (rotated -90 about z onto the seat), so the labels are swapped and it
	# thunks on the way down. The seat only lifts while the lid is up.
	var lid_mi := _mesh(TOILET_LID)
	var seat_mi := _mesh(TOILET_SEAT)
	var lid: Node3D = null
	if lid_mi != null:
		lid = HingedPropScript.new()
		_add_prop(lid, lid_mi, PropScript.PivotMode.ORIGIN, Vector3(0.10, 0.02, 0.02))
		lid.set("axis", Vector3(0, 0, 1))
		lid.set("open_deg", -90.0)
		lid.set("open_time", 0.6)
		lid.set("close_time", 0.7)
		lid.set("thunk_on_open", true)
		lid.set("thunk_sound", "closet_thump")
		lid.set("close_db", -20.0)
		lid.set("recoil_amount", 0.01)
		lid.set("prompt_open", "Close lid")
		lid.set("prompt_close", "Lift lid")
		lid.set("prompt_open_ar", "سكّر الغطا")
		lid.set("prompt_close_ar", "ارفع الغطا")
	if seat_mi != null:
		var seat: Node3D = HingedPropScript.new()
		_add_prop(seat, seat_mi, PropScript.PivotMode.ORIGIN, Vector3(0.02, 0.10, 0.02))
		seat.set("axis", Vector3(0, 0, 1))
		seat.set("open_deg", 90.0)
		seat.set("open_time", 0.6)
		seat.set("close_time", 0.5)
		seat.set("thunk_sound", "closet_thump")
		seat.set("close_db", -20.0)
		seat.set("recoil_amount", 0.01)
		seat.set("prompt_open", "Lift seat")
		seat.set("prompt_close", "Lower seat")
		seat.set("prompt_open_ar", "ارفع الكرسي")
		seat.set("prompt_close_ar", "نزّل الكرسي")
		if lid != null:
			seat.set("needs", lid)
			seat.set("needs_open", false)

	# tap lever on the vanity: swivel, water runs, the flag flips
	var tap_mi := _mesh(TAP)
	if tap_mi != null:
		var tap: Node3D = HingedPropScript.new()
		_add_prop(tap, tap_mi, PropScript.PivotMode.ORIGIN, Vector3(0.10, 0.10, 0.10))
		tap.set("axis", Vector3.UP)
		tap.set("open_deg", 40.0)
		tap.set("open_time", 0.25)
		tap.set("close_time", 0.25)
		tap.set("overshoot_deg", 4.0)
		tap.set("prompt_open", "Turn tap")
		tap.set("prompt_close", "Turn tap off")
		tap.set("prompt_open_ar", "افتح الحنفية")
		tap.set("prompt_close_ar", "سكّر الحنفية")
		tap.connect("toggled", _on_tap.bind(tap))

	# flush: an interact spot on the cistern, no motion, a long sound
	var toilet_mi := _mesh(TOILET)
	if toilet_mi != null:
		var aabb := MeshUtilScript.world_aabb(toilet_mi)
		var spot: Area3D = SimpleInteractableScript.create(Vector3(0.36, 0.30, 0.50), "اسحب السيفون", "Flush", false)
		spot.name = "FlushSpot"
		_house.add_child(spot)
		# cistern is the tall back part at the low-x end of the bowl
		spot.global_position = Vector3(aabb.position.x + 0.16, aabb.end.y - 0.12, aabb.get_center().z)
		spot.connect("interacted", _on_flush.bind(spot))


func _on_tap(on: bool, tap: Node3D) -> void:
	GameState.flags.tap_running = on
	if on:
		if _tap_player == null or not is_instance_valid(_tap_player):
			_tap_player = AudioBus.loop_at("water_loop", tap, tap.global_position, -16.0)
		elif not _tap_player.playing:
			_tap_player.play()
	elif _tap_player != null and is_instance_valid(_tap_player):
		var t := create_tween()
		t.tween_property(_tap_player, "volume_db", -60.0, 0.5)
		t.tween_callback(_tap_player.stop)
		t.tween_callback(func() -> void: _tap_player.volume_db = -16.0)


func _on_flush(_by: Node3D, spot: Area3D) -> void:
	spot.set("enabled", false)
	AudioBus.sfx_at("flush", spot.global_position, -8.0, 0.02)
	var t := create_tween()
	t.tween_interval(4.2)
	t.tween_callback(func() -> void: spot.set("enabled", true))
