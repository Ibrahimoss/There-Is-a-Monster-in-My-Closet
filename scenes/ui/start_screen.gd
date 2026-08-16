extends Control
## Title screen + web gesture gate.
##
## Uses the level scene itself as the backdrop (player / story nodes stripped),
## camera in the kid's bed looking at the closet. Menu = dad's caption line and
## the kid's replies as buttons; hovering a reply moves something in the room
## (closet swing, lamp). Options and credits are drawn inside the open closet.
## "ok." swings the closet open, dollies the camera in, then loads the level.
##
## Web needs a click before pointer lock / audio, so the first reply click is
## also the audio unlock.

const UiKit := preload("res://scripts/ui_kit.gd")
const DoomFilterScript := preload("res://scripts/doom_filter.gd")
const BedtimeScript := preload("res://scripts/bedtime.gd")
const MeshUtilScript := preload("res://scripts/mesh_util.gd")
const DOOM_FONT := preload("res://assets/fonts/Amazdoomleft-epw3.ttf")

const GAME_SCENE := "res://real_world.tscn"
## Level nodes removed before the menu shows the scene: player (would pull in
## Presence + Act 0), story UI + intro, the level's own filter (menu has its
## own), colliders.
const STRIP: Array[String] = [
	"player", "DialogueLayer", "EyeOpenIntro", "DoomFilter",
	"DoorFirstOpenDialogue", "start dialouge", "House_Colliders",
]

enum Mode { MENU, OPTIONS, CREDITS, LEAVING }

## Camera: sitting up in bed, turned to the closet. Vars (not consts) so
## MenuShot can override them via env.
var eye := Vector3(6.40, 5.35, -11.95)
var eye_yaw := 207.0
var eye_pitch := 1.0
var fov := 51.0
## Dolly target on "ok.": just inside the closet doorway, facing in.
const DOLLY_END := Vector3(6.68, 4.98, -9.62)
const DOLLY_YAW := 180.0
## Breathing + mouse parallax, kept small.
const BREATH_AMP := 0.006
const BREATH_HZ := 0.5
const PARALLAX_YAW := 1.4
const PARALLAX_PITCH := 0.9
const PARALLAX_EASE := 3.5

## Lights on, by mesh (or light node) name -> energy multiplier; everything
## else off. Only the bedside lamps at bedtime.
const LIGHT_LEVELS := {"Desk_lamp_004": 0.5, "Desk_lamp_003": 0.35}
const KID_LAMPS: Array[String] = ["Desk_lamp_004", "Desk_lamp_003"]
const KID_DOOR := "Door_006"
const CLOSET_FRAME := "Door_frame_008"
## Black unshaded quad behind the closet frame: the gap shows pure black and
## the options/credits text sits on it.
const VOID_DEPTH := 0.32
const VOID_SIZE := Vector2(1.5, 2.9)

## Idle events, rare and quiet.
const CREAK_FIRST := 9.0
const CREAK_AGAIN_MIN := 34.0
const CREAK_AGAIN_MAX := 52.0
## From this camera the gap is hidden by the panel until ~25 deg, so the idle
## steps are fairly big.
const CREAK_STEPS: Array[float] = [0.08, 0.16, 0.24]
const FLICKER_MIN := 13.0
const FLICKER_MAX := 27.0
## Closet swing on hover / for the options page.
const SWING_HOVER := 0.34
const SWING_PANEL := 1.0
## Lamp gain on hover (options / credits).
const LAMP_LOUD := 1.7
const LAMP_STORY := 0.72

## Over the 3D view, under the filter: darkens the left side behind the text.
## Under the filter so it gets the same palette crunch.
const SHADE_SHADER := """
shader_type canvas_item;
void fragment() {
	float left = 1.0 - smoothstep(0.0, 0.46, UV.x);
	float top = 1.0 - smoothstep(0.0, 0.30, UV.y);
	float bottom = 1.0 - smoothstep(0.62, 1.0, UV.y);
	float a = left * 0.56 + top * 0.14 + left * top * 0.12 + left * bottom * 0.22;
	COLOR = vec4(0.0, 0.0, 0.0, clamp(a, 0.0, 0.78));
}
"""

const TEXT_LAYER := 95
const CAPTION := Color(1.0, 1.0, 0.93)
const CAPTION_DIM := Color(0.62, 0.58, 0.50)
const CAPTION_FAINT := Color(0.42, 0.39, 0.34)
const OUTLINE := Color(0.09, 0.055, 0.03, 1.0)
## Title alpha while the lamp is out mid-flicker.
const TITLE_DARK := 0.55
const TYPE_CPS := 30.0

