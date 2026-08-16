extends Node
## Self-review tool for the start screen: boots it, saves PNGs of the reveal,
## the settled frame, each answer hovered, the options and credits pages and
## the walk into the closet, then quits. Run windowed (needs a GPU context):
##   godot --path . res://tools/MenuShot.tscn
## MENU_VIEW="x,y,z,yaw,pitch,fov" tries another camera. MENU_QUICK=1 only
## shoots the settled frame. Never shipped.

var out_dir := ""


func _ready() -> void:
	out_dir = OS.get_environment("REVIEW_OUT")
	if out_dir.is_empty():
		out_dir = "user://review"
	get_window().size = Vector2i(1280, 720)
	var menu := (load("res://scenes/ui/StartScreen.tscn") as PackedScene).instantiate()
	var view := OS.get_environment("MENU_VIEW")
	if not view.is_empty():
		var p := view.split(",")
		if p.size() >= 6:
			menu.set("eye", Vector3(float(p[0]), float(p[1]), float(p[2])))
			menu.set("eye_yaw", float(p[3]))
			menu.set("eye_pitch", float(p[4]))
			menu.set("fov", float(p[5]))
	add_child(menu)
	_run(menu)


func _shot(name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))


func _hover(btn: Button) -> void:
	var vp := get_viewport()
	var c := btn.get_global_rect().get_center()
	vp.warp_mouse(c)
	var ev := InputEventMouseMotion.new()
	ev.position = c
	ev.global_position = c
	Input.parse_input_event(ev)


func _unhover() -> void:
	var vp := get_viewport()
	var c := Vector2(vp.get_visible_rect().size.x * 0.5, 40.0)
	vp.warp_mouse(c)
	var ev := InputEventMouseMotion.new()
	ev.position = c
	ev.global_position = c
	Input.parse_input_event(ev)


func _run(menu: Node) -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	var quick := not OS.get_environment("MENU_QUICK").is_empty()
	await get_tree().create_timer(0.9).timeout
	if not quick:
		await _shot("menu_1_reveal")
	await get_tree().create_timer(4.6).timeout
	await _shot("menu_2_settled")
	if quick:
		get_tree().quit()
		return
	var buttons: Array = menu.get("_reply_buttons")
	var names: Array[String] = ["begin", "options", "credits", "quit"]
	for i in buttons.size():
		_hover(buttons[i])
		await get_tree().create_timer(1.6).timeout
		await _shot("menu_3_hover_" + names[i])
		_unhover()
		await get_tree().create_timer(2.4).timeout
	# options page
	menu.call("_open_panel", 1)
	await get_tree().create_timer(4.2).timeout
	await _shot("menu_4_options")
	menu.call("_close_panel")
	await get_tree().create_timer(3.6).timeout
	menu.call("_open_panel", 2)
	await get_tree().create_timer(4.2).timeout
	await _shot("menu_5_credits")
	menu.call("_close_panel")
	await get_tree().create_timer(3.6).timeout
	# the walk in
	# quit before the scene change lands, or the game runs on with no one watching
	menu.call("_on_begin")
	await get_tree().create_timer(2.0).timeout
	await _shot("menu_6_begin_a")
	await get_tree().create_timer(0.9).timeout
	await _shot("menu_6_begin_b")
	await get_tree().create_timer(0.7).timeout
	await _shot("menu_6_begin_c")
	get_tree().quit()
