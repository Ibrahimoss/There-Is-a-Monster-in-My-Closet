shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

// Something coming apart where it stands. The cut is a noise field in the
// model's own space, biased so the low parts go first, with a hot rim on the
// boundary that reads as the edge of a burn.
//
// It stays lit rather than unshaded: the toy is standing in the beam and the
// beam is the whole point of the shot.

uniform sampler2D albedo_tex : source_color, hint_default_white;
uniform bool has_tex = false;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// 0 whole, 1 gone
uniform float threshold : hint_range(0.0, 1.0) = 0.0;
uniform float edge : hint_range(0.001, 0.4) = 0.045;
uniform vec3 edge_color : source_color = vec3(1.0, 0.52, 0.16);
// how hard the burn climbs from the feet up
uniform float up_bias : hint_range(-2.0, 2.0) = 0.9;
// Fine, on purpose. The toy is a third of a metre tall: at a coarse scale the
// burn edge is wider than the thing burning and it reads as on fire rather than
// as coming apart.
uniform float noise_scale = 34.0;

varying vec3 obj_pos;

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
	return mix(
		mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
		mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y),
		f.z);
}

void vertex() {
	// model space, so the pattern is fixed to the object and does not swim
	// about when it is turned
	obj_pos = VERTEX;
}

void fragment() {
	float n = vnoise(obj_pos * noise_scale) * 0.72
		+ vnoise(obj_pos * noise_scale * 2.7) * 0.28;
	float h = clamp(obj_pos.y * up_bias + 0.5, 0.0, 1.0);
	float cut = n * 0.70 + h * 0.30;
	// overshoot a little so threshold 1.0 really does clear every last fragment
	float t = threshold * 1.22;

	if (cut < t - edge) {
		discard;
	}

	vec3 base = has_tex ? texture(albedo_tex, UV).rgb : vec3(1.0);
	base *= tint.rgb;
	float rim = 1.0 - smoothstep(t - edge, t + edge * 0.35, cut);
	// a thread of ember on the boundary, not a coat of it: at half gone the toy
	// still has to read as the toy
	ALBEDO = mix(base, edge_color, rim * 0.30);
	EMISSION = edge_color * rim * rim * rim * 3.4;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