const LINE_DAD := "Dad: lights out, champ."
const LINE_DAD_OPTIONS := "Dad: fine. just for a bit."
const LINE_DAD_CREDITS := "Dad: alright. once upon a time..."
const LINE_DAD_QUIT := "Dad: yes you are."
## The kid's answers, in order. `tag` says what the answer does, small and dim.
const REPLIES: Array[Dictionary] = [
	{"id": "begin", "say": "ok.", "tag": "begin"},
	{"id": "options", "say": "can the light stay on?", "tag": "options"},
	{"id": "credits", "say": "tell me a story", "tag": "credits"},
	{"id": "quit", "say": "I'm not sleepy", "tag": "quit"},
]
const CONTROLS_LINE := "WASD move   R use   Shift run   C crouch   Q / E lean       headphones recommended"

## Options rows. Volumes and mouse are ten notches.
const SLIDER_STEPS := 10
const SENS_MIN := 0.4
const SENS_MAX := 2.2

const CREDITS_LINES: Array[Dictionary] = [
	{"t": "once upon a time", "s": 24, "c": 1},
	{"t": "two people made a game in three days", "s": 24, "c": 1},
	{"t": "", "s": 12, "c": 2},
	{"t": "Yaser Allahem", "s": 32, "c": 0},
	{"t": "Ibrahim Alhumud", "s": 32, "c": 0},
	{"t": "", "s": 12, "c": 2},
	{"t": "for Game Zanga 14", "s": 22, "c": 1},
	{"t": "theme: dreams", "s": 22, "c": 1},
	{"t": "", "s": 12, "c": 2},
	{"t": "letters  Amazdoom, Noto Naskh Arabic", "s": 18, "c": 2},
	{"t": "noises  Kenney, alex_jauk, flutie8211, universfield", "s": 18, "c": 2},
	{"t": "made with Godot", "s": 18, "c": 2},
	{"t": "", "s": 12, "c": 2},
	{"t": "the end. go to sleep.", "s": 24, "c": 1},
]

var _level: Node3D
var _house: Node
var _lamps: Node
var _rig: Node3D
var _cam: Camera3D
var _closet: MeshInstance3D
var _closet_anchor := Vector3.ZERO
var _kid_lamp_lights: Array[Light3D] = []
var _lamp_base: Array[float] = []
var _text: CanvasLayer
var _title_flick: Control
var _reveal: Array[Control] = []
var _dad: Label
var _kid: Label
var _reply_rows: Array[Control] = []
var _reply_buttons: Array[Button] = []
var _panel: Control
var _panel_box: VBoxContainer
var _mode := Mode.MENU
var _starting := false
var _time := 0.0
var _look := Vector2.ZERO
var _creak_voice: AudioStreamPlayer3D
var _flickering := false
var _closet_tween: Tween
var _closet_idle := 0.0
var _lamp_gain := 1.0
var _lamp_gain_target := 1.0
var _pitch_bias := 0.0
var _pitch_bias_target := 0.0
var _dolly := 0.0
var _type_token := 0
var _dad_token := 0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	HUD.set_active(false)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	if not OS.has_feature("web"):
		AudioBus.unlock()
	_build_backdrop()
	_build_room()
	_build_shade()
	_build_filter()
	_build_text_layer()
	_build_title_block()
	_build_exchange()
	_build_footer()
	_build_panel()
	Fade.fade_in(1.6)
	_reveal_text()
	_closet_life()
	_lamp_life()


func _process(delta: float) -> void:
	_time += delta
	if _rig == null:
		return
	# breathing + mouse parallax
	var vp := get_viewport_rect().size
	var target := Vector2.ZERO
	if vp.x > 0.0 and vp.y > 0.0 and not _starting:
		target = (get_viewport().get_mouse_position() / vp - Vector2(0.5, 0.5)).clamp(
			Vector2(-0.5, -0.5), Vector2(0.5, 0.5))
	_look = _look.lerp(target, minf(1.0, PARALLAX_EASE * delta))
	_pitch_bias = lerpf(_pitch_bias, _pitch_bias_target, minf(1.0, 3.0 * delta))
	var breath := Vector3(0.0, sin(_time * TAU * BREATH_HZ) * BREATH_AMP, 0.0)
	# _dolly 0..1 blends the pose from the bed to the doorway (begin)
	var d := _dolly * _dolly * (3.0 - 2.0 * _dolly)
	_rig.position = eye.lerp(DOLLY_END, d) + breath * (1.0 - d)
	_rig.rotation = Vector3(
		deg_to_rad(lerpf(eye_pitch + _pitch_bias, 0.0, d)),
		deg_to_rad(lerpf(eye_yaw, DOLLY_YAW, d)), 0.0)
	_cam.rotation = Vector3(
		deg_to_rad(-_look.y * PARALLAX_PITCH) * (1.0 - d),
		deg_to_rad(-_look.x * PARALLAX_YAW) * (1.0 - d), 0.0)
	# lamp gain from hover state
	_lamp_gain = lerpf(_lamp_gain, _lamp_gain_target, minf(1.0, 4.0 * delta))
	for i in _kid_lamp_lights.size():
		var l := _kid_lamp_lights[i]
		if is_instance_valid(l):
			l.light_energy = _lamp_base[i] * _lamp_gain
	# title dims with the lamp flicker
	if _title_flick != null and not _starting:
		_title_flick.modulate.a = 1.0 if _lamp_lit() else TITLE_DARK
	_place_panel()


