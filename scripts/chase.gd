extends Node
## The chase: the closet opens, the thing comes out, and the house turns into
## ten hallways that only run one way.
##
## Attached at runtime by Presence as "Chase" under the level root, started
## from Bedtime's `finished`. Owns the hidden room chain, the seam warp at the
## bathroom door, the per-room slam/pound/burst beat, respawns, and the ending.
##
## Scripts are preloaded by path, not by class name: this file hangs off an
## autoload's preload chain, where the global class cache does not exist yet.

signal stage_changed(stage: int)
signal room_entered(index: int)
signal finished

const Kit := preload("res://scripts/chase_kit.gd")
const Rooms := preload("res://scripts/chase_rooms.gd")
const NavGraphScript := preload("res://scripts/nav_graph.gd")
const MonsterScript := preload("res://scripts/monster.gd")
const DREAD_SHADER := preload("res://scripts/dread.gdshader")
const SimpleInteractableScript := preload("res://scripts/simple_interactable.gd")
const BedtimeScript := preload("res://scripts/bedtime.gd")

enum Stage { IDLE, EMERGE, HOUSE, ROOMS, THRESHOLD, BATHROOM, DONE }

## The rooms live here, far enough east that the 60 m far plane never shows the
## house from them and the other way round.
const CHASE_OFFSET := Vector3(150.0, 0.0, 0.0)
const ROOM_COUNT := 10
const TYPES: Array[String] = ["long", "donut", "stairs", "garden"]
## Metres at which the thing starts getting into the picture.
const DREAD_RANGE := 11.0

## Rooms either side of the one you are in that stay in the picture. The chain
## builds 91 lights across 926 meshes and GL compatibility renders 64 lights a
## frame at best, so the rest is hidden. One either side is the floor, not a
## choice: the next room's spill has to reach back under its door, and the door
## the thing came through behind you is still standing open.
const ROOM_WINDOW := 1

## Distance fog. Nearly black rather than grey, so it eats the far end of a
## corridor instead of hazing the picture over, and it thickens the deeper the
## nightmare goes.
const FOG_COLOR := Color(0.03, 0.035, 0.05)
const FOG_NEAR := 0.045
const FOG_DEEP := 0.075
## The garden is outdoors and has a moon and a lit gate at the far end. Corridor
## density flattens both, so it gets a fraction of it.
const GARDEN_FOG := 0.55
## Where the rot starts. Not zero: the first hallway is meant to still read as a
## house, but at a clean zero it reads as a bright beige tube and it is the very
## first thing the chase shows you.
const DEPTH_START := 0.15
## How far a lightning flash lifts the ambient in a room that can see it.
const FLASH_AMBIENT := 0.55

const FLOOR_Y := 3.7316
## Standing spot beside the bed, facing the closet.
const BED_SIDE := Vector3(6.15, 3.7316, -10.7)
const CLOSET_POINT := Vector3(6.8, 3.7316, -9.1)
## The corridor point in front of the bathroom door, and the door's own plane.
const CORRIDOR_POINT := Vector3(5.4448, 3.7316, -6.186702)
const BATH_DOOR_Z := -6.186702
const BATHROOM_SPOT := Vector3(6.95, 3.7316, -6.186702)
const SINK_POINT := Vector3(6.77, 4.9, -4.46)

## The kid's route out of their own room, walked by whatever is behind them.
const HOUSE_PATH: Array[Vector3] = [
	Vector3(6.80, 3.7316, -9.10),
	Vector3(6.55, 3.7316, -10.10),
	Vector3(6.30, 3.7316, -10.90),
	Vector3(5.90, 3.7316, -11.00),
	Vector3(5.55, 3.7316, -10.20),
	Vector3(5.35, 3.7316, -9.40),
	Vector3(5.28, 3.7316, -8.60),
	Vector3(5.42, 3.7316, -7.90),
	Vector3(5.4448, 3.7316, -6.186702),
]

const LINE_EMERGE := "no no no"
const LINE_BLOCKED := "not this way"
const LINE_HURRY := "come on come on"
const LINE_DAD := "Dad: hey. it's late. bed."

## Tests set this so `finished` can be checked without the scene changing under
## the test node.
var test_no_scene_change := false
## Fixed layout seed. -1 reads CHASE_SEED, and failing that rolls one.
var force_seed := -1

var stage := Stage.IDLE
var rooms: Array[Dictionary] = []
var lights: Array[OmniLight3D] = []
var monster: Node3D
var world: Node3D
var current_room := -1
var seq: Array[String] = []
## Every window and rain curtain in the chase, driven from _process.
var panes: Array[ShaderMaterial] = []

var _root: Node
var _house: Node
var _player: CharacterBody3D
var _ui: Node
var _doom: Node
var _lamps: Node
var _rng := RandomNumberGenerator.new()
var _warp: Area3D
var _real_spill: OmniLight3D
var _deaths := 0
var _seq_token := 0
var _darkness := 0.0
var _blocked_said := false
var _crouch_hinted := false
var _hurry_room := -1
var _ending := false
var _hum: AudioStreamPlayer3D
var _weather: AudioStreamPlayer3D
var _rain_t := 0.0
var _flash := 0.0
var _storm := 8.0
var _env: Environment
var _ambient_was := -1.0
## What the chase runs the ambient at, before any lightning on top.
var _ambient_now := 0.0
var _fog_saved := false
var _fog_was := false
var _fog_density_was := 0.0
var _fog_light_was := Color.BLACK
var _fog_energy_was := 0.0
var _fog_sky_was := 0.0
var _dread_mat: ShaderMaterial
var _dread_rect: ColorRect
var _dread := 0.0
var _seen := 0.0
var _rain: CPUParticles3D
## Light shafts, animated with the rain clock.
var shafts: Array[MeshInstance3D] = []


func setup(root: Node, house: Node, player: CharacterBody3D) -> void:
	_root = root
	_house = house
	_player = player
	_ui = root.get_node_or_null("DialogueLayer/dialouge ui")
	_doom = root.get_node_or_null("DoomFilter")
	_lamps = root.get_node_or_null("LampLights")
	for c in root.get_children():
		if c is WorldEnvironment:
			_env = (c as WorldEnvironment).environment
			break
	_build_dread()
	set_process(false)


## The full-screen distortion, under the Doom filter so it gets crushed along
## with the picture instead of floating over it.
func _build_dread() -> void:
	var layer := CanvasLayer.new()
	layer.name = "DreadLayer"
	layer.layer = 88
	_root.add_child(layer)
	_dread_mat = ShaderMaterial.new()
	_dread_mat.shader = DREAD_SHADER
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.material = _dread_mat
	rect.color = Color.WHITE
	layer.add_child(rect)
	_dread_rect = rect
	rect.visible = false


