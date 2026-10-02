shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_opaque;

// The lava wave on the hell portal's swirl: see-through (albedo alpha), bulging off the disc's face.
#define WAVE_SEE_THROUGH
#include "res://maps/bentham_ring/materials/lava_wave.gdshaderinc"
