// The sun as Sunshine drew it: a soft sprite 2.5 km out toward the scene's Sun, held square to the camera, a hot
// white core in a wide soft halo with long thin star rays; no edge. The glare that blinds is beach_sun_glare.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, skip_vertex_transform, fog_disabled, shadows_disabled;

uniform vec3 sun_direction = vec3(0.9587, 0.1219, 0.2568);   // toward the sun: the scene's Sun (+Z)
uniform vec3 sun_color : source_color = vec3(1.0, 0.66, 0.3);    // sunset orange-gold
uniform vec3 core_color : source_color = vec3(1.0, 0.93, 0.7);
uniform float core_degrees = 1.6;     // the hot core's soft radius
uniform float halo_degrees = 7.0;     // the halo's falloff
uniform float ray_degrees = 11.0;     // how far the star rays reach (shortened a third)
uniform float span_degrees = 20.0;    // the sprite's half size
uniform float sun_distance = 2500.0;
uniform float display_gain = 1.0;    // tuned in plain SDR

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
	float fade = 1.0 - clamp(a / span_degrees, 0.0, 1.0);            // everything tapers to nothing at the edge
	fade *= fade;
	ALBEDO = (core_color * core + sun_color * (halo + rays) * fade) * display_gain;
}
