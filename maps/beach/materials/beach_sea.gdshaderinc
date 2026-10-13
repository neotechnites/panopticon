// Shared by the beach's shaders: the still sea's height and the sRGB decode for raw vertex colours.

const float SEA_Y = 22.6;          // the still water's surface (beach_build.py WATER_Z)

vec3 srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

// A tile whose own edges do not match, read with no seam: four taps half a period apart weighted by sin^2/cos^2,
// which sum to 1 and vanish WITH THEIR SLOPE exactly on the tile's edges; contrast is kept about `mean`.
vec3 tile_seamless(sampler2D tex, vec2 uv, vec3 mean) {
	vec2 s = sin(3.14159265 * fract(uv));
	vec2 wb = s * s;                                 // 1 at the tile's middle, 0 on its edge
	vec2 wa = 1.0 - wb;                              // cos^2: the other way about
	vec4 w = vec4(wb.x * wb.y, wa.x * wb.y, wb.x * wa.y, wa.x * wa.y);
	vec3 t = w.x * texture(tex, uv).rgb
		+ w.y * texture(tex, uv + vec2(0.5, 0.0)).rgb
		+ w.z * texture(tex, uv + vec2(0.0, 0.5)).rgb
		+ w.w * texture(tex, uv + vec2(0.5, 0.5)).rgb;
	return mean + (t - mean) * inversesqrt(dot(w, w));   // the cross-fade's lost contrast put back
}


// The tile's own average colour: its 1x1 mip, so nothing has to be hand-matched when the drawing changes.
vec3 tile_mean(sampler2D tex) {
	return textureLod(tex, vec2(0.5), 16.0).rgb;
}
