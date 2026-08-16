extends Node

## Dev-only fast forward. Press ` (backtick) to cycle Engine.time_scale so
## fades, cutscenes and walking across the house stop eating your afternoon.
##
## Everything driven by delta speeds up together: tweens, SceneTreeTimers,
## physics, animation. Audio does not — samples keep playing at their own
## rate, so a sped-up cutscene sounds out of sync. That is expected.
##
## Use it either way:
##   - drop this on a Node in the scene you are working in, or
##   - Project > Project Settings > Autoload for it to follow you everywhere.
##
## Off in exported builds unless allow_in_release is ticked.

## Cycled in order, starting from the first. Keep 1.0 first so one more press
## always brings you back to normal speed.
@export var speeds: PackedFloat32Array = [1.0, 3.0, 6.0]
## Physical key. QUOTELEFT is ` on a US layout.
@export var key := KEY_QUOTELEFT
## Corner readout while fast, so you never wonder why the game feels drunk.
@export var show_indicator := true
@export var allow_in_release := false

var _index := 0
var _label: Label
var _physics_steps_default := 8


func _ready() -> void:
	# keep working while the tree is paused (menus, cutscene pauses)
	process_mode = Node.PROCESS_MODE_ALWAYS

	if not (OS.has_feature("debug") or allow_in_release):
		set_process_input(false)
		return

	_physics_steps_default = Engine.max_physics_steps_per_frame
	if show_indicator:
		_build_indicator()


func _exit_tree() -> void:
	# never leak a sped-up clock into the next scene
	Engine.time_scale = 1.0
	Engine.max_physics_steps_per_frame = _physics_steps_default


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var k := event as InputEventKey
	# check both so it works regardless of keyboard layout mapping
	if k.physical_keycode != key and k.keycode != key:
		return
	get_viewport().set_input_as_handled()
	_cycle()


func _cycle() -> void:
	if speeds.is_empty():
		return
	_index = (_index + 1) % speeds.size()
	set_speed(speeds[_index])


func set_speed(scale: float) -> void:
	Engine.time_scale = maxf(scale, 0.01)
	# Physics runs at most max_physics_steps_per_frame ticks per frame; at 6x
	# the default 8 is not enough and the world starts lagging behind the
	# clock. Give it room, proportionally.
	Engine.max_physics_steps_per_frame = maxi(
		_physics_steps_default, int(ceil(_physics_steps_default * scale)))
	_update_indicator()


func _build_indicator() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 128  # above the fade, which sits at 100
	add_child(layer)

	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_label.offset_left = -140.0
	_label.offset_top = 8.0
	_label.offset_right = -12.0
	_label.offset_bottom = 40.0
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_label.add_theme_constant_override("outline_size", 6)
	layer.add_child(_label)
	_update_indicator()


func _update_indicator() -> void:
	if _label == null:
		return
	_label.text = "" if is_equal_approx(Engine.time_scale, 1.0) \
		else "▶▶ x%s" % String.num(Engine.time_scale, 2).trim_suffix(".00")
