shader_type spatial;
// Where the oculus' shaft lands on the pit floor: a soft additive pool, full in the middle, gone at its rim.
render_mode unshaded, blend_add, cull_back, depth_draw_never, shadows_disabled;

uniform vec3 tint : source_color = vec3(1.0, 0.96, 0.88);
uniform float strength = 0.22;

void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	ALBEDO = tint * strength * (1.0 - smoothstep(0.35, 1.0, d));
}
