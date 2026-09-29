shader_type spatial;
render_mode cull_back;

// Every lava surface on map 1 (sea, river, falls, S3 cracks), waving. Offsets are a function of
// position only (world xyz, and UV2.x baked per position: 0 on every lava edge), so faces stay welded.

uniform sampler2D albedo_texture : source_color, filter_nearest_mipmap_anisotropic, repeat_enable;
uniform sampler2D emission_texture : source_color, filter_nearest_mipmap_anisotropic, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform vec4 emission_color : source_color = vec4(1.0);
uniform float emission_energy = 1.4;
uniform float roughness = 1.0;
uniform float metallic = 0.0;
uniform vec3 uv1_scale = vec3(1.0);
uniform vec3 uv1_offset = vec3(0.0);
// The emission texture is the albedo itself: each texel glows by a smoothstep of its brightest
// sRGB channel, glow_floor of it on the crust (glow_lo) up to all of it on the orange (glow_hi).
uniform bool glow_from_albedo = false;
uniform float glow_lo = 0.4392;         // 112 / 255: the crust
uniform float glow_hi = 0.6902;         // 176 / 255: the orange
uniform float glow_floor = 0.25;        // Ryan, "a faint glow to the lava", even in shadow

uniform vec2 ring_centre = vec2(0.0);   // world xz the falls' walls are round
uniform float river_y = 22.7;           // the river, S2, S4 and the cracks: world y
uniform float shelf_y = 28.8;           // the flat lava over the outer fall
uniform float sea_y = -11.05;           // the pit sea (its crust swells 0.6 m either way)
uniform float river_amp = 1.75;         // metres crest to trough on flat lava
uniform float fall_amp = 1.5;           // metres a fall moves out and back
uniform float speed = 0.55;             // rad/s: one heavy swell every ~11 s

vec3 to_srgb(vec3 c) {
	return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
}

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

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
	float t = TIME * speed;
	float fl = flat_w(w.y);
	float edge = clamp(UV2.x, 0.0, 1.0);             // pinned on banks, walls, rocks and the tower foot
	// flat: a long swell rolling toward the pit, crossed by a second, slower one
	float sr = 0.6 * sin(0.4 * r + t) + 0.4 * sin(0.2 * w.x + 0.27 * w.z + 0.7 * t);
	// falls: rings running down the face, slightly wobbled across it
	float sf = 0.75 * sin(0.45 * w.y + 1.3 * t) + 0.25 * sin(0.3 * (w.x - w.z) + 0.6 * t);
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
	ALBEDO = texture(albedo_texture, UV).rgb * albedo_color.rgb;
	vec3 glow = texture(emission_texture, UV).rgb;
	if (glow_from_albedo) {
		vec3 s = to_srgb(glow);
		float t = smoothstep(glow_lo, glow_hi, max(s.r, max(s.g, s.b)));
		glow = to_linear(s * (glow_floor + (1.0 - glow_floor) * t));
	}
	EMISSION = glow * emission_color.rgb * emission_energy;
	ROUGHNESS = roughness;
	METALLIC = metallic;
}
