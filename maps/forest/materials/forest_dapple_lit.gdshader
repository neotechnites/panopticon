// A forest surface whose sun light passes through a soft leaf dapple (forest_dapple.png), projected
// along each sun to the ground plane; ambient and every other light are untouched.
shader_type spatial;

uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_vertex_color = true;
uniform float roughness = 0.95;
// 1 = the tile x tint as is; lower greys the surface's own colour toward its brightness.
uniform float saturation = 1.0;
uniform sampler2D dapple : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float dapple_metres = 27.0;
// 0 leaves the sun whole, 1 is the full dapple.
uniform float dapple_strength = 0.85;
// Lifts the leaf shade: the share of the sun that still reaches shaded spots (0 = shade is ambient only).
// Set per material, e.g. only on the grass, to show the tile's texture in the shade.
uniform float shade_lift = 0.0;
// Brightness of the sun that gets through the dapple (1 = the suns' full light). Only dappled surfaces.
uniform float dapple_light = 0.8;
// The fine second layer (the texture's G): small flecks of light in shade and of shade in light.
uniform float fleck_strength = 0.4;
// Pulls the flecks dark: total sun 13%, a little under the big pattern alone (14%).
uniform float fleck_bias = 0.22;
// Leaves in a light wind: the pattern drifts back and forth (as forest_crown_shadow.gdshader's holes did).
uniform float sway = 0.6;
uniform float sway_speed = 1.0;

varying vec3 world;
// The sway, worked out per vertex (TIME is not trusted inside light() on every renderer).
varying vec2 drift;
// The fleck layer sways on its own slower, crossing rhythm, so the two layers slide over each other.
varying vec2 fleck_drift;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	drift = sway * vec2(sin(TIME * sway_speed), 0.6 * sin(TIME * sway_speed * 0.73 + 1.3));
	fleck_drift = sway * vec2(0.7 * sin(TIME * sway_speed * 1.37 + 2.1), sin(TIME * sway_speed * 0.59 + 0.4));
}

// Soft fake AO where trunks meet the ground, from forest_contact.png (tools/textures/forest_contact.py).
// 0 = off. Darkens within contact_radius m of a trunk and up to contact_height m above its ground.
uniform float contact_strength = 0.0;
uniform float contact_radius = 1.5;
uniform float contact_height = 1.0;
uniform sampler2D contact_mask : hint_default_white, filter_linear, repeat_disable;

void fragment() {
	vec4 tex = texture(albedo_texture, UV);
	vec3 base = albedo_color.rgb * tex.rgb;
	if (use_vertex_color) {
		base *= COLOR.rgb;
	}
	base = mix(vec3(dot(base, vec3(0.2126, 0.7152, 0.0722))), base, saturation);
	if (contact_strength > 0.0) {
		vec2 m = texture(contact_mask, world.xz / 120.0 + 0.5).rg;
		float h = world.y - (13.0 + 20.0 * m.g);
		float ring = 1.0 - smoothstep(0.0, contact_radius, m.r * 4.0);
		float rise = 1.0 - smoothstep(0.0, contact_height, h);
		base *= 1.0 - contact_strength * ring * rise * step(-1.5, h);
	}
	ALBEDO = base;
	ROUGHNESS = roughness;
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
		sun = max(sun, shade_lift * dapple_light);
	}
	DIFFUSE_LIGHT += clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * ATTENUATION * LIGHT_COLOR / PI * sun;
}