func _input(event: InputEvent) -> void:
	# any click / key counts as the browser's user gesture for audio
	if event is InputEventMouseButton or event is InputEventKey:
		if event.is_pressed():
			AudioBus.unlock()
	if event.is_action_pressed("ui_cancel") and (_mode == Mode.OPTIONS or _mode == Mode.CREDITS):
		_close_panel()
		get_viewport().set_input_as_handled()


# --- the room --------------------------------------------------------------------------

## Clear color under everything. The 2D layer has to stay clear (it draws over
## the 3D view), so this is set on the renderer instead.
func _build_backdrop() -> void:
	RenderingServer.set_default_clear_color(Color(0.008, 0.008, 0.014))


func _build_room() -> void:
	if not ResourceLoader.exists(GAME_SCENE):
		return
	var scene := load(GAME_SCENE) as PackedScene
	if scene == null:
		return
	_level = scene.instantiate() as Node3D
	for n in STRIP:
		var c := _level.get_node_or_null(n)
		if c != null:
			_level.remove_child(c)
			c.free()
	_level.name = "Room"
	add_child(_level)
	_house = _level.get_node_or_null("house")
	_lamps = _level.get_node_or_null("LampLights")

	_build_environment()
	_build_camera()
	_set_lights()
	_set_doors()
	_build_closet()
	_build_void()


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Presence.NIGHT_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Presence.NIGHT_AMBIENT
	env.ambient_light_energy = Presence.NIGHT_AMBIENT_ENERGY
	var we := WorldEnvironment.new()
	we.environment = env
	_level.add_child(we)


func _build_camera() -> void:
	_rig = Node3D.new()
	_rig.position = eye
	_rig.rotation = Vector3(deg_to_rad(eye_pitch), deg_to_rad(eye_yaw), 0.0)
	_level.add_child(_rig)
	_cam = Camera3D.new()
	_cam.fov = fov
	_cam.near = 0.04
	_rig.add_child(_cam)
	_cam.make_current()


func _set_lights() -> void:
	if _lamps != null:
		var by_mesh: Dictionary = _lamps.get("lights_by_mesh")
		for k: String in by_mesh.keys():
			var l := by_mesh[k] as Light3D
			if l == null:
				continue
			_level_light(l, k)
			if KID_LAMPS.has(k):
				_kid_lamp_lights.append(l)
				_lamp_base.append(l.light_energy)
	for c in _level.get_children():
		if c is Light3D:
			_level_light(c as Light3D, String(c.name))


func _level_light(l: Light3D, key: String) -> void:
	l.visible = LIGHT_LEVELS.has(key)
	if l.visible:
		l.light_energy *= float(LIGHT_LEVELS[key])


func _mesh(mesh_name: String) -> MeshInstance3D:
	if _house == null:
		return null
	return _house.find_child(mesh_name, true, false) as MeshInstance3D


## Kid's door shut (bedtime), so the closet is the only door in frame.
func _set_doors() -> void:
	var kid := _mesh(KID_DOOR)
	if kid != null and kid.has_method("snap_open"):
		kid.call("snap_open", false)


func _build_closet() -> void:
	var tmpl := _mesh(KID_DOOR)
	_closet = BedtimeScript.make_closet_panel(_house, tmpl)
	if _closet == null:
		return
	_house.add_child(_closet)
	_closet.set("_dir", _closet.call("swing_away_from", BedtimeScript.closet_room_point(_house)))
	var frame := _mesh(CLOSET_FRAME)
	if frame != null:
		_closet_anchor = MeshUtilScript.world_aabb(frame).get_center() + Vector3(0.0, 0.05, VOID_DEPTH * 0.5)
	# after act 0 the closet was left open
	if GameState.current_act != GameState.Act.BEDTIME:
		_closet_idle = 1.0
		_closet.call("snap_open", true)


