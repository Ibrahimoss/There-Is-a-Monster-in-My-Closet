extends Node
## Headless feel test on the real level: drives the player through its own
## movement code (test_input) and checks walls glide instead of stopping the
## body dead, bumps fire once per contact, and latched doors do not move when
## walked into. Run:
##   godot --headless --path . res://tools/FeelTest.tscn
## Prints FEEL OK / FEEL FAIL. Never shipped.

const LEVEL := "res://real_world.tscn"

var _level: Node
var _player: CharacterBody3D
var _fail := 0


func _ready() -> void:
	_run()


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _check(name: String, ok: bool, detail := "") -> void:
	if not ok:
		_fail += 1
	print("  %-34s %s %s" % [name, "ok" if ok else "FAIL", detail])


func _place(pos: Vector3, yaw_deg: float) -> void:
	_player.teleport_to(pos)
	_player.rotation.y = deg_to_rad(yaw_deg)
	_player.sync_look_from_transform()
	_player.debug_bump_count = 0
	_player.debug_dir_flips = 0


func _drive(input: Vector2, seconds: float) -> void:
	_player.test_input = input
	await _wait(seconds)
	_player.test_input = Vector2.ZERO


func _visible_light_count() -> int:
	var n := 0
	var stack: Array[Node] = [_level]
	while not stack.is_empty():
		var x: Node = stack.pop_back()
		for c in x.get_children():
			stack.push_back(c)
		if x is Light3D and (x as Light3D).visible:
			n += 1
	return n


func _house_child(wanted: String) -> Node:
	var house := _level.get_node_or_null("house")
	return house.find_child(wanted, true, false) if house else null


func _find_door(node: Node, wanted: String) -> Door:
	if node is Door and node.name == wanted:
		return node as Door
	for c in node.get_children():
		var d := _find_door(c, wanted)
		if d != null:
			return d
	return null


