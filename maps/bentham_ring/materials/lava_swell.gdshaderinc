// The flat lava's swell at world xz, -1..1: a long roll toward the pit crossed by a slower one.
// lava_wave.gdshaderinc moves the lava by it; hot_rock.gdshader breathes the heated rim with it.
float lava_swell(vec2 xz, vec2 centre, float t) {
	return 0.6 * sin(0.4 * length(xz - centre) + t) + 0.4 * sin(0.2 * xz.x + 0.27 * xz.y + 0.7 * t);
}
