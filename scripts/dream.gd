class_name Dream
extends Node
## The act between the bedroom and the chase: the pillow hall, and the corridor
## out of it that does not go anywhere.
##
## You come out of a low stub into a room far too big for the house, wade across
## a floor of pillows, climb the flight wound round the pillar in the middle,
## and take the toy off the plinth at the top. It comes apart in your hands.
## Then the thing at the windows, the flight going with it, the fall, the black,
## and the dark taking the room while you run for the door. Behind the door is a
## corridor with a lit bathroom at the end of it that keeps its distance, until
## it stops, lets you look, and shuts.
##
## Its own director rather than a chase room: none of this is generated and none
## of it is hunted. It hands off to Chase.begin() when the last door opens.

signal stage_changed(stage: int)
signal finished

const Kit := preload("res://scripts/chase_kit.gd")
const Rooms := preload("res://scripts/dream_rooms.gd")
const NavGraphScript := preload("res://scripts/nav_graph.gd")
const MonsterScript := preload("res://scripts/monster.gd")
const ToyScript := preload("res://scripts/toy.gd")
const WakeScript := preload("res://scripts/wake_up_sequence.gd")
const SpotScript := preload("res://scripts/simple_interactable.gd")
const DREAD_SHADER := preload("res://scripts/dread.gdshader")
const STUN_SHADER := preload("res://scripts/stun.gdshader")

enum Stage { IDLE, ENTER, CLIMB, BURN, PEEK, FALL, OUT, DARK, HALL, SEEN, DONE }
## Where the corridor is in its one joke: running at a door that will not come,
## waiting for you to look back, holding while you do, and standing in your way.
enum RunStep { CHASING, ARMED, TURNED, NEAR }

## Clear of the house (x -8..13) and of the chase world (x 150 and east).
const DREAM_OFFSET := Vector3(-400.0, 0.0, 0.0)

## How long the toy takes to go once you have picked it up.
const BURN_TIME := 3.2
## And how long the flight takes to come off the pillar, bottom first.
const COLLAPSE_TIME := 2.6

## Slow. It is smoke filling a room, not a door closing.
const DARK_START_Z := 41.0
const DARK_SPEED := 1.05
## Each death hands back a few metres. Same invisible assist the chase uses.
const DARK_ASSIST := 7.0

## Metres of forward running before the corridor gives up the joke.
const RUN_GIVE_UP := 30.0
## And the outside limit on waiting for the kid to turn round afterwards. Past
## it the door simply stops where it is and the walk is a long one.
const RUN_PATIENCE := 20.0
## Where the bathroom is left standing while you have your back to it.
const BATH_NEAR := 7.0
## Metres of corridor the treadmill always leaves between the kid and the door
## they came in by, so a shift can never put them inside it.
const RUN_KEEP := 1.2
## How close you get before it shuts in your face.
const BATH_SHUT_AT := 2.6
## Metres ahead at which the corridor's lamps are already lit, and the band
## over which they come up. Past that the hall is simply dark.
const LAMP_LIT := 9.0
const LAMP_FADE := 6.0

const FOG_HALL := 0.030
## Thick enough that the unlit far end of the corridor is gone and the bathroom
## is a smudge of warm rather than a room you can read.
const FOG_RUN := 0.026
## And thin again once it is standing in front of you.
const FOG_SEEN := 0.012

const LINE_TOY := ["...لا"]
const LINE_RUN := ["الباب. الباب."]
const LINE_BACK := ["ما يقرب"]

var stage := Stage.IDLE
var world: Node3D
var hall: Dictionary = {}
var run: Dictionary = {}
var toy: Node3D
var monster: Node3D
var force_seed := -1
var test_no_handoff := false

var _root: Node
var _house: Node
var _player: CharacterBody3D
var _ui: Node
var _doom: Node
var _env: Environment
var _dread_mat: ShaderMaterial
var _dread_rect: ColorRect
var _stun_mat: ShaderMaterial
var _stun_rect: ColorRect
var _rng := RandomNumberGenerator.new()
var _token := 0
var _t := 0.0
var _dread := 0.0
var _seen := 0.0
var _roar := 0.0
var _stun := 0.0
var _stun_want := 0.0
var _flash := 0.0
var _ash: CPUParticles3D
var _toy_spot: Area3D
var _voidw: Dictionary = {}
var _dark_z := 0.0
var _dark_on := false
var _deaths := 0
var _dying := false
var _rumble := 0.0

# the flight coming off the pillar
var _debris: Array[Dictionary] = []

# the fall
var _fall_t := 0.0
var _fall_on := false
var _fall_step := 0
var _airborne := false
var _fall_roll := 0.0
var _fall_yaw := 0.0
var _fall_pitch := 0.0

# the corridor
var _run_on := false
var _run_far := 0.0
var _run_step := RunStep.CHASING
var _arm_t := 0.0
var _cue_t := 0.0
var _prev_pz := 0.0
var _door_stopped := false
var _bath_shut := false
var _handed := false
var _chase_ready := false
var _trail_lit := 0

var _hum: AudioStreamPlayer3D
var _drip_on := false
var _my_doors: Array[MeshInstance3D] = []
var _ambient_was := -1.0
var _fog_saved := false
var _fog_was := false
var _fog_density_was := 0.0
var _fog_light_was := Color.BLACK
var _fog_sky_was := 0.0


func setup(root: Node, house: Node, player: CharacterBody3D) -> void:
	_root = root
	_house = house
	_player = player
	_ui = root.get_node_or_null("DialogueLayer/dialouge ui")
	_doom = root.get_node_or_null("DoomFilter")
	for c in root.get_children():
		if c is WorldEnvironment:
			_env = (c as WorldEnvironment).environment
			break
	_find_dread()
	_build_stun()
	set_process(false)
	set_physics_process(false)


## Chase builds the distortion layer in its own setup and leaves it idle until
## it begins, so there is never a frame where both are driving it. If the dream
## runs without a Chase in the scene, put up an identical one.
func _find_dread() -> void:
	var layer := _root.get_node_or_null("DreadLayer") as CanvasLayer
	if layer == null:
		layer = CanvasLayer.new()
		layer.name = "DreadLayer"
		layer.layer = 88
		_root.add_child(layer)
		var mat := ShaderMaterial.new()
		mat.shader = DREAD_SHADER
		var r := ColorRect.new()
		r.set_anchors_preset(Control.PRESET_FULL_RECT)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.material = mat
		r.color = Color.WHITE
		r.visible = false
		layer.add_child(r)
	_dread_rect = layer.get_child(0) as ColorRect
	if _dread_rect != null:
		_dread_mat = _dread_rect.material as ShaderMaterial


## Concussion sits over the distortion and under the Doom filter, so a hit can
## smear the picture while the palette crush still owns the look.
func _build_stun() -> void:
	var layer := CanvasLayer.new()
	layer.name = "StunLayer"
	layer.layer = 89
	_root.add_child(layer)
	_stun_mat = ShaderMaterial.new()
	_stun_mat.shader = STUN_SHADER
	_stun_rect = ColorRect.new()
	_stun_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stun_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stun_rect.material = _stun_mat
	_stun_rect.color = Color.WHITE
	_stun_rect.visible = false
	layer.add_child(_stun_rect)


