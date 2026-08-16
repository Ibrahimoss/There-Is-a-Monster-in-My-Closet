extends Node
## Cover art, rendered out of the game: the monster down a chase corridor, seen
## through an open door, with the menu's title block over the top left.
##
## The camera is its own Camera3D rather than the player -- the player is a
## CharacterBody3D, so teleporting it and then waiting for the shot just gives
## it time to fall, which is what made every earlier attempt come out black.
##
## Run windowed, it needs a GPU context:
##   godot --path . res://tools/CoverShot.tscn
## REVIEW_OUT picks the folder. COVER_SEED fixes the layout.

const StartScreen := preload("res://scenes/ui/start_screen.gd")
const NASKH := "res://assets/fonts/NotoNaskhArabic.ttf"
const TWIST := preload("res://tools/cover_twist.gdshader")
const DREAD := preload("res://scripts/dread.gdshader")
const STUN := preload("res://scripts/stun.gdshader")

## 630x500 is what the jam page wants; rendered at twice that and left
## for them to downscale, so the type stays crisp.
const SHOT := Vector2i(1260, 1000)
## Long halls either side of the doorway so the corridor reads as depth.
const SEQ := "long,long,long,long,long,donut,stairs,garden,long,donut"

var out_dir := ""
var _level: Node
var _chase: Node
var _cam: Camera3D


func _ready() -> void:
	out_dir = OS.get_environment("REVIEW_OUT")
	if out_dir.is_empty():
		out_dir = "user://cover"
	DirAccess.make_dir_recursive_absolute(out_dir)
	# the title wants the doom face, which is the English side of the menu
	GameState.language = "en"
	OS.set_environment("CHASE", "rooms")
	if OS.get_environment("CHASE_SEQ").is_empty():
		OS.set_environment("CHASE_SEQ", SEQ)
	get_window().size = SHOT
	AudioBus.unlock()
	_run()


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _run() -> void:
	_level = (load("res://real_world.tscn") as PackedScene).instantiate()
	add_child(_level)
	var fade := get_node_or_null("/root/Fade")
	if fade != null and fade.has_method("fade_in"):
		fade.call("fade_in", 0.2)
	await _wait(3.0)
	if fade != null and fade.has_method("fade_in"):
		fade.call("fade_in", 0.2)

	_chase = _level.get_node_or_null("Chase")
	if _chase == null:
		push_error("cover: no chase")
		get_tree().quit(1)
		return
	var tries := 0
	while (_chase.get("rooms") as Array).size() < 4 and tries < 300:
		await get_tree().process_frame
		tries += 1
	var rooms: Array = _chase.get("rooms")
	if rooms.size() < 4:
		push_error("cover: chase never built")
		get_tree().quit(1)
		return

	_force_english()
	_park_the_player()
	_show(rooms)
	_open_the_door(rooms)
	_lights_on(rooms)
	_frame(rooms)
	await _wait(1.5)
	_twist(rooms)
	_place_monster(rooms)
	_tension()
	_title()
	await _wait(0.5)
	await _shot("cover")
	get_tree().quit()


## GameState re-applies the saved settings on a deferred call, so setting the
## language in _ready is undone a frame later. Set the setting as well as the
## live value, and do it after that call has landed.
func _force_english() -> void:
	GameState.settings["language"] = "en"
	GameState.language = "en"


## The player is not in this picture and must not fall through it either.
func _park_the_player() -> void:
	var p := _level.get_node_or_null("player") as CharacterBody3D
	if p == null:
		return
	p.visible = false
	p.set_physics_process(false)
	p.set_process(false)


## The director hides everything outside a window either side of you, and it
## does that off entry triggers this tool never fires.
func _show(rooms: Array) -> void:
	_chase.set("current_room", 1)
	for i in rooms.size():
		var raw: Variant = rooms[i]["root"]
		if is_instance_valid(raw):
			(raw as Node3D).visible = i <= 4


## The chase brings a room's lamps up as you enter it, off triggers this tool
## never fires, so every hall it shows would otherwise be unlit.
func _lights_on(rooms: Array) -> void:
	for i in mini(5, rooms.size()):
		for l in (rooms[i]["lights"] as Array):
			var light := l as Light3D
			if light == null or not is_instance_valid(light):
				continue
			light.visible = true
			# falling off with distance keeps the far end a silhouette
			light.light_energy = maxf(light.light_energy, 1.0) * (1.0 if i < 3 else 1.6)
			var bulb = light.get_meta("bulb") if light.has_meta("bulb") else null
			if bulb is Node3D:
				(bulb as Node3D).visible = true


