class_name WakeUpSequence
extends CanvasLayer

## Cinematic "waking up in bed" opener.
##
## Drives the player's Camera3D from a lying-on-the-pillow pose up to its normal
## standing pose while eyelids blink open over a black screen. The player is
## frozen for the duration and control is handed back when it finishes.

signal finished

const OVERLAY_SHADER := preload("res://scripts/wake_up_overlay.gdshader")

@export_group("Wiring")
@export var player_path: NodePath = NodePath("../CharacterBody3D")
## Leave empty to use the first Camera3D found under the player.
@export var camera_path: NodePath
## Optional Node3D placed exactly where the head lies. Overrides the offsets below.
@export var bed_marker_path: NodePath

@export_group("Pose")
## Head-on-pillow position, relative to the standing eye position, in player space.
## -Y drops you to mattress height, +Z pushes you back into the bed.
@export var bed_offset := Vector3(0.0, -1.0, 0.7)
## Degrees. Positive looks up at the ceiling.
@export_range(-90.0, 90.0) var lie_pitch := 66.0
## Degrees. Head turned to one side on the pillow.
@export_range(-90.0, 90.0) var lie_yaw := -14.0
## Degrees. Head rolled onto its side.
@export_range(-60.0, 60.0) var lie_roll := 15.0

@export_group("Timing")
@export var start_delay := 0.6
## Pause between the eyes being fully open and pushing yourself upright.
@export var sit_up_delay := 0.35
@export var sit_up_time := 2.4
@export var auto_start := true
@export var skippable := true
## Off when something else already owns the player (a director mid-sequence);
## the sequence still hands control back through end_cinematic when it ends.
@export var auto_freeze := true

@export_group("Feel")
## Tunnel vision while still on the pillow; eases back to the camera's own FOV.
@export var groggy_fov := 66.0
@export var breath_amount := 0.014
## Faint vignette left in place once the sequence is over. 0 disables it.
@export_range(0.0, 1.0) var resting_vignette := 0.10

@export_group("Audio (optional)")
@export var breath_sound: AudioStream
@export var sheets_sound: AudioStream
@export var ambience: AudioStream

var _player: Node3D
var _cam: Camera3D
var _rect: ColorRect
var _mat: ShaderMaterial
var _stand := Transform3D.IDENTITY
var _lie := Transform3D.IDENTITY
var _stand_fov := 75.0
var _pose := 0.0  # 0 = head on pillow, 1 = standing
var _time := 0.0
var _elapsed := 0.0
var _running := false
var _tween: Tween


func _ready() -> void:
	layer = 100
	_build_overlay()

	_player = get_node_or_null(player_path) as Node3D
	if _player == null:
		push_warning("WakeUpSequence: no player at '%s' — sequence disabled." % player_path)
		set_process(false)
		return

	_cam = _resolve_camera()
	if _cam == null:
		push_warning("WakeUpSequence: no Camera3D found under the player — sequence disabled.")
		set_process(false)
		return

	_stand = _cam.transform
	_stand_fov = _cam.fov
	_lie = _compute_lie_pose()

	if auto_freeze and _player.has_method("begin_cinematic"):
		_player.begin_cinematic()

	_apply_pose(0.0)
	if auto_start:
		play()


