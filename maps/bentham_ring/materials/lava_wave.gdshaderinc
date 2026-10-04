// Every lava surface on map 1 (sea, river, falls, S3 cracks), waving. Offsets are a function of
// position only (world xyz, and UV2.x baked per position: 0 on every lava edge), so faces stay welded.

#ifndef WAVE_FILTER
#define WAVE_FILTER filter_nearest_mipmap_anisotropic
#endif
uniform sampler2D albedo_texture : source_color, WAVE_FILTER, repeat_enable;
uniform sampler2D emission_texture : source_color, WAVE_FILTER, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform vec4 emission_color : source_color = vec4(1.0);
uniform float emission_energy = 1.4;
uniform float roughness = 1.0;
uniform float metallic = 0.0;
uniform vec3 uv1_scale = vec3(1.0);
uniform vec3 uv1_offset = vec3(0.0);

uniform vec2 ring_centre = vec2(0.0);   // world xz the falls' walls are round
uniform float river_y = 22.7;           // the river, S2, S4 and the cracks: world y
uniform float shelf_y = 28.8;           // the flat lava over the outer fall
uniform float sea_y = -11.05;           // the pit sea (its crust swells 0.6 m either way)
uniform float river_amp = 1.75;         // metres crest to trough on flat lava
#ifndef WAVE_FALL_AMP
#define WAVE_FALL_AMP 1.5
#define WAVE_SPEED 0.55
#define WAVE_SCALE 1.0
#endif
#ifdef WAVE_SEE_THROUGH
// Consts, not uniforms: an imported material can never keep a stale copy of the portal's wave.
const float fall_amp = WAVE_FALL_AMP;
const float speed = WAVE_SPEED;
const float wave_scale = WAVE_SCALE;
#else
uniform float fall_amp = WAVE_FALL_AMP;  // metres a fall moves out and back
uniform float speed = WAVE_SPEED;        // rad/s: one heavy swell every ~11 s
uniform float wave_scale = WAVE_SCALE;   // the falls' spatial frequency: 1.0 is the lava's
#endif
#ifndef WAVE_SEE_THROUGH
uniform float flow_speed = 0.012;   // tiles per second each lava layer drifts
uniform float layer_scale = 0.61;   // the second layer's size against the first
uniform float downstream = 0.0;     // 1: river and falls, the tile runs in to the pit and down the falls
uniform float stream_speed = 0.06;  // tiles per second downstream (falls a third faster, stretched)
varying vec3 rest_w;
#endif

float flat_w(float y) {
	float a = 1.0 - smoothstep(0.25, 0.9, abs(y - river_y));
	float b = 1.0 - smoothstep(0.25, 0.9, abs(y - shelf_y));
	float c = 1.0 - smoothstep(0.9, 1.6, abs(y - sea_y));
	return max(max(a, b), c);
}

void vertex() {
	UV = UV * uv1_scale.xy + uv1_offset.xy;
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 d = w.xz - ring_centre;
	float r = length(d);
	vec2 out_dir = r > 0.001 ? -d / r : vec2(0.0);   // off the wall, into the ring
#ifdef WAVE_SEE_THROUGH
	out_dir = normalize((MODEL_MATRIX * vec4(0.0, 0.0, 1.0, 0.0)).xz);   // an upright disc: off its face
#endif
#ifndef WAVE_SEE_THROUGH
	rest_w = w;
#endif
	float t = TIME * speed;
	float fl = flat_w(w.y);
#ifdef WAVE_SEE_THROUGH
	fl = 0.0;                                        // the disc only moves off its face
#endif
	float edge = clamp(UV2.x, 0.0, 1.0);             // pinned on banks, walls, rocks and the tower foot
	// flat: a long swell rolling toward the pit, crossed by a second, slower one
	float sr = 0.6 * sin(0.4 * r + t) + 0.4 * sin(0.2 * w.x + 0.27 * w.z + 0.7 * t);
	// falls: rings running down the face, slightly wobbled across it
	float sf = 0.75 * sin(0.45 * wave_scale * w.y + 1.3 * t) + 0.25 * sin(0.3 * wave_scale * (w.x - w.z) + 0.6 * t);
	// centred on the rest surface; the pinned edges keep it tucked in, never gapped
	float up = 0.5 * river_amp * edge * fl * sr;
	float bulge = 0.5 * fall_amp * edge * (1.0 - fl) * sf;
	w += vec3(out_dir.x * bulge, up, out_dir.y * bulge);
	VERTEX = (inverse(MODEL_MATRIX) * vec4(w, 1.0)).xyz;
}

void fragment() {
	// flat face normal of the bent surface, kept on the side the mesh faces
	vec3 n = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	NORMAL = dot(n, NORMAL) < 0.0 ? -n : n;
#ifdef WAVE_SEE_THROUGH
	vec4 albedo_tex = texture(albedo_texture, UV);
	vec3 emission_tex = texture(emission_texture, UV).rgb;
	ALPHA = albedo_tex.a * albedo_color.a;
#else
	// two drifting layers of the one tile, turned and scaled apart so the repeat never lines up
	vec2 ua = UV + vec2(0.6, 0.8) * flow_speed * TIME;
	vec2 ub = mat2(vec2(0.799, 0.602), vec2(-0.602, 0.799)) * UV * layer_scale - vec2(0.8, -0.6) * flow_speed * 0.7 * TIME;
	vec2 ax = dFdx(ua), ay = dFdy(ua), bx = dFdx(ub), by = dFdy(ub);
	if (downstream > 0.5) {
		// round the ring (65 tiles a turn) by distance downstream: in to the pit on the flat, down the falls
		vec2 d = rest_w.xz - ring_centre;
		float r2 = max(dot(d, d), 0.01);
		float turn = atan(d.y, d.x) / TAU;
		vec2 dturn = vec2(d.x * dFdx(d.y) - d.y * dFdx(d.x), d.x * dFdy(d.y) - d.y * dFdy(d.x)) / (r2 * TAU);
		float s = (sqrt(r2) + 0.75 * rest_w.y) / 5.0;
		vec2 ds = vec2(dFdx(s), dFdy(s));
		ua = vec2(turn * 65.0, s + stream_speed * TIME);
		ub = vec2(turn * 40.0 + 0.37, s * layer_scale + stream_speed * 0.7 * TIME);
		ax = vec2(dturn.x * 65.0, ds.x); ay = vec2(dturn.y * 65.0, ds.y);
		bx = vec2(dturn.x * 40.0, ds.x * layer_scale); by = vec2(dturn.y * 40.0, ds.y * layer_scale);
	}
	vec3 albedo_mean = textureLod(albedo_texture, UV, 16.0).rgb;
	vec3 emission_mean = textureLod(emission_texture, UV, 16.0).rgb;
	vec4 albedo_tex = vec4(clamp(albedo_mean + 0.75 * (textureGrad(albedo_texture, ua, ax, ay).rgb + textureGrad(albedo_texture, ub, bx, by).rgb - 2.0 * albedo_mean), 0.0, 1.0), 1.0);
	vec3 emission_tex = clamp(emission_mean + 0.75 * (textureGrad(emission_texture, ua, ax, ay).rgb + textureGrad(emission_texture, ub, bx, by).rgb - 2.0 * emission_mean), 0.0, 1.0);
#endif
	ALBEDO = albedo_tex.rgb * albedo_color.rgb;
	EMISSION = emission_tex * emission_color.rgb * emission_energy;
	ROUGHNESS = roughness;
	METALLIC = metallic;
}
