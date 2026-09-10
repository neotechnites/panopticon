class_name AirControlPreset
extends Resource

## One named answer to the question "how much should the mouse steer a body that
## is off the ground?", expressed as a small edit to the shipped
## [MovementProfile].
##
## [b]Why this is a derivation and not a whole profile[/b]
##
## A preset states [member base] plus the four air-control numbers and nothing
## else, so two things are true by construction rather than by review:
##
## 1. Two presets can differ [i]only[/i] in air control. Copy a whole profile
##    instead and a stray edit to walk speed or to the slide's boost cap rides
##    along in the comparison, and the back-to-back test stops answering the
##    question it was set up to answer.
## 2. Retuning gravity, the slide or the jump moves every preset at once. A
##    fleet of hand-copied profiles goes stale the first time the shipped
##    default is touched, silently, and the stale ones then argue for a game
##    that no longer exists.
##
## [b]The four numbers, and why they are the four[/b]
##
## [member MovementProfile.max_air_speed] and
## [member MovementProfile.air_acceleration] are the Quake air-acceleration
## routine's only inputs; [member MovementProfile.air_friction] is the only
## thing that removes speed while airborne; and
## [member MovementProfile.auto_bunny_hop] decides whether the body is airborne
## at all between hops. Nothing else in the profile touches how a body turns in
## the air. See [method PlayerController._air_accelerate].
##
## [b]Measured, not asserted[/b]
##
## Holding forward and turning the mouse at a constant rate while jump is held,
## the angle between where the body faces and where it is travelling settles at
## [code]acos(max_air_speed / speed)[/code] -- the direct consequence of
## [method PlayerController._accelerate] adding nothing once
## [code]velocity.dot(wish) >= max_air_speed[/code]. Raising
## [member MovementProfile.max_air_speed] on its own therefore does [b]not[/b]
## fix the lock: speed rises in the same proportion and the ratio, hence the
## angle, barely moves. Only [member MovementProfile.air_friction] puts a
## ceiling on the speed and so on the angle, and only touching the floor
## replaces the whole air branch with ground acceleration. The presets on disk
## are built from that finding rather than from taste.

## What this preset is called on screen. Named for the sensation, not the
## numbers -- the point of the set is to be chosen between by feel.
@export var display_name: String = ""

## One sentence describing what the player should expect to feel, shown under
## the name while the preset is selected.
@export_multiline var feel: String = ""

## The profile every number that is [i]not[/i] air control comes from. The
## shipped default, so a preset can never quietly retune the game underneath the
## comparison.
@export var base: MovementProfile

## See [member MovementProfile.max_air_speed].
@export_range(0.0, 20.0, 0.01, "or_greater") var max_air_speed: float = 0.8

## See [member MovementProfile.air_acceleration].
@export_range(0.0, 60.0, 0.1, "or_greater") var air_acceleration: float = 12.0

## See [member MovementProfile.air_friction].
@export_range(0.0, 30.0, 0.1, "or_greater") var air_friction: float = 0.0

## See [member MovementProfile.auto_bunny_hop].
@export var auto_bunny_hop: bool = true


## A private [MovementProfile] carrying this preset's air control over
## [member base].
##
## A duplicate every time, deliberately. [member base] is the one instance of
## [code]default_movement_profile.tres[/code] that the whole process shares, and
## writing into it would retune the shipped game from a dev scene -- the exact
## failure this whole exercise exists to avoid.
func build() -> MovementProfile:
	if base == null:
		push_error("AirControlPreset \"%s\" has no base MovementProfile." % display_name)
		return null
	var profile: MovementProfile = base.duplicate() as MovementProfile
	profile.max_air_speed = max_air_speed
	profile.air_acceleration = air_acceleration
	profile.air_friction = air_friction
	profile.auto_bunny_hop = auto_bunny_hop
	return profile


## The four numbers on one line, for a readout that wants them under the name.
func describe_numbers() -> String:
	return "air cap %.1f  accel %.0f  drag %.2f  auto-hop %s" % [
		max_air_speed, air_acceleration, air_friction, "on" if auto_bunny_hop else "off",
	]
