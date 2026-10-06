shader_type spatial;
render_mode cull_back, unshaded;

// Self-lit: the lava glows by itself and no scene light lands on it (it is what lights the pit).
#define WAVE_SELF_LIT 0.25

#define WAVE_FILTER filter_linear_mipmap_anisotropic
#include "res://maps/bentham_ring/materials/lava_wave.gdshaderinc"
