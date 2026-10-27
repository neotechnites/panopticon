shader_type spatial;
// Where the oculus' ray lands on the pit floor: a soft additive disc, full in the middle, gone at r 20 (the
// cone's foot) well inside its plane's rim. It does its own depth test against the opaque depth with a reach:
// drawn over anything less than `reach` in front of it (the spikes' feet and their square pads, which a plain
// depth test cut out of the glow as dark squares -- Ryan 2026-10-26: "the shadow it casts on the spikes is a
// perfect square"), hidden behind anything further in front (the tower, the deck).
render_mode unshaded, blend_add, cull_back, depth_draw_never, depth_test_disabled, shadows_disabled, fog_disabled;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec3 tint : source_color = vec3(1.0, 0.96, 0.88);
uniform float strength = 0.10;
uniform float reach = 1.2;

void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	float depth = texture(depth_tex, SCREEN_UV).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth * 2.0 - 1.0);
	vec4 scene = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	float scene_z = -scene.z / scene.w;
	float here_z = -VERTEX.z;
	float show = smoothstep(-reach, -reach * 0.4, scene_z - here_z);
	ALBEDO = tint * strength * (1.0 - smoothstep(0.35, 0.91, d)) * show;
}