func _build_void() -> void:
	var frame := _mesh(CLOSET_FRAME)
	if frame == null:
		return
	var q := QuadMesh.new()
	q.size = VOID_SIZE
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color.BLACK
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	q.material = mat
	var mi := MeshInstance3D.new()
	mi.name = "ClosetDark"
	mi.mesh = q
	_house.add_child(mi)
	mi.global_position = MeshUtilScript.world_aabb(frame).get_center() + Vector3(0.0, 0.0, VOID_DEPTH)


func _build_shade() -> void:
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = SHADE_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	rect.material = mat
	add_child(rect)


## Same filter node the level uses so menu and game share one palette.
func _build_filter() -> void:
	var f := CanvasLayer.new()
	f.name = "DoomFilter"
	f.set_script(DoomFilterScript)
	add_child(f)


# --- idle life ---------------------------------------------------------------------------

func _lamp_lit() -> bool:
	for l in _kid_lamp_lights:
		if is_instance_valid(l) and l.visible:
			return true
	return false


func _closet_swing() -> float:
	if _closet == null:
		return 1.0
	return float(_closet.get("_swing"))


## Single tween drives the closet panel. creak_db < -60 = no sound.
func _swing_to(swing: float, dur: float, creak_db := -100.0) -> void:
	if _closet == null or not is_instance_valid(_closet):
		return
	if _closet_tween != null and _closet_tween.is_valid():
		_closet_tween.kill()
	var from := _closet_swing()
	if is_equal_approx(from, swing):
		return
	if creak_db > -60.0:
		_play_creak(dur, creak_db)
	_closet_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_closet_tween.tween_method(func(v: float) -> void: _closet.call("_apply", v), from, swing, dur)


## Idle: the closet creaks open in steps over time.
func _closet_life() -> void:
	if _closet == null or _closet_idle > 0.0:
		return
	await get_tree().create_timer(CREAK_FIRST).timeout
	for step in CREAK_STEPS:
		if _starting or not is_inside_tree():
			return
		_closet_idle = step
		if _mode == Mode.MENU and _closet_swing() < step:
			var dur := 2.4 + (step - _closet_swing()) * 40.0
			_swing_to(step, dur, -24.0)
			await get_tree().create_timer(dur).timeout
		await get_tree().create_timer(randf_range(CREAK_AGAIN_MIN, CREAK_AGAIN_MAX)).timeout


## Creak at the closet, faded out when the swing ends.
func _play_creak(dur: float, db: float) -> void:
	if not AudioBus.is_unlocked() or _closet == null:
		return
	var stream := AudioBus.stream("door_open")
	if stream == null:
		return
	if _creak_voice != null and is_instance_valid(_creak_voice):
		_creak_voice.queue_free()
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.volume_db = db
	p.pitch_scale = randf_range(0.72, 0.84)
	p.unit_size = 3.0
	p.max_distance = 16.0
	if AudioServer.get_bus_index("SFX") >= 0:
		p.bus = "SFX"
	_level.add_child(p)
	p.global_position = _closet.call("get_prompt_anchor")
	p.play()
	p.finished.connect(p.queue_free)
	_creak_voice = p
	var t := create_tween()
	t.tween_interval(maxf(dur - 0.4, 0.1))
	t.tween_property(p, "volume_db", -50.0, 0.4)
	t.tween_callback(p.queue_free)


func _thud(db: float) -> void:
	if _closet == null or not AudioBus.is_unlocked():
		return
	AudioBus.sfx_at("door_close", _closet.call("get_prompt_anchor"), db, 0.08)


## Random lamp flicker, one or two pulses.
func _lamp_life() -> void:
	while is_inside_tree() and not _starting:
		await get_tree().create_timer(randf_range(FLICKER_MIN, FLICKER_MAX)).timeout
		if _starting or not is_inside_tree():
			return
		await _flicker(1 if randf() < 0.7 else 2)


func _flicker(pulses: int) -> void:
	if _flickering or _kid_lamp_lights.is_empty():
		return
	_flickering = true
	for i in pulses:
		for l in _kid_lamp_lights:
			l.visible = false
		await get_tree().create_timer(randf_range(0.04, 0.09)).timeout
		for l in _kid_lamp_lights:
			l.visible = true
		await get_tree().create_timer(randf_range(0.05, 0.14)).timeout
	_flickering = false


# --- text ------------------------------------------------------------------------------

func _build_text_layer() -> void:
	_text = CanvasLayer.new()
	_text.name = "Text"
	_text.layer = TEXT_LAYER
	add_child(_text)


