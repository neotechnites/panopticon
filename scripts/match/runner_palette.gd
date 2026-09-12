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

## One entry per seat, in match order, worn on the shirt. Chosen to stay
## readable at 35-60 m against dark red rock and lava: no reds, oranges or
## browns, nothing that could be mistaken for the arena or for a trap. Wraps
## rather than runs out -- see [method color_for_index].
@export var runner_colors: Array[Color] = [
	Color(0.98, 0.85, 0.10, 1.0), # yellow
	Color(0.10, 0.92, 0.92, 1.0), # cyan
	Color(0.50, 0.95, 0.15, 1.0), # lime
	Color(0.95, 0.20, 0.85, 1.0), # magenta
	Color(0.92, 0.94, 0.88, 1.0), # off-white
	Color(0.25, 0.60, 1.00, 1.0), # sky blue
	Color(0.62, 0.35, 0.98, 1.0), # violet
	Color(0.45, 1.00, 0.72, 1.0), # mint
]

## Alpha a ghost's own runner colour is painted at. Not a separate hue -- see
## the class doc -- and not a faint one either: the author's own word is
## "slightly" translucent, meaning still clearly visible, not a wisp.
@export_range(0.0, 1.0, 0.01) var ghost_alpha: float = 0.62

## The one shirt colour worn only by whoever holds the tower, never dealt to a
## runner: plain white, so the seat reads as a role rather than as a racer, and
## is still clear of the off-white in [member runner_colors].
@export var guard_color: Color = Color(1.0, 1.0, 1.0, 1.0)


## [param index]'s runner colour, wrapping if the roster outgrows the list.
## Falls back to [member guard_color] only if the list has been emptied
## entirely -- a body still has to wear SOMETHING.
func color_for_index(index: int) -> Color:
	if runner_colors.is_empty():
		return guard_color
	return runner_colors[index % runner_colors.size()]