# --- entry points -------------------------------------------------------------

## From Bedtime's `finished`, or from whatever room comes before this one.
func begin() -> void:
	if stage != Stage.IDLE:
		return
	GameState.set_act(GameState.Act.NIGHTMARE)
	AudioBus.prewarm(["monster_breath", "monster_roar", "monster_glitch", "heartbeat",
		"ring", "void_hum", "pillow_thud", "drip", "door_smash"])
	_set_stage(Stage.ENTER)
	await Fade.fade_out(0.7)
	_build_world()
	_enter_hall_pose()
	set_process(true)
	set_physics_process(true)
	await Fade.fade_in(1.4)


## Dev entry. "top" drops you on the platform with the toy still there, "dark"
## just after the fall, "hall" straight into the corridor.
func begin_at(mode: String) -> void:
	if stage != Stage.IDLE:
		return
	GameState.set_act(GameState.Act.NIGHTMARE)
	AudioBus.prewarm(["monster_breath", "monster_roar", "monster_glitch", "heartbeat",
		"ring", "void_hum", "pillow_thud", "drip", "door_smash"])
	_build_world()
	_enter_hall_pose()
	set_process(true)
	set_physics_process(true)
	_set_stage(Stage.CLIMB)
	Fade.clear_deferred()
	match mode:
		"top":
			_player.teleport_to(_world_of(hall, Vector3(0.0, Rooms.TOP_Y, Rooms.PILLAR_C.z - 2.2)))
			_face(_player, _world_of(hall, hall["toy_at"] as Vector3))
		"dark":
			_player.teleport_to(_world_of(hall, hall["fall_spawn"] as Vector3))
			_start_dark()
		"hall":
			_player.teleport_to(_world_of(run, run["spawn"] as Vector3))
			_face(_player, _world_of(run, Vector3(0.0, 0.0, 8.0)))
			_enter_run()
		_:
			_set_stage(Stage.ENTER)


func _enter_hall_pose() -> void:
	_player.set_chase(true)
	_player.set_step_sound("cloth", -3.0)
	if bool(_player.get("in_bed")):
		_player.exit_bed(_world_of(hall, hall["spawn"] as Vector3))
	else:
		_player.teleport_to(_world_of(hall, hall["spawn"] as Vector3))
	_face(_player, _world_of(hall, Vector3(0.0, 0.0, 4.0)))
	_set_env(true)
	AudioBus.stop_ambience(1.5)
	_hum = AudioBus.loop_at("void_hum", self, _player.global_position, -30.0)


# --- world --------------------------------------------------------------------

func _build_world() -> void:
	world = Node3D.new()
	world.name = "DreamWorld"
	add_child(world)

	var seed_val := force_seed
	if seed_val < 0:
		var env_seed := OS.get_environment("DREAM_SEED")
		seed_val = int(env_seed) if env_seed.is_valid_int() else 20260816
	_rng.seed = seed_val

	var opts := {"house": _house, "rng": _rng}
	hall = Rooms.build_pillow_hall(Transform3D(Basis.IDENTITY, DREAM_OFFSET), opts)
	world.add_child(hall["root"])

	# the corridor hangs off the hall's exit, its own +z running along the hall's
	# +x. Never hand-pick that turn: derive it and let the basis carry it
	var ang := Vector3(0, 0, 1).signed_angle_to(Vector3(1, 0, 0), Vector3.UP)
	var run_frame := (hall["root"] as Node3D).transform * Transform3D(Basis(Vector3.UP, ang),
		Vector3(Rooms.HALL_W * 0.5 + Kit.WALL * 2.0, 0.0, Rooms.EXIT_Z))
	run = Rooms.build_endless_hall(run_frame, opts)
	world.add_child(run["root"])

	_voidw = Rooms.build_void(hall["root"] as Node3D, Rooms.HALL_L + 12.0)
	(_voidw["node"] as Node3D).visible = false
	(_voidw["roll"] as CPUParticles3D).emitting = false

	_build_toy()
	_register(hall)
	_register(run)

	(hall["entry_trigger"] as Area3D).body_entered.connect(_on_hall_entry)
	var exit_door := hall["exit_door"] as MeshInstance3D
	if exit_door != null:
		exit_door.connect("opened", _on_exit_opened)
	var bath: Dictionary = run["bath"]
	var bath_door := bath["door"] as MeshInstance3D
	if bath_door != null:
		bath_door.connect("opened", _on_bath_opened)


func _build_toy() -> void:
	var root := hall["root"] as Node3D
	var at := hall["toy_at"] as Vector3
	toy = ToyScript.new()
	toy.name = "DreamToy"
	toy.position = at
	toy.rotation.y = PI
	root.add_child(toy)
	if toy.has_method("set_glow"):
		toy.call("set_glow", true)
	_ash = Kit.ash(root, at + Vector3(0.0, 0.16, 0.0),
		Vector3(0.14, 0.16, 0.14), 110, Color(0.46, 0.42, 0.40), 3.8, 0.32)

	# you take it. It does not simply go off on its own halfway up the stairs
	_toy_spot = SpotScript.create(Vector3(1.5, 1.7, 1.5), "خذ اللعبة", "Take")
	_toy_spot.set("focus_target", toy)
	root.add_child(_toy_spot)
	_toy_spot.position = at + Vector3(0.0, 0.45, 0.0)
	_toy_spot.connect("interacted", _on_toy_taken)


## Doors have to go in Presence's registry or the player cannot see a prompt on
## them, and they have to come back out again when the dream is freed.
func _register(room: Dictionary) -> void:
	for d: MeshInstance3D in (room["doors"] as Array):
		if d == null:
			continue
		Presence.get_doors().append(d)
		_my_doors.append(d)


func _unregister() -> void:
	var reg := Presence.get_doors()
	for d in _my_doors:
		var i := reg.find(d)
		if i >= 0:
			reg.remove_at(i)
	_my_doors.clear()


func _world_of(room: Dictionary, local: Vector3) -> Vector3:
	return (room["root"] as Node3D).transform * local


func _local_of(room: Dictionary, world_pos: Vector3) -> Vector3:
	return (room["root"] as Node3D).transform.affine_inverse() * world_pos


func _face(node: Node3D, at: Vector3) -> void:
	var dir := at - node.global_position
	dir.y = 0.0
	if dir.length() < 0.01:
		return
	dir = dir.normalized()
	node.rotation.y = atan2(-dir.x, -dir.z)
	if node.has_method("sync_look_from_transform"):
		node.call("sync_look_from_transform")


func _head() -> Node3D:
	var h := _player.get_node_or_null("Head") as Node3D
	if h != null:
		return h
	return _player.get("_head") as Node3D


func _say(lines: Array) -> void:
	if _ui != null and _ui.has_method("play"):
		_ui.call("play", lines)


func _set_stage(s: int) -> void:
	stage = s
	stage_changed.emit(s)


