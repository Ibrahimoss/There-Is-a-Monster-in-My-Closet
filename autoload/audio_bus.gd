extends Node
## Central audio playback, autoloaded as `AudioBus`.
##
## Everything routes through here so Saturday's audio pass is one file to edit
## rather than thirty scenes to hunt through.
##
## On web, nothing plays until the player has clicked the start screen -
## browsers block all audio before a user gesture. `unlock()` is called by
## StartScreen and is what makes the first ambience actually audible.

const SFX_VOICES := 8

## Bus tree, built in code so it can never desync from the routing here:
##   Master ← World (lowpass, transparent by default) ← SFX, Ambience
##   Master ← UI
## Under-covers muffling is one tween on the single World lowpass.
const LOWPASS_OPEN := 20500.0
const LOWPASS_MUFFLED := 500.0

## Named sound registry. A name maps to a single stream or an Array of variant
## streams (picked at random, so repeated sounds never machine-gun). Missing
## names no-op with a single warning, so systems can be wired before their
## sounds exist.
const STREAMS := {
	"footstep_wood": [
		preload("res://assets/audio/steps/footstep_wood_000.ogg"),
		preload("res://assets/audio/steps/footstep_wood_001.ogg"),
		preload("res://assets/audio/steps/footstep_wood_002.ogg"),
		preload("res://assets/audio/steps/footstep_wood_003.ogg"),
		preload("res://assets/audio/steps/footstep_wood_004.ogg"),
	],
	"door_open": [
		preload("res://assets/audio/doors/creak1.ogg"),
		preload("res://assets/audio/doors/creak2.ogg"),
		preload("res://assets/audio/doors/creak3.ogg"),
	],
	"door_close": [
		preload("res://assets/audio/doors/doorClose_1.ogg"),
		preload("res://assets/audio/doors/doorClose_2.ogg"),
		preload("res://assets/audio/doors/doorClose_3.ogg"),
		preload("res://assets/audio/doors/doorClose_4.ogg"),
	],
	"door_latch": [
		preload("res://assets/audio/doors/metalLatch.ogg"),
		preload("res://assets/audio/doors/metalClick.ogg"),
	],
	"door_locked": [
		preload("res://assets/audio/doors/beltHandle1.ogg"),
		preload("res://assets/audio/doors/beltHandle2.ogg"),
	],
	"closet_thump": [
		preload("res://assets/audio/impacts/impactWood_heavy_000.ogg"),
		preload("res://assets/audio/impacts/impactWood_heavy_001.ogg"),
		preload("res://assets/audio/impacts/impactWood_heavy_002.ogg"),
	],
	"land_soft": [
		preload("res://assets/audio/impacts/impactSoft_medium_000.ogg"),
		preload("res://assets/audio/impacts/impactSoft_medium_001.ogg"),
	],
	"cloth": [
		preload("res://assets/audio/cloth/cloth1.ogg"),
		preload("res://assets/audio/cloth/cloth2.ogg"),
		preload("res://assets/audio/cloth/cloth3.ogg"),
		preload("res://assets/audio/cloth/cloth4.ogg"),
	],
	"switch": preload("res://assets/audio/doors/metalClick.ogg"),
	"room_tone": preload("res://assets/audio/ambience/crickets_night.mp3"),
	# real weather beats anything synthesised: field recordings out of the
	# Sonniss GDC bundles, trimmed and cut down for the web build
	"rain": preload("res://assets/audio/weather/rain_loop.ogg"),
	"thunder": [
		preload("res://assets/audio/weather/thunder_close.ogg"),
		preload("res://assets/audio/weather/thunder_far.ogg"),
	],
}

## Music is loaded on demand rather than preloaded: it is the one big file in
## the project, and an autoload that preloads it cannot parse until the file
## has been imported, which is a bootstrap knot on a fresh clone.
const MUSIC := {
	"chase": "res://assets/audio/music/run_for_your_life.mp3",
}

## Same reason as MUSIC, for anything that arrives after a clone: preloading a
## file that has never been imported deadlocks this autoload. Loaded on the
## first request and cached from then on.
const LAZY := {
	"monster_scream": "res://assets/audio/monster/monster_scream.ogg",
}

## Baked procedural streams (scripts/sound_gen.gd), made on first use so the
## start click stays cheap. Looked up after STREAMS.
const GeneratedSounds := preload("res://scripts/sound_gen.gd")

