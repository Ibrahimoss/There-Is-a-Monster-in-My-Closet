extends Node
## Act 0, bedtime: the objective chain from dad's line to lights out. Built at
## runtime by Presence (never placed in the level scene) as "Bedtime" under
## the level root. Guidance is light and sound first, a caption only as a late
## backup:
##   TEETH  you wake in your own room, the door dad left open; the house is
##          dark except the bathroom next door, whose door hangs ajar with the
##          light spilling into the hall; the tap drips; the toothbrush on the
##          near sink is the interact
##   BED    back to the one lit doorway; the bed is the interact
##   LYING  dad shuts the door and the light, the closet door rattles, the
##          exchange, the kid puts the lamps out (or they die), the closet
##          creaks open in the dark, cut to black
## Names below are the level's mesh names.

signal state_changed(state: int)
signal finished

## By path: this script is preloaded by an autoload, before class names exist.
const PropScript := preload("res://scripts/prop.gd")
const SimpleInteractableScript := preload("res://scripts/simple_interactable.gd")
const MeshUtilScript := preload("res://scripts/mesh_util.gd")

enum State { TEETH, BED, LYING, DONE }

## After the closet beat: fade out and back to the start screen. Off now that
## the dream picks up from `finished` / GameState.Act.CLOSET.
const CUT_TO_MENU := false

## The kid's room: on the floor by the bed, facing the door.
const START_POS := Vector3(5.5, 3.74, -10.6)
const START_YAW := 180.0

const TOOTHBRUSH := "Toothbrush_02"
const SINK := "Washbasin_07"
const BATH_DOOR := "Door_005"
const KID_DOOR := "Door_006"
const KID_BED := "bed_02"
const CLOSET_FRAME := "Door_frame_008"
## The closet frame has no panel in the model; one is cloned from this door
## and its frame gives the hinge offset.
const CLOSET_DOOR_FROM := "Door_006"
const CLOSET_DOOR_FROM_FRAME := "Door_frame_007"
const KID_SWITCH := "Light_switch_011"
const KID_CEILING := "Focus_02_007"
const KID_LAMPS: Array[String] = ["Desk_lamp_003", "Desk_lamp_004"]
## Lights on at bedtime, by mesh (or light node) name -> energy multiplier.
## Everything else in the house is off.
const LIGHT_LEVELS := {
	"Focus_02_012": 2.2,
	"Focus_02_007": 0.9,
	"Desk_lamp_003": 0.8,
	"Desk_lamp_004": 0.8,
}
## Ceiling lights whose glow should reach out of the door.
const LIGHT_REACH := {"Focus_02_012": 6.5}
## Fraction of the swing the bathroom door hangs open at.
const BATH_AJAR := 0.24
## Top step of the stairs, blocked until the kid is in bed.
const STAIR_BLOCK_POS := Vector3(4.55, 4.75, -5.3)
const STAIR_BLOCK_SIZE := Vector3(0.16, 2.1, 0.95)
const STAIR_LINE_RANGE := 1.1

## Where the body lies (head at the headboard end) and which way it faces.
const BED_SPOT := Vector3(7.05, 4.42, -11.85)
const BED_YAW := 180.0
## Camera-space rest pose of the held brush: the head at the mouth, just
## under the frame, the handle rising out to the right hand.
var hand_pos := Vector3(0.10, -0.105, -0.15)
var hand_tilt := 10.0
var hand_roll := 90.0
const BRUSH_TIME := 4.2
const BRUSH_HZ := 4.5
## Flat, no falloff (see _on_brush). Four seconds of bristles against the lens
## is the one sound in the game with nowhere to hide, so it sits well under the
## drip and the room tone.
const BRUSH_DB := -36.0
const DRIP_MIN := 1.4
const DRIP_MAX := 3.2
const HINT_AFTER := 32.0
const STAIR_LINE_COOLDOWN := 22.0
const REFUSE_COOLDOWN := 7.0
## Seconds the kid gets to put the lamps out before they go by themselves.
const LAMP_GRACE := 22.0

