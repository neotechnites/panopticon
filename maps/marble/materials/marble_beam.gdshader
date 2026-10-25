shader_type spatial;
// The oculus cone, one vane of six: a plane through the spot's axis, fanned to the spot's own half-angle (taper),
// shaded with the spot's own angular falloff (1 - rim^cone_attenuation, the engine's spot formula) times a bright
// core over the tower with a faint skirt out to the cone's edge, feathered toward its foot, gone edge-on (forest's ray approach).
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 tint : source_color = vec3(0.96, 0.93, 0.8);
uniform float alpha_gain = 0.2;
uniform float cone_angle = 62.0;       // degrees, the spot's half-angle
uniform float cone_attenuation = 2.0;  // the spot's spot_angle_attenuation
uniform float core_angle = 28.0;       // degrees: the bright body of the visible cone (gaussian in angle)
uniform float skirt = 0.25;            // how much of the glow survives outside the core, out to the spot's edge
uniform float apex_rise = 5.85;        // the light cone's apex sits this far above the vane's top edge (glass rim on the cone edge)
uniform float taper = 7.58;            // foot half-width / top half-width
uniform float half_height = 19.25;     // half the vane's height (the quad's), to place the apex from local y

varying vec2 lp;

void vertex() {
	VERTEX.x *= mix(1.0, taper, UV.y);
	lp = VERTEX.xy;
}

void fragment() {
	float drop = (half_height - lp.y) + apex_rise;      // distance below the apex
	float cos_t = drop / sqrt(drop * drop + lp.x * lp.x);
	float cos_c = cos(radians(cone_angle));
	float rim = clamp((1.0 - cos_t) / (1.0 - cos_c), 0.0, 1.0);
	float fall = max(1.0 - pow(rim, cone_attenuation), 0.0);   // the light's own profile: 1 on the axis, 0 at the cone's edge
	float theta = acos(clamp(cos_t, 0.0, 1.0)) / radians(core_angle);
	float body = mix(skirt, 1.0, exp(-theta * theta));           // bright core over the tower, a faint skirt to the edge
	float down = smoothstep(0.0, 0.06, UV.y) * mix(1.0, 0.45, UV.y) * (1.0 - smoothstep(0.75, 1.0, UV.y));
	float face = smoothstep(0.1, 0.6, abs(dot(normalize(NORMAL), normalize(VIEW))));
	ALBEDO = tint;
	ALPHA = clamp(alpha_gain * fall * body * down * face, 0.0, 1.0);
}
