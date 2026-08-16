shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, blend_mix, shadows_disabled;

// The front of the dark. Solid where it has already taken the room, torn up
// along one edge where it is still reaching, and that edge writhes.
//
// UV.y 0 is the solid end, 1 the ragged one. A QuadMesh puts UV.y 0 at the top,
// so the upright face is ragged along its bottom and the skirt lying on the
// floor is ragged at its far end, both without a flag.
//
// unshaded ignores EMISSION, so the fringe goes in ALBEDO.

uniform float t = 0.0;
// how much of the far end is torn
uniform float ragged : hint_range(0.0, 1.0) = 0.34;
uniform float wobble : hint_range(0.0, 4.0) = 1.0;
uniform vec3 tint : source_color = vec3(0.004, 0.004, 0.007);
uniform vec3 fringe : source_color = vec3(0.055, 0.048, 0.085);
uniform float tile = 7.0;
// UV.y is 0 at the TOP of a QuadMesh, so by default the solid end is the top
// and the torn end is the floor. A bank of smoke wants that the other way up.
uniform bool flip = false;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash12(i), hash12(i + vec2(1.0, 0.0)), f.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), f.x),
		f.y);
}

void fragment() {
	float v = flip ? 1.0 - UV.y : UV.y;
	vec2 p = vec2(UV.x * tile, v * tile * 0.5 - t * 0.18);
	float n = vnoise(p) * 0.62 + vnoise(p * 2.3 + vec2(t * 0.09, 0.0)) * 0.38;

	// where the boundary sits on this column, pushed about by the noise
	float e = 1.0 - ragged + (n - 0.5) * ragged * 1.7 * wobble;
	float a = 1.0 - smoothstep(e, e + 0.09, v);
	// a cold thread right on the boundary, or black on black is invisible
	float rim = smoothstep(e - 0.055, e, v) * (1.0 - smoothstep(e, e + 0.045, v));

	ALBEDO = tint + fringe * rim;
	ALPHA = clamp(a + rim * 0.5, 0.0, 1.0);
}