## The hallways are lit by bulbs metres apart, and the palette crush turns
## anything they miss into flat black. A little more ambient keeps the floor
## and whatever is lying on it just readable without lifting the mood.
## The fog goes on with it. A hallway with nothing at the far end reads as a
## lit tube with a wall in it; fogged nearly to black, the same hallway runs
## out of sight, which is most of what makes the length of one worth anything.
func _set_ambient(on: bool) -> void:
	if _env == null:
		return
	if on:
		_ambient_was = _env.ambient_light_energy
		_ambient_now = maxf(_ambient_was, 0.22)
		_env.ambient_light_energy = _ambient_now
		_fog_was = _env.fog_enabled
		_fog_density_was = _env.fog_density
		_fog_light_was = _env.fog_light_color
		_fog_energy_was = _env.fog_light_energy
		_fog_sky_was = _env.fog_sky_affect
		_fog_saved = true
		_env.fog_enabled = true
		_env.fog_light_color = FOG_COLOR
		_env.fog_light_energy = 1.0
		# the garden is the one room with a sky worth looking at, and fog in
		# front of the moon would take it away
		_env.fog_sky_affect = 0.0
		_env.fog_density = FOG_NEAR
	elif _ambient_was >= 0.0:
		_env.ambient_light_energy = _ambient_was
		if _fog_saved:
			_env.fog_enabled = _fog_was
			_env.fog_density = _fog_density_was
			_env.fog_light_color = _fog_light_was
			_env.fog_light_energy = _fog_energy_was
			_env.fog_sky_affect = _fog_sky_was
			_fog_saved = false


func _say(lines: Array) -> void:
	if _ui != null and _ui.has_method("play"):
		_ui.call("play", lines)


func _set_stage(s: int) -> void:
	stage = s
	stage_changed.emit(s)


# --- entry points -------------------------------------------------------------

## From Bedtime's `finished`: the kid is in bed, the closet has just swung open.
## `world` is checked as well as the stage: the dream builds the hallways early,
## behind a shut door, and this must not come along afterwards and build a
## second set on top of them.
func begin() -> void:
	if stage != Stage.IDLE or world != null:
		return
	GameState.set_act(GameState.Act.NIGHTMARE)
	AudioBus.prewarm(["monster_breath", "monster_step", "monster_roar", "wind", "rain", "thunder", "heartbeat", "monster_glitch", "door_smash"])
	_build_world()
	_prepare_house()
	_player.set_chase(true)
	if bool(_player.get("in_bed")):
		_player.exit_bed(BED_SIDE)
	else:
		_player.teleport_to(BED_SIDE)
	_face(_player, CLOSET_POINT)
	AudioBus.stop_ambience(2.0)
	set_process(true)
	_emerge()


## Dev shortcut: skip the house and start already inside the vestibule.
func begin_at_rooms() -> void:
	if stage != Stage.IDLE or world != null:
		return
	GameState.set_act(GameState.Act.NIGHTMARE)
	AudioBus.prewarm(["monster_breath", "monster_step", "monster_roar", "wind", "rain", "thunder", "heartbeat", "monster_glitch", "door_smash"])
	_build_world()
	_prepare_house()
	_player.set_chase(true)
	if bool(_player.get("in_bed")):
		_player.exit_bed(BED_SIDE)
	_spawn_monster()
	_player.teleport_to((rooms[0]["spawn"] as Vector3) + CHASE_OFFSET)
	_face(_player, (rooms[0]["spawn"] as Vector3) + CHASE_OFFSET + Vector3(1.0, 0.0, 0.0))
	if _warp != null:
		_warp.queue_free()
	set_process(true)
	_set_stage(Stage.ROOMS)
	_set_ambient(true)
	AudioBus.music("chase", 2.5, -16.0)
	_open_vestibule_door()


## The dream hands over at its own bathroom door rather than at the vestibule.
## The hallways are chained out of that doorway, the corridor the kid is already
## standing in becomes room zero, and the panel they are about to pull becomes
## its way out. Built while the door is shut, so the swing has a finished world
## behind it: nothing is faded and nobody is moved. Returns whether it took.
func prepare_from_portal(portal: Transform3D, entry: Dictionary) -> bool:
	if stage != Stage.IDLE or world != null or entry.is_empty():
		return false
	GameState.set_act(GameState.Act.NIGHTMARE)
	AudioBus.prewarm(["monster_breath", "monster_step", "monster_roar", "wind", "rain",
		"thunder", "heartbeat", "monster_glitch", "door_smash"])
	_build_world(entry, portal)
	_set_ambient(true)
	return true


## And then the door opens. Everything the player can see is already there; this
## only starts the chase running behind it.
func start_from_portal() -> void:
	if stage != Stage.IDLE or rooms.is_empty() or world == null:
		return
	_player.set_chase(true)
	set_process(true)
	_set_stage(Stage.ROOMS)
	current_room = 0
	_cull_rooms(0)
	GameState.set_checkpoint(rooms[0]["spawn_world"] as Vector3)
	# a low room tone that rides with the kid, with the rain on the other side
	# of the walls under it
	if _hum == null or not is_instance_valid(_hum):
		_hum = AudioBus.loop_at("wind", self, _player.global_position, -30.0)
		if _hum != null:
			_hum.unit_size = 1.0
			_hum.max_distance = 4.0
			_hum.pitch_scale = 0.55
		_weather = AudioBus.loop_at("rain", self, _player.global_position, -27.0)
		if _weather != null:
			_weather.unit_size = 1.0
			_weather.max_distance = 4.0
			_weather.pitch_scale = 0.8
	AudioBus.music("chase", 2.5, -16.0)
	_spawn_monster()
	if monster != null and is_instance_valid(monster):
		monster.call("vanish", 0.0)
		monster.set("lights", _nearby_lights(0))
	HUD.show_prompt("run", "Shift")
	await get_tree().create_timer(3.5).timeout
	if stage == Stage.ROOMS:
		HUD.hide_prompt()


func _face(node: Node3D, at: Vector3) -> void:
	var dir := at - node.global_position
	dir.y = 0.0
	if dir.length() < 0.01:
		return
	dir = dir.normalized()
	node.rotation.y = atan2(-dir.x, -dir.z)
	if node.has_method("sync_look_from_transform"):
		node.call("sync_look_from_transform")


# --- the house ----------------------------------------------------------------

