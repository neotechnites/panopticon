// A player lit by the map's suns only: painted x floor in shade, + painted x lift in full sun; no ambient, no fog.
// Display-space maths: GL Compatibility takes ALBEDO/EMISSION as sRGB and adds each shadowed sun's pass in sRGB.
render_mode cull_disabled, ambient_light_disabled, specular_disabled, fog_disabled;

uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, hint_default_white, filter_nearest_mipmap_anisotropic, repeat_enable;
uniform float light_floor = 1.0;
uniform float light_lift = 0.0;
uniform float light_facing_gain = 0.0;
uniform float light_sun_energy = 1.0;
uniform float light_wrap = 0.5;

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

vec3 to_srgb(vec3 c) {
	c = max(c, vec3(0.0));
	return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
}

void fragment() {
	vec4 painted = albedo_color * texture(albedo_texture, UV);
	ALBEDO = painted.rgb;
	EMISSION = painted.rgb * light_floor;
#ifdef FADE
	ALPHA = painted.a;
#endif
}

void light() {
	if (LIGHT_IS_DIRECTIONAL && light_lift > 0.0) {
		vec3 painted = to_srgb(ALBEDO);
		float share = dot(LIGHT_COLOR / PI, vec3(0.2126, 0.7152, 0.0722)) / light_sun_energy;
		float facing = min(light_facing_gain * max(dot(NORMAL, LIGHT), light_wrap), 1.0);
		vec3 added = painted * light_lift * min(share, 1.0) * facing * ATTENUATION;
		DIFFUSE_LIGHT += to_linear(added) / max(ALBEDO, vec3(1e-4));
	}
}
