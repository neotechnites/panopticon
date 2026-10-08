// Shared by the beach's shaders: the still sea's height and the sRGB decode for raw vertex colours.

const float SEA_Y = 22.6;          // the still water's surface (beach_build.py WATER_Z)

vec3 srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}