## Doors and lights for the run out of the bedroom, plus the interact spot that
## is really the seam.
func _prepare_house() -> void:
	var kid := Presence.get_door("Door_006")
	if kid != null:
		kid.set("swing_time", 0.5)
		kid.set("locked", false)
	var bath := Presence.get_door("Door_005")
	if bath != null:
		bath.call("snap_open", false)
		bath.set("locked", false)
		bath.set("swing_time", 0.5)
		bath.connect("opened", _on_bath_door_opened)
	if Presence.get_door("closet door") == null:
		var panel := BedtimeScript.make_closet_panel(_house, Presence.get_door("Door_006"))
		if panel != null:
			_house.add_child(panel)
			Presence.get_doors().append(panel)

	# the light under the bathroom door, the only thing worth running toward
	_real_spill = OmniLight3D.new()
	_real_spill.light_color = Color(1.0, 0.86, 0.62)
	_real_spill.light_energy = 0.35
	_real_spill.omni_range = 1.6
	_real_spill.shadow_enabled = false
	_root.add_child(_real_spill)
	_real_spill.global_position = Vector3(5.85, FLOOR_Y + 0.07, BATH_DOOR_Z)

	_warp = SimpleInteractableScript.create(Vector3(0.14, 2.0, 0.92), "افتح", "Open")
	_warp.name = "WarpSpot"
	_root.add_child(_warp)
	_warp.global_position = Vector3(5.92, FLOOR_Y + 1.05, BATH_DOOR_Z)
	_warp.set("prompt_anchor_offset", Vector3(0.0, -0.05, 0.30))
	_warp.connect("interacted", _on_warp)


## The closet bangs fully open and the thing is standing in it.
func _emerge() -> void:
	_set_stage(Stage.EMERGE)
	var closet := Presence.get_door("closet door")
	if closet != null:
		if not bool(closet.get("is_open")):
			closet.set("locked", false)
			closet.set("_dir", closet.call("swing_away_from", CLOSET_POINT))
			closet.call("snap_open", true)
		# it is done being a door now: off the ray and out of the way, so the
		# panel cannot be pressed for act 0's refusal line mid-chase
		for c in closet.get_children():
			if c is CollisionObject3D:
				(c as CollisionObject3D).collision_layer = 0
	AudioBus.sfx_at("closet_thump", CLOSET_POINT, -4.0, 0.05, 0.65)
	_player.shake(1.2)
	_spawn_monster()
	monster.call("begin_house", HOUSE_PATH)
	_say([LINE_EMERGE])
	HUD.show_prompt("run", "Shift")
	_set_stage(Stage.HOUSE)
	await get_tree().create_timer(3.0).timeout
	if stage == Stage.HOUSE:
		HUD.hide_prompt()


func _spawn_monster() -> void:
	if monster != null and is_instance_valid(monster):
		return
	monster = MonsterScript.new()
	monster.name = "Monster"
	add_child(monster)
	monster.call("setup", _player)
	monster.connect("caught", _on_caught)


func _on_bath_door_opened() -> void:
	# belt and braces: the warp spot is nearer the ray, but if the panel opens
	# some other way the seam still has to happen
	if stage == Stage.HOUSE:
		_do_warp()


func _on_warp(_by: Node3D) -> void:
	if stage == Stage.HOUSE:
		_do_warp()


## The seam. Everything the player can see stays where it was; only the world
## under them is a different copy of the same corridor.
func _do_warp() -> void:
	_set_stage(Stage.ROOMS)
	_set_ambient(true)
	_player.shift_by(CHASE_OFFSET)
	# a low room tone that rides with the kid and thickens the deeper they get,
	# with the rain on the other side of the walls under it
	if _hum == null or not is_instance_valid(_hum):
		_hum = AudioBus.loop_at("wind", self, _player.global_position, -30.0)
		if _hum != null:
			_hum.unit_size = 1.0
			_hum.max_distance = 4.0
			_hum.pitch_scale = 0.55
		_weather = AudioBus.loop_at("rain", self, _player.global_position, -27.0)
		if _weather != null:
			_weather.unit_size = 1.0
			_weather.max_distance = 4.0
			_weather.pitch_scale = 0.8
	if _warp != null and is_instance_valid(_warp):
		_warp.queue_free()
	if _real_spill != null and is_instance_valid(_real_spill):
		_real_spill.queue_free()
	AudioBus.music("chase", 2.5, -16.0)
	var bath := Presence.get_door("Door_005")
	if bath != null:
		bath.set("locked", true)
		bath.call("snap_open", false)
	if monster != null and is_instance_valid(monster):
		monster.call("vanish", 0.2)
	_open_vestibule_door()


func _open_vestibule_door() -> void:
	var door: MeshInstance3D = rooms[0]["exit_door"]
	if door == null:
		return
	door.set("locked", false)
	door.set("_dir", door.call("swing_away_from", _player.global_position))
	door.call("set_open", true)


# --- world --------------------------------------------------------------------

