// The aspens' sky: a flat pale gradient, both colours measured between the leaves of the grove photo.
shader_type sky;

uniform vec3 top_color : source_color = vec3(0.839, 0.847, 0.941);
uniform vec3 horizon_color : source_color = vec3(0.965, 0.957, 0.937);
// Ryan's display shows SDR at 2x linear (scripts/fx/mac_lift.gdshader): the colours above are what he sees.
uniform float display_gain = 0.5;

void sky() {
	COLOR = mix(horizon_color, top_color, pow(clamp(normalize(EYEDIR).y, 0.0, 1.0), 0.5)) * display_gain;
}
