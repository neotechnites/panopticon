shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

// A sun shaft: unshaded additive vertex colour, seen and never lighting anything. ALBEDO clamps at 1, so brightness past that comes from alpha_gain on the vertex alpha.
uniform vec3 tint : source_color = vec3(1.0, 0.85, 0.6);
uniform float alpha_gain = 4.0;

void fragment() {
	ALBEDO = COLOR.rgb * tint;
	ALPHA = min(COLOR.a * alpha_gain, 1.0);
}
