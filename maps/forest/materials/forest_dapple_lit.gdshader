// A forest surface whose sun light passes through a soft leaf dapple (forest_dapple.png), projected
// along each sun to the ground plane; ambient and every other light are untouched.
shader_type spatial;

uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_vertex_color = true;
uniform float roughness = 0.95;
uniform sampler2D dapple : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float dapple_metres = 27.0;
// 0 leaves the sun whole, 1 is the full dapple.
uniform float dapple_strength = 1.0;

varying vec3 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec4 tex = texture(albedo_texture, UV);
	vec3 base = albedo_color.rgb * tex.rgb;
	if (use_vertex_color) {
		base *= COLOR.rgb;
	}
	ALBEDO = base;
	ROUGHNESS = roughness;
}

void light() {
	float sun = 1.0;
	if (LIGHT_IS_DIRECTIONAL) {
		vec3 l = (INV_VIEW_MATRIX * vec4(LIGHT, 0.0)).xyz;
		vec2 p = world.xz - l.xz / max(l.y, 0.2) * world.y;
		sun = mix(1.0, texture(dapple, p / dapple_metres).r, dapple_strength);
	}
	DIFFUSE_LIGHT += clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * ATTENUATION * LIGHT_COLOR / PI * sun;
}
