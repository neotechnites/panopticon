shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_opaque;

// The hell portal's swirl: a flat see-through disc, texture drawn static and nearest-filtered.

uniform sampler2D albedo_texture : source_color, filter_nearest_mipmap_anisotropic, repeat_enable;
uniform sampler2D emission_texture : source_color, filter_nearest_mipmap_anisotropic, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform vec4 emission_color : source_color = vec4(1.0);
uniform float emission_energy = 1.0;
uniform float roughness = 1.0;
uniform float metallic = 0.0;
uniform vec3 uv1_scale = vec3(1.0);
uniform vec3 uv1_offset = vec3(0.0);

void vertex() {
	UV = UV * uv1_scale.xy + uv1_offset.xy;
}

void fragment() {
	vec4 albedo_tex = texture(albedo_texture, UV);
	ALBEDO = albedo_tex.rgb * albedo_color.rgb;
	ALPHA = albedo_tex.a * albedo_color.a;
	EMISSION = texture(emission_texture, UV).rgb * emission_color.rgb * emission_energy;
	ROUGHNESS = roughness;
	METALLIC = metallic;
}
