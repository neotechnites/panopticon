shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

// A sun shaft: unshaded additive, vertex alpha only; tint is the lit lane patch's rendered colour. alpha_gain is the overall opacity of every streak and must stay below 1 to dim (vertex alpha reaches 1 at the core).
uniform vec3 tint : source_color = vec3(1.0, 0.805, 0.4);
uniform float alpha_gain = 0.1;

void fragment() {
	ALBEDO = tint;
	ALPHA = min(COLOR.a * alpha_gain, 1.0);
}
