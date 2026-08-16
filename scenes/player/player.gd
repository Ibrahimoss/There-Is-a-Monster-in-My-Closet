extends CharacterBody3D
## The kid. First person, slow and short on purpose.
##
## Eye height 1.10m (kid scale), which alone makes the normal house read
## oversized. Slow walk by default, shift to run with a small stamina pool.
## No stamina bar, it shows as edge vignette (HUD.set_stamina) + breathing.
##
## Feel is split in two: _physics_process moves the body (input, momentum,
## wall glide, collisions), _process moves the head (smoothed look with a
## lagging follower, bob, breath, lean, springs for weight and bumps, a bit of
## noise). All camera motion is additive on the CamRig, the Head keeps eye
## height and pitch, the Camera itself is left for cutscenes to drive.
##
## No `class_name` on purpose, other systems find the player through the
## "player" group.
##
## Attaches to any CharacterBody3D. If the node has no Head, the rig
## (Head -> CamRig -> Camera -> InteractRay) is built at runtime around
## whatever Camera3D and CollisionShape3D it already has, so the level scene
## keeps its bare player node and this script owns the feel.
##
## A target is any Node with interact(by); get_prompt(), can_interact() and
## the focus/anchor hooks are optional. Interactable areas and door bodies
## (walk up to the node that has interact) both work.

signal target_changed(target: Node)
signal entered_bed
signal covers_changed(under: bool)

const WALK_SPEED := 1.55
const RUN_SPEED := 3.1
const CROUCH_SPEED := 0.85
const GRAVITY := 18.0

## Being chased: quicker on both legs and no stamina floor, because dying to
## an empty bar in a corridor is not the scare anyone came for.
const CHASE_WALK_SPEED := 2.4
const CHASE_RUN_SPEED := 3.3
const CHASE_CROUCH_SPEED := 1.6
## Running into a shut door in the chase shoulders it open instead of stopping
## dead. Below this approach speed it is just a walk into a wall.
const BARGE_MIN_SPEED := 2.2

## Capsule heights. Crouched, the collider shrinks with the eyes so a low gap
## can actually be gone under, and you stay down until there is headroom.
const CAPSULE_R := 0.24
const CAPSULE_H_STAND := 1.25
const CAPSULE_H_CROUCH := 0.78

# --- Momentum ---------------------------------------------------------------
## Rates for the exponential approach of velocity to its target. Higher is
## snappier. Reversal has its own rate.
const ACCEL := 8.5
const DECEL := 12.0
const TURN_ACCEL := 15.0
const AIR_ACCEL := 2.0
## Fraction of speed kept when pressing into a wall at an angle.
const WALL_GLIDE := 0.55
## Below this angle (from the wall plane) CharacterBody3D would stop dead
## instead of sliding. The default 15 degrees is most of "stiff walls".
const WALL_MIN_SLIDE := deg_to_rad(2.5)

const MOUSE_SENSITIVITY := 0.0025
const PITCH_LIMIT := deg_to_rad(85.0)
## Look smoothing: rate of the exponential approach. Kept high so the image
## follows the hand inside a frame or two; anything slower reads as the
## camera fighting the mouse. Fast flicks get less of it still (LOOK_SMOOTH_FAST
## kicks in past LOOK_FLICK_PX per frame) so a snap turn lands where you aimed.
const LOOK_SMOOTH := 55.0
const LOOK_SMOOTH_FAST := 90.0
const LOOK_FLICK_PX := 40.0
## Slower follower whose error drives head trail and turn roll. Kept
## small.
const LOOK_LAG_RATE := 14.0
const LOOK_LAG_MAX := deg_to_rad(2.2)
const LOOK_LAG_MIX := 0.08
const TURN_ROLL_MIX := 0.16
## Web pointer lock hands the whole unlocked travel to the first motion event
## after capture; only that first event is checked, later big deltas are real
## flicks and go through.
const LOOK_SPIKE_PX := 160.0

const STAND_EYE := 1.10
const CROUCH_EYE := 0.62
## Lying in bed: eye height above the body origin (which rests on the mattress).
const BED_EYE := 0.35

# --- Stamina ---------------------------------------------------------------
## ~5.5s of full sprint. Empty forces walking until it climbs back over the
## recovery threshold (hysteresis, so run doesn't stutter at the boundary).
const STAMINA_MAX := 100.0
const STAMINA_DRAIN := 18.0
const STAMINA_REGEN_MOVE := 15.0
const STAMINA_REGEN_IDLE := 25.0
const STAMINA_RECOVER_AT := 35.0

# --- Feel ------------------------------------------------------------------
## Step cycle. Run raises cadence, not stride length.
const BOB_FREQ_WALK := 1.95
const BOB_FREQ_RUN := 2.6
const BOB_AMP_Y_WALK := 0.011
const BOB_AMP_Y_RUN := 0.022
const BOB_AMP_X_WALK := 0.006
const BOB_AMP_X_RUN := 0.011
const BOB_ROLL_WALK := deg_to_rad(0.25)
const BOB_ROLL_RUN := deg_to_rad(0.45)

## Idle breathing. Deepens and quickens as stamina empties.
const BREATH_FREQ := 1.15
const BREATH_AMP := 0.003

## Q/E lean: peek around cover without stepping into a beam.
const LEAN_OFFSET := 0.36
const LEAN_ROLL := deg_to_rad(9.0)
const LEAN_SPEED := 6.5

const STRAFE_ROLL := deg_to_rad(1.2)

const LAND_DIP := 0.06
const LAND_RECOVER := 8.0
## Coming to a halt from a run drops the head a touch and scuffs.
const STOP_DIP := 0.010

## Head trails the body: metres of lag per m/s, on a slightly underdamped
## spring so it settles with a small overshoot when you stop.
const HEAD_LAG_PER_MPS := 0.010
const HEAD_LAG_OMEGA := 12.0
const HEAD_LAG_ZETA := 0.62

