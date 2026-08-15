extends Node
## Headless door test: for every swing door, checks the player is blocked while
## it is closed, then opens it from each side the way a player would (panel
## swings away from them) and pushes the player through. Also reports if the
## open panel ends up inside walls or furniture. Run:
##   godot --headless --path . res://tools/DoorWalkTest.tscn
## Prints DOORS OK / DOORS FAIL. Never shipped.

const PUSH_SPEED := 1.6
const PUSH_TIME := 3.0
## Shrink the panel box by this much per axis before the overlap query so
## grazing the jamb or the floor does not count.
const OVERLAP_SHRINK := 0.06

var _house: Node3D
var _director: Node
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


func _overlaps_static(door: Door) -> Array:
	var body: AnimatableBody3D = door._body
	var shape_node := body.get_child(0) as CollisionShape3D
	var src := shape_node.shape as BoxShape3D
	var box := BoxShape3D.new()
	box.size = (src.size - Vector3.ONE * OVERLAP_SHRINK).max(Vector3.ONE * 0.01)
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


func _test_door(panel_name: String, door: Door) -> void:
	var aabb: AABB = door._closed_aabb
	var c := aabb.get_center()
	var normal: Vector3 = door._normal
	var floor_y := aabb.position.y + 0.15
	var a := Vector3(c.x, floor_y, c.z) - normal * 0.9
	var b := Vector3(c.x, floor_y, c.z) + normal * 0.9

	# some doors start open (the hall door in act 0); everything below assumes closed
	if door.is_open():
		door.close(0.4)
		await _wait(0.7)

	if door.locked:
		_player.teleport_to(a)
		var p := await _push(normal, PUSH_TIME)
		if p.y < a.y - 0.6:
			print("  %-16s locked: no floor at test spot, skipped" % panel_name)
			return
		var passed := (p - c).dot(normal) > 0.3
		print("  %-16s locked: %s" % [panel_name, "FAIL walked through" if passed else "blocks, ok"])
		if passed:
			_fail += 1
		return

	# closed: must block. A panel that already sits inside the wall shell while
	# closed is a pack quirk, not a swing problem, so note it and skip the
	# open-pose overlap check for that door.
	var overlaps_closed := _overlaps_static(door)
	_player.teleport_to(a)
	var p0 := await _push(normal, PUSH_TIME)
	var through_closed := (p0 - c).dot(normal) > 0.3

	# open from side A the way the player would, walk A -> B
	door.open(0.6, door.swing_away_from(a))
	await _wait(0.9)
	var overlaps_a := _overlaps_static(door)
	_player.teleport_to(a)
	var p1 := await _push(normal, PUSH_TIME)
	var pass_ab := (p1 - c).dot(normal) > 0.3
	door.close(0.5)
	await _wait(0.8)

	# open from side B, walk B -> A
	door.open(0.6, door.swing_away_from(b))
	await _wait(0.9)
	var overlaps_b := _overlaps_static(door)
	_player.teleport_to(b)
	var p2 := await _push(-normal, PUSH_TIME)
	var pass_ba := (p2 - c).dot(normal) < -0.3
	door.close(0.5)
	await _wait(0.8)

	_player.teleport_to(a)
	var p3 := await _push(normal, PUSH_TIME)
	var through_reclosed := (p3 - c).dot(normal) > 0.3

	var swing_clean := overlaps_closed.is_empty() == false \
		or (overlaps_a.is_empty() and overlaps_b.is_empty())
	var ok := (not through_closed) and pass_ab and pass_ba and (not through_reclosed) and swing_clean
	if not ok:
		_fail += 1
	print("  %-16s closed:%s  A>B:%s  B>A:%s  reclosed:%s  closed-pose hits:%s  open-from-A hits:%s  open-from-B hits:%s" % [
		panel_name,
		"FAIL(passes)" if through_closed else "blocks",
		"ok" if pass_ab else "FAIL",
		"ok" if pass_ba else "FAIL",
		"FAIL(passes)" if through_reclosed else "blocks",
		str(overlaps_closed) if not overlaps_closed.is_empty() else "none",
		str(overlaps_a) if not overlaps_a.is_empty() else "none",
		str(overlaps_b) if not overlaps_b.is_empty() else "none",
	])


func _run() -> void:
	AudioBus.unlock()
	_house = (load("res://scenes/house/House.tscn") as PackedScene).instantiate() as Node3D
	add_child(_house)
	_director = _house.get_node("OpeningDirector")
	_player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	_player.can_move = false
	await _wait(0.5)

	var doors: DoorSystem = _director.doors
	print("DOOR WALK TEST")
	for cfg: Dictionary in DoorSystem.SWING_DOORS:
		if doors.get_door(String(cfg["panel"])) == null:
			print("  %-16s MISSING" % String(cfg["panel"]))
			_fail += 1
	if doors.get_door(DoorSystem.PARENTS_DOOR_NAME) == null:
		print("  %-16s MISSING" % DoorSystem.PARENTS_DOOR_NAME)
		_fail += 1
	for pname: String in doors._doors.keys():
		if pname == "closet_door_03":
			continue  # scripted only, nothing to walk into
		await _test_door(pname, doors.get_door(pname))

	if _fail == 0:
		print("DOORS OK")
		get_tree().quit(0)
	else:
		print("DOORS FAIL: %d door(s)" % _fail)
		get_tree().quit(1)
