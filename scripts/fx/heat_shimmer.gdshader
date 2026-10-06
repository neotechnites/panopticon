shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, fog_disabled, shadows_disabled;
// Hell's heat shimmer: a clip-space quad re-reading the opaque frame through two rising noise layers.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform sampler2D noise_tex : filter_linear, repeat_enable;
uniform float strength = 1.0;
uniform float speed = 1.0;
// Peak UV offset at strength 1, as a fraction of screen height.
uniform float amplitude = 0.009;
uniform float bottom_boost = 0.7;
uniform float look_down_boost = 0.8;
uniform vec3 warm : source_color = vec3(1.0, 0.55, 0.25);
uniform float warm_lift = 0.06;
// The screen copy reads back darker at the dark end (measured, see lava_haze.gdshader); lift it back.
uniform float dark_lift = 0.0157;

void vertex() {
	POSITION = vec4(VERTEX.xy, 0.0, 1.0);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = 1.0 / VIEWPORT_SIZE;
	float aspect = VIEWPORT_SIZE.x / VIEWPORT_SIZE.y;
	vec2 p = vec2(uv.x * aspect, 1.0 - uv.y);
	float t = TIME * speed;
	// p.y runs up the screen, so subtracting t makes the pattern rise.
	vec2 a = p * vec2(1.6, 1.1) - vec2(0.0, t * 0.22);
	vec2 b = p * vec2(3.8, 2.6) - vec2(-t * 0.03, t * 0.55);
	vec2 n = vec2(texture(noise_tex, a).r, texture(noise_tex, a + vec2(0.37, 0.61)).r) - 0.5;
	n += (vec2(texture(noise_tex, b).r, texture(noise_tex, b + vec2(0.53, 0.29)).r) - 0.5) * 0.7;
	float low = 1.0 + bottom_boost * smoothstep(0.25, 1.0, 1.0 - p.y);
	float down = clamp(INV_VIEW_MATRIX[2].y, 0.0, 1.0) * look_down_boost;
	float amp = amplitude * strength * low * (1.0 + down);
	vec2 off = n * amp * vec2(0.7 / aspect, 1.2);
	vec3 c = texture(screen_tex, clamp(uv + off, px, vec2(1.0) - px)).rgb;
	c += vec3(dark_lift * clamp(1.45 - 6.37 * c, 0.0, 1.0));
	ALBEDO = c * (vec3(1.0) + warm * warm_lift * strength);
}
