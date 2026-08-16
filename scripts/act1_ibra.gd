extends Node

## Ibrahim's act-1 room director. Attach to the "act1" node that parents the
## room's objects; it sleeps through act 0 and arms itself the moment Bedtime
## hands over (GameState -> Act.CLOSET, right after the cut to black).
##
## Same philosophy as bedtime.gd: this node orchestrates, the scene stays
## plain. Everything here resolves by name at runtime and fails soft, so the
## script runs both in real_world_ibra_mod.tscn today and in the merged
## real_world.tscn later without edits.

signal started
signal finished

## Which act wakes this room up. CLOSET is what Bedtime sets when it ends.
@export var arm_on_act := 1  # GameState.Act.CLOSET
## Skip the wait and run immediately — for testing this scene on its own.
@export var debug_arm_immediately := false
## Hide everything under act1 until the act starts (props that should not
## exist yet during bedtime). Leave off if the room dresses the whole game.
@export var hidden_until_armed := false
## Meshes anywhere in the level that should disappear for this act only.
## Hidden on arm and put back if the act is reset, so act 0 is untouched.
@export var hide_during_act: PackedStringArray = ["Glass_004"]

@export_group("Opening")
## Called out from the bed, before he gets up, after the closet noise.
@export var dad_calls: PackedStringArray = ["بابا؟", "بابا!"]
## Beat between the closet noise and the first call, and between the calls.
@export var call_gap := 1.1
## What he says once he's on his feet.
@export var monologue := "لازم ألقى سكويبل"
## Caption when a locked door is tried.
@export var locked_caption := "مو من هنا"
## When the world turns over.
@export var flip_caption := "ويش... ويش صار؟"
## When he drops into the sewer.
@export var sewer_caption := "وين أنا؟"
## Sound the closet makes, and where it comes from. Bedtime builds the closet
## on this frame, so the noise lines up with the door that rattled in act 0.
@export var closet_sound := "closet_thump"
@export var closet_mesh_name := "Door_frame_008"
## His own room door stays open (Bedtime's KID_DOOR).
@export var kid_door_name := "Door_006"

@export_group("Handover")
## Reaching this and hearing its last line ends the act.
@export var return_point_path: NodePath = NodePath("return point")
## Act to move GameState to when this one is done, so the next director can
## arm itself the same way this one did. -1 just emits `finished`.
@export var hand_over_to_act := -1

@export_group("Wake up")
## Where the body lies (Bedtime's BED_SPOT). He starts the act here.
@export var bed_spot := Vector3(7.05, 4.42, -11.85)
@export var bed_yaw_degrees := 180.0
## Floor spot beside the bed he stands up onto (Bedtime's START_POS).
@export var wake_position := Vector3(5.5, 3.74, -10.6)
@export var wake_yaw_degrees := 180.0
## Getting up is two moves, not one slide: sitting up on the spot, a beat on
## the edge of the bed, then standing and stepping off.
@export var sit_up_time := 1.1
@export var sit_pause := 0.45
@export var stand_up_time := 1.3
## Bedtime ends with the lamps out. Relight this much of the house so the
## act isn't played blind. 0 keeps it pitch dark.
@export_range(0.0, 1.0) var wake_light := 0.35

@export_group("Reversed gravity")
## The placed trigger box under this node — move it in the editor to change
## where gravity turns over. If it is missing, the doorway below is measured
## at runtime instead.
@export var flip_zone_node := "GravityFlipZone"
## Fallback doorway when there is no placed zone. Stays unlocked for obvious
## reasons — it is the way into the act.
@export var flip_door_name := "Door_004"
## How deep the trigger slab is, across the doorway.
@export var flip_zone_depth := 1.2
## Seconds for the world to turn over. Longer reads as a slow somersault,
## shorter as a lurch. Below ~0.2 it starts to look like a teleport again.
@export var flip_time := 0.9