func _build_title_block() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_TOP_LEFT)
	margin.add_theme_constant_override("margin_left", 84)
	margin.add_theme_constant_override("margin_top", 64)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text.add_child(margin)

	_title_flick = VBoxContainer.new()
	_title_flick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(_title_flick)

	var box := VBoxContainer.new()
	# font has a lot of vertical air, pull the lines together
	box.add_theme_constant_override("separation", -16)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_flick.add_child(box)

	var l1 := _doom_label("THERE IS A", 26, CAPTION_DIM, 6)
	box.add_child(l1)
	var l2 := _doom_label("MONSTER", 92, CAPTION, 14)
	box.add_child(l2)
	var l3 := _doom_label("IN MY CLOSET", 38, CAPTION, 10)
	box.add_child(l3)

	var ar_pad := Control.new()
	ar_pad.custom_minimum_size = Vector2(0, 20)
	box.add_child(ar_pad)

	# arabic title, naskh font
	var ar := UiKit.make_label("في وحش في دولابي", 22, CAPTION_DIM)
	ar.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	ar.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	ar.add_theme_constant_override("shadow_offset_x", 2)
	ar.add_theme_constant_override("shadow_offset_y", 2)
	box.add_child(ar)

	var rule_pad := Control.new()
	rule_pad.custom_minimum_size = Vector2(0, 22)
	box.add_child(rule_pad)

	var rule := ColorRect.new()
	rule.color = Color(UiKit.WARM.r, UiKit.WARM.g, UiKit.WARM.b, 0.55)
	rule.custom_minimum_size = Vector2(150, 2)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	box.add_child(rule)

	_reveal.append_array([l1, l2, l3, ar, rule])


## Dad's caption line with the kid's replies (= menu buttons) under it.
func _build_exchange() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	margin.grow_vertical = Control.GROW_DIRECTION_BEGIN
	margin.add_theme_constant_override("margin_left", 84)
	margin.add_theme_constant_override("margin_bottom", 78)
	_text.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	margin.add_child(box)

	_dad = _doom_label("", 28, CAPTION_DIM, 7)
	_dad.custom_minimum_size = Vector2(560, 0)
	box.add_child(_dad)

	var pad := Control.new()
	pad.custom_minimum_size = Vector2(0, 8)
	box.add_child(pad)

	# replies and the picked reply share a fixed-height slot so the dad line
	# doesn't jump when the replies hide
	var slot := Control.new()
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(slot)
	var replies := VBoxContainer.new()
	replies.add_theme_constant_override("separation", 4)
	slot.add_child(replies)
	for r in REPLIES:
		if r["id"] == "quit" and OS.has_feature("web"):
			continue
		var b := _menu_item(String(r["say"]), 32)
		b.pressed.connect(_on_reply.bind(String(r["id"])))
		b.mouse_entered.connect(_on_reply_hover.bind(String(r["id"]), true))
		b.mouse_exited.connect(_on_reply_hover.bind(String(r["id"]), false))
		var row := _wrap_hover(b, String(r["tag"]))
		row.modulate.a = 0.0
		replies.add_child(row)
		_reply_rows.append(row)
		_reply_buttons.append(b)
	_kid = _doom_label("", 32, CAPTION, 8)
	_kid.visible = false
	_kid.position = Vector2(0.0, 6.0)
	slot.add_child(_kid)
	# slot height from the rows once they have a size
	(func() -> void: slot.custom_minimum_size = replies.get_combined_minimum_size()).call_deferred()


func _build_footer() -> void:
	var right := MarginContainer.new()
	right.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	right.grow_vertical = Control.GROW_DIRECTION_BEGIN
	right.add_theme_constant_override("margin_right", 28)
	right.add_theme_constant_override("margin_bottom", 22)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text.add_child(right)
	var f := _doom_label("GAME ZANGA 14", 16, CAPTION_FAINT, 4)
	right.add_child(f)
	_reveal.append(f)

	# controls line, only place keys are listed (in game only the object prompt)
	var left := MarginContainer.new()
	left.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	left.grow_vertical = Control.GROW_DIRECTION_BEGIN
	left.add_theme_constant_override("margin_left", 84)
	left.add_theme_constant_override("margin_bottom", 26)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text.add_child(left)
	var keys := _doom_label(CONTROLS_LINE, 15, CAPTION_FAINT, 4)
	left.add_child(keys)
	_reveal.append(keys)


## Staggered fade-in top to bottom, then dad's line types, then the replies.
func _reveal_text() -> void:
	var delay := 0.7
	for c in _reveal:
		c.modulate.a = 0.0
		var t := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		t.tween_interval(delay)
		t.tween_property(c, "modulate:a", 1.0, 0.9)
		delay += 0.13
	await get_tree().create_timer(1.1).timeout
	if _starting or not is_inside_tree():
		return
	await _say_dad(LINE_DAD)
	_show_replies(true, 0.35)


