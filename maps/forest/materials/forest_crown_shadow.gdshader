// Leaf shadow, drawn by shadows-only copies of the tree, the map and the canopy: solid under the tower's roof
// (r < roof_radius) and on the ring's wall (r > wall_radius) below solid_below_y; elsewhere noise lets light through.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

uniform float roof_radius = 8.7;
uniform float solid_below_y = -1000.0;
uniform float wall_radius = 0.0;
uniform float gap = 0.39;
uniform float cell = 1.0;
uniform float soft = 0.14;
uniform float sway = 0.12;        // metres the holes drift back and forth, as leaves in a light wind
uniform float sway_speed = 1.0;   // radians per second: about a 6 s swing

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
	// Noise across the sun's rays (shadow camera rotation), so stacked leaf layers share one set of holes.
	vec2 q = (mat3(VIEW_MATRIX) * world).xy;
	vec2 s = q + sway * vec2(sin(TIME * sway_speed), 0.6 * sin(TIME * sway_speed * 0.73 + 1.3));
	float n = 0.65 * vnoise(s / cell) + 0.35 * vnoise(s / (cell * 0.45) + 17.0);
	float r = length(world.xz);
	float wall = step(wall_radius, r) * (1.0 - step(solid_below_y, world.y));
	float open = step(roof_radius, r) * (1.0 - wall);
	// A dithered fringe (fixed in world, fine grain) the shadow filter averages into a soft edge.
	float d = (hash(floor(q * 9.0)) - 0.5) * soft;
	if ((n + d) * open < gap * open) {
		discard;
	}
	ALBEDO = vec3(0.0);
}