const LINE_BED := "okay... bed"
const LINE_NOT_YET := "not yet. teeth first"
const LINE_HINT_TEETH := "teeth. the bathroom's right next door"
const LINE_HINT_BED := "my room's the one with the light on"
const LINE_STAIRS := "Dad: bed's upstairs. go on"
const LINE_NIGHT := "Dad: night, champ"
const LINE_NO_WAY := "no... I'm not opening it"
const LINE_LAMP := "...lamp off. sleep"
const LINES_CLOSET: Array[String] = [
	"Dad!",
	"Dad: yes?",
	"there's something in the closet",
	"Dad: there's nothing in there. go to sleep",
	"Dad: and I don't want to hear a sound",
]

var state := State.TEETH

var _root: Node
var _house: Node
var _player: CharacterBody3D
var _lamps: Node
var _ui: Node
var _brush_mesh: MeshInstance3D
var _brush_home := Transform3D.IDENTITY
var _brush_glow: Array[StandardMaterial3D] = []
var _bed_glow: Array[StandardMaterial3D] = []
var _brush_area: Area3D
var _bed_area: Area3D
var _stair_block: StaticBody3D
var _drip_timer: Timer
var _drip_pos := Vector3.ZERO
var _closet_pos := Vector3.ZERO
var _closet_door: MeshInstance3D
var _kid_lamp_lights: Array[Light3D] = []

var _brushing := false
var _brush_t := 0.0
var _brush_stroke := 0
var _brush_loop: AudioStreamPlayer3D
var _idle := 0.0
var _hinted := false
var _stair_line_at := -100.0
var _refused_at := -100.0
var _time := 0.0


func setup(root: Node, house: Node, player: CharacterBody3D) -> void:
	_root = root
	_house = house
	_player = player
	_lamps = root.get_node_or_null("LampLights")
	_ui = root.get_node_or_null("DialogueLayer/dialouge ui")
	AudioBus.prewarm(["drip", "toothbrush"])
	_place_player()
	_set_lights()
	_set_doors()
	_build_closet_door()
	_build_stair_block()
	_build_toothbrush()
	_build_bed()
	_start_drip()
	_set_state(State.TEETH)


func _mesh(mesh_name: String) -> MeshInstance3D:
	if _house == null:
		return null
	return _house.find_child(mesh_name, true, false) as MeshInstance3D


func _say(lines: Array) -> void:
	if _ui != null and _ui.has_method("play"):
		_ui.call("play", lines)


func _set_state(s: State) -> void:
	state = s
	_idle = 0.0
	_hinted = false
	state_changed.emit(s)


## The scene wakes the kid wherever it likes; act 0 starts in the kid's room.
func _place_player() -> void:
	_player.teleport_to(START_POS)
	_player.rotation.y = deg_to_rad(START_YAW)
	_player.sync_look_from_transform()


# --- lights -------------------------------------------------------------------

## Bedtime: the house is dark except the bathroom next door (bright, the
## goal) and the kid's own room.
func _set_lights() -> void:
	if _lamps == null:
		return
	var by_mesh: Dictionary = _lamps.get("lights_by_mesh")
	for k: String in by_mesh.keys():
		var l := by_mesh[k] as Light3D
		if l == null:
			continue
		_level_light(l, k)
		if KID_LAMPS.has(k):
			_kid_lamp_lights.append(l)
	for c in _root.get_children():
		if c is Light3D:
			_level_light(c as Light3D, String(c.name))
	# switch plates read the new state
	for p in Presence.get_props():
		if p.has_method("sync_from_lights"):
			p.call("sync_from_lights")


func _level_light(l: Light3D, key: String) -> void:
	l.visible = LIGHT_LEVELS.has(key)
	if l.visible:
		l.light_energy *= float(LIGHT_LEVELS[key])
	if LIGHT_REACH.has(key) and l is OmniLight3D:
		(l as OmniLight3D).omni_range = float(LIGHT_REACH[key])


