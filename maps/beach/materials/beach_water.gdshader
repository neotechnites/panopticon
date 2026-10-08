// The beach's sea, built the way the GameCube drew water (Sunshine): the colour and see-through come baked in
// the vertices (COLOR, UV2.x alpha) from beach_build.py; one copy of the frame is sampled through a scrolling
// offset texture (refraction); two scrolling ripple layers; a sparkle layer offset by the ripples (EMBM-style
// glints); a foam texture in rings round rocks (UV2.y). No lighting maths. Mapping in docs/maps/beach.md.
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_always, fog_disabled;

#include "res://maps/beach/materials/beach_sea.gdshaderinc"

uniform sampler2D ripples : filter_linear_mipmap_anisotropic, repeat_enable;      // beach_water_normal: the offset texture
uniform sampler2D caustics : filter_linear_mipmap, repeat_enable;     // beach_water: the sparkle layer
uniform sampler2D foam_texture : filter_linear_mipmap, repeat_enable;
uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform vec3 foam_color : source_color = vec3(0.96, 0.99, 1.0);
uniform vec3 sun_color : source_color = vec3(1.0, 0.98, 0.9);
uniform vec3 under_color : source_color = vec3(0.02, 0.6, 0.62);    // the surface seen from below
uniform float refraction = 0.014;
uniform float sparkle = 1.6;
uniform float display_gain = 0.73;   // Ryan's HDR desktop shows SDR at 2x linear; unshaded output is undone by 2^(-1/2.2)
uniform float swell = 0.07;          // metres: the vertex swell (the GameCube moved water vertices too)

varying vec3 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float r = length(world.xz);
	float amp = swell * mix(1.0, 3.0, smoothstep(80.0, 220.0, r))
		* (1.0 - smoothstep(600.0, 1500.0, r));
	float y = sin(dot(world.xz, vec2(-0.57, 0.1)) - TIME * 2.1) + 0.5 * sin(dot(world.xz, vec2(-0.7, -0.53)) - TIME * 2.6);
	VERTEX.y += y * amp * step(r, 1500.0) * smoothstep(0.2, 0.5, UV2.x);
}

void fragment() {
	float t = TIME;
	float dist = length(world.xz - CAMERA_POSITION_WORLD.xz);
	float near = 1.0 - smoothstep(40.0, 260.0, dist);
	// two scrolling ripple layers: they make the offset (refraction, sparkle) and shade the colour a little
	vec3 r1 = texture(ripples, world.xz / 9.0 + t * vec2(0.021, 0.006)).xyz - 0.5;
	vec3 r2 = texture(ripples, world.xz / 5.3 - t * vec2(0.007, 0.017)).xyz - 0.5;
	vec2 off = (r1.xy + r2.xy);
	vec3 col = COLOR.rgb * (1.0 + 0.08 * (off.x + off.y) * near);
	// the sparkle layer, offset by the ripples (indirect texturing, as Sunshine's glints)
	float sp = texture(caustics, world.xz / 1.6 + off * 0.25 + t * vec2(0.03, -0.02)).r;
	float glow = smoothstep(0.988, 0.998, sp) * near * near;
	col += sun_color * glow * sparkle;
	// foam rings round rocks
	float lace = max(texture(foam_texture, world.xz / 3.1 + vec2(t * 0.02, 0.0)).r,
		texture(foam_texture, world.xz / 1.7 - vec2(0.0, t * 0.03)).r);
	float foam = UV2.y * smoothstep(0.2, 0.6, lace * (0.7 + 0.3 * sin(t * 1.3 + world.x * 0.7)));
	col = mix(col, foam_color, foam);
	float alpha = max(UV2.x, max(foam, glow));
	// the bed through the water: the frame copy, sampled through the ripple offset
	vec3 bed = texture(screen, SCREEN_UV + off * 2.0 * refraction * near * smoothstep(0.14, 0.5, UV2.x)).rgb;
	if (!FRONT_FACING) {
		ALBEDO = under_color * display_gain;
	} else {
		ALBEDO = mix(bed, col * display_gain, clamp(alpha, 0.0, 1.0));
	}
	ALPHA = 1.0;
}
