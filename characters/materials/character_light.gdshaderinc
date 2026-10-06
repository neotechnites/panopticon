// A player lit as its map lights it: painted x shade turned from the map's light, x light turned to it, + a sun patch.
// Display-space maths: levels are on-screen multiples; GL Compatibility adds each shadowed sun's pass in sRGB.
render_mode cull_disabled, ambient_light_disabled, specular_disabled;

uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 shade_level = vec3(1.0);
uniform vec3 light_level = vec3(1.0);
uniform vec2 light_from = vec2(0.0, 1.0);
uniform vec2 arena_axis = vec2(0.0);
uniform float light_wrap = 0.5;
uniform float rim_level = 0.0;
uniform vec3 paint_level = vec3(1.0);
uniform float hue_keep = 0.0;
uniform float sun_lift = 0.0;
uniform float sun_facing_gain = 0.0;
uniform float sun_energy = 1.0;
uniform float sun_wrap = 0.5;
#include "res://characters/materials/character_dapple.gdshaderinc"

varying vec3 dapple_world;
// The sway, per vertex (TIME is not trusted inside light()), as the forest's surfaces do it.
varying vec2 dapple_drift_v;
varying vec2 dapple_fleck_v;

void vertex() {
	dapple_drift_v = dapple_drift(TIME);
	dapple_fleck_v = dapple_fleck_drift(TIME);
}

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

vec3 to_srgb(vec3 c) {
	c = max(c, vec3(0.0));
	return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
}

void fragment() {
	vec4 painted = albedo_color * texture(albedo_texture, UV);
	vec3 normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 place = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 inward = normalize(arena_axis - place.xz + vec2(1e-4));
	vec3 toward = normalize(vec3(inward.x * light_from.x, light_from.y, inward.y * light_from.x));
	float facing = clamp((dot(normal, toward) + light_wrap) / (1.0 + light_wrap), 0.0, 1.0);
	float edge = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);
	vec3 level = mix(shade_level, light_level, facing) + light_level * rim_level * edge;
	level = mix(level, vec3(dot(level, vec3(0.2126, 0.7152, 0.0722))), hue_keep);
	dapple_world = place;
	if (dapple_on) {
		float lit_share = 0.5 * (dapple_pattern(place, dapple_sun_a, dapple_drift_v, dapple_fleck_v) + dapple_pattern(place, dapple_sun_b, dapple_drift_v, dapple_fleck_v));
		level *= mix(dapple_shade, 1.0, lit_share);
	}
	ALBEDO = painted.rgb;
	EMISSION = to_linear(to_srgb(painted.rgb) * paint_level * level);
#ifdef FADE
	ALPHA = painted.a;
#endif
}

void light() {
	if (LIGHT_IS_DIRECTIONAL && sun_lift > 0.0) {
		vec3 painted = to_srgb(ALBEDO);
		float share = dot(LIGHT_COLOR / PI, vec3(0.2126, 0.7152, 0.0722)) / sun_energy;
		float facing = min(sun_facing_gain * max(dot(NORMAL, LIGHT), sun_wrap), 1.0);
		vec3 added = painted * paint_level * light_level * sun_lift * min(share, 1.0) * facing * ATTENUATION;
		if (dapple_on) {
			vec3 l = (INV_VIEW_MATRIX * vec4(LIGHT, 0.0)).xyz;
			added *= dapple_light * dapple_pattern(dapple_world, l, dapple_drift_v, dapple_fleck_v);
		}
		DIFFUSE_LIGHT += to_linear(added) / max(ALBEDO, vec3(1e-4));
	}
}