@export_group("Sewer footing")
## Godot treats anything steeper than floor_max_angle as wall, not floor. The
## sewer is round pipe: measured surfaces reach 66 degrees, so at the 45
## degree default a third of it is unwalkable and he sticks and slides.
## Raised for the upside-down stretch, restored afterwards.
@export_range(30.0, 89.0, 1.0, "suffix:°") var curved_floor_max_angle := 72.0
## Curved ground drops away under each step; a longer snap keeps his feet on
## it instead of letting him skip along the surface.
@export var curved_floor_snap := 0.5
## The sewer pieces sit inside the house's collision volume (measured: house
## collision intrudes across the whole act1 sewer footprint, y 3.6 to 6.5).
## Down there that geometry is invisible but still solid, so it reads as
## random walls. Switch it off once he is in the sewer.
@export var mute_house_collision_in_sewer := true
@export var house_colliders_path: NodePath = NodePath("../House_Colliders")
## Override: a hand-placed trigger instead of the doorway. ZERO = use the door.
@export var flip_zone_position := Vector3.ZERO
@export var flip_zone_size := Vector3(1.6, 2.2, 1.6)

var _armed := false
var _last_locked_caption_ms := -100000
var _flipped := false
var _player: CharacterBody3D


func _ready() -> void:
	set_physics_process(false)  # only ticks while gravity is reversed
	# run ahead of the player in the frame so the look correction below lands
	# before the player consumes the frame's mouse delta
	process_priority = -100
	_player = get_tree().get_first_node_in_group("player") as CharacterBody3D

	# the placed trigger stays deaf until the act asks for it
	var placed := _placed_zone()
	if placed != null:
		placed.monitoring = false

	if hidden_until_armed:
		_set_room_visible(false)
	_dev_fade_in.call_deferred()

	if debug_arm_immediately:
		_arm.call_deferred()
		return

	var gs := get_node_or_null("/root/GameState")
	if gs != null:
		gs.act_changed.connect(func(act): if int(act) == arm_on_act and not _armed: _arm())
		# already past it? (loading straight into a later act while testing)
		if int(gs.current_act) == arm_on_act:
			_arm.call_deferred()
	else:
		# no friend-stack: running the scene bare. Arm after a beat so
		# the room is still testable.
		push_warning("act1: GameState autoload missing, arming in 2s for dev.")
		get_tree().create_timer(2.0).timeout.connect(_arm)


## Fade starts opaque and only the start screen ever fades in — booting the
## sandbox scene directly would stay black forever. If nobody has claimed the
## fade shortly after boot, claim it. A no-op in the real flow.
func _dev_fade_in() -> void:
	await wait(0.8)
	var fade := get_node_or_null("/root/Fade")
	if fade != null and fade.has_method("fade_in") \
			and fade.get("_rect") != null and fade._rect.color.a > 0.99:
		fade.fade_in(1.0)


func _arm() -> void:
	if _armed:
		return
	_armed = true
	if hidden_until_armed:
		_set_room_visible(true)
	_hide_act_props(true)
	started.emit()
	_run()


# =========================================================================
# The act itself. Write the beats here, in order, using the helpers below.
# `await` freely — this runs as its own sequence like bedtime's chain.
# =========================================================================
func _run() -> void:
	_hook_sewer_line()
	# The black beat between acts: cut out on the closet creak, settle him in
	# bed while nobody can see, cut back in with him lying there.
	var fade := get_node_or_null("/root/Fade")
	if fade != null and fade.has_method("fade_out"):
		await fade.fade_out(1.4)
	# Only now shut and lock the house. Doing it before the fade slammed the
	# closet door in shot -- act 0 ends with that door swinging open on its
	# own, and it was being snapped shut on the same frame it arrived.
	_lock_the_house()
	await wait(1.0)  # a breath of black
	_put_in_bed()
	_relight()
	if fade != null and fade.has_method("fade_in"):
		fade.fade_in(1.6)
	await wait(1.2)

	# he wakes and gets himself up
	await _rise_from_bed()
	caption(monologue)

	# gravity turns over once he's through the act room's doorway
	await _await_room_entry()
	await set_gravity_flipped(true)
	caption(flip_caption)

	# From here the act is event-driven: the hop, the thing in the tunnel, and
	# finally the return point. When that last line has been said the act is
	# over and whatever comes next can take the game.
	await _await_return()
	finish(hand_over_to_act)


