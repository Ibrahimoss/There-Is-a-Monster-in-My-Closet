extends CharacterBody3D

const SPEED := 4.0
const SPRINT := 6.4
const JUMP_VELOCITY := 4.5
const MOUSE_SENS := 0.0025
const INTERACT_RANGE := 3.0

const FOOTSTEP_DIR := "res://assets/footsteps"
## Meters of travel between steps; sprinting shortens the gap by moving faster.
const STRIDE := 1.9
const FOOTSTEP_DB := -18.0

@onready var cam: Camera3D = $Camera3D
var ray: RayCast3D

var _steps: Array[AudioStream] = []
var _step_player: AudioStreamPlayer
var _stride_left := STRIDE
var _last_step := -1

# set by WakeUpSequence (or any other cutscene) while the camera isn't ours
var cinematic := false


func _ready() -> void:
	_ensure_actions()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	_step_player = AudioStreamPlayer.new()
	_step_player.volume_db = FOOTSTEP_DB
	add_child(_step_player)
	for f in DirAccess.get_files_at(FOOTSTEP_DIR):
		# in exported builds resources appear as .remap entries
		f = f.trim_suffix(".remap")
		if f.get_extension() == "wav":
			_steps.append(load(FOOTSTEP_DIR + "/" + f))

	ray = RayCast3D.new()
	ray.target_position = Vector3(0, 0, -INTERACT_RANGE)
	# Areas are walk-in triggers (dialogue zones), not clickables — letting the
	# ray see them makes an invisible zone eat clicks meant for what's behind it.
	ray.collide_with_areas = false
	cam.add_child(ray)


func begin_cinematic() -> void:
	cinematic = true
	velocity = Vector3.ZERO
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func end_cinematic() -> void:
	cinematic = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if cinematic:
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENS)
		cam.rotate_x(-event.relative.y * MOUSE_SENS)
		cam.rotation.x = clampf(cam.rotation.x, -1.4, 1.4)

	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return

	if event.is_action_pressed("interact"):
		# clicking while the cursor is free just re-captures it
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and event is InputEventMouseButton:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			return
		_try_interact()


func _physics_process(delta: float) -> void:
	# frozen solid during a cutscene — no gravity either, or the body would sink
	# out from under the camera pose the sequence is driving
	if cinematic:
		velocity = Vector3.ZERO
		return

	if not is_on_floor():
		velocity += get_gravity() * delta

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var speed := SPRINT if Input.is_action_pressed("sprint") else SPEED
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	if direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed)
		velocity.z = move_toward(velocity.z, 0.0, speed)

	move_and_slide()
	_update_footsteps(delta)


func _update_footsteps(delta: float) -> void:
	if _steps.is_empty():
		return
	var ground_speed := Vector2(velocity.x, velocity.z).length()
	if not is_on_floor() or ground_speed < 0.5:
		_stride_left = STRIDE * 0.4  # next step comes quickly when you set off
		return
	_stride_left -= ground_speed * delta
	if _stride_left > 0.0:
		return
	_stride_left = STRIDE

	# random step, never the same one twice in a row
	var i := randi() % _steps.size()
	if i == _last_step:
		i = (i + 1) % _steps.size()
	_last_step = i
	_step_player.stream = _steps[i]
	_step_player.pitch_scale = randf_range(0.94, 1.06)
	_step_player.play()


func _try_interact() -> void:
	ray.force_raycast_update()
	if not ray.is_colliding():
		print("nothing in range")
		return

	# collision shapes are usually nested under the real object, so walk up
	var target: Node = ray.get_collider()
	while target != null and not target.has_method("interact"):
		target = target.get_parent()

	if target != null:
		target.interact(self)
	else:
		print("hit ", ray.get_collider().name, " — not interactable")


# --- registers the input actions at runtime so you don't have to touch Project Settings ---
func _ensure_actions() -> void:
	_bind("move_forward", [KEY_W])
	_bind("move_back",    [KEY_S])
	_bind("move_left",    [KEY_A])
	_bind("move_right",   [KEY_D])
	_bind("jump",         [KEY_SPACE])
	_bind("sprint",       [KEY_SHIFT])
	_bind("interact",     [KEY_R], [MOUSE_BUTTON_LEFT])


func _bind(action: String, keys: Array, buttons: Array = []) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(action, e)
	for b in buttons:
		var e := InputEventMouseButton.new()
		e.button_index = b
		InputMap.action_add_event(action, e)
