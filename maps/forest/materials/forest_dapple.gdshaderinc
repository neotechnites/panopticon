// The forest's lit surfaces: their own albedo, plus the overhead light broken into leaf-shaped pools by a top-down
// world-XZ mask cut from the leaf sheet (forest_sun_albedo), so every metre of the ring is dappled the same way.

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform bool use_vertex_color = false;
uniform bool vertex_color_srgb = false;
uniform float roughness = 0.95;
uniform vec3 uv1_scale = vec3(1.0);
uniform vec3 uv1_offset = vec3(0.0);
// The leaf sheet read raw (luminance only): its bright leaves become the hot spots.
uniform sampler2D dapple_texture : hint_default_white, filter_linear_mipmap, repeat_enable;
// Metres one tile spans: the broad pattern, and a finer one turned across it.
uniform float dapple_metres = 4.5;
uniform float fine_metres = 3.1;
// Leaf-sheet luminance mapped to shadow (lo) .. full pool (hi); between is the soft edge.
uniform float dapple_lo = 0.49;
uniform float dapple_hi = 0.58;
// Least mip read, so pool edges stay soft close up.
uniform float soft_lod = 3.0;
// How much the fine layer breaks the broad pools; 0 is the broad layer alone.
uniform float fine_share = 0.25;
// Metres per second the pattern drifts; 0 holds it still.
uniform float drift = 0.02;
// Share of the sky's light a dappled surface keeps, so the pools add light where the shadows take it away.
uniform float sky_share = 0.6;
// Share of the overhead light this surface takes: 1 dappled, 0 for leaves, which keep the sky's light alone.
uniform float overhead = 1.0;
// Overhead light reaching walls: 0 lights only up-facing ground, 1 lights walls half as much as floor.
uniform float wrap = 0.35;

varying vec3 world_pos;
varying float dapple;

void vertex() {
	UV = UV * uv1_scale.xy + uv1_offset.xy;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float leaf_layer(vec2 uv) {
	vec2 size = vec2(textureSize(dapple_texture, 0));
	vec2 texel = fwidth(uv) * size;
	float lod = max(soft_lod, log2(max(max(texel.x, texel.y), 1e-4)));
	float lum = dot(textureLod(dapple_texture, uv, lod).rgb, vec3(0.299, 0.587, 0.114));
	return smoothstep(dapple_lo, dapple_hi, lum);
}

void fragment() {
	vec4 albedo = texture(albedo_texture, UV) * albedo_color;
	if (use_vertex_color) {
		vec3 c = vertex_color_srgb ? pow(COLOR.rgb, vec3(2.2)) : COLOR.rgb;
		albedo.rgb *= c;
	}
	ALBEDO = albedo.rgb;
	ROUGHNESS = roughness;
	METALLIC = 0.0;
	AO = mix(1.0, sky_share, overhead);
	AO_LIGHT_AFFECT = 0.0;
	vec2 xz = world_pos.xz + vec2(TIME * drift, TIME * drift * 0.6);
	const mat2 turn = mat2(vec2(0.799, 0.602), vec2(-0.602, 0.799));
	float broad = leaf_layer(xz / dapple_metres);
	float fine = leaf_layer(turn * xz / fine_metres + vec2(0.37, 0.71));
	dapple = broad * mix(1.0, fine, fine_share);
}

void light() {
	if (LIGHT_IS_DIRECTIONAL) {
		float nl = clamp((dot(NORMAL, LIGHT) + wrap) / (1.0 + wrap), 0.0, 1.0);
		DIFFUSE_LIGHT += nl * dapple * overhead * ATTENUATION * LIGHT_COLOR / PI;
	} else {
		DIFFUSE_LIGHT += clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * ATTENUATION * LIGHT_COLOR / PI;
	}
}
