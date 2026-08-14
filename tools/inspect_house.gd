extends SceneTree
## Dev-only: prints the node tree and world-space bounds of the imported house
## model so level work can be planned without opening the editor.
## Run: godot --headless --path . -s res://tools/inspect_house.gd

const HOUSE := "res://assets/House/House/Models/house.fbx"


func _init() -> void:
	var ps: PackedScene = load(HOUSE)
	if ps == null:
		print("FAILED to load ", HOUSE)
		quit(1)
		return
	var root := ps.instantiate()
	var total := AABB()
	var first := true
	var mesh_count := 0

	var stack: Array = [[root, Transform3D.IDENTITY, 0]]
	while not stack.is_empty():
		var entry: Array = stack.pop_back()
		var node: Node = entry[0]
		var xform: Transform3D = entry[1]
		var depth: int = entry[2]
		var local := xform
		if node is Node3D:
			local = xform * (node as Node3D).transform
		var info := "%s%s (%s)" % ["  ".repeat(depth), node.name, node.get_class()]
		if node is MeshInstance3D:
			mesh_count += 1
			var aabb: AABB = (node as MeshInstance3D).get_aabb()
			var world_aabb := local * aabb
			info += "  aabb=%s size=%s" % [world_aabb.position, world_aabb.size]
			if first:
				total = world_aabb
				first = false
			else:
				total = total.merge(world_aabb)
		if depth <= 2:
			print(info)
		for child in node.get_children():
			stack.push_back([child, local, depth + 1])

	print("---")
	print("meshes: ", mesh_count)
	print("total bounds: pos=", total.position, " size=", total.size)
	root.free()
	quit(0)