func _show_replies(on: bool, dur: float) -> void:
	var delay := 0.0
	for row in _reply_rows:
		var t := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		t.tween_interval(delay)
		t.tween_property(row, "modulate:a", 1.0 if on else 0.0, dur)
		if on:
			delay += 0.12
	for b in _reply_buttons:
		b.disabled = not on
		b.mouse_filter = Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_IGNORE


## Swap dad's line: fade the old one, type the new one. A newer call cancels
## an in-progress one via the token.
func _say_dad(text: String) -> void:
	_dad_token += 1
	var token := _dad_token
	if not _dad.text.is_empty() and _dad.modulate.a > 0.01:
		var t := create_tween()
		t.tween_property(_dad, "modulate:a", 0.0, 0.3)
		await t.finished
		if token != _dad_token or not is_inside_tree():
			return
	_dad.modulate.a = 1.0
	await _type_out(_dad, text, token)


func _type_out(label: Label, text: String, token: int) -> void:
	label.text = text
	label.visible_characters = 0
	var count := label.get_total_character_count()
	var shown := 0.0
	while shown < count:
		if token != _dad_token or not is_inside_tree():
			return
		shown += TYPE_CPS * get_process_delta_time()
		label.visible_characters = int(shown)
		await get_tree().process_frame
	label.visible_characters = -1


## Show the picked reply as the kid's line where the replies were.
func _say_kid(text: String) -> void:
	_show_replies(false, 0.25)
	await get_tree().create_timer(0.25).timeout
	_kid.text = text
	_kid.visible = true
	_kid.modulate.a = 1.0
	_kid.visible_characters = 0
	var count := _kid.get_total_character_count()
	var shown := 0.0
	while shown < count:
		if not is_inside_tree():
			return
		shown += TYPE_CPS * 1.4 * get_process_delta_time()
		_kid.visible_characters = int(shown)
		await get_tree().process_frame
	_kid.visible_characters = -1


func _hide_kid() -> void:
	if not _kid.visible:
		return
	var t := create_tween()
	t.tween_property(_kid, "modulate:a", 0.0, 0.3)
	await t.finished
	_kid.visible = false


static func _doom_label(text: String, size: int, color: Color, outline: int) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", DOOM_FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", OUTLINE)
	l.add_theme_constant_override("outline_size", outline)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_offset_x", 3)
	l.add_theme_constant_override("shadow_offset_y", 3)
	return l


## Flat text button, warm on hover; _wrap_hover adds the slide.
func _menu_item(text: String, size: int) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_override("font", DOOM_FONT)
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", CAPTION)
	b.add_theme_color_override("font_hover_color", UiKit.WARM)
	b.add_theme_color_override("font_pressed_color", UiKit.WARM)
	b.add_theme_color_override("font_focus_color", CAPTION)
	b.add_theme_color_override("font_disabled_color", CAPTION)
	b.add_theme_color_override("font_outline_color", OUTLINE)
	b.add_theme_constant_override("outline_size", 8)
	b.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	b.add_theme_constant_override("shadow_offset_x", 3)
	b.add_theme_constant_override("shadow_offset_y", 3)
	return b


## Row: pad (animated on hover) + button + small dim tag on the right.
func _wrap_hover(btn: Button, tag: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(0, 0)
	row.add_child(pad)
	row.add_child(btn)
	if not tag.is_empty():
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(22, 0)
		row.add_child(gap)
		var t := _doom_label(tag, 16, Color(0.52, 0.48, 0.42), 4)
		t.size_flags_vertical = Control.SIZE_FILL
		t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(t)
	btn.mouse_entered.connect(_slide.bind(pad, 12.0))
	btn.mouse_exited.connect(_slide.bind(pad, 0.0))
	return row


func _slide(pad: Control, to: float) -> void:
	var t := create_tween()
	t.tween_property(pad, "custom_minimum_size:x", to, 0.16) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


# --- answers ---------------------------------------------------------------------------

## Hover reactions in the room per reply.
func _on_reply_hover(id: String, on: bool) -> void:
	if _mode != Mode.MENU or _starting:
		return
	match id:
		"begin":
			if on:
				_swing_to(maxf(_closet_idle, SWING_HOVER), 1.1, -30.0)
			else:
				_swing_to(_closet_idle, 2.2)
		"options":
			_lamp_gain_target = LAMP_LOUD if on else 1.0
		"credits":
			_lamp_gain_target = LAMP_STORY if on else 1.0
			_pitch_bias_target = -1.6 if on else 0.0
		"quit":
			if on:
				_swing_to(0.0, 0.55)
				if _closet_swing() > 0.02:
					var t := create_tween()
					t.tween_interval(0.5)
					t.tween_callback(_thud.bind(-30.0))
			else:
				_swing_to(_closet_idle, 2.6)


func _on_reply(id: String) -> void:
	if _mode != Mode.MENU or _starting:
		return
	match id:
		"begin":
			_on_begin()
		"options":
			_open_panel(Mode.OPTIONS)
		"credits":
			_open_panel(Mode.CREDITS)
		"quit":
			_on_quit()


# --- options / credits page inside the open closet -------------------------------------

func _build_panel() -> void:
	_panel = Control.new()
	_panel.name = "ClosetPage"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.modulate.a = 0.0
	_panel.visible = false
	_text.add_child(_panel)
	_panel_box = VBoxContainer.new()
	_panel_box.add_theme_constant_override("separation", 6)
	_panel_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_panel_box)


