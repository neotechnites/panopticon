// The beach's sand and bed, GameCube style: the drawn tile x the baked vertex colour (wet band, the water's
// tint and absorption with depth), plus two scrolling caustic layers weighted by UV2.x (baked by depth).
// His sand tile's own edges do not match (a 4x step across them), so on a continuous world projection they
// drew a 12.8 m grid of straight lines. tile_seamless reads it with no edge at all; a slow noise then slides
// the lattice about and drifts the light, so the repeat never lines up either.
shader_type spatial;

#include "res://maps/beach/materials/beach_sea.gdshaderinc"

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D caustics : filter_linear_mipmap, repeat_enable;   // the light net (beach_water_albedo)
uniform sampler2D variation : hint_default_white, filter_linear_mipmap, repeat_enable;   // seamless noise
uniform float caustic_strength = 0.7;
uniform float variation_metres = 34.0;    // the noise's world repeat; the slow field below is 2.7x this
uniform float variation_strength = 0.09;  // the macro light/dark drift, +-
uniform float wander_tiles = 0.5;         // how far that slow field slides the 12.8 m lattice, in tiles

varying vec3 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 slow = world.xz / (variation_metres * 2.7);
	float drift = texture(variation, slow + vec2(0.5)).r;
	vec2 wander = vec2(texture(variation, slow).r, texture(variation, slow + vec2(0.37, 0.11)).r) - vec2(0.5);
	vec2 uv = UV + wander * (wander_tiles * 2.0);
	vec3 tile = tile_seamless(albedo_texture, uv, tile_mean(albedo_texture));
	tile *= 1.0 + variation_strength * (drift - 0.5) * 2.0;
	ALBEDO = tile * srgb_to_linear(COLOR.rgb);
	float c1 = smoothstep(0.955, 0.985, texture(caustics, world.xz / 3.4 + TIME * vec2(0.035, 0.012)).r);
	float c2 = smoothstep(0.955, 0.985, texture(caustics, world.xz / 5.1 - TIME * vec2(0.014, 0.03)).r);
	EMISSION = vec3(0.85, 1.0, 0.95) * max(c1, c2) * caustic_strength * UV2.x;
	ROUGHNESS = 0.95;
	SPECULAR = 0.15;
}
