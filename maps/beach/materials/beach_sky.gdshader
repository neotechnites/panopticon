// The beach's sky: a painted gradient, no clouds (Ryan: "no clouds in the sky, just sky"). The sun is
// beach_sun.gdshader's quad, so its disc stays round. Static.
shader_type sky;

uniform vec3 top_color : source_color = vec3(0.02, 0.28, 0.95);      // saturated blue, after Sunshine and Emerald Coast
uniform vec3 horizon_color : source_color = vec3(0.55, 0.78, 0.98);
uniform float curve = 0.7;
// Ryan's Windows HDR shows SDR at 2x linear (scripts/fx/mac_lift.gdshader): colours here are what he sees.
uniform float display_gain = 0.73;   // Ryan's HDR desktop shows SDR at 2x linear; unshaded output is undone by 2^(-1/2.2)
uniform vec3 below_color : source_color = vec3(0.0, 0.3, 0.4);   // under the horizon: never seen but from the water

void sky() {
	vec3 d = normalize(EYEDIR);
	float el = asin(clamp(d.y, -1.0, 1.0));
	vec3 col = mix(horizon_color, top_color, pow(clamp(el / radians(75.0), 0.0, 1.0), curve));
	vec3 below = mix(horizon_color, below_color, smoothstep(radians(2.0), radians(10.0), -el));
	COLOR = (d.y < 0.0 ? below : col) * display_gain;
}
