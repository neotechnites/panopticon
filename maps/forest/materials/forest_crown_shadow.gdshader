// The great tree's shadow, drawn by a shadows-only copy of forest_tree.glb: solid over the guard's floor,
// broken past solid_radius by world-XZ noise so the sun falls through the crown onto the pit in patches.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

uniform float solid_radius = 11.0;
uniform float ramp = 4.0;
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
	if (n < gap * smoothstep(solid_radius, solid_radius + ramp, length(world.xz))) {
		discard;
	}
	ALBEDO = vec3(0.0);
}
