shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque;

// The lava's falls wave on every finish portal's one-sheet swirl: 0.3 m deep, crests half as dense, pinned at the rim, turning.
#define WAVE_SEE_THROUGH
#define WAVE_FALL_AMP 0.6
#define WAVE_SPEED 1.1
#define WAVE_SCALE 7.35
// The swirl spins about its centre: 0 is still, 0.8 rad/s one turn every ~7.9 s.
uniform float wave_spin = 0.0;
uniform float spin_angle = 0.0;
#define WAVE_SPIN (spin_angle / max(TIME, 0.0001))
#include "res://maps/bentham_ring/materials/lava_wave.gdshaderinc"
