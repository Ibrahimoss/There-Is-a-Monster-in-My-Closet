shader_type canvas_item;
render_mode unshaded;

// Eyelids, drawn as an almond-shaped hole that opens vertically.
// 0.0 = shut, 1.0 = wide open.
uniform float eye_open : hint_range(0.0, 1.0) = 0.0;
// Flat blackness laid over everything, independent of the lids.
uniform float darkness : hint_range(0.0, 1.0) = 1.0;
// Corner darkening — sells the "not focusing yet" feeling.
uniform float vignette : hint_range(0.0, 1.0) = 0.0;
// How much the lid edges bow toward the corners of the eye.
uniform float curvature : hint_range(0.0, 0.5) = 0.18;
uniform float softness : hint_range(0.001, 0.2) = 0.014;
uniform float aspect = 1.777;
uniform vec3 lid_color : source_color = vec3(0.0);

void fragment() {
	// Corners of the eye stay closed longer than the middle.
	float ex = abs(UV.x - 0.5) * 2.0;
	float curve = curvature * ex * ex;

	float top = mix(0.52, -0.08, eye_open) + curve;
	float bot = mix(0.48, 1.08, eye_open) - curve;

	float below_top = smoothstep(top - softness, top + softness, UV.y);
	float above_bot = 1.0 - smoothstep(bot - softness, bot + softness, UV.y);
	float lid = 1.0 - below_top * above_bot;

	vec2 d = (UV - 0.5) * vec2(aspect, 1.0);
	float vig = smoothstep(0.30, 0.82, length(d)) * vignette;

	// Stack the three sources of black multiplicatively so none of them clips.
	float a = 1.0 - (1.0 - lid) * (1.0 - darkness) * (1.0 - vig);
	COLOR = vec4(lid_color, a);
}
