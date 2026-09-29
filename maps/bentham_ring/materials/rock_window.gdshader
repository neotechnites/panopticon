shader_type spatial;
render_mode cull_back;

// A texture that repeats inside one window of a shared sheet (glTF KHR_texture_transform).
// Mips follow the unwrapped UV, so the wrap draws no seam.

uniform sampler2D albedo_texture : source_color, hint_default_black, filter_nearest_mipmap_anisotropic, repeat_disable;
uniform sampler2D emission_texture : source_color, hint_default_black, filter_nearest_mipmap_anisotropic, repeat_disable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 1.0;
uniform float roughness = 1.0;
uniform float metallic = 0.0;
uniform float specular = 0.5;
uniform vec2 window_offset = vec2(0.0);
uniform vec2 window_scale = vec2(1.0);

void fragment() {
	vec2 uv = window_offset + fract(UV) * window_scale;
	vec2 dx = dFdx(UV) * window_scale;
	vec2 dy = dFdy(UV) * window_scale;
	ALBEDO = textureGrad(albedo_texture, uv, dx, dy).rgb * albedo_color.rgb;
	EMISSION = textureGrad(emission_texture, uv, dx, dy).rgb * emission_color.rgb * emission_energy;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	SPECULAR = specular;
}
