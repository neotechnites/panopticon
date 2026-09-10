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
## takes their spot: the caught player becomes the ghost, the ghost becomes
## living. It is a SWAP -- not a revive, not a kill, and not a score. The count
## of living prisoners is unchanged by a catch, which is what keeps the
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
## "Faster than the living" is canon; how much faster is not, and it is the
## single most important number in the mechanic -- it decides whether a catch is
## a certainty (in which case the round is a formality) or a chase (in which case
## it is a game). 1.25 is a starting guess, not a measured answer: at the shipped
## walk speed of 8 m/s it closes a 10 m gap in five seconds of straight running,
## which is long enough to be a chase and short enough that a ghost is never
## simply out of the round.
##
## [b]Sweep this first.[/b] It is applied through
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

## Whether the rifle can hit a ghost. Canon says it cannot, so false.
##
## True turns a ghost into a body that soaks the tower's one shot, which is
## either a good mechanic or a griefing tool; it is here so that question can be
## measured rather than argued, and it is not the shipped answer.
@export var shootable: bool = false

## Whether a chasing ghost holds sprint.
##
## Compounds with [member speed_multiplier] rather than replacing it: sprint is
## the same button a living prisoner holds, and the multiplier scales whatever
## speed that produces. On by default because a ghost that ambled would never
## close on a sprinting prisoner however large the multiplier was made.
@export var chase_holds_sprint: bool = true

## Whether a swap carries the caught prisoner's lap progress to the ghost who
## took their spot.
##
## [b]This is the ghost HINDER / ghost HELP question in its smallest form, and it
## is NOT ruled.[/b] It is exposed rather than baked in because the two readings
## produce different games:
##
## - [b]true[/b] (shipped) -- "takes their spot" is read literally: the spot
##   includes the distance already run. A catch changes WHO is alive and nothing
##   else, so the prisoners as a side lose nothing and gain nothing, and the ring
##   keeps advancing towards the finish. Neutral.
## - [b]false[/b] -- the ghost starts the caught player's spot from its own,
##   lower progress. A catch then costs the prisoners the lap the caught player
##   had run, which makes a ghost a HINDRANCE to the side it used to be on.
##
## True is the default because it is the plain reading of the canon sentence and
## because it is the one that cannot deadlock a round: with progress conserved,
## a pair of prisoners trading roles still walks the lap between them. See
## [method MatchController.get_ghost_profile] and the report that shipped this.
@export var catch_transfers_progress: bool = true


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
