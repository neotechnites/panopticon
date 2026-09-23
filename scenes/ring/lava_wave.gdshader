shader_type spatial;
render_mode cull_back;

// Map 1's lava river and falls (LavaRiver), gently waving: the floor swells, the falls ripple down.
// Offsets are a function of position only (never NORMAL), so flat-shaded faces stay welded.

uniform sampler2D albedo_texture : source_color, filter_nearest_mipmap_anisotropic, repeat_enable;
uniform sampler2D emission_texture : source_color, filter_nearest_mipmap_anisotropic, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform vec4 emission_color : source_color = vec4(1.0);
uniform float emission_energy = 1.0;
uniform float roughness = 1.0;
uniform float metallic = 0.0;
uniform vec3 uv1_scale = vec3(1.0);
uniform vec3 uv1_offset = vec3(0.0);

uniform vec2 ring_centre = vec2(0.0);   // world xz the falls' walls are round
uniform float river_y = 22.7;           // the river's surface, world y
uniform float shelf_y = 28.8;           // the flat lava over the outer fall
uniform float river_amp = 0.35;         // metres the river rises at a crest
uniform float fall_amp = 0.30;          // metres a fall bulges out at a crest
uniform float speed = 0.9;              // rad/s: one swell every ~7 s

float flat_w(float y) {
	float a = 1.0 - smoothstep(0.25, 0.9, abs(y - river_y));
	float b = 1.0 - smoothstep(0.25, 0.9, abs(y - shelf_y));
	return max(a, b);
}

void vertex() {
	UV = UV * uv1_scale.xy + uv1_offset.xy;
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 d = w.xz - ring_centre;
	float r = length(d);
	vec2 out_dir = r > 0.001 ? -d / r : vec2(0.0);   // off the wall, into the ring
	float t = TIME * speed;
	float fl = flat_w(w.y);
	// river: a slow swell rolling toward the pit, crossed by a second, slower one
	float sr = 0.6 * sin(0.9 * r + t) + 0.4 * sin(0.45 * w.x + 0.6 * w.z + 0.7 * t);
	// falls: rings running down the face, slightly wobbled across it
	float sf = 0.75 * sin(0.85 * w.y + 1.3 * t) + 0.25 * sin(0.5 * (w.x - w.z) + 0.6 * t);
	// only up and out of the surface, so its edges tuck into the banks, never gap
	float up = river_amp * fl * (0.5 + 0.5 * sr);
	float bulge = fall_amp * (1.0 - fl) * (0.5 + 0.5 * sf);
	w += vec3(out_dir.x * bulge, up, out_dir.y * bulge);
	VERTEX = (inverse(MODEL_MATRIX) * vec4(w, 1.0)).xyz;
}

void fragment() {
	// flat face normal of the bent surface, kept on the side the mesh faces
	vec3 n = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	NORMAL = dot(n, NORMAL) < 0.0 ? -n : n;
	ALBEDO = texture(albedo_texture, UV).rgb * albedo_color.rgb;
	EMISSION = texture(emission_texture, UV).rgb * emission_color.rgb * emission_energy;
	ROUGHNESS = roughness;
	METALLIC = metallic;
}