# =========================================================================
# Reversed gravity. The player script hardcodes `velocity.y -= GRAVITY*dt`
# while airborne; rather than edit the shared file, this node adds
# +2*GRAVITY*dt on the same condition every physics tick, so the net pull
# is the same strength upward. up_direction makes the ceiling count as
# floor (walking, footsteps, landing all work), and a PI roll on the body
# turns the world the right way up for an upside-down kid. The roll lives
# in rotation.z, which the look code never writes, so mouse-look survives.
# =========================================================================
var _flip_lift := 0.0
var _flipping := false
var _footing_saved := false
var _saved_max_angle := 0.0
var _saved_snap := 0.0

## Turns the world over. The roll and the lift are tweened together over
## flip_time: rolling about the feet-origin alone would drop the collider
## through the floor, and applying the correction in one frame is the jolt
## that reads as a teleport. Moved together and gradually, the head simply
## swings down as the room turns over.
func set_gravity_flipped(on: bool) -> void:
	if _player == null or _flipped == on or _flipping:
		return
	_flipped = on
	_flipping = true

	var lift := _rig_height() if on else _flip_lift
	if on:
		_flip_lift = lift

	# hold him still for the turn so physics isn't fighting the tween
	if _player.has_method("begin_cinematic"):
		_player.begin_cinematic()
	_player.velocity = Vector3.ZERO
	_player.up_direction = Vector3.DOWN if on else Vector3.UP
	_set_curved_footing(on)

	var t := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(_player, "rotation:z", PI if on else 0.0, flip_time)
	t.parallel().tween_property(_player, "global_position:y",
		_player.global_position.y + (lift if on else -lift), flip_time)
	await t.finished

	if not on:
		_flip_lift = 0.0
	_flipping = false
	if _player.has_method("end_cinematic"):
		_player.end_cinematic()
	# a nudge off the surface so the new pull takes hold immediately
	_player.velocity.y = 1.0 if on else -1.0
	set_physics_process(on)


## Props this act does without — a pane of glass in the way, say. Their
## collision goes with them, so they can't block an invisible body either.
func _hide_act_props(hide: bool) -> void:
	for prop_name in hide_during_act:
		var node := obj(prop_name) as Node3D
		if node == null:
			push_warning("act1: nothing named '%s' to hide." % prop_name)
			continue
		node.visible = not hide
		for body in node.find_children("*", "CollisionObject3D", true, false):
			var co := body as CollisionObject3D
			if hide:
				if not co.has_meta("act1_prop_layer"):
					co.set_meta("act1_prop_layer", co.collision_layer)
					co.collision_layer = 0
			elif co.has_meta("act1_prop_layer"):
				co.collision_layer = co.get_meta("act1_prop_layer")
				co.remove_meta("act1_prop_layer")


## Silence the house's collision so the sewer is the only solid thing down
## there. Layers are remembered, so it can be handed back.
func set_house_collision(on: bool) -> void:
	if not mute_house_collision_in_sewer:
		return
	var house := get_node_or_null(house_colliders_path)
	if house == null:
		push_warning("act1: no house colliders at '%s'." % house_colliders_path)
		return
	for body in house.find_children("*", "StaticBody3D", true, false):
		var sb := body as StaticBody3D
		if on:
			if sb.has_meta("act1_layer"):
				sb.collision_layer = sb.get_meta("act1_layer")
				sb.remove_meta("act1_layer")
		elif not sb.has_meta("act1_layer"):
			sb.set_meta("act1_layer", sb.collision_layer)
			sb.collision_layer = 0


## Let him walk the round pipe instead of sliding off it. Remembers what the
## player was set to so the house gets its normal footing back.
func _set_curved_footing(on: bool) -> void:
	if _player == null:
		return
	if on:
		if not _footing_saved:
			_footing_saved = true
			_saved_max_angle = _player.floor_max_angle
			_saved_snap = _player.floor_snap_length
		_player.floor_max_angle = deg_to_rad(curved_floor_max_angle)
		_player.floor_snap_length = curved_floor_snap
	elif _footing_saved:
		_player.floor_max_angle = _saved_max_angle
		_player.floor_snap_length = _saved_snap
		_footing_saved = false


