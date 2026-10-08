// The beach's sea, GameCube style: see-through over the shallows and fading with depth into turquoise, then
// the bay's deep teal; a gentle swell, the sky in it at grazing angles, the sun's glint and sparkle,
// caustics on the shallow bed, and the swash running up the sand with its foam (beach_swash.gdshaderinc).
// COLOR carries data from beach_build.py: r = (depth + 2) / 14, g = the bay's pit, b = foam round rocks.
// Colour uniforms are source_color: Godot hands them over already linear.
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_always, fog_disabled;

#include "res://maps/beach/materials/beach_swash.gdshaderinc"

uniform sampler2D ripples : filter_linear_mipmap_anisotropic, repeat_enable;      // beach_water_normal: raw data
uniform sampler2D caustics : filter_linear_mipmap, repeat_enable;
uniform sampler2D foam_texture : filter_linear_mipmap, repeat_enable;

group_uniforms colours;
uniform vec3 foam_edge_color : source_color = vec3(0.88, 0.98, 0.96);
uniform vec3 shallow_color : source_color = vec3(0.62, 0.92, 0.86);
uniform vec3 turquoise_color : source_color = vec3(0.12, 0.78, 0.86);
uniform vec3 pit_color : source_color = vec3(0.0, 0.47, 0.6);
uniform vec3 open_color : source_color = vec3(0.0, 0.56, 0.8);
uniform vec3 sky_top : source_color = vec3(0.26, 0.63, 1.0);
uniform vec3 sky_horizon : source_color = vec3(0.64, 0.8, 0.9);
uniform vec3 foam_color : source_color = vec3(0.96, 0.99, 1.0);
group_uniforms;

group_uniforms light;
uniform vec3 sun_direction = vec3(0.7913, 0.5736, 0.212);   // toward the sun: the scene's Sun
uniform vec3 sun_color : source_color = vec3(1.0, 0.98, 0.9);
uniform float glint = 5.0;
uniform float sparkle = 14.0;
uniform float reflection = 0.7;
uniform float caustic_strength = 0.45;
group_uniforms;

group_uniforms swell;
uniform float bay_swell = 0.07;        // metres in the bay ...
uniform float sea_swell = 0.22;        // ... and out at sea
uniform float swell_speed = 1.0;
uniform vec2 horizon_fade = vec2(700.0, 3000.0);
group_uniforms;

varying vec3 world;
varying vec3 swell_normal;
varying float depth;
varying float pit;
varying float rock_foam;
varying float shore;

// One travelling wave: (height, d/dx, d/dz).
vec3 wave(vec2 p, vec2 dir, float length, float amp, float t) {
	float k = 6.2832 / length;
	float c = sqrt(9.8 / k);
	float ph = k * dot(normalize(dir), p) - k * c * t;
	vec2 d = normalize(dir) * k * amp * cos(ph);
	return vec3(amp * sin(ph), d.x, d.y);
}

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	depth = COLOR.r * 14.0 - 2.0;
	pit = COLOR.g;
	rock_foam = COLOR.b;
	float t = TIME * swell_speed;
	float r = length(world.xz);
	float amp = mix(bay_swell, sea_swell, smoothstep(80.0, 220.0, r)) * smoothstep(0.4, 4.0, depth)
		* (1.0 - smoothstep(600.0, 1500.0, r));
	vec3 w = wave(world.xz, vec2(-1.0, 0.18), 11.0, 0.55, t) + wave(world.xz, vec2(-0.8, -0.6), 7.0, 0.3, t * 1.1)
		+ wave(world.xz, vec2(-0.55, 0.85), 4.6, 0.15, t * 0.9);
	shore = 1.0 - smoothstep(0.25, 2.2, depth);
	float y = mix(SEA_Y + w.x * amp, swash_level(world.xz, TIME), shore);
	VERTEX.y += y - world.y;
	world.y = y;
	swell_normal = normalize(vec3(-w.y * amp, 1.0, -w.z * amp));
}