## Fog is what makes a room this size read as having no end. The corridor wants
## far less of it, because the whole joke there is a light you can see and never
## reach.
func _set_env(on: bool) -> void:
	if _env == null:
		return
	if on:
		_ambient_was = _env.ambient_light_energy
		_env.ambient_light_energy = maxf(_ambient_was, 0.24)
		_fog_was = _env.fog_enabled
		_fog_density_was = _env.fog_density
		_fog_light_was = _env.fog_light_color
		_fog_sky_was = _env.fog_sky_affect
		_fog_saved = true
		_env.fog_enabled = true
		_env.fog_light_color = Color(0.02, 0.022, 0.032)
		_env.fog_light_energy = 1.0
		_env.fog_sky_affect = 0.0
		_env.fog_density = FOG_HALL
	elif _ambient_was >= 0.0:
		_env.ambient_light_energy = _ambient_was
		if _fog_saved:
			_env.fog_enabled = _fog_was
			_env.fog_density = _fog_density_was
			_env.fog_light_color = _fog_light_was
			_env.fog_sky_affect = _fog_sky_was
			_fog_saved = false


# --- the climb ----------------------------------------------------------------

func _on_hall_entry(body: Node3D) -> void:
	if body != _player or stage != Stage.ENTER:
		return
	_set_stage(Stage.CLIMB)
	_shut_behind()


## The way back closes. Not a jump scare, just a door that will not open again,
## so there is one direction left.
func _shut_behind() -> void:
	var token := _token
	await get_tree().create_timer(2.6).timeout
	if token != _token or stage != Stage.CLIMB:
		return
	var d := hall["entry_door"] as MeshInstance3D
	if d == null or not is_instance_valid(d):
		return
	d.set("swing_time", 0.8)
	d.call("set_open", false)
	await get_tree().create_timer(1.0).timeout
	if not is_instance_valid(d):
		return
	d.set("locked", true)
	d.set("locked_prompt", "It will not")
	AudioBus.sfx_at("closet_thump", d.global_position, -18.0, 0.06, 0.75)


