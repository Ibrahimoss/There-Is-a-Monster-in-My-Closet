class_name Ambience
extends Node

## Background sound bed: a constant low hum (AC) plus a cricket that chirps
## at random. Every roll_interval seconds a coin is flipped; on success one
## short chirp is cut from a random spot in the cricket recording.

@export_group("Constant hum")
@export var ac_stream: AudioStream
@export_range(-60.0, 6.0, 0.1, "suffix:dB") var ac_volume_db := -18.0

@export_group("Cricket")
@export var cricket_stream: AudioStream
@export_range(-60.0, 6.0, 0.1, "suffix:dB") var cricket_volume_db := -10.0
## Seconds between dice rolls.
@export var roll_interval := 10.0
## Chance (0..1) that a roll produces a chirp.
@export_range(0.0, 1.0) var chirp_chance := 0.5
## Length of the slice cut from the recording.
@export var chirp_length := 1.3
## Small random pitch drift so chirps don't sound identical.
@export var pitch_jitter := 0.08

var _ac: AudioStreamPlayer
var _cricket: AudioStreamPlayer
var _stop_timer: Timer


func _ready() -> void:
	if ac_stream != null:
		_ac = AudioStreamPlayer.new()
		_ac.stream = ac_stream
		_ac.volume_db = ac_volume_db
		add_child(_ac)
		_ac.play()
		# Safety net: if the stream's import somehow lost its loop flag,
		# restart the hum instead of letting the room go dead quiet.
		_ac.finished.connect(_ac.play)

	if cricket_stream != null:
		_cricket = AudioStreamPlayer.new()
		_cricket.stream = cricket_stream
		_cricket.volume_db = cricket_volume_db
		add_child(_cricket)

		_stop_timer = Timer.new()
		_stop_timer.one_shot = true
		_stop_timer.timeout.connect(_cricket.stop)
		add_child(_stop_timer)

		var roller := Timer.new()
		roller.wait_time = roll_interval
		roller.timeout.connect(_roll)
		add_child(roller)
		roller.start()


func _roll() -> void:
	if _cricket.playing:
		return  # last chirp still sounding
	if randf() > chirp_chance:
		return
	_cricket.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	var len := cricket_stream.get_length()
	var from := randf_range(0.0, maxf(0.0, len - chirp_length))
	_cricket.play(from)
	_stop_timer.start(chirp_length)
