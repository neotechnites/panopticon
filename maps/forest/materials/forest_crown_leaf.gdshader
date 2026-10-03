// The tree's leaf surfaces as their imported StandardMaterial3D draws them, plus a textured warm fill on the
// crown's down-facing underside (r > fill_radius) that no sun reaches, so it reads about as lit as the leaf walls.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 tint = vec3(1.0);    // the glTF baseColorFactor, linear
uniform float roughness = 0.95;
uniform vec3 fill = vec3(0.80, 0.68, 0.48);   // linear light on the underside: the suns' warm tone
uniform float fill_radius = 11.0;  // the crown's rim; the guard's canopy inside it stays as it was

varying vec3 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 albedo = texture(albedo_texture, UV).rgb * COLOR.rgb * tint;
	ALBEDO = albedo;
	ROUGHNESS = roughness;
	METALLIC = 0.0;
	SPECULAR = 0.5;
	float down = smoothstep(0.1, 0.6, -(INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).y);
	float crown = smoothstep(fill_radius - 1.0, fill_radius + 1.0, length(world.xz));
	EMISSION = albedo * fill * down * crown;
}
