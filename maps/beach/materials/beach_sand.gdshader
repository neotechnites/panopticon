// The beach's sand: the drawn tile x the vertex colour, as the import made it, darkened and glossed where
// it is under the still sea, caustics on it there; the waves' wet edges are beach_waves.gdshader's.
shader_type spatial;

#include "res://maps/beach/materials/beach_sea.gdshaderinc"

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 wet_tint = vec3(0.74, 0.71, 0.62);
uniform vec3 sea_tint = vec3(0.26, 0.84, 0.82);    // the bed under the water takes the sea's colour with depth
uniform sampler2D caustics : filter_linear_mipmap, repeat_enable;   // the light net (beach_water_albedo)
uniform float caustic_strength = 0.7;

varying vec3 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 albedo = texture(albedo_texture, UV).rgb * srgb_to_linear(COLOR.rgb);
	float wet = 1.0 - smoothstep(0.0, 0.05, world.y - SEA_Y);
	albedo = mix(albedo, albedo * wet_tint, wet);
	ALBEDO = mix(albedo, albedo * sea_tint, smoothstep(0.02, 0.8, SEA_Y - world.y));
	// caustics on the bed: the light net twice, scrolling at two scales, crisp, fading with depth
	float under = SEA_Y - world.y;
	float c1 = smoothstep(0.955, 0.985, texture(caustics, world.xz / 3.4 + TIME * vec2(0.035, 0.012)).r);
	float c2 = smoothstep(0.955, 0.985, texture(caustics, world.xz / 5.1 - TIME * vec2(0.014, 0.03)).r);
	EMISSION = vec3(0.85, 1.0, 0.95) * max(c1, c2) * caustic_strength * smoothstep(0.03, 0.15, under) * (1.0 - smoothstep(1.2, 3.0, under));
	ROUGHNESS = mix(0.95, 0.45, wet);
	SPECULAR = mix(0.15, 0.45, wet);           // dry sand barely shines; wet sand sheens
}
