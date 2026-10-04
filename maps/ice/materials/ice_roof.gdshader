shader_type spatial;
render_mode unshaded, cull_back, blend_mix;
// The ice roof seen from below: the tile lit from behind. COLOR_0 carries how thin the ice is
// (rgb the light through it, a how much of the bright shell behind shows).

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float glow = 3.4;
uniform float graze_opacity = 0.35;
uniform vec3 graze_tint : source_color = vec3(0.55, 0.78, 0.95);

void fragment() {
	vec3 tile = texture(albedo_texture, UV).rgb;
	float graze = 1.0 - abs(dot(normalize(NORMAL), normalize(VIEW)));
	graze *= graze;
	ALBEDO = mix(tile * COLOR.rgb * glow, graze_tint * COLOR.rgb, graze * 0.35);
	ALPHA = clamp(COLOR.a + graze_opacity * graze, 0.0, 1.0);
}