## Top of the player's collider above its origin, measured pre-flip.
func _rig_height() -> float:
	var best := 1.7
	for cs in _player.find_children("*", "CollisionShape3D", true, false):
		var shape: Shape3D = cs.shape
		if shape == null:
			continue
		var half := 0.0
		if shape is CapsuleShape3D:
			half = shape.height * 0.5
		elif shape is BoxShape3D:
			half = shape.size.y * 0.5
		var top: float = cs.global_position.y + half * absf(cs.global_transform.basis.get_scale().y) \
			- _player.global_position.y
		best = maxf(best, top)
	return best


func _physics_process(delta: float) -> void:
	if not _flipped or _flipping or _player == null:
		return  # never bank velocity while he is held for the turn
	if not _player.is_on_floor():
		var g: float = _player.get("GRAVITY") if "GRAVITY" in _player else 18.0
		_player.velocity.y += 2.0 * g * delta


func _process(_dt: float) -> void:
	# Upside down, only the horizontal reads backwards: yaw turns the body
	# about world up while the screen's up is world down, so the world slides
	# the wrong way. Pitch pivots on the rolled head axis and double-negates,
	# so it stays correct — measured, not assumed. Negate the frame's
	# horizontal delta before the player consumes it.
	if _flipped and _player != null and "_look_accum" in _player:
		_player._look_accum.x = -_player._look_accum.x


## The house resets shut, then every door locks except the kid's own, the one
## the act runs through, and anything living under this act1 node. Locked
## doors rattle and the kid mutters instead of opening.
func _lock_the_house() -> void:
	var bus := get_node_or_null("/root/AudioBus")
	for d in _all_doors():
		# shut without animating — this happens under the fade, and Bedtime
		# leaves his door open and the bathroom ajar
		if d.has_method("snap_open"):
			d.snap_open(false)
		# his own room, anything under act1, and the door the act runs through
		var exempt: bool = String(d.name) == kid_door_name \
			or String(d.name) == flip_door_name \
			or is_ancestor_of(d)
		d.set("locked", not exempt)
		if exempt:
			continue
		if d.get("locked_sound") == null and bus != null and bus.has_method("stream"):
			d.set("locked_sound", bus.stream("door_locked"))
		if not d.refused.is_connected(_on_locked_door_tried):
			d.refused.connect(_on_locked_door_tried)


func _on_locked_door_tried() -> void:
	# refuse-spam guard: one mutter every few seconds, the queue never stacks
	var now := Time.get_ticks_msec()
	if now - _last_locked_caption_ms < 3000:
		return
	_last_locked_caption_ms = now
	caption(locked_caption)


func _all_doors() -> Array:
	var presence := get_node_or_null("/root/Presence")
	if presence != null and presence.has_method("get_doors"):
		var regs: Array = presence.get_doors()
		if not regs.is_empty():
			return regs
	# bare-scene fallback: anything with a lock and an interact is a door
	var out: Array = []
	var level: Node = get_tree().current_scene if get_tree().current_scene else get_parent()
	for n in level.find_children("*", "MeshInstance3D", true, false):
		if n.has_method("interact") and "locked" in n:
			out.append(n)
	return out


## The thing in the closet shifts. Positional when the bus supports it, so it
## comes from the closet rather than from inside his head.
func _closet_noise() -> void:
	var bus := get_node_or_null("/root/AudioBus")
	if bus == null:
		return
	var closet := obj(closet_mesh_name) as Node3D
	if closet != null and bus.has_method("sfx_at"):
		bus.sfx_at(closet_sound, closet.global_position, -6.0, 0.05, 0.7)
	elif bus.has_method("sfx"):
		bus.sfx(closet_sound, -6.0)


## The sewer line is connected rather than sequenced, because the hop happens
## whenever he decides to take it.
func _hook_sewer_line() -> void:
	for child in get_children():
		if child.has_signal("hopped") and not child.hopped.is_connected(_on_hopped):
			child.hopped.connect(_on_hopped)


func _on_hopped() -> void:
	caption(sewer_caption)


## He starts the act lying down. After Bedtime he already is, so this only
## does anything when the act is run on its own.
func _put_in_bed() -> void:
	if _player == null:
		return
	if "in_bed" in _player and _player.in_bed:
		return
	if _player.has_method("enter_bed"):
		_player.enter_bed(bed_spot, bed_yaw_degrees)
	else:
		_player.global_position = bed_spot


