extends Area3D

## The moment in the sewer where it stops being a walk.
##
## Player crosses the line, control locks, his heart comes up, he breathes
## like he has been running, and then the caption tells him what he already
## knows. Dad fades in at the marker behind him.
##
## Fires once. Emits `finished` so the act can carry on from here.

signal started
signal finished
## He reached the kid; the sequence resets and can run again.
signal caught

const HEARTBEAT := preload("res://assets/audio/heartbeat.wav")
const BREATH := preload("res://assets/audio/breath_heavy.wav")

@export_group("Lines")
@export var heart_caption := "you can hear your heartbeat getting louder"
@export var behind_caption := "he is behind you"
## Beat between the lock and the first line.
@export var lead_in := 0.8
## How long the heart climbs before the second line lands.
@export var dread_time := 4.5
## Held after dad appears, before control returns.
@export var hold_after := 2.5

@export_group("Dad")
## The node to reveal. Defaults to the marker sitting beside this trigger.
@export var dad_path: NodePath = NodePath("../dad point")
@export var dad_fade := 1.2
## Metres per second he closes the gap. Slow on purpose — he is not chasing,
## he is arriving.
@export var approach_speed := 0.55
## Close enough to count as caught.
@export var catch_distance := 1.2
## Where the kid comes back to. Empty means this trigger's own position, so
## being caught puts him at the top of the whole sequence again.
@export var respawn_path: NodePath
@export var caught_fade := 0.5
## Lights within this of him go out, and come back once he has moved on.
@export var dark_radius := 9.0

@export_group("Sound")
## Heartbeat starts here and climbs to the second value as the dread builds.
@export var heart_db_from := -26.0
@export var heart_db_to := -6.0
## And speeds up, because his pulse is rising.
@export var heart_pitch_from := 0.85
@export var heart_pitch_to := 1.35
@export var breath_db := -12.0

@export_group("Look at him")
## Shown for as long as dad is in view, once he has appeared.
@export var run_text := "RUN RUN RUN"
## Degrees off the centre of the screen that still counts as looking at him.
@export_range(5.0, 90.0, 1.0, "suffix:°") var look_cone := 38.0
@export var run_font_size := 64
@export var run_color := Color(0.85, 0.07, 0.07)

@export_group("Behaviour")
## Give control back afterwards. Off leaves him locked for whatever follows.
@export var release_control := true

var _fired := false
var _player: Node3D
var _heart: AudioStreamPlayer
var _breath: AudioStreamPlayer
var _dad: Node3D
var _run_label: Label
var _dad_home := Vector3.ZERO
var _resetting := false


func _ready() -> void:
	set_process(false)
	# a trigger volume is looked at by nobody; it only watches
	collision_layer = 0
	collision_mask = 0b11  # player body sits on layer 1 or 2 depending on rig
	monitoring = true
	body_entered.connect(_on_body)


func _on_body(body: Node3D) -> void:
	if _fired or not body.is_in_group("player"):
		return
	_fired = true
	_player = body
	_run()


func _run() -> void:
	started.emit()
	if _player.has_method("begin_cinematic"):
		_player.begin_cinematic()
	if "can_move" in _player:
		_player.can_move = false

	var dad := _prepare_dad()

	# heart, quiet at first
	_heart = AudioStreamPlayer.new()
	_heart.stream = HEARTBEAT
	_heart.volume_db = heart_db_from
	_heart.pitch_scale = heart_pitch_from
	add_child(_heart)
	_heart.finished.connect(_heart.play)  # loop it by hand, no import flag needed
	_heart.play()

	_breath = AudioStreamPlayer.new()
	_breath.stream = BREATH
	_breath.volume_db = breath_db
	add_child(_breath)
	_breath.finished.connect(_breath.play)

	await _wait(lead_in)
	_say(heart_caption)

	# it climbs while the caption sits there
	var climb := create_tween().set_parallel(true)
	climb.tween_property(_heart, "volume_db", heart_db_to, dread_time)
	climb.tween_property(_heart, "pitch_scale", heart_pitch_to, dread_time)
	await _wait(dread_time)

	_say(behind_caption)
	if dad != null:
		var t := create_tween()
		t.tween_method(func(v: float): _set_appear(dad, v), 0.0, 1.0, dad_fade)
		_dad = dad
		_build_run_label()
		_hand_lights_to_dad(dad)
		set_process(true)  # from here on he walks in, and looking says RUN

	await _wait(hold_after)

	if release_control:
		if "can_move" in _player:
			_player.can_move = true
		if _player.has_method("end_cinematic"):
			_player.end_cinematic()
	finished.emit()


