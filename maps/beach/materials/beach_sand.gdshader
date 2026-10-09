// The beach's sand and bed, GameCube style: the drawn tile x the baked vertex colour (wet band, the water's
// tint and absorption with depth), plus two scrolling caustic layers weighted by UV2.x (baked by depth).
shader_type spatial;

#include "res://maps/beach/materials/beach_sea.gdshaderinc"

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D caustics : filter_linear_mipmap, repeat_enable;   // the light net (beach_water_albedo)
uniform float caustic_strength = 0.35;
uniform vec3 grade = vec3(0.95, 0.74, 0.54);   // sunset: the sand's palette pulled to warm tan for the low light
uniform vec3 caustic_color = vec3(1.0, 0.7, 0.4);   // sunset: the low sun's net is warm and faint

varying vec3 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	ALBEDO = texture(albedo_texture, UV).rgb * srgb_to_linear(COLOR.rgb) * grade;
	float c1 = smoothstep(0.955, 0.985, texture(caustics, world.xz / 3.4 + TIME * vec2(0.035, 0.012)).r);
	float c2 = smoothstep(0.955, 0.985, texture(caustics, world.xz / 5.1 - TIME * vec2(0.014, 0.03)).r);
	EMISSION = caustic_color * max(c1, c2) * caustic_strength * UV2.x;
	ROUGHNESS = 0.95;
	SPECULAR = 0.15;
}
