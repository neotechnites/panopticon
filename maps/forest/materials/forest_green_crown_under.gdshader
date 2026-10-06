// forest_crown_under.gdshader for forest_green.tscn: the backlit leaf in LeafGreen's colour, its lit share
// lit exactly as the walls (forest_dapple_lit.gdshader's sun through the dapple), so the two meet as one leaf.
shader_type spatial;
render_mode cull_back;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float glow = 0.3;
// LeafGreen's albedo_color, so the underside is the walls' leaf where it lands on them.
uniform vec4 tint : source_color = vec4(1.0);
// The glow rolls in over this many metres of radius in from the walls' head (seam_r), lit leaf giving way.
uniform float seam_r = 47.6;
uniform float glow_ramp = 6.0;
// The canopy's brightness away from the walls; eases to 1 at the seam over the same ramp, so no step.
uniform float canopy_brightness = 0.7;
uniform sampler2D dapple : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float dapple_metres = 27.0;
uniform float dapple_strength = 1.0;
uniform float dapple_light = 0.8;
uniform float fleck_strength = 0.245;
uniform float fleck_bias = 0.22;
uniform float sway = 0.35;
uniform float sway_speed = 1.0;

varying vec3 world;
varying vec2 drift;
varying vec2 fleck_drift;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	drift = sway * vec2(sin(TIME * sway_speed), 0.6 * sin(TIME * sway_speed * 0.73 + 1.3));
	fleck_drift = sway * vec2(0.7 * sin(TIME * sway_speed * 1.37 + 2.1), sin(TIME * sway_speed * 0.59 + 0.4));
}

void fragment() {
	vec3 tile = texture(albedo_texture, UV).rgb * tint.rgb;
	float lit = clamp(UV2.x, 0.0, 1.0);
	float g = smoothstep(seam_r, seam_r - glow_ramp, length(world.xz));
	float leaf = max(lit, 1.0 - g);
	tile *= mix(1.0, canopy_brightness, g);
	ALBEDO = tile * COLOR.rgb * leaf;
	// The glow's strength from COLOR_0 but the walls' hue, not its warm cast.
	EMISSION = tile * dot(COLOR.rgb, vec3(0.299, 0.587, 0.114)) * (1.0 - leaf) * glow;
	ROUGHNESS = 0.95;
}

// Height (world y) where the dapple starts fading to its mean, gone dapple_top_fade m higher; high = never.
uniform float dapple_top = 10000.0;
uniform float dapple_top_fade = 3.0;
uniform float dapple_mean = 0.14;

void light() {
	float sun = 1.0;
	if (LIGHT_IS_DIRECTIONAL) {
		vec3 l = (INV_VIEW_MATRIX * vec4(LIGHT, 0.0)).xyz;
		vec2 p = world.xz - l.xz / max(l.y, 0.2) * world.y;
		vec2 d = vec2(texture(dapple, (p + drift) / dapple_metres).r, texture(dapple, (p + fleck_drift) / dapple_metres).g);
		sun = dapple_light * mix(1.0, clamp(d.r + (d.g - 0.5 - fleck_bias) * 2.0 * fleck_strength, 0.0, 1.0), dapple_strength);
		sun = mix(sun, dapple_light * dapple_mean, smoothstep(dapple_top, dapple_top + dapple_top_fade, world.y));
	}
	DIFFUSE_LIGHT += clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * ATTENUATION * LIGHT_COLOR / PI * sun;
}
