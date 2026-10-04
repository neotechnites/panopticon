// forest_crown_under.gdshader plus a tint, for forest_green.tscn: the same backlit leaf, recoloured without touching the tile.
shader_type spatial;
render_mode cull_back;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float glow = 0.3;
// Linear multiplier on tile x vertex light; blue runs over 1 because the tile holds almost none.
uniform vec3 tint = vec3(1.0);

void fragment() {
	vec3 leaf = texture(albedo_texture, UV).rgb * COLOR.rgb * tint;
	float lit = clamp(UV2.x, 0.0, 1.0);
	ALBEDO = leaf * lit;
	EMISSION = leaf * (1.0 - lit) * glow;
	ROUGHNESS = 0.95;
	SPECULAR = 0.5 * lit;
}
