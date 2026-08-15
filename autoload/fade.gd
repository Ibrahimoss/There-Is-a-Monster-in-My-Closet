extends CanvasLayer
## Screen fade, autoloaded as `Fade`. Layer 100 - above everything, including
## subtitles.
##
## Every scene change in the game goes through black. Starts opaque so the
## first frame of the game is black instead of a white flash while the web
## canvas initializes.

var _rect: ColorRect
var _tween: Tween


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.color = Color(0, 0, 0, 1)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)


func fade_in(duration := 0.8) -> void:
	await _to(0.0, duration)


func fade_out(duration := 0.6) -> void:
	await _to(1.0, duration)


func set_black() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_rect.color.a = 1.0


## Snap clear a couple of frames from now, once a scene change has landed,
## for scenes that bring their own opening (the eyelid intro starts black).
func clear_deferred() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if _tween and _tween.is_valid():
		_tween.kill()
	_rect.color.a = 0.0


func _to(alpha: float, duration: float) -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_rect, "color:a", alpha, duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await _tween.finished