## You picked it up. It goes then, in front of you, and not before.
func _on_toy_taken(_by: Node3D) -> void:
	if stage != Stage.CLIMB or toy == null:
		return
	_set_stage(Stage.BURN)
	if _toy_spot != null and is_instance_valid(_toy_spot):
		_toy_spot.queue_free()
		_toy_spot = null
	if toy.has_method("set_glow"):
		toy.call("set_glow", false)
	if toy.has_method("hop"):
		toy.call("hop", 0.035)
	if _ash != null and is_instance_valid(_ash):
		_ash.emitting = true
	AudioBus.sfx_at("cloth", toy.global_position, -14.0, 0.1)

	var beam := hall["beam_light"] as OmniLight3D
	var cone := hall["beam_shaft"] as MeshInstance3D
	var t := create_tween()
	t.tween_method(func(v: float) -> void:
		if toy != null and is_instance_valid(toy):
			toy.call("set_dissolve", v)
		if beam != null and is_instance_valid(beam):
			beam.light_energy = lerpf(3.2, 0.7, v)
		if cone != null and is_instance_valid(cone):
			var m := cone.material_override as ShaderMaterial
			if m != null:
				m.set_shader_parameter("energy", lerpf(2.6, 0.5, v))
		, 0.0, 1.0, BURN_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_callback(_toy_gone)


func _toy_gone() -> void:
	if toy != null and is_instance_valid(toy):
		toy.queue_free()
	toy = null
	AudioBus.sfx_at("monster_glitch", _world_of(hall, hall["toy_at"] as Vector3), -18.0, 0.1, 0.7)
	_say(LINE_TOY)
	_set_stage(Stage.PEEK)
	_peek()


# --- the windows --------------------------------------------------------------

func _peek() -> void:
	_token += 1
	var token := _token
	await get_tree().create_timer(0.9).timeout
	if token != _token:
		return

	var spots := hall["window_spots"] as Array
	var spot := _world_of(hall, spots[0] as Vector3)
	_player.begin_cinematic()
	# aim where its face ends up, near the top of the glass
	_pan_to(spot + Vector3(0.0, 13.0, 0.0), 1.0)
	_spawn_monster(spot)

	# the room notices before you do
	await get_tree().create_timer(0.7).timeout
	if token != _token:
		return
	_rumble = 1.0
	AudioBus.sfx_at("door_smash", _player.global_position, -14.0, 0.1, 0.45)
	_collapse_flight()

	await get_tree().create_timer(1.9).timeout
	if token != _token:
		return

	# the shout. Everything at once: it, the glass, the room and the picture
	if monster != null and is_instance_valid(monster):
		monster.call("roar", -3.0)
	AudioBus.sfx("monster_scream", -3.0, 0.02)
	_roar = 1.0
	_flash = 1.0
	AudioBus.set_muffled(true, 0.08)
	AudioBus.sfx("ring", -18.0, 0.0)
	for pane: MeshInstance3D in (hall["panes"] as Array):
		Kit.burst(hall["root"] as Node3D, pane.position + Vector3(1.0, 0.0, 0.0),
			Vector3(0.1, Rooms.WIN_H * 0.45, Rooms.WIN_W * 0.45),
			Vector3(1, -0.2, 0), 3.6, 44, Color(0.62, 0.70, 0.86), 0.02, 1.5).restart()
	for i in 3:
		_player.shake(2.6 - float(i) * 0.5)
		_player.recoil(0.05)
		await get_tree().create_timer(0.16).timeout
		if token != _token:
			return
		_roar = maxf(_roar, 0.85)

	await get_tree().create_timer(0.35).timeout
	if token != _token:
		return
	AudioBus.set_muffled(false, 1.4)
	_begin_fall()


## A short turn onto something, for a beat that cannot be allowed to happen off
## screen. The head is pinned first so nothing fights the tween for it.
func _pan_to(at: Vector3, secs: float) -> void:
	_player.look_lock(true)
	var head := _head()
	var dir := at - _player.global_position
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length() < 0.01:
		return
	var want_yaw := _player.rotation.y + wrapf(atan2(-flat.x, -flat.z) - _player.rotation.y, -PI, PI)
	var want_pitch := clampf(atan2(dir.y - 1.1, flat.length()), -1.2, 1.2)
	var t := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(_player, "rotation:y", want_yaw, secs)
	if head != null:
		t.tween_property(head, "rotation:x", want_pitch, secs)


func _spawn_monster(spot: Vector3) -> void:
	var m: Node3D = MonsterScript.new()
	m.name = "DreamMonster"
	world.add_child(m)
	m.call("setup", _player)
	# frozen before it ever ticks: no graph, no hunt, it only stands there
	m.set("state", 3)
	m.set("graph", null)
	# the billboard is 1.15 by 2.45; at this scale it is sixteen metres of it
	# against an eleven metre window, which is the whole idea
	m.scale = Vector3.ONE * 6.5
	m.global_position = spot - Vector3(0.0, 13.0, 0.0)
	m.call("_show", 0.6)
	m.set("dread", 0.85)
	var eaten: Array[OmniLight3D] = []
	for l: OmniLight3D in (hall["lights"] as Array):
		if l.has_meta("window"):
			eaten.append(l)
	m.set("lights", eaten)
	monster = m
	# up into the frame, slowly, the way something too big has to move
	var t := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_property(m, "global_position", spot, 1.6)


## The flight comes off the pillar, bottom first, and takes the view of the
## windows with it. It also takes the only way down, which is what makes the
## next thirty seconds a fall rather than a decision.
func _collapse_flight() -> void:
	var parts := hall["stair_parts"] as Array
	if parts.is_empty():
		return
	var per := COLLAPSE_TIME / float(maxi(Rooms.STEP_COUNT, 1))
	for n: Node3D in parts:
		if not is_instance_valid(n):
			continue
		var step := int(n.get_meta("step", 0)) if n.has_meta("step") else 0
		_debris.append({
			"node": n,
			"wait": float(step) * per + _rng.randf_range(0.0, 0.12),
			"vel": Vector3(_rng.randf_range(-0.9, 0.9), _rng.randf_range(-0.2, 1.1),
				_rng.randf_range(-0.9, 0.9)),
			"spin": Vector3(_rng.randf_range(-2.2, 2.2), _rng.randf_range(-1.4, 1.4),
				_rng.randf_range(-2.2, 2.2)),
		})
	hall["stair_parts"] = []
	# dust off the pillar as it goes
	Kit.burst(hall["root"] as Node3D, Rooms.PILLAR_C + Vector3(0.0, 6.0, 0.0),
		Vector3(3.4, 6.0, 3.4), Vector3(0, -1, 0), 2.0, 90, Color(0.5, 0.48, 0.46), 0.05, 3.0).restart()


func _drive_debris(delta: float) -> void:
	if _debris.is_empty():
		return
	var done: Array[int] = []
	for i in _debris.size():
		var d := _debris[i]
		var n := d["node"] as Node3D
		if not is_instance_valid(n):
			done.append(i)
			continue
		var wait := float(d["wait"])
		if wait > 0.0:
			d["wait"] = wait - delta
			continue
		if n is StaticBody3D and (n as StaticBody3D).collision_layer != 0:
			(n as StaticBody3D).collision_layer = 0
			AudioBus.sfx_at("closet_thump", n.global_position, -26.0, 0.2, 0.7)
		var vel := d["vel"] as Vector3
		vel.y -= 15.0 * delta
		d["vel"] = vel
		n.position += vel * delta
		n.rotation += (d["spin"] as Vector3) * delta
		if n.position.y < -4.0:
			n.queue_free()
			done.append(i)
	for k in range(done.size() - 1, -1, -1):
		_debris.remove_at(done[k])


# --- the fall -----------------------------------------------------------------

## Hand animated, on a timeline, in physics. The old version was three shoves
## and gravity and it read as three shoves and gravity: what was missing is the
## weight going somewhere before the feet do. So this is a recoil, two steps
## back that each land and settle, the heel finding nothing, and only then the
## slip. Everything the head does is a sum of sines on top of the beat, because
## a single tween per beat is what "stiff" looks like.
func _begin_fall() -> void:
	_set_stage(Stage.FALL)
	_fall_on = true
	_fall_t = 0.0
	_fall_step = 0
	_airborne = false
	_fall_roll = 0.0
	_fall_yaw = 0.0
	_fall_pitch = 0.0
	_player.begin_cinematic()
	_player.look_lock(true)
	_stun_want = 0.35


func _away() -> Vector3:
	var spots := hall["window_spots"] as Array
	var a := _player.global_position - _world_of(hall, spots[0] as Vector3)
	a.y = 0.0
	if a.length() < 0.01:
		return (hall["root"] as Node3D).transform.basis * Vector3(1, 0, 0)
	return a.normalized()


func _drive_fall(delta: float) -> void:
	if not _fall_on:
		return
	var was := _fall_t
	_fall_t += delta
	var head := _head()

	if not _airborne:
		# the beats. Each one is a shove plus a kick, and the sway between them
		# is what keeps it from reading as a machine
		var beats: Array[float] = [0.0, 0.62, 1.18, 1.62]
		var shove: Array[float] = [1.5, 1.9, 2.1, 1.4]
		for i in beats.size():
			if was < beats[i] and _fall_t >= beats[i] and _fall_step <= i:
				_fall_step = i + 1
				_player.push(_away() * shove[i])
				if i == 0:
					# hit: the head goes back and up before anything else moves
					_player.nudge(Vector3(deg_to_rad(-7.0), 0.0, deg_to_rad(3.0)))
					_player.recoil(0.07)
					_player.shake(1.1)
				else:
					_player.nudge(Vector3(deg_to_rad(2.4), deg_to_rad(-1.6),
						deg_to_rad(3.4 * (1.0 if i % 2 == 0 else -1.0))))
					AudioBus.sfx_at("cloth", _player.global_position, -13.0, 0.15)
					AudioBus.sfx_at("land_soft", _player.global_position, -24.0, 0.2, 1.15)

		# weight shifting about while the feet catch up
		var ramp := clampf(_fall_t / 1.7, 0.0, 1.0)
		var sway := sin(_fall_t * 3.4) * 0.055 + sin(_fall_t * 1.9 + 1.1) * 0.035
		_fall_roll = sway * (0.55 + 1.5 * ramp)
		_fall_pitch = -0.10 * ramp + sin(_fall_t * 2.6 + 0.4) * 0.045
		_fall_yaw = sin(_fall_t * 1.4) * 0.05 * ramp

		# the heel finds nothing
		if _fall_t > 1.62 and not _player.is_on_floor():
			_airborne = true
			_player.shake(0.7)
			AudioBus.sfx("ring", -26.0, 0.05)
		elif _fall_t > 2.6:
			# it did not take. Put them over the side rather than lose the beat
			var over := _world_of(hall, hall["platform_at"] as Vector3) \
				+ _away() * (Rooms.PLATFORM_R + 1.2) + Vector3(0.0, 0.5, 0.0)
			_player.teleport_to(over)
			_player.look_lock(true)
			_airborne = true
	else:
		# turning over, with the light going away above you
		var air := _fall_t - 1.62
		_fall_pitch = lerpf(_fall_pitch, 0.95, clampf(1.6 * delta, 0.0, 1.0))
		_fall_roll += (0.9 + sin(air * 2.2) * 0.5) * delta
		_fall_yaw = sin(air * 1.6) * 0.22
		_stun_want = clampf(0.35 + air * 0.35, 0.0, 0.8)
		if fmod(air, 0.5) < delta:
			_player.nudge(Vector3(0.0, 0.0, deg_to_rad(4.0)))
		if _player.is_on_floor() and air > 0.25:
			_fall_on = false
			_land()
		elif air > 5.0:
			_fall_on = false
			_land()

	if head != null:
		head.rotation = Vector3(_fall_pitch, _fall_yaw, _fall_roll)


func _land() -> void:
	_token += 1
	var token := _token
	var at := _player.global_position
	AudioBus.sfx_at("pillow_thud", at, -4.0, 0.05)
	AudioBus.sfx_at("cloth", at, -5.0, 0.12)
	_player.shake(3.2)
	_player.recoil(0.11)
	_stun_want = 1.0
	_stun = 0.85
	Kit.burst(hall["root"] as Node3D, _local_of(hall, at) + Vector3(0.0, 0.2, 0.0),
		Vector3(0.8, 0.1, 0.8), Vector3(0, 1, 0), 2.6, 60, Color(0.80, 0.77, 0.72), 0.055, 2.0).restart()
	_set_stage(Stage.OUT)
	await get_tree().create_timer(0.35).timeout
	if token != _token:
		return
	Fade.set_black()
	_out(token)


# --- coming round -------------------------------------------------------------

func _out(token: int) -> void:
	_player.velocity = Vector3.ZERO
	AudioBus.set_muffled(true, 0.3)
	_dread = 0.5
	_seen = 0.0
	for i in 3:
		AudioBus.sfx("heartbeat", -13.0 + float(i) * 2.0, 0.03)
		await get_tree().create_timer(0.62).timeout
		if token != _token:
			return

	# The fall drove the head's roll and yaw straight onto the node, and nothing
	# else in the game ever writes those two. Coming round has to put the head
	# back flat, or every minute after this one is played at whatever angle the
	# kid happened to land on.
	var head := _head()
	if head != null:
		head.rotation = Vector3.ZERO

	# on your back in the pillows, at the foot of the thing you climbed
	_player.teleport_to(_world_of(hall, hall["fall_spawn"] as Vector3))
	_face(_player, _world_of(hall, Rooms.PILLAR_C))
	_player.look_lock(false)

	var lids := WakeScript.new()
	lids.name = "DreamLids"
	lids.player_path = NodePath("..")
	lids.camera_path = NodePath("../Head/CamRig/Camera")
	lids.auto_start = false
	lids.auto_freeze = false
	lids.skippable = false
	lids.bed_offset = Vector3(0.0, -0.86, 0.0)
	lids.lie_pitch = 68.0
	lids.lie_yaw = -8.0
	lids.lie_roll = 13.0
	lids.start_delay = 0.5
	lids.sit_up_delay = 0.5
	lids.sit_up_time = 2.6
	lids.resting_vignette = 0.0
	_player.add_child(lids)
	# the lids are the black from here; two of them stacked reads as a bug
	Fade.clear_deferred()
	lids.play()
	await lids.finished
	lids.queue_free()
	if token != _token:
		return
	AudioBus.set_muffled(false, 1.0)
	_player.look_lock(false)
	_stun_want = 0.28
	_start_dark()


# --- the dark -----------------------------------------------------------------

func _start_dark() -> void:
	_set_stage(Stage.DARK)
	_dark_z = DARK_START_Z + DARK_ASSIST * float(_deaths)
	_dark_on = true
	_dying = false
	_trail_lit = 0
	var node := _voidw["node"] as Node3D
	node.visible = true
	node.position.z = _dark_z
	(_voidw["roll"] as CPUParticles3D).emitting = true
	# the way out stops being scenery
	var glow: Array = hall["exit_glow"]
	(glow[0] as OmniLight3D).light_energy = 1.25
	var sm := (glow[1] as MeshInstance3D).material_override as ShaderMaterial
	if sm != null:
		sm.set_shader_parameter("energy", 0.6)
	(glow[2] as CPUParticles3D).emitting = true
	if _hum != null and is_instance_valid(_hum):
		_hum.volume_db = -18.0
	_guide()


## Nothing about a black room forty metres across tells you where to go, so it
## gets told: the lamps come up one after another from where you are lying to
## the door, and the camera is walked round onto it once while you sit up.
func _guide() -> void:
	var token := _token
	if _deaths == 0:
		_say(LINE_RUN)
		_player.begin_cinematic()
		var door_at := _world_of(hall, Vector3(Rooms.HALL_W * 0.5 - 2.0, 1.4, Rooms.EXIT_Z))
		_pan_to(door_at, 1.4)
		await get_tree().create_timer(1.7).timeout
		if token != _token:
			return
	_player.look_lock(false)
	_player.end_cinematic()

	var trail := hall["trail"] as Array
	for i in trail.size():
		var l := trail[i] as OmniLight3D
		if not is_instance_valid(l):
			continue
		l.light_energy = float(l.get_meta("base_energy", 0.75))
		var bulb: Node3D = (l.get_meta("bulb") as Node3D) if l.has_meta("bulb") else null
		if bulb != null and is_instance_valid(bulb):
			bulb.visible = true
		AudioBus.sfx_at("switch", l.global_position, -26.0, 0.12, 1.3)
		_trail_lit = i + 1
		await get_tree().create_timer(0.11).timeout
		if token != _token:
			return


func _drive_dark(delta: float) -> void:
	if not _dark_on or _dying:
		return
	_dark_z -= DARK_SPEED * delta
	var node := _voidw["node"] as Node3D
	node.position.z = _dark_z
	# the layers crawl across each other, which is what stops six flat things
	# reading as one flat thing
	var veils := _voidw["veils"] as Array
	var layers := _voidw["layers"] as Array
	for i in veils.size():
		(veils[i] as ShaderMaterial).set_shader_parameter("t", _t * (0.6 + 0.22 * float(i)))
		var mi := layers[i] as Node3D
		mi.position.x = sin(_t * (0.13 + 0.05 * float(i)) + float(i)) * (1.4 + 0.5 * float(i))

	# anything it has already reached is out
	for l: OmniLight3D in (hall["lights"] as Array):
		if not is_instance_valid(l) or l.has_meta("exit_marker") or l.has_meta("trail"):
			continue
		if l.position.z > _dark_z - 1.5 and l.light_energy > 0.001:
			l.light_energy = maxf(0.0, l.light_energy - delta * 1.4)
			var bulb: Node3D = (l.get_meta("bulb") as Node3D) if l.has_meta("bulb") else null
			if bulb != null and is_instance_valid(bulb):
				bulb.visible = l.light_energy > 0.05

	# only inside the hall. Once you are through the door it is not your problem
	if stage != Stage.DARK:
		return
	var p := _local_of(hall, _player.global_position)
	if p.x > Rooms.HALL_W * 0.5 or p.z < -0.2:
		return
	var near := clampf((16.0 - (p.z - _dark_z)) / 16.0, 0.0, 1.0)
	_dread = maxf(_dread, near * near)
	if _env != null:
		_env.fog_density = lerpf(FOG_HALL, 0.050, near)
	if p.z > _dark_z - 0.5:
		_taken()


## Touching it costs what the monster costs: black, and back at the pillar.
func _taken() -> void:
	if _dying:
		return
	_dying = true
	_token += 1
	var token := _token
	_dark_on = false
	AudioBus.sfx_at("monster_roar", _player.global_position, -8.0, 0.05, 0.6)
	_player.shake(2.2)
	_stun_want = 0.7
	await Fade.fade_out(0.18)
	await get_tree().create_timer(0.75).timeout
	if token != _token:
		return
	_deaths += 1
	_player.teleport_to(_world_of(hall, hall["fall_spawn"] as Vector3))
	_face(_player, _world_of(hall, Vector3(Rooms.HALL_W * 0.5, 0.0, Rooms.EXIT_Z)))
	_stun_want = 0.2
	_start_dark()
	Fade.fade_in(0.45)


func _on_exit_opened() -> void:
	if stage != Stage.DARK:
		return
	_enter_run()


# --- the corridor -------------------------------------------------------------

func _enter_run() -> void:
	_set_stage(Stage.HALL)
	_dark_on = false
	_run_on = true
	_run_far = 0.0
	_run_step = RunStep.CHASING
	_arm_t = 0.0
	_cue_t = 0.0
	_prev_pz = _local_of(run, _player.global_position).z
	_door_stopped = false
	_bath_shut = false
	_handed = false
	_chase_ready = false
	_player.set_step_sound("", 0.0)
	_stun_want = 0.0
	if _env != null:
		_env.fog_density = FOG_RUN
	if _hum != null and is_instance_valid(_hum):
		_hum.volume_db = -26.0
	if not _drip_on:
		_drip_on = true
		_drip_forever()
	_seal_behind()


## The room you came from goes, and the door you came through shuts on where it
## was. The door itself is kept and moved over to the corridor rather than being
## freed and replaced, so it is the same door, standing in the same place, with
## nothing behind it any more.
func _seal_behind() -> void:
	var token := _token
	await get_tree().create_timer(1.1).timeout
	if token != _token or stage != Stage.HALL:
		return
	var hr := hall["root"] as Node3D
	var door := hall["exit_door"] as MeshInstance3D
	if door != null and is_instance_valid(door):
		door.set("swing_time", 0.45)
		door.call("set_open", false)
	await get_tree().create_timer(0.9).timeout
	if token != _token or hr == null or not is_instance_valid(hr):
		return
	if door != null and is_instance_valid(door):
		door.set("locked", true)
		door.set("locked_prompt", "It will not")
		AudioBus.sfx_at("closet_thump", door.global_position, -12.0, 0.06, 0.7)
		_player.shake(0.5)
		# keep_global_transform, or the Door's cached shut pose stops matching
		# where it is standing and the next swing snaps it across the corridor
		var frame := hr.get_node_or_null("dream exit frame") as Node3D
		door.reparent(run["root"] as Node3D, true)
		if frame != null:
			frame.reparent(run["root"] as Node3D, true)
	# everything else goes
	for d: MeshInstance3D in (hall["doors"] as Array):
		if d == door:
			continue
		var i := Presence.get_doors().find(d)
		if i >= 0:
			Presence.get_doors().remove_at(i)
		var j := _my_doors.find(d)
		if j >= 0:
			_my_doors.remove_at(j)
	_debris.clear()
	hr.queue_free()
	hall["root"] = null


## Which way the kid is looking: +1 down the corridor, -1 back up it.
func _facing() -> float:
	var cam := _player.get_camera() as Camera3D
	if cam == null or run.is_empty():
		return 1.0
	var fwd := (run["root"] as Node3D).transform.basis * Vector3(0, 0, 1)
	return (-cam.global_transform.basis.z).dot(fwd)


## The corridor really does stream past: the segments are identical and get
## re-anchored on a grid under the player, so what is behind is cut and reused
## with nothing to notice.
##
## On top of that it is a treadmill. Every segment length of forward progress
## the kid is put back one segment, and the bathroom with them - the hall is the
## same every six metres, so there is nothing in the picture that can tell, and
## the door out of the pillow hall, which never moves, ends up a few metres
## behind instead of half a minute behind. That is the whole beat: you look back
## and you never went anywhere. It is only ever done while facing down the
## corridor, so the way back can never be caught jumping.
func _drive_run(delta: float) -> void:
	if not _run_on:
		return
	var bath: Dictionary = run["bath"]
	var node := bath["node"] as Node3D
	if node == null or not is_instance_valid(node):
		return
	var seg := float(run["seg"])
	var gap := float(run["gap"])
	var pz := _local_of(run, _player.global_position).z
	var ahead := _facing()

	# a stride, not a jump: anything bigger than one frame of running is the
	# treadmill or a teleport, and neither of those is ground the kid covered
	var stride := pz - _prev_pz
	if stride > 0.0 and stride < 0.5:
		_run_far += stride
	# and the treadmill only runs while the door is still running away. Once it
	# has stopped, sliding the world back would mean the kid could never close
	# the last thirty metres either
	var rolling := _run_step == RunStep.CHASING or _run_step == RunStep.ARMED
	if rolling and ahead > 0.35 and pz > seg + RUN_KEEP:
		# never all the way back to the wall: the kid has to land in the corridor
		# and not inside the door they came through
		var back := floorf((pz - RUN_KEEP) / seg) * seg
		_player.shift_by((run["root"] as Node3D).transform.basis * Vector3(0.0, 0.0, -back))
		node.position.z -= back
		pz -= back
	_prev_pz = pz

	match _run_step:
		RunStep.CHASING:
			_slide_bath(node, pz, gap, delta)
			if _run_far > RUN_GIVE_UP:
				_arm_reveal(pz)
		RunStep.ARMED:
			_slide_bath(node, pz, gap, delta)
			_arm_t += delta
			_cue_t -= delta
			if ahead < -0.35:
				_bring_it_close(node, pz)
			elif _cue_t <= 0.0:
				_cue_t = 9.0
				_call_from_behind(pz)
			elif _arm_t > RUN_PATIENCE:
				# it will not wait forever: the door simply stops instead
				_run_step = RunStep.NEAR
				_door_stopped = true
				AudioBus.sfx_at("door_locked", node.global_position, -22.0, 0.1, 0.8)
				_player.shake(0.4)
		RunStep.TURNED:
			if ahead > 0.25:
				# and there it is
				_run_step = RunStep.NEAR
				_door_stopped = true
				_player.shake(0.5)
				_roar = maxf(_roar, 0.35)
		RunStep.NEAR:
			if not _bath_shut and node.position.z - pz < BATH_SHUT_AT:
				_shut_the_bath()

	# Segments sit on a grid anchored to the player, so the walls really do
	# stream past. A segment drops out once it would reach past the door; the
	# plug the door carries is longer than one segment, so what it leaves behind
	# is always covered and never doubled up on a surface.
	var door_z := node.position.z
	var segs := run["segs"] as Array
	var base := floorf((pz - seg * 1.5) / seg) * seg
	for k in segs.size():
		var s := segs[k] as Node3D
		var z := base + float(k) * seg
		s.position.z = z
		var on := z + seg <= door_z + 0.01
		if s.visible != on:
			s.visible = on
	_drive_lamps(pz)


func _slide_bath(node: Node3D, pz: float, gap: float, delta: float) -> void:
	# eased, so it is a hallway that will not end rather than a prop on rails,
	# and never allowed to drift back toward you
	var want := pz + gap
	node.position.z = maxf(lerpf(node.position.z, want, clampf(5.0 * delta, 0.0, 1.0)),
		pz + gap * 0.8)


## The corridor arrives out of the dark rather than standing there fully lit.
##
## This is most of what makes the thing work. The segment that drops out where
## the bathroom's own stretch of corridor takes over is thirty metres away, and
## with the lamps out that far it is a hidden black wall behind a black wall.
## Lit, it was a bulb blinking on and off down the hall every few strides, which
## is exactly how you catch a corridor cheating.
func _drive_lamps(pz: float) -> void:
	# untyped, then checked: a typed loop variable errors on the way in if the
	# list has picked up anything freed
	for entry in (run["lights"] as Array):
		if not is_instance_valid(entry):
			continue
		var l := entry as OmniLight3D
		if l == null or l.has_meta("bath"):
			continue
		var base := float(l.get_meta("base_energy", 0.62))
		var d := _local_of(run, l.global_position).z - pz
		l.light_energy = base * clampf((LAMP_LIT + LAMP_FADE - d) / LAMP_FADE, 0.0, 1.0)
		var bulb: Node3D = (l.get_meta("bulb") as Node3D) if l.has_meta("bulb") else null
		if bulb != null and is_instance_valid(bulb):
			bulb.visible = l.light_energy > base * 0.06


## Thirty metres of nothing is enough. The corridor stops pretending it is going
## to end, and starts pointing at the way back.
func _arm_reveal(pz: float) -> void:
	_run_step = RunStep.ARMED
	_arm_t = 0.0
	_cue_t = 6.0
	_say(LINE_BACK)
	_call_from_behind(pz)


func _call_from_behind(pz: float) -> void:
	var at := _world_of(run, Vector3(0.0, 1.0, pz - 3.0))
	AudioBus.sfx_at("door_latch", at, -15.0, 0.06, 0.85)
	AudioBus.sfx_at("closet_thump", at, -19.0, 0.08, 0.7)


## You turned round, and the door out of the pillow hall is three metres away:
## every stride of that run bought nothing. While your eyes are on it the far
## end of the corridor is quietly folded up and the bathroom is set down where
## the next lamp used to be, standing open, lit, close enough to walk to.
func _bring_it_close(node: Node3D, pz: float) -> void:
	_run_step = RunStep.TURNED
	node.position.z = pz + BATH_NEAR
	var bath: Dictionary = run["bath"]
	var door := bath["door"] as MeshInstance3D
	if door != null and is_instance_valid(door):
		door.call("snap_open", true)
	var l := bath["light"] as OmniLight3D
	if l != null and is_instance_valid(l):
		l.light_energy = float(l.get_meta("base_energy", 1.5))
	if _env != null:
		_env.fog_density = FOG_SEEN
	AudioBus.sfx_at("drip", node.global_transform * (bath["drip_at"] as Vector3), -17.0, 0.1)


## You get your look at it, and then you do not.
func _shut_the_bath() -> void:
	_bath_shut = true
	_set_stage(Stage.SEEN)
	var bath: Dictionary = run["bath"]
	var door := bath["door"] as MeshInstance3D
	if door != null and is_instance_valid(door):
		door.set("swing_time", 0.28)
		door.call("set_open", false)
		AudioBus.sfx_at("door_smash", door.global_position, -9.0, 0.06, 0.85)
	_player.shake(1.5)
	_player.recoil(0.05)
	_roar = maxf(_roar, 0.55)
	_swap_bathroom_for_the_chase()


## Behind the shut door the bathroom is taken away and the chase is built out of
## this very doorway. Nothing is faded and nobody is moved: when the kid pulls
## the door open again the hallway is simply what is there.
func _swap_bathroom_for_the_chase() -> void:
	var token := _token
	await get_tree().create_timer(0.4).timeout
	if token != _token or stage != Stage.SEEN:
		return
	var bath: Dictionary = run["bath"]
	var interior := bath["room"] as Node3D
	if interior != null and is_instance_valid(interior):
		interior.queue_free()
	bath["room"] = null
	var l := bath["light"] as OmniLight3D
	if l != null and is_instance_valid(l):
		# it went with the room, but the fade reads the list every frame
		(run["lights"] as Array).erase(l)
	_chase_ready = _prepare_chase()


func _prepare_chase() -> bool:
	if test_no_handoff or _root == null:
		return false
	var chase := _root.get_node_or_null("Chase")
	if chase == null or not chase.has_method("prepare_from_portal"):
		return false
	var bath: Dictionary = run["bath"]
	var node := bath["node"] as Node3D
	var door := bath["door"] as MeshInstance3D
	if node == null or not is_instance_valid(node) or door == null:
		return false
	# the room convention: the centre of the doorway at floor level on the far
	# side of the wall it is set in, +z running on into whatever comes next
	var portal := (run["root"] as Node3D).transform \
		* Transform3D(Basis.IDENTITY, node.position + Vector3(0.0, 0.0, Kit.WALL))
	# Segments the door has already run past are invisible but still solid, and
	# they sit in exactly the stretch of world the first hallway is about to be
	# built into. Invisible walls in the chase is not a trade worth making for
	# geometry nobody can see or reach. Their lamps have to come out of the list
	# by parentage rather than by validity: queue_free only lands at the end of
	# the frame, and a freed light still in there is an error every tick after.
	var doomed: Array[Node3D] = []
	for s: Node3D in (run["segs"] as Array):
		if is_instance_valid(s) and not s.visible:
			doomed.append(s)
	if not doomed.is_empty():
		var kept: Array[OmniLight3D] = []
		for entry in (run["lights"] as Array):
			var l := entry as OmniLight3D
			if l == null:
				continue
			var going := false
			for s in doomed:
				if s.is_ancestor_of(l):
					going = true
					break
			if not going:
				kept.append(l)
		run["lights"] = kept
		for s in doomed:
			s.queue_free()
	run["segs"] = [] as Array

	# the dream puts the level's own environment back first, so what the chase
	# saves when it raises its is the level's values and not the nightmare's
	_set_env(false)
	# and the distance fade stops with the dream, so the corridor is handed over
	# lit rather than frozen half dark
	for entry in (run["lights"] as Array):
		if not is_instance_valid(entry):
			continue
		var l := entry as OmniLight3D
		if l == null:
			continue
		l.light_energy = float(l.get_meta("base_energy", 0.62))
		var bulb: Node3D = (l.get_meta("bulb") as Node3D) if l.has_meta("bulb") else null
		if bulb != null and is_instance_valid(bulb):
			bulb.visible = true
	return bool(chase.call("prepare_from_portal", portal, _corridor_entry()))


## What the chase gets to treat as its room zero: the corridor the kid is
## standing in, with the bathroom door as its way out. That is all it takes for
## the first hallway to slam that door and start pounding on it.
func _corridor_entry() -> Dictionary:
	var lights: Array[OmniLight3D] = []
	for entry in (run["lights"] as Array):
		if is_instance_valid(entry) and entry is OmniLight3D:
			lights.append(entry as OmniLight3D)
	var pz := _local_of(run, _player.global_position).z
	var node := (run["bath"] as Dictionary)["node"] as Node3D
	var far := (node.position.z if node != null and is_instance_valid(node) else pz + BATH_NEAR) + 0.4
	var g := NavGraphScript.new()
	var pts: Array[Vector3] = [Vector3(0.0, 0.0, pz - 2.0), Vector3(0.0, 0.0, far - 0.6)]
	g.chain(pts)
	# what is actually left standing, not the forty-eight metres the corridor
	# reserved for itself while it was still pretending to go somewhere: the
	# hallways have to route around this, and a footprint that lies costs the
	# chain most of its turns
	var half := Rooms.RUN_W * 0.5 + 0.5
	var near := pz - float(run["seg"]) * 3.0
	return {
		"root": run["root"],
		"type": "corridor",
		"spawn": Vector3(0.0, 0.0, pz),
		"doors": [] as Array,
		"lights": lights,
		"panes": [] as Array,
		"shafts": [] as Array,
		"motes": [] as Array,
		"crawls": [] as Array,
		"events": [] as Array,
		"loops": [] as Array,
		"graph": g,
		"entry_trigger": null,
		"exit_door": (run["bath"] as Dictionary)["door"],
		"footprint": AABB(Vector3(-half, -0.5, near),
			Vector3(half * 2.0, Kit.CEIL + 1.0, far - near)),
		"head_start": 99.0,
	}


## The panel sets `is_open` the instant it is pressed, a whole swing before the
## `opened` signal. Catching it there is what lets the world behind the door be
## the chase's from the first frame the panel moves rather than half a second
## after the player has already seen through it.
func _watch_the_door() -> void:
	if stage != Stage.SEEN or _handed or run.is_empty():
		return
	var door := (run["bath"] as Dictionary)["door"] as MeshInstance3D
	if door == null or not is_instance_valid(door) or not bool(door.get("is_open")):
		return
	_handed = true
	_finish()


func _on_bath_opened() -> void:
	if stage != Stage.SEEN or _handed:
		return
	_handed = true
	_finish()


func _drip_forever() -> void:
	var bath: Dictionary = run["bath"]
	var node := bath["node"] as Node3D
	while is_instance_valid(node) and (stage == Stage.HALL or stage == Stage.SEEN):
		await get_tree().create_timer(randf_range(1.4, 3.0)).timeout
		if not is_instance_valid(node) or (stage != Stage.HALL and stage != Stage.SEEN):
			return
		# once the room behind the door has gone there is no tap left to drip
		if bath.get("room") == null:
			return
		AudioBus.sfx_at("drip", node.global_transform * (bath["drip_at"] as Vector3), -21.0, 0.1)


# --- handing over -------------------------------------------------------------

func _finish() -> void:
	if stage == Stage.DONE:
		return
	_set_stage(Stage.DONE)
	_token += 1
	_run_on = false
	set_process(false)
	set_physics_process(false)

	if _chase_ready:
		# The hallway is already standing behind that door. No fade, no cut, and
		# above all nobody moved: the corridor the kid is in becomes the chase's
		# first room and the panel they just pulled becomes its way out.
		var chase := _root.get_node_or_null("Chase")
		_release()
		# started before `finished` goes out, not after: Presence wires that
		# signal straight to Chase.begin, and begin only stands down once the
		# chase is already running
		if chase != null and chase.has_method("start_from_portal"):
			if chase.has_signal("room_entered"):
				chase.connect("room_entered", _drop_corridor)
			chase.call("start_from_portal")
		finished.emit()
		return

	await Fade.fade_out(0.9)
	_teardown()
	finished.emit()
	if not test_no_handoff:
		# whatever picks this up (Chase) has already put the player where it
		# wants them by now, so it is safe to come back up
		await get_tree().create_timer(0.2).timeout
		Fade.fade_in(1.2)


## Two hallways on, the corridor is behind a locked door that cannot be come
## back through, and every metre of it is still solid. Leaving it standing means
## the chase has to route the rest of the chain around geometry nobody will ever
## see again, so once it is out of the picture it goes.
func _drop_corridor(index: int) -> void:
	if index < 2 or world == null or not is_instance_valid(world):
		return
	# out of Presence's registry first: get_door walks that list by name, and a
	# freed panel left in it takes the real bathroom door down with it
	_unregister()
	world.queue_free()
	world = null
	run = {}


## Everything the dream was driving, let go of. Kept apart from freeing the
## world, because on the hand-off the corridor stays standing - it is the chase's
## room zero from here on.
func _release() -> void:
	if monster != null and is_instance_valid(monster):
		monster.queue_free()
	monster = null
	if _hum != null and is_instance_valid(_hum):
		_hum.queue_free()
	_hum = null
	_debris.clear()
	if not _chase_ready:
		_set_env(false)
	_player.set_step_sound("", 0.0)
	_player.look_lock(false)
	_player.set_dread(0.0, 0.0)
	if _dread_rect != null:
		_dread_rect.visible = false
	if _stun_rect != null:
		_stun_rect.visible = false
	if _doom != null:
		_doom.set("darkness", 0.0)


func _teardown() -> void:
	_release()
	_unregister()
	if world != null and is_instance_valid(world):
		world.queue_free()
	world = null


# --- per frame ----------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	_drive_fall(delta)


func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player) or hall.is_empty():
		return
	_t += delta

	_drive_debris(delta)
	_drive_dark(delta)
	_drive_run(delta)
	_watch_the_door()

	_roar = maxf(0.0, _roar - delta * 0.45)
	_flash = maxf(0.0, _flash - delta * 3.2)
	if _rumble > 0.0:
		_rumble = maxf(0.0, _rumble - delta * 0.42)
		_player.shake(_rumble * 0.28)

	# the thing at the window is worth being afraid of for as long as it is up
	var want := _roar
	if monster != null and is_instance_valid(monster) and bool(monster.get("visible_now")):
		var to_it := monster.global_position + Vector3(0.0, 5.0, 0.0) - _player.global_position
		want = maxf(want, clampf((26.0 - to_it.length()) / 26.0, 0.0, 1.0) * 0.55)
	_dread = lerpf(_dread, want, clampf((5.0 if want > _dread else 1.6) * delta, 0.0, 1.0))
	var seen_want := _roar
	var cam := _player.get_camera() as Camera3D
	if cam != null and monster != null and is_instance_valid(monster):
		var facing := -cam.global_transform.basis.z
		var to_m := (monster.global_position + Vector3(0.0, 5.0, 0.0) - cam.global_position).normalized()
		seen_want = maxf(seen_want, pow(clampf(facing.dot(to_m), 0.0, 1.0), 3.0) * _dread)
	_seen = lerpf(_seen, seen_want, clampf((6.0 if seen_want > _seen else 2.0) * delta, 0.0, 1.0))
	# concussion lets go slowly and takes hold fast
	_stun = lerpf(_stun, _stun_want, clampf((7.0 if _stun_want > _stun else 0.55) * delta, 0.0, 1.0))
	if stage == Stage.OUT or stage == Stage.DARK:
		_stun_want = maxf(0.0, _stun_want - delta * 0.035)

	if _dread_mat != null:
		var live := _dread > 0.004 or _seen > 0.004
		if _dread_rect != null and _dread_rect.visible != live:
			_dread_rect.visible = live
		if live:
			_dread_mat.set_shader_parameter("amount", _dread)
			_dread_mat.set_shader_parameter("seen", _seen)
			_dread_mat.set_shader_parameter("t", _t)
	if _stun_mat != null:
		var on := _stun > 0.004
		if _stun_rect != null and _stun_rect.visible != on:
			_stun_rect.visible = on
		if on:
			_stun_mat.set_shader_parameter("amount", _stun)
			_stun_mat.set_shader_parameter("t", _t)
	_player.set_dread(_dread, _seen)
	if monster != null and is_instance_valid(monster):
		monster.set("dread", maxf(_dread, 0.4))
	if _doom != null:
		_doom.set("darkness", clampf(_dread * 0.28, 0.0, 0.32))

	var hr := hall["root"] as Node3D
	if hr != null and is_instance_valid(hr):
		for s: MeshInstance3D in (hall["shafts"] as Array):
			var sm := s.material_override as ShaderMaterial
			if sm != null:
				sm.set_shader_parameter("t", _t)
		for p: MeshInstance3D in (hall["panes"] as Array):
			var pm := p.material_override as ShaderMaterial
			if pm != null:
				pm.set_shader_parameter("t", _t)
				pm.set_shader_parameter("flash", _flash)
	if _hum != null and is_instance_valid(_hum):
		_hum.global_position = _player.global_position