## Shoulder into a wall: a kick on a stiff spring plus a small roll.
const BUMP_MIN_SPEED := 0.7
const BUMP_KICK := 0.35
const BUMP_OMEGA := 22.0
const BUMP_ZETA := 0.55
const BUMP_ROLL := deg_to_rad(2.2)
const BUMP_COOLDOWN := 0.35

const CROUCH_OMEGA := 11.0
const CROUCH_ZETA := 0.8

## Shouldering a door open. Its own spring, slower and looser than the wall
## bump, so the camera rides the hit and drifts back rather than snapping:
## that drift is what makes it feel like the door gave way to you.
## Underdamped on purpose: the view overshoots and rings back rather than
## easing home. A kid at a dead run putting a shoulder through a door should
## cost them their footing for a moment.
const BARGE_OMEGA := 9.0
const BARGE_ZETA := 0.38
## Metres the view is thrown along the direction of the hit, and dropped.
const BARGE_PUSH := 0.34
const BARGE_DROP := 0.15
## Degrees. Pitch dips whichever way you hit it; yaw and roll only answer to
## the sideways part, so a shoulder-first hit leans and a head-on one does not.
const BARGE_PITCH := 5.6
const BARGE_YAW := 3.2
const BARGE_ROLL := 5.0

## Hand-held camera noise. Tiny, steadier when aiming at something.
const MICRO_AMP := deg_to_rad(0.16)
const MICRO_FREQ := 0.45
const MICRO_AIM_CUT := 0.6
const MICRO_TIRED_MUL := 1.8

## Fright. A hand tremble on the view, the walls closing in, and a heart that
## goes from a resting knock to a hammer as the thing gets close.
const DREAD_SHAKE := deg_to_rad(0.7)
const DREAD_FOV := 5.0
const DREAD_FOV_SEEN := 3.5
const HEART_SLOW := 1.05
const HEART_FAST := 2.6

const FOV_BASE := 75.0
const FOV_WALK := 0.8
const FOV_RUN := 2.5

## Interact press: lunge toward the target, eyes dip, FOV nudges in.
const REACH_PUSH := 0.16
const REACH_PITCH := 1.1
const REACH_FOV := -0.8

@export var can_move := true
@export var can_look := true

## Set by cutscenes (EyeOpenIntro, WakeUpSequence): no move, look or
## interact until end_cinematic().
var cinematic := false

## Under the covers: no move/look, screen goes almost black, the scene is
## carried by audio and the light strip through the blanket gap.
var under_covers := false: set = _set_under_covers

## In bed: physics is bypassed entirely (no capsule-vs-bed-collider fights),
## the camera lies at pillow height, and Space holds the covers over you.
var in_bed := false
## While true the director is pinning the kid down - releasing Space does
## nothing until the scene lets go.
var covers_locked := false

## The interact ray, public for UI that wants to peek at it.
var ray: RayCast3D

## Test hooks: headless tests feed movement through test_input instead of
## the keyboard, and read the counters.
var test_drive := false
var test_input := Vector2.ZERO
var test_run := false
var test_crouch := false
var debug_bump_count := 0
var debug_barge_count := 0
## Ticks where the planar velocity turned more than 90 degrees while input
## held steady. Should stay 0 while gliding along a wall.
var debug_dir_flips := 0
var _prev_planar_dir := Vector2.ZERO

var _head: Node3D
var _rig: Node3D
var _camera: Camera3D
var _ray: RayCast3D
var _hands: HandRig
var _capsule: CapsuleShape3D
var _capsule_node: CollisionShape3D
var _was_crouching := false
## Velocity handed to us by the world (a door swinging into us), decays.
var _external_vel := Vector3.ZERO

# look
var _look_accum := Vector2.ZERO
var _yaw := 0.0
var _yaw_target := 0.0
var _pitch := 0.0
var _pitch_target := 0.0
var _lag_yaw := 0.0
var _lag_pitch := 0.0
var _yaw_vel := 0.0
var _pitch_vel := 0.0
var _written_yaw := 0.0
var _written_pitch := 0.0
var _look_lock := false
var _step_sound := "footstep_wood"
var _step_db := 0.0
var _capture_grace := 0
var _first_motion := true
var _aim_focus := 0.0
var _noise := FastNoiseLite.new()

# body
var _chase := false
var _dread := 0.0
var _dread_seen := 0.0
var _heart := 0.0
var _crouching := false
var _running := false
var _stamina := STAMINA_MAX
var _exhausted := false
var _target: Node = null
var _planar := 0.0
var _speed_cap := WALK_SPEED
var _last_input := Vector2.ZERO
var _pre_v := Vector3.ZERO
var _wall_contact := false
var _last_bump := -10.0
var _stop_timer := 0.0
var _stop_speed := 0.0

# feel state
var _time := 0.0
var _bob_phase := 0.0
var _bob_blend := 0.0
var _step_index := 0
var _run_blend := 0.0
var _lean := 0.0
var _strafe_roll := 0.0
var _land_offset := 0.0
var _fov_kick := 0.0
var _eye_base := STAND_EYE
var _was_on_floor := true
var _prev_vy := 0.0

var _head_lag := Spring3.new(HEAD_LAG_OMEGA, HEAD_LAG_ZETA)
var _bump_pos := Spring3.new(BUMP_OMEGA, BUMP_ZETA)
var _bump_rot := Spring3.new(BUMP_OMEGA, BUMP_ZETA)
var _barge_pos := Spring3.new(BARGE_OMEGA, BARGE_ZETA)
var _barge_rot := Spring3.new(BARGE_OMEGA, BARGE_ZETA)
var _reach_pitch := Spring1.new(16.0, 0.7)
var _crouch := Spring1.new(CROUCH_OMEGA, CROUCH_ZETA)


