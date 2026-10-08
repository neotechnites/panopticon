// The shore's waves, the GameCube way (Sunshine, Emerald Coast): each strip of beach_waves.glb is one wave
// on its own clock. Its drawn foam (beach_wave_albedo) slides up the sand on a thin sheet of water, thins
// and slides back, leaving the sand it reached wet until it dries. Reach, speed and angle vary per strip
// and per wave; waves come in sets that roll along the shore, then a lull.
// COLOR is data (beach_build.py build_waves): r = phase, g = (metres up the sand + 1.5) / 5.5, b = along 0..1.
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;

uniform sampler2D foam : filter_linear_mipmap, repeat_enable;
uniform vec3 foam_color : source_color = vec3(0.97, 0.99, 1.0);
uniform vec3 sheet_color : source_color = vec3(0.56, 0.9, 0.86);
uniform vec3 wet_color : source_color = vec3(0.6, 0.55, 0.44);
uniform float set_seconds = 38.0;      // a set of bigger waves, then a lull
uniform float back = -1.3;             // metres out in the water a wave starts from and drains back to
uniform float display_gain = 0.73;     // Ryan's HDR desktop shows SDR at 2x linear (beach_water.gdshader)

varying float phase;
varying float up;
varying float along;

float hash(float x) {
	return fract(sin(x * 91.7 + 13.1) * 43758.5);
}

void vertex() {
	phase = COLOR.r;
	up = COLOR.g * 5.5 - 1.5;
	along = COLOR.b;
}

void fragment() {
	float period = 6.0 + 6.0 * hash(phase * 3.1);
	float clock = TIME / period + phase;
	float q = fract(clock);
	float n = floor(clock);
	// this wave's reach up the sand: the strip's own, the set's swell, and a little luck
	float set = 0.5 + 0.5 * sin(6.2832 * ((n - phase) * period / set_seconds + phase * 0.35));
	float reach = (0.7 + 1.9 * hash(phase * 7.7)) * (0.45 + 0.8 * set * set) * (0.8 + 0.4 * hash(n + phase * 97.0));
	float slant = (hash(phase * 5.3 + n) * 2.0 - 1.0) * 0.9 * reach * (along - 0.5);
	float run = q < 0.3 ? 1.0 - (1.0 - q / 0.3) * (1.0 - q / 0.3) : 1.0 - smoothstep(0.3, 0.8, q);
	float front = mix(back, reach, run) + slant;
	float peak = (q < 0.3 ? front : reach + slant);
	float fade = 1.0 - smoothstep(0.3, 0.75, q);

	// the foam: the drawn wave, its leading edge at the front, thinning as it drains
	float tv = (front - up) / 3.2;
	float f = 0.0;
	if (tv >= 0.0 && tv <= 1.0) {
		f = texture(foam, vec2(UV.x + 0.02 * sin(TIME * 0.6 + phase * 6.3), tv)).r;
	}
	f = smoothstep(0.55 * (1.0 - fade), 0.55 * (1.0 - fade) + 0.2, f) * fade;
	// the sheet of water behind the foam, and the wet sand above it where this wave has been
	float sheet = (tv >= 0.0 ? 0.32 * (1.0 - smoothstep(0.4, 1.0, tv)) : 0.0) * max(fade, 0.35) * smoothstep(-0.6, 0.2, up);
	float dry = q < 0.3 ? 1.0 : 1.0 - smoothstep(0.3, 1.0, q);
	float wet = (tv < 0.0 ? 0.42 : 0.0) * dry * (1.0 - smoothstep(peak - 0.15, peak + 0.05, up)) * smoothstep(-0.1, 0.15, up);
	float ends = smoothstep(0.0, 0.18, along) * (1.0 - smoothstep(0.82, 1.0, along));
	float a = 1.0 - (1.0 - wet) * (1.0 - sheet) * (1.0 - f);
	vec3 col = ((wet_color * wet * (1.0 - sheet) + sheet_color * sheet) * (1.0 - f) + foam_color * f) / max(a, 0.001);
	ALBEDO = col * display_gain;
	ALPHA = a * ends;
}
