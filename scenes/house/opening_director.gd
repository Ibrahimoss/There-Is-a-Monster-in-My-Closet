class_name OpeningDirector
extends Node
## Runs the scripted opening: act 0 (bedtime, the toy) into act 1 (the closet,
## dad at the door, sleep). One awaited chain, every subtitle line is awaited
## so lines can't race each other's hide timers.
##
## No HUD markers anywhere. Guidance is the lit bathroom door across the dark
## landing plus one kid line.

## World anchors (see house.gd's layout docstring; derived from mesh AABBs).
const BED_SPOT := Vector3(6.42, 4.60, -12.30)
const BED_YAW := 180.0  # lying with the headboard at the window, facing the room
const BED_EXIT := Vector3(5.6, 3.85, -11.3)
const LAMP_POS := Vector3(7.1, 4.9, -13.0)
const DAD_DOOR_POS := Vector3(-2.46, 4.9, -8.71)
const KID_DOOR_POS := Vector3(5.28, 4.9, -8.88)
const CLOSET_POS := Vector3(6.68, 4.9, -9.31)
## Room centre, high - even warm fill. The door-gap glow that leads the player
## across the landing is the Door_003 spill rig's job, not this light's.
const BATHROOM_LIGHT_POS := Vector3(1.4, 5.6, -9.9)

## Toy home: floor nook between the lidded bin (Trash_can_002 at 2.36, -10.19)
## and the vanity's side. Hiding spots match real bathroom furniture.
const TOY_HOME := Vector3(2.05, 3.74, -10.05)
const SPOT_TOILET_AREA := Vector3(0.62, 4.05, -10.90)   # behind the toilet
const SPOT_TOILET_REST := Vector3(0.68, 3.74, -11.00)
const SPOT_NOOK_AREA := Vector3(2.05, 4.05, -10.05)     # the nook (home)
const SPOT_CISTERN_AREA := Vector3(0.15, 4.85, -10.77)  # on the cistern lid
const SPOT_CISTERN_REST := Vector3(0.10, 4.74, -10.77)

var house: Node3D
var doors: DoorSystem
var player: CharacterBody3D

var _toy: Toy
var _take_spot: SimpleInteractable
var _putback_spots: Array[SimpleInteractable] = []
var _bed: SimpleInteractable
var _sleep: SimpleInteractable
var _bathroom_light: OmniLight3D

var _toy_taken := false
var _putback_done := false
var _bed_requested := false
var _sleep_requested := false


func run() -> void:
	_build_props()
	await _act0()
	await _act1()


