class_name Ambience
extends Node

## Background sound bed: a constant low hum (AC) plus a cricket outside.
## Every roll_interval seconds a coin is flipped; on success one short chirp
## is cut from a random spot in the cricket recording and played from a 3D
## emitter parked just outside one of the windows nearest the player, faded
## in and out. Positional so it reads as outside.

@export_group("Constant hum")
@export var ac_stream: AudioStream
@export_range(-60.0, 6.0, 0.1, "suffix:dB") var ac_volume_db := -18.0

@export_group("Cricket")
@export var cricket_stream: AudioStream
@export_range(-60.0, 6.0, 0.1, "suffix:dB") var cricket_volume_db := -8.0
## Seconds between dice rolls.
@export var roll_interval := 10.0
## Chance (0..1) that a roll produces a chirp.
@export_range(0.0, 1.0) var chirp_chance := 0.5
## Length of the slice cut from the recording.
@export var chirp_length := 1.3
## Small random pitch drift so chirps don't sound identical.
@export var pitch_jitter := 0.08
## Metres past the glass the chirp is placed.
@export var outside_distance := 1.6
## Only the windows nearest the player are candidates, so it always reads.
@export var nearest_windows := 3
@export var house_path: NodePath = NodePath("../house")

const FADE_IN := 0.25
const FADE_OUT := 0.35

var _ac: AudioStreamPlayer
var _cricket: AudioStreamPlayer3D
var _stop_timer: Timer
var _fade: Tween
## World positions just outside each window.
var _spots: Array[Vector3] = []


func _ready() -> void:
	var bus := "Ambience" if AudioServer.get_bus_index("Ambience") >= 0 else "Master"
	if ac_stream != null:
		_ac = AudioStreamPlayer.new()
		_ac.stream = ac_stream
		_ac.volume_db = ac_volume_db
		_ac.bus = bus
		add_child(_ac)
		_ac.play()
		# Safety net: if the stream's import somehow lost its loop flag,
		# restart the hum instead of letting the room go dead quiet.
		_ac.finished.connect(_ac.play)

	if cricket_stream != null:
		_find_windows()
		_cricket = AudioStreamPlayer3D.new()
		_cricket.stream = cricket_stream
		_cricket.volume_db = cricket_volume_db
		_cricket.bus = bus
		# garden scale, and glass takes the top off
		_cricket.unit_size = 5.0
		_cricket.max_distance = 30.0
		_cricket.attenuation_filter_cutoff_hz = 4500.0
		_cricket.attenuation_filter_db = -18.0
		add_child(_cricket)

		_stop_timer = Timer.new()
		_stop_timer.one_shot = true
		_stop_timer.timeout.connect(_fade_out)
		add_child(_stop_timer)

		var roller := Timer.new()
		roller.wait_time = roll_interval
		roller.timeout.connect(_roll)
		add_child(roller)
		roller.start()


## Window frames in the house: the thin axis is the wall normal, the outside
## is the side away from the house centre.
func _find_windows() -> void:
	_spots.clear()
	var house := get_node_or_null(house_path)
	if house == null:
		return
	var frames: Array[MeshInstance3D] = []
	var stack: Array[Node] = [house]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.push_back(c)
		if n is MeshInstance3D and String(n.name).begins_with("Window_frame") and (n as MeshInstance3D).mesh != null:
			frames.append(n as MeshInstance3D)
	if frames.is_empty():
		return
	var boxes: Array[AABB] = []
	var centre := Vector3.ZERO
	for f in frames:
		var b := MeshUtil.world_aabb(f)
		boxes.append(b)
		centre += b.get_center()
	centre /= float(frames.size())
	for b in boxes:
		var c := b.get_center()
		var normal := Vector3(1, 0, 0) if b.size.x < b.size.z else Vector3(0, 0, 1)
		var out := normal * signf((c - centre).dot(normal))
		if out == Vector3.ZERO:
			out = normal
		_spots.append(c + out * outside_distance)


func _pick_spot() -> Vector3:
	if _spots.is_empty():
		return Vector3.ZERO
	var listener := get_viewport().get_camera_3d()
	if listener == null:
		return _spots[randi() % _spots.size()]
	var lp := listener.global_position
	var sorted := _spots.duplicate()
	sorted.sort_custom(func(a: Vector3, b: Vector3) -> bool:
		return a.distance_squared_to(lp) < b.distance_squared_to(lp))
	var n := mini(nearest_windows, sorted.size())
	return sorted[randi() % n]


func _roll() -> void:
	if _cricket.playing:
		return  # last chirp still sounding
	if randf() > chirp_chance:
		return
	_cricket.global_position = _pick_spot()
	_cricket.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	var len := cricket_stream.get_length()
	var from := randf_range(0.0, maxf(0.0, len - chirp_length))
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_cricket.volume_db = cricket_volume_db - 30.0
	_cricket.play(from)
	_fade = create_tween()
	_fade.tween_property(_cricket, "volume_db", cricket_volume_db, FADE_IN)
	_stop_timer.start(maxf(chirp_length - FADE_OUT, 0.1))


func _fade_out() -> void:
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_fade = create_tween()
	_fade.tween_property(_cricket, "volume_db", cricket_volume_db - 30.0, FADE_OUT)
	_fade.tween_callback(_cricket.stop)