func _run() -> void:
	AudioBus.unlock()
	# root is still adding the main scene during _ready; wait a frame
	await get_tree().process_frame
	_level = (load(LEVEL) as PackedScene).instantiate()
	get_tree().root.add_child(_level)
	await _wait(1.0)
	_player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	if _player == null:
		print("FEEL FAIL: no player")
		get_tree().quit(1)
		return
	_player.cinematic = false
	_player.can_move = true
	_player.test_drive = true
	print("FEEL TEST")

	# 1. head-on into the parents' room north wall (z = -8.66)
	_place(Vector3(-2.0, 3.85, -7.5), 0.0)
	await _drive(Vector2(0.0, -1.0), 2.0)
	var p1 := _player.global_position
	_check("head-on wall: stopped at the wall", p1.z < -8.2 and p1.z > -8.7, str(p1))
	_check("head-on wall: one bump", _player.debug_bump_count == 1, "bumps=%d" % _player.debug_bump_count)
	_check("head-on wall: no direction flips", _player.debug_dir_flips == 0, "flips=%d" % _player.debug_dir_flips)
	_check("head-on wall: still on the floor", absf(p1.y - 3.73) < 0.12, "y=%.2f" % p1.y)

	# 2. 30 degrees into the same wall: should glide west more than 2 m
	# (2.2 s stays short of the west wall, so the only contact is the one wall)
	_place(Vector3(0.2, 3.85, -7.6), 60.0)
	await _drive(Vector2(0.0, -1.0), 2.2)
	var p2 := _player.global_position
	_check("30deg wall: glides along it > 2 m", p2.x < 0.2 - 2.0, "x=%.2f" % p2.x)
	_check("30deg wall: at most one bump", _player.debug_bump_count <= 1, "bumps=%d" % _player.debug_bump_count)
	_check("30deg wall: no direction flips", _player.debug_dir_flips == 0, "flips=%d" % _player.debug_dir_flips)

	# 3. walking into a latched door does not move it
	var hall := _find_door(_level, "Door_004")
	if hall == null:
		_check("hall door found", false)
	else:
		hall.snap_open(false)
		await get_tree().physics_frame
		_place(Vector3(3.9, 3.85, -8.06), 90.0)
		await _drive(Vector2(0.0, -1.0), 2.0)
		var p3 := _player.global_position
		_check("latched door: player held east of it", p3.x > 3.05, "x=%.2f" % p3.x)
		_check("latched door: did not swing", is_zero_approx(hall._swing), "swing=%.3f" % hall._swing)

	# 3b. the ajar bathroom door hangs into the hall: from the hall a shove
	# latches it (a wall), from inside the bathroom a shove swings it open
	var bath := _find_door(_level, "bathroom door")
	if bath == null:
		_check("bathroom door found", false)
	else:
		var swing0: float = bath._swing
		_place(Vector3(1.5, 3.85, -7.4), 0.0)
		await _drive(Vector2(0.0, -1.0), 1.5)
		_check("ajar door: shove from the hall latches it", is_zero_approx(bath._swing) and not bath.is_open,
			"swing %.2f -> %.2f" % [swing0, bath._swing])
		# hang it ajar again and come from the other side
		bath._dir = 1.0
		bath._apply(swing0)
		await get_tree().physics_frame
		_place(Vector3(1.5, 3.85, -9.7), 180.0)
		await _drive(Vector2(0.0, -1.0), 2.5)
		var p3b := _player.global_position
		_check("ajar door: shove from inside swings it open", absf(bath._swing) > swing0 + 20.0 / 90.0 and bath.is_open,
			"swing %.2f -> %.2f" % [swing0, bath._swing])
		_check("ajar door: walked through into the hall", p3b.z > -8.5, "z=%.2f" % p3b.z)

	# 4. free run across the room, momentum settles, no flips
	_place(Vector3(-3.2, 3.85, -6.0), 270.0)
	await _drive(Vector2(0.0, -1.0), 1.5)
	await _wait(0.6)
	var p4 := _player.global_position
	_check("free run: travelled", p4.x > -3.2 + 1.5, "x=%.2f" % p4.x)
	_check("free run: came to rest", _player.velocity.length() < 0.05, "v=%.3f" % _player.velocity.length())
	_check("free run: no direction flips", _player.debug_dir_flips == 0, "flips=%d" % _player.debug_dir_flips)

	# 5. look: a 200 px mouse move ends up as yaw, with a bit of roll on the way
	_place(Vector3(-2.0, 3.85, -6.0), 0.0)
	await _wait(0.5)
	var yaw0 := _player.rotation.y
	_player.set("_look_accum", Vector2(200.0, 0.0))
	await get_tree().process_frame
	await get_tree().process_frame
	var rig: Node3D = _player.get("_rig")
	var roll_early := absf(rig.rotation.z)
	await _wait(0.6)
	var yaw_after := _player.rotation.y
	var expected: float = -200.0 * float(_player.get("MOUSE_SENSITIVITY"))
	_check("look: yaw converges to the mouse move", absf((yaw_after - yaw0) - expected) < 0.01,
		"d=%.3f want %.3f" % [yaw_after - yaw0, expected])
	_check("look: turn roll while turning", roll_early > deg_to_rad(0.05), "roll=%.3f deg" % rad_to_deg(roll_early))
	_check("look: roll settles", absf(rig.rotation.z) < deg_to_rad(0.5),
		"roll=%.3f deg" % rad_to_deg(rig.rotation.z))
	var rig_rot: Vector3 = rig.rotation
	_check("look: micro-motion stays tiny", absf(rig_rot.x) < deg_to_rad(0.6) and absf(rig_rot.y) < deg_to_rad(0.6),
		"rig=%s" % str(rig_rot))

	# 6. hand rig: hold the bear, it settles into the hand, sways with a look, releases
	var toy := Toy.new()
	_level.add_child(toy)
	toy.global_position = _player.global_position + Vector3(0.0, 0.5, -1.0)
	await get_tree().process_frame
	_player.hold(toy, Vector3(0.2, -0.24, -0.5), -15.0, 0.75, 0.3)
	await _wait(0.6)
	var hands: Node3D = _player.get("_hands")
	_check("hand rig: held under Hands", toy.get_parent() == hands)
	_check("hand rig: settled to the rest pose", toy.position.length() < 0.01 and absf(toy.scale.x - 0.75) < 0.01,
		"pos=%s scale=%.2f" % [str(toy.position), toy.scale.x])
	var rest: Vector3 = hands.position
	_player.set("_look_accum", Vector2(160.0, 0.0))
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var swayed: float = (hands.position - rest).length() + hands.rotation.length()
	_check("hand rig: sways on a turn", swayed > 0.002, "sway=%.4f" % swayed)
	await _wait(0.8)
	var settled: float = (hands.position - Vector3(0.2, -0.24, -0.5)).length()
	_check("hand rig: settles after the turn", settled < 0.004, "off=%.4f" % settled)
	var got: Node = _player.release()
	_check("hand rig: release hands it back", got == toy and not bool(_player.is_holding()))
	toy.queue_free()

	# 7. props: every one toggles and comes back with busy cleared; a switch
	# really changes a light; the tap flips the flag
	var props: Array = Presence.get_props()
	_check("props: some were built", props.size() >= 8, "count=%d" % props.size())
	var lights_before := _visible_light_count()
	var switch_done := false
	for p in props:
		var prop: Node3D = p
		var area: Node = prop.get("area")
		if area == null or not bool(prop.call("can_use")):
			continue
		var was: bool = prop.get("is_open")
		area.call("interact", _player)
		await _wait(0.9)
		var now: bool = prop.get("is_open")
		var busy_after: bool = prop.get("busy")
		var ok := (now != was) and not busy_after
		if not switch_done and prop is SwitchProp:
			var lights_now := _visible_light_count()
			_check("props: switch changed a light", lights_now != lights_before, "%d -> %d" % [lights_before, lights_now])
			switch_done = true
		area.call("interact", _player)
		await _wait(0.9)
		var back: bool = prop.get("is_open")
		ok = ok and back == was and not bool(prop.get("busy"))
		_check("prop %-28s toggles and returns" % prop.name, ok, "%s -> %s -> %s" % [was, now, back])
	var tap: Node = _house_child("Manija_Washbasin_05_001Prop")
	if tap != null:
		var tap_area: Node = tap.get("area")
		tap_area.call("interact", _player)
		await _wait(0.4)
		var running: bool = GameState.flags.tap_running
		tap_area.call("interact", _player)
		await _wait(0.4)
		_check("tap: flag runs then stops", running and not bool(GameState.flags.tap_running))

	if _fail == 0:
		print("FEEL OK")
		get_tree().quit(0)
	else:
		print("FEEL FAIL: %d check(s)" % _fail)
		get_tree().quit(1)