func beat(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _build_props() -> void:
	# the toy, tucked between the bin and the vanity
	_toy = Toy.new()
	_toy.name = "TheToy"
	add_child(_toy)
	_toy.global_position = TOY_HOME
	_toy.rotation.y = deg_to_rad(-90.0)

	_take_spot = SimpleInteractable.create(
		Vector3(0.7, 0.7, 0.7), "خذه", "Take him", true
	)
	add_child(_take_spot)
	_take_spot.global_position = SPOT_NOOK_AREA
	_take_spot.enabled = false
	_take_spot.interacted.connect(func(_by: Node3D) -> void: _toy_taken = true)

	# The three hiding spots, in GameState.ToySpot order:
	# [enum value, interact-area centre, where the toy's feet come to rest].
	var spot_data: Array = [
		[GameState.ToySpot.BEHIND_PANEL, SPOT_TOILET_AREA, SPOT_TOILET_REST],
		[GameState.ToySpot.UNDER_SINK, SPOT_NOOK_AREA, TOY_HOME],
		[GameState.ToySpot.IN_CISTERN, SPOT_CISTERN_AREA, SPOT_CISTERN_REST],
	]
	for entry: Array in spot_data:
		var spot_id: int = entry[0]
		var area_pos: Vector3 = entry[1]
		var rest_pos: Vector3 = entry[2]
		var spot := SimpleInteractable.create(
			Vector3(0.65, 0.6, 0.65), "خبّئه هنا", "Hide him here", false
		)
		add_child(spot)
		spot.global_position = area_pos
		spot.enabled = false
		spot.interacted.connect(_on_putback.bind(spot_id, rest_pos))
		_putback_spots.append(spot)

	_bed = SimpleInteractable.create(
		Vector3(1.8, 1.1, 2.5), "ادخل السرير", "Get in bed", true
	)
	add_child(_bed)
	_bed.global_position = Vector3(6.42, 4.55, -11.84)
	_bed.enabled = false
	_bed.interacted.connect(func(_by: Node3D) -> void: _bed_requested = true)

	# Sleep target floats over the foot of the bed so the lying view hits it
	# wherever you look (the ray can't start inside a shape, keep it ahead).
	_sleep = SimpleInteractable.create(
		Vector3(2.4, 1.8, 1.6), "غمّض عيونك", "Close your eyes", true
	)
	add_child(_sleep)
	_sleep.global_position = Vector3(6.42, 5.5, -10.7)
	_sleep.enabled = false
	_sleep.interacted.connect(func(_by: Node3D) -> void: _sleep_requested = true)

	# Bathroom light left on. Spills through the ajar door, this is the whole
	# act 0 guidance.
	_bathroom_light = OmniLight3D.new()
	_bathroom_light.light_color = Color(1.0, 0.80, 0.55)
	_bathroom_light.light_energy = 1.0
	_bathroom_light.omni_range = 3.4
	_bathroom_light.omni_attenuation = 1.5
	_bathroom_light.shadow_enabled = false
	add_child(_bathroom_light)
	_bathroom_light.global_position = BATHROOM_LIGHT_POS
	GameState.flags.bathroom_light_on = true


# --- Act 0: bedtime ----------------------------------------------------------

func _act0() -> void:
	GameState.set_act(GameState.Act.BEDTIME)
	await Fade.fade_in(1.8)
	await beat(1.2)
	await Subtitles.show_line("dad_bedtime", 3.0)
	await beat(0.5)
	await Subtitles.show_line("kid_need_toy", 3.6)
	_take_spot.enabled = true

	while not _toy_taken:
		await beat(0.1)
	await _hug()

	for spot in _putback_spots:
		spot.enabled = true
	while not _putback_done:
		await beat(0.1)
	await Subtitles.show_line("kid_goodnight_toy", 2.6)

	# Bathroom goes dark, the bedside lamp leads back to bed.
	_set_bathroom_light(false)
	_bed.enabled = true
	while not _bed_requested:
		await beat(0.1)
	# The spent bed area must not shadow the sleep target's area later.
	_bed.queue_free()
	player.enter_bed(BED_SPOT, BED_YAW)
	await player.entered_bed


func _hug() -> void:
	_take_spot.queue_free()  # its area must not shadow the put-back spot
	AudioBus.sfx("cloth", -6.0)
	var cam := player.get_node("Head/Camera") as Camera3D
	_toy.reparent(cam)
	var t := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(_toy, "position", Vector3(0.20, -0.24, -0.5), 0.7)
	t.parallel().tween_property(_toy, "rotation:y", deg_to_rad(160.0), 0.7)
	t.parallel().tween_property(_toy, "scale", Vector3.ONE * 0.75, 0.7)
	# camera bows down over him and back up
	t.parallel().tween_property(cam, "rotation:x", deg_to_rad(-7.0), 0.55)
	t.chain().tween_property(cam, "rotation:x", 0.0, 0.9)
	await Subtitles.show_line("kid_got_toy", 2.6)


func _on_putback(_by: Node3D, spot_id: int, pos: Vector3) -> void:
	if _putback_done:
		return
	_putback_done = true
	GameState.toy_location = spot_id as GameState.ToySpot
	AudioBus.sfx("cloth", -8.0)
	for spot in _putback_spots:
		spot.enabled = false
	var target := get_parent() as Node3D
	_toy.reparent(target)
	var t := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(_toy, "global_position", pos, 0.6)
	t.parallel().tween_property(_toy, "scale", Vector3.ONE, 0.6)


func _set_bathroom_light(on: bool) -> void:
	_bathroom_light.visible = on
	GameState.flags.bathroom_light_on = on
	var bathroom_door := doors.get_door("Door_003")
	if bathroom_door:
		bathroom_door.set_spill(on)
	AudioBus.sfx_at("switch", BATHROOM_LIGHT_POS, -12.0)


# --- Act 1: the closet -------------------------------------------------------

func _act1() -> void:
	GameState.set_act(GameState.Act.CLOSET)
	var closet := doors.get_door("closet_door_03")
	var kid_door := doors.get_door("Door_006")

	await beat(2.5)
	# Lights out.
	house.set_bedside_lamp(false)
	AudioBus.sfx_at("switch", LAMP_POS, -10.0)
	await beat(4.5)  # false calm; crickets only

	AudioBus.sfx_at("closet_thump", CLOSET_POS, -4.0)
	closet.shake(1.0)
	await beat(0.5)
	closet.set_ajar(4.0)
	# faint cold glow in the gap
	closet.set_spill(true)
	await beat(2.6)
	AudioBus.sfx_at("closet_thump", CLOSET_POS, 0.0)
	closet.shake(1.7)
	await beat(1.2)

	await Subtitles.show_line("kid_call", 2.2)
	await beat(1.6)
	await Subtitles.show_line("dad_answer", 2.2)
	await beat(0.4)
	await Subtitles.show_line("kid_closet", 2.8)

	HUD.show_prompt(
		"اختبئ تحت البطانية" if GameState.language == "ar" else "Hide under the covers",
		"Space"
	)
	while not player.under_covers:
		await beat(0.1)
	HUD.hide_prompt()
	player.set_covers_locked(true)
	await beat(2.0)

	# dad's visit, audio only, he's never shown
	await _dad_walk(DAD_DOOR_POS, KID_DOOR_POS, 8, 0.55)
	await beat(0.8)
	await kid_door.open(1.7)
	await Subtitles.show_line("dad_reassure", 3.8)
	# gap glow off before dad gets to it
	closet.set_spill(false)
	await _dad_walk(KID_DOOR_POS, CLOSET_POS, 4, 0.62)
	await closet.open(1.9)
	await beat(2.6)  # long pause while he checks
	await closet.close(1.3)
	await beat(0.7)
	await Subtitles.show_line("dad_quiet", 3.0)
	await _dad_walk(CLOSET_POS, KID_DOOR_POS, 4, 0.62)
	await kid_door.close(1.3)
	kid_door.set_spill(false)
	house.set_hall_light(false)
	await _dad_walk(KID_DOOR_POS, DAD_DOOR_POS, 8, 0.62)
	await beat(1.5)

	player.set_covers_locked(false)
	while player.under_covers:
		await beat(0.1)
	await beat(1.2)

	_sleep.enabled = true
	while not _sleep_requested:
		await beat(0.1)
	# glow comes back as the kid drifts off
	closet.set_spill(true)
	AudioBus.set_muffled(true, 2.5)
	GameState.set_act(GameState.Act.NIGHTMARE)
	GameState.set_checkpoint(BED_EXIT)
	await Fade.fade_out(4.5)
	AudioBus.stop_ambience(3.0)
	# Hold on black. The nightmare picks it up from here.


## Dad's footsteps: same wood steps as the kid's, pitched down, slower.
func _dad_walk(from: Vector3, to: Vector3, steps: int, pace: float) -> void:
	for i in steps:
		var t := float(i) / float(maxi(steps - 1, 1))
		AudioBus.sfx_at("footstep_wood", from.lerp(to, t), -2.0, 0.08, 0.78)
		await beat(pace * randf_range(0.92, 1.08))