## Page centre follows the projected closet anchor, clamped to the screen.
func _place_panel() -> void:
	if _panel == null or not _panel.visible or _cam == null:
		return
	var size := _panel_box.get_combined_minimum_size()
	_panel_box.size = size
	var vr := get_viewport().get_visible_rect()
	var at := _cam.unproject_position(_closet_anchor)
	var pos := at - size * 0.5
	pos.x = clampf(pos.x, 24.0, maxf(24.0, vr.size.x - size.x - 24.0))
	pos.y = clampf(pos.y, 24.0, maxf(24.0, vr.size.y - size.y - 24.0))
	_panel.position = pos
	_panel.size = size


func _clear_panel() -> void:
	for c in _panel_box.get_children():
		_panel_box.remove_child(c)
		c.queue_free()


func _open_panel(mode: Mode) -> void:
	_mode = mode
	_pitch_bias_target = 0.0
	if mode == Mode.OPTIONS:
		_lamp_gain_target = LAMP_LOUD
	_say_kid("can the light stay on?" if mode == Mode.OPTIONS else "tell me a story")
	_say_dad(LINE_DAD_OPTIONS if mode == Mode.OPTIONS else LINE_DAD_CREDITS)
	_swing_to(SWING_PANEL, 3.0, -22.0)
	_clear_panel()
	if mode == Mode.OPTIONS:
		_fill_options()
	else:
		_fill_credits()
	await get_tree().create_timer(1.3).timeout
	if _mode != mode:
		return
	_panel.visible = true
	var t := create_tween()
	t.tween_property(_panel, "modulate:a", 1.0, 0.7)


func _close_panel() -> void:
	if _mode != Mode.OPTIONS and _mode != Mode.CREDITS:
		return
	_mode = Mode.MENU
	_lamp_gain_target = 1.0
	GameState.save_settings()
	var t := create_tween()
	t.tween_property(_panel, "modulate:a", 0.0, 0.3)
	t.tween_callback(func() -> void: _panel.visible = false)
	_swing_to(_closet_idle, 2.6, -28.0)
	await _hide_kid()
	await _say_dad(LINE_DAD)
	if _mode == Mode.MENU:
		_show_replies(true, 0.3)


func _page_label(text: String, size: int, color: Color) -> Label:
	var l := _doom_label(text, size, color, 6 if size >= 28 else 4)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _fill_credits() -> void:
	var colors: Array[Color] = [CAPTION, CAPTION_DIM, CAPTION_FAINT]
	for line in CREDITS_LINES:
		var text := String(line["t"])
		if text.is_empty():
			var pad := Control.new()
			pad.custom_minimum_size = Vector2(0, int(line["s"]))
			_panel_box.add_child(pad)
			continue
		var l := _page_label(text, int(line["s"]), colors[int(line["c"])])
		_panel_box.add_child(l)
	_add_back_row()


func _fill_options() -> void:
	_add_slider("sound", "master", 0.0, 1.0)
	_add_slider("effects", "sfx", 0.0, 1.0)
	_add_slider("ambience", "ambience", 0.0, 1.0)
	_add_slider("mouse", "sensitivity", SENS_MIN, SENS_MAX)
	_add_toggle("invert Y", "invert_y", [false, true], ["off", "on"])
	if not OS.has_feature("web"):
		_add_toggle("window", "fullscreen", [false, true], ["windowed", "fullscreen"])
	_add_toggle("prompts", "language", ["en", "ar"], ["english", "arabic"])
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(0, 8)
	_panel_box.add_child(pad)
	_add_back_row()


func _add_back_row() -> void:
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(0, 8)
	_panel_box.add_child(pad)
	var b := _menu_item("ok. night.", 26)
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.pressed.connect(_close_panel)
	_panel_box.add_child(b)


