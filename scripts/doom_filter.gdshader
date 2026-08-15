shader_type canvas_item;
render_mode unshaded;

// Full-screen Doom filter. Reads whatever the 3D camera rendered, chops it down
// to a 320x200-ish grid, and snaps every color to the Doom palette via a baked
// LUT (see tools/doomify.py --emit-lut).

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_nearest;
uniform sampler2D lut_tex : filter_nearest, repeat_disable;

// Edge length of the baked LUT cube. Must match --lut-size.
uniform float lut_size = 32.0;

// Virtual framebuffer. Doom was 320x200.
uniform vec2 virtual_resolution = vec2(320.0, 200.0);
uniform bool pixelate = true;

// COLORMAP-style darkening applied before the palette snap, 0..1.
// Crank it for the closet.
uniform float darkness : hint_range(0.0, 1.0) = 0.0;

// Dial the whole effect back toward the untouched image.
uniform float amount : hint_range(0.0, 1.0) = 1.0;

// Ordered dither before the snap, in the same spirit as the offline tool.
uniform float dither : hint_range(0.0, 2.0) = 0.6;

const mat4 BAYER = mat4(
	vec4( 0.0,  8.0,  2.0, 10.0),
	vec4(12.0,  4.0, 14.0,  6.0),
	vec4( 3.0, 11.0,  1.0,  9.0),
	vec4(15.0,  7.0, 13.0,  5.0)
);

vec3 palette_snap(vec3 c) {
	float n = lut_size;
	vec3 q = floor(clamp(c, 0.0, 1.0) * (n - 1.0) + 0.5);
	// Slices run left to right, so u walks the blue axis in blocks of n.
	float u = (q.b * n + q.r + 0.5) / (n * n);
	float v = (q.g + 0.5) / n;
	// Nearest sampling on purpose — filtering would blend between two palette
	// entries and hand back a color the palette does not contain.
	return texture(lut_tex, vec2(u, v)).rgb;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	if (pixelate) {
		// Snap to the center of a chunky pixel so the sample is stable.
		uv = (floor(uv * virtual_resolution) + 0.5) / virtual_resolution;
	}

	vec3 src = texture(screen_tex, uv).rgb;
	vec3 c = src * (1.0 - darkness);

	if (dither > 0.0) {
		ivec2 cell = ivec2(mod(FRAGCOORD.xy, 4.0));
		float bias = (BAYER[cell.y][cell.x] + 0.5) / 16.0 - 0.5;
		// ~1/32 of the range matches the LUT's own cell spacing.
		c += bias * dither * (1.0 / 32.0);
	}

	COLOR = vec4(mix(src, palette_snap(c), amount), 1.0);
}