func _flicker(lights: Array[Light3D], end_on: bool, pulses := 3) -> void:
	for i in pulses:
		for l in lights:
			l.visible = false
		await get_tree().create_timer(randf_range(0.04, 0.09)).timeout
		for l in lights:
			l.visible = true
		await get_tree().create_timer(randf_range(0.05, 0.14)).timeout
	for l in lights:
		l.visible = end_on


func _lamps_off() -> bool:
	for l in _kid_lamp_lights:
		if is_instance_valid(l) and l.visible:
			return false
	return true


# --- doors ----------------------------------------------------------------------

## Dad left the kid's door open behind him; the bathroom door hangs ajar
## with the light behind it.
func _set_doors() -> void:
	var kid := Presence.get_door(KID_DOOR)
	if kid != null:
		kid.set("_dir", kid.call("swing_away_from", Vector3(5.28, 4.5, -9.6)))
		kid.call("snap_open", true)
	var bath := Presence.get_door(BATH_DOOR)
	if bath != null:
		bath.set("_dir", bath.call("swing_away_from", Vector3(5.4, 4.5, -6.19)))
		bath.call("_apply", BATH_AJAR)


## A panel for the closet frame, cloned from the kid's door: locked, says
## "Open", and refuses with the kid's line.
func _build_closet_door() -> void:
	var tmpl := Presence.get_door(CLOSET_DOOR_FROM)
	var d := make_closet_panel(_house, tmpl)
	if d == null:
		return
	_closet_pos = closet_room_point(_house)
	_house.add_child(d)
	d.connect("refused", _on_closet_refused)
	Presence.get_doors().append(d)
	_closet_door = d


## The closet panel, built but not yet in the tree: the kid's door duplicated
## (script and all) and hung shut in the closet frame. `tmpl` must have run
## _ready so its shut pose is known. Also used by the start screen, so the
## menu shows the same door the game does.
static func make_closet_panel(house: Node, tmpl: MeshInstance3D) -> MeshInstance3D:
	if house == null or tmpl == null:
		return null
	var frame := house.find_child(CLOSET_FRAME, true, false) as MeshInstance3D
	if frame == null:
		return null
	var fc := MeshUtilScript.world_aabb(frame).get_center()
	var offset := Vector3(0.458, 0.011, 0.007)
	var tf := house.find_child(CLOSET_DOOR_FROM_FRAME, true, false) as MeshInstance3D
	if tf != null:
		var shut_origin: Vector3 = (tmpl.get("_shut") as Transform3D).origin
		offset = shut_origin - MeshUtilScript.world_aabb(tf).get_center()
	# the template may already be swung open: build from its shut pose
	var shut: Transform3D = tmpl.get("_shut")
	var d := tmpl.duplicate(Node.DUPLICATE_SCRIPTS) as MeshInstance3D
	d.name = "closet door"
	d.transform = Transform3D(shut.basis, fc + offset)
	d.set("locked", true)
	d.set("locked_prompt", "Open")
	d.set("ajar_angle", 0.0)
	d.set("closed_offset", 0.0)
	d.set("swing_time", 3.6)
	d.set("locked_sound", AudioBus.stream("door_locked"))
	return d


## A point just inside the closet; swinging the panel away from it opens it
## into the room.
static func closet_room_point(house: Node) -> Vector3:
	var frame := house.find_child(CLOSET_FRAME, true, false) as MeshInstance3D
	if frame == null:
		return Vector3.ZERO
	return MeshUtilScript.world_aabb(frame).get_center() + Vector3(0.2, -0.4, 0.5)


func _on_closet_refused() -> void:
	if _time - _refused_at < REFUSE_COOLDOWN:
		return
	_refused_at = _time
	_say([LINE_NO_WAY])


