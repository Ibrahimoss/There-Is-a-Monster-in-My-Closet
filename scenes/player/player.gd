extends CharacterBody3D
## The kid. First person, slow and short on purpose.
##
## Eye height 1.10m (kid scale), which alone makes the normal house read
## oversized. Slow walk by default, shift to run with a small stamina pool.
## No stamina bar, it shows as edge vignette (HUD.set_stamina) + breathing.
##
## Camera feel is bob + breath + landing dip + strafe roll + q/e lean, all
## small additive offsets on top of a plain capsule controller.
##
## No `class_name` on purpose, other systems find the player through the
## "player" group.

signal target_changed(target: Interactable)
signal entered_bed
signal covers_changed(under: bool)

const WALK_SPEED := 1.55
const RUN_SPEED := 3.1
const CROUCH_SPEED := 0.85
const ACCEL := 10.0
const GRAVITY := 18.0

const MOUSE_SENSITIVITY := 0.0022
const PITCH_LIMIT := deg_to_rad(85.0)

const STAND_EYE := 1.10
const CROUCH_EYE := 0.62
## Lying in bed: eye height above the body origin (which rests on the mattress).
const BED_EYE := 0.35
const EYE_LERP := 10.0

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

const FOV_BASE := 75.0
const FOV_WALK := 0.8
const FOV_RUN := 2.5

@export var can_move := true
@export var can_look := true

## Under the covers: no move/look, screen goes almost black, the scene is
## carried by audio and the light strip through the blanket gap.
var under_covers := false: set = _set_under_covers

## In bed: physics is bypassed entirely (no capsule-vs-bed-collider fights),
## the camera lies at pillow height, and Space holds the covers over you.
var in_bed := false
## While true the director is pinning the kid down - releasing Space does
## nothing until the scene lets go.
var covers_locked := false

@onready var _head: Node3D = $Head
@onready var _camera: Camera3D = $Head/Camera
@onready var _ray: RayCast3D = $Head/Camera/InteractRay

var _pitch := 0.0
var _crouching := false
var _running := false
var _stamina := STAMINA_MAX
var _exhausted := false
var _target: Interactable = null

var _time := 0.0
var _bob_phase := 0.0
var _bob_blend := 0.0
var _step_index := 0
var _run_blend := 0.0
var _lean := 0.0
var _strafe_roll := 0.0
var _land_offset := 0.0
var _eye_base := STAND_EYE
var _was_on_floor := true
var _prev_vy := 0.0


func _ready() -> void:
	add_to_group("player")


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
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		_pitch = clampf(
			_pitch - event.relative.y * MOUSE_SENSITIVITY, -PITCH_LIMIT, PITCH_LIMIT
		)
		_head.rotation.x = _pitch

	if event.is_action_pressed("ui_cancel"):
		release_mouse()

	if in_bed:
		if event.is_action_pressed("hide_under_covers"):
			under_covers = true
		elif event.is_action_released("hide_under_covers") and not covers_locked:
			under_covers = false

	if event.is_action_pressed("interact"):
		_try_interact()


func _physics_process(delta: float) -> void:
	_time += delta

	if in_bed:
		_update_bed_feel()
		_update_target()
		return

	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	var input := Vector2.ZERO
	if _moving():
		_crouching = Input.is_action_pressed("crouch")
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	else:
		_crouching = false

	_update_stamina(input, delta)

	var wish := (transform.basis * Vector3(input.x, 0.0, input.y)).normalized() \
		if input != Vector2.ZERO else Vector3.ZERO
	var speed := CROUCH_SPEED if _crouching else (RUN_SPEED if _running else WALK_SPEED)
	velocity.x = move_toward(velocity.x, wish.x * speed, ACCEL * delta)
	velocity.z = move_toward(velocity.z, wish.z * speed, ACCEL * delta)

	_prev_vy = velocity.y
	move_and_slide()

	_update_feel(input, speed, delta)
	_update_target()


