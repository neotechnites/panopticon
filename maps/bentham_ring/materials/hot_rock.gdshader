shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Hell's rock (HellRock, HellShade, HellEmber): the imported StandardMaterial3D's look plus a rim of heat
// where it meets lava, breathing with the lava's swell. Swapped in at import, never in the lightmap bake.

#include "res://maps/bentham_ring/materials/lava_swell.gdshaderinc"

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float roughness : hint_range(0.0, 1.0) = 1.0;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float specular : hint_range(0.0, 1.0) = 0.5;
uniform vec3 uv1_scale = vec3(1.0);
uniform vec3 uv1_offset = vec3(0.0);

// Tuning: change the defaults here to keep them (the imported materials never store these).
uniform vec3 heat_color : source_color = vec3(1.0, 0.36, 0.1);   // deep ember, the lava's own
uniform float heat_energy : hint_range(0.0, 4.0, 0.05) = 0.6;    // glow strength right at the lava
uniform float heat_reach : hint_range(0.25, 4.0, 0.05) = 1.5;    // metres up and away it fades out over
uniform float heat_pulse : hint_range(0.0, 1.0, 0.01) = 0.3;     // how much it breathes with the swell

// tools/textures/hot_rock_mask.py: R metres to the nearest lava in xz, G that lava's top y.
uniform sampler2D heat_mask : hint_default_white, filter_linear, repeat_disable;
const float MASK_HALF = 60.0;
const float MASK_MAX_DIST = 4.0;
const float MASK_Y_MIN = -16.0;
const float MASK_Y_SPAN = 48.0;
const float SWELL_SPEED = 0.55;   // lava_wave.gdshaderinc's speed

varying vec3 world_pos;
varying float pulse;

void vertex() {
	UV = UV * uv1_scale.xy + uv1_offset.xy;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	pulse = 1.0 + heat_pulse * lava_swell(world_pos.xz, vec2(0.0), TIME * SWELL_SPEED);
}

void fragment() {
	vec4 tex = texture(albedo_texture, UV);
	ALBEDO = albedo_color.rgb * tex.rgb;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	SPECULAR = specular;
	vec2 m = texture(heat_mask, world_pos.xz / (2.0 * MASK_HALF) + 0.5).rg;
	float d = length(vec2(m.r * MASK_MAX_DIST, max(world_pos.y - (MASK_Y_MIN + m.g * MASK_Y_SPAN), 0.0)));
	float heat = clamp(1.0 - d / heat_reach, 0.0, 1.0);
	// cubed: a hot rim at the lava, not a coat; the texture's grain carries it, so it reads as rock
	EMISSION = heat_color * (heat_energy * heat * heat * heat * pulse * clamp(tex.r * 12.0, 0.4, 1.5));
}
