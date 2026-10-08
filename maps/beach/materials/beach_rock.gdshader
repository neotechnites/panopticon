// Beach rock: the drawn tile x the vertex colour (darker, warmer at a stone's foot), wet and glossy where the
// waves' splash reaches, a weed-dark band under the water line (beach_sea.gdshaderinc).
shader_type spatial;

#include "res://maps/beach/materials/beach_sea.gdshaderinc"

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 wet_tint = vec3(0.62, 0.6, 0.56);
uniform vec3 weed_tint = vec3(0.48, 0.52, 0.42);
uniform float splash = 0.35;           // metres the waves wet the rock above still water

varying vec3 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 albedo = texture(albedo_texture, UV).rgb * srgb_to_linear(COLOR.rgb);
	float wet = 1.0 - smoothstep(0.05, splash, world.y - SEA_Y);
	float weed = 1.0 - smoothstep(-0.05, 0.08, world.y - SEA_Y);
	albedo = mix(albedo, albedo * wet_tint, wet);
	albedo = mix(albedo, albedo * weed_tint, weed);
	ALBEDO = albedo * exp(-vec3(0.3, 0.07, 0.055) * max(SEA_Y - world.y, 0.0));   // the water's absorption, as the sand
	ROUGHNESS = mix(0.9, 0.35, wet);
	SPECULAR = mix(0.5, 0.65, wet);
}