func _ready() -> void:
	add_to_group("player")
	_build_rig()
	wall_min_slide_angle = WALL_MIN_SLIDE
	floor_snap_length = 0.25
	floor_constant_speed = true
	floor_block_on_wall = true
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 1.0
	_noise.seed = randi()
	sync_look_from_transform()
	HUD.set_active(true)
	# the level's colliders may not be in the tree yet
	_snap_to_floor.call_deferred()
	Presence.on_player_ready.call_deferred(self)


## Head -> CamRig -> Camera -> InteractRay. Reuses a Camera3D and a
## CollisionShape3D if the node already has them (the level scene's bare
## player), otherwise makes them.
func _build_rig() -> void:
	_head = get_node_or_null("Head") as Node3D
	if _head == null:
		_head = Node3D.new()
		_head.name = "Head"
		add_child(_head)
		_head.position = Vector3(0.0, STAND_EYE, 0.0)

	var cam: Camera3D = null
	for c in get_children():
		if c is Camera3D:
			cam = c
			break
	if cam == null:
		cam = _head.get_node_or_null("Camera") as Camera3D
		if cam == null:
			cam = _head.get_node_or_null("CamRig/Camera") as Camera3D
	if cam == null:
		cam = Camera3D.new()
		cam.fov = FOV_BASE
		cam.near = 0.05
		cam.far = 60.0
		_head.add_child(cam)
	cam.name = "Camera"

	_rig = _head.get_node_or_null("CamRig") as Node3D
	if _rig == null:
		_rig = Node3D.new()
		_rig.name = "CamRig"
		_head.add_child(_rig)
	if cam.get_parent() != _rig:
		cam.reparent(_rig, false)
	cam.transform = Transform3D.IDENTITY
	cam.current = true
	_camera = cam

	_ray = _camera.get_node_or_null("InteractRay") as RayCast3D
	if _ray == null:
		_ray = RayCast3D.new()
		_ray.name = "InteractRay"
		_ray.target_position = Vector3(0.0, 0.0, -2.2)
		_ray.collision_mask = 5
		_ray.collide_with_areas = true
		_ray.collide_with_bodies = true
		_ray.hit_from_inside = true
		_camera.add_child(_ray)
	ray = _ray

	_hands = _camera.get_node_or_null("Hands") as HandRig
	if _hands == null:
		_hands = HandRig.new()
		_hands.name = "Hands"
		_camera.add_child(_hands)

	# kid capsule with the origin at the feet, whatever shape the node came with
	var cs: CollisionShape3D = null
	for c in get_children():
		if c is CollisionShape3D:
			cs = c
			break
	if cs == null:
		cs = CollisionShape3D.new()
		add_child(cs)
	var capsule := cs.shape as CapsuleShape3D
	if capsule == null or not is_equal_approx(capsule.radius, CAPSULE_R) or cs.scale != Vector3.ONE:
		capsule = CapsuleShape3D.new()
		capsule.radius = CAPSULE_R
		capsule.height = CAPSULE_H_STAND
		cs.shape = capsule
		cs.transform = Transform3D(Basis.IDENTITY, Vector3(0.0, CAPSULE_H_STAND * 0.5, 0.0))
	_capsule = capsule
	_capsule_node = cs
	collision_layer = 2
	collision_mask = 1


func _snap_to_floor() -> void:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(
		global_position + Vector3(0.0, 0.5, 0.0), global_position - Vector3(0.0, 3.0, 0.0), 1)
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		global_position.y = (hit["position"] as Vector3).y + 0.01
		velocity = Vector3.ZERO


## Cutscene hooks. The camera pose is left to whoever runs the scene.
func begin_cinematic() -> void:
	cinematic = true
	velocity = Vector3.ZERO
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func end_cinematic() -> void:
	cinematic = false
	sync_look_from_transform()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func get_camera() -> Camera3D:
	return _camera


## Adopt whatever yaw/pitch the transform currently has as the look state,
## after anything else (teleport, cutscene, bed) moved the body or head.
func sync_look_from_transform() -> void:
	_yaw = rotation.y
	_yaw_target = _yaw
	_lag_yaw = _yaw
	_written_yaw = _yaw
	_pitch = _head.rotation.x if _head else 0.0
	_pitch_target = _pitch
	_lag_pitch = _pitch
	_written_pitch = _pitch
	_yaw_vel = 0.0
	_pitch_vel = 0.0


# --- input -----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	# Recapture must run BEFORE interact: on web the browser drops pointer
	# lock on Escape and only re-grants it inside a real user gesture. The
	# same click must not also fire interact, hence the early return.
	if event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			capture_mouse()
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseMotion and _looking():
		var rel: Vector2 = event.relative
		if _capture_grace > 0:
			return
		if _first_motion:
			_first_motion = false
			if rel.length() > LOOK_SPIKE_PX:
				return
		_look_accum += rel

	if event.is_action_pressed("ui_cancel"):
		release_mouse()

	if in_bed:
		if event.is_action_pressed("hide_under_covers"):
			under_covers = true
		elif event.is_action_released("hide_under_covers") and not covers_locked:
			under_covers = false

	if event.is_action_pressed("interact"):
		_try_interact()


