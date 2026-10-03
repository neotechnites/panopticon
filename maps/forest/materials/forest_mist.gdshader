shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, fog_disabled;

// The pit's mist on ForestFog's discs (forest_pit_build.fog_mesh): COLOR.a is the proven column,
// this adds the colour, cloud drifting per layer, and a soft fade wherever a layer meets bank, trunk or thorn.

uniform sampler2D mist_noise : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D scene_depth : hint_depth_texture, filter_nearest;
// Grey-gold, a shade darker and greyer low, warmer where the mist thins up top.
uniform vec3 tint_low : source_color = vec3(0.17, 0.165, 0.15);
uniform vec3 tint_high : source_color = vec3(0.26, 0.245, 0.20);
// Hue shift toward the warm light; divided by its own luma so lightness stays put.
uniform vec3 hue : source_color = vec3(1.0, 0.88, 0.58);
// The stack: forest_pit_build.FOG_Z (bottom, top, pitch), so each disc knows its own layer.
uniform vec3 stack = vec3(-11.6, -5.75, 0.45);
// Metres one noise tile spans, the broad cloud and the fine one.
uniform float cloud_metres = 12.0;
uniform float fine_metres = 4.5;
// Each layer drifts its own way at a speed between these, in metres per second.
uniform vec2 drift_speed = vec2(0.12, 0.32);
// The least share of COLOR.a drawn: forest_pit_build.FOG_OVERRIDE. Never lower, or the floor proof lies.
uniform float noise_floor : hint_range(0.6, 1.0) = 0.6;
// How much the cloud lightens and darkens the tint.
uniform float shade = 0.35;
// Metres of depth over which a layer fades out in front of what is behind it: forest_pit_build.FOG_SOFT.
uniform float soft_metres = 1.0;
// Over this much depth the mist darkens by up to shadow where it meets bank, trunk or thorn, so it has no lit rim.
uniform float shadow_metres = 6.0;
uniform float shadow = 0.65;

varying vec3 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float layer = floor((world.y - stack.x) / stack.z + 0.5);
	float turn = layer * 2.39996;
	vec2 dir = vec2(cos(turn), sin(turn));
	float speed = mix(drift_speed.x, drift_speed.y, fract(layer * 0.618));
	vec2 broad = (world.xz + dir * speed * TIME) / cloud_metres + layer * vec2(0.31, 0.17);
	vec2 fine = (world.xz - dir.yx * speed * 0.6 * TIME) / fine_metres + layer * vec2(0.23, 0.41);
	float cloud = smoothstep(0.2, 0.8, texture(mist_noise, broad).r * 0.7 + texture(mist_noise, fine).r * 0.3);

	float depth = texture(scene_depth, SCREEN_UV).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(SCREEN_UV, depth) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
#endif
	vec4 behind = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	float gap = VERTEX.z - behind.z / behind.w;
	float soft = smoothstep(0.0, soft_metres, gap);

	float up = clamp((world.y - stack.x) / (stack.y - stack.x), 0.0, 1.0);
	ALBEDO = mix(tint_low, tint_high, up) * mix(1.0 - shade, 1.0 + shade, cloud)
			* mix(1.0 - shadow, 1.0, smoothstep(0.0, shadow_metres, gap))
			* hue / dot(hue, vec3(0.2126, 0.7152, 0.0722));
	ALPHA = COLOR.a * mix(noise_floor, 1.0, cloud) * soft;
}
