extends Node
## Headless run of the bedtime chain on the real level: lights at start, the
## stair block, brushing at the sink, the doors opening, the bed, the closet
## beat through to `finished`. Time-scaled so the whole act runs in seconds.
## Run:
##   godot --headless --path . res://tools/ActTest.tscn
## Prints ACT OK / ACT FAIL. Never shipped.

const LEVEL := "res://real_world.tscn"

var _level: Node
var _player: CharacterBody3D
var _bedtime: Node
var _fail := 0
var _finished := false


func _ready() -> void:
	_run()


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _check(name: String, ok: bool, detail := "") -> void:
	if not ok:
		_fail += 1
	print("  %-36s %s %s" % [name, "ok" if ok else "FAIL", detail])


func _light(mesh_name: String) -> Light3D:
	var lamps := _level.get_node("LampLights")
	return lamps.call("get_light", mesh_name) as Light3D


func _run() -> void:
	print("ACT TEST")
	AudioBus.unlock()
	Engine.time_scale = 5.0
	_level = (load(LEVEL) as PackedScene).instantiate()
	add_child(_level)
	_player = _level.get_node("player")
	_player.test_drive = true
	await _wait(1.0)
	_bedtime = _level.get_node_or_null("Bedtime")
	_check("bedtime director attached", _bedtime != null)
	if _bedtime == null:
		_done()
		return
	_bedtime.connect("finished", func() -> void: _finished = true)
	_check("state starts at TEETH", int(_bedtime.get("state")) == 0)
	_check("night environment present", _level.get_node_or_null("NightEnvironment") != null)
	var amb := _level.get_node_or_null("Ambience")
	var spots: Array = amb.get("_spots") if amb != null else []
	_check("cricket spots outside windows", spots.size() >= 5, "n=%d" % spots.size())
	if not spots.is_empty():
		var far := 0.0
		for sp: Vector3 in spots:
			far = maxf(far, sp.distance_to(Vector3(2.9, 4.0, -6.6)))
		_check("cricket spots outside the house", far > 6.0, "far=%.1f" % far)

	# spawn: the kid's room, facing the open door
	_check("spawn in the kid's room", _player.global_position.distance_to(Vector3(5.5, 3.74, -10.6)) < 0.3,
		"at %s" % _player.global_position)

	# lights: the bathroom next door + the kid's room, everything else off
	var bath := _light("Focus_02_012")
	var kid := _light("Focus_02_007")
	var parents := _light("Focus_02_009")
	var landing := _light("Focus_02_006")
	var small_bath := _light("Focus_02_008")
	_check("big bathroom light on, boosted", bath != null and bath.visible and bath.light_energy > 1.5, "e=%.2f" % bath.light_energy)
	_check("kid's room light on", kid != null and kid.visible)
	_check("parents' ceiling off", parents != null and not parents.visible)
	_check("landing off", landing != null and not landing.visible)
	_check("small bathroom off", small_bath != null and not small_bath.visible)
	var area := _level.get_node_or_null("bedroom light") as Light3D
	_check("bedroom area light off", area != null and not area.visible)

	# doors: kid's open, bathroom ajar, closet door built and locked
	var kid_door := Presence.get_door("Door_006")
	var bath_door := Presence.get_door("Door_005")
	var closet := Presence.get_door("closet door")
	_check("kid's door open at start", kid_door != null and bool(kid_door.get("is_open")))
	_check("bathroom door ajar", bath_door != null and not bool(bath_door.get("is_open")) and float(bath_door.get("_swing")) > 0.1,
		"swing=%.2f" % float(bath_door.get("_swing")))
	_check("closet door built", closet != null)
	if closet != null:
		var cc := MeshUtil.world_aabb(closet).get_center()
		_check("closet door sits in its frame", cc.distance_to(Vector3(6.68, 4.98, -9.31)) < 0.35, "c=%s" % cc)
		_check("closet door locked, prompt Open", bool(closet.get("locked")) and String(closet.call("get_prompt")) == "Open")
		var refused := [false]
		closet.connect("refused", func() -> void: refused[0] = true)
		closet.call("interact", _player)
		await _wait(0.2)
		_check("closet door refuses", refused[0] and not bool(closet.get("is_open")))

	# stairs blocked
	var block := _level.get_node_or_null("StairBlock")
	_check("stair block present", block != null)
	_player.teleport_to(Vector3(5.2, 3.73, -5.3))
	_player.rotation.y = deg_to_rad(90.0)
	_player.sync_look_from_transform()
	_player.test_input = Vector2(0, -1)
	await _wait(2.5)
	_player.test_input = Vector2.ZERO
	_check("stairs: held at the top step", _player.global_position.x > 4.55 and _player.global_position.y > 3.6,
		"x=%.2f y=%.2f" % [_player.global_position.x, _player.global_position.y])

	# brushing
	var spot := _level.get_node_or_null("house/BrushSpot")
	_check("brush spot built", spot != null)
	var brush := _level.get_node("house").find_child("Toothbrush_02", true, false) as MeshInstance3D
	var home := brush.global_transform
	_check("brush spot at the near sink", (spot as Node3D).global_position.distance_to(home.origin) < 0.3)
	_player.teleport_to(Vector3(6.6, 3.73, -5.2))
	spot.call("interact", _player)
	await _wait(0.6)
	_check("brush: held in the hand", _player.is_holding())
	_check("brush: player cannot move", not bool(_player.get("can_move")))
	await _wait(float(_bedtime.get("BRUSH_TIME")) + 1.5)
	_check("brush: released", not _player.is_holding())
	_check("brush: back on the sink", brush.global_position.distance_to(home.origin) < 0.05,
		"d=%.3f" % brush.global_position.distance_to(home.origin))
	_check("brush: can move again", bool(_player.get("can_move")))
	_check("state moved to BED", int(_bedtime.get("state")) == 1)
	_check("flag teeth_brushed", bool(GameState.flags.get("teeth_brushed", false)))

	# bed
	var bed_spot := _level.get_node_or_null("house/BedSpot")
	_check("bed spot built", bed_spot != null)
	_player.teleport_to(Vector3(5.5, 3.73, -10.6))
	bed_spot.call("interact", _player)
	await _wait(0.3)
	_check("state moved to LYING", int(_bedtime.get("state")) == 2)
	_check("stair block dropped", _level.get_node_or_null("StairBlock") == null or (_level.get_node("StairBlock") as Node).is_queued_for_deletion())
	await _wait(2.0)
	_check("player in bed", bool(_player.get("in_bed")))
	_check("head at the headboard end", _player.global_position.x > 6.8, "x=%.2f" % _player.global_position.x)

	# the closet beat, through to finished; the kid puts the lamps out
	# midway like a player would
	var t := 0.0
	var lamps_done := false
	while not _finished and t < 120.0:
		await _wait(1.0)
		t += 1.0
		if not lamps_done and t > 30.0:
			lamps_done = true
			for n in ["Desk_lamp_003", "Desk_lamp_004"]:
				var p := Presence.get_prop(n)
				if p != null:
					p.call("flick", false)
	_check("closet beat finished", _finished, "after %.0fs (scaled)" % t)
	_check("kid's door shut again", kid_door != null and not bool(kid_door.get("is_open")))
	_check("kid's ceiling off", kid != null and not kid.visible)
	var lamp := _light("Desk_lamp_003")
	_check("kid's lamp out", lamp != null and not lamp.visible)
	_check("closet door opened by itself", closet != null and bool(closet.get("is_open")))
	# the menu cut is gone: the dream rooms take over from `finished`, and hand
	# on to the chase when the last of them is done
	var chase := _level.get_node_or_null("Chase")
	var dream := _level.get_node_or_null("Dream")
	_check("chase director attached", chase != null)
	_check("dream director attached", dream != null)
	_check("dream picks up from the closet beat", dream != null and int(dream.get("stage")) >= 1,
		"stage=%d" % (int(dream.get("stage")) if dream != null else -1))
	_check("chase still waiting its turn", chase != null and int(chase.get("stage")) == 0)
	_check("act is NIGHTMARE", GameState.current_act == GameState.Act.NIGHTMARE)
	_done()


func _done() -> void:
	print("ACT OK" if _fail == 0 else "ACT FAIL (%d)" % _fail)
	get_tree().quit()