## The light script owns the fixtures, so it is told who to be afraid of.
func _hand_lights_to_dad(dad: Node3D) -> void:
	var lights := _light_script()
	if lights != null:
		lights.set_dark_source(dad, dark_radius)
	else:
		push_warning("ScareTrigger: no LightBuzz to darken around dad.")


func _light_script() -> Node:
	var lights := _level().find_child("LightBuzz", true, false)
	return lights if (lights != null and lights.has_method("set_dark_source")) else null


## He walks in. Only across the floor plan — his height stays where it was
## placed, so he keeps hanging from the ceiling the kid is standing on.
func _close_in(dt: float) -> void:
	if _player == null or not is_instance_valid(_player) or approach_speed <= 0.0:
		return
	var here: Vector3 = _dad.global_position
	var there: Vector3 = _player.global_position
	var flat := Vector3(there.x - here.x, 0.0, there.z - here.z)
	var gap := flat.length()
	if gap <= catch_distance:
		_caught()
		return
	var step: float = minf(approach_speed * dt, gap - catch_distance)
	_dad.global_position = here + flat.normalized() * step


## He got him. Put everything back the way it was at the top of the sequence
## and let it run again, rather than ending the game.
func _caught() -> void:
	if _resetting:
		return
	_resetting = true
	set_process(false)
	caught.emit()

	if _player.has_method("begin_cinematic"):
		_player.begin_cinematic()
	if "can_move" in _player:
		_player.can_move = false

	var fade := get_node_or_null("/root/Fade")
	if fade != null and fade.has_method("fade_out"):
		await fade.fade_out(caught_fade)

	# put the kid back at the start of the bad part
	var spot := global_position
	if respawn_path != NodePath():
		var m := get_node_or_null(respawn_path) as Node3D
		if m != null:
			spot = m.global_position
	if _player.has_method("teleport_to"):
		_player.teleport_to(spot)
	else:
		_player.global_position = spot
	_player.velocity = Vector3.ZERO
	_face_away_from_dad(spot)

	_reset_scene()

	if fade != null and fade.has_method("fade_in"):
		fade.fade_in(caught_fade)
	if "can_move" in _player:
		_player.can_move = true
	if _player.has_method("end_cinematic"):
		_player.end_cinematic()

	_resetting = false
	_fired = false  # walking back in starts the whole thing over


## Turn him to look up the tunnel, away from where dad waits — coming back
## already staring at him gives the reveal away and reads as a taunt.
func _face_away_from_dad(spot: Vector3) -> void:
	var away := spot - _dad_home
	away.y = 0.0
	if away.length_squared() < 0.001:
		return
	away = away.normalized()
	# a body with rotation.y = yaw faces (-sin yaw, 0, -cos yaw); solve for
	# that equalling `away`. Only yaw is touched, so an upside-down roll
	# from the gravity flip survives.
	_player.rotation.y = atan2(-away.x, -away.z)
	if _player.has_method("sync_look_from_transform"):
		_player.sync_look_from_transform()


## Send him away for good — the chase is over. Same teardown as being caught,
## but the trigger stays spent so he does not come back.
func dismiss() -> void:
	set_process(false)
	_reset_scene()
	_fired = true


