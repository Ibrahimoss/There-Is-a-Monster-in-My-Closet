extends Node
## Cover art, rendered out of the actual game rather than drawn.
##
## Boots the chase, stands the camera back in one hallway looking through an
## open door into the next, puts the monster down the far end where it is a
## silhouette rather than a model you can read, and lays the title over it.
## Run windowed -- it needs a GPU context, headless cannot screenshot:
##   godot --path . res://tools/CoverShot.tscn
## REVIEW_OUT picks the folder.

const LEVEL := "res://real_world.tscn"
## Long halls either side of the doorway, so the corridor reads as depth and
## the far end falls away into the dark.
const SEQ := "long,long,long,donut,long,long,stairs,garden,long,donut"
const SHOT := Vector2i(1920, 1080)

var out_dir := ""
var _level: Node
var _player: CharacterBody3D
var _chase: Node


func _ready() -> void:
	out_dir = OS.get_environment("REVIEW_OUT")
	if out_dir.is_empty():
		out_dir = "user://cover"
	DirAccess.make_dir_recursive_absolute(out_dir)
	OS.set_environment("CHASE", "rooms")
	if OS.get_environment("CHASE_SEQ").is_empty():
		OS.set_environment("CHASE_SEQ", SEQ)
	DisplayServer.window_set_size(SHOT)
	get_viewport().size = SHOT
	AudioBus.unlock()
	_run()


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _run() -> void:
	_level = (load(LEVEL) as PackedScene).instantiate()
	add_child(_level)
	# Fade boots opaque and only the start screen ever clears it, so a tool
	# scene renders a black frame unless it claims the fade itself.
	var fade := get_node_or_null("/root/Fade")
	if fade != null:
		if fade.has_method("clear_deferred"):
			fade.call("clear_deferred")
		elif fade.has_method("fade_in"):
			fade.call("fade_in", 0.2)
	await _wait(2.5)
	if fade != null and fade.has_method("fade_in"):
		fade.call("fade_in", 0.2)
	# the palette-crush filter sits over everything; the cover wants the raw look
	var doom := _level.get_node_or_null("DoomFilter")
	if doom != null:
		doom.visible = false
	await _wait(0.5)
	_player = _level.get_node_or_null("player") as CharacterBody3D
	_chase = _level.get_node_or_null("Chase")
	if _player == null or _chase == null:
		push_error("cover: no player or chase")
		get_tree().quit(1)
		return
	# let the hallways finish generating
	var tries := 0
	while (_chase.get("rooms") as Array).size() < 4 and tries < 200:
		await get_tree().process_frame
		tries += 1
	var rooms: Array = _chase.get("rooms")
	if rooms.size() < 4:
		push_error("cover: chase never built")
		get_tree().quit(1)
		return

	# the director only keeps the rooms either side of you in the picture
	_chase.set("current_room", 1)
	_chase.call("_cull_rooms", 1)
	for i in rooms.size():
		var raw: Variant = rooms[i]["root"]
		if is_instance_valid(raw):
			(raw as Node3D).visible = i <= 3

	_open_the_door(rooms)
	_place_monster(rooms)
	_frame_the_shot(rooms)
	_light_it(rooms)
	await _wait(1.2)
	_title()
	await _wait(0.6)
	await _shot("cover")
	get_tree().quit()


## The door between us and it, stood open. Foreground framing: the corridor is
## read through the opening rather than presented flat.
func _open_the_door(rooms: Array) -> void:
	var d: MeshInstance3D = rooms[1]["exit_door"]
	if d == null:
		return
	d.set("locked", false)
	if d.has_method("snap_open"):
		d.call("snap_open", true)


## Far down the corridor and frozen, so it renders as a shape in the dark.
func _place_monster(rooms: Array) -> void:
	var m: Node3D = _chase.get("monster")
	if m == null or not is_instance_valid(m):
		return
	var far: Dictionary = rooms[3]
	var root := far["root"] as Node3D
	if m.has_method("enter_room"):
		m.call("enter_room", far["world_graph"], root.transform * Vector3(0.0, 0.0, 0.5))
	if m.has_method("freeze"):
		m.call("freeze")
	m.visible = true
	m.global_position = root.transform * Vector3(0.0, 0.0, 2.2)


## Stood back in the near hall, low, looking down the throat of the corridor.
func _frame_the_shot(rooms: Array) -> void:
	var near := rooms[1]["root"] as Node3D
	var far := rooms[3]["root"] as Node3D
	var eye: Vector3 = near.transform * Vector3(0.0, 0.0, -3.4)
	var at: Vector3 = far.transform * Vector3(0.0, 0.9, 2.2)
	_player.teleport_to(eye)
	var d := at - eye
	d.y = 0.0
	if d.length() > 0.01:
		d = d.normalized()
		_player.rotation.y = atan2(-d.x, -d.z)
	_player.sync_look_from_transform()
	var head: Node3D = _player.get("_head")
	if head != null:
		# a shade below the horizon: the floor leads the eye in
		head.rotation.x = -0.045


## Kill the near lamps so the doorway is a bright cut in a dark wall, and leave
## one alive behind the monster so it is backlit.
func _light_it(rooms: Array) -> void:
	var lit := 0
	for i in mini(4, rooms.size()):
		var raw: Variant = rooms[i]["root"]
		if not is_instance_valid(raw):
			continue
		for l in (raw as Node3D).find_children("*", "OmniLight3D", true, false):
			var light := l as OmniLight3D
			if i <= 1:
				light.light_energy *= 0.22
			elif i == 2:
				light.light_energy *= 0.75
			else:
				light.light_energy *= 1.5
				lit += 1
	if lit == 0:
		return


## Title over the picture, same faces the menu uses.
func _title() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 120
	add_child(layer)

	# a floor-to-frame darkening so the type has something to sit on
	var vail := ColorRect.new()
	vail.set_anchors_preset(Control.PRESET_FULL_RECT)
	vail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var grad := GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.72))
	g.set_color(1, Color(0, 0, 0, 0.0))
	grad.gradient = g
	grad.fill_from = Vector2(0, 1)
	grad.fill_to = Vector2(0, 0.35)
	var tex := TextureRect.new()
	tex.texture = grad
	tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(tex)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	box.offset_left = 90
	box.offset_right = -90
	box.offset_top = -330
	box.offset_bottom = -70
	box.add_theme_constant_override("separation", 6)
	layer.add_child(box)

	var ar := Label.new()
	ar.text = "فيه وحش في دولابي"
	ar.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ar.add_theme_font_override("font", load("res://assets/fonts/NotoNaskhArabic.ttf"))
	ar.add_theme_font_size_override("font_size", 116)
	ar.add_theme_color_override("font_color", Color(0.96, 0.90, 0.80))
	ar.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	ar.add_theme_constant_override("outline_size", 10)
	box.add_child(ar)

	var en := Label.new()
	en.text = "THERE IS A MONSTER IN MY CLOSET"
	en.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	en.add_theme_font_override("font", load("res://assets/fonts/Amazdoomleft-epw3.ttf"))
	en.add_theme_font_size_override("font_size", 54)
	en.add_theme_color_override("font_color", Color(0.78, 0.20, 0.16))
	en.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	en.add_theme_constant_override("outline_size", 10)
	box.add_child(en)


func _shot(shot_name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await _wait(0.4)
	var img := get_viewport().get_texture().get_image()
	var path := out_dir.path_join(shot_name + ".png")
	img.save_png(path)
	print("saved ", path)
