shader_type spatial;
// The oculus' light shaft: an open cone drawn additively as a flat, hard-edged god ray (its silhouette IS the edge), dimming toward the floor.
render_mode unshaded, blend_add, cull_back, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 tint : source_color = vec3(1.0, 0.96, 0.88);
uniform float strength = 0.12;

void fragment() {
	float fade = mix(1.0, 0.4, UV.y) * (1.0 - smoothstep(0.9, 1.0, UV.y));
	ALBEDO = tint * strength * fade;
}
