extends Node3D
## Proving ground for the web export, the interact loop, and - now - the look.
##
## Lit the way the real game will be lit: near-black with distance fog, one
## warm door-gap as the hero light, one small lamp pool. No directional light,
## no shadows. If it reads here under GL Compatibility, it reads everywhere.
##
## Still throwaway - replaced by the house greybox. Nothing should depend on
## this file.

const WALL_COLOR := Color(0.13, 0.12, 0.15)
const FLOOR_COLOR := Color(0.09, 0.085, 0.10)
const WARM := Color(1.0, 0.78, 0.50)

var _player: CharacterBody3D
var _door_light: OmniLight3D
var _time := 0.0


func _ready() -> void:
	_build_environment()
	_build_room()
	_build_door_gap()
	_build_lamp()
	_spawn_player()
	_spawn_test_interactable()
	HUD.set_active(true)
	Fade.fade_in(1.0)


func _process(delta: float) -> void:
	_time += delta
	# The light behind the door is not steady. Nothing dramatic - a lamp on an
	# old circuit, or something moving in front of it very slowly.
	_door_light.light_energy = 1.5 * (
		0.90 + 0.055 * sin(_time * 3.2) + 0.035 * sin(_time * 7.9 + 1.4)
		+ 0.02 * sin(_time * 19.0)
	)


func _build_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.004, 0.004, 0.007)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.10, 0.11, 0.17)
	env.ambient_light_energy = 0.22
	# Distance fog is the whole atmosphere budget under GL Compatibility -
	# volumetric fog does not exist there. This is also what makes the beams
	# read once the eye system lands.
	env.fog_enabled = true
	env.fog_light_color = Color(0.012, 0.012, 0.020)
	env.fog_density = 0.055
	# Gentle contrast curve; Compatibility has no real tonemapping to lean on.
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 0.92
	we.environment = env
	add_child(we)


func _build_room() -> void:
	_add_box(Vector3(20, 0.5, 20), Vector3(0, -0.25, 0), FLOOR_COLOR)
	_add_box(Vector3(20, 0.5, 20), Vector3(0, 4.25, 0), FLOOR_COLOR)  # ceiling
	_add_box(Vector3(20, 4, 0.5), Vector3(0, 2, -10), WALL_COLOR)
	_add_box(Vector3(20, 4, 0.5), Vector3(0, 2, 10), WALL_COLOR)
	_add_box(Vector3(0.5, 4, 20), Vector3(-10, 2, 0), WALL_COLOR)
	_add_box(Vector3(0.5, 4, 20), Vector3(10, 2, 0), WALL_COLOR)

	# Crates at child scale - sanity check that 1.10 m eye height reads as
	# small, and lean has something to peek around.
	_add_box(Vector3(1, 1, 1), Vector3(-3, 0.5, -4), WALL_COLOR)
	_add_box(Vector3(1, 1, 1), Vector3(-3, 1.5, -4), WALL_COLOR)
	_add_box(Vector3(1, 1, 1), Vector3(-1.6, 0.5, -4.4), WALL_COLOR)
	_add_box(Vector3(2, 0.1, 1), Vector3(4, 1.2, -3), WALL_COLOR)


## A door standing ajar in the far wall, warm light leaking through the crack.
## This is the hero image of the whole game, proven in greybox.
func _build_door_gap() -> void:
	var z := -9.6
	# Frame sides and lintel, slightly proud of the wall.
	_add_box(Vector3(0.9, 2.1, 0.14), Vector3(-1.05, 1.05, z), WALL_COLOR)
	_add_box(Vector3(0.9, 2.1, 0.14), Vector3(1.05, 1.05, z), WALL_COLOR)
	_add_box(Vector3(3.0, 0.5, 0.14), Vector3(0, 2.35, z), WALL_COLOR)

	# The door panel, open a few degrees.
	var panel := _add_box(Vector3(1.16, 2.1, 0.06), Vector3.ZERO, Color(0.16, 0.13, 0.11))
	panel.position = Vector3(-0.58, 1.05, z + 0.04)
	panel.rotation.y = deg_to_rad(-7.0)

	# The light in the crack: an emissive sliver plus one warm omni. The
	# sliver is what the eye sees; the omni is what the room feels.
	var sliver := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.055, 2.05)
	sliver.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = WARM
	mat.emission_enabled = true
	mat.emission = WARM
	mat.emission_energy_multiplier = 2.0
	sliver.material_override = mat
	sliver.position = Vector3(0.52, 1.05, z + 0.02)
	add_child(sliver)

	_door_light = OmniLight3D.new()
	_door_light.light_color = WARM
	_door_light.light_energy = 1.5
	_door_light.omni_range = 7.0
	_door_light.omni_attenuation = 1.6
	_door_light.shadow_enabled = false
	_door_light.position = Vector3(0.5, 1.1, z + 0.6)
	add_child(_door_light)


## A small cool lamp pool on the other side of the room, so the space has two
## temperatures and the darkness between them.
func _build_lamp() -> void:
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(0.55, 0.62, 0.85)
	lamp.light_energy = 0.5
	lamp.omni_range = 4.5
	lamp.omni_attenuation = 1.8
	lamp.shadow_enabled = false
	lamp.position = Vector3(4.0, 1.6, -3.0)
	add_child(lamp)


func _add_box(size: Vector3, pos: Vector3, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	body.collision_layer = 1
	body.collision_mask = 0

	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.95
	mesh.material_override = mat
	body.add_child(mesh)

	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)

	add_child(body)
	return body


func _spawn_player() -> void:
	_player = preload("res://scenes/player/Player.tscn").instantiate()
	_player.position = Vector3(0, 0.2, 6)
	add_child(_player)
	_player.target_changed.connect(_on_target_changed)


func _spawn_test_interactable() -> void:
	var it := Interactable.new()
	it.name = "TestToy"
	it.prompt_ar = "خذها"
	it.prompt_en = "Take it"
	it.position = Vector3(-2.3, 1.15, -4.2)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.5, 0.5, 0.5)
	shape.shape = box
	it.add_child(shape)

	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(0.28, 0.28, 0.28)
	mesh.mesh = box_mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.40, 0.28)
	mat.emission_enabled = true
	mat.emission = Color(0.55, 0.40, 0.28)
	mat.emission_energy_multiplier = 0.25
	mesh.material_override = mat
	it.add_child(mesh)

	it.interacted.connect(_on_test_interacted)
	add_child(it)


func _on_target_changed(target: Interactable) -> void:
	if target:
		HUD.show_prompt(target.get_prompt())
	else:
		HUD.hide_prompt()


func _on_test_interacted(_by: Node3D) -> void:
	# Exercises the whole text path: dialogue lookup, speaker label, Arabic
	# shaping and the English gloss underneath.
	Subtitles.show_line("dad_reassure", 3.5)
