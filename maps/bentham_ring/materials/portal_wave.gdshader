shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_opaque;

// The hell portal's swirl: a flat see-through disc whose texture ripples (rings outward, a slow twist).
// Distorted UVs snap to texel centres so the pixel art stays crisp; UV2.x pins the rim still.

uniform sampler2D albedo_texture : source_color, filter_nearest_mipmap_anisotropic, repeat_enable;
uniform sampler2D emission_texture : source_color, filter_nearest_mipmap_anisotropic, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform vec4 emission_color : source_color = vec4(1.0);
uniform float emission_energy = 1.4;
uniform float roughness = 1.0;
uniform float metallic = 0.0;
uniform vec3 uv1_scale = vec3(1.0);
uniform vec3 uv1_offset = vec3(0.0);

uniform vec2 disc_centre = vec2(0.0, 1.5);   // local xy of the disc's middle
uniform float ripple_wavelength = 0.42;      // metres ring to ring: ~7 rings across the disc
uniform float ripple_speed = 1.0;            // m/s outward: a ring crosses centre to rim in ~1.5 s
uniform float ripple_texels = 2.5;           // texels the swirl is pushed at a crest
uniform float twist_degrees = 4.0;           // the swirl's back-and-forth turn
uniform float twist_period = 3.2;            // seconds per twist
uniform float shimmer = 0.12;                // brightness riding the rings
uniform float rim_pin = 0.12;                // UV2.x (0 at the rim) where the ripple is full

varying vec2 disc_pos;

void vertex() {
	UV = UV * uv1_scale.xy + uv1_offset.xy;
	disc_pos = VERTEX.xy - disc_centre;
}

void fragment() {
	// local metres -> UV: the disc's mapping is planar, so this Jacobian is exact
	vec2 px = dFdx(disc_pos), py = dFdy(disc_pos);
	float det = px.x * py.y - px.y * py.x;
	mat2 to_uv = abs(det) > 1e-12 ? mat2(dFdx(UV), dFdy(UV)) * inverse(mat2(px, py)) : mat2(0.0);
	vec2 size = vec2(textureSize(albedo_texture, 0));
	float r = length(disc_pos);
	vec2 rad = r > 1e-4 ? disc_pos / r : vec2(0.0);
	float k = 6.2831853 / ripple_wavelength;
	float om = k * ripple_speed;
	float wave = 0.65 * sin(k * r - om * TIME) + 0.35 * sin(1.6 * k * r - 1.25 * om * TIME + 1.7);
	float pin = clamp(UV2.x / rim_pin, 0.0, 1.0);
	// rings: a push along the radius, a fixed number of texels long
	vec2 rad_uv = to_uv * rad;
	float rad_tex = length(rad_uv * size);
	vec2 off = rad_tex > 1e-6 ? rad_uv / rad_tex * ripple_texels * wave : vec2(0.0);
	// twist: the swirl turns a few degrees and back, the outside lagging the middle
	float ang = radians(twist_degrees) * sin(6.2831853 * TIME / twist_period - 0.9 * r);
	off += to_uv * (vec2(-disc_pos.y, disc_pos.x) * ang) * size;
	vec2 uv = (floor(UV * size + off * pin) + 0.5) / size;
	vec2 gx = dFdx(UV), gy = dFdy(UV);
	vec4 albedo_tex = textureGrad(albedo_texture, uv, gx, gy);
	float glow = 1.0 + shimmer * pin * wave;
	ALBEDO = albedo_tex.rgb * albedo_color.rgb * glow;
	ALPHA = albedo_tex.a * albedo_color.a;
	EMISSION = textureGrad(emission_texture, uv, gx, gy).rgb * emission_color.rgb * emission_energy * glow;
	ROUGHNESS = roughness;
	METALLIC = metallic;
}
