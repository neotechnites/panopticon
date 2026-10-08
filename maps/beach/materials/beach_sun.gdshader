// The sun's disc and glow, drawn on a quad held square to the camera 2.5 km out toward the scene's Sun, so the
// disc stays round at any field of view (a sky shader's disc stretches off-centre). Occluded like any far thing.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, skip_vertex_transform, fog_disabled, shadows_disabled;

uniform vec3 sun_direction = vec3(0.7913, 0.5736, 0.212);   // toward the sun: the scene's Sun (+Z)
uniform vec3 sun_color : source_color = vec3(1.0, 0.98, 0.9);
uniform float disc_degrees = 2.2;
uniform float glow_degrees = 8.0;
uniform float glow = 0.3;
uniform float sun_distance = 2500.0;
uniform float display_gain = 0.73;   // Ryan's HDR desktop shows SDR at 2x linear; unshaded output is undone by 2^(-1/2.2)

varying vec2 offset;

void vertex() {
	offset = VERTEX.xy * 2.0;                                     // the QuadMesh is 1 x 1: -1..1 across it
	float span = sun_distance * tan(radians(glow_degrees * 4.0));
	vec3 centre = (VIEW_MATRIX * vec4(CAMERA_POSITION_WORLD + normalize(sun_direction) * sun_distance, 1.0)).xyz;
	VERTEX = centre + vec3(offset * span, 0.0);
}

void fragment() {
	float a = length(offset) * glow_degrees * 4.0;                 // degrees from the sun's centre
	float disc = smoothstep(disc_degrees * 1.1, disc_degrees * 0.9, a);
	float halo = glow * exp(-a / glow_degrees) * (1.0 - smoothstep(glow_degrees * 3.0, glow_degrees * 4.0, a));
	ALBEDO = sun_color * (disc * 1.6 + halo) * display_gain;
}
