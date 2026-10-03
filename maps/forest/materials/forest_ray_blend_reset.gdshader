shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled;

// RayMat's next pass, drawn before the streaks (lower render_priority) and culled with them; its vertices are off-screen, so it draws nothing.
// It only binds blend_mix: Compatibility caches blend state, and a blend_add first in the transparent pass inherits GL_ONE,GL_ONE from the opaque light passes (alpha ignored).
void vertex() {
	POSITION = vec4(0.0, 0.0, 2.0, 1.0);
}

void fragment() {
	ALBEDO = vec3(0.0);
	ALPHA = 0.0;
}
