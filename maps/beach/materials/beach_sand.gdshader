// The beach's sand and bed, GameCube style: the drawn tile x the baked vertex colour (wet band, the water's
// tint and absorption with depth), plus two scrolling caustic layers weighted by UV2.x (baked by depth).
// The tile's 12.8 m repeat is hidden the usual way: a second, turned read of it chosen by a low-frequency
// noise so neither grid lines up, and a slow light/dark drift from that noise at a much larger scale.
shader_type spatial;

#include "res://maps/beach/materials/beach_sea.gdshaderinc"

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D caustics : filter_linear_mipmap, repeat_enable;   // the light net (beach_water_albedo)
uniform sampler2D variation : hint_default_white, filter_linear_mipmap, repeat_enable;   // seamless noise
uniform float caustic_strength = 0.7;
uniform float variation_metres = 34.0;    // the noise's world repeat: which read goes where
uniform float variation_strength = 0.09;  // the macro light/dark drift, +-
uniform float second_turn = 0.63;         // the second read's turn, radians
uniform float second_scale = 0.79;        // and its uv scale: a 16.2 m repeat, so the two grids never agree

varying vec3 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float ct = cos(second_turn), st = sin(second_turn);
	vec2 uv2 = mat2(vec2(ct, -st), vec2(st, ct)) * UV * second_scale + vec2(0.37, 0.11);
	float pick = texture(variation, world.xz / variation_metres).r;
	float drift = texture(variation, world.xz / (variation_metres * 2.7) + vec2(0.5)).r;
	vec3 tile = mix(texture(albedo_texture, UV).rgb, texture(albedo_texture, uv2).rgb, smoothstep(0.35, 0.65, pick));
	tile *= 1.0 + variation_strength * (drift - 0.5) * 2.0;
	ALBEDO = tile * srgb_to_linear(COLOR.rgb);
	float c1 = smoothstep(0.955, 0.985, texture(caustics, world.xz / 3.4 + TIME * vec2(0.035, 0.012)).r);
	float c2 = smoothstep(0.955, 0.985, texture(caustics, world.xz / 5.1 - TIME * vec2(0.014, 0.03)).r);
	EMISSION = vec3(0.85, 1.0, 0.95) * max(c1, c2) * caustic_strength * UV2.x;
	ROUGHNESS = 0.95;
	SPECULAR = 0.15;
}