## Closet knock: thump, panel rattle, camera shake, lamp flicker.
func _closet_knock(intensity: float) -> void:
	AudioBus.sfx_at("closet_thump", _closet_pos, -8.0 + 6.0 * intensity, 0.05, 0.75)
	if _closet_door != null:
		_closet_door.call("jiggle", 1.8 * intensity)
		AudioBus.sfx_at("door_locked", _closet_door.call("get_prompt_anchor"), -16.0 + 4.0 * intensity, 0.08, 0.9)
	_player.shake(0.7 * intensity)
	var lit: Array[Light3D] = []
	for l in _kid_lamp_lights:
		if is_instance_valid(l) and l.visible:
			lit.append(l)
	_flicker(lit, true, 1 if intensity < 1.2 else 2)


# --- stairs -----------------------------------------------------------------------

func _build_stair_block() -> void:
	_stair_block = StaticBody3D.new()
	_stair_block.name = "StairBlock"
	_stair_block.collision_layer = 1
	_stair_block.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = STAIR_BLOCK_SIZE
	cs.shape = box
	_stair_block.add_child(cs)
	_root.add_child(_stair_block)
	_stair_block.global_position = STAIR_BLOCK_POS


func _drop_stair_block() -> void:
	if _stair_block != null and is_instance_valid(_stair_block):
		_stair_block.queue_free()
		_stair_block = null


# --- teeth ----------------------------------------------------------------------

func _build_toothbrush() -> void:
	_brush_mesh = _mesh(TOOTHBRUSH)
	if _brush_mesh == null:
		return
	_brush_home = _brush_mesh.global_transform
	_brush_glow = MeshUtilScript.make_glow_overrides(_brush_mesh, PropScript.GLOW_COLOR)
	var b := MeshUtilScript.world_aabb(_brush_mesh)
	var c := b.get_center()
	_brush_area = SimpleInteractableScript.create(Vector3(0.5, 0.34, 0.5), "نظّف أسنانك", "Brush teeth", true)
	_brush_area.name = "BrushSpot"
	_house.add_child(_brush_area)
	_brush_area.global_position = c + Vector3(0.0, 0.10, 0.0)
	_brush_area.set("prompt_anchor_offset", _brush_area.to_local(c + Vector3(0, 0.05, 0)))
	_brush_area.connect("focus_changed", _glow.bind(_brush_glow))
	_brush_area.connect("interacted", _on_brush)
	var sink := _mesh(SINK)
	_drip_pos = MeshUtilScript.world_aabb(sink).get_center() + Vector3(0.0, 0.3, 0.0) if sink != null else c


func _glow(on: bool, mats: Array[StandardMaterial3D]) -> void:
	var t := create_tween().set_parallel(true)
	for m in mats:
		t.tween_property(m, "emission_energy_multiplier", PropScript.GLOW_ENERGY if on else 0.0, 0.25 if on else 0.35)


func _start_drip() -> void:
	_drip_timer = Timer.new()
	_drip_timer.one_shot = true
	_drip_timer.timeout.connect(_drip)
	add_child(_drip_timer)
	_drip_timer.start(2.5)


func _drip() -> void:
	if state != State.TEETH:
		return
	AudioBus.sfx_at("drip", _drip_pos, -19.0, 0.10)
	_drip_timer.start(randf_range(DRIP_MIN, DRIP_MAX))


func _on_brush(_by: Node3D) -> void:
	if state != State.TEETH or _brushing or _brush_mesh == null:
		return
	_brushing = true
	_brush_t = 0.0
	_brush_stroke = 0
	_player.can_move = false
	var s := _brush_home.basis.get_scale().x
	_player.hold(_brush_mesh, hand_pos, 0.0, s, 0.4, hand_tilt)
	var hands: Node3D = _player.get_hands()
	hands.set("rest_rot", Vector3(0.0, 0.0, deg_to_rad(hand_roll)))
	_brush_loop = AudioBus.loop_at("toothbrush", _player.get_camera(), _player.get_camera().global_position, -60.0)
	if _brush_loop != null:
		# It rides on the camera, so it sits exactly on the listener and takes the
		# full inverse-distance boost on top of whatever it is mixed at - which is
		# how a -27 dB loop came out louder than anything else in the game. It is
		# in the kid's own mouth: no distance, no falloff, and quiet.
		_brush_loop.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
		_brush_loop.max_db = 0.0
		var t := create_tween()
		t.tween_property(_brush_loop, "volume_db", BRUSH_DB, 0.6)


