// The map's leaf dapple over a player, as a multiply pass on its lit body: full leaf shade dims it to dapple_shade.
shader_type spatial;
render_mode blend_mul, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
#include "res://characters/materials/character_dapple.gdshaderinc"

varying vec3 dapple_world;
varying vec2 dapple_drift_v;
varying vec2 dapple_fleck_v;

void vertex() {
	dapple_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	dapple_drift_v = dapple_drift(TIME);
	dapple_fleck_v = dapple_fleck_drift(TIME);
}

void fragment() {
	float lit_share = 0.5 * (dapple_pattern(dapple_world, dapple_sun_a, dapple_drift_v, dapple_fleck_v) + dapple_pattern(dapple_world, dapple_sun_b, dapple_drift_v, dapple_fleck_v));
	ALBEDO = vec3(mix(dapple_shade, 1.0, lit_share));
}