## Nudge him, then wait for the interact key and play the rise.
## enter_bed's lie-down, played backwards: the eye rises from pillow height
## to standing, the head levels off, the body slides to the bedside. exit_bed
## then restores the player's own state (flags, eye base, movement).
func _rise_from_bed() -> void:
	var head: Node3D = _player.get("_head") as Node3D
	var stand := _stand_eye()
	var bed_eye: float = head.position.y if head != null else 0.35
	# somewhere between lying and standing — where your eyes are once you are
	# sat on the edge of the mattress
	var seated: float = bed_eye + (stand - bed_eye) * 0.55

	# 1. sit up. The body does not go anywhere; only the head comes up off the
	#    pillow and the chin levels out. Moving the body here is what made the
	#    whole thing read as a slide.
	if head != null:
		var sit := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		sit.tween_property(head, "position:y", seated, sit_up_time)
		sit.parallel().tween_property(head, "rotation:x", deg_to_rad(-4.0), sit_up_time)
		await sit.finished
		await wait(sit_pause)  # a moment sitting on the edge before standing

	# 2. stand and step off. Now the body travels, and it accelerates out of
	#    the sit rather than gliding at a constant rate. The turn to face the
	#    room rides along with it — setting rotation.y at the end instead is
	#    what snapped the view round on the last frame.
	var up := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	up.tween_property(_player, "global_position", wake_position, stand_up_time)
	# shortest way round, so turning from 179 to 181 degrees is a nudge and
	# not most of a circle
	var turn: float = _player.rotation.y + wrapf(
		deg_to_rad(wake_yaw_degrees) - _player.rotation.y, -PI, PI)
	up.parallel().tween_property(_player, "rotation:y", turn, stand_up_time) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if head != null:
		up.parallel().tween_property(head, "position:y", stand, stand_up_time) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		up.parallel().tween_property(head, "rotation:x", 0.0, stand_up_time)
	await up.finished

	if _player.has_method("exit_bed"):
		_player.exit_bed(wake_position)
	# the look springs still think he is facing the old way
	if _player.has_method("sync_look_from_transform"):
		_player.sync_look_from_transform()


func _stand_eye() -> float:
	var v = _player.get("STAND_EYE")
	return float(v) if v != null else 1.10


## Gravity turns over once he is through the act room's doorway. The trigger
## sits in the door's opening and is measured from the door panel itself, so
## it stays right if the door is moved in the editor.
func _await_room_entry() -> void:
	# the box placed under act1 wins, so it can be dragged in the editor
	var placed := _placed_zone()
	if placed != null:
		placed.set("_fired", false)  # in case act 0 brushed past it
		placed.monitoring = true
		await placed.triggered
		return

	var zone := _room_zone()
	if zone.is_empty():
		push_warning("act1: no '%s' node, no '%s' door, no flip_zone_position "
			% [flip_zone_node, flip_door_name] + "— gravity stays normal.")
		return
	await entered(zone["pos"], zone["size"])


## The hand-placed trigger, if there is one. Kept switched off until the act
## actually wants it so walking the room during act 0 can't burn the trigger.
func _placed_zone() -> Area3D:
	if flip_zone_node.is_empty():
		return null
	return get_node_or_null(NodePath(flip_zone_node)) as Area3D


func _room_zone() -> Dictionary:
	if flip_zone_position != Vector3.ZERO:
		return {"pos": flip_zone_position, "size": flip_zone_size}

	var d := door(flip_door_name) as VisualInstance3D
	if d == null:
		return {}

	# Measure the doorway from the door's SHUT pose: by the time he walks
	# through, the panel has swung aside and its live AABB is no longer over
	# the opening. door.gd keeps the shut transform for exactly this reason.
	var xf: Transform3D = d.global_transform
	var shut = d.get("_shut")
	if shut is Transform3D:
		xf = shut

	var local := d.get_aabb()
	var world := AABB(xf * local.position, Vector3.ZERO)
	for i in 8:
		world = world.expand(xf * local.get_endpoint(i))

	# The panel is a thin slab; fatten it into a volume he cannot stride over
	# in one frame, and keep it a touch wider than the opening.
	var size := world.size
	size.x = maxf(size.x, flip_zone_depth)
	size.y = maxf(size.y, 1.8)
	size.z = maxf(size.z, flip_zone_depth)
	return {"pos": world.get_center(), "size": size}


