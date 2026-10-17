shader_type canvas_item;
// Sentinel (boss) Server: a pulsing blood-red vignette with a rare flicker.
uniform vec4 glow : source_color = vec4(0.9, 0.0, 0.1, 1.0);
uniform float strength : hint_range(0.0, 1.0) = 0.6;

void fragment() {
	vec2 uv = (UV - 0.5) * vec2(1.0, 0.85);
	float edge = smoothstep(0.22, 0.8, length(uv));
	float pulse = 0.75 + 0.25 * sin(TIME * 1.7);
	float flick = step(0.985, fract(sin(floor(TIME * 14.0) * 91.7) * 437.5)) * 0.2;
	COLOR = vec4(glow.rgb, edge * (strength * pulse + flick));
}
