// What an imported glTF StandardMaterial3D draws, through the PS1 snap and affine UVs; tools/import/mipmap_textures.gd builds it.
// The importing hook picks the render_mode; PS1_ALPHA is defined for see-through surfaces.

#include "res://scripts/fx/ps1.gdshaderinc"

uniform sampler2D albedo_texture : source_color, hint_default_white, filter_nearest_mipmap_anisotropic, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform bool use_vertex_color = false;
uniform sampler2D emission_texture : source_color, hint_default_black, filter_nearest_mipmap_anisotropic, repeat_enable;
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 1.0;
uniform bool emission_multiply = false;
uniform float roughness = 1.0;
uniform float metallic = 0.0;
uniform float specular = 0.5;
uniform vec3 uv1_scale = vec3(1.0);
uniform vec3 uv1_offset = vec3(0.0);

void vertex() {
	UV = UV * uv1_scale.xy + uv1_offset.xy;
	PS1_VERTEX
}

void fragment() {
	vec2 uv = PS1_UV(UV);
	vec4 albedo = texture(albedo_texture, uv) * albedo_color;
	if (use_vertex_color) {
		albedo *= COLOR;
	}
	ALBEDO = albedo.rgb;
#ifdef PS1_ALPHA
	ALPHA = albedo.a;
#endif
	vec3 glow = texture(emission_texture, uv).rgb;
	EMISSION = (emission_multiply ? emission_color.rgb * glow : emission_color.rgb + glow) * emission_energy;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	SPECULAR = specular;
}