## `entry` lets somebody else supply room zero — the dream hands over its own
## corridor, so the hallways chain out of the bathroom doorway the kid is
## standing at instead of out of a vestibule 550 metres away. Empty builds the
## vestibule as usual.
func _build_world(entry := {}, entry_frame := Transform3D.IDENTITY) -> void:
	world = Node3D.new()
	world.name = "ChaseWorld"
	add_child(world)

	var seed_env := OS.get_environment("CHASE_SEED")
	if force_seed >= 0:
		_rng.seed = force_seed
	elif seed_env.is_valid_int():
		_rng.seed = int(seed_env)
	else:
		_rng.seed = randi()
	seq = _make_sequence()
	print("chase seq: ", seq)

	var opts := {"house": _house, "rng": _rng, "depth": 0.0}
	var first: Dictionary
	var frame: Transform3D
	if entry.is_empty():
		first = Rooms.build_vestibule(Transform3D(Basis.IDENTITY, CHASE_OFFSET), opts)
		world.add_child(first["root"] as Node3D)
		frame = (first["root"] as Node3D).transform * (first["exit_portal"] as Transform3D)
	else:
		# already standing, already the room the kid is in: it is not ours to
		# parent and not ours to free
		first = entry
		frame = entry_frame
	rooms = [first]
	var placed: Array[AABB] = [_world_aabb(first)]

	var donuts_seen := 0
	for i in ROOM_COUNT:
		# how deep in the nightmare: the first hallway still looks like a house,
		# just not a clean one
		opts["depth"] = lerpf(DEPTH_START, 1.0, float(i) / float(ROOM_COUNT - 1))
		# the first ring always comes down on you; later ones sometimes
		opts["collapse"] = false
		if seq[i] == "donut":
			opts["collapse"] = donuts_seen == 0 or _rng.randf() < 0.5
			donuts_seen += 1
		var room := _place(seq[i], frame, placed, opts, i + 1)
		rooms.append(room)
		placed.append(_world_aabb(room))
		frame = frame * (room["exit_portal"] as Transform3D)

	var threshold := Rooms.build_threshold(frame, opts)
	world.add_child(threshold["root"] as Node3D)
	rooms.append(threshold)
	_rain = Kit.rain_volume(world)

	for i in rooms.size():
		var r := rooms[i]
		var root := r["root"] as Node3D
		var xf := root.transform
		r["world_graph"] = (r["graph"] as NavGraphScript).transformed(xf)
		r["spawn_world"] = xf * (r["spawn"] as Vector3)
		r["forward"] = xf.basis * Vector3(0, 0, 1)
		var crawls_world: Array[Dictionary] = []
		for c: Dictionary in (r["crawls"] as Array):
			crawls_world.append({
				"aabb": xf * (c["aabb"] as AABB),
				"through": xf.basis * (c["through"] as Vector3),
			})
		r["crawls_world"] = crawls_world
		for l: OmniLight3D in (r["lights"] as Array):
			lights.append(l)
			if l.has_meta("flicker") and l.visible:
				_flicker_forever(l)
		for pane: MeshInstance3D in (r["panes"] as Array):
			panes.append(pane.material_override as ShaderMaterial)
		for s: MeshInstance3D in (r["shafts"] as Array):
			shafts.append(s)
		for loop: Array in (r["loops"] as Array):
			var p := AudioBus.loop_at(String(loop[0]), root, xf * (loop[1] as Vector3), float(loop[2]))
			if p != null:
				p.unit_size = 6.0
				p.max_distance = 26.0
		for d: MeshInstance3D in (r["doors"] as Array):
			Presence.get_doors().append(d)
			if bool(d.get("locked")):
				d.connect("refused", _on_blocked)
		for ev: Dictionary in (r["events"] as Array):
			var t := ev["trigger"] as Area3D
			if t != null:
				t.body_entered.connect(_on_event_body.bind(ev))
		var trig := r["entry_trigger"] as Area3D
		if trig != null:
			trig.body_entered.connect(_on_room_body.bind(i))

	_cull_rooms(0)


## Build candidates for `type` until one fits, then add it to the world.
func _place(type: String, frame: Transform3D, placed: Array[AABB], opts: Dictionary, index: int) -> Dictionary:
	var candidates := _candidates(type, float(opts.get("depth", 0.0)))
	for cand: int in candidates:
		var o := opts.duplicate()
		o["variant"] = cand
		o["exit_choice"] = cand
		var room := Rooms.build(type, frame, o)
		var fp := _world_aabb(room)
		if _fits(fp, placed):
			world.add_child(room["root"] as Node3D)
			return room
		(room["root"] as Node3D).queue_free()
	# nothing fitted: a straight corridor never turns back on the chain
	print("chase: forced long at %d" % index)
	var o2 := opts.duplicate()
	o2["variant"] = 0
	var forced := Rooms.build_long(frame, o2)
	world.add_child(forced["root"] as Node3D)
	return forced


## Room variants worth trying, best first. The collapsed corridor only shows
## up once the nightmare has had time to rot.
func _candidates(type: String, depth: float) -> Array[int]:
	var out: Array[int] = []
	match type:
		"long":
			out.append_array([0, 2])
			_shuffle(out)
			if depth >= 0.25 and _rng.randf() < lerpf(0.35, 0.75, depth):
				out.push_front(3)
		"donut":
			# all three ways out take a turn. Straight used to get first refusal,
			# but _place takes the first candidate that FITS and straight always
			# fits, so left and right were dead code: the way on was always the
			# door you could already see from the entry, which costs the ring the
			# only thing it is for.
			out.append_array([0, 2, 4])
			_shuffle(out)
		"stairs":
			out.append_array([0, 1])
			_shuffle(out)
		_:
			out.append(0)
	return out


func _shuffle(a: Array[int]) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var t := a[i]
		a[i] = a[j]
		a[j] = t


func _world_aabb(room: Dictionary) -> AABB:
	return (room["root"] as Node3D).transform * (room["footprint"] as AABB)


## Rooms always touch the one before them, so only the rest of the chain counts.
func _fits(fp: AABB, placed: Array[AABB]) -> bool:
	var a := fp.grow(-0.3)
	for i in placed.size() - 1:
		if a.intersects(placed[i].grow(-0.3)):
			return false
	return true