func _update_stamina(input: Vector2, delta: float) -> void:
	if _exhausted and _stamina >= STAMINA_RECOVER_AT:
		_exhausted = false

	var wants_run := (
		Input.is_action_pressed("run")
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


## Composes every camera offset for this frame. All small, all additive.
func _update_feel(input: Vector2, speed: float, delta: float) -> void:
	var planar := Vector2(velocity.x, velocity.z).length()
	var ratio := clampf(planar / speed, 0.0, 1.0) if speed > 0.0 else 0.0
	var moving_ground := is_on_floor() and planar > 0.15

	# Landing dip.
	if is_on_floor() and not _was_on_floor:
		var impact := clampf(-_prev_vy / 9.0, 0.0, 1.0)
		_land_offset = -LAND_DIP * impact
		if impact > 0.15:
			AudioBus.sfx_at("land_soft", global_position, -16.0 + 9.0 * impact)
	_was_on_floor = is_on_floor()
	_land_offset = lerpf(_land_offset, 0.0, LAND_RECOVER * delta)

	# Walk↔run blend drives cadence and amplitude together.
	_run_blend = move_toward(_run_blend, 1.0 if _running else 0.0, 4.0 * delta)
	var freq := lerpf(BOB_FREQ_WALK, BOB_FREQ_RUN, _run_blend)
	var amp_y := lerpf(BOB_AMP_Y_WALK, BOB_AMP_Y_RUN, _run_blend)
	var amp_x := lerpf(BOB_AMP_X_WALK, BOB_AMP_X_RUN, _run_blend)
	var roll_amp := lerpf(BOB_ROLL_WALK, BOB_ROLL_RUN, _run_blend)

	if moving_ground:
		_bob_phase += TAU * freq * ratio * delta
	_bob_blend = move_toward(_bob_blend, 1.0 if moving_ground else 0.0, 5.0 * delta)

	# A footfall is each bottom of the bob dip: (phase*2 + PI/2) crosses a
	# multiple of TAU exactly when sin(phase*2) bottoms out.
	var step_idx := int(floorf((_bob_phase * 2.0 + PI * 0.5) / TAU))
	if step_idx != _step_index:
		_step_index = step_idx
		if _bob_blend > 0.4:
			_play_footstep()
	var bob_y := sin(_bob_phase * 2.0) * amp_y * _bob_blend
	var bob_x := sin(_bob_phase) * amp_x * _bob_blend
	var bob_roll := sin(_bob_phase) * roll_amp * _bob_blend

	# Breathing: fades out while walking, deepens and quickens as stamina
	# empties.
	var tired := 1.0 - _stamina / STAMINA_MAX
	var breath_freq := BREATH_FREQ * (1.0 + 0.7 * tired)
	var breath_amp := BREATH_AMP * (1.0 + 2.2 * tired)
	var breath := sin(_time * TAU * breath_freq * 0.5) * breath_amp * (1.0 - _bob_blend)

	# Lean.
	var lean_axis := 0.0
	if can_look and not under_covers:
		lean_axis = Input.get_axis("lean_left", "lean_right")
	_lean = lerpf(_lean, lean_axis, LEAN_SPEED * delta)

	# Strafe roll.
	_strafe_roll = lerpf(_strafe_roll, -input.x * STRAFE_ROLL, 6.0 * delta)

	# Apply.
	_eye_base = lerpf(_eye_base, CROUCH_EYE if _crouching else STAND_EYE, EYE_LERP * delta)
	_head.position.y = _eye_base + bob_y + breath + _land_offset
	_head.position.x = _lean * LEAN_OFFSET + bob_x
	_camera.rotation.z = bob_roll + -_lean * LEAN_ROLL + _strafe_roll
	var fov_target := FOV_BASE + FOV_WALK * ratio * _bob_blend + FOV_RUN * _run_blend
	_camera.fov = lerpf(_camera.fov, fov_target, 4.0 * delta)


func _moving() -> bool:
	return can_move and not under_covers


func _looking() -> bool:
	return (
		can_look
		and not under_covers
		and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	)


func _update_target() -> void:
	var found: Interactable = null
	if not under_covers and _ray.is_colliding():
		var hit := _ray.get_collider()
		if hit is Interactable and hit.can_interact():
			found = hit
	if found != _target:
		_target = found
		target_changed.emit(_target)


func _try_interact() -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if _target and _target.can_interact():
		_target.interact(self)
		# The interaction may have consumed a one-shot; refresh so the prompt
		# disappears on the same frame rather than a frame late.
		_update_target()
		# The interaction may also have changed the prompt on the SAME target
		# (a door flipping Open → Close). `_update_target` only emits on target
		# change, so re-emit unconditionally for the HUD to re-read the prompt.
		target_changed.emit(_target)


func get_target() -> Interactable:
	return _target


func get_stamina() -> float:
	return _stamina / STAMINA_MAX


func is_exhausted() -> bool:
	return _exhausted


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
## the room. `spot` is where the body origin rests on the mattress.
func enter_bed(spot: Vector3, yaw_deg: float) -> void:
	if in_bed:
		return
	in_bed = true
	can_move = false
	velocity = Vector3.ZERO
	_crouching = false
	AudioBus.sfx("cloth", -6.0)
	var target_yaw := rotation.y + wrapf(deg_to_rad(yaw_deg) - rotation.y, -PI, PI)
	var t := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(self, "global_position", spot, 1.4)
	t.parallel().tween_property(self, "rotation:y", target_yaw, 1.4)
	t.parallel().tween_property(_head, "position:y", BED_EYE, 1.4)
	t.parallel().tween_property(_head, "rotation:x", deg_to_rad(18.0), 1.4)
	t.parallel().tween_property(_camera, "rotation:z", 0.0, 1.4)
	await t.finished
	_pitch = deg_to_rad(18.0)
	_eye_base = BED_EYE
	entered_bed.emit()


func exit_bed(floor_pos: Vector3) -> void:
	if not in_bed:
		return
	in_bed = false
	under_covers = false
	_eye_base = STAND_EYE
	_head.position.y = STAND_EYE
	can_move = true
	teleport_to(floor_pos)


## Slow breathing while lying in bed.
func _update_bed_feel() -> void:
	if _eye_base != BED_EYE:
		return  # still tweening down
	_head.position.y = BED_EYE + sin(_time * TAU * 0.5) * 0.006


func _play_footstep() -> void:
	var vol := -14.0 if _crouching else -8.0
	vol += 6.0 * _run_blend
	AudioBus.sfx_at("footstep_wood", global_position, vol, 0.1)


func capture_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func release_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Used by the beam system's respawn. Teleports without carrying momentum.
func teleport_to(pos: Vector3) -> void:
	global_position = pos
	velocity = Vector3.ZERO
