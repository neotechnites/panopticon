// The great tree's shadow, drawn by a shadows-only copy of forest_tree.glb: solid only under the tower's roof
// (r < roof_radius); every leaf beyond it lets the sun through in world-XZ noise patches.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

uniform float roof_radius = 8.7;
uniform float gap = 0.5;
uniform float cell = 2.6;

varying vec3 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	float n = 0.65 * vnoise(world.xz / cell) + 0.35 * vnoise(world.xz / (cell * 0.45) + 17.0);
	if (n < gap * step(roof_radius, length(world.xz))) {
		discard;
	}
	ALBEDO = vec3(0.0);
}
