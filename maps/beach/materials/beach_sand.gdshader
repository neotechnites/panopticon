// The beach's sand: the drawn tile x the vertex colour, as the import made it, darkened and glossed where
// the swash has wet it (beach_swash.gdshaderinc).
shader_type spatial;

#include "res://maps/beach/materials/beach_swash.gdshaderinc"

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 wet_tint = vec3(0.74, 0.71, 0.62);

varying vec3 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 albedo = texture(albedo_texture, UV).rgb * srgb_to_linear(COLOR.rgb);
	float wet = 1.0 - smoothstep(0.0, 0.05, world.y - wet_level(world.xz, TIME));
	wet *= 1.0 - smoothstep(0.7, 1.0, world.y - SEA_Y);
	ALBEDO = mix(albedo, albedo * wet_tint, wet);
	ROUGHNESS = mix(0.95, 0.3, wet);
	SPECULAR = mix(0.5, 0.7, wet);
}
