shader_type spatial;
// The drill, done in the world rather than on the picture: every vertex is
// rotated about the corridor's own axis by an angle proportional to how far
// down that axis it sits, so the hallway winds like a rifled barrel. Walls,
// floor, doorframes and props all wind together because they all share the
// axis -- which is the part a screen-space swirl cannot do, since that bends
// the image and leaves the geometry straight.

render_mode cull_disabled;

uniform sampler2D albedo_tex : source_color, hint_default_white;
uniform vec4 albedo_col : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float has_tex = 0.0;
// radians of wind per metre travelled down the axis
uniform float twist = 0.16;
// a world point on the corridor's centre line, and the way it runs
uniform vec3 axis_origin = vec3(0.0);
uniform vec3 axis_dir = vec3(0.0, 0.0, 1.0);
// the wind starts here, so the room you stand in is not already spiralling
uniform float start = 2.0;
// and stops here. Without a cap a long wall slab keeps turning along its own
// length until it sweeps out a cone, which is what it looks like: a cone.
uniform float max_turn = 0.85;

// Rodrigues: turn `v` about the unit `k` by `a`.
vec3 spin(vec3 v, vec3 k, float a) {
	return v * cos(a) + cross(k, v) * sin(a) + k * dot(k, v) * (1.0 - cos(a));
}

void vertex() {
	vec3 k = normalize(axis_dir);
	mat4 inv = inverse(MODEL_MATRIX);

	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 d = wp - axis_origin;
	float t = dot(d, k);
	float a = clamp(twist * max(t - start, 0.0), -max_turn, max_turn);

	vec3 radial = d - k * t;
	vec3 turned = spin(radial, k, a);
	vec3 moved = axis_origin + k * t + turned;
	VERTEX = (inv * vec4(moved, 1.0)).xyz;

	// carry the normal round with it or the lighting keeps facing the old way
	vec3 wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	NORMAL = normalize((inv * vec4(spin(wn, k, a), 0.0)).xyz);
}

void fragment() {
	vec4 c = albedo_col;
	if (has_tex > 0.5) {
		c *= texture(albedo_tex, UV);
	}
	ALBEDO = c.rgb;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
