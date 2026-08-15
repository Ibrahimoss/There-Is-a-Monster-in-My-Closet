extends Node3D
## The house at night. Visual model + collider model from the asset pack,
## night lighting built in code.
##
## Layout (from mesh AABB data, world space):
##   Upstairs floor y≈3.7  ·  ground floor y≈0.4  ·  stairs at (3.1, -6.8)
##   Kid's bedroom: bed_02 (6.4, 4.3, -11.8), closet_door_03 (6.7, 5.0, -9.3),
##   alarm clock nightstand (7.1, 4.6, -13.0), window (5.4, 5.4, -13.7)
##   Small bathroom upstairs: washbasin (2.4, 4.5, -9.4)
##   Parents' room: bed_01 (-2.5, 4.3, -5.9) - stays locked
##
## No directional light on purpose: without shadow maps it would light every
## interior wall evenly. Everything is local light pools instead (window
## spills, hallway light, bedside lamp).

const HOUSE_MODEL := preload("res://assets/House/House/Models/house.fbx")
const HOUSE_COLLIDERS := preload("res://assets/House/House/Models/House_Colliders.fbx")
const PLAYER_SCENE := preload("res://scenes/player/Player.tscn")

const MOON := Color(0.58, 0.66, 0.92)
const WARM := Color(1.0, 0.78, 0.50)

## Just inside upstairs windows - moonlight pooling on the floor. The parents'
## room is behind a locked door now, so no pool there.
const WINDOW_POOLS: Array[Vector3] = [
	Vector3(5.4, 5.2, -13.2),   # kid's bedroom window
	Vector3(9.2, 5.2, -6.0),    # bathtub bathroom window
	Vector3(9.2, 1.8, -6.0),    # ground floor window
]

## Stair gate: closes the gap in the east banister where the top step is.
const GATE_POS := Vector3(4.93, 3.73, -5.41)
const GATE_LENGTH := 1.22

## Hall light levels. LOW is act 0: enough to see the east landing, dim enough
## that the lit bathroom down the west hall is the brightest thing in view.
## FULL is dad switching it on in act 1.
const HALL_LOW := 0.5
const HALL_FULL := 1.1

var _player: CharacterBody3D
var _house_visual: Node3D
var _doors: DoorSystem
var _hall_light: OmniLight3D
var _hall_level := HALL_LOW
var _bedside_lamp: OmniLight3D
var _gate: StairGate
var _director: OpeningDirector
var _time := 0.0


func _ready() -> void:
	_build_environment()
	_build_house()
	_build_colliders()
	_build_doors()
	_build_gate()
	_build_lights()
	_spawn_player()
	HUD.set_active(true)
	# quiet night ambience, keep it low
	AudioBus.ambience("room_tone", 3.0, -16.0)
	# The director owns the fade-in and everything scripted from here on.
	_director = OpeningDirector.new()
	_director.name = "OpeningDirector"
	_director.house = self
	_director.doors = _doors
	_director.player = _player
	add_child(_director)
	_director.run()


func _process(delta: float) -> void:
	_time += delta
	# Tiny flicker so the house never feels frozen. Gated on visibility so the
	# director can turn the light off without the flicker re-enabling it.
	if _hall_light.visible:
		_hall_light.light_energy = _hall_level * (
			0.94 + 0.04 * sin(_time * 2.7) + 0.02 * sin(_time * 6.3 + 1.2)
		)


func _build_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.004, 0.005, 0.010)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.10, 0.12, 0.18)
	env.ambient_light_energy = 0.20
	env.fog_enabled = true
	env.fog_light_color = Color(0.010, 0.011, 0.018)
	env.fog_density = 0.035
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 0.90
	we.environment = env
	add_child(we)


func _build_house() -> void:
	_house_visual = HOUSE_MODEL.instantiate() as Node3D
	_house_visual.name = "HouseVisual"
	add_child(_house_visual)
	_patch_emissives()


