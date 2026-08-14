extends SceneTree
## Dev-only: dumps every mesh in the house model (and the collider model) with
## world-space AABBs, one per line, so room layout can be reconstructed from
## data. Run: godot --headless --path . -s res://tools/dump_meshes.gd


func _init() -> void:
	_dump("res://assets/House/House/Models/house.fbx", "HOUSE")
	_dump("res://assets/House/House/Models/House_Colliders.fbx", "COLLIDERS")
	quit(0)


func _dump(path: String, tag: String) -> void:
	var ps: PackedScene = load(path)
	if ps == null:
		print(tag, " FAILED TO LOAD")
		return
	var root := ps.instantiate()
	var stack: Array = [[root, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var entry: Array = stack.pop_back()
		var node: Node = entry[0]
		var xform: Transform3D = entry[1]
		var local := xform
		if node is Node3D:
			local = xform * (node as Node3D).transform
		if node is MeshInstance3D:
			var aabb: AABB = local * (node as MeshInstance3D).get_aabb()
			var c := aabb.position + aabb.size * 0.5
			print("%s|%s|%.2f,%.2f,%.2f|%.2f,%.2f,%.2f" % [
				tag, node.name, c.x, c.y, c.z, aabb.size.x, aabb.size.y, aabb.size.z
			])
		for child in node.get_children():
			stack.push_back([child, local])
	root.free()
