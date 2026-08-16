extends Node
## Headless door test on the real level: for every Door in real_world.tscn,
## checks the player is blocked while it is shut, then opens it from each side
## the way a player would (panel swings away from them) and pushes the player
## through. Also reports if the open panel ends up inside walls or furniture.
## Run:
##   godot --headless --path . res://tools/DoorWalkTest.tscn
## Prints DOORS OK / DOORS FAIL. Never shipped.

const LEVEL := "res://real_world.tscn"
const PUSH_SPEED := 1.6
const PUSH_TIME := 3.0
## Shrink the panel box by this much per axis before the overlap query so
## grazing the jamb or the floor does not count.
const OVERLAP_SHRINK := 0.06

var _level: Node
var _player: CharacterBody3D
var _fail := 0


func _ready() -> void:
	_run()


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _push(dir: Vector3, seconds: float) -> Vector3:
	var t := 0.0
	while t < seconds:
		_player.velocity.x = dir.x * PUSH_SPEED
		_player.velocity.z = dir.z * PUSH_SPEED
		_player.velocity.y -= 18.0 * get_physics_process_delta_time()
		_player.move_and_slide()
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	return _player.global_position


func _body_of(door: Door) -> AnimatableBody3D:
	for c in door.get_children():
		if c is AnimatableBody3D:
			return c as AnimatableBody3D
	return null


func _overlaps_static(door: Door) -> Array:
	var body := _body_of(door)
	if body == null:
		return ["no body"]
	var shape_node: CollisionShape3D = null
	for c in body.get_children():
		if c is CollisionShape3D:
			shape_node = c as CollisionShape3D
			break
	if shape_node == null or not (shape_node.shape is BoxShape3D):
		return []
	var src := shape_node.shape as BoxShape3D
	var world_scale := shape_node.global_transform.basis.get_scale().abs()
	var box := BoxShape3D.new()
	# shrink in world units, the shape lives under the door's 100x scale
	box.size = (src.size - Vector3(
		OVERLAP_SHRINK / maxf(world_scale.x, 0.001),
		OVERLAP_SHRINK / maxf(world_scale.y, 0.001),
		OVERLAP_SHRINK / maxf(world_scale.z, 0.001))).max(Vector3.ONE * 0.0001)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = box
	q.transform = shape_node.global_transform
	q.collision_mask = 1
	q.margin = 0.0
	q.exclude = [body.get_rid(), _player.get_rid()]
	var hits := _player.get_world_3d().direct_space_state.intersect_shape(q, 8)
	var names := {}
	for h: Dictionary in hits:
		var n: Node = h["collider"]
		var key := String(n.get_parent().name if n.get_parent() else n.name)
		names[key] = true
	return names.keys()


