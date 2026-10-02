shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque;

// The lava's falls wave on every finish portal's one-sheet swirl: 0.8 m deep, crests half as dense, pinned at the rim.
#define WAVE_SEE_THROUGH
#define WAVE_FALL_AMP 1.6
#define WAVE_SPEED 1.1
#define WAVE_SCALE 7.35
#include "res://maps/bentham_ring/materials/lava_wave.gdshaderinc"
