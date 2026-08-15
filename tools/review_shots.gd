extends Node
## Self-review tool: boots the level scene, flies a camera through a fixed
## shot list, saves PNGs, quits. Run windowed (needs a GPU context):
##   godot --path . res://tools/ReviewShots.tscn
## Never shipped.

const SHOTS := [
	[Vector3(5.3, 4.95, -10.7), Vector3(6.7, 4.9, -9.3), "01_spawn_toward_closet"],
	[Vector3(6.0, 4.9, -10.5), Vector3(5.28, 4.7, -8.88), "02_bedroom_door_spill"],
	[Vector3(5.0, 4.9, -8.2), Vector3(1.5, 4.6, -8.9), "03_landing_bathroom_beacon"],
	[Vector3(1.7, 4.85, -9.0), Vector3(2.36, 4.15, -10.19), "04_bathroom_toy"],
	[Vector3(-1.3, 4.9, -9.9), Vector3(-2.94, 4.5, -8.73), "05_dads_door_glow"],
	[Vector3(6.42, 4.95, -12.3), Vector3(6.0, 5.8, -9.0), "06_bed_view"],
	[Vector3(3.2, 5.1, -5.6), Vector3(2.2, 5.0, -8.2), "07_landing_wide"],
	[Vector3(6.7, 4.8, -10.4), Vector3(6.68, 4.9, -9.33), "08_closet_closeup"],
	[Vector3(1.55, 4.75, -9.05), Vector3(2.36, 4.30, -10.19), "09_basket_toy"],
	[Vector3(4.4, 4.9, -8.35), Vector3(1.6, 4.3, -8.8), "10_player_path_beacon"],
]

var out_dir := ""


func _ready() -> void:
	out_dir = OS.get_environment("REVIEW_OUT")
	if out_dir.is_empty():
		out_dir = "user://review"
	AudioBus.unlock()
	var house := (load("res://real_world.tscn") as PackedScene).instantiate()
	add_child(house)
	var cam := Camera3D.new()
	cam.fov = 75.0
	add_child(cam)
	cam.make_current()
	_run(cam)


func _run(cam: Camera3D) -> void:
	# Let the director's fade-in finish and Act 0 settle.
	await get_tree().create_timer(2.4).timeout
	DirAccess.make_dir_recursive_absolute(out_dir)
	for shot: Array in SHOTS:
		cam.global_position = shot[0]
		cam.look_at(shot[1])
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().create_timer(0.3).timeout
		var img := get_viewport().get_texture().get_image()
		img.save_png(out_dir.path_join(String(shot[2]) + ".png"))
	get_tree().quit()
