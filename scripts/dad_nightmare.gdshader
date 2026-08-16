shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_opaque, shadows_disabled;

// The dad_nightmare drawing is a black figure on a white page. This keys the
// page out by luminance and lights up the pale parts left inside him — the
// eyes, the mouth, the scratch marks — so he reads as a shape in the dark
// with something bright looking back.
//
// Measured on the source art: the figure sits at luminance 0.00-0.08, the
// page at 0.98-1.00, and the eyes peak at 0.62. Anything between the two
// key thresholds below fades out, so those bands are wide apart on purpose.

uniform sampler2D dad_tex : source_color, filter_nearest;

// Above key_high is page and goes fully transparent.
uniform float key_low : hint_range(0.0, 1.0) = 0.72;
uniform float key_high : hint_range(0.0, 1.0) = 0.94;

// The pale parts inside him ramp from body_color to glow_color across this.
uniform float glow_low : hint_range(0.0, 1.0) = 0.10;
uniform float glow_high : hint_range(0.0, 1.0) = 0.55;
uniform vec3 body_color : source_color = vec3(0.02, 0.02, 0.03);
uniform vec3 glow_color : source_color = vec3(1.0, 0.96, 0.86);
uniform float glow_gain : hint_range(0.0, 8.0) = 3.2;

// Slow breathing pulse on the glow. 0 holds it steady.
uniform float pulse_rate = 1.6;
uniform float pulse_depth : hint_range(0.0, 1.0) = 0.22;

// Fade him in without touching the material's other settings.
uniform float appear : hint_range(0.0, 1.0) = 1.0;

void vertex() {
	// Full billboard: face the camera on every axis, so he still reads
	// correctly while the kid is walking upside down on the ceiling.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2],
		MODEL_MATRIX[3]);
}

void fragment() {
	vec4 src = texture(dad_tex, UV);
	float lum = dot(src.rgb, vec3(0.299, 0.587, 0.114));

	// page -> transparent, figure -> solid
	float solid = 1.0 - smoothstep(key_low, key_high, lum);

	float hot = smoothstep(glow_low, glow_high, lum);
	float pulse = 1.0 + sin(TIME * pulse_rate) * pulse_depth;
	vec3 col = mix(body_color, glow_color * glow_gain * pulse, hot);

	ALBEDO = col;
	ALPHA = solid * src.a * appear;
}