var _unlocked := false
var _sfx: Array[AudioStreamPlayer] = []
var _ambience: AudioStreamPlayer
var _ambience_tween: Tween
var _music: AudioStreamPlayer
var _music_tween: Tween
var _music_cache := {}
var _missing_warned := {}
var _generated := {}
var _lazy := {}
var _world_lowpass: AudioEffectLowPassFilter
var _muffle_tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_buses()

	for i in SFX_VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_sfx.append(p)

	_ambience = AudioStreamPlayer.new()
	_ambience.bus = "Ambience"
	add_child(_ambience)


func _build_buses() -> void:
	var world_idx := AudioServer.bus_count
	AudioServer.add_bus(world_idx)
	AudioServer.set_bus_name(world_idx, "World")
	AudioServer.set_bus_send(world_idx, "Master")
	_world_lowpass = AudioEffectLowPassFilter.new()
	_world_lowpass.cutoff_hz = LOWPASS_OPEN
	AudioServer.add_bus_effect(world_idx, _world_lowpass)

	for bus_name in ["SFX", "Ambience"]:
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "World")

	var ui_idx := AudioServer.bus_count
	AudioServer.add_bus(ui_idx)
	AudioServer.set_bus_name(ui_idx, "UI")
	AudioServer.set_bus_send(ui_idx, "Master")


## Called once, from the start screen click. Before this, web browsers will
## silently refuse to play anything.
func unlock() -> void:
	_unlocked = true


func is_unlocked() -> bool:
	return _unlocked


func play_sfx(stream: AudioStream, volume_db := 0.0, pitch := 1.0) -> void:
	if stream == null or not _unlocked:
		return
	for p in _sfx:
		if not p.playing:
			p.stream = stream
			p.volume_db = volume_db
			p.pitch_scale = pitch
			p.play()
			return
	# All voices busy - steal the first rather than dropping the sound.
	_sfx[0].stream = stream
	_sfx[0].volume_db = volume_db
	_sfx[0].pitch_scale = pitch
	_sfx[0].play()


## One-shot positional sound. Frees itself when finished, so callers do not
## have to manage lifetimes during a jam.
func play_at(stream: AudioStream, pos: Vector3, volume_db := 0.0, pitch := 1.0) -> void:
	if stream == null or not _unlocked:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.bus = "SFX"
	# Interior-scale falloff - the defaults are tuned for outdoor distances.
	p.unit_size = 3.0
	p.max_distance = 16.0
	get_tree().current_scene.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()


## --- Named registry helpers -------------------------------------------------

## 2D (non-positional) named sound with a random variant and pitch jitter.
func sfx(sound: String, volume_db := 0.0, jitter := 0.06) -> void:
	play_sfx(_pick(sound), volume_db, _jittered(jitter))


## Positional named sound with a random variant and pitch jitter.
## `base_pitch` shifts the whole sound (dad's footsteps are the kid's,
## pitched down).
func sfx_at(sound: String, pos: Vector3, volume_db := 0.0, jitter := 0.06, base_pitch := 1.0) -> void:
	play_at(_pick(sound), pos, volume_db, base_pitch * _jittered(jitter))


func _jittered(jitter: float) -> float:
	return randf_range(1.0 - jitter, 1.0 + jitter)


func _pick(sound: String) -> AudioStream:
	if not STREAMS.has(sound):
		var lazy := _lazy_stream(sound)
		if lazy != null:
			return lazy
		var gen := _generated_stream(sound)
		if gen != null:
			return gen
		if not _missing_warned.has(sound):
			_missing_warned[sound] = true
			push_warning("AudioBus: no stream registered for '%s'" % sound)
		return null
	var entry: Variant = STREAMS[sound]
	if entry is Array:
		var variants := entry as Array
		return variants[randi() % variants.size()] as AudioStream
	return entry as AudioStream


## File-backed streams that are loaded rather than preloaded.
func _lazy_stream(sound: String) -> AudioStream:
	if _lazy.has(sound):
		return _lazy[sound] as AudioStream
	if not LAZY.has(sound):
		return null
	var path := String(LAZY[sound])
	if not ResourceLoader.exists(path):
		return null
	var s := load(path) as AudioStream
	if s != null:
		_lazy[sound] = s
	return s


