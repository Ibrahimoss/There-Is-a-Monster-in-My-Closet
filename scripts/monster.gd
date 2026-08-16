extends Node3D
## The thing out of the closet.
##
## It never uses a navmesh: every room hands it a small graph of points and it
## walks those, hopping node to node, until it gets close enough to see the kid
## and lunge straight at them. Speed rubber-bands on distance so it is always
## just behind, and it drops a notch for every time it has already caught you
## in this room.
##
## It eats light: any lamp it walks near fades out, which is how you see it
## coming down a hall before you can make out its shape.

signal caught

const NavGraphScript := preload("res://scripts/nav_graph.gd")
const VIEW_SHADER := preload("res://scripts/monster_view.gdshader")
const ART_PATH := "res://assets/monster/monster.png"

enum State { HIDDEN, EMERGE, HUNT, FROZEN }

const HEIGHT := 2.45
const WIDTH := 1.15
## Feet-to-eyes, for the line of sight test.
const CHEST := 1.4
const CATCH_XZ := 0.62
const CATCH_Y := 1.3
const LUNGE_RANGE := 2.6
const REPATH := 0.2
const STEP_TIME := 0.42
## House stage: the slow walk out of the closet, then the real pace.
const LURCH_SPEED := 1.9
const HOUSE_SPEED := 2.5
const LURCH_TIME := 3.5

var state := State.HIDDEN
var graph: NavGraphScript
var target: CharacterBody3D
## Every catch in the same room takes a shaving off the top speed.
var assist_speed_mul := 1.0
## The lamps close enough to be worth checking each tick.
var lights: Array[OmniLight3D] = []
var visible_now := false
## 0..1, how far into the player's head it is. Set by the director; drives how
## torn up it looks and how deep it sounds.
var dread := 0.0

var _view: MeshInstance3D
var _mat: ShaderMaterial
var _breath: AudioStreamPlayer3D
var _from := -1
var _way := -1
var _repath := 0.0
var _t := 0.0
var _step := 0.0
var _steps := 0
var _amount := 0.0
var _amount_target := 0.0
var _house := false
var _lurch := 0.0
var _lurch_goal := -1
var _eyes := 0.0
var _roar_until := 0.0
var _lateral := 0.0
var _glitch_in := 1.0


func setup(player: CharacterBody3D) -> void:
	target = player
	_build_view()
	_breath = AudioBus.loop_at("monster_breath", self, global_position, -60.0)
	if _breath != null:
		_breath.unit_size = 4.0
		_breath.max_distance = 22.0
	visible = false
	set_physics_process(true)


func _build_view() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = VIEW_SHADER
	if ResourceLoader.exists(ART_PATH):
		var img := (load(ART_PATH) as Texture2D).get_image()
		if img != null:
			img.convert(Image.FORMAT_RGBA8)
			# a drawing on white paper: key the paper out
			for y in img.get_height():
				for x in img.get_width():
					var c := img.get_pixel(x, y)
					if c.r > 0.93 and c.g > 0.93 and c.b > 0.93:
						c.a = 0.0
					img.set_pixel(x, y, c)
			_mat.set_shader_parameter("tex", ImageTexture.create_from_image(img))
			_mat.set_shader_parameter("use_tex", true)
	_mat.set_shader_parameter("visible_amount", 0.0)

	var quad := QuadMesh.new()
	quad.size = Vector2(WIDTH, HEIGHT)
	_view = MeshInstance3D.new()
	_view.name = "View"
	_view.mesh = quad
	_view.material_override = _mat
	_view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_view.position = Vector3(0.0, HEIGHT * 0.5, 0.0)
	add_child(_view)


# --- what the director asks for ------------------------------------------------

## House stage: stand up in the closet and lurch toward the bed before it turns
## on the kid.
func begin_house(path: Array[Vector3]) -> void:
	var g := NavGraphScript.new()
	var pts: Array[Vector3] = []
	for p in path:
		pts.append(p)
	g.chain(pts)
	graph = g
	_house = true
	global_position = path[0]
	_from = 0
	_way = 1
	_lurch = LURCH_TIME
	_lurch_goal = mini(2, path.size() - 1)
	state = State.EMERGE
	_show(0.5)
	AudioBus.sfx_at("monster_roar", global_position, -16.0, 0.05, 1.1)


## A room burst its door: come through it and start hunting.
func enter_room(room_graph: NavGraphScript, at: Vector3) -> void:
	graph = room_graph
	_house = false
	global_position = at
	_from = graph.nearest_node(at)
	_way = _from
	_repath = 0.0
	state = State.HUNT
	_show(0.25)
	roar(-12.0)


func vanish(time := 0.25) -> void:
	state = State.HIDDEN
	_show_off(time)


func freeze() -> void:
	state = State.FROZEN


func roar(db := -10.0) -> void:
	AudioBus.sfx_at("monster_roar", global_position, db, 0.05)
	_roar_until = _t + 1.2


func _show(time: float) -> void:
	visible = true
	visible_now = true
	_amount_target = 1.0
	if time <= 0.0:
		_amount = 1.0
	if _breath != null and is_instance_valid(_breath):
		if not _breath.playing:
			_breath.play()
		_breath.volume_db = -18.0


func _show_off(time: float) -> void:
	visible_now = false
	_amount_target = 0.0
	if time <= 0.0:
		_amount = 0.0
		visible = false
	if _breath != null and is_instance_valid(_breath):
		_breath.volume_db = -60.0


# --- brain --------------------------------------------------------------------

