shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, fog_disabled, shadows_disabled;
// Hell's heat shimmer: a clip-space quad re-reading the opaque frame, warped by world-pinned rising
// noise in proportion to how much air the view ray crosses: still up close, wobbling at range.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D noise_tex : filter_linear, repeat_enable;
uniform float strength = 1.0;
uniform float speed = 1.0;
// Peak UV offset at strength 1, as a fraction of screen height.
uniform float amplitude = 0.045;
// Metres one noise texture tile spans (about five waves), broad and fine layer.
uniform float tile_broad = 30.0;
uniform float tile_fine = 15.0;
// Rise in metres per second at speed 1, broad and fine layer.
uniform float rise_broad = 0.7;
uniform float rise_fine = 1.0;
// Air thinner than this barely moves; the warp is full by heat_full metres.
uniform float heat_near = 3.0;
uniform float heat_full = 30.0;
// The noise is read no farther than this, so far rock keeps broad waves instead of scrambling.
uniform float noise_distance = 25.0;
uniform float bottom_boost = 0.7;
uniform float look_down_boost = 0.8;
// The game camera's unzoomed vertical FOV: a scope magnifies the warp by its zoom over this.
uniform float base_fov = 100.0;
uniform vec3 warm : source_color = vec3(1.0, 0.55, 0.25);
uniform float warm_lift = 0.06;
// The screen copy reads back darker at the dark end (measured, see lava_haze.gdshader); lift it back.
uniform float dark_lift = 0.0157;
// Measured (PC, Compatibility): the copy reads back sRGB-encoded and this quad's ALBEDO is decoded,
// tonemapped and re-encoded, so the copy was tonemapped twice; heat_shimmer.gd mirrors the environment.
uniform int tonemap_mode = 0;
uniform float tonemap_white = 1.0;
uniform float tonemap_exposure = 1.0;

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

vec3 to_srgb(vec3 c) {
	return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(0.0031308, c));
}

// Undoes Reinhard x(W^2 + x) / (W^2 (1 + x)) and the exposure multiply before it, on linear light.
vec3 untonemap(vec3 y) {
	vec3 x = y;
	if (tonemap_mode == 1) {
		float w2 = tonemap_white * tonemap_white;
		vec3 b = w2 * (1.0 - y);
		x = 0.5 * (sqrt(b * b + 4.0 * w2 * y) - b);
	}
	return x / max(tonemap_exposure, 0.0001);
}

void vertex() {
	POSITION = vec4(VERTEX.xy, 0.0, 1.0);
}

// Two vertical planes of one rising field, x and z, so walls in any direction get it.
vec2 field(vec3 w, float tile, float rise, vec2 seed) {
	float y = (w.y - rise) / tile;
	vec2 px = vec2(w.x / tile, y) + seed;
	vec2 pz = vec2(w.z / tile, y) + seed.yx;
	vec2 a = vec2(texture(noise_tex, px).r, texture(noise_tex, px + vec2(0.37, 0.61)).r);
	vec2 b = vec2(texture(noise_tex, pz).r, texture(noise_tex, pz + vec2(0.53, 0.29)).r);
	return (a + b) - 1.0;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = 1.0 / VIEWPORT_SIZE;
	float aspect = VIEWPORT_SIZE.x / VIEWPORT_SIZE.y;
	float depth = texture(depth_tex, uv).r;
	// GL Compatibility depth runs 0..1 over NDC -1..1.
	vec3 ndc = vec3(uv, depth) * 2.0 - 1.0;
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	vec3 v = view.xyz / view.w;
	float dist = length(v);
	float heat = smoothstep(heat_near, heat_full, dist);
	vec3 centre = (INV_VIEW_MATRIX * vec4(v * min(1.0, noise_distance / max(dist, 0.001)), 1.0)).xyz;
	float t = TIME * speed;
	vec2 n = field(centre, tile_broad, t * rise_broad, vec2(0.0));
	n += field(centre, tile_fine, t * rise_fine, vec2(0.41, 0.17)) * 0.5;
	float low = 1.0 + bottom_boost * smoothstep(0.25, 1.0, 1.0 - uv.y);
	float down = clamp(INV_VIEW_MATRIX[2].y, 0.0, 1.0) * look_down_boost;
	float zoom = PROJECTION_MATRIX[1][1] * tan(radians(base_fov * 0.5));
	float amp = amplitude * strength * heat * low * (1.0 + down) * zoom;
	vec2 off = n * amp * vec2(0.7 / aspect, 1.2);
	vec3 c = texture(screen_tex, clamp(uv + off, px, vec2(1.0) - px)).rgb;
	c += vec3(dark_lift * clamp(1.45 - 6.37 * c, 0.0, 1.0));
	vec3 lit = untonemap(to_linear(clamp(c, 0.0, 1.0))) * (vec3(1.0) + warm * warm_lift * strength);
	ALBEDO = to_srgb(lit);
}