## Room 1 is always the long hall and room 2 the ring; the rest is a shuffled
## bag with at least one staircase and one garden, no two the same in a row,
## and never more than three rings.
func _make_sequence() -> Array[String]:
	var out: Array[String] = []
	var env := OS.get_environment("CHASE_SEQ")
	if not env.is_empty():
		for part in env.split(",", false):
			var t := part.strip_edges()
			if TYPES.has(t) and out.size() < ROOM_COUNT:
				out.append(t)
	if out.is_empty():
		out = ["long", "donut"]
	var bag: Array[String] = ["stairs", "garden"]
	while out.size() + bag.size() < ROOM_COUNT:
		bag.append(TYPES[_rng.randi_range(0, TYPES.size() - 1)])
	for i in range(bag.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var t := bag[i]
		bag[i] = bag[j]
		bag[j] = t
	out.append_array(bag)
	out.resize(ROOM_COUNT)

	var donuts := 0
	for i in out.size():
		if out[i] == "donut":
			donuts += 1
			if donuts > 3:
				out[i] = "long" if i % 2 == 0 else "garden"
	for _try in 50:
		var clash := -1
		for i in range(1, out.size()):
			if out[i] == out[i - 1]:
				clash = i
				break
		if clash < 0:
			break
		var swapped := false
		for j in range(clash + 1, out.size()):
			var before := out[clash - 1]
			var after: String = out[clash + 1] if clash + 1 < out.size() else ""
			var jbefore := out[j - 1]
			var jafter: String = out[j + 1] if j + 1 < out.size() else ""
			if out[j] != before and out[j] != after and out[clash] != jbefore and out[clash] != jafter:
				var t := out[clash]
				out[clash] = out[j]
				out[j] = t
				swapped = true
				break
		if not swapped:
			out[clash] = "long" if out[clash] != "long" else "garden"
	return out


# --- per room -----------------------------------------------------------------

func _on_room_body(body: Node3D, index: int) -> void:
	if body != _player or index <= current_room:
		return
	current_room = index
	_cull_rooms(index)
	_deaths = 0
	_hurry_room = -1
	room_entered.emit(index)
	GameState.set_checkpoint(rooms[index]["spawn_world"] as Vector3)
	if monster != null and is_instance_valid(monster):
		monster.set("lights", _nearby_lights(index))
	# a room whose crawl is just lying there gets the hint on entry; the ones
	# that come down on you get it when they land
	if not (rooms[index]["crawls"] as Array).is_empty() and (rooms[index]["events"] as Array).is_empty():
		_crouch_hint()
	if String(rooms[index]["type"]) == "threshold":
		_threshold_beat()
		return
	_seq_token += 1
	_room_beat(index, _seq_token, false)


## Lights the monster can reach from here: this room and the two either side.
func _nearby_lights(index: int) -> Array[OmniLight3D]:
	var out: Array[OmniLight3D] = []
	for i in range(maxi(0, index - 1), mini(rooms.size(), index + 2)):
		for l: OmniLight3D in (rooms[i]["lights"] as Array):
			out.append(l)
	return out


## Only the rooms next to you are in the picture. Hiding a room's root takes its
## lamps with it, which is the whole point: the renderer has a hard ceiling on
## how many it will draw, and a chain of ten rooms blows through it four times
## over. Colliders, triggers and the loops keep running while hidden, so none of
## the room beat can desync behind it.
func _cull_rooms(around: int) -> void:
	for i in rooms.size():
		var root := rooms[i]["root"] as Node3D
		if root != null and is_instance_valid(root):
			root.visible = absi(i - around) <= ROOM_WINDOW


## A flash is only worth showing where there is glass or sky to see it through.
func _room_sees_sky(index: int) -> bool:
	if index < 0 or index >= rooms.size():
		return false
	if String(rooms[index]["type"]) == "garden":
		return true
	return not (rooms[index]["panes"] as Array).is_empty()


## Door shuts, locks, is pounded on, then comes off its latch.
func _room_beat(index: int, token: int, short: bool) -> void:
	var room := rooms[index]
	var door: MeshInstance3D = rooms[index - 1]["exit_door"] if index > 0 else null
	var anchor := (room["root"] as Node3D).transform * Vector3(0.0, 1.0, -0.15)
	var head: float = float(room["head_start"]) + 1.2 * float(_deaths)

	if door != null and not short:
		await get_tree().create_timer(0.6).timeout
		if token != _seq_token:
			return
		door.set("swing_time", 0.35)
		door.call("set_open", false)
		await get_tree().create_timer(0.4).timeout
		if token != _seq_token:
			return
		door.set("locked", true)
		AudioBus.sfx_at("closet_thump", anchor, -10.0, 0.05, 0.7)
		_player.shake(0.5)
		_player.recoil(0.02)

	var pounds := [1.3, 1.8, 2.3] if not short else [0.9]
	var loud := [-8.0, -6.0, -4.0]
	var elapsed := 1.0 if not short else 0.0
	for i in pounds.size():
		var wait: float = float(pounds[i]) - elapsed
		if wait > 0.0:
			await get_tree().create_timer(wait).timeout
		elapsed = float(pounds[i])
		if token != _seq_token:
			return
		AudioBus.sfx_at("closet_thump", anchor, float(loud[mini(i, 2)]), 0.05, 0.7)
		AudioBus.sfx_at("door_locked", anchor, -16.0, 0.08, 0.9)
		if door != null:
			door.call("jiggle", 1.6)
		_player.shake(0.3)

	if head > elapsed:
		await get_tree().create_timer(head - elapsed).timeout
	if token != _seq_token:
		return
	_burst(index, door, anchor)


func _burst(index: int, door: MeshInstance3D, anchor: Vector3) -> void:
	var room := rooms[index]
	var root := room["root"] as Node3D
	if door != null:
		door.set("locked", false)
		door.set("_dir", door.call("swing_away_from", root.transform * Vector3(0.0, 1.0, -1.0)))
		door.call("snap_open", true)
	# the crack first, then the weight behind it. Starting at -14 per the sound
	# rule; this is the loudest beat in a room, so it is the first knob to turn
	# up if it reads polite.
	AudioBus.sfx_at("door_smash", anchor, -14.0, 0.06, 0.95)
	AudioBus.sfx_at("closet_thump", anchor, -4.0, 0.05, 0.6)
	AudioBus.sfx_at("door_locked", anchor, -16.0, 0.08, 0.8)
	_player.shake(1.4)
	if monster != null and is_instance_valid(monster):
		monster.call("enter_room", room["world_graph"], root.transform * Vector3(0.0, 0.0, 0.5))


func _on_blocked() -> void:
	if _blocked_said or stage != Stage.ROOMS:
		return
	_blocked_said = true
	_say([LINE_BLOCKED])


## The rain box rides six metres over the player, so the drops are always
## falling through wherever they are standing rather than sliding about on a
## pane in front of the lens. Only in a room with no roof on it.
func _drive_rain() -> void:
	if _rain == null or not is_instance_valid(_rain) or _player == null:
		return
	var outside := stage == Stage.ROOMS and current_room >= 0 and current_room < rooms.size() \
		and String(rooms[current_room]["type"]) == "garden"
	if _rain.emitting != outside:
		_rain.emitting = outside
	_rain.visible = outside
	if outside:
		_rain.global_position = _player.global_position + Vector3(0.0, 5.0, 0.0)


## A flash at the windows, a beat of nothing, then the thunder behind it. Two
## strikes as often as one, because that is what real lightning does.
func _lightning() -> void:
	_flash = 1.0
	await get_tree().create_timer(randf_range(0.06, 0.13)).timeout
	if randf() < 0.6:
		_flash = 0.8
	await get_tree().create_timer(randf_range(0.6, 1.9)).timeout
	if _player == null or not is_instance_valid(_player):
		return
	AudioBus.sfx_at("thunder", _player.global_position + Vector3(0.0, 6.0, 0.0), -17.0, 0.12,
		randf_range(0.85, 1.1))


## A bad bulb, for as long as the room lives: short stutters, long gaps.
func _flicker_forever(l: OmniLight3D) -> void:
	while is_instance_valid(l) and is_inside_tree():
		await get_tree().create_timer(randf_range(3.0, 9.0)).timeout
		if not is_instance_valid(l) or not l.visible:
			continue
		for i in randi_range(1, 3):
			var was := l.light_energy
			l.light_energy = 0.0
			var bulb := (l.get_meta("bulb") as Node3D) if l.has_meta("bulb") else null
			if bulb != null and is_instance_valid(bulb):
				bulb.visible = false
			await get_tree().create_timer(randf_range(0.05, 0.12)).timeout
			if not is_instance_valid(l):
				return
			l.light_energy = was
			if bulb != null and is_instance_valid(bulb):
				bulb.visible = true
			await get_tree().create_timer(randf_range(0.06, 0.2)).timeout


## Something in a room comes down as you reach it. One shot each.
func _on_event_body(body: Node3D, ev: Dictionary) -> void:
	if body != _player or bool(ev.get("done", false)):
		return
	ev["done"] = true
	var play := ev["play"] as Callable
	if play.is_valid():
		play.call(_player)
	_crouch_hint()


## Told once, the first time the way on is a gap under something.
func _crouch_hint() -> void:
	if _crouch_hinted:
		return
	_crouch_hinted = true
	HUD.show_prompt("crouch", "Ctrl")
	await get_tree().create_timer(4.0).timeout
	if stage == Stage.ROOMS:
		HUD.hide_prompt()


# --- caught -------------------------------------------------------------------

func _on_caught() -> void:
	if stage != Stage.ROOMS or current_room < 1 or _ending:
		return
	var index := current_room
	_seq_token += 1
	var token := _seq_token
	monster.call("freeze")
	AudioBus.sfx_at("monster_roar", monster.global_position, -4.0, 0.05)
	var away := _player.global_position - monster.global_position
	away.y = 0.0
	_player.shake(2.5)
	_player.push(away.normalized() * 1.5)
	Fade.fade_out(0.18)
	await get_tree().create_timer(0.75).timeout
	if token != _seq_token or not is_instance_valid(_player):
		return
	_deaths += 1
	monster.call("vanish", 0.0)
	monster.set("assist_speed_mul", maxf(0.82, 1.0 - 0.06 * float(_deaths)))
	_player.teleport_to(rooms[index]["spawn_world"] as Vector3)
	_face(_player, (rooms[index]["spawn_world"] as Vector3) + (rooms[index]["forward"] as Vector3))
	# shut the way back so the burst still has a door to come through
	var back: MeshInstance3D = rooms[index - 1]["exit_door"]
	if back != null:
		back.call("snap_open", false)
		back.set("locked", true)
	Fade.fade_in(0.45)
	_room_beat(index, token, true)


# --- the way out --------------------------------------------------------------

func _threshold_beat() -> void:
	_set_stage(Stage.THRESHOLD)
	_seq_token += 1
	var door: MeshInstance3D = rooms[rooms.size() - 2]["exit_door"]
	var anchor := (rooms[rooms.size() - 1]["root"] as Node3D).transform * Vector3(0.0, 1.0, -0.15)
	if monster != null and is_instance_valid(monster):
		monster.call("vanish", 0.2)
	AudioBus.stop_music(1.4)
	await get_tree().create_timer(0.4).timeout
	if door != null:
		door.set("swing_time", 0.3)
		door.call("set_open", false)
		door.set("locked", true)
	AudioBus.sfx_at("closet_thump", anchor, -8.0, 0.05, 0.7)
	_player.shake(0.7)
	Fade.set_black()
	AudioBus.set_muffled(true)
	await get_tree().create_timer(0.6).timeout
	for i in 3:
		AudioBus.sfx_at("closet_thump", anchor, -8.0 + 2.0 * float(i), 0.05, 0.65)
		_player.shake(0.6 + 0.2 * float(i))
		await get_tree().create_timer(0.5).timeout
	AudioBus.sfx_at("monster_roar", anchor, -14.0, 0.05)
	await get_tree().create_timer(1.6).timeout
	AudioBus.sfx_at("switch", BATHROOM_SPOT, -10.0, 0.03, 0.9)
	_enter_bathroom()


## Out the other side: the real bathroom, light on, door shut behind you.
func _enter_bathroom() -> void:
	_set_stage(Stage.BATHROOM)
	GameState.set_act(GameState.Act.BATHROOM)
	_set_ambient(false)
	_dread = 0.0
	_seen = 0.0
	_player.set_dread(0.0, 0.0)
	if _dread_rect != null:
		_dread_rect.visible = false
	_player.set_chase(false)
	if _hum != null and is_instance_valid(_hum):
		_hum.queue_free()
	if _weather != null and is_instance_valid(_weather):
		_weather.queue_free()
	_player.teleport_to(BATHROOM_SPOT)
	# backed into the room with your eyes on the door. Facing the other way put
	# the kid's back to the only thing in the scene and every beat of the next
	# ten seconds - the pounding, the grit, the panel giving - happened off the
	# side of the screen
	_player.rotation.y = PI * 0.5
	_player.sync_look_from_transform()
	var bath := Presence.get_door("Door_005")
	if bath != null:
		bath.call("snap_open", false)
		bath.set("locked", true)
		bath.set("locked_prompt", "Hold it")
	if _lamps != null:
		var ceiling := _lamps.call("get_light", "Focus_02_012") as Light3D
		if ceiling != null:
			ceiling.visible = true
	AudioBus.set_muffled(false)
	if monster != null and is_instance_valid(monster):
		monster.call("vanish", 0.0)
	Fade.clear_deferred()
	_bathroom_beat()


## Four rounds of it putting its weight into the door, harder each time, with
## grit coming off the ceiling as the frame takes it. Then it stops, and stays
## stopped long enough that you start to believe it has gone.
func _bathroom_beat() -> void:
	var anchor := Vector3(6.05, 4.75, BATH_DOOR_Z)
	var bath := Presence.get_door("Door_005")
	var grit := Kit.burst(_root, Vector3(6.45, 6.35, BATH_DOOR_Z), Vector3(0.9, 0.04, 0.7),
		Vector3(0, -1, 0), 0.9, 46, Color(0.80, 0.76, 0.68, 0.9), 0.016, 1.8)
	await get_tree().create_timer(0.8).timeout
	for i in 4:
		var f := float(i)
		AudioBus.sfx_at("door_smash", anchor, -20.0 + 2.0 * f, 0.06, 0.86 - 0.05 * f)
		AudioBus.sfx_at("closet_thump", anchor, -9.0 + 2.0 * f, 0.05, 0.62)
		if bath != null:
			bath.call("jiggle", 2.2 + 0.7 * f)
		_player.shake(0.8 + 0.35 * f)
		_player.recoil(0.02 + 0.01 * f)
		grit.restart()
		await get_tree().create_timer(0.62).timeout
	AudioBus.sfx_at("door_locked", anchor, -18.0, 0.08, 0.95)
	_drip_forever()
	await get_tree().create_timer(6.5).timeout
	_ending = true
	_break_in(bath, anchor, grit)


## Drive the distortion by hand. `_process` is off through the break-in, so the
## shader's clock has to be turned here as well as its depth: frozen, the tear
## reads as a broken picture rather than as one coming apart.
func _paint_dread(amount: float, seen: float) -> void:
	if _dread_mat == null or _dread_rect == null:
		return
	_dread_rect.visible = true
	_rain_t += 0.016
	_dread_mat.set_shader_parameter("amount", amount)
	_dread_mat.set_shader_parameter("seen", seen)
	_dread_mat.set_shader_parameter("t", _rain_t)


## Put the view on something, now. One tween, no easing in: this is the head
## snapping round, not a camera move.
func _look_at(at: Vector3, secs: float) -> void:
	var head := _player.get_node_or_null("Head") as Node3D
	var dir := at - _player.global_position
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length() < 0.01:
		return
	var want_yaw := _player.rotation.y + wrapf(atan2(-flat.x, -flat.z) - _player.rotation.y, -PI, PI)
	var want_pitch := clampf(atan2(dir.y - 1.1, flat.length()), -1.0, 1.0)
	var t := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_property(_player, "rotation:y", want_yaw, secs)
	if head != null:
		t.tween_property(head, "rotation:x", want_pitch, secs)


## The door loses. It is in the room with you, and a bathroom has nowhere in it
## to go.
##
## Two things make this land rather than happen. The view is taken and put on
## the door before the panel goes, because a scare the player can be facing away
## from is not one. And the thing does not walk in: it is frozen, off the nav
## graph entirely, and thrown down the lens - two metres in a third of a second,
## growing the whole way - so what stops the picture is the thing itself filling
## it, and not a shape somewhere across the room.
func _break_in(bath: MeshInstance3D, anchor: Vector3, grit: CPUParticles3D) -> void:
	# the per-frame dread drive decays to nothing outside the chase stages and
	# would walk over everything set here
	set_process(false)
	_player.can_move = false
	_player.begin_cinematic()
	_player.look_lock(true)
	# aimed high in the frame, not at the handle: what comes through that hole is
	# two and a half metres of it and the head is up by the lintel
	_look_at(Vector3(5.98, FLOOR_Y + 1.75, BATH_DOOR_Z), 0.20)

	AudioBus.sfx_at("door_smash", anchor, -10.0, 0.03, 0.62)
	AudioBus.sfx_at("closet_thump", anchor, -2.0, 0.03, 0.55)
	_player.shake(3.0)
	_player.recoil(0.07)
	_player.set_dread(0.6, 0.2)
	if grit != null and is_instance_valid(grit):
		grit.restart()
	# the panel itself coming apart into the room
	Kit.burst(_root, Vector3(6.1, 4.85, BATH_DOOR_Z), Vector3(0.06, 0.7, 0.45),
		Vector3(1, 0, 0), 4.5, 34, Color(0.62, 0.50, 0.36, 1.0), 0.05, 1.4).restart()
	# The distortion starts low and is driven up as it crosses the room. Slammed
	# to full the moment the panel goes, the picture is torn to static for the
	# whole beat and the thing arrives inside noise: you cannot be frightened by
	# something you cannot make out.
	_paint_dread(0.45, 0.25)
	if bath != null:
		bath.set("locked", false)
		bath.set("swing_time", 0.1)
		bath.set("_dir", bath.call("swing_away_from", Vector3(5.5, 4.7, BATH_DOOR_Z)))
		bath.call("snap_open", true)

	# a beat of the empty doorway, so the eye has somewhere to be
	await get_tree().create_timer(0.22).timeout
	_spawn_monster()
	if monster == null or not is_instance_valid(monster):
		_wake()
		return
	# frozen and off the graph: nothing about its brain is wanted here
	monster.set("state", 3)
	monster.set("graph", null)
	monster.set("dread", 1.0)
	monster.set("lights", [] as Array[OmniLight3D])
	monster.scale = Vector3.ONE
	monster.global_position = Vector3(6.15, FLOOR_Y, BATH_DOOR_Z)
	monster.call("_show", 0.0)
	monster.call("roar", -2.0)
	AudioBus.sfx("monster_scream", -4.0, 0.0)
	AudioBus.sfx("ring", -16.0, 0.0)
	_player.shake(1.2)

	await get_tree().create_timer(0.16).timeout
	if not is_instance_valid(monster) or not is_instance_valid(_player):
		return
	var cam := _player.get_camera() as Camera3D
	var to := _player.global_position + (-cam.global_basis.z) * 0.5
	to.y = FLOOR_Y
	var lunge := create_tween().set_parallel(true)
	lunge.tween_property(monster, "global_position", to, 0.30) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	lunge.tween_property(monster, "scale", Vector3.ONE * 2.3, 0.30) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	# and the picture comes apart with it, arriving at full only as it lands
	lunge.tween_method(func(v: float) -> void:
		_paint_dread(lerpf(0.45, 1.0, v), lerpf(0.25, 1.0, v))
		if is_instance_valid(_player):
			_player.set_dread(lerpf(0.6, 1.0, v), lerpf(0.2, 1.0, v))
		, 0.0, 1.0, 0.42).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	for i in 3:
		await get_tree().create_timer(0.1).timeout
		if not is_instance_valid(_player):
			return
		_player.shake(1.6 + 0.9 * float(i))
		_player.recoil(0.03 + 0.02 * float(i))

	# hard cut, not a fade: the picture stops on it, and the next thing is your
	# own bed. Two frames later, or the eye reads a shape leaving the screen
	await get_tree().create_timer(0.07).timeout
	Fade.set_black()
	AudioBus.stop_music(0.2)
	AudioBus.set_muffled(true)
	if monster != null and is_instance_valid(monster):
		monster.call("vanish", 0.0)
		monster.scale = Vector3.ONE
	await get_tree().create_timer(0.55).timeout
	_wake()


## Your own bed, in the dark, breathing hard, with the closet still open across
## the room. Nothing comes out of it. That is the whole beat.
func _wake() -> void:
	GameState.set_act(GameState.Act.WAKE)
	_player.set_chase(false)
	_player.can_move = false
	# the break-in owned the head; hand it back before the pose goes on, or the
	# kid wakes up still staring at a door that is not there any more
	_player.look_lock(false)
	_player.end_cinematic()
	# No tween. The picture stopped in the bathroom and comes back in the bed:
	# the one thing the player must never watch is themselves sliding across the
	# house under the fade, which is exactly what a 1.4 second move looks like.
	_player.enter_bed(BedtimeScript.BED_SPOT, BedtimeScript.BED_YAW, 0.0)
	_player.set_dread(0.9, 0.0)
	AudioBus.set_muffled(false)
	AudioBus.sfx_at("heartbeat", BedtimeScript.BED_SPOT, -14.0, 0.04)
	if _dread_rect != null:
		_dread_rect.visible = false
	Fade.fade_in(1.8)
	# the heart coming down out of it, and nothing else happening at all
	var t := 0.0
	while t < 3.4:
		await get_tree().create_timer(0.1).timeout
		t += 0.1
		_player.set_dread(lerpf(0.9, 0.1, t / 3.4), 0.0)
	_say([LINE_DAD])
	var said := [false]
	if _ui != null and _ui.has_signal("event_finished"):
		_ui.connect("event_finished", func() -> void: said[0] = true, CONNECT_ONE_SHOT)
	var waited := 0.0
	while not bool(said[0]) and waited < 5.0:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	await Fade.fade_out(2.5)
	_set_stage(Stage.DONE)
	finished.emit()
	if test_no_scene_change:
		return
	await get_tree().create_timer(1.2).timeout
	HUD.set_active(false)
	get_tree().change_scene_to_file("res://scenes/ui/StartScreen.tscn")


func _drip_forever() -> void:
	# stops at `_ending`, not at the stage change: the stage stays BATHROOM all
	# the way through the break-in and the wake, and a tap dripping over that
	# would be the only sound in the room that had not noticed
	while stage == Stage.BATHROOM and not _ending and is_inside_tree():
		await get_tree().create_timer(randf_range(1.7, 2.4)).timeout
		if stage != Stage.BATHROOM or _ending:
			return
		AudioBus.sfx_at("drip", SINK_POINT, -22.0, 0.10)


# --- per frame ----------------------------------------------------------------

func _process(delta: float) -> void:
	if monster == null or not is_instance_valid(monster) or _player == null:
		return
	var d := _player.global_position.distance_to(monster.global_position)
	# the deeper the room, the less light the world starts with; the monster
	# closing in takes what is left
	var floor_dark := 0.0
	if stage == Stage.ROOMS and current_room >= 1:
		floor_dark = 0.12 * clampf(float(current_room - 1) / float(ROOM_COUNT - 1), 0.0, 1.0)
	var hunting := bool(monster.get("visible_now")) and (stage == Stage.HOUSE or stage == Stage.ROOMS)
	var want := floor_dark
	if hunting:
		want = maxf(want, floor_dark + lerpf(0.0, 0.35, clampf((6.0 - d) / 5.0, 0.0, 1.0)))
	_darkness = lerpf(_darkness, want, clampf(3.0 * delta, 0.0, 1.0))
	if _doom != null:
		_doom.set("darkness", _darkness)

	# how much of it is getting into your head: closeness, and doubly so with
	# your eyes on it
	var near := 0.0
	var looking := 0.0
	if hunting:
		near = clampf((DREAD_RANGE - d) / DREAD_RANGE, 0.0, 1.0)
		near = near * near
		var cam := _player.get_camera() as Camera3D
		if cam != null:
			var to_it := monster.global_position + Vector3(0.0, 1.2, 0.0) - cam.global_position
			if to_it.length() > 0.05:
				var face := -cam.global_basis.z
				looking = clampf(face.dot(to_it.normalized()), 0.0, 1.0)
				looking = pow(looking, 3.0)
	_dread = lerpf(_dread, near, clampf((5.0 if near > _dread else 1.8) * delta, 0.0, 1.0))
	_seen = lerpf(_seen, near * looking, clampf((6.0 if near * looking > _seen else 2.2) * delta, 0.0, 1.0))
	if _dread_mat != null:
		var on := _dread > 0.004 or _seen > 0.004
		_dread_rect.visible = on
		if on:
			_dread_mat.set_shader_parameter("amount", _dread)
			_dread_mat.set_shader_parameter("seen", _seen)
			_dread_mat.set_shader_parameter("t", _rain_t)
	_player.set_dread(_dread, _seen)
	monster.set("dread", _dread)

	# the weather: rain runs all the time, lightning comes and goes
	_rain_t += delta
	_flash = maxf(0.0, _flash - delta * 3.2)
	# the fog closes in as the rooms go on, and a flash belongs in the room and
	# not just on the glass: lit only on the pane, lightning is a bright
	# rectangle in a dark wall and nothing else about the hallway changes
	if _env != null and stage == Stage.ROOMS:
		var deep := clampf(float(maxi(current_room, 0)) / float(ROOM_COUNT), 0.0, 1.0)
		var want_fog := lerpf(FOG_NEAR, FOG_DEEP, deep)
		if current_room >= 0 and current_room < rooms.size() \
				and String(rooms[current_room]["type"]) == "garden":
			want_fog *= GARDEN_FOG
		_env.fog_density = lerpf(_env.fog_density, want_fog, clampf(delta, 0.0, 1.0))
		var lift := 0.0
		if _room_sees_sky(current_room):
			lift = _flash * FLASH_AMBIENT
		_env.ambient_light_energy = _ambient_now + lift
	for m in panes:
		if is_instance_valid(m):
			m.set_shader_parameter("t", _rain_t)
			m.set_shader_parameter("flash", _flash)
	_drive_rain()
	for s in shafts:
		if is_instance_valid(s):
			(s.material_override as ShaderMaterial).set_shader_parameter("t", _rain_t)
	if stage == Stage.ROOMS:
		_storm -= delta
		if _storm <= 0.0:
			_storm = randf_range(11.0, 26.0)
			_lightning()
	if _hum != null and is_instance_valid(_hum):
		_hum.global_position = _player.global_position
		_hum.volume_db = lerpf(-30.0, -19.0, clampf(float(current_room) / float(ROOM_COUNT), 0.0, 1.0))
	if _weather != null and is_instance_valid(_weather):
		_weather.global_position = _player.global_position

	if stage == Stage.ROOMS and current_room >= 1 and _hurry_room != current_room and d < 3.0:
		var door: MeshInstance3D = rooms[current_room]["exit_door"]
		if door != null:
			var anchor: Vector3 = door.call("get_prompt_anchor")
			if _player.global_position.distance_to(anchor) < 2.2:
				_hurry_room = current_room
				_say([LINE_HURRY])
