shader_type canvas_item;

// Concussed. Not glitched: the two are different feelings and the chase already
// owns the glitch.
//
// The second image lags behind the first and swims about, everything smears out
// of the middle, colour drains, and the edges close in. It stacks under the
// dread distortion rather than replacing it, so a scare can be loud and this can
// be slow at the same time.

uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform float t = 0.0;

void fragment() {
	if (amount < 0.002) {
		COLOR = vec4(texture(screen, SCREEN_UV).rgb, 1.0);
	} else {
		vec2 uv = SCREEN_UV;
		vec2 c = uv - vec2(0.5);
		float r = length(c);

		// the head is still moving after the rest of you has stopped
		vec2 lag = vec2(sin(t * 1.7) * 0.011, cos(t * 1.27) * 0.008) * amount;
		vec2 ghost = uv + lag + c * 0.020 * amount;

		// smeared out of the middle
		vec3 blur = vec3(0.0);
		float w = 0.0;
		for (int i = 0; i < 5; i++) {
			float f = float(i) / 4.0;
			float k = 1.0 - f * 0.55;
			blur += texture(screen, uv - c * (0.038 * amount) * f).rgb * k;
			w += k;
		}
		blur /= w;

		vec3 base = texture(screen, uv).rgb;
		vec3 second = texture(screen, ghost).rgb;
		vec3 col = mix(base, blur, amount * 0.72);
		// lighten-blend the double, so it is the lit things that ghost and the
		// dark stays dark instead of going milky
		col = mix(col, max(col, second), amount * 0.60);

		float g = dot(col, vec3(0.299, 0.587, 0.114));
		col = mix(col, vec3(g) * vec3(0.86, 0.90, 1.03), amount * 0.5);
		col *= 1.0 - smoothstep(0.20, 0.80, r) * amount * 0.8;

		COLOR = vec4(col, 1.0);
	}
}
