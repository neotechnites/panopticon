// The waterfall, its stream, foam ring and mist: beach_fall_albedo scrolled down the flow (v along it, baked by
// beach_build.py), alpha from the tile times the vertex alpha (the stream and mist fade out), unshaded white water.
shader_type spatial;
render_mode blend_mix, cull_disabled, unshaded, depth_draw_opaque, shadows_disabled;

uniform sampler2D sheet : source_color, filter_linear_mipmap, repeat_enable;
uniform float speed = 0.7;             // tiles (12.8 m) per second down the flow
uniform float display_gain = 0.73;     // Ryan's HDR desktop shows SDR at 2x linear (beach_water.gdshader)

void fragment() {
	vec4 t = texture(sheet, vec2(UV.x, UV.y - TIME * speed));
	ALBEDO = t.rgb * display_gain;
	ALPHA = t.a * COLOR.a;
}
