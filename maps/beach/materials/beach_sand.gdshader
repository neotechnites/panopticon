// The beach's sand: the drawn tile x the vertex colour, as the import made it, darkened and glossed where
// it is under the still sea; the waves' wet edges are beach_waves.gdshader's (beach_sea.gdshaderinc).
shader_type spatial;

#include "res://maps/beach/materials/beach_sea.gdshaderinc"

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 wet_tint = vec3(0.74, 0.71, 0.62);
uniform vec3 sea_tint = vec3(0.42, 0.8, 0.78);    // the bed under the water takes the sea's colour with depth

varying vec3 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 albedo = texture(albedo_texture, UV).rgb * srgb_to_linear(COLOR.rgb);
	float wet = 1.0 - smoothstep(0.0, 0.05, world.y - SEA_Y);
	albedo = mix(albedo, albedo * wet_tint, wet);
	ALBEDO = mix(albedo, albedo * sea_tint, smoothstep(0.1, 1.2, SEA_Y - world.y));
	ROUGHNESS = mix(0.95, 0.45, wet);
	SPECULAR = mix(0.15, 0.45, wet);           // dry sand barely shines; wet sand sheens
}