func _test_door(door: Door) -> void:
	var pname := String(door.name)
	var aabb := MeshUtil.world_aabb(door)
	var c: Vector3 = door._shut.origin + door._hinge_to_center
	var normal: Vector3 = door._normal
	var floor_y := aabb.position.y + 0.15
	var a := Vector3(c.x, floor_y, c.z) - normal * 0.9
	var b := Vector3(c.x, floor_y, c.z) + normal * 0.9

	# start shut, whatever the level left it at (the bathroom door hangs ajar)
	door.snap_open(false)
	await get_tree().physics_frame

	if door.locked:
		_player.teleport_to(a)
		var p := await _push(normal, PUSH_TIME)
		if p.y < a.y - 0.6:
			print("  %-16s locked: no floor at test spot, skipped" % pname)
			return
		var passed := (p - c).dot(normal) > 0.3
		print("  %-16s locked: %s" % [pname, "FAIL walked through" if passed else "blocks, ok"])
		if passed:
			_fail += 1
		return

	var overlaps_closed := _overlaps_static(door)
	_player.teleport_to(a)
	var p0 := await _push(normal, PUSH_TIME)
	if p0.y < a.y - 0.6:
		print("  %-16s no floor at test spot, skipped" % pname)
		return
	var through_closed := (p0 - c).dot(normal) > 0.3

	# open from side A the way the player would, walk A -> B
	door._dir = door.swing_away_from(a)
	door.set_open(true)
	await _wait(door.swing_time + 0.3)
	var overlaps_a := _overlaps_static(door)
	_player.teleport_to(a)
	var p1 := await _push(normal, PUSH_TIME)
	var pass_ab := (p1 - c).dot(normal) > 0.3
	door.set_open(false)
	await _wait(door.swing_time + 0.3)

	# open from side B, walk B -> A
	door._dir = door.swing_away_from(b)
	door.set_open(true)
	await _wait(door.swing_time + 0.3)
	var overlaps_b := _overlaps_static(door)
	_player.teleport_to(b)
	var p2 := await _push(-normal, PUSH_TIME)
	var pass_ba := (p2 - c).dot(normal) < -0.3
	door.set_open(false)
	await _wait(door.swing_time + 0.3)

	_player.teleport_to(a)
	var p3 := await _push(normal, PUSH_TIME)
	var through_reclosed := (p3 - c).dot(normal) > 0.3

	# open INTO the player standing in the swing: they must get shoved out,
	# never left inside the panel
	var toward := -door.swing_away_from(a)
	_player.teleport_to(Vector3(c.x, floor_y, c.z) - normal * 0.45)
	await get_tree().physics_frame
	door._dir = toward
	door.set_open(true)
	await _wait(door.swing_time + 0.5)
	var inside := _panel_overlaps_player(door)
	door.set_open(false)
	await _wait(door.swing_time + 0.3)

	var swing_clean := (not overlaps_closed.is_empty()) \
		or (overlaps_a.is_empty() and overlaps_b.is_empty())
	var ok := (not through_closed) and pass_ab and pass_ba and (not through_reclosed) and swing_clean and not inside
	if not ok:
		_fail += 1
	print("  %-16s closed:%s  A>B:%s  B>A:%s  reclosed:%s  into-player:%s  closed-pose hits:%s  open-from-A hits:%s  open-from-B hits:%s" % [
		pname,
		"FAIL(passes)" if through_closed else "blocks",
		"ok" if pass_ab else "FAIL",
		"ok" if pass_ba else "FAIL",
		"FAIL(passes)" if through_reclosed else "blocks",
		"FAIL(stuck in panel)" if inside else "shoved",
		str(overlaps_closed) if not overlaps_closed.is_empty() else "none",
		str(overlaps_a) if not overlaps_a.is_empty() else "none",
		str(overlaps_b) if not overlaps_b.is_empty() else "none",
	])


func _panel_overlaps_player(door: Door) -> bool:
	var body := _body_of(door)
	if body == null:
		return false
	var shape_node: CollisionShape3D = null
	for c in body.get_children():
		if c is CollisionShape3D:
			shape_node = c as CollisionShape3D
			break
	if shape_node == null:
		return false
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape_node.shape
	q.transform = shape_node.global_transform
	q.collision_mask = 2
	q.margin = 0.0
	var hits := _player.get_world_3d().direct_space_state.intersect_shape(q, 4)
	for h: Dictionary in hits:
		if h["collider"] == _player:
			return true
	return false


func _collect(node: Node, out: Array[Door]) -> void:
	if node is Door:
		out.append(node as Door)
	for c in node.get_children():
		_collect(c, out)


func _run() -> void:
	AudioBus.unlock()
	_level = (load(LEVEL) as PackedScene).instantiate()
	add_child(_level)
	await _wait(1.0)
	_player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	if _player == null:
		print("DOORS FAIL: no player in the level")
		get_tree().quit(1)
		return
	_player.can_move = false
	_player.cinematic = false

	var doors: Array[Door] = []
	_collect(_level, doors)
	print("DOOR WALK TEST: %d doors" % doors.size())
	if doors.is_empty():
		_fail += 1
	for door in doors:
		await _test_door(door)

	if _fail == 0:
		print("DOORS OK")
		get_tree().quit(0)
	else:
		print("DOORS FAIL: %d door(s)" % _fail)
		get_tree().quit(1)