func play() -> void:
	if _running:
		return
	_running = true
	_elapsed = 0.0
	_pose = 0.0
	_set_param("eye_open", 0.0)
	_set_param("darkness", 1.0)
	_set_param("vignette", 1.0)

	if ambience != null:
		_spawn_sound(ambience, -12.0)

	_tween = create_tween()
	_tween.tween_interval(start_delay)

	# First crack of light — barely open, still mostly dark.
	_tween.tween_callback(_play_breath)
	_tween.tween_property(_mat, "shader_parameter/eye_open", 0.16, 0.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.parallel().tween_property(_mat, "shader_parameter/darkness", 0.45, 0.5)

	_tween.tween_interval(0.15)
	_tween.tween_property(_mat, "shader_parameter/eye_open", 0.02, 0.3) \
		.set_trans(Tween.TRANS_SINE)
	_tween.tween_interval(0.35)

	# Second, longer look at the room before the lids get heavy again.
	_tween.tween_property(_mat, "shader_parameter/eye_open", 0.55, 0.55) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.parallel().tween_property(_mat, "shader_parameter/darkness", 0.18, 0.55)

	_tween.tween_interval(0.25)
	_tween.tween_property(_mat, "shader_parameter/eye_open", 0.24, 0.4) \
		.set_trans(Tween.TRANS_SINE)

	# Fully awake.
	_tween.tween_property(_mat, "shader_parameter/eye_open", 1.0, 1.1) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.parallel().tween_property(_mat, "shader_parameter/darkness", 0.0, 1.1)
	_tween.parallel().tween_property(_mat, "shader_parameter/vignette", 0.4, 1.4)

	_tween.tween_interval(sit_up_delay)

	# Push yourself upright and out of bed.
	_tween.tween_callback(_play_sheets)
	_tween.tween_property(self, "_pose", 1.0, sit_up_time) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_tween.parallel().tween_property(_mat, "shader_parameter/vignette", resting_vignette, sit_up_time)

	_tween.tween_callback(_finish)


func skip() -> void:
	if not _running:
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_finish()


func _process(delta: float) -> void:
	_time += delta
	if _running:
		_elapsed += delta

	var vs := get_viewport().get_visible_rect().size
	_set_param("aspect", vs.x / maxf(vs.y, 1.0))

	if _running:
		_apply_pose(_pose)


func _unhandled_input(event: InputEvent) -> void:
	if not (_running and skippable):
		return
	if _elapsed < 0.4:  # swallow a keypress left over from the menu
		return
	var pressed := false
	if event is InputEventKey:
		pressed = event.pressed and not event.echo
	elif event is InputEventMouseButton:
		pressed = event.pressed
	if pressed:
		get_viewport().set_input_as_handled()
		skip()


# --- pose ---------------------------------------------------------------

func _apply_pose(p: float) -> void:
	_cam.transform = _lie.interpolate_with(_stand, p)
	_cam.fov = lerpf(groggy_fov, _stand_fov, p)

	# Breathing and a slow groggy drift, both strongest while still lying down.
	var w := 1.0 - p
	_cam.position.y += sin(_time * 1.9) * breath_amount * (0.35 + 0.65 * w)
	_cam.rotate_object_local(Vector3.FORWARD, sin(_time * 0.8) * deg_to_rad(1.6) * w)
	_cam.rotate_object_local(Vector3.RIGHT, sin(_time * 0.53 + 1.1) * deg_to_rad(1.1) * w)


func _compute_lie_pose() -> Transform3D:
	if bed_marker_path != NodePath():
		var marker := get_node_or_null(bed_marker_path) as Node3D
		if marker != null:
			# Marker is authored in world space; the camera lives in player space.
			return _player.global_transform.affine_inverse() * marker.global_transform

	var basis := Basis.from_euler(Vector3(
		deg_to_rad(lie_pitch), deg_to_rad(lie_yaw), deg_to_rad(lie_roll)))
	return Transform3D(basis, _stand.origin + bed_offset)


func _resolve_camera() -> Camera3D:
	if camera_path != NodePath():
		var c := get_node_or_null(camera_path) as Camera3D
		if c != null:
			return c
	for child in _player.get_children():
		if child is Camera3D:
			return child
	return null


func _finish() -> void:
	if not _running:
		return
	_running = false
	_pose = 1.0
	_cam.transform = _stand
	_cam.fov = _stand_fov
	_set_param("eye_open", 1.0)
	_set_param("darkness", 0.0)
	_set_param("vignette", resting_vignette)
	_rect.visible = resting_vignette > 0.0

	if _player.has_method("end_cinematic"):
		_player.end_cinematic()
	finished.emit()


# --- plumbing -----------------------------------------------------------

func _build_overlay() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = OVERLAY_SHADER
	_mat.set_shader_parameter("eye_open", 0.0)
	_mat.set_shader_parameter("darkness", 1.0)
	_mat.set_shader_parameter("vignette", 1.0)

	_rect = ColorRect.new()
	_rect.name = "EyelidOverlay"
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.color = Color.WHITE  # the shader supplies the actual color
	_rect.material = _mat
	add_child(_rect)


func _set_param(name: String, value: Variant) -> void:
	if _mat != null:
		_mat.set_shader_parameter(name, value)


func _play_breath() -> void:
	if breath_sound != null:
		_spawn_sound(breath_sound, -6.0)


func _play_sheets() -> void:
	if sheets_sound != null:
		_spawn_sound(sheets_sound, -4.0)


func _spawn_sound(stream: AudioStream, db: float) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = db
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)
