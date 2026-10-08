// The beach's swash, shared by the sea and the sand so the foam line and the wet sand agree.
// A wave runs up the shore fast and draws back slowly, its phase drifting along the bay.

const float SEA_Y = 22.6;          // the still water's surface (beach_build.py WATER_Z)
const float SWASH_AMP = 0.28;      // metres from the backwash's foot to the run-up's crest
const float SWASH_PERIOD = 7.5;    // seconds between waves

float swash_phase(vec2 xz, float t) {
	float th = atan(xz.y, xz.x);
	return t / SWASH_PERIOD + th * 0.32 + 0.12 * sin(th * 7.0);
}

float swash_shape(float p) {
	p = fract(p);
	return p < 0.3 ? smoothstep(0.0, 0.3, p) : 1.0 - smoothstep(0.3, 1.0, p);
}

// The water's height at the shore: from 0.3 of the stroke below still water to 0.7 above.
float swash_level(vec2 xz, float t) {
	return SEA_Y + SWASH_AMP * (swash_shape(swash_phase(xz, t)) - 0.3);
}

// How high the sand is wet: the run-up's crest, drying back as the wave withdraws.
float wet_level(vec2 xz, float t) {
	float p = fract(swash_phase(xz, t));
	float dried = p < 0.3 ? 0.15 : 0.7 - 0.55 * smoothstep(0.3, 1.0, p);
	return max(swash_level(xz, t), SEA_Y + SWASH_AMP * dried);
}

vec3 srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}
