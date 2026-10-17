shader_type canvas_item;

// Added filter_linear_mipmap to allow for smooth blurring (LOD)
uniform sampler2D SCREEN_TEXTURE: hint_screen_texture, filter_linear_mipmap;

// Changed 5 to 5.0 (Godot shaders are very strict about floats vs ints)
uniform float lod: hint_range(0.0, 5.0) = 0.0;

void fragment() {
	// Changed texture() to textureLod() to apply the blur
	vec4 color = textureLod(SCREEN_TEXTURE, SCREEN_UV, lod);
	COLOR = color;
}
