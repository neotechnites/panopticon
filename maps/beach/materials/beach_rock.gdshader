// Beach rock and the bay's coral heads: the drawn tile x the baked vertex colour (darker, warmer at a stone's
// foot; wet above still water, the weed band and the water's absorption below, all baked in beach_build.py).
shader_type spatial;

#include "res://maps/beach/materials/beach_sea.gdshaderinc"

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 tint : source_color = vec3(1.0);   // one rock tile wears the reef's colour

void fragment() {
	ALBEDO = texture(albedo_texture, UV).rgb * tint * srgb_to_linear(COLOR.rgb);
	ROUGHNESS = 0.9;
	SPECULAR = 0.5;
}
