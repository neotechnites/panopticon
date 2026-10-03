// The forest's lit surfaces: their own albedo, plus the overhead light (shadowed by tower and trees) broken into soft
// leaf pools on up-facing ground by a top-down world-XZ mask cut from the leaf sheet (forest_sun_albedo).

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform bool use_vertex_color = false;
uniform bool vertex_color_srgb = false;
uniform float roughness = 0.95;
uniform vec3 uv1_scale = vec3(1.0);
uniform vec3 uv1_offset = vec3(0.0);
// The leaf sheet read raw (luminance only): its bright leaves become the hot spots.
uniform sampler2D dapple_texture : hint_default_white, filter_linear_mipmap, repeat_enable;
// Metres one tile spans: the broad pattern, a finer one turned across it, and a slow swell that hides the tiling.
uniform float dapple_metres = 4.5;
uniform float fine_metres = 3.1;
uniform float swell_metres = 12.0;
// Leaf-sheet luminance mapped to shadow (lo) .. full pool (hi); between is the soft edge.
uniform float dapple_lo = 0.50;
uniform float dapple_hi = 0.575;
// Least mip read, so pool edges stay soft close up; the swell reads far blurrier.
uniform float soft_lod = 3.0;
uniform float swell_lod = 6.0;
// Share of the broad layer the fine one replaces; 0 is the broad layer alone.
uniform float fine_share = 0.35;
// Overhead light between the pools: 0 leaves them black, 1 erases the pattern.
uniform float dapple_floor = 0.25;
// Swell gain: how far the 12 m layer (its luminance off the sheet's mean) lifts and sinks the pools.
uniform float swell_gain = 4.0;
// Mask mean, the even overhead light walls and trunks take instead of the pattern.
uniform float dapple_mean = 0.6;
// Metres per second the pattern drifts; 0 holds it still.
uniform float drift = 0.02;
// Share of the sky's light a dappled surface keeps: the shade level.
uniform float sky_share = 0.36;
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

float leaf_lum(vec2 uv, float least_lod) {
	vec2 size = vec2(textureSize(dapple_texture, 0));
	vec2 texel = fwidth(uv) * size;
	float lod = max(least_lod, log2(max(max(texel.x, texel.y), 1e-4)));
	return dot(textureLod(dapple_texture, uv, lod).rgb, vec3(0.299, 0.587, 0.114));
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
	float broad = leaf_lum(xz / dapple_metres, soft_lod);
	float fine = leaf_lum(turn * xz / fine_metres + vec2(0.37, 0.71), soft_lod);
	float swell = leaf_lum(transpose(turn) * xz / swell_metres + vec2(0.13, 0.59), swell_lod);
	float lift = (swell - 0.533) * swell_gain;
	float leaves = mix(smoothstep(dapple_lo, dapple_hi, broad + lift), smoothstep(dapple_lo, dapple_hi, fine + lift), fine_share);
	float pattern = mix(dapple_floor, 1.0, leaves);
	float up = max(0.0, (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).y);
	dapple = mix(dapple_mean, pattern, up);
}

void light() {
	if (LIGHT_IS_DIRECTIONAL) {
		float nl = clamp((dot(NORMAL, LIGHT) + wrap) / (1.0 + wrap), 0.0, 1.0);
		DIFFUSE_LIGHT += nl * dapple * overhead * ATTENUATION * LIGHT_COLOR / PI;
	} else {
		DIFFUSE_LIGHT += clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * ATTENUATION * LIGHT_COLOR / PI;
	}
}
