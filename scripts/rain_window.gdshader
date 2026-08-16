shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, blend_mix, shadows_disabled;

// Night on the other side of the glass: streaks running down it, a dull sky
// behind, and the odd flash that throws the whole corridor into relief.

uniform float t = 0.0;
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform vec3 sky_color : source_color = vec3(0.16, 0.20, 0.30);
uniform vec3 rain_color : source_color = vec3(0.42, 0.50, 0.62);
uniform float rain_amount : hint_range(0.0, 1.0) = 1.0;
// A pane of glass is solid; a curtain of rain in the open air is only the
// streaks, with the night showing through the gaps.
uniform bool curtain = false;
// Streak density. A six metre curtain needs far more columns than a one metre
// pane or the rain reads as fence posts.
uniform float tile = 1.0;

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

// Vertical streaks falling at their own speeds, in a few columns.
//
// UV.y runs 0 at the top to 1 at the bottom, so the phase has to be pushed the
// other way for the drops to fall rather than climb.
float streaks(vec2 uv, float speed, float cols, float seed) {
	float col = floor(uv.x * cols + seed);
	float lane = hash11(col * 1.7 + seed);
	float y = fract(uv.y * 1.6 - t * (speed + lane * 0.6) + lane * 7.0);
	// a bright head with the tail stretched out behind it, above
	float dash = smoothstep(0.0, 0.05, y) * (1.0 - smoothstep(0.05, 0.34, y));
	float across = 1.0 - smoothstep(0.0, 0.42, abs(fract(uv.x * cols + seed) - 0.5) * 2.0);
	return dash * across * step(0.22, lane);
}

// Rain in the open is drawn on quads that hang in front of the camera. They
// have to turn to face it, or you catch them edge on and the weather reads as
// a sheet of glass standing in the garden.
void vertex() {
	if (curtain) {
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
	}
}

void fragment() {
	vec2 uv = UV;
	// the pane sits a little deeper at the edges, so a soft frame shadow
	float edge = smoothstep(0.0, 0.09, min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y)));

	// sky, brighter toward the top
	vec3 col = sky_color * mix(0.55, 1.25, 1.0 - uv.y);
	// running water distorts what little there is to see, and it runs down
	float wob = sin(uv.y * 40.0 - t * 1.7) * 0.012 + sin(uv.y * 17.0 - t * 0.9) * 0.02;
	col *= 1.0 + wob * 2.0;

	vec2 suv = vec2(uv.x * tile, uv.y);
	float r = streaks(suv + vec2(wob, 0.0), 0.55, 26.0, 0.0) * 0.9
		+ streaks(suv, 0.85, 17.0, 3.1) * 0.7
		+ streaks(suv, 1.35, 11.0, 8.4) * 0.5;
	col += rain_color * r * rain_amount;

	// lightning: the sky goes pale and the streaks light up with it
	col = mix(col, vec3(0.72, 0.78, 0.92), flash * (0.75 + 0.25 * r));

	// unshaded: ALBEDO is the final colour, EMISSION would be ignored
	if (curtain) {
		// falling in the open: only the water is there
		ALBEDO = rain_color * (1.0 + flash);
		ALPHA = clamp(r * rain_amount, 0.0, 1.0) * 0.62;
	} else {
		// the pane is the light here, not a lamp beside it: bright enough to
		// read as night sky from down a black corridor
		ALBEDO = col * (2.4 + flash * 3.0) * edge;
		ALPHA = 1.0;
	}
}
