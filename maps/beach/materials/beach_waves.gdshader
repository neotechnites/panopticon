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

// One train at s metres along the shore, h metres up the sand: (foam, sheet, wet).
vec3 train(float s, float h, float t, float period, float travel, float seed, float u) {
	float ph = t / period + s / travel + 0.4 * noise1(s / 29.0 + seed * 7.0);
	float q = fract(ph);
	float n = floor(ph);
	float set = 0.5 + 0.5 * sin(6.2832 * (t / set_seconds + s / 170.0 + seed));
	float reach = (0.8 + 1.4 * noise1(s / 21.0 + n * 1.7 + seed * 3.0)) * (0.5 + 0.7 * set * set);
	float k = 1.0 - q / 0.32;
	float run = q < 0.32 ? 1.0 - k * k : 1.0 - smoothstep(0.32, 0.85, q);
	float front = mix(back, reach, run);
	float peak = q < 0.32 ? front : reach;
	float fade = 1.0 - smoothstep(0.32, 0.8, q);
	float d = front - h;                                   // metres behind the wave's front
	float wash = smoothstep(-0.06, 0.12, d) * (1.0 - smoothstep(0.25, 1.1, d));
	float lace = 0.0;   // the drawn wave foam behind the front
	if (d >= 0.0 && d <= 3.2) {
		lace = texture(foam, vec2(u + seed, d / 3.2)).r;
	}
	float f = max(wash * 0.85, lace * 0.95) * fade;
	float sheet = d >= 0.0 ? 0.32 * (1.0 - smoothstep(1.2, 3.0, d)) * max(fade, 0.3) : 0.0;
	sheet *= smoothstep(-1.2, 0.1, h);
	float dry = q < 0.32 ? 1.0 : 1.0 - smoothstep(0.32, 1.0, q);
	float wet = d < 0.0 ? 0.42 * dry * (1.0 - smoothstep(peak - 0.2, peak + 0.05, h)) : 0.0;
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
	// a thin band of lace always at the waterline, wandering a little, as Sunshine's shores
	float w = 0.28 + 0.12 * sin(s * 0.21 + TIME * 0.4) + 0.08 * sin(s * 0.57 - TIME * 0.3);
	float band = 1.0 - smoothstep(w * 0.5, w, abs(up + 0.05 + 0.06 * sin(TIME * 0.5 + s * 0.13)));
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