## Dad back where he was, hidden; lights returned; sounds stopped.
func _reset_scene() -> void:
	if _dad != null and is_instance_valid(_dad):
		_dad.global_position = _dad_home
		_set_appear(_dad, 0.0)
		_dad.visible = false
	_dad = null

	var lights := _light_script()
	if lights != null:
		lights.set_dark_source(null, 0.0)

	for p in [_heart, _breath]:
		if p != null and is_instance_valid(p):
			p.stop()
			p.queue_free()
	_heart = null
	_breath = null

	if _run_label != null and is_instance_valid(_run_label):
		_run_label.get_parent().queue_free()
		_run_label = null


## RUN, for as long as he is on screen. Its own layer above the doom filter
## so the text stays sharp, same as the captions.
func _build_run_label() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 97
	add_child(layer)

	_run_label = Label.new()
	_run_label.text = run_text
	_run_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_run_label.anchor_left = 0.0
	_run_label.anchor_right = 1.0
	_run_label.offset_top = 90.0
	_run_label.offset_bottom = 190.0
	_run_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_run_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_run_label.add_theme_font_size_override("font_size", run_font_size)
	_run_label.add_theme_color_override("font_color", run_color)
	_run_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_run_label.add_theme_constant_override("outline_size", 10)
	var font := load("res://assets/fonts/Amazdoomleft-epw3.ttf")
	if font != null:
		_run_label.add_theme_font_override("font", font)
	_run_label.modulate.a = 0.0
	layer.add_child(_run_label)


func _process(dt: float) -> void:
	if _dad == null or not is_instance_valid(_dad):
		return
	_close_in(dt)
	if _run_label == null:
		return
	var cam := get_viewport().get_camera_3d()
	var looking := false
	if cam != null:
		var to_dad: Vector3 = _dad.global_position - cam.global_position
		if to_dad.length_squared() > 0.001:
			var ang := rad_to_deg((-cam.global_basis.z).angle_to(to_dad.normalized()))
			looking = ang <= look_cone
	# a hard pulse rather than a steady sit, so it reads as panic
	var target := 1.0 if looking else 0.0
	_run_label.modulate.a = move_toward(_run_label.modulate.a, target, 6.0 * dt)
	if looking:
		_run_label.modulate.a *= 0.75 + 0.25 * absf(sin(Time.get_ticks_msec() * 0.012))


## Make dad visible but fully faded out, ready to be brought up.
func _prepare_dad() -> Node3D:
	var dad := get_node_or_null(dad_path) as Node3D
	if dad == null:
		push_warning("ScareTrigger: nothing at '%s' to reveal." % dad_path)
		return null
	# remembered once, so being caught can put him back at the far end
	if _dad_home == Vector3.ZERO:
		_dad_home = dad.global_position
	else:
		dad.global_position = _dad_home
	dad.visible = true
	_set_appear(dad, 0.0)
	return dad


func _set_appear(dad: Node3D, v: float) -> void:
	for m in _surfaces(dad):
		m.set_shader_parameter("appear", v)


func _surfaces(n: Node) -> Array:
	var out := []
	if n is GeometryInstance3D:
		var mat = (n as GeometryInstance3D).material_override
		if mat is ShaderMaterial:
			out.append(mat)
	for c in n.get_children():
		out.append_array(_surfaces(c))
	return out


func _say(text: String) -> void:
	var ui := _find_dialogue()
	if ui != null:
		ui.play([text])
	else:
		push_warning("ScareTrigger: no dialogue ui for '%s'" % text)


func _find_dialogue() -> Node:
	var ui := _level().find_child("dialouge ui", true, false)
	return ui if (ui != null and ui.has_method("play")) else null


## current_scene is null when the level is loaded by hand, so climb our own
## branch rather than trusting it.
func _level() -> Node:
	var scene: Node = get_tree().current_scene
	if scene != null:
		return scene
	scene = self
	while scene.get_parent() != null and scene.get_parent() != get_tree().root:
		scene = scene.get_parent()
	return scene


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
