shader_type canvas_item;
// Lifts shadows of the finished sRGB frame toward what Windows HDR shows; highlights pass through.

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float lift = 0.02;
uniform float gamma = 1.4;

void fragment() {
	vec3 c = clamp(texture(screen_tex, SCREEN_UV).rgb, 0.0, 1.0);
	vec3 up = lift + (1.0 - lift) * pow(c, vec3(1.0 / gamma));
	COLOR = vec4(mix(up, c, smoothstep(0.55, 0.95, c)), 1.0);
}
