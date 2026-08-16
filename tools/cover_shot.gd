extends Node
## Cover art: the start screen with nothing on it but the room and the title.
##
## The menu already frames the bedroom, the closet and the lamp exactly the way
## the game wants to be seen, so the cover is that shot with the answers, the
## dad line and the controls strip taken out. Run windowed -- it needs a GPU
## context, headless cannot screenshot:
##   godot --path . res://tools/CoverShot.tscn
## REVIEW_OUT picks the folder, MENU_VIEW="x,y,z,yaw,pitch,fov" reframes it.

const SHOT := Vector2i(1920, 1080)
## The menu settles over a few seconds -- the lamp comes up, the closet drifts.
## Shoot once it has arrived, not during.
const SETTLE := 5.6

var out_dir := ""


func _ready() -> void:
	out_dir = OS.get_environment("REVIEW_OUT")
	if out_dir.is_empty():
		out_dir = "user://cover"
	DirAccess.make_dir_recursive_absolute(out_dir)
	get_window().size = SHOT
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


func _run(menu: Node) -> void:
	await get_tree().create_timer(SETTLE).timeout
	_strip(menu)
	await get_tree().create_timer(0.6).timeout
	await _shot("cover")
	get_tree().quit()


## Everything that is a menu rather than a picture. Buttons go with their rows,
## so the title does not end up sitting over a column of gaps.
func _strip(menu: Node) -> void:
	var buttons: Array = menu.get("_reply_buttons")
	for b in buttons:
		if not (b is Control):
			continue
		var row: Node = (b as Control).get_parent()
		if row is Control and row != menu:
			(row as Control).visible = false
		else:
			(b as Control).visible = false
	# the dad line and the controls strip are labels rather than buttons: hide
	# anything left in the text layer that is not the title block
	var layer: Node = menu.get("_text")
	var keep: Node = menu.get("_title_flick")
	if layer == null:
		return
	for child in layer.get_children():
		if child is Control and not _holds(child, keep):
			(child as Control).visible = false


## Is `needle` this node, or somewhere beneath it.
func _holds(node: Node, needle: Node) -> bool:
	var n: Node = needle
	while n != null:
		if n == node:
			return true
		n = n.get_parent()
	return false


func _shot(shot_name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.3).timeout
	var img := get_viewport().get_texture().get_image()
	var path := out_dir.path_join(shot_name + ".png")
	img.save_png(path)
	print("saved ", path)
