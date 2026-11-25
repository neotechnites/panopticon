class_name PowerDef
extends Resource

## One runner power's definition (DESIGN 9 PowerDef): its own run and cooldown, and how it behaves.
## One file per [enum MatchRules.RunnerAbility] in [code]res://match/powers/[/code], read by [RunnerPower].

## What the host simulates for it, where its activation puts it, and the clock it runs on.
enum Entity { NONE, DECOY, CAT }
enum Place { NONE, ABOVE, AHEAD }
## TIMED runs from the press; FUSE (the cat) only once it is lit.
enum Clock { NONE, TIMED, FUSE }

@export var clock: Clock = Clock.NONE
## Seconds it runs (the fuse, for the cat); a release-ended power runs at most this long.
@export_range(0.0, 60.0, 0.1, "or_greater") var duration_seconds: float = 0.0
## Seconds after it ends before it can be used again, before [member MatchRules.ability_cooldown_multiplier].
@export_range(0.0, 120.0, 0.5, "or_greater") var cooldown_seconds: float = 0.0
## Letting the power key go ends it.
@export var ends_on_release: bool = false
@export var place: Place = Place.NONE
@export var entity: Entity = Entity.NONE
## It holds the body still (and hit-immune).
@export var holds_body: bool = false
