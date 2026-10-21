shader_type spatial;
// The oculus beam: an open cone, unshaded and additive, soft at its silhouette, faint at its foot, with a few slow streaks.
render_mode unshaded, blend_add, cull_back, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 tint : source_color = vec3(1.0, 0.95, 0.82);
uniform float strength = 0.3;
uniform float streaks = 9.0;

void fragment() {
	float face = pow(clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0), 2.0);
	float fall = mix(1.0, 0.25, UV.y) * smoothstep(0.0, 0.04, UV.y) * (1.0 - smoothstep(0.7, 1.0, UV.y));
	float band = 0.75 + 0.25 * sin(UV.x * 6.2831853 * streaks + sin(UV.x * 31.0) * 0.6);
	ALBEDO = tint * strength * face * fall * band;
}