func _row(label_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(380, 0)
	row.add_theme_constant_override("separation", 12)
	var l := _doom_label(label_text, 24, CAPTION, 5)
	l.custom_minimum_size = Vector2(120, 0)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size_flags_vertical = Control.SIZE_FILL
	row.add_child(l)
	_panel_box.add_child(row)
	return row


func _arrow(text: String) -> Button:
	var b := _menu_item(text, 24)
	b.custom_minimum_size = Vector2(26, 0)
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	return b


## Ten-notch slider: click a notch or the arrows.
func _add_slider(label_text: String, key: String, lo: float, hi: float) -> void:
	var row := _row(label_text)
	var less := _arrow("<")
	row.add_child(less)
	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", 4)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(strip)
	var ticks: Array[ColorRect] = []
	for i in SLIDER_STEPS:
		var tick := ColorRect.new()
		tick.custom_minimum_size = Vector2(12, 16)
		tick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tick.mouse_filter = Control.MOUSE_FILTER_STOP
		strip.add_child(tick)
		ticks.append(tick)
	var more := _arrow(">")
	row.add_child(more)

	var step_of := func() -> int:
		var v := float(GameState.settings[key])
		return clampi(int(roundf((v - lo) / (hi - lo) * SLIDER_STEPS)), 0, SLIDER_STEPS)
	var paint := func() -> void:
		var s: int = step_of.call()
		for i in ticks.size():
			ticks[i].color = UiKit.WARM if i < s else Color(CAPTION_FAINT.r, CAPTION_FAINT.g, CAPTION_FAINT.b, 0.55)
	var set_step := func(s: int) -> void:
		s = clampi(s, 0 if lo <= 0.0 else 1, SLIDER_STEPS)
		GameState.set_setting(key, lo + (hi - lo) * float(s) / float(SLIDER_STEPS))
		paint.call()
		AudioBus.sfx("door_latch", -22.0, 0.08)
	less.pressed.connect(func() -> void: set_step.call(step_of.call() - 1))
	more.pressed.connect(func() -> void: set_step.call(step_of.call() + 1))
	for i in ticks.size():
		var idx := i
		ticks[i].gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.is_pressed() and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
				set_step.call(idx + 1))
	paint.call()


## Toggle shown as a word, click to flip.
func _add_toggle(label_text: String, key: String, values: Array, words: Array[String]) -> void:
	var row := _row(label_text)
	var b := _menu_item("", 24)
	b.custom_minimum_size = Vector2(160, 0)
	row.add_child(b)
	var paint := func() -> void:
		var i := values.find(GameState.settings[key])
		b.text = words[maxi(i, 0)]
	b.pressed.connect(func() -> void:
		var i := values.find(GameState.settings[key])
		GameState.set_setting(key, values[(i + 1) % values.size()])
		paint.call()
		AudioBus.sfx("door_latch", -22.0, 0.08))
	paint.call()


# --- begin / quit ---------------------------------------------------------------------

## Begin: closet swings fully open, camera dollies in, fade to black, load
## the level.
func _on_begin() -> void:
	if _starting:
		return
	_starting = true
	_mode = Mode.LEAVING
	# Unlock and capture INSIDE the gesture handler; after any await the
	# browser no longer counts this as a user gesture.
	AudioBus.unlock()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	GameState.reset()
	_lamp_gain_target = 1.0
	_pitch_bias_target = 0.0
	_say_kid("ok.")
	var t := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	for c in _reveal:
		t.parallel().tween_property(c, "modulate:a", 0.0, 0.6)
	t.parallel().tween_property(_dad, "modulate:a", 0.0, 0.6)
	await get_tree().create_timer(0.7).timeout
	_swing_to(1.0, 2.6, -18.0)
	await get_tree().create_timer(1.0).timeout
	var k := create_tween()
	k.tween_property(_kid, "modulate:a", 0.0, 0.5)
	var d := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	d.tween_property(self, "_dolly", 1.0, 2.5)
	await get_tree().create_timer(1.4).timeout
	await Fade.fade_out(1.1)
	_lamp_off()
	get_tree().change_scene_to_file(GAME_SCENE)
	# level starts black with its own eyelid intro
	Fade.clear_deferred()


func _lamp_off() -> void:
	if _kid_lamp_lights.is_empty():
		return
	AudioBus.sfx_at("switch", _kid_lamp_lights[0].global_position, -14.0, 0.03, 0.8)
	for l in _kid_lamp_lights:
		l.visible = false
	_kid_lamp_lights.clear()
	_lamp_base.clear()


func _on_quit() -> void:
	if _starting:
		return
	_starting = true
	_mode = Mode.LEAVING
	_say_kid("I'm not sleepy")
	await _say_dad(LINE_DAD_QUIT)
	await get_tree().create_timer(0.5).timeout
	_swing_to(0.0, 0.5)
	await get_tree().create_timer(0.5).timeout
	_thud(-20.0)
	await get_tree().create_timer(0.5).timeout
	_lamp_off()
	await Fade.fade_out(0.6)
	get_tree().quit()
