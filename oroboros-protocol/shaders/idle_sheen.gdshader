shader_type canvas_item;
// Card surface effect, drawn on top of a card, never blocks input:
//  * gloss: a soft light sweep (used for modified Nodes only; every other card has no effect)

uniform vec4 tint : source_color = vec4(0.4, 0.99, 0.945, 1.0);
uniform float strength : hint_range(0.0, 2.0) = 1.0;   // unused (kept for the script)
uniform float gloss : hint_range(0.0, 1.0) = 0.0;       // 0 = no gloss
uniform float period = 6.0;      // seconds between gloss sweeps
uniform float phase = 0.0;       // random per card
uniform vec2 rect_size = vec2(224.0, 126.0);
uniform float radius = 5.0;

void fragment() {
	vec2 p = UV * rect_size;
	vec2 q = abs(p - rect_size * 0.5) - (rect_size * 0.5 - vec2(radius));
	float d = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
	float mask = 1.0 - smoothstep(-1.0, 0.5, d);

	float t = fract((TIME + phase) / period);
	float diag = (p.x + p.y * 0.4) / (rect_size.x + rect_size.y * 0.4);
	float band = smoothstep(0.1, 0.0, abs(diag - (t * 1.7 - 0.35)));
	float a_gloss = mask * band * 0.2 * gloss;

	COLOR = vec4(tint.rgb, clamp(a_gloss, 0.0, 1.0));
}
