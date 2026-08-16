extends Node

## Puts an OmniLight3D at every lamp mesh in the house, found by name, so
## nobody hand-places 26 lights or forgets one when furniture moves.
##
## Shadowless on purpose: the Compatibility renderer chokes on many shadowed
## lights, and the Doom filter's palette crush hides soft shadows anyway.

@export var house_path: NodePath = NodePath("../house")

@export_group("Ceiling fixtures (Focus_*)")
@export var ceiling_color := Color(1.0, 0.93, 0.78)
@export var ceiling_energy := 1.1
@export var ceiling_range := 3.5

@export_group("Desk and floor lamps (Desk_lamp*, Lamp_*)")
@export var lamp_color := Color(1.0, 0.85, 0.6)
@export var lamp_energy := 0.9
@export var lamp_range := 2.5

var count := 0
## Mesh name -> its light, so switches can find what they toggle.
var lights_by_mesh := {}


func get_light(mesh_name: String) -> OmniLight3D:
	return lights_by_mesh.get(mesh_name) as OmniLight3D


## Every ceiling light we made, by mesh name.
func ceiling_lights() -> Dictionary:
	var out := {}
	for k: String in lights_by_mesh.keys():
		if k.begins_with("Focus_"):
			out[k] = lights_by_mesh[k]
	return out


func _ready() -> void:
	var house := get_node_or_null(house_path)
	if house == null:
		push_warning("LampLights: no house at '%s'." % house_path)
		return

	for child in house.get_children():
		if not child is MeshInstance3D:
			continue
		var lamp_name: String = child.name
		if lamp_name.begins_with("Focus_"):
			_add_light(child, ceiling_color, ceiling_energy, ceiling_range, -0.25)
		elif lamp_name.begins_with("Desk_lamp") or lamp_name.begins_with("Lamp_"):
			_add_light(child, lamp_color, lamp_energy, lamp_range, 0.1)


func _add_light(mesh: MeshInstance3D, color: Color, energy: float, radius: float, y_offset: float) -> void:
	var center: Vector3 = mesh.global_transform * mesh.get_aabb().get_center()
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.omni_range = radius
	light.shadow_enabled = false
	add_child(light)
	light.global_position = center + Vector3(0, y_offset, 0)
	lights_by_mesh[String(mesh.name)] = light
	count += 1
