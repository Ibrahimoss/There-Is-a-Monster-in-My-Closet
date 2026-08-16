shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add, shadows_disabled;

// A shaft of light hanging under a lamp or leaning out of a doorway.
//
// The compatibility renderer has no volumetrics, so this is a cone. Everything
// here exists to stop it reading as a solid transparent cone:
//   - it fades to nothing at the rim, so there is never a visible edge
//   - it fades out along its length, so where it meets the floor it has
//     already gone, instead of cutting a hard ellipse into it
//   - it dims as you look straight down its axis, because a real shaft is
//     only visible side on
//   - it fades as you get close, so you never walk into a wedge of colour
//   - dust drifts through it, so it is not a flat gradient

uniform vec3 shaft_color : source_color = vec3(1.0, 0.86, 0.62);
uniform float energy : hint_range(0.0, 4.0) = 1.0;
// 0 at the lamp, 1 at the far end: where the light has died out.
uniform float reach : hint_range(0.1, 1.0) = 0.85;
uniform float t = 0.0;
uniform float dust : hint_range(0.0, 1.0) = 0.5;
// Metres over which it fades out as the camera closes in.
uniform float near_fade = 1.1;
// The cone's height. Set it: the length used to be worked out per fragment from
// the vertex's own y, which is only right at the two ends - across the middle of
// the cone it collapses to nothing and takes the whole band to black with it.
// Left at 0 for the old behaviour, so nothing that does not set it changes.
uniform float span = 0.0;

varying vec3 v_model;
varying vec3 v_world;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(i);
	float n100 = hash13(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash13(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash13(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash13(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash13(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash13(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash13(i + vec3(1.0, 1.0, 1.0));
	return mix(mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
		mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}

void vertex() {
	v_model = VERTEX;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// The mesh is a cone standing on its point: model y runs +h/2 at the lamp
	// down to -h/2 at the floor. Work out how far out from the axis we are as
	// a fraction of the cone's radius at this height.
	float h = span > 0.001 ? span : max(abs(v_model.y) * 2.0, 0.001);
	float down = clamp(0.5 - v_model.y / h, 0.0, 1.0);
	float radius = max(down, 0.02);
	float r = clamp(length(v_model.xz) / (radius * h * 0.5 + 0.001), 0.0, 1.0);

	// soft to nothing at the rim, and gone before the far end
	float edge = pow(1.0 - r, 2.2);
	float along = 1.0 - smoothstep(reach * 0.45, reach, down);

	// only visible side on: looking up the axis it thins away
	vec3 axis = normalize((MODEL_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	vec3 view = normalize(v_world - INV_VIEW_MATRIX[3].xyz);
	float side = 1.0 - abs(dot(view, axis));
	side = 0.25 + 0.75 * side;

	// nothing hard right in front of the eye
	float dist = length(v_world - INV_VIEW_MATRIX[3].xyz);
	float near = smoothstep(0.0, near_fade, dist);

	// motes drifting down through it
	float motes = vnoise(v_world * 2.6 + vec3(0.0, -t * 0.35, 0.0));
	motes = mix(1.0, 0.55 + 0.9 * motes, dust);

	ALBEDO = shaft_color;
	ALPHA = clamp(edge * along * side * near * motes * energy, 0.0, 1.0);
}
