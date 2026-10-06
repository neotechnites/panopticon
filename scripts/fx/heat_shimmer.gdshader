shader_type canvas_item;
render_mode unshaded;
// Hell's heat shimmer: the finished frame re-read through two rising, tiling noise layers.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform sampler2D noise_tex : filter_linear, repeat_enable;
uniform float strength = 1.0;
uniform float speed = 1.0;
// Peak UV offset at strength 1, as a fraction of screen height.
uniform float amplitude = 0.009;
uniform float bottom_boost = 0.7;
// 0..1 from HeatShimmer: how far the camera is pitched down at the lava.
uniform float look_down = 0.0;
uniform vec3 warm : source_color = vec3(1.0, 0.55, 0.25);
uniform float warm_lift = 0.06;

void fragment() {
	vec2 uv = SCREEN_UV;
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec2 p = vec2(uv.x * aspect, uv.y);
	float t = TIME * speed;
	// SCREEN_UV y runs down, so adding t to the sample makes the pattern rise.
	vec2 a = p * vec2(1.6, 1.1) + vec2(0.0, t * 0.22);
	vec2 b = p * vec2(3.8, 2.6) + vec2(t * 0.03, t * 0.55);
	vec2 n = vec2(texture(noise_tex, a).r, texture(noise_tex, a + vec2(0.37, 0.61)).r) - 0.5;
	n += (vec2(texture(noise_tex, b).r, texture(noise_tex, b + vec2(0.53, 0.29)).r) - 0.5) * 0.7;
	float low = 1.0 + bottom_boost * smoothstep(0.25, 1.0, uv.y);
	float amp = amplitude * strength * low * (1.0 + look_down);
	vec2 off = n * amp * vec2(0.7 / aspect, 1.2);
	vec3 c = texture(screen_tex, clamp(uv + off, vec2(0.0), vec2(1.0))).rgb;
	COLOR = vec4(c * (vec3(1.0) + warm * warm_lift * strength), 1.0);
}
