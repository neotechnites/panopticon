shader_type spatial;
// A sun beam from a drum window: an open cylinder drawn additively, both faces, soft at its silhouette, faint at the window, running the whole way to the floor.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec3 tint : source_color = vec3(1.0, 0.93, 0.68);
uniform float strength = 0.16;

void fragment() {
	float face = 0.15 + 0.85 * abs(dot(normalize(NORMAL), normalize(VIEW)));
	float fade = smoothstep(0.0, 0.2, UV.y) * (1.0 - smoothstep(0.95, 1.0, UV.y));
	ALBEDO = tint * strength * face * fade;
}
