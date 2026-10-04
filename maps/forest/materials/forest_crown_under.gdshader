// The crown's underside: leaf lit from behind. COLOR_0 is the light through it, UV2.x the share that is
// ordinary lit leaf instead (the crown's rim, the cove onto the drum's head), so it meets both unbroken.
shader_type spatial;
render_mode cull_back;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float glow = 0.3;

void fragment() {
	vec3 leaf = texture(albedo_texture, UV).rgb * COLOR.rgb;
	float lit = clamp(UV2.x, 0.0, 1.0);
	ALBEDO = leaf * lit;
	EMISSION = leaf * (1.0 - lit) * glow;
	ROUGHNESS = 0.95;
	SPECULAR = 0.5 * lit;
}
