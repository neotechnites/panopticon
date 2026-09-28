shader_type canvas_item;
// Decodes sRGB the way Windows 11 HDR does, then re-encodes at gamma 2.2, matching the PC.

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;

vec3 srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

void fragment() {
	vec3 c = clamp(texture(screen_tex, SCREEN_UV).rgb, 0.0, 1.0);
	COLOR = vec4(pow(srgb_to_linear(c), vec3(1.0 / 2.2)), 1.0);
}
