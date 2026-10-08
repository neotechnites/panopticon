// Beach rock: the drawn tile x the vertex colour (darker, warmer at a stone's foot), wet and glossy where the
// swash and its splash reach, a weed-dark band under the water line (beach_swash.gdshaderinc).
shader_type spatial;

#include "res://maps/beach/materials/beach_swash.gdshaderinc"

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 wet_tint = vec3(0.62, 0.6, 0.56);
uniform vec3 weed_tint = vec3(0.48, 0.52, 0.42);
uniform float splash = 0.3;            // metres the spray wets above the swash

varying vec3 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 albedo = texture(albedo_texture, UV).rgb * srgb_to_linear(COLOR.rgb);
	float wet = 1.0 - smoothstep(0.0, splash, world.y - wet_level(world.xz, TIME));
	wet *= 1.0 - smoothstep(0.5, 0.8, world.y - SEA_Y);
	float weed = 1.0 - smoothstep(-0.05, 0.08, world.y - SEA_Y);
	albedo = mix(albedo, albedo * wet_tint, wet);
	ALBEDO = mix(albedo, albedo * weed_tint, weed);
	ROUGHNESS = mix(0.9, 0.35, wet);
	SPECULAR = mix(0.5, 0.65, wet);
}
