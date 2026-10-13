// The bay's fish, GameCube style: sprite cards turned round their swim line to face the camera, a tail wiggle from
// beach_fish_albedo; seen through the water by the sea's own absorption and view-path see-through at their depth.
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, skip_vertex_transform, shadows_disabled, fog_disabled;

#include "res://maps/beach/materials/beach_sea.gdshaderinc"

uniform sampler2D sheet : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D ripples : filter_linear_mipmap, repeat_enable;   // the sea's offset texture: the refraction wobble
uniform float species_rows = 5.0;
uniform float frames = 3.0;
uniform float frame_rate = 7.0;
uniform vec3 bed_tint = vec3(0.2, 0.8, 0.95);       // beach_build.py BED_TINT: the water's colour on what is under it
uniform vec3 absorb = vec3(0.15, 0.035, 0.028);    // half beach_build.py ABSORB: the bed's light goes down and back up
uniform float tint_share = 0.25;                   // how much of the bed's water tint a fish takes
uniform float extinction = 7.5;                    // beach_water.gdshader: metres of sight line that hide ~63%
uniform float refraction = 0.12;                   // metres the ripples shift a fish per metre of depth
uniform float display_gain = 0.73;                 // Ryan's HDR desktop shows SDR at 2x linear (beach_water.gdshader)

varying float depth;
varying float see;

void vertex() {
	// INSTANCE_CUSTOM: x species row, y animation phase, z length (m); the basis's x is the swim direction
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 dir = normalize(MODEL_MATRIX[0].xyz);
	vec3 cam = CAMERA_POSITION_WORLD;
	vec3 up = cross(normalize(cam - origin), dir);
	float side = length(up);                       // a fish swimming straight at the camera thins to a line
	up = side > 0.001 ? up / side : vec3(0.0, 1.0, 0.0);
	if (dot(up, INV_VIEW_MATRIX[1].xyz) < 0.0) {
		up = -up;                                  // the dorsal fin stays toward the top of the screen
	}
	float len = INSTANCE_CUSTOM.z;
	vec3 world = origin + dir * VERTEX.x * len + up * VERTEX.y * len * 0.5;
	depth = max(SEA_Y - world.y, 0.0);
	vec2 off = textureLod(ripples, world.xz / 9.0 + TIME * vec2(0.021, 0.006), 0.0).xy
		+ textureLod(ripples, world.xz / 5.3 - TIME * vec2(0.007, 0.017), 0.0).xy - 1.0;
	world.xz += off * refraction * depth;
	vec3 v = normalize(cam - world);
	see = mix(0.12, 1.0, 1.0 - exp(-(depth / max(v.y, 0.03)) / extinction));
	// drawn where its sight line meets the surface: the same pixels, but in front of the water's depth
	if (cam.y > SEA_Y + 0.05 && world.y < SEA_Y) {
		world = cam + (world - cam) * ((cam.y - SEA_Y - 0.03) / (cam.y - world.y));
	}
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	float f = mod(floor(TIME * frame_rate + INSTANCE_CUSTOM.y * 4.0), 4.0);
	f = f == 3.0 ? 1.0 : f;                        // frames 0 1 2 1: a back-and-forth wiggle
	UV = vec2((f + UV.x) / frames, (INSTANCE_CUSTOM.x + UV.y) / species_rows);
}

void fragment() {
	vec4 c = texture(sheet, UV);
	float k = smoothstep(0.0, 1.0, clamp(depth / 0.8, 0.0, 1.0));
	ALBEDO = c.rgb * mix(vec3(1.0), bed_tint, k * tint_share) * exp(-absorb * depth) * display_gain;
	ALPHA = step(0.45, c.a) * (1.0 - see);
}
