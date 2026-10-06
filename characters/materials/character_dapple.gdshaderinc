// The forest's leaf dapple (forest_dapple_lit.gdshader's maths) on a player: off unless the map's fit sets it.
// Values come from CharacterLight, read off the forest's own shader so the two stay one.
uniform bool dapple_on = false;
uniform sampler2D dapple : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float dapple_metres = 27.0;
uniform float dapple_strength = 1.0;
uniform float dapple_light = 0.7;
uniform float fleck_strength = 0.4;
uniform float fleck_bias = 0.22;
uniform float sway = 0.6;
uniform float sway_speed = 1.0;
uniform float dapple_top = 10000.0;
uniform float dapple_top_fade = 3.0;
uniform float dapple_mean = 0.14;
// The body's own level in full leaf shade (1 = untouched): its ambient stays, so it never goes black.
uniform float dapple_shade = 1.0;
// The suns' directions (toward them, world), for the body's level away from any one sun's pass.
uniform vec3 dapple_sun_a = vec3(0.0, 1.0, 0.0);
uniform vec3 dapple_sun_b = vec3(0.0, 1.0, 0.0);

vec2 dapple_drift(float t) {
	return sway * vec2(sin(t * sway_speed), 0.6 * sin(t * sway_speed * 0.73 + 1.3));
}

vec2 dapple_fleck_drift(float t) {
	return sway * vec2(0.7 * sin(t * sway_speed * 1.37 + 2.1), sin(t * sway_speed * 0.59 + 0.4));
}

// The pattern (0 shade .. 1 patch) at [param w] with the sun toward [param l], as the ground has it.
float dapple_pattern(vec3 w, vec3 l, vec2 drift, vec2 fleck_drift) {
	vec2 p = w.xz - l.xz / max(l.y, 0.2) * w.y;
	vec2 d = vec2(texture(dapple, (p + drift) / dapple_metres).r, texture(dapple, (p + fleck_drift) / dapple_metres).g);
	float s = mix(1.0, clamp(d.r + (d.g - 0.5 - fleck_bias) * 2.0 * fleck_strength, 0.0, 1.0), dapple_strength);
	return mix(s, dapple_mean, smoothstep(dapple_top, dapple_top + dapple_top_fade, w.y));
}
