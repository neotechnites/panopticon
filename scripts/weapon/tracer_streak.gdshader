// A shot's streak: unshaded, alpha-blended, unculled, no depth write.
// A quad seen edge-on fades out, so a streak viewed down its own line is not a hairline.
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 albedo : source_color = vec4(1.0);
uniform bool use_vertex_color = false;

void fragment() {
	vec4 color = albedo;
	// Only UV.x = 1 faces fade on a vertex-coloured bullet (the tail); the head never does.
	float weight = 1.0;
	if (use_vertex_color) {
		color *= COLOR;
		weight = UV.x;
	}
	vec3 face = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	float facing = abs(dot(face, normalize(VIEW)));
	ALBEDO = color.rgb;
	ALPHA = color.a * mix(1.0, smoothstep(0.05, 0.3, facing), weight);
}