func _physics_process(dt: float) -> void:
	_t += dt
	_drive_view(dt)
	_eat_light(dt)
	if target == null or graph == null or graph.size() < 2:
		return
	if state != State.HUNT and state != State.EMERGE:
		return

	var feet := global_position
	var to_player := target.global_position - feet
	var flat := Vector3(to_player.x, 0.0, to_player.z)
	var dist := flat.length()

	var speed := _speed(dist)
	var dir := Vector3.ZERO

	if state == State.EMERGE:
		_lurch -= dt
		dir = _toward_node(_lurch_goal, feet)
		if _lurch <= 0.0:
			state = State.HUNT
			_from = graph.nearest_node(feet)
			_way = _from
			_repath = 0.0
	elif dist < LUNGE_RANGE and _has_los(feet, target.global_position):
		dir = flat.normalized()
	else:
		_repath -= dt
		if _repath <= 0.0:
			_repath = REPATH
			var goal := graph.nearest_node(target.global_position)
			if _way < 0 or feet.distance_to(graph.points[_way]) < 0.35:
				_from = _way if _way >= 0 else graph.nearest_node(feet)
			_way = graph.next_node(_from, goal)
		dir = _toward_node(_way, feet)
		# a steep edge is climbed, not run
		if _way >= 0 and _from >= 0 and absf(graph.points[_way].y - feet.y) > 0.5:
			speed *= 0.8

	if dir != Vector3.ZERO:
		global_position += dir * speed * assist_speed_mul * dt
		var side := 0.0
		if dist > 0.05:
			side = dir.rotated(Vector3.UP, PI * 0.5).dot(flat / dist)
		_lateral = lerpf(_lateral, side, 4.0 * dt)
		_footfall(dt, speed)

	if dist < CATCH_XZ and absf(to_player.y) < CATCH_Y:
		state = State.FROZEN
		caught.emit()


## Straight at node `i`, but rising or falling with the edge so stairs read.
func _toward_node(i: int, feet: Vector3) -> Vector3:
	if i < 0 or i >= graph.size():
		return Vector3.ZERO
	var to := graph.points[i] - feet
	if to.length() < 0.02:
		return Vector3.ZERO
	return to.normalized()


## Always just behind: fast when it has ground to make up, near walking pace
## once it is breathing on you.
func _speed(d: float) -> float:
	if _house:
		return LURCH_SPEED if state == State.EMERGE else HOUSE_SPEED
	if d > 8.0:
		return 3.5
	if d > 4.0:
		return 3.0
	if d > 2.0:
		return 2.75
	return 2.55


func _has_los(from: Vector3, to: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(
		from + Vector3(0.0, CHEST, 0.0), to + Vector3(0.0, 1.0, 0.0), 1)
	return space.intersect_ray(q).is_empty()


func _footfall(dt: float, speed: float) -> void:
	_step += dt * clampf(speed / 2.75, 0.5, 1.4)
	if _step < STEP_TIME:
		return
	_step = 0.0
	_steps += 1
	AudioBus.sfx_at("monster_step", global_position, -16.0, 0.12)
	if _steps % 4 == 0:
		AudioBus.sfx_at("closet_thump", global_position, -20.0, 0.08, 0.6)


# --- the look of it -----------------------------------------------------------

func _drive_view(dt: float) -> void:
	_amount = move_toward(_amount, _amount_target, dt * 4.0)
	if _amount <= 0.001 and _amount_target <= 0.0:
		visible = false
	_mat.set_shader_parameter("visible_amount", _amount)
	_mat.set_shader_parameter("t", _t)
	_eyes = 1.0 if _t < _roar_until else (0.72 + 0.28 * dread)
	_mat.set_shader_parameter("eyes", _eyes)
	# it comes apart more the closer it gets to you
	_mat.set_shader_parameter("glitch",
		0.55 + 0.45 * float(state == State.HUNT) + 0.9 * dread)
	# it breathes, and leans into the way it is going
	var breath := 1.0 + sin(_t * TAU * 0.45) * 0.02
	_view.scale = Vector3(1.0, breath, 1.0)
	_view.position.y = HEIGHT * 0.5 * breath - absf(sin(_t * TAU / STEP_TIME)) * 0.03
	_mat.set_shader_parameter("lean", clampf(_lateral, -1.0, 1.0))
	if _breath != null and is_instance_valid(_breath) and visible_now and target != null:
		# it gets louder and drops in pitch as it closes, which is most of why
		# it reads as bearing down on you rather than just being nearby
		_breath.volume_db = lerpf(-20.0, -8.0, dread)
		_breath.pitch_scale = lerpf(1.0, 0.72, dread)
	# and it tears at itself, more often the closer it is
	if visible_now and state == State.HUNT and dread > 0.12:
		_glitch_in -= dt
		if _glitch_in <= 0.0:
			_glitch_in = randf_range(0.5, 2.4) * (1.2 - dread)
			AudioBus.sfx_at("monster_glitch", global_position + Vector3(0.0, 1.4, 0.0),
				lerpf(-24.0, -9.0, dread), 0.18, randf_range(0.75, 1.05))


## Lamps go out as it comes: the only warning the hallway gives.
func _eat_light(dt: float) -> void:
	var k := 1.0 - exp(-8.0 * dt)
	for l in lights:
		if not is_instance_valid(l):
			continue
		var base := float(l.get_meta("base_energy", 1.0))
		var want := base
		if visible_now:
			var d := l.global_position.distance_to(global_position)
			want = base * clampf((d - 1.5) / 3.5, 0.0, 1.0)
		l.light_energy = lerpf(l.light_energy, want, k)
		# windows and moonlight have no bulb to put out
		if not l.has_meta("bulb"):
			continue
		var bulb := l.get_meta("bulb") as Node3D
		if bulb != null and is_instance_valid(bulb) and l.visible:
			bulb.visible = l.light_energy > base * 0.15
