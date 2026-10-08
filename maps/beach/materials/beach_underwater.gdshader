// Under the water: a shell round the camera, drawn only while the camera is below the sea, so a runner who
// sinks sees deep teal closing in rather than the sky under the bay. Five shells (2.5 to 34 m) make the fade.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_front, skip_vertex_transform, fog_disabled, shadows_disabled;

#include "res://maps/beach/materials/beach_swash.gdshaderinc"

uniform vec3 water_color : source_color = vec3(0.0, 0.32, 0.42);
uniform float radius = 18.0;
uniform float opacity = 0.5;

void vertex() {
	float under = step(CAMERA_POSITION_WORLD.y, SEA_Y - 0.02);
	VERTEX = (VIEW_MATRIX * vec4(CAMERA_POSITION_WORLD + VERTEX * 2.0 * radius * under, 1.0)).xyz;
}

void fragment() {
	ALBEDO = water_color * 0.5;             // Ryan's HDR desktop shows SDR at 2x linear
	ALPHA = opacity;
}