## The pack ships _Emissor maps its FBX materials never wire up. Alarm clock
## faces get theirs so they glow, only light in the bedroom after lights-out.
func _patch_emissives() -> void:
	var patches := [
		["Alarm_clock_01", "res://assets/House/House/Textures/Alarm_clock_01_Emissor.png"],
		["Alarm_clock", "res://assets/House/House/Textures/Alarm_clock_Emissor.png"],
	]
	var stack: Array[Node] = [_house_visual]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.push_back(child)
		if not (node is MeshInstance3D):
			continue
		var mi := node as MeshInstance3D
		for patch: Array in patches:
			if not String(mi.name).begins_with(String(patch[0])):
				continue
			var tex := load(String(patch[1])) as Texture2D
			for s in mi.mesh.get_surface_count():
				var mat := mi.get_active_material(s)
				if mat is StandardMaterial3D:
					var dup := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
					dup.emission_enabled = true
					dup.emission_texture = tex
					dup.emission = Color.WHITE
					dup.emission_energy_multiplier = 1.5
					mi.set_surface_override_material(s, dup)
			break


func _build_doors() -> void:
	_doors = DoorSystem.new()
	_doors.name = "Doors"
	add_child(_doors)
	_doors.build(_house_visual)


func _build_gate() -> void:
	var rail := _house_visual.find_child("railing_ladders_01", true, false) as MeshInstance3D
	var wood: Material = rail.get_active_material(0) if rail else null
	_gate = StairGate.new()
	_gate.name = "StairGate"
	add_child(_gate)
	_gate.global_position = GATE_POS
	_gate.setup(GATE_LENGTH, wood)


## The collider FBX carries floors, the wall shell, the stair ramp and
## per-furniture boxes as plain meshes. Convert each to a static trimesh body
## and hide the meshes.
func _build_colliders() -> void:
	var root := HOUSE_COLLIDERS.instantiate()
	add_child(root)
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.push_back(child)
		if node is MeshInstance3D:
			var mi := node as MeshInstance3D
			mi.visible = false
			var shape := mi.mesh.create_trimesh_shape()
			if shape:
				var body := StaticBody3D.new()
				body.collision_layer = 1
				body.collision_mask = 0
				var cs := CollisionShape3D.new()
				cs.shape = shape
				body.add_child(cs)
				mi.add_child(body)


func _build_lights() -> void:
	# Cool pools under the windows.
	for pos in WINDOW_POOLS:
		var moon := OmniLight3D.new()
		moon.light_color = MOON
		moon.light_energy = 0.55
		moon.omni_range = 3.6
		moon.omni_attenuation = 1.7
		moon.shadow_enabled = false
		moon.position = pos
		add_child(moon)

	# Hallway light, at the corner where the landing turns down past the
	# stairwell: reaches the kid's door, the stair gate and the far bedroom
	# door, and falls off before the west hall so the lit bathroom down there
	# stays the brightest thing you can see from the bedroom door.
	_hall_light = OmniLight3D.new()
	_hall_light.light_color = WARM
	_hall_light.light_energy = HALL_LOW
	_hall_light.omni_range = 5.2
	_hall_light.omni_attenuation = 1.6
	_hall_light.shadow_enabled = false
	_hall_light.position = Vector3(4.7, 5.8, -6.9)
	add_child(_hall_light)

	# Bedside lamp in the kid's room. Range reaches the closet door so the
	# closet reads as a door while the lamp is on, not a black slab.
	_bedside_lamp = OmniLight3D.new()
	_bedside_lamp.light_color = Color(1.0, 0.72, 0.42)
	_bedside_lamp.light_energy = 0.9
	_bedside_lamp.omni_range = 5.6
	_bedside_lamp.omni_attenuation = 1.55
	_bedside_lamp.shadow_enabled = false
	_bedside_lamp.position = Vector3(7.1, 4.9, -13.0)
	add_child(_bedside_lamp)


func set_hall_light(on: bool) -> void:
	_hall_light.visible = on


## Dad's hand on the switch: LOW is the night setting, FULL is him turning it
## up when he comes to the door.
func set_hall_light_full(full: bool) -> void:
	_hall_level = HALL_FULL if full else HALL_LOW


func set_bedside_lamp(on: bool) -> void:
	_bedside_lamp.visible = on


func _spawn_player() -> void:
	_player = PLAYER_SCENE.instantiate()
	# Beside the bed, facing the closet across the room.
	_player.position = Vector3(5.3, 3.85, -10.7)
	_player.rotation_degrees = Vector3(0, 227, 0)
	add_child(_player)
	_player.target_changed.connect(_on_target_changed)


func _on_target_changed(target: Interactable) -> void:
	if target:
		HUD.show_prompt(target.get_prompt())
	else:
		HUD.hide_prompt()
