shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix;

// Heat shimmer over the lava cracks.
//
// Ryan's brief: "cracks that have like, wavy hotness coming out of them. the
// type of waviness you see above a road on a hot day. not steam"
//
// Refraction only: the screen behind is resampled through a rising noise
// field. Nothing is tinted or added, so the quad has no colour of its own.

// What is behind the quad.
uniform sampler2D screen : hint_screen_texture, filter_linear;
// Peak screen-space displacement, in UV.
uniform float strength : hint_range(0.0, 0.05, 0.0005) = 0.006;
// How fast the shimmer climbs, in metres per second.
uniform float rise_metres_per_second : hint_range(0.0, 2.0, 0.05) = 0.4;
// Quad height in metres, so the rise reads at any size.
uniform float haze_height_metres : hint_range(0.5, 8.0, 0.1) = 2.0;
// Noise cells across the quad: high is fine ripple, low is slow roll.
uniform float wave_scale : hint_range(1.0, 24.0, 0.5) = 7.0;
// Width of the fade at both sides, in UV; the top fades over the whole height.
uniform float edge_fade : hint_range(0.01, 0.5, 0.01) = 0.28;
// How much the dark end of the screen copy is lifted back, in colour units
// (4/255 as measured; 0 on a renderer whose copy comes back exact).
uniform float dark_lift : hint_range(0.0, 0.05, 0.001) = 0.0157;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

// Value noise, smoothstep-interpolated across the cell.
float value_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = smoothstep(vec2(0.0), vec2(1.0), fract(p));
	float a = hash(cell);
	float b = hash(cell + vec2(1.0, 0.0));
	float c = hash(cell + vec2(0.0, 1.0));
	float d = hash(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Two octaves, second at twice the frequency and half the weight.
float haze_noise(vec2 p) {
	return (value_noise(p) + value_noise(p * 2.0) * 0.5) / 1.5;
}

void fragment() {
	// Subtracting from v walks the field downwards, so the pattern rises.
	float rise = TIME * rise_metres_per_second / haze_height_metres;
	vec2 p = vec2(UV.x, UV.y - rise) * wave_scale;

	// Decorrelated samples: one per axis, offset far enough not to rhyme.
	vec2 offset = vec2(
		haze_noise(p),
		haze_noise(p + vec2(37.2, 11.7))
	);
	offset = (offset - vec2(0.5)) * 2.0 * strength;

	// Nothing at the top edge, nothing at either side.
	float mask = smoothstep(0.0, 1.0, UV.y);
	mask *= smoothstep(0.0, edge_fade, UV.x);
	mask *= smoothstep(0.0, edge_fade, 1.0 - UV.x);
	offset *= mask;

	vec3 behind = texture(screen, SCREEN_UV + offset).rgb;
	// The screen copy comes back a shade darker at the dark end than the
	// pixels it was copied from (measured on the PC, RX 6600 XT under GL
	// Compatibility: 10/255 reads back as 4, 20 as 16, 30 as 28, 40 as 39,
	// 60 and up exact), so a quad that only re-sampled the screen drew a
	// faint darker pane with hard edges. This lifts the dark end by the
	// measured amount, and the alpha fade below hides whatever is left.
	behind += vec3(dark_lift * clamp(1.45 - 6.37 * behind, 0.0, 1.0));
	ALBEDO = behind;
	// The quad is only there where it shimmers: fully drawn at its base
	// and middle, fading to nothing at the top and both sides, so it has no
	// edge of its own.
	ALPHA = mask;
}