# --- body ------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if in_bed:
		velocity = Vector3.ZERO
		_update_target()
		return

	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	var input := Vector2.ZERO
	if test_drive:
		input = test_input
		_crouching = test_crouch
	elif _moving():
		_crouching = Input.is_action_pressed("crouch")
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	else:
		_crouching = false
	# no standing up into whatever you just crawled under
	if not _crouching and _crouch.value > 0.05 and not _headroom():
		_crouching = true
	if _crouching != _was_crouching:
		_was_crouching = _crouching
		AudioBus.sfx("cloth", -16.0, 0.08)
	_last_input = input

	_crouch.target = 1.0 if _crouching else 0.0
	_crouch.step(delta)
	var cb := clampf(_crouch.value, 0.0, 1.0)
	_fit_capsule(cb)

	_update_stamina(input, delta)
	_run_blend = move_toward(_run_blend, 1.0 if _running else 0.0, 4.0 * delta)
	var run_t := smoothstep(0.0, 1.0, _run_blend)
	var walk_cap := CHASE_WALK_SPEED if _chase else WALK_SPEED
	var run_cap := CHASE_RUN_SPEED if _chase else RUN_SPEED
	var crouch_cap := CHASE_CROUCH_SPEED if _chase else CROUCH_SPEED
	_speed_cap = lerpf(lerpf(walk_cap, run_cap, run_t), crouch_cap, cb)

	var wish := (transform.basis * Vector3(input.x, 0.0, input.y)).normalized() \
		if input != Vector2.ZERO else Vector3.ZERO

	# Wall glide: pressing into a wall at an angle keeps most of the speed
	# along it instead of scrubbing it off.
	if wish != Vector3.ZERO and is_on_wall():
		var n := get_wall_normal()
		if wish.dot(n) < 0.0:
			var slid := wish - n * wish.dot(n)
			var l := slid.length()
			if l > 0.25:
				wish = slid.normalized() * lerpf(l, 1.0, WALL_GLIDE)

	var v := Vector2(velocity.x, velocity.z)
	var tv := Vector2(wish.x, wish.z) * _speed_cap
	var rate := AIR_ACCEL
	if is_on_floor():
		if tv == Vector2.ZERO:
			rate = DECEL
		elif v.length() > 0.2 and v.normalized().dot(tv.normalized()) < -0.2:
			rate = TURN_ACCEL
		else:
			rate = ACCEL
		rate *= lerpf(1.0, 0.85, run_t)
	v = v.lerp(tv, 1.0 - exp(-rate * delta))
	velocity.x = v.x
	velocity.z = v.y

	# something shoved us (a door swinging into the capsule)
	if _external_vel != Vector3.ZERO:
		velocity.x += _external_vel.x
		velocity.z += _external_vel.z
		_external_vel *= exp(-8.0 * delta)
		if _external_vel.length() < 0.02:
			_external_vel = Vector3.ZERO

	# stop dip: from a real pace to nothing inside a quarter second
	var planar_before := _planar
	_pre_v = velocity
	_prev_vy = velocity.y
	var was_on_floor := is_on_floor()
	move_and_slide()
	_planar = Vector2(velocity.x, velocity.z).length()

	# direction-flip counter for tests: a body that keeps moving should not
	# reverse on its own while the stick is held
	var pdir := Vector2(velocity.x, velocity.z)
	if _planar > 0.3 and _prev_planar_dir != Vector2.ZERO and input != Vector2.ZERO \
			and pdir.normalized().dot(_prev_planar_dir) < 0.0:
		debug_dir_flips += 1
	_prev_planar_dir = pdir.normalized() if _planar > 0.3 else Vector2.ZERO

	if _planar > 1.0:
		_stop_timer = 0.25
		_stop_speed = _planar
	elif _stop_timer > 0.0:
		_stop_timer -= delta
		if _planar < 0.3 and planar_before >= 0.3:
			var s := clampf(_stop_speed / RUN_SPEED, 0.0, 1.0)
			_land_offset -= STOP_DIP * s
			if s > 0.6:
				AudioBus.sfx_at(_step_sound, global_position, -18.0 + _step_db, 0.1, 0.9)
			_stop_timer = 0.0

	# landing
	if is_on_floor() and not was_on_floor:
		var impact := clampf(-_prev_vy / 9.0, 0.0, 1.0)
		_land_offset = -LAND_DIP * impact
		if impact > 0.15:
			AudioBus.sfx_at("land_soft", global_position, -16.0 + 9.0 * impact)
			_bump_pos.kick(Vector3(0.0, -0.12 * impact, 0.0))
			_hands.kick(Vector3(0.0, -0.4 * impact, 0.0))

	# head lag target: local planar velocity, trailing
	var local_v := Vector3(velocity.x, 0.0, velocity.z).rotated(Vector3.UP, -rotation.y)
	_head_lag.target = -local_v * HEAD_LAG_PER_MPS

	_scan_collisions()
	_update_target()


## The capsule follows the crouch: shorter and lower, feet staying put.
func _fit_capsule(cb: float) -> void:
	if _capsule == null:
		return
	var h := lerpf(CAPSULE_H_STAND, CAPSULE_H_CROUCH, cb)
	if absf(_capsule.height - h) < 0.002:
		return
	_capsule.height = h
	_capsule_node.position.y = h * 0.5


## Room to stand up here: a standing capsule at our feet meets nothing solid.
func _headroom() -> bool:
	var probe := CapsuleShape3D.new()
	probe.radius = CAPSULE_R - 0.02
	probe.height = CAPSULE_H_STAND
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = probe
	q.transform = Transform3D(Basis.IDENTITY, global_position + Vector3(0.0, CAPSULE_H_STAND * 0.5 + 0.02, 0.0))
	q.collision_mask = 1
	q.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


## Wall contact on the rising edge only, gated on approach speed and a
## cooldown, so leaning on a wall does not machine-gun bumps.
func _scan_collisions() -> void:
	var wall_now := false
	var bumped := false
	var planar_pre := Vector3(_pre_v.x, 0.0, _pre_v.z)
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var n := c.get_normal()
		if absf(n.y) > 0.5:
			continue
		var col := c.get_collider()
		# door bodies get shoved with the speed we hit them at; in the chase a
		# running shoulder throws them open instead
		if col != null and col.has_meta("door"):
			var door: Object = col.get_meta("door")
			if door != null and door.has_method("push_from"):
				var into := -planar_pre.dot(n)
				if _chase and _running and into > BARGE_MIN_SPEED and door.has_method("barge") \
						and bool(door.call("barge", self)):
					debug_barge_count += 1
					_barge_kick(n, into)
					velocity.x = _pre_v.x * 0.8
					velocity.z = _pre_v.z * 0.8
					continue
				door.call("push_from", c.get_position(), _pre_v)
		if bumped:
			continue
		wall_now = true
		var approach := -Vector3(_pre_v.x, 0.0, _pre_v.z).dot(n)
		if not _wall_contact and approach > BUMP_MIN_SPEED and _time - _last_bump > BUMP_COOLDOWN:
			_fire_bump(n, approach, c.get_position())
		bumped = true
	_wall_contact = wall_now


