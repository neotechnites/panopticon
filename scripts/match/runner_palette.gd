class_name RunnerPalette
extends Resource

## The colours a match paints its bodies with. Purely data -- [MatchController]
## turns an entry here into an unshaded [StandardMaterial3D] at runtime, never
## the other way round, so retuning the roster's colours is an edit to this
## Resource and never to the controller script.
##
## [b]Why a Resource and not a script constant[/b]
##
## The author's own instruction: colours belong on something Ryan can open and
## drag swatches around in, not buried in [code]match_controller.gd[/code]. The
## shipped instance is
## [code]resources/rules/default_runner_palette.tres[/code]; a scene that names
## none gets it, exactly the way [method MatchController.get_ghost_profile]
## falls back to the shipped [GhostProfile].
##
## [b]Three colours, three jobs[/b]
##
## [member runner_colors] is dealt one-per-seat, in [member
## MatchParticipant.index] order, and is what makes two runners tellable apart
## at a glance -- the thing this whole Resource exists for. [member ghost_alpha]
## is not a colour at all: a ghost wears the SAME entry its body already has,
## with this as the alpha, so a ghost reads as both "which participant" and
## "a ghost" in the same glance instead of one flat colour meaning both. [member
## guard_color] is the one colour no runner is ever dealt, so the seat always
## reads as a role and never as a coincidence of whoever is sitting in it.

## One entry per seat, in match order. Chosen to stay readable at 35-60 m
## against the arena's grey deck (albedo ~0.42) and dark surrounds under GL
## Compatibility's flat, unshaded shading -- and clear of the traps' saturated
## red ([code]Color(0.86, 0.06, 0.06)[/code]), the cover pieces' duller
## green/brown/grey, and [member guard_color]. Wraps rather than runs out --
## see [method color_for_index] -- so a roster bigger than this list repeats
## colours rather than breaking.
@export var runner_colors: Array[Color] = [
	Color(0.95, 0.82, 0.10, 1.0), # yellow
	Color(0.20, 0.55, 0.95, 1.0), # sky blue
	Color(0.45, 0.90, 0.20, 1.0), # lime
	Color(0.90, 0.25, 0.80, 1.0), # magenta
	Color(1.00, 0.60, 0.05, 1.0), # amber
	Color(0.10, 0.90, 0.80, 1.0), # cyan
	Color(0.60, 0.35, 0.95, 1.0), # violet
	Color(0.95, 0.90, 0.75, 1.0), # warm white, last resort
]

## Alpha a ghost's own runner colour is painted at. Not a separate hue -- see
## the class doc -- and not a faint one either: the author's own word is
## "slightly" translucent, meaning still clearly visible, not a wisp.
@export_range(0.0, 1.0, 0.01) var ghost_alpha: float = 0.62

## The one colour worn only by whoever holds the tower, and never dealt to a
## runner. A cool grey deliberately close to the model's own shipped flat grey
## -- the guard is a role, not a racer -- but distinct from the deck's neutral
## grey (0.42, 0.42, 0.44) so the seat still reads as painted rather than bare.
@export var guard_color: Color = Color(0.42, 0.46, 0.56, 1.0)


## [param index]'s runner colour, wrapping if the roster outgrows the list.
## Falls back to [member guard_color] only if the list has been emptied
## entirely -- a body still has to wear SOMETHING.
func color_for_index(index: int) -> Color:
	if runner_colors.is_empty():
		return guard_color
	return runner_colors[index % runner_colors.size()]
