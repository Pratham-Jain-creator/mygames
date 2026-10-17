shader_type canvas_item;
// Full-screen post effect: barely-there CRT (scanlines + curvature + vignette)
// plus a chromatic aberration whose strength is driven by AnimationPlayer
// ("impact" animation in post_fx.tscn).

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float curvature : hint_range(0.0, 0.2) = 0.025;
uniform float scan_strength : hint_range(0.0, 0.5) = 0.05;
uniform float scan_count = 420.0;
uniform float vignette : hint_range(0.0, 1.0) = 0.22;
uniform float aberration : hint_range(0.0, 0.05) = 0.0;
uniform bool crt_enabled = true;
// Old-TV power-on: 0 = off, 1 = fully on (driven by the "crt_on" animation in post_fx.tscn).
uniform float power : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 cc = uv - 0.5;
	float dist = dot(cc, cc);
	if (crt_enabled) {
		uv += cc * dist * curvature * 4.0;
	}
	vec3 col;
	if (aberration > 0.0005) {
		vec2 off = vec2(aberration, 0.0);
		col = vec3(texture(screen_tex, uv + off).r, texture(screen_tex, uv).g, texture(screen_tex, uv - off).b);
	} else {
		col = texture(screen_tex, uv).rgb;   // 1 texture read instead of 3 when idle
	}
	if (crt_enabled) {
		float scan = sin(uv.y * scan_count * 3.14159) * 0.5 + 0.5;
		col *= 1.0 - scan_strength * scan;
		col *= 1.0 - vignette * dist * 2.0;
		if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
			col = vec3(0.0);
		}
	}
	if (power < 0.999) {
		// A bright line grows sideways from the centre, then opens up and down.
		float lw = clamp(power / 0.3, 0.0, 1.0);
		float open = clamp((power - 0.3) / 0.7, 0.0, 1.0);
		open = open * open * (3.0 - 2.0 * open);
		float half_h = mix(0.003, 0.5, open);
		float dy = abs(SCREEN_UV.y - 0.5);
		float dx = abs(SCREEN_UV.x - 0.5) * 2.0;
		float inside = step(dy, half_h) * step(dx, lw);
		float glow = (1.0 - open) * inside * (1.0 - smoothstep(0.0, half_h + 0.002, dy) * 0.6);
		col = mix(col * inside, vec3(1.0), glow * 0.85);
	}
	COLOR = vec4(col, 1.0);
}