## Went through a door shoulder-first. Everything here is in body space, so
## the throw follows where the door actually was rather than where you were
## looking: hit it head on and the view drives forward and dips; catch it with
## a shoulder and it swings that way and leans; back into it and it just drops.
## `n` is the contact normal (out of the door, toward us), `approach` the speed
## going in.
func _barge_kick(n: Vector3, approach: float) -> void:
	var ln := n.rotated(Vector3.UP, -rotation.y)
	var into := Vector3(-ln.x, 0.0, -ln.z)
	if into.length() < 0.01:
		return
	into = into.normalized()
	var force := clampf(approach / CHASE_RUN_SPEED, 0.45, 1.15)
	# how much of the hit was sideways: 0 straight ahead or straight behind
	var side := into.x
	var head_on := absf(into.z)

	_barge_pos.kick((into * BARGE_PUSH + Vector3(0.0, -BARGE_DROP, 0.0)) * force * BARGE_OMEGA)
	_barge_rot.kick(Vector3(
		-deg_to_rad(BARGE_PITCH) * (0.55 + 0.45 * head_on),
		-deg_to_rad(BARGE_YAW) * side,
		-deg_to_rad(BARGE_ROLL) * side) * force * BARGE_OMEGA)
	_hands.kick(into * 0.3 * force)
	_fov_kick = -1.6 * force


func _fire_bump(n: Vector3, approach: float, pos: Vector3) -> void:
	_last_bump = _time
	debug_bump_count += 1
	var ln := n.rotated(Vector3.UP, -rotation.y)
	var k := BUMP_KICK * clampf(approach / RUN_SPEED, 0.3, 1.0)
	# the head keeps going into the wall for a beat, then springs back
	_bump_pos.kick(-ln * k)
	_bump_rot.kick(Vector3(0.0, 0.0, ln.x * BUMP_ROLL * 8.0))
	_hands.kick(-ln * k * 0.7)
	AudioBus.sfx_at("land_soft", pos, -22.0 + 6.0 * clampf(approach / RUN_SPEED, 0.0, 1.0), 0.12, 0.85)


## Something in the world moved us (a door swinging into the capsule).
func push(v: Vector3) -> void:
	_external_vel = Vector3(v.x, 0.0, v.z)


## A jolt from the world: thump in the closet, a slam. Rings the head springs.
func shake(intensity := 1.0) -> void:
	var dir := Vector3(randf_range(-1.0, 1.0), randf_range(-0.4, 0.4), randf_range(-1.0, 1.0)).normalized()
	_bump_pos.kick(dir * 0.05 * intensity)
	_bump_rot.kick(Vector3(randf_range(-1.0, 1.0) * 0.6, 0.0, randf_range(-1.0, 1.0)) * deg_to_rad(2.5) * intensity)
	_hands.kick(dir * 0.08 * intensity)


## Heartbeat, quickening as the thing closes. Two knocks per beat, and the
## whole body flinches with the first one.
func _drive_heart(dt: float, scared: float) -> void:
	var rate := lerpf(HEART_SLOW, HEART_FAST, scared)
	_heart += dt * rate
	if _heart < 1.0:
		return
	_heart -= 1.0
	var vol := lerpf(-26.0, -13.0, scared)
	AudioBus.sfx("heartbeat", vol, 0.05)
	_bump_pos.kick(Vector3(0.0, -0.012 * scared, 0.0))


## Small kick straight back, for switch flicks and drawer thunks nearby.
func recoil(z: float) -> void:
	_bump_pos.kick(Vector3(0.0, 0.0, z))
	_hands.kick(Vector3(0.0, 0.0, z * 0.5))


## Directed head kick, for scripted motion (a nod per brush stroke).
func nudge(rot: Vector3, pos := Vector3.ZERO) -> void:
	_bump_rot.kick(rot)
	if pos != Vector3.ZERO:
		_bump_pos.kick(pos)


func _update_stamina(input: Vector2, delta: float) -> void:
	# Chased: the pool is off entirely, so Shift always answers.
	if _chase:
		_exhausted = false
		_stamina = STAMINA_MAX
		var held := test_run if test_drive else Input.is_action_pressed("run")
		_running = held and _moving() and input != Vector2.ZERO and not _crouching
		HUD.set_stamina(1.0, false)
		return

	if _exhausted and _stamina >= STAMINA_RECOVER_AT:
		_exhausted = false

	var wants_run := (
		Input.is_action_pressed("run")
		and _moving()
		and not _crouching
		and not _exhausted
		and input != Vector2.ZERO
	)
	_running = wants_run

	var planar := Vector2(velocity.x, velocity.z).length()
	if _running and planar > WALK_SPEED * 0.6:
		_stamina -= STAMINA_DRAIN * delta
		if _stamina <= 0.0:
			_stamina = 0.0
			_exhausted = true
			_running = false
	else:
		var regen := STAMINA_REGEN_IDLE if planar < 0.2 else STAMINA_REGEN_MOVE
		_stamina = minf(_stamina + regen * delta, STAMINA_MAX)

	HUD.set_stamina(_stamina / STAMINA_MAX, _exhausted)


# --- head ------------------------------------------------------------------

func _process(delta: float) -> void:
	_time += delta
	var dt := minf(delta, 1.0 / 20.0)
	if _capture_grace > 0:
		_capture_grace -= 1
		_look_accum = Vector2.ZERO
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		# whichever path recaptures next, its first motion event is suspect
		_first_motion = true
	_update_look(dt)
	_head_lag.step(dt)
	_bump_pos.step(dt)
	_bump_rot.step(dt)
	_barge_pos.step(dt)
	_barge_rot.step(dt)
	_reach_pitch.step(dt)
	_hands.drive(_bob_phase, _bob_blend, _yaw_vel, _pitch_vel, dt)
	if in_bed:
		_update_bed_feel()
		return
	_update_feel(dt)


