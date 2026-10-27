shader_type spatial;
// The oculus' god ray: an open cone drawn additively, cull_back so only its near half draws and the eye never
// sees it from inside. Not a wall of haze (Ryan 2026-10-26: "too foggy ... too bright, it washes out the tower
// and everything behind it"): a thin bright core where the sight line crosses the axis, a fast fall to a soft
// but defined silhouette, faint striations round the cone so it reads as rays with the motes in them, and a
// low body so the tower and the far wall keep their contrast through it.
render_mode unshaded, blend_add, cull_back, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 tint : source_color = vec3(1.0, 0.96, 0.88);
uniform float strength = 0.09;      // the body, at the top, face-on (0.30 was the haze)
uniform float core = 0.06;          // the thin core on top of the body, under the glass
uniform float body_power = 3.5;     // (N.V)^p: the body's radial fall (1.6 was the haze)
uniform float core_power = 28.0;    // the core's: full only within ~25 percent of the radius
uniform float streaks = 0.35;       // how deep the striations cut
uniform float forward_gain = 3.0;   // forward scatter: looking up the ray into the glass it blooms; level, nothing

void fragment() {
	float f = abs(dot(normalize(NORMAL), normalize(VIEW)));
	// Dust scatters forward: from under the oculus looking up the ray (the view vector pointing down into the
	// eye) the cone's near wall blooms and its fall softens; from the lane, level with the tower, this is nil.
	vec3 vw = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	float forward = pow(clamp(-vw.y, 0.0, 1.0), 3.0);
	float body = pow(f, mix(body_power, 1.5, forward)) * (1.0 + forward_gain * forward);
	float ray = pow(f, core_power);
	// Brightest under the glass, a third of that at the floor, gone before the floor; the core spends itself
	// in the upper half, so the tower (UV.y 0.55..0.8) takes the body alone and keeps its contrast.
	float foot = 1.0 - smoothstep(0.80, 1.0, UV.y);
	float along = mix(1.0, 0.33, UV.y) * foot;
	float along_core = (1.0 - UV.y) * (1.0 - UV.y) * foot;
	// Two incommensurate bands round the cone: rays, not a gradient; never to zero.
	float s = 1.0 - streaks * (0.5 + 0.5 * sin(UV.x * 6.2832 * 22.0)) * (0.5 + 0.5 * sin(UV.x * 6.2832 * 9.0 + 1.3));
	ALBEDO = tint * (strength * body * along + core * ray * along_core) * s;
}
