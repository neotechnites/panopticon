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
uniform vec3 shallow_color : source_color = vec3(0.4, 0.86, 0.8);
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

uniform float display_gain = 0.73;   // Ryan's HDR desktop shows SDR at 2x linear; unshaded output is undone by 2^(-1/2.2)

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

// The breaker: a low roll that crosses the shelf in the last 30% of each swash cycle and breaks onto the sand
// as the run-up starts. x: (height, breaking 0..1, signed depth from its crest; negative is shoreward).
vec3 breaker(float d, vec2 xz, float t) {
	float p = fract(swash_phase(xz, t));
	if (p < 0.7) {
		return vec3(0.0, 0.0, 9.0);
	}
	float db = 0.75 * (1.0 - (p - 0.7) / 0.3);
	float a = 0.11 * (1.0 - smoothstep(0.42, 0.75, db)) * smoothstep(0.0, 0.18, db);
	float x = d - db;
	float q = x / (x < 0.0 ? 0.06 : 0.22);
	float h = a * exp(-q * q);                 // (pow of a negative base is NaN in GLSL)
	return vec3(h, 1.0 - smoothstep(0.12, 0.42, db), x);
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
	float y = mix(SEA_Y + w.x * amp, swash_level(world.xz, TIME), shore) + breaker(depth, world.xz, TIME).x;
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
	vec3 n3 = texture(ripples, world.xz / 61.0 + t * vec2(0.004, 0.0015)).xyz * 2.0 - 1.0;   // far mottle
	vec2 tilt = (n1.xy + n2.xy) * 0.22 * (0.25 + 0.75 * near) + n3.xy * 0.12 * (1.0 - near);
	vec3 n = normalize(swell_normal + vec3(tilt.x, 0.0, tilt.y));
	vec3 v = normalize(CAMERA_POSITION_WORLD - world);
	if (!FRONT_FACING) {
		n = -n;
	}

	// colour by depth: shallow over the shelf, turquoise, the bay's deep teal, the open sea
	// (the shelf's colour spreads down the whole drop-off: no seam where the sand falls away)
	vec3 col = mix(shallow_color, turquoise_color, smoothstep(0.3, 9.0, depth));
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
	// close up the glint breaks into small sharp sparkles on a fine ripple net (Sunshine), far off it is whole
	float s = max(dot(refl, normalize(sun_direction)), 0.0);
	vec3 nf = texture(ripples, world.xz / 1.7 + t * vec2(0.05, -0.03)).xyz * 2.0 - 1.0;
	float sf = max(dot(reflect(-v, normalize(n + vec3(nf.x, 0.0, nf.y) * 0.35 * near)), normalize(sun_direction)), 0.0);
	float net = smoothstep(0.95, 0.985, texture(caustics, world.xz / 1.3 - t * vec2(0.04, 0.025)).r);
	float shine = mix(pow(s, 380.0) * glint, pow(sf, 900.0) * glint * 2.5 * net, near)
		+ pow(s, 30.0) * 0.12 * (1.0 - 0.7 * near) + pow(sf, 2600.0) * sparkle * near;
	col += sun_color * shine;

	// the wave: the breaker's crest foam and white water, then the swash: a crisp ragged foam line at its
	// front, lace on the thin sheet behind that breaks into patches and fades as it drains; rings round rocks
	float sand_y = SEA_Y - depth;
	float thick = world.y - sand_y;
	float lace = texture(foam_texture, world.xz / 3.1 + vec2(t * 0.02, 0.0)).r;
	float lace2 = texture(foam_texture, world.xz / 1.4 - vec2(0.0, t * 0.03)).r;
	vec3 bk = breaker(depth, world.xz, t);
	float cq = (bk.z + 0.015) / 0.03;
	float crest = exp(-cq * cq) * bk.y * smoothstep(0.15, 0.45, lace2 + 0.25);
	float white = step(0.0, bk.z) * (1.0 - smoothstep(0.0, 0.18 * bk.y + 0.001, bk.z)) * bk.y * smoothstep(0.35, 0.6, lace);
	float sp = fract(swash_phase(world.xz, t));
	float drain = smoothstep(0.3, 1.0, sp);
	float front = (1.0 - smoothstep(0.012, 0.03, thick - 0.012 * lace2)) * shore * (1.0 - 0.6 * drain);
	float sheet = shore * (1.0 - smoothstep(0.04, 0.16, thick))
		* smoothstep(0.3 + 0.45 * drain, 0.42 + 0.45 * drain, lace) * (1.0 - 0.5 * drain);
	float ring = rock_foam * smoothstep(0.35, 0.8, lace * (0.65 + 0.35 * sin(t * 1.3 + world.x * 0.7)));
	float foam = clamp(max(max(max(front, sheet), max(crest, white)), ring), 0.0, 1.0);
	col = mix(col, foam_color, foam);
	col = mix(col, turquoise_color * 1.1, clamp(bk.x / 0.11, 0.0, 1.0) * step(bk.z, 0.0) * 0.5);   // the roll's face

	// toward the horizon, the sky's own horizon colour, so sea and sky meet without an edge
	float far = pow(smoothstep(horizon_fade.x, horizon_fade.y, r), 1.4);
	col = mix(col, sky_horizon, far);

	float alpha = mix(0.5, 1.0, smoothstep(0.12, 1.1, depth));      // opaque before the bed ends (1.2 m down)
	alpha = mix(alpha, 0.3, shore * (1.0 - smoothstep(0.02, 0.1, thick)));        // the swash's thin sheet
	alpha = max(alpha, clamp(bk.x / 0.11, 0.0, 1.0) * 0.8);
	alpha = max(alpha, max(foam, clamp(shine, 0.0, 1.0)));
	alpha = mix(alpha, 1.0, far);
	if (!FRONT_FACING) {                    // from under the water: the surface seen from below, deep teal
		col = mix(turquoise_color * 0.75, pit_color * 0.55, smoothstep(0.0, 40.0, dist));
		alpha = 1.0;
	}
	ALBEDO = col * display_gain;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
