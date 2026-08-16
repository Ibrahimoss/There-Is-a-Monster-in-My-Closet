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






## A heart, from the inside: two thuds, the second softer, and nothing else.
static func heartbeat() -> AudioStreamWAV:
	var n := int(0.62 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		# lub at 0, dub at 0.19, both a short low thump
		var a := exp(-t / 0.055) * minf(1.0, t / 0.006)
		var b := 0.0
		if t > 0.19:
			var u := t - 0.19
			b = exp(-u / 0.07) * minf(1.0, u / 0.006) * 0.62
		phase += TAU * lerpf(64.0, 38.0, minf(1.0, t / 0.3)) / RATE
		out[i] = sin(phase) * (a + b) * 0.95
	return _bake(out, false)


## The thing glitching: a burst of digital tearing, pitched down. Synthetic on
## purpose - this is the one sound that should not sound like a recording.
static func monster_glitch() -> AudioStreamWAV:
	var n := int(0.45 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 31337
	var held := 0.0
	var hold_for := 0
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		# sample-and-hold noise: the rate drops through the burst, which is
		# what gives it the torn, downsampled edge
		if hold_for <= 0:
			held = rng.randf() * 2.0 - 1.0
			hold_for = int(lerpf(12.0, 90.0, t / 0.45)) + rng.randi_range(0, 8)
		hold_for -= 1
		phase += TAU * lerpf(58.0, 27.0, minf(1.0, t / 0.45)) / RATE
		var env := minf(1.0, t / 0.008) * exp(-t / 0.22)
		out[i] = (held * 0.55 + sin(phase) * 0.7) * env * 0.9
	return _bake(out, false)


## Night air moving through a hedge corridor. Slow, wide, nothing in it.
static func wind() -> AudioStreamWAV:
	var env := func(t: float) -> float:
		return 0.72 + 0.28 * sin(TAU * t / 6.0) + 0.12 * sin(TAU * t / 3.0 + 0.9)
	return noise(6.0, 520.0, 90.0, 2.4, env, true)


## Raw samples into a 16-bit mono WAV, looping or not. The bespoke sounds below
## mix layers per sample, which `noise` and `tone` cannot do.
static func _bake(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var n := samples.size()
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
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


## Something breathing where nothing should be: brown noise under a heavy
## low-pass, swelling twice every five seconds, with a hum sitting beneath it.
## The swell reaches zero at both ends, so the loop has no seam.
static func monster_breath() -> AudioStreamWAV:
	var n := int(5.0 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	var a_lp := 1.0 - exp(-TAU * 180.0 / RATE)
	var brown := 0.0
	var lp := 0.0
	var lp2 := 0.0
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		brown = clampf(brown * 0.995 + (rng.randf() * 2.0 - 1.0) * 0.05, -1.0, 1.0)
		lp += (brown - lp) * a_lp
		lp2 += (lp - lp2) * a_lp
		var swell := pow(maxf(sin(TAU * 0.4 * t), 0.0), 1.4)
		phase += TAU * 52.0 / RATE
		out[i] = lp2 * 6.0 * swell + sin(phase) * 0.126 * swell
	return _bake(out, true)


## One heavy foot: a low thump with a scuff of grit on the front of it.
static func monster_step() -> AudioStreamWAV:
	var n := int(0.11 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var a_lp := 1.0 - exp(-TAU * 900.0 / RATE)
	var lp := 0.0
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		phase += TAU * 60.0 / RATE
		lp += ((rng.randf() * 2.0 - 1.0) - lp) * a_lp
		out[i] = sin(phase) * exp(-t / 0.035) * 0.85 + lp * exp(-t / 0.012) * 0.5
	return _bake(out, false)


## The roar: a growl that sags as it runs out, with air behind it.
static func monster_roar() -> AudioStreamWAV:
	var n := int(1.2 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7717
	var a_lp := 1.0 - exp(-TAU * 1200.0 / RATE)
	var lp := 0.0
	var car := 0.0
	var modu := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := t / 1.2
		car += TAU * lerpf(70.0, 48.0, f) / RATE
		modu += TAU * 23.0 / RATE
		lp += ((rng.randf() * 2.0 - 1.0) - lp) * a_lp
		var env := minf(1.0, t / 0.05) * exp(-t / 0.55)
		out[i] = sin(car + lerpf(3.0, 1.0, f) * sin(modu)) * env * 0.8 \
			+ lp * exp(-t / 0.35) * 0.3
	return _bake(out, false)


## A door being put through rather than opened: the latch and the frame letting
## go as three hard cracks with no attack ramp on them at all, a low thump
## sagging underneath, and splinters trailing off. The door sounds already here
## are all smooth swings, which is why a burst reads as somebody turning a
## handle politely instead of a body hitting wood at a run.
static func door_smash() -> AudioStreamWAV:
	var n := int(0.5 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150
	var a_lp := 1.0 - exp(-TAU * 2600.0 / RATE)
	var lp := 0.0
	var phase := 0.0
	# the latch, the frame, then a board giving way a beat later
	var cracks := [0.0, 0.021, 0.058]
	for i in n:
		var t := float(i) / RATE
		phase += TAU * lerpf(78.0, 44.0, minf(1.0, t / 0.2)) / RATE
		var w := rng.randf() * 2.0 - 1.0
		lp += (w - lp) * a_lp
		var body := sin(phase) * exp(-t / 0.085) * 0.9
		var crack := 0.0
		for c: float in cracks:
			if t >= c:
				crack += w * exp(-(t - c) / 0.006) * 0.8
		out[i] = clampf(body + crack + lp * exp(-t / 0.13) * 0.35, -1.0, 1.0)
	return _bake(out, false)


## What is left in your ears after something has shouted at you from close up:
## two sines a little apart so they beat against each other, fading out over
## three seconds. Meant to sit under a muffled world, not over it.
static func ring() -> AudioStreamWAV:
	var n := int(3.2 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var p1 := 0.0
	var p2 := 0.0
	for i in n:
		var t := float(i) / RATE
		p1 += TAU * 4180.0 / RATE
		p2 += TAU * 4655.0 / RATE
		var env := minf(1.0, t / 0.03) * exp(-t / 1.15)
		out[i] = (sin(p1) * 0.6 + sin(p2) * 0.4) * env * 0.5
	return _bake(out, false)


## The dark itself: two low sines beating slowly with a breath of noise over
## them. Eight seconds, and every partial is an exact multiple of the loop rate
## so the seam is not a click.
static func void_hum() -> AudioStreamWAV:
	var secs := 8.0
	var n := int(secs * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	var a_lp := 1.0 - exp(-TAU * 220.0 / RATE)
	var lp := 0.0
	var fade := int(0.5 * RATE)
	for i in n:
		var t := float(i) / RATE
		var w := rng.randf() * 2.0 - 1.0
		lp += (w - lp) * a_lp
		var s := sin(TAU * 32.0 * t) * 0.55 + sin(TAU * 47.0 * t) * 0.32 + sin(TAU * 19.0 * t) * 0.22
		var air := lp * 0.30
		# only the noise is crossfaded; the sines close on themselves already
		if i < fade:
			air *= float(i) / float(fade)
		elif i > n - fade:
			air *= float(n - i) / float(fade)
		out[i] = clampf((s + air) * 0.55, -1.0, 1.0)
	return _bake(out, true)


## A body landing in a heap of cushions: almost no crack, a lot of air being
## pushed out, and a low sag under it that dies inside a fifth of a second.
static func pillow_thud() -> AudioStreamWAV:
	var n := int(0.55 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 6023
	var a_lp := 1.0 - exp(-TAU * 900.0 / RATE)
	var lp := 0.0
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		phase += TAU * lerpf(72.0, 41.0, minf(1.0, t / 0.12)) / RATE
		var w := rng.randf() * 2.0 - 1.0
		lp += (w - lp) * a_lp
		var body := sin(phase) * exp(-t / 0.065) * 0.8
		var cloth := lp * minf(1.0, t / 0.012) * exp(-t / 0.19) * 0.7
		out[i] = clampf(body + cloth, -1.0, 1.0)
	return _bake(out, false)
