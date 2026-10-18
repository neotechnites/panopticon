// The shore's waves, the GameCube way (Gelato Beach, Emerald Coast): one long strip along the waterline
// (beach_waves.glb) carries two trains of waves. Each is a continuous line that rolls in, its soft white wash
// and drawn lace (beach_wave_albedo) running up the sand on a thin sheet and draining back, leaving wet sand
// that dries. Where it arrives drifts along the shore, its reach swells in sets and lulls.
// COLOR is data (beach_build.py build_waves): r = 0 on the heads' rock, g = (metres up the sand + 3) / 6.6, b = 0..1 along the strip.
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;

uniform sampler2D foam : filter_linear_mipmap, repeat_enable;
uniform sampler2D edge_lace : filter_linear_mipmap, repeat_enable;   // beach_foam_albedo: the standing lace at the edge
uniform vec3 foam_color : source_color = vec3(0.96, 0.99, 1.0);
uniform vec3 sheet_color : source_color = vec3(0.62, 0.93, 0.9);
uniform vec3 wet_color : source_color = vec3(0.62, 0.56, 0.45);
uniform float set_seconds = 40.0;      // bigger waves come in sets, then a lull
uniform float back = -2.6;             // metres out in the water a wave rolls in from and drains back to
uniform float display_gain = 0.73;     // Ryan's HDR desktop shows SDR at 2x linear (beach_water.gdshader)

varying float up;
varying float knoll;
varying float along;

float hash(float x) {
	return fract(sin(x * 91.7 + 13.1) * 43758.5);
}

// Smooth 1-D noise, 0..1.
float noise1(float x) {
	float i = floor(x);
	float f = fract(x);
	return mix(hash(i), hash(i + 1.0), f * f * (3.0 - 2.0 * f));
}

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Smooth 2-D noise, 0..1: breaks the run-up's edge into scallops and thins the foam unevenly.
float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), f.x), mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), f.x), f.y);
}

// One train at s metres along the shore, h metres up the sand: (foam, sheet, wet). Each stretch of shore has its
// own phase and reach (noise along s at 60, 29, 7 and 4 m), so the fronts arrive as tongues, never one arc.
vec3 train(float s, float h, float t, float period, float travel, float seed, float u) {
	float ph = t / period + s / travel + 0.4 * noise1(s / 29.0 + seed * 7.0) + 0.22 * noise1(s / 7.5 + seed * 11.0);
	float q = fract(ph);
	float n = floor(ph);
	float set = 0.5 + 0.5 * sin(6.2832 * (t / set_seconds + s / 170.0 + seed));
	float reach = (0.8 + 1.4 * noise1(s / 21.0 + n * 1.7 + seed * 3.0)) * (0.5 + 0.7 * set * set);
	reach *= 0.7 + 0.6 * noise1(s / 61.0 + seed * 5.0);                       // some stretches run further
	reach += 1.0 * (noise1(s / 5.0 + n * 2.3 + seed * 13.0) - 0.5)            // tongues 4..8 m wide ...
		+ 0.3 * (noise1(s / 2.4 + n * 1.1 + seed * 17.0) - 0.5);              // ... scalloped
	reach = max(reach, 0.25);
	float k = 1.0 - q / 0.32;
	float run = q < 0.32 ? 1.0 - k * k : 1.0 - smoothstep(0.32, 0.85, q);
	float front = mix(back, reach, run);
	float peak = q < 0.32 ? front : reach;
	float fade = 1.0 - smoothstep(0.32, 0.8, q);
	float e = 0.24 * (noise2(vec2(s / 2.0, h / 0.9) + vec2(seed * 3.0 + t * 0.02, seed * 5.0)) - 0.5);   // the edge's scallops
	float d = front - h + e;                               // metres behind the wave's front
	float wash = smoothstep(-0.06, 0.12, d) * (1.0 - smoothstep(0.25, 1.1, d));
	// the drawn wave foam behind the front, cut by a wandering threshold: patches, thin in places,
	// fading to 0 alpha over a soft band at each edge rather than stopping on a hard line
	float cut = mix(0.18, 0.62, noise2(vec2(s / 2.4, h / 1.1) + vec2(seed * 9.0, t * 0.06)));
	float lace = smoothstep(cut - 0.12, cut + 0.12, texture(foam, vec2(u + seed, d / 3.2)).r);
	lace *= smoothstep(-0.3, 0.0, d) * (1.0 - smoothstep(3.2, 3.5, d));
	float f = max(wash * 0.85, lace * 0.95) * fade;
	float sheet = d >= 0.0 ? 0.32 * (1.0 - smoothstep(1.2, 3.0, d)) * max(fade, 0.3) : 0.0;
	sheet *= smoothstep(-1.2, 0.1, h);
	float dry = q < 0.32 ? 1.0 : 1.0 - smoothstep(0.32, 1.0, q);
	float wet = d < 0.0 ? 0.42 * dry * (1.0 - smoothstep(peak - 0.2, peak + 0.05, h - e)) : 0.0;
	wet *= smoothstep(-0.1, 0.2, h);
	return vec3(f, sheet, wet);
}

void vertex() {
	up = COLOR.g * 6.6 - 3.0;
	knoll = COLOR.r;
	along = COLOR.b;
}

void fragment() {
	float s = UV.x * 12.8;
	vec3 a = train(s, up, TIME, 9.5, 70.0, 0.0, UV.x);
	vec3 b = train(s, up, TIME + 3.7, 12.5, -110.0, 0.43, UV.x * 1.3);
	float f = max(a.x, b.x) * mix(0.55, 1.0, smoothstep(-2.0, -0.4, up));
	// a thin band of lace at the waterline, as Sunshine's shores: its width, place and presence wander along
	// the shore, so it is a broken line of patches, not an arc
	float w = 0.2 + 0.26 * noise1(s / 8.5 + TIME * 0.05) + 0.12 * (noise2(vec2(s / 1.4, up / 0.5) + TIME * 0.03) - 0.5);
	float c = -0.05 + 0.3 * (noise1(s / 5.5 + TIME * 0.07 + 4.0) - 0.5) + 0.05 * sin(TIME * 0.5 + s * 0.13);
	float band = 1.0 - smoothstep(w * 0.4, w, abs(up - c));
	band *= mix(0.45, 1.0, smoothstep(0.25, 0.75, noise1(s / 4.0 + TIME * 0.04 + 9.0)));
	float l = texture(edge_lace, vec2(UV.x * 4.0, up / 1.6 + TIME * 0.015)).r;
	f = max(f, band * smoothstep(0.25, 0.55, l) * 0.9);
	float sheet = max(a.y, b.y);
	float wet = max(a.z, b.z);
	float ends = smoothstep(0.0, 0.03, along) * (1.0 - smoothstep(0.97, 1.0, along));
	float al = 1.0 - (1.0 - wet) * (1.0 - sheet) * (1.0 - f);
	vec3 col = ((wet_color * wet * (1.0 - sheet) + sheet_color * sheet) * (1.0 - f) + foam_color * f) / max(al, 0.001);
	ALBEDO = col * display_gain;
	ALPHA = al * ends * knoll;
}