## Bedtime blows the lamps out on its way through; bring some back so the
## player can see the act. Dim on purpose — it's still the middle of the night.
func _relight() -> void:
	if wake_light <= 0.0:
		return
	var lamps := get_node_or_null("../LampLights")
	if lamps == null or not "lights_by_mesh" in lamps:
		return
	for key in lamps.lights_by_mesh:
		var light: Light3D = lamps.lights_by_mesh[key]
		if not is_instance_valid(light):
			continue
		if not light.visible:
			light.visible = true
			light.light_energy = maxf(light.light_energy, 0.9)
		light.light_energy *= wake_light


## Blocks until the return point has finished talking. If there is no return
## point the act simply never hands over, which is the safe way round.
func _await_return() -> void:
	var rp := get_node_or_null(return_point_path)
	if rp == null or not rp.has_signal("returned"):
		push_warning("act1: no return point at '%s'; the act will not hand over."
			% return_point_path)
		return
	await rp.returned


func finish(next_act := -1) -> void:
	await set_gravity_flipped(false)  # never hand the next act an upside-down kid
	finished.emit()
	var gs := get_node_or_null("/root/GameState")
	if gs != null and next_act >= 0:
		gs.set_act(next_act)


# =========================================================================
# Helpers — the room's vocabulary. All resolve by name, all fail soft.
# =========================================================================

## Seconds, awaitable:  await wait(1.5)
func wait(seconds: float) -> Signal:
	return get_tree().create_timer(seconds).timeout


## On-screen caption through whichever dialogue stack is alive.
func caption(text: String) -> void:
	var ui := get_node_or_null("../DialogueLayer/dialouge ui")
	if ui != null and ui.has_method("play"):
		ui.play([text])
	else:
		push_warning("act1: no dialogue ui for caption '%s'" % text)


## A node under act1 (your modified objects) or anywhere in the level.
func obj(node_name: String) -> Node:
	var mine := find_child(node_name, true, false)
	if mine != null:
		return mine
	# search from the level root; current_scene can be null when the scene
	# is loaded by hand (tests), so climb to just under /root as a fallback
	var level: Node = get_tree().current_scene
	if level == null:
		level = self
		while level.get_parent() != null and level.get_parent() != get_tree().root:
			level = level.get_parent()
	return level.find_child(node_name, true, false)


## A registered door, via Presence when present, by name otherwise.
func door(door_name: String) -> Node:
	var presence := get_node_or_null("/root/Presence")
	if presence != null and presence.has_method("get_door"):
		var d: Node = presence.get_door(door_name)
		if d != null:
			return d
	return obj(door_name)


## Kill or restore one lamp by its mesh name (LampLights registry).
func light_out(mesh_name: String, out := true) -> void:
	var lamps := get_node_or_null("../LampLights")
	if lamps == null or not "lights_by_mesh" in lamps:
		return
	var light: OmniLight3D = lamps.lights_by_mesh.get(mesh_name)
	if light != null:
		light.visible = not out


## Sound through the friend's bus if present:  sfx("door_locked", -8.0)
func sfx(sound_name: String, volume_db := 0.0) -> void:
	var bus := get_node_or_null("/root/AudioBus")
	if bus != null and bus.has_method("sfx"):
		bus.sfx(sound_name, volume_db)


## Awaitable player-walks-here:  await entered(pos, size)
## Builds a one-shot EventArea in code — nothing placed in the editor.
func entered(world_pos: Vector3, size: Vector3) -> Signal:
	var area: Area3D = preload("res://scripts/event_area.gd").new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	area.add_child(shape)
	add_child(area)
	area.global_position = world_pos
	area.triggered.connect(area.queue_free, CONNECT_DEFERRED)
	return area.triggered


func _set_room_visible(on: bool) -> void:
	for child in get_children():
		if child is Node3D:
			child.visible = on
