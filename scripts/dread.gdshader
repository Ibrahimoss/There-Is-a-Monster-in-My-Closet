shader_type canvas_item;

// What being hunted does to the picture. Driven by how close the thing is and
// whether it is in front of you, so turning round to look at it is punished.
//
// Sits under the Doom filter, so everything here gets palette-crushed with the
// rest of the image rather than sitting on top of it.

uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform float amount : hint_range(0.0, 1.0) = 0.0;
// Rises when it is actually in view, on top of `amount`.
uniform float seen : hint_range(0.0, 1.0) = 0.0;
uniform float t = 0.0;

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float a = clamp(amount, 0.0, 1.0);
	float s = clamp(seen, 0.0, 1.0);

	// the whole image breathes and pulls toward the centre
	vec2 mid = uv - vec2(0.5);
	float rad = length(mid);
	float pull = sin(t * 3.1) * 0.5 + 0.5;
	uv -= mid * a * (0.006 + 0.012 * pull) * (0.5 + rad);

	// bands of the picture tear sideways, more of them the closer it is
	float rows = 34.0;
	float row = floor(uv.y * rows);
	float jump = hash11(row * 1.7 + floor(t * 11.0) * 3.3);
	float torn = step(1.0 - (0.10 + 0.55 * a * (0.4 + 0.6 * s)), jump);
	uv.x += torn * (jump - 0.5) * 0.05 * (a + s);

	// a slow wave, so even a still frame is never quite steady
	uv.x += sin(uv.y * 18.0 + t * 2.3) * 0.0022 * a;

	// the colour comes apart at the edges as it closes
	float split = (0.004 + 0.010 * a) * (0.35 + 0.65 * s) * (0.35 + rad);
	vec3 col;
	col.r = texture(screen, uv + vec2(split, 0.0)).r;
	col.g = texture(screen, uv).g;
	col.b = texture(screen, uv - vec2(split, 0.0)).b;

	// dark closing in from the edges, breathing with the pulse
	float vig = smoothstep(0.30, 0.95, rad) * a * (0.45 + 0.3 * pull);
	col *= 1.0 - vig;
	// and a cold cast over everything
	col = mix(col, col * vec3(0.72, 0.80, 1.0), a * 0.5);

	COLOR = vec4(col, 1.0);
}
