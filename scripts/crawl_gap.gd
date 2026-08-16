extends MeshInstance3D

## Debris you get past by ducking.
##
## Put this on the debris mesh. Walk near it and the kid works out he has to
## duck; look at it and the key prompt appears; hold crouch and its collision
## drops away so you can crawl through. Stand up and it is solid again.

signal squeezed_through

@export_group("Prompt")
## Said once, the first time he gets close.
@export var hint_caption := "duck"
## Shown on the HUD while he is looking at it.
@export var prompt_text := "Duck"
@export var prompt_key := "CTRL"
## Metres. Inside this he is close enough to be told to duck.
@export var near_distance := 3.5
## Degrees off centre screen that counts as looking at it.
@export_range(5.0, 90.0, 1.0, "suffix:°") var look_cone := 35.0

@export_group("Crouch")
## Input action that opens the gap.
@export var crouch_action := "crouch"
## Only let him through when he is actually close, so crouching elsewhere
## does not quietly unlock debris across the level.
@export var open_distance := 4.0

var _player: Node3D
var _bodies: Array[CollisionObject3D] = []
var _layers: Array[int] = []
var _open := false
var _hinted := false
var _prompting := false


func _ready() -> void:
	for b in find_children("*", "CollisionObject3D", true, false):
		var co := b as CollisionObject3D
		_bodies.append(co)
		_layers.append(co.collision_layer)
	if _bodies.is_empty():
		push_warning("CrawlGap on '%s': no collider to open." % name)
	_player = get_tree().get_first_node_in_group("player") as Node3D


func _process(_dt: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
		return

	var centre := _centre()
	var gap := _player.global_position.distance_to(centre)

	# close enough to notice the problem
	if gap <= near_distance and not _hinted:
		_hinted = true
		_say(hint_caption)

	_set_prompt(gap <= near_distance and _looking_at(centre))
	_set_open(gap <= open_distance and Input.is_action_pressed(crouch_action))


## Collision off while crouched, back on when he stands. Layers are stored
## rather than assumed, so whatever the debris was set to is what returns.
func _set_open(open: bool) -> void:
	if open == _open:
		return
	_open = open
	for i in _bodies.size():
		var co := _bodies[i]
		if is_instance_valid(co):
			co.collision_layer = 0 if open else _layers[i]
	if open:
		squeezed_through.emit()


func _set_prompt(on: bool) -> void:
	if on == _prompting:
		return
	_prompting = on
	var hud := get_node_or_null("/root/HUD")
	if hud == null:
		return
	if on and hud.has_method("show_prompt"):
		hud.show_prompt(prompt_text, prompt_key)
	elif not on and hud.has_method("hide_prompt"):
		hud.hide_prompt()


func _looking_at(point: Vector3) -> bool:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return false
	var to_it: Vector3 = point - cam.global_position
	if to_it.length_squared() < 0.001:
		return true
	return rad_to_deg((-cam.global_basis.z).angle_to(to_it.normalized())) <= look_cone


func _centre() -> Vector3:
	return global_transform * get_aabb().get_center()


func _say(text: String) -> void:
	var scene: Node = get_tree().current_scene
	if scene == null:
		scene = self
		while scene.get_parent() != null and scene.get_parent() != get_tree().root:
			scene = scene.get_parent()
	var ui := scene.find_child("dialouge ui", true, false)
	if ui != null and ui.has_method("play"):
		ui.play([text])