## Smoothed look. Raw deltas accumulate in _unhandled_input; here they move
## a target that the real yaw/pitch chase, and a slower follower trails that
## for head lag and turn roll. If something else turned the body or head
## since the last write (teleport, cutscene), that pose is adopted first.
func _update_look(dt: float) -> void:
	if not is_equal_approx(rotation.y, _written_yaw) or not is_equal_approx(_head.rotation.x, _written_pitch):
		sync_look_from_transform()

	var sens := MOUSE_SENSITIVITY * float(GameState.settings["sensitivity"])
	var y_sign := -1.0 if bool(GameState.settings["invert_y"]) else 1.0
	_yaw_target -= _look_accum.x * sens
	_pitch_target = clampf(_pitch_target - _look_accum.y * sens * y_sign, -PITCH_LIMIT, PITCH_LIMIT)
	var flick := clampf(_look_accum.length() / LOOK_FLICK_PX, 0.0, 1.0)
	_look_accum = Vector2.ZERO

	var k := 1.0 - exp(-lerpf(LOOK_SMOOTH, LOOK_SMOOTH_FAST, flick) * dt)
	var prev_yaw := _yaw
	var prev_pitch := _pitch
	_yaw += (_yaw_target - _yaw) * k
	_pitch += (_pitch_target - _pitch) * k
	var kv := 1.0 - exp(-20.0 * dt)
	_yaw_vel = lerpf(_yaw_vel, (_yaw - prev_yaw) / maxf(dt, 0.0001), kv)
	_pitch_vel = lerpf(_pitch_vel, (_pitch - prev_pitch) / maxf(dt, 0.0001), kv)

	var kl := 1.0 - exp(-LOOK_LAG_RATE * dt)
	_lag_yaw += (_yaw - _lag_yaw) * kl
	_lag_pitch += (_pitch - _lag_pitch) * kl

	# keep the unbounded yaw floats small, all three together
	if absf(_yaw) > TAU * 16.0:
		var r := TAU * 16.0 * signf(_yaw)
		_yaw -= r
		_yaw_target -= r
		_lag_yaw -= r

	if not _look_lock:
		rotation.y = _yaw
		_head.rotation.x = _pitch
	_written_yaw = rotation.y
	_written_pitch = _head.rotation.x


## Composes every camera offset for this frame onto the CamRig. All small,
## all additive.
func _update_feel(dt: float) -> void:
	var speed := _speed_cap
	var ratio := clampf(_planar / speed, 0.0, 1.0) if speed > 0.0 else 0.0
	var moving_ground := is_on_floor() and _planar > 0.15

	_land_offset = lerpf(_land_offset, 0.0, LAND_RECOVER * dt)

	# Walk<->run blend drives cadence and amplitude together; crouch and slow
	# speeds shrink the step.
	var cb := clampf(_crouch.value, 0.0, 1.0)
	var freq := lerpf(BOB_FREQ_WALK, BOB_FREQ_RUN, _run_blend) * lerpf(1.0, 0.85, cb)
	var amp_scale := lerpf(0.55, 1.0, ratio) * lerpf(1.0, 0.7, cb)
	var amp_y := lerpf(BOB_AMP_Y_WALK, BOB_AMP_Y_RUN, _run_blend) * amp_scale
	var amp_x := lerpf(BOB_AMP_X_WALK, BOB_AMP_X_RUN, _run_blend) * amp_scale
	var roll_amp := lerpf(BOB_ROLL_WALK, BOB_ROLL_RUN, _run_blend) * amp_scale

	if moving_ground:
		_bob_phase += TAU * freq * ratio * dt
	_bob_blend = move_toward(_bob_blend, 1.0 if moving_ground else 0.0, 5.0 * dt)

	# A footfall is each bottom of the bob dip: (phase*2 + PI/2) crosses a
	# multiple of TAU exactly when sin(phase*2) bottoms out.
	var step_idx := int(floorf((_bob_phase * 2.0 + PI * 0.5) / TAU))
	if step_idx != _step_index:
		_step_index = step_idx
		if _bob_blend > 0.4:
			_play_footstep(ratio)
	var bob_y := sin(_bob_phase * 2.0) * amp_y * _bob_blend
	var bob_x := sin(_bob_phase) * amp_x * _bob_blend
	var bob_roll := sin(_bob_phase) * roll_amp * _bob_blend

	# Breathing: fades out while walking, deepens and quickens as stamina
	# empties.
	# Fright rides on top of exhaustion: the breath goes fast and shallow, and
	# it does not fade out while running the way the tired breath does.
	var tired := 1.0 - _stamina / STAMINA_MAX
	var scared := smoothstep(0.05, 1.0, _dread)
	var breath_freq := BREATH_FREQ * (1.0 + 0.7 * tired + 1.5 * scared)
	var breath_amp := BREATH_AMP * (1.0 + 2.2 * tired + 5.0 * scared)
	if _chase:
		breath_freq *= 1.5
		breath_amp *= 1.6
	var breath := sin(_time * TAU * breath_freq * 0.5) * breath_amp \
		* (1.0 - _bob_blend * (1.0 - scared))

	# Lean.
	var lean_axis := 0.0
	if can_look and not under_covers and not cinematic:
		lean_axis = Input.get_axis("lean_left", "lean_right")
	_lean = lerpf(_lean, lean_axis, LEAN_SPEED * dt)

	# Strafe roll.
	_strafe_roll = lerpf(_strafe_roll, -_last_input.x * STRAFE_ROLL, 6.0 * dt)

	# Look lag and turn roll from the follower's error.
	var lag_y := clampf(_lag_yaw - _yaw, -LOOK_LAG_MAX, LOOK_LAG_MAX)
	var lag_p := clampf(_lag_pitch - _pitch, -LOOK_LAG_MAX, LOOK_LAG_MAX)

	# Micro-motion. Steadier while something is under the reticle.
	_aim_focus = move_toward(_aim_focus, 1.0 if _target != null else 0.0, 3.0 * dt)
	var t := _time * MICRO_FREQ
	var mm := MICRO_AMP * (1.0 - MICRO_AIM_CUT * _aim_focus) * (1.0 + MICRO_TIRED_MUL * tired)
	var micro := Vector3(
		_noise.get_noise_2d(t, 0.0),
		_noise.get_noise_2d(t, 37.0),
		_noise.get_noise_2d(t, 91.0) * 0.6) * mm
	# a fast tremble on top, from the hands rather than the head, so it reads
	# as the kid shaking and not as the camera drifting
	if scared > 0.001:
		var ft := _time * 9.0
		var jitter := DREAD_SHAKE * scared * (1.0 + _dread_seen)
		micro += Vector3(
			_noise.get_noise_2d(ft, 300.0),
			_noise.get_noise_2d(ft, 411.0),
			_noise.get_noise_2d(ft, 527.0)) * jitter
		_drive_heart(dt, scared)

	# Apply.
	_eye_base = STAND_EYE + (CROUCH_EYE - STAND_EYE) * _crouch.value
	if not _look_lock:
		_head.position = Vector3(_lean * LEAN_OFFSET, _eye_base, 0.0)
	_rig.position = Vector3(bob_x, bob_y + breath + _land_offset, 0.0) \
		+ _head_lag.value + _bump_pos.value + _barge_pos.value
	_rig.rotation = Vector3(
		lag_p * LOOK_LAG_MIX + micro.x + _reach_pitch.value + _bump_rot.value.x + _barge_rot.value.x,
		lag_y * LOOK_LAG_MIX + micro.y + _barge_rot.value.y,
		bob_roll - _lean * LEAN_ROLL + _strafe_roll - lag_y * TURN_ROLL_MIX + micro.z
			+ _bump_rot.value.z + _barge_rot.value.z)
	_fov_kick = lerpf(_fov_kick, 0.0, 6.0 * dt)
	var fov_run := FOV_RUN + (1.5 if _chase else 0.0)
	# the walls come in as it gets close: tunnel vision, and it lurches when
	# you actually look at the thing
	var fov_fear := -DREAD_FOV * scared - DREAD_FOV_SEEN * _dread_seen
	var fov_target := FOV_BASE + FOV_WALK * ratio * _bob_blend + fov_run * _run_blend \
		+ _fov_kick + fov_fear
	_camera.fov = lerpf(_camera.fov, fov_target, 4.0 * dt)


