shader_type spatial;
// The oculus' light shaft: an open cone drawn additively, bright face-on, gone at its silhouette and floor.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec3 tint : source_color = vec3(1.0, 0.96, 0.88);
uniform float strength = 0.18;

void fragment() {
	float face = pow(abs(dot(normalize(NORMAL), normalize(VIEW))), 1.6);
	float fade = mix(1.0, 0.35, UV.y) * (1.0 - smoothstep(0.85, 1.0, UV.y));
	ALBEDO = tint * strength * face * fade;
}
