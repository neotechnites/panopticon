// Alpha-cut cards: the aspens' leaf masses and grass tufts. Unshaded, so the light comes through a leaf from any side.
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform float cut = 0.4;
uniform float glow = 1.0;
// Ryan's display shows SDR at 2x linear (scripts/fx/mac_lift.gdshader): the tile's colours are what he sees.
uniform float display_gain = 0.5;

void fragment() {
	vec4 tile = texture(albedo_texture, UV);
	ALBEDO = tile.rgb * COLOR.rgb * glow * display_gain;
	ALPHA = tile.a;
	ALPHA_SCISSOR_THRESHOLD = cut;
}
