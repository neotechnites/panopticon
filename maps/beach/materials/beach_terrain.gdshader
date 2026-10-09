// The island's ground: grass and the crag's rock in ONE material, blended by a per-vertex rock weight (UV2.y, baked
// by beach_build.py) with a noise-driven soft edge; both triplanar, the grass at two scales so its repeat hides.
shader_type spatial;

#include "res://maps/beach/materials/beach_sea.gdshaderinc"

uniform sampler2D grass_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float grass_metres = 12.8;
uniform float rock_metres = 102.4;
uniform float edge_noise = 0.4;

varying vec3 wpos;
varying vec3 wnrm;
varying float rock_w;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	rock_w = UV2.y;
}

vec3 triplanar(sampler2D tex, vec3 p, vec3 n, float metres) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	return texture(tex, p.zy / metres).rgb * w.x + texture(tex, p.xz / metres).rgb * w.y + texture(tex, p.xy / metres).rgb * w.z;
}

void fragment() {
	vec3 g1 = triplanar(grass_texture, wpos, wnrm, grass_metres);
	vec3 g2 = triplanar(grass_texture, wpos + vec3(37.0, 0.0, 11.0), wnrm, grass_metres * 3.1);
	vec3 grass = mix(g1, g2, 0.45);
	vec3 rock = triplanar(rock_texture, wpos, wnrm, rock_metres);
	float n = texture(rock_texture, wpos.xz / 61.0).r;
	float k = smoothstep(0.42, 0.58, rock_w + edge_noise * (n - 0.55));
	ALBEDO = mix(grass, rock, k) * srgb_to_linear(COLOR.rgb);
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
}