## The door between us and it, stood open: the corridor is read through the
## opening rather than presented flat.
func _open_the_door(rooms: Array) -> void:
	var d: MeshInstance3D = rooms[1]["exit_door"]
	if d == null:
		return
	d.set("locked", false)
	if d.has_method("snap_open"):
		d.call("snap_open", true)


## Far enough down that it is a shape in the dark rather than a model.
func _place_monster(rooms: Array) -> void:
	var m: Node3D = _chase.get("monster")
	if m == null or not is_instance_valid(m):
		return
	var far: Dictionary = rooms[1]
	var root := far["root"] as Node3D
	if m.has_method("enter_room"):
		m.call("enter_room", far["world_graph"], root.transform * Vector3(0.0, 0.0, 0.5))
	if _cam == null:
		return
	# _show drives the dissolve the shader fades it in with; without it the
	# body is in the scene at zero visible_amount and renders as nothing.
	if m.has_method("_show"):
		m.call("_show", 0.0)
	if m.has_method("freeze"):
		m.call("freeze")
	m.visible = true
	# Close enough to loom over the frame, pushed off the centre line so it is
	# not a mugshot and does not sit under the title. Down the camera's own
	# sight line, which is the one line guaranteed to be in shot.
	var fwd := -_cam.global_transform.basis.z.normalized()
	var right := _cam.global_transform.basis.x.normalized()
	var at := _cam.global_position + fwd * 4.2 + right * 0.26
	at.y = root.global_position.y
	m.global_position = at
	# Its view is a Y-billboard, so it already faces us and turning the node
	# does nothing -- the lean uniform is the only way to tilt it. Height is
	# HEIGHT (2.45) with the feet on the node origin, and the corridor ceiling
	# is CEIL (2.85), so anything past about 1.16 puts its head through the
	# ceiling. 1.05 leaves it 2.57 -- a good head over the kid, and inside.
	m.scale = Vector3.ONE * 1.05
	_light_it_from_behind(at, fwd)
	_wake_its_face(m)


## A lamp on the floor beyond it, so it comes forward as a silhouette instead
## of a grey model standing in a corridor.
func _light_it_from_behind(at: Vector3, fwd: Vector3) -> void:
	var back := OmniLight3D.new()
	back.light_color = Color(1.0, 0.86, 0.66)
	back.light_energy = 3.4
	back.omni_range = 5.5
	back.shadow_enabled = false
	_level.add_child(back)
	back.global_position = at + fwd * 2.2 + Vector3(0.0, 0.75, 0.0)


## The monster's own shader carries the eyes and the glitch; both idle low
## until it is actually hunting you.
func _wake_its_face(m: Node3D) -> void:
	var view := m.get("_view") as MeshInstance3D
	if view == null:
		return
	var mat := view.material_override as ShaderMaterial
	if mat == null and view.mesh != null and view.mesh.get_surface_count() > 0:
		mat = view.mesh.surface_get_material(0) as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter("visible_amount", 1.0)
	mat.set_shader_parameter("eyes", 1.0)
	mat.set_shader_parameter("glitch", 0.5)
	mat.set_shader_parameter("t", 3.1)
	# In play the body sits at 0.02 -- near enough to black that all you get is
	# the pair of eyes, which is right when it is hunting you and wrong on a
	# cover, where the shape is the thing being sold. Lifted just off black so
	# the head, the shoulders and the fall of it read against the lit wall
	# behind, without turning it into a model you can inspect.
	mat.set_shader_parameter("body_color", Color(0.105, 0.105, 0.135))
	# a tilt: the billboard throws the node rotation away, so it goes here
	mat.set_shader_parameter("lean", 0.22)


## Our own camera, at standing height, looking straight down the throat of it.
func _frame(rooms: Array) -> void:
	var near := rooms[1]["root"] as Node3D
	var far := rooms[3]["root"] as Node3D
	_cam = Camera3D.new()
	_cam.fov = 68.0
	_cam.current = true
	_level.add_child(_cam)
	var eye: Vector3 = near.transform * Vector3(0.0, 1.55, 1.2)
	var at: Vector3 = far.transform * Vector3(0.0, 1.25, 3.0)
	_cam.global_position = eye
	_cam.look_at(at, Vector3.UP)
	# a dutch tilt -- the cheapest tension there is, and it costs nothing here
	_cam.rotate_object_local(Vector3(0, 0, 1), deg_to_rad(5.0))


