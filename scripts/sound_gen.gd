class_name SoundGen
extends RefCounted
## Small procedural sounds baked once into AudioStreamWAV: filtered noise
## with an envelope. Water, a flush, a drawer slide, a shoulder brush.
## Nothing here runs per frame; a stream is generated on first use and then
## played like any file.

const RATE := 22050


## White noise through a one-pole lowpass then highpass, shaped by `env(t)`
## (0..1 over the length). `lp_of_t`, if given, sweeps the lowpass cutoff.
static func noise(seconds: float, lp_hz: float, hp_hz: float, gain: float,
		env: Callable, loop: bool, lp_of_t: Callable = Callable()) -> AudioStreamWAV:
	var n := int(seconds * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var a_hp := exp(-TAU * hp_hz / RATE)
	var lp := 0.0
	var hp := 0.0
	var hp_in := 0.0
	var fade := mini(int(0.08 * RATE), n / 4)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	for i in n:
		var t := float(i) / RATE
		var cutoff := lp_hz
		if lp_of_t.is_valid():
			cutoff = float(lp_of_t.call(t))
		var a_lp := 1.0 - exp(-TAU * cutoff / RATE)
		var w := rng.randf() * 2.0 - 1.0
		lp += (w - lp) * a_lp
		hp = a_hp * (hp + lp - hp_in)
		hp_in = lp
		var s := clampf(hp * gain * float(env.call(t)), -1.0, 1.0)
		if loop and i < fade:
			s *= float(i) / float(fade)
		if loop and i > n - fade:
			s *= float(n - i) / float(fade)
		data.encode_s16(i * 2, int(s * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = n
	return wav


## Sine with a per-sample frequency and envelope, for plinks and beeps.
static func tone(seconds: float, freq: Callable, env: Callable, gain: float) -> AudioStreamWAV:
	var n := int(seconds * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		phase += TAU * float(freq.call(t)) / RATE
		var s := clampf(sin(phase) * float(env.call(t)) * gain, -1.0, 1.0)
		data.encode_s16(i * 2, int(s * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav


## One drop into a basin: a fast downward chirp that rings out.
static func drip() -> AudioStreamWAV:
	var freq := func(t: float) -> float:
		return 1050.0 + 2100.0 * exp(-t / 0.016)
	var env := func(t: float) -> float:
		return exp(-t / 0.05) * minf(1.0, t / 0.0015)
	return tone(0.22, freq, env, 0.55)


## Bristles on teeth: hiss bursts twice per stroke, seamless loop.
static func toothbrush() -> AudioStreamWAV:
	var env := func(t: float) -> float:
		var s := absf(sin(TAU * 4.5 * t))
		return pow(s, 1.6) * (0.85 + 0.15 * sin(TAU * 0.5 * t))
	return noise(2.0, 2400.0, 700.0, 1.8, env, true)


## Running tap: steady hiss with a slow wobble, seamless loop.
static func water_loop() -> AudioStreamWAV:
	var env := func(t: float) -> float:
		return 1.0 + 0.15 * sin(TAU * 0.7 * t) + 0.08 * sin(TAU * 3.1 * t + 1.7)
	return noise(3.0, 2200.0, 350.0, 3.0, env, true)


## Toilet flush: rush up, peak, drain down to a hiss.
static func flush() -> AudioStreamWAV:
	var env := func(t: float) -> float:
		if t < 0.25:
			return t / 0.25
		if t < 1.6:
			return 1.0
		if t < 3.0:
			return lerpf(1.0, 0.35, (t - 1.6) / 1.4)
		return lerpf(0.35, 0.0, (t - 3.0) / 1.0)
	var lp := func(t: float) -> float:
		if t < 1.5:
			return 1800.0
		return lerpf(1800.0, 500.0, clampf((t - 1.5) / 1.5, 0.0, 1.0))
	return noise(4.0, 1800.0, 200.0, 3.2, env, false, lp)


## Wood on wood, a drawer running on its slides.
static func drawer_slide() -> AudioStreamWAV:
	var env := func(t: float) -> float:
		return sin(PI * t / 0.35)
	return noise(0.35, 900.0, 120.0, 2.2, env, false)


## Cloth on plaster: a shoulder catching a wall.
static func brush() -> AudioStreamWAV:
	var env := func(t: float) -> float:
		return sin(PI * t / 0.18)
	return noise(0.18, 1200.0, 300.0, 1.4, env, false)
