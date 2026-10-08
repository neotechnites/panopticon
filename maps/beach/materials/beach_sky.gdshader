// The beach's sky: a painted gradient and the drawn clouds (beach_clouds_albedo.png, RGBA). The sun is
// beach_sun.gdshader's quad, so its disc stays round. Static.
shader_type sky;

uniform vec3 top_color : source_color = vec3(0.26, 0.63, 1.0);
uniform vec3 horizon_color : source_color = vec3(0.64, 0.8, 0.9);
uniform float curve = 0.5;
uniform sampler2D clouds : source_color, filter_linear, repeat_enable;
uniform float cloud_top_degrees = 90.0;
uniform vec3 below_color : source_color = vec3(0.0, 0.3, 0.4);   // under the horizon: never seen but from the water

void sky() {
	vec3 d = normalize(EYEDIR);
	float el = asin(clamp(d.y, -1.0, 1.0));
	vec3 col = mix(horizon_color, top_color, pow(clamp(el / radians(75.0), 0.0, 1.0), curve));
	vec2 uv = vec2(fract(atan(d.z, d.x) / TAU), 1.0 - el / radians(cloud_top_degrees));
	if (uv.y >= 0.0 && uv.y <= 1.0) {
		vec4 c = texture(clouds, uv);
		col = mix(col, c.rgb, c.a);
	}
	vec3 below = mix(horizon_color, below_color, smoothstep(radians(2.0), radians(10.0), -el));
	COLOR = d.y < 0.0 ? below : col;
}
