shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque;

// The lava's falls wave on the hell portal's one-sheet swirl: smaller, faster, deeper, pinned at the rim.
#define WAVE_SEE_THROUGH
#define WAVE_FALL_AMP 0.2
#define WAVE_SPEED 1.1
#define WAVE_SCALE 14.7
#include "res://maps/bentham_ring/materials/lava_wave.gdshaderinc"
