class_name Toy
extends Node3D
## The kid's bear (CC-BY, see assets/ATTRIBUTION.md). Scaled at runtime to
## plush size with its feet at this node's origin, so you place it where it
## stands.

const MODEL := preload("res://assets/toy/bear.glb")
## Plush size. The house is at 2.5m-door scale so keep him small.
const HEIGHT := 0.35

var _model: Node3D


func _ready() -> void:
	_model = MODEL.instantiate() as Node3D
	add_child(_model)
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(_model, meshes)
	if meshes.is_empty():
		push_warning("Toy: bear.glb has no meshes")
		return
	var world := MeshUtil.world_aabb(meshes[0])
	for i in range(1, meshes.size()):
		world = world.merge(MeshUtil.world_aabb(meshes[i]))
	var s := HEIGHT / maxf(world.size.y, 0.001)
	_model.scale = Vector3.ONE * s
	var center := (world.get_center() - global_position) * s
	var base_y := (world.position.y - global_position.y) * s
	_model.position -= Vector3(center.x, base_y, center.z)


static func _collect_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		_collect_meshes(child, out)
