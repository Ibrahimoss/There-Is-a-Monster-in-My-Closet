class_name EyeOpenIntro
extends CanvasLayer

## Pure-visual eye opening at scene start. Blinks the eyelid overlay open over
## whatever the camera already sees — touches nothing else: no camera pose, no
## player freeze, no input capture. Frees itself when done.

signal finished

const OVERLAY_SHADER := preload("res://scripts/wake_up_overlay.gdshader")

@export var start_delay := 0.4
## Total feel of the effect; the blink pattern scales to it.
@export var duration := 2.6
## Player to freeze while the eyes are shut, so nobody walks blind into a
## wall. Leave empty to keep the old purely-visual behavior.
@export var player_path: NodePath = NodePath("../player")

var _mat: ShaderMaterial
var _player: Node


func _ready() -> void:
	layer = 100  # above the doom filter (90) and dialogue (95)

	_mat = ShaderMaterial.new()
	_mat.shader = OVERLAY_SHADER
	_mat.set_shader_parameter("eye_open", 0.0)
	_mat.set_shader_parameter("darkness", 1.0)
	_mat.set_shader_parameter("vignette", 1.0)

	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.material = _mat
	add_child(rect)

	var vs := get_viewport().get_visible_rect().size
	_mat.set_shader_parameter("aspect", vs.x / maxf(vs.y, 1.0))

	_player = get_node_or_null(player_path)
	if _player != null and _player.has_method("begin_cinematic"):
		_player.begin_cinematic()

	# The Fade autoload boots opaque and only the start screen fades it in.
	# Booting a level scene directly (dev, sandbox) would stay black forever
	# UNDER our own eyelids. If nobody has claimed the fade by the time the
	# intro starts, clear it fast — our own black covers the seam.
	_claim_unclaimed_fade.call_deferred()


func _claim_unclaimed_fade() -> void:
	await get_tree().create_timer(0.3).timeout
	var fade := get_node_or_null("/root/Fade")
	if fade != null and fade.has_method("fade_in") \
			and fade.get("_rect") != null and fade._rect.color.a > 0.99:
		fade.fade_in(0.3)

	var tween := create_tween()
	tween.tween_interval(start_delay)

	# One smooth open, slow off the line and easing out at the end.
	tween.tween_property(_mat, "shader_parameter/eye_open", 1.0, duration) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tween.parallel().tween_property(_mat, "shader_parameter/darkness", 0.0, duration * 0.6)
	tween.parallel().tween_property(_mat, "shader_parameter/vignette", 0.0, duration)

	tween.tween_callback(func():
		if _player != null and _player.has_method("end_cinematic"):
			_player.end_cinematic()
		finished.emit()
		queue_free())
