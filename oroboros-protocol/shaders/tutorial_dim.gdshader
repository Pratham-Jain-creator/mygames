shader_type canvas_item;
// Tutorial focus layer: everything is dimmed to near-black except up to 3 rectangles
// ("holes", in pixels: x, y, width, height). A hole with width 0 is unused.

uniform vec4 hole0 = vec4(0.0);
uniform vec4 hole1 = vec4(0.0);
uniform vec4 hole2 = vec4(0.0);
uniform float dim : hint_range(0.0, 1.0) = 0.88;
uniform float feather = 16.0;
uniform vec2 area_size = vec2(1280.0, 720.0);

float lit(vec2 p, vec4 h) {
	if (h.z <= 0.0) {
		return 0.0;
	}
	vec2 d = max(h.xy - p, p - (h.xy + h.zw));
	float sd = max(d.x, d.y);
	return 1.0 - smoothstep(0.0, feather, sd);
}

void fragment() {
	vec2 p = UV * area_size;
	float l = max(lit(p, hole0), max(lit(p, hole1), lit(p, hole2)));
	COLOR = vec4(0.0, 0.0, 0.0, dim * (1.0 - l));
}
