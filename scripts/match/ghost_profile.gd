class_name GhostProfile
extends Resource

## Every number a GHOST is made of, in one swappable resource.
##
## [b]What a ghost is[/b]
##
## Canon, in the author's words: "A shot prisoner becomes a ghost: faster than
## the living, cannot be shot, must catch up to a living player and take their
## spot." It exists to satisfy one hard constraint -- [i]"i dont want idel time
## for any player involved"[/i] -- so death is not a removal, it is a change of
## role with something to do the instant it happens.
##
## The catch is the whole mechanic. A ghost closes on a living prisoner and
## takes their spot -- literally, down to how far round the ring that prisoner
## had got: the caught player becomes the ghost, the ghost becomes living and
## inherits the lap. It is a SWAP -- not a revive, not a kill, and not a score.
## The count of living prisoners is unchanged by a catch, which is what keeps the
## shooter's win condition meaningful: only the rifle ever lowers it.
##
## [b]Which resource does a number belong in?[/b]
##
## The seam [MatchRules] states: this is the third kind of answer, and it is a
## DESIGN one. Everything here is a rule of the round rather than component
## tuning of a body or a brain, and it lives on its own resource for exactly the
## reason [WeaponProfile] and [RunnerProfile] do -- a headless sweep varies one
## file and changes nothing else. [MatchRules.ghost_behaviour] decides WHETHER
## ghosts exist at all; this decides what they are once they do.
##
## Nothing here is read while [member MatchRules.ghost_behaviour] is
## [constant MatchRules.GhostBehaviour.NONE].

## How much faster a ghost moves than the living, as a multiplier on the ground
## speed its [MovementProfile] would otherwise give it.
##
## "Faster than the living" is canon, and how much faster is the author's
## ruling: the shipped [code]resources/rules/default_ghost_profile.tres[/code]
## runs at 3.0. The code default below is the older 1.25 and is left alone
## deliberately -- a profile constructed from nothing is the neutral control a
## harness compares against, and the file the game is played on is the ruling.
##
## It is applied through
## [member PlayerController.speed_scale], so it scales the wish speed the same
## Quake accelerate routine a human is driven through reads -- a ghost is not
## running on different physics, only on a different target speed.
@export_range(0.5, 4.0, 0.05, "or_greater") var speed_multiplier: float = 1.25

## How close a ghost must get to a living prisoner to take their spot, in metres,
## measured horizontally.
##
## The body capsule is 0.8 m across, so anything under about 1.0 m would require
## the two capsules to interpenetrate, which they cannot -- a ghost is solid.
## 1.8 m is a body's width of clearance on top of contact: close enough to read
## as "caught you", far enough that the catch does not depend on the depenetration
## solver.
@export_range(0.5, 20.0, 0.1, "or_greater") var catch_radius_metres: float = 1.8

## Seconds a freshly made ghost may not catch anybody.
##
## [b]This is not flavour; without it the mechanic oscillates.[/b] A swap leaves
## the new ghost standing inside the new living player's catch radius, so on the
## very next physics tick it catches them straight back, and the two bodies trade
## roles sixty times a second forever. The grace is the smallest possible answer
## to "can a ghost be caught back immediately" -- no, not for this long -- and it
## is a number rather than a constant precisely because the right length of it is
## an open question.
##
## It runs from the moment a participant BECOMES a ghost, by either route: shot
## by the rifle, or caught by another ghost.
@export_range(0.0, 10.0, 0.1, "or_greater") var catch_grace_seconds: float = 1.5

## Seconds a killed participant is held, inert, where they died, before the
## match puts them back on the start line.
##
## The author's ruling: [i]"add a 3 second respawn timer. weather youre alive or
## already a ghost."[/i] Both halves matter. It is a hold on DEATH, not on
## becoming a ghost, so it is served identically by the three ways a body can
## die -- shot by the rifle, walked into a trap, fallen off the deck -- and by
## the fourth case, a ghost a hazard has to return to the start, which was never
## alive to begin with.
##
## [b]The hold happens where you died, not where you respawn.[/b] The placement
## is what waits: for these seconds the body stands frozen at the spot the shot,
## the trap or the pit found it, and only then is it moved. That is a deliberate
## reading of "before you are placed back at the start" and it is also the more
## useful one -- the last thing a converted prisoner sees is the place and the
## angle they were taken from, rather than a start line they are about to be
## standing on anyway.
##
## [b]What the body may do while it waits: nothing.[/b] See
## [method MatchController._place_ghost_at_start]. It is put through
## [method MatchController._hold_body], which is the same inertness every
## placement in a match uses -- off every collision layer and mask, velocity
## zeroed, [method Node.set_physics_process] false -- so it cannot be shot,
## cannot be caught, cannot trip a hazard, cannot fall, and cannot be moved by
## any intent from a keyboard or from a bot brain. [method
## MatchController._tick_ghosts] skips it outright, so its own catch clock does
## not run either.
##
## Zero turns the hold off entirely and restores the instant placement this
## match had before the timer existed, which is what a headless sweep that does
## not want three seconds of dead air per conversion should set.
@export_range(0.0, 10.0, 0.1, "or_greater") var respawn_delay_seconds: float = 3.0

## Whether the rifle can hit a ghost. Canon says it cannot, so false.
##
## True turns a ghost into a body that soaks the tower's one shot, which is
## either a good mechanic or a griefing tool; it is here so that question can be
## measured rather than argued, and it is not the shipped answer.
@export var shootable: bool = false


## The ghost profile a match should use, after [MatchRules] has had its say.
##
## The same three-step resolution [method RunnerProfile.resolve] uses, and for
## the same reason: an exported field is what a scene or a hand-built rule set
## sets, metadata is what a JSON sweep spec can set (it can only write a path),
## and the caller's own fallback is what a match with no opinion gets.
static func resolve(rules: MatchRules, fallback: GhostProfile) -> GhostProfile:
	if rules == null:
		return fallback

	for entry: Dictionary in rules.get_property_list():
		if String(entry.get("name", "")) == "ghost_profile":
			var exported: GhostProfile = rules.get("ghost_profile") as GhostProfile
			if exported != null:
				return exported
			break

	if rules.has_meta(&"ghost_profile"):
		var from_meta: GhostProfile = _as_profile(rules.get_meta(&"ghost_profile"))
		if from_meta != null:
			return from_meta

	return fallback


## A metadata value read back as a profile: the resource itself, or a path to
## one. Anything else is somebody's mistake and is reported rather than ignored,
## because a ghost tuning that quietly failed to apply would make a whole sweep
## a lie.
static func _as_profile(value: Variant) -> GhostProfile:
	var direct: GhostProfile = value as GhostProfile
	if direct != null:
		return direct
	if typeof(value) == TYPE_STRING:
		var path: String = String(value)
		var loaded: GhostProfile = load(path) as GhostProfile
		if loaded != null:
			return loaded
		push_error("GhostProfile could not load a profile from %s" % path)
		return null
	push_error("GhostProfile metadata must be a GhostProfile or a path to one.")
	return null
