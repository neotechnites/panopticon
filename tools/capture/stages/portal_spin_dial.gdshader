shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque;

// Capture only (stages/portal_spin.gd): portal_wave.gdshader with the spin as a dial, the angle fed each frame.
#define WAVE_SEE_THROUGH
#define WAVE_FALL_AMP 0.6
#define WAVE_SPEED 1.1
#define WAVE_SCALE 7.35
uniform float spin_angle = 0.0;
#define WAVE_SPIN (spin_angle / max(TIME, 0.0001))
#include "res://maps/bentham_ring/materials/lava_wave.gdshaderinc"
