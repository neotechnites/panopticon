// PS1 vertex snap and affine UVs for any spatial shader: PS1_VERTEX last in vertex(), PS1_UV(UV) and PS1_TEXTURE in fragment().
// Driven by global uniforms that scripts/fx/ps1_presentation.gd writes; both zero leaves the shader as it was.

global uniform vec2 ps1_snap_grid;   // snap steps across the view (0 is off)
global uniform float ps1_affine;     // 0 perspective-correct UVs .. 1 fully affine
global uniform float ps1_mip_bias;   // negative: mips picked as at the window's resolution, not the low-res one

varying vec3 ps1_uvw;

// The main camera only: shadow views are orthographic or square, and snapping them to the screen grid shifts shadows.
vec4 ps1_snap(vec4 clip, mat4 projection) {
	bool view = projection[2][3] < -0.5 && abs(projection[0][0] - projection[1][1]) > 0.001;
	if (view && ps1_snap_grid.x > 0.0 && clip.w > 0.0) {
		vec2 half_grid = ps1_snap_grid * 0.5;
		clip.xy = round(clip.xy / clip.w * half_grid) / half_grid * clip.w;
	}
	return clip;
}

#define PS1_VERTEX vec4 ps1_clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)); POSITION = ps1_snap(ps1_clip, PROJECTION_MATRIX); ps1_uvw = vec3(UV * ps1_clip.w, ps1_clip.w);
#define PS1_UV(uv) mix(uv, ps1_uvw.xy / ps1_uvw.z, ps1_affine)
#define PS1_TEXTURE(tex, uv) texture(tex, uv, ps1_mip_bias)
