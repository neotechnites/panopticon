// The beach's sky at sunset: violet overhead, rose in the middle, orange and gold at the horizon round the sun.
// No clouds (Ryan's rule). The sun is beach_sun.gdshader's quad, so its disc stays round. Static.
shader_type sky;

uniform vec3 top_color : source_color = vec3(0.09, 0.07, 0.26);        // deep violet-blue overhead
uniform vec3 mid_color : source_color = vec3(0.31, 0.17, 0.32);        // rose-mauve partway down
uniform vec3 horizon_color : source_color = vec3(0.6, 0.32, 0.28);    // the horizon away from the sun
uniform vec3 sun_horizon_color : source_color = vec3(1.0, 0.56, 0.18); // orange-gold under and round the sun
uniform vec3 sun_direction = vec3(0.9587, 0.1219, 0.2568);            // toward the sun: the scene's Sun (+Z)
uniform float sun_spread = 0.55;      // how far round the horizon the sun's orange reaches (0..1 of the dot)
uniform float curve = 0.5;
uniform float display_gain = 1.0;     // tuned in plain SDR
uniform vec3 below_color : source_color = vec3(0.05, 0.1, 0.16);      // under the horizon: never seen but from the water

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 s = normalize(sun_direction);
	float el = asin(clamp(d.y, -1.0, 1.0));
	float t = pow(clamp(el / radians(80.0), 0.0, 1.0), curve);
	float toward = clamp(dot(normalize(vec3(d.x, 0.0, d.z) + 1e-5), normalize(vec3(s.x, 0.0, s.z))) * 0.5 + 0.5, 0.0, 1.0);
	float warm = pow(toward, 1.0 / max(sun_spread, 0.05) * 1.5);
	vec3 horizon = mix(horizon_color, sun_horizon_color, warm);
	vec3 col = t < 0.45 ? mix(horizon, mid_color, smoothstep(0.0, 0.45, t)) : mix(mid_color, top_color, smoothstep(0.45, 1.0, t));
	float a = acos(clamp(dot(d, s), -1.0, 1.0));
	col += sun_horizon_color * 0.35 * exp(-a / radians(9.0)) + vec3(1.0, 0.8, 0.45) * 0.2 * exp(-a / radians(3.0));
	vec3 below = mix(horizon, below_color, smoothstep(radians(2.0), radians(10.0), -el));
	COLOR = (d.y < 0.0 ? below : col) * display_gain;
}
