@tool
extends EditorScenePostImport

# Leave empty to give EVERY mesh collision (correct for House_Colliders.fbx).
# Add lowercase keywords to filter, e.g. ["wall", "floor", "roof"].
const INCLUDE: Array[String] = []

# false = trimesh (exact, static only). true = convex hull (for movable bodies).
const USE_CONVEX := false


func _post_import(scene: Node) -> Node:
	print("=== IMPORT SCRIPT RAN on %s ===" % scene.name)

	var meshes: Array[MeshInstance3D] = []
	_collect(scene, meshes)
	print("found %d MeshInstance3D nodes with a mesh" % meshes.size())

	var made := 0
	for m in meshes:
		if not _wanted(m.name):
			continue
		if USE_CONVEX:
			m.create_convex_collision(true, true)
		else:
			m.create_trimesh_collision()
		if m.get_child_count() > 0:
			_own(m.get_child(m.get_child_count() - 1), scene)
		made += 1

	print("collision added to %d meshes" % made)
	return scene


func _collect(n: Node, out: Array[MeshInstance3D]) -> void:
	if n is MeshInstance3D and n.mesh != null:
		out.append(n)
	for c in n.get_children():
		_collect(c, out)


func _wanted(nm: String) -> bool:
	if INCLUDE.is_empty():
		return true
	var l := nm.to_lower()
	for k in INCLUDE:
		if l.contains(k):
			return true
	return false


func _own(n: Node, o: Node) -> void:
	n.owner = o
	for c in n.get_children():
		_own(c, o)