func _moving() -> bool:
	return can_move and not under_covers and not cinematic


func _looking() -> bool:
	return (
		can_look
		and not under_covers
		and not cinematic
		and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	)


# --- interaction -----------------------------------------------------------

func _update_target() -> void:
	var found: Node = null
	if not under_covers and not cinematic and _ray.is_colliding():
		found = _resolve_target(_ray.get_collider())
	if found != _target:
		if _target != null and is_instance_valid(_target) and _target.has_method("set_focused"):
			_target.call("set_focused", false)
		_target = found
		if _target != null and _target.has_method("set_focused"):
			_target.call("set_focused", true)
		target_changed.emit(_target)
		_refresh_prompt()


## The ray hit something. Interactable areas answer for themselves; anything
## else is walked up to the first ancestor with interact() (a door body under
## its Door, a prop's collider under the prop).
func _resolve_target(hit: Object) -> Node:
	if hit is Interactable:
		return hit if (hit as Interactable).can_interact() else null
	var n := hit as Node
	while n != null and not n.has_method("interact"):
		n = n.get_parent()
	if n == null:
		return null
	if n.has_method("can_interact") and not bool(n.call("can_interact")):
		return null
	return n


func _refresh_prompt() -> void:
	HUD.set_world_target(_target)


func _try_interact() -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or cinematic:
		return
	if _target == null:
		return
	if _target.has_method("can_interact") and not bool(_target.call("can_interact")):
		return
	_reach_toward(_target)
	_target.call("interact", self)
	# The interaction may have consumed a one-shot; refresh so the prompt
	# disappears on the same frame rather than a frame late.
	_update_target()
	# The interaction may also have changed the prompt on the SAME target
	# (a door flipping Open to Close). `_update_target` only emits on target
	# change, so re-read unconditionally.
	target_changed.emit(_target)
	_refresh_prompt()


## Interact press: small head lunge toward the target, eye dip, FOV nudge.
func _reach_toward(t: Node) -> void:
	var anchor: Vector3 = t.call("get_prompt_anchor") if t.has_method("get_prompt_anchor") \
		else (t as Node3D).global_position if t is Node3D else _camera.global_position
	var to := anchor - _camera.global_position
	if to.length() < 0.05:
		return
	var local := to.normalized().rotated(Vector3.UP, -rotation.y)
	_bump_pos.kick(local * REACH_PUSH)
	_reach_pitch.kick(-deg_to_rad(REACH_PITCH) * 40.0)
	_fov_kick = REACH_FOV


func get_target() -> Node:
	return _target


## Held-object system: take a node into the hand (camera space rest pose),
## give it back to whoever wants it.
func hold(n: Node3D, pos: Vector3, yaw_deg: float, scale_to: float, settle := 0.7, tilt_deg := 0.0) -> void:
	_hands.hold(n, pos, yaw_deg, scale_to, settle, tilt_deg)


func release() -> Node3D:
	return _hands.release()


func is_holding() -> bool:
	return _hands.is_holding()


func get_hands() -> HandRig:
	return _hands


func get_stamina() -> float:
	return _stamina / STAMINA_MAX


