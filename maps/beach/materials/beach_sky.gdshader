// The beach's sky: a painted gradient, the drawn clouds (beach_clouds_albedo, black = clear), and the sun
// drawn where the scene's DirectionalLight comes from, so the shadows agree with it. Static.
shader_type sky;

uniform vec3 top_color : source_color = vec3(0.26, 0.63, 1.0);
uniform vec3 horizon_color : source_color = vec3(0.64, 0.8, 0.9);
uniform float curve = 0.5;
uniform sampler2D clouds : source_color, filter_linear, repeat_enable;
uniform float cloud_top_degrees = 90.0;
uniform float sun_degrees = 2.2;
uniform vec3 sun_color : source_color = vec3(1.0, 0.98, 0.9);
uniform float sun_energy = 1.6;
uniform float glow = 0.3;

void sky() {
	vec3 d = normalize(EYEDIR);
	float el = asin(clamp(d.y, -1.0, 1.0));
	vec3 col = mix(horizon_color, top_color, pow(clamp(el / radians(75.0), 0.0, 1.0), curve));
	if (LIGHT0_ENABLED) {
		float a = acos(clamp(dot(d, LIGHT0_DIRECTION), -1.0, 1.0));
		float r = radians(sun_degrees);
		col += sun_color * glow * exp(-a / radians(8.0));
		col = mix(col, sun_color * sun_energy, smoothstep(r * 1.1, r * 0.9, a));
	}
	vec2 uv = vec2(fract(atan(d.z, d.x) / TAU), 1.0 - el / radians(cloud_top_degrees));
	if (uv.y >= 0.0 && uv.y <= 1.0) {
		vec3 c = texture(clouds, uv).rgb;
		float a = clamp(max(c.r, max(c.g, c.b)) / 0.55, 0.0, 1.0);      // black is clear: un-premultiply the edge
		col = mix(col, c / max(a, 0.001), a);
	}
	COLOR = d.y < 0.0 ? horizon_color : col;
}
