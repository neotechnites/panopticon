shader_type canvas_item;
render_mode unshaded;

// The low-res 3D (ps1_presentation.gd's SubViewport) under the UI, one texel per block, cut to 5 bits a channel, Bayer 4x4 dithered.

uniform vec2 low_size = vec2(320.0, 240.0);   // the SubViewport's size in pixels
uniform float levels = 31.0;                   // steps per channel: 31 is 5 bits
uniform float dither = 1.0;                    // 0 rounds, 1 is the full ordered dither

const float BAYER[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);

void fragment() {
	vec2 cell = floor(UV * low_size);
	vec3 colour = texture(TEXTURE, (cell + 0.5) / low_size).rgb;
	int index = int(mod(cell.x, 4.0)) + int(mod(cell.y, 4.0)) * 4;
	float threshold = mix(0.5, (BAYER[index] + 0.5) / 16.0, dither);
	COLOR = vec4(min(floor(colour * levels + threshold), levels) / levels, 1.0);
}
