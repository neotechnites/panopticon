shader_type canvas_item;
render_mode blend_mix, unshaded;

// The scope, drawn rather than modelled.
//
// Ryan's brief: "it comes up to your eye then puts like a vignette on your
// screen, the scope doesn't actually need to be see through." So this is the
// optic: a dark ring closing in from the edges of the screen around a clear
// centre, exactly the Call of Duty read, with no render target, no second
// camera and no transparent lens on the model. The rifle's own scope stays
// the opaque brick tools/modelling/rifle_build.py makes it.
//
// Every uniform below is driven from scripts/optics/scope_vignette.gd, which
// reads them off ZoomProfile -- see that resource's "Scope vignette" group.
// Nothing here has an opinion of its own about how dark or how tight the
// optic is.

// 0 at hipfire, 1 at full aim. The one value that animates: it is
// RifleAds' own shaped transition progress, remapped by ZoomProfile's onset,
// so the ring closes on exactly the clock the pose and the field of view use.
uniform float amount : hint_range(0.0, 1.0) = 0.0;

// How opaque the darkest part of the border gets.
uniform float opacity : hint_range(0.0, 1.0) = 1.0;

// Radius of the clear centre, as a fraction of HALF THE SCREEN HEIGHT: 1.0
// would touch the top and bottom edges. Below this radius the screen is
// untouched, which is what keeps the shot line's own pixels readable.
uniform float clear_fraction : hint_range(0.0, 1.2) = 0.46;

// How far past clear_fraction the border takes to reach full opacity, in the
// same units. Small is a hard-edged tube; large is a soft fall-off.
uniform float softness : hint_range(0.01, 1.5) = 0.30;

// Viewport width / height, pushed in by the script. Without it the ring is an
// ellipse stretched to the window rather than the circle an optic actually is.
uniform float aspect = 1.7777778;

// The border's colour. Black is a scope body; anything else is a stylistic
// choice, so it is a uniform rather than a constant.
uniform vec4 tint : source_color = vec4(0.0, 0.0, 0.0, 1.0);

void fragment() {
	// Centre-relative, scaled so 1.0 is half the screen HEIGHT in both axes --
	// the aspect factor is what makes the ring round on a 16:9 window and
	// still round on a 4:3 one.
	vec2 offset = (UV - vec2(0.5)) * vec2(aspect, 1.0) * 2.0;
	float radius = length(offset);
	float edge = smoothstep(clear_fraction, clear_fraction + softness, radius);
	COLOR = vec4(tint.rgb, tint.a * edge * opacity * amount);
}