func _drive_brush(dt: float) -> void:
	_brush_t += dt
	var hands: Node3D = _player.get_hands()
	var ramp := smoothstep(0.0, 0.5, _brush_t) * (1.0 - smoothstep(BRUSH_TIME - 0.6, BRUSH_TIME, _brush_t))
	var ph := _brush_t * TAU * BRUSH_HZ
	# strokes across the mouth, a little lift on each turn, the handle rocking
	hands.set("rest_pos", hand_pos + Vector3(sin(ph) * 0.022, absf(cos(ph)) * 0.006, sin(ph) * 0.004) * ramp)
	hands.set("rest_rot", Vector3(0.0, 0.0, deg_to_rad(hand_roll) + sin(ph) * deg_to_rad(7.0) * ramp))
	# small head nudge per stroke
	var stroke := int(floorf(_brush_t * BRUSH_HZ * 2.0))
	if stroke != _brush_stroke:
		_brush_stroke = stroke
		var side := 1.0 if stroke % 2 == 0 else -1.0
		_player.nudge(Vector3(0.0, side * 0.10, side * 0.06) * ramp)
	if _brush_t >= BRUSH_TIME:
		_end_brush()


func _end_brush() -> void:
	_brushing = false
	var hands: Node3D = _player.get_hands()
	hands.set("rest_pos", hand_pos)
	hands.set("rest_rot", Vector3.ZERO)
	var n: Node3D = _player.release()
	if n != null:
		n.reparent(_house, true)
		var t := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		t.tween_property(n, "global_transform", _brush_home, 0.7)
	if _brush_loop != null and is_instance_valid(_brush_loop):
		var f := create_tween()
		f.tween_property(_brush_loop, "volume_db", -60.0, 0.4)
		f.tween_callback(_brush_loop.queue_free)
	_player.can_move = true
	GameState.flags["teeth_brushed"] = true
	_set_state(State.BED)
	_say([LINE_BED])
	await get_tree().create_timer(1.6).timeout
	# the way back is the one lit doorway; make sure it is open
	var kid := Presence.get_door(KID_DOOR)
	if kid != null and not bool(kid.get("is_open")):
		kid.set("_dir", kid.call("swing_away_from", Vector3(5.28, 4.5, -9.6)))
		kid.call("set_open", true)


# --- bed ----------------------------------------------------------------------------

func _build_bed() -> void:
	var bed := _mesh(KID_BED)
	if bed == null:
		return
	var b := MeshUtilScript.world_aabb(bed)
	_bed_glow = MeshUtilScript.make_glow_overrides(bed, PropScript.GLOW_COLOR)
	_bed_area = SimpleInteractableScript.create(Vector3(b.size.x - 0.2, 0.7, b.size.z - 0.2), "نام", "Go to bed", false)
	_bed_area.name = "BedSpot"
	_house.add_child(_bed_area)
	_bed_area.global_position = Vector3(b.get_center().x, b.end.y - 0.3, b.get_center().z)
	_bed_area.set("prompt_anchor_offset", _bed_area.to_local(Vector3(BED_SPOT.x - 0.3, b.end.y - 0.05, BED_SPOT.z)))
	_bed_area.connect("focus_changed", _glow.bind(_bed_glow))
	_bed_area.connect("interacted", _on_bed)


