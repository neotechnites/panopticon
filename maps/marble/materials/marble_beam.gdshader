shader_type spatial;
// The oculus beam, one vane of six: pale, mixed, feathered at both edges and toward its foot, gone edge-on (forest's ray approach).
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 tint : source_color = vec3(1.0, 0.8, 0.46);
uniform float alpha_gain = 0.6;
uniform float taper = 0.8;

void vertex() {
	VERTEX.x *= mix(1.0, taper, UV.y);
}

void fragment() {
	float across = pow(1.0 - abs(UV.x * 2.0 - 1.0), 1.6);
	float down = smoothstep(0.0, 0.06, UV.y) * mix(1.0, 0.45, UV.y) * (1.0 - smoothstep(0.75, 1.0, UV.y));
	float face = smoothstep(0.1, 0.6, abs(dot(normalize(NORMAL), normalize(VIEW))));
	ALBEDO = tint;
	ALPHA = clamp(alpha_gain * across * down * face, 0.0, 1.0);
}
