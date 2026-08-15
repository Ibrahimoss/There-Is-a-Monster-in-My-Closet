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

var _mat: ShaderMaterial


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

	var tween := create_tween()
	tween.tween_interval(start_delay)

	# One smooth open, slow off the line and easing out at the end.
	tween.tween_property(_mat, "shader_parameter/eye_open", 1.0, duration) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tween.parallel().tween_property(_mat, "shader_parameter/darkness", 0.0, duration * 0.6)
	tween.parallel().tween_property(_mat, "shader_parameter/vignette", 0.0, duration)

	tween.tween_callback(func():
		finished.emit()
		queue_free())