## The drill, in the world. Every mesh in the corridor gets a vertex shader
## that winds it about the corridor's own axis, carrying its albedo across so
## the walls keep their surface. Done after the camera exists, because the
## axis is the camera's own sight line -- that is the line the hall runs down.
func _twist(rooms: Array) -> void:
	if _cam == null:
		return
	var origin := _cam.global_position
	var dir := -_cam.global_transform.basis.z.normalized()
	for i in mini(5, rooms.size()):
		var raw: Variant = rooms[i]["root"]
		if not is_instance_valid(raw):
			continue
		for node in (raw as Node3D).find_children("*", "MeshInstance3D", true, false):
			_wind(node as MeshInstance3D, origin, dir)


func _wind(mi: MeshInstance3D, origin: Vector3, dir: Vector3) -> void:
	if mi == null or mi.mesh == null:
		return
	# whatever the mesh is wearing now, so the twist does not strip it
	var src: Material = mi.material_override
	if src == null:
		src = mi.get_surface_override_material(0)
	if src == null and mi.mesh.get_surface_count() > 0:
		src = mi.mesh.surface_get_material(0)
	# Anything already on a shader is not corridor: the monster's body is a
	# ShaderMaterial that carries its dissolve, its eyes and its glitch, and
	# swapping that for a flat albedo pass is what turned it into a plain grey
	# cone standing in the hall.
	if src is ShaderMaterial:
		return
	var col := Color.WHITE
	var tex: Texture2D = null
	var std := src as StandardMaterial3D
	if std != null:
		col = std.albedo_color
		tex = std.albedo_texture

	var mat := ShaderMaterial.new()
	mat.shader = TWIST
	mat.set_shader_parameter("albedo_col", col)
	if tex != null:
		mat.set_shader_parameter("albedo_tex", tex)
	mat.set_shader_parameter("has_tex", 1.0 if tex != null else 0.0)
	mat.set_shader_parameter("twist", 0.045)
	mat.set_shader_parameter("axis_origin", origin)
	mat.set_shader_parameter("axis_dir", dir)
	mat.set_shader_parameter("start", 5.0)
	mat.set_shader_parameter("max_turn", 0.8)
	mi.material_override = mat


## The game's own two full-screen passes, held at a value rather than played:
## dread swims and pulls the frame about, stun lags a second image behind the
## first and smears everything out of the middle. Between them the cover gets
## its blur and its unsteadiness without inventing a look the game does not
## already have.
func _tension() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 108
	add_child(layer)
	_pass(layer, DREAD, {"amount": 0.55, "seen": 0.85, "t": 7.3})
	_pass(layer, STUN, {"amount": 0.34, "t": 4.7})


func _pass(layer: CanvasLayer, shader: Shader, params: Dictionary) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = shader
	for k: String in params.keys():
		mat.set_shader_parameter(k, params[k])
	var r := ColorRect.new()
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.material = mat
	r.color = Color.WHITE
	layer.add_child(r)


## The menu's own title block, top left, in the doom face.
func _title() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 120
	add_child(layer)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_TOP_LEFT)
	margin.add_theme_constant_override("margin_left", 84)
	margin.add_theme_constant_override("margin_top", 48)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(margin)

	var box := VBoxContainer.new()
	# the face has a lot of vertical air; the menu pulls the lines together
	box.add_theme_constant_override("separation", -30)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(box)

	box.add_child(StartScreen._doom_label("THERE IS A", 34, StartScreen.CAPTION_DIM, 6))
	box.add_child(StartScreen._doom_label("MONSTER", 118, StartScreen.CAPTION, 16))
	box.add_child(StartScreen._doom_label("IN MY CLOSET", 50, StartScreen.CAPTION, 12))

	var pad := Control.new()
	pad.custom_minimum_size = Vector2(0, 26)
	box.add_child(pad)

	var ar := Label.new()
	ar.text = "في وحش في دولابي"
	ar.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	ar.add_theme_font_override("font", load(NASKH))
	ar.add_theme_font_size_override("font_size", 30)
	ar.add_theme_color_override("font_color", StartScreen.CAPTION_DIM)
	ar.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	ar.add_theme_constant_override("shadow_offset_x", 2)
	ar.add_theme_constant_override("shadow_offset_y", 2)
	box.add_child(ar)


func _shot(shot_name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await _wait(0.3)
	var img := get_viewport().get_texture().get_image()
	var path := out_dir.path_join(shot_name + ".png")
	img.save_png(path)
	print("saved ", path)