func _on_bed(_by: Node3D) -> void:
	if state == State.LYING or state == State.DONE:
		return
	if state == State.TEETH:
		# dad said teeth first; the bed stays available for later
		_say([LINE_NOT_YET])
		return
	_bed_area.set("enabled", false)
	if _brush_area != null:
		_brush_area.set("enabled", false)
	_set_state(State.LYING)
	_drop_stair_block()
	_player.enter_bed(BED_SPOT, BED_YAW)
	await _player.entered_bed
	_closet_beat()


func _closet_beat() -> void:
	await get_tree().create_timer(2.0).timeout
	# dad at the door: shuts it, kills the ceiling light
	var kid := Presence.get_door(KID_DOOR)
	if kid != null and bool(kid.get("is_open")):
		kid.call("set_open", false)
	await get_tree().create_timer(1.5).timeout
	var sw := Presence.get_prop(KID_SWITCH)
	if sw != null and sw.has_method("flick"):
		sw.call("flick", false)
	if _lamps != null:
		var ceiling := _lamps.call("get_light", KID_CEILING) as Light3D
		if ceiling != null:
			ceiling.visible = false
	await get_tree().create_timer(0.7).timeout
	_say([LINE_NIGHT])
	await get_tree().create_timer(5.5).timeout

	# the closet
	_closet_knock(1.0)
	await get_tree().create_timer(1.2).timeout
	_say(Array(LINES_CLOSET))
	if _ui != null and _ui.has_signal("event_finished"):
		await _ui.event_finished
	await get_tree().create_timer(1.5).timeout

	# lamps out: the kid's move, with a nudge, then they go by themselves
	var waited := 0.0
	var nudged := false
	while not _lamps_off() and waited < LAMP_GRACE:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
		if not nudged and waited >= 6.0:
			nudged = true
			_say([LINE_LAMP])
	if not _lamps_off():
		await _flicker(_kid_lamp_lights, false, 4)
		AudioBus.sfx_at("switch", _kid_lamp_lights[0].global_position if not _kid_lamp_lights.is_empty() else BED_SPOT, -14.0, 0.03, 0.8)
	await get_tree().create_timer(2.4).timeout

	_closet_knock(1.4)
	await get_tree().create_timer(0.4).timeout
	_closet_knock(1.1)
	await get_tree().create_timer(1.8).timeout
	# then it opens on its own
	if _closet_door != null:
		_closet_door.set("locked", false)
		_closet_door.set("_dir", _closet_door.call("swing_away_from", _closet_pos))
		_closet_door.call("set_open", true)
	await get_tree().create_timer(3.4).timeout
	AudioBus.sfx_at("closet_thump", BED_SPOT + Vector3(-1.2, -0.3, 0.6), -6.0, 0.05, 0.6)
	_player.shake(0.8)
	await get_tree().create_timer(1.6).timeout

	_set_state(State.DONE)
	GameState.set_act(GameState.Act.CLOSET)
	finished.emit()
	if CUT_TO_MENU:
		await Fade.fade_out(1.8)
		await get_tree().create_timer(1.2).timeout
		HUD.set_active(false)
		get_tree().change_scene_to_file("res://scenes/ui/StartScreen.tscn")


# --- per frame -------------------------------------------------------------------------

func _process(delta: float) -> void:
	_time += delta
	if _brushing:
		_drive_brush(minf(delta, 1.0 / 20.0))
	if _player == null or _player.cinematic:
		return
	if state == State.TEETH or state == State.BED:
		_idle += delta
		if not _hinted and _idle > HINT_AFTER:
			_hinted = true
			_say([LINE_HINT_TEETH if state == State.TEETH else LINE_HINT_BED])
		if _stair_block != null and _time - _stair_line_at > STAIR_LINE_COOLDOWN:
			var d := _player.global_position.distance_to(Vector3(STAIR_BLOCK_POS.x, _player.global_position.y, STAIR_BLOCK_POS.z))
			if d < STAIR_LINE_RANGE:
				_stair_line_at = _time
				_say([LINE_STAIRS])
