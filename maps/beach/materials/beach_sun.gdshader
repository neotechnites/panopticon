// The sun as Sunshine drew it: a soft sprite 2.5 km out toward the scene's Sun, held square to the camera, a hot
// white core in a wide soft halo with long thin star rays; no edge. The glare that blinds is beach_sun_glare.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, skip_vertex_transform, fog_disabled, shadows_disabled;

uniform vec3 sun_direction = vec3(0.7913, 0.5736, 0.212);   // toward the sun: the scene's Sun (+Z)
uniform vec3 sun_color : source_color = vec3(1.0, 0.98, 0.9);
uniform float core_degrees = 1.6;     // the hot core's soft radius
uniform float halo_degrees = 7.0;     // the halo's falloff
uniform float ray_degrees = 16.0;     // how far the star rays reach
uniform float span_degrees = 20.0;    // the sprite's half size
uniform float sun_distance = 2500.0;
uniform float display_gain = 0.73;   // Ryan's HDR desktop shows SDR at 2x linear; unshaded output is undone by 2^(-1/2.2)

varying vec2 offset;

void vertex() {
	offset = VERTEX.xy * 2.0;                                     // the QuadMesh is 1 x 1: -1..1 across it
	float span = sun_distance * tan(radians(span_degrees));
	vec3 centre = (VIEW_MATRIX * vec4(CAMERA_POSITION_WORLD + normalize(sun_direction) * sun_distance, 1.0)).xyz;
	VERTEX = centre + vec3(offset * span, 0.0);
}

void fragment() {
	float a = length(offset) * span_degrees;                      // degrees from the sun's centre
	float ang = atan(offset.y, offset.x);
	float core = exp(-pow(a / core_degrees, 2.0)) * 1.8;
	float halo = 0.55 * exp(-a / halo_degrees);
	float rays = (pow(abs(cos(ang * 4.0)), 60.0) + 0.6 * pow(abs(cos(ang * 4.0 + 0.39)), 90.0)
		+ 0.4 * pow(abs(cos(ang * 7.0 + 1.1)), 120.0)) * exp(-a / (ray_degrees * 0.35)) * 0.7;
	float fade = 1.0 - smoothstep(span_degrees * 0.8, span_degrees, a);
	ALBEDO = sun_color * (core + halo + rays) * fade * display_gain;
}