vec3 sky(vec3 dir) {
	float el = asin(clamp(dir.y, -1.0, 1.0));
	return mix(sky_horizon, sky_top, pow(clamp(el / radians(75.0), 0.0, 1.0), 0.5));
}

void fragment() {
	float t = TIME;
	float dist = length(world.xz - CAMERA_POSITION_WORLD.xz);
	float r = length(world.xz);
	float near = 1.0 - smoothstep(40.0, 260.0, dist);

	// ripples: two scrolling copies of the drawn normal tile, fading out with distance
	vec3 n1 = texture(ripples, world.xz / 9.0 + t * vec2(0.021, 0.006)).xyz * 2.0 - 1.0;
	vec3 n2 = texture(ripples, world.xz / 5.3 - t * vec2(0.007, 0.017)).xyz * 2.0 - 1.0;
	vec2 tilt = (n1.xy + n2.xy) * 0.22 * (0.25 + 0.75 * near);
	vec3 n = normalize(swell_normal + vec3(tilt.x, 0.0, tilt.y));
	vec3 v = normalize(CAMERA_POSITION_WORLD - world);
	if (!FRONT_FACING) {
		n = -n;
	}

	// colour by depth: shallow over the shelf, turquoise, the bay's deep teal, the open sea
	vec3 col = mix(shallow_color, turquoise_color, smoothstep(0.45, 2.0, depth));
	col = mix(col, pit_color, pit * smoothstep(2.5, 7.5, depth));
	col = mix(col, open_color, (1.0 - pit) * smoothstep(110.0, 700.0, r) * smoothstep(2.0, 7.0, depth));

	// caustics on the shallow bed: two scrolling copies of the light net, where they cross
	float c1 = texture(caustics, world.xz / 4.2 + t * vec2(0.03, 0.011)).r;
	float c2 = texture(caustics, world.xz / 5.9 - t * vec2(0.013, 0.027)).r;
	float caustic = clamp((min(c1, c2) - 0.9) * 9.0, 0.0, 1.0) * (1.0 - smoothstep(0.3, 2.6, depth)) * near;
	col += caustic * caustic_strength;

	// the sky at grazing angles, the sun's glint, and sparkle off the ripples
	float fresnel = 0.02 + 0.98 * pow(1.0 - clamp(dot(n, v), 0.0, 1.0), 5.0);
	vec3 refl = reflect(-v, n);
	col = mix(col, sky(refl), fresnel * reflection);
	float s = max(dot(refl, normalize(sun_direction)), 0.0);
	col += sun_color * (pow(s, 380.0) * glint + pow(s, 30.0) * 0.12);
	col += sun_color * pow(s, 2600.0) * sparkle * near;

	// foam: the swash's leading edge on the sand, lace in the run-up, rings round rocks
	float sand_y = SEA_Y - depth;
	float thick = world.y - sand_y;
	float lace = texture(foam_texture, world.xz / 3.1 + vec2(t * 0.02, 0.0)).r;
	float edge = (1.0 - smoothstep(0.0, 0.06, thick)) * shore;
	float run = shore * (1.0 - smoothstep(0.0, 0.22, thick)) * lace;
	float ring = rock_foam * smoothstep(0.35, 0.8, lace * (0.65 + 0.35 * sin(t * 1.3 + world.x * 0.7)));
	float foam = clamp(max(max(edge * (0.55 + 0.45 * lace), run), ring), 0.0, 1.0);
	col = mix(col, foam_color, foam);

	// toward the horizon, the sky's own horizon colour, so sea and sky meet without an edge
	float far = pow(smoothstep(horizon_fade.x, horizon_fade.y, r), 1.4);
	col = mix(col, sky_horizon, far);

	float alpha = mix(0.38, 0.97, smoothstep(0.12, 2.3, depth));
	alpha = max(alpha, foam);
	alpha = mix(alpha, 1.0, far);
	if (!FRONT_FACING) {
		col = pit_color * 0.8;
		alpha = 0.9;
	}
	ALBEDO = col;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