## Procedural streams by name, baked the first time they are asked for.
func _generated_stream(sound: String) -> AudioStream:
	if _generated.has(sound):
		return _generated[sound] as AudioStream
	var s: AudioStream = null
	match sound:
		"water_loop":
			s = GeneratedSounds.water_loop()
		"flush":
			s = GeneratedSounds.flush()
		"drawer_slide":
			s = GeneratedSounds.drawer_slide()
		"brush":
			s = GeneratedSounds.brush()
		"drip":
			s = GeneratedSounds.drip()
		"toothbrush":
			s = GeneratedSounds.toothbrush()
		"wind":
			s = GeneratedSounds.wind()
		"heartbeat":
			s = GeneratedSounds.heartbeat()
		"monster_glitch":
			s = GeneratedSounds.monster_glitch()
		"monster_breath":
			s = GeneratedSounds.monster_breath()
		"monster_step":
			s = GeneratedSounds.monster_step()
		"monster_roar":
			s = GeneratedSounds.monster_roar()
		"door_smash":
			s = GeneratedSounds.door_smash()
		"ring":
			s = GeneratedSounds.ring()
		"void_hum":
			s = GeneratedSounds.void_hum()
		"pillow_thud":
			s = GeneratedSounds.pillow_thud()
	if s != null:
		_generated[sound] = s
	return s


## Bake named procedural sounds now, off the interaction path.
func prewarm(sounds: Array[String]) -> void:
	for s in sounds:
		_generated_stream(s)


## The stream a name resolves to (a random variant for lists), or null.
func stream(sound: String) -> AudioStream:
	return _pick(sound)


## Positional loop that the caller owns (tap water, a running thing). Parent
## it under the prop so it dies with the level. Starts silent unless unlocked.
func loop_at(sound: String, parent: Node, pos: Vector3, volume_db := -14.0) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = _pick(sound)
	p.volume_db = volume_db
	p.unit_size = 3.0
	p.max_distance = 16.0
	p.bus = "SFX"
	parent.add_child(p)
	p.global_position = pos
	if _unlocked and p.stream != null:
		p.play()
	return p


## A looping music bed on its own player, so it is independent of ambience and
## can be faded out on its own when the chase ends.
func music(sound: String, fade := 1.5, volume_db := -14.0) -> void:
	if not _unlocked or not MUSIC.has(sound):
		return
	var path: String = MUSIC[sound]
	if not _music_cache.has(sound):
		_music_cache[sound] = load(path) as AudioStream if ResourceLoader.exists(path) else null
	var stream := _music_cache[sound] as AudioStream
	if stream == null:
		return
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	if _music == null or not is_instance_valid(_music):
		_music = AudioStreamPlayer.new()
		_music.bus = "Ambience"
		add_child(_music)
	if _music.stream == stream and _music.playing:
		return
	_music.stream = stream
	_music.volume_db = -60.0
	_music.play()
	_fade_music(volume_db, fade)


func stop_music(fade := 1.5) -> void:
	if _music == null or not is_instance_valid(_music):
		return
	_fade_music(-60.0, fade)


func _fade_music(target_db: float, time: float) -> void:
	if _music_tween and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = create_tween()
	_music_tween.tween_property(_music, "volume_db", target_db, time)


## Named looping ambience. MP3 streams don't loop by default; force it.
func ambience(sound: String, fade := 2.0, volume_db := -12.0) -> void:
	var stream := _pick(sound)
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	play_ambience(stream, fade, volume_db)


## Under-covers muffle (also usable for anything "through a wall" later).
## One knob, tweens the World bus lowpass. UI bus stays clean.
func set_muffled(on: bool, time := 0.35) -> void:
	if _muffle_tween and _muffle_tween.is_valid():
		_muffle_tween.kill()
	var world := AudioServer.get_bus_index("World")
	_muffle_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_muffle_tween.tween_property(
		_world_lowpass, "cutoff_hz", LOWPASS_MUFFLED if on else LOWPASS_OPEN, time
	)
	_muffle_tween.parallel().tween_method(
		func(db: float) -> void: AudioServer.set_bus_volume_db(world, db),
		AudioServer.get_bus_volume_db(world),
		-5.0 if on else 0.0,
		time
	)


func play_ambience(stream: AudioStream, fade := 1.5, volume_db := -6.0) -> void:
	if stream == null or not _unlocked:
		return
	if _ambience.stream == stream and _ambience.playing:
		return
	_ambience.stream = stream
	_ambience.volume_db = -60.0
	_ambience.play()
	_fade_ambience(volume_db, fade)


func stop_ambience(fade := 1.5) -> void:
	_fade_ambience(-60.0, fade)
	await get_tree().create_timer(fade).timeout
	_ambience.stop()


func _fade_ambience(target_db: float, time: float) -> void:
	if _ambience_tween and _ambience_tween.is_valid():
		_ambience_tween.kill()
	_ambience_tween = create_tween()
	_ambience_tween.tween_property(_ambience, "volume_db", target_db, time)