func is_exhausted() -> bool:
	return _exhausted


# --- covers / bed ----------------------------------------------------------

func _set_under_covers(value: bool) -> void:
	if under_covers == value:
		return
	under_covers = value
	if value:
		velocity = Vector3.ZERO
	AudioBus.sfx("cloth", -8.0)
	AudioBus.set_muffled(value)
	HUD.tween_covers(1.0 if value else 0.0)
	covers_changed.emit(value)


## The director pins the kid under the covers for the dad beat. Unlocking
## releases immediately if the player has already let go of the key.
func set_covers_locked(value: bool) -> void:
	covers_locked = value
	if not value and under_covers and not Input.is_action_pressed("hide_under_covers"):
		under_covers = false


## Lie down: physics off, camera tweens to pillow height, body turns to face
## the room. `spot` is where the body origin rests on the mattress. `secs` 0
## poses it instantly — the ending cuts to black somewhere else entirely and
## fades up here, and a tween there is the player watching themselves slide
## across the house.
func enter_bed(spot: Vector3, yaw_deg: float, secs := 1.4) -> void:
	if in_bed:
		return
	in_bed = true
	can_move = false
	velocity = Vector3.ZERO
	_crouching = false
	_look_lock = true
	AudioBus.sfx("cloth", -6.0)
	var target_yaw := rotation.y + wrapf(deg_to_rad(yaw_deg) - rotation.y, -PI, PI)
	if secs > 0.0:
		var t := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		t.tween_property(self, "global_position", spot, secs)
		t.parallel().tween_property(self, "rotation:y", target_yaw, secs)
		t.parallel().tween_property(_head, "position:y", BED_EYE, secs)
		t.parallel().tween_property(_head, "position:x", 0.0, secs)
		t.parallel().tween_property(_head, "rotation:x", deg_to_rad(18.0), secs)
		t.parallel().tween_property(_rig, "rotation", Vector3.ZERO, secs)
		t.parallel().tween_property(_rig, "position", Vector3.ZERO, secs)
		await t.finished
	else:
		global_position = spot
		rotation.y = target_yaw
		_head.position = Vector3(0.0, BED_EYE, 0.0)
		_head.rotation = Vector3(deg_to_rad(18.0), 0.0, 0.0)
		_rig.transform = Transform3D.IDENTITY
	_eye_base = BED_EYE
	_head_lag.reset()
	_bump_pos.reset()
	_bump_rot.reset()
	_barge_pos.reset()
	_barge_rot.reset()
	_look_lock = false
	sync_look_from_transform()
	entered_bed.emit()


func exit_bed(floor_pos: Vector3) -> void:
	if not in_bed:
		return
	in_bed = false
	under_covers = false
	_eye_base = STAND_EYE
	_head.position = Vector3(0.0, STAND_EYE, 0.0)
	_head.rotation.x = 0.0
	can_move = true
	_look_lock = false
	teleport_to(floor_pos)


## Slow breathing while lying in bed.
func _update_bed_feel() -> void:
	if _eye_base != BED_EYE:
		return  # still tweening down
	_rig.position = Vector3(0.0, sin(_time * TAU * 0.5) * 0.006, 0.0) + _bump_pos.value
	_rig.rotation = _bump_rot.value


func _play_footstep(ratio: float) -> void:
	var vol := -14.0 if _crouching else -8.0
	vol += 6.0 * _run_blend + 4.0 * ratio - 4.0
	if _chase:
		vol += 2.0
	AudioBus.sfx_at(_step_sound, global_position, vol + _step_db, 0.1)


## What the floor sounds like. Boards by default; the dream rooms are not made
## of boards. Pass an empty key to go back to the default.
func set_step_sound(key: String, db_offset := 0.0) -> void:
	_step_sound = "footstep_wood" if key.is_empty() else key
	_step_db = db_offset


## Pin the head where it is so a cutscene can pose it. While this is on,
## `_update_look` leaves rotation.y, the head pitch and the eye height alone;
## whatever you write stays written. Turning it off resyncs, so the mouse picks
## up from wherever the camera ended.
func look_lock(on: bool) -> void:
	_look_lock = on
	if not on:
		# A cutscene may have posed the head off the rig's one axis - the dream's
		# fall rolls and yaws it the whole way down. Mouse look only ever writes
		# pitch, so anything left in the other two stays written for the rest of
		# the game, which reads as a camera stuck at a tilt. Normalise on the way
		# out and take the pitch as where the scene left off.
		if _head != null:
			_head.rotation = Vector3(_head.rotation.x, 0.0, 0.0)
		sync_look_from_transform()


func capture_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_capture_grace = 2
	_look_accum = Vector2.ZERO


func release_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## How frightened the kid is, 0..1, and how much of that is from having the
## thing actually in view. The director feeds this every frame; it drives the
## shakes, the FOV and the heartbeat.
func set_dread(amount: float, seen := 0.0) -> void:
	_dread = clampf(amount, 0.0, 1.0)
	_dread_seen = clampf(seen, 0.0, 1.0)


## Chase mode: faster on both legs, no stamina, harder breathing. The director
## turns it on when the closet opens and off in the bathroom at the end.
func set_chase(on: bool) -> void:
	_chase = on
	if on:
		_stamina = STAMINA_MAX
		_exhausted = false
		HUD.set_stamina(1.0, false)


func is_chased() -> bool:
	return _chase


## The seam warp: the whole body slides by a constant offset into the copy of
## the corridor it is already standing in. Momentum, springs and look all
## carry over untouched, which is the point - the player must not feel it.
func shift_by(offset: Vector3) -> void:
	global_position += offset


## Used by scripted respawns and tools. Teleports without carrying momentum
## and adopts the pose as the look state.
func teleport_to(pos: Vector3) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	# a respawn should not arrive still leaning from the door you just hit
	_barge_pos.reset()
	_barge_rot.reset()
	sync_look_from_transform()
