shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, blend_mix, shadows_disabled;

// The thing itself: a Y-billboarded quad with a procedural silhouette. Black
// fuzz, two pale eyes, and horizontal strokes that tear across it. A drawing
// can be dropped in over the top; the strokes and eyes still get added.

uniform sampler2D tex : source_color, hint_default_transparent;
uniform bool use_tex = false;
uniform float t = 0.0;
uniform float glitch : hint_range(0.0, 1.0) = 1.0;
uniform float eyes : hint_range(0.0, 1.0) = 1.0;
uniform float visible_amount : hint_range(0.0, 1.0) = 1.0;
/// Sideways lean. The billboard throws the node's own rotation away, so the
/// lean has to happen here: the crown slides, the feet stay put.
uniform float lean : hint_range(-1.0, 1.0) = 0.0;
uniform vec3 body_color : source_color = vec3(0.02, 0.02, 0.025);

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.x, p.y, p.x) * 0.1031);
	p3 += dot(p3, vec3(p3.y, p3.z, p3.x) + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	// billboard about the world up only, so it never lies down when you look
	// up at it; the node's own scale is kept
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(normalize(cross(vec3(0.0, 1.0, 0.0), INV_VIEW_MATRIX[2].xyz)), 0.0),
		vec4(0.0, 1.0, 0.0, 0.0),
		vec4(normalize(cross(INV_VIEW_MATRIX[0].xyz, vec3(0.0, 1.0, 0.0))), 0.0),
		MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec2 uv = UV;
	uv.x -= lean * (1.0 - uv.y) * 0.11;

	// a few scanlines tear sideways each frame
	float row = floor(uv.y * 46.0);
	float h = hash11(row + floor(t * 9.0) * 13.0);
	float torn = step(0.86, h);
	uv.x += torn * (h - 0.86) * 1.5 * (hash11(row * 3.1) - 0.5) * glitch;

	float d = length((uv - vec2(0.5, 0.52)) * vec2(2.4, 1.05));
	float m;
	vec3 col = body_color;
	if (use_tex) {
		vec4 s = texture(tex, uv);
		m = s.a;
		col = mix(s.rgb * 0.3, body_color, 0.5);
	} else {
		float n = vnoise(uv * vec2(8.0, 18.0) + vec2(0.0, t * 0.6)) * 0.62
			+ vnoise(uv * vec2(19.0, 41.0) - vec2(0.0, t * 0.35)) * 0.38;
		m = 1.0 - smoothstep(0.42, 0.50 + 0.06 * n, d);
	}
	// fuzz off the crown, dissolve into the floor at the feet
	m *= smoothstep(0.0, 0.10, uv.y);
	m *= smoothstep(0.0, 0.06, 1.0 - uv.y);

	// two eyes, each drifting on its own
	vec2 e1 = vec2(0.43, 0.20) + vec2(sin(t * 1.7), cos(t * 1.3)) * 0.006;
	vec2 e2 = vec2(0.57, 0.20) + vec2(sin(t * 1.1 + 2.0), cos(t * 1.9 + 1.0)) * 0.006;
	float ed = min(length((uv - e1) * vec2(1.0, 1.6)), length((uv - e2) * vec2(1.0, 1.6)));
	float eye = (1.0 - smoothstep(0.010, 0.026, ed)) * eyes;

	// a mouth only while it is roaring
	float arc = 0.34 + 0.018 * cos(uv.x * 60.0);
	float mouth = (1.0 - smoothstep(0.0, 0.014, abs(uv.y - arc)))
		* (1.0 - smoothstep(0.055, 0.10, abs(uv.x - 0.5)))
		* smoothstep(0.9, 1.0, eyes) * 0.35;

	// pale strokes just off the silhouette edge, on the torn rows only
	float stroke = torn * glitch * (1.0 - smoothstep(0.0, 0.022, abs(d - 0.46))) * 0.55;

	col = mix(col, vec3(0.82, 0.82, 0.86), clamp(eye + mouth, 0.0, 1.0));
	col = mix(col, vec3(0.55, 0.55, 0.58), stroke * (1.0 - m));

	ALBEDO = col;
	ALPHA = clamp(max(m, max(eye, stroke)), 0.0, 1.0) * visible_amount;
}
