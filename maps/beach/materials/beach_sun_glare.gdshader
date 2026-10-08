// Sunshine's blinding sun: a full-screen wash that rises as the view turns to the sun, star rays streaming from
// its screen position, both cut when the sun is hidden (depth sampled at the sun, as the GameCube read the EFB).
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_test_disabled, depth_draw_never, fog_disabled, shadows_disabled;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform vec3 sun_direction = vec3(0.7913, 0.5736, 0.212);   // toward the sun: the scene's Sun (+Z)
uniform vec3 glare_color : source_color = vec3(1.0, 1.0, 0.94);
uniform float glare_strength = 0.7;   // the wash dead-on (0..1): how blinded you are looking straight at it
uniform float glare_degrees = 22.0;   // off-angle where the wash has gone; it rises steeply only near dead-on
uniform float ray_strength = 0.45;    // the star rays streaming from the sun across the screen
uniform float display_gain = 1.0;    // the glare is meant to clip: no HDR compensation

varying vec4 sun_clip;
varying float facing;

void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, 0.0, 1.0);
	vec3 dir = normalize(sun_direction);
	sun_clip = PROJECTION_MATRIX * VIEW_MATRIX * vec4(CAMERA_POSITION_WORLD + dir * 1000.0, 1.0);
	vec3 forward = -normalize(INV_VIEW_MATRIX[2].xyz);
	facing = dot(forward, dir);
}

void fragment() {
	float near = smoothstep(cos(radians(glare_degrees)), 1.0, facing);
	if (near <= 0.0 || sun_clip.w <= 0.0) {
		discard;
	}
	vec2 sun_uv = sun_clip.xy / sun_clip.w * 0.5 + 0.5;
	// is the sun seen? five depth taps round its screen position: sky is the far plane
	float vis = 0.0;
	for (int i = 0; i < 5; i++) {
		vec2 o = (i == 0) ? vec2(0.0) : vec2(cos(float(i) * 1.5708), sin(float(i) * 1.5708)) * 0.012;
		vec2 p = sun_uv + o;
		float on = step(0.0, p.x) * step(p.x, 1.0) * step(0.0, p.y) * step(p.y, 1.0);
		float z = texture(depth_tex, p).r;
		float sky = max(step(z, 0.00001), step(0.99999, z));     // the sky sits at the far plane, either z convention
		vis += mix(1.0, sky, on);
	}
	vis /= 5.0;
	vec2 d = (SCREEN_UV - sun_uv) * vec2(VIEWPORT_SIZE.x / VIEWPORT_SIZE.y, 1.0);
	float r = length(d);
	float ang = atan(d.y, d.x);
	float rays = (pow(abs(cos(ang * 4.0)), 80.0) + 0.5 * pow(abs(cos(ang * 4.0 + 0.39)), 120.0)) * exp(-r * 2.2);
	float wash = glare_strength * pow(near, 2.2) * (0.75 + 0.25 * exp(-r * 3.0));
	ALBEDO = glare_color * display_gain;
	ALPHA = clamp((wash + rays * ray_strength * near) * vis, 0.0, 0.95);
}
