class_name BotParticipantTally
extends RefCounted

## One participant's contribution to a bot match, accumulated by
## [BotMatchTelemetry] and serialised into the per-match result file.
##
## A participant in PANOPTICON is not "a guard" or "a prisoner" -- the tower
## changes hands, so the same body is both over the course of one match. Every
## field here is therefore per-PERSON and not per-ROLE, and the role split is
## recovered from [member ticks_in_tower] against the match duration.

## Match order, as [member MatchParticipant.index].
var index: int = 0

## [member MatchParticipant.display_name], carried through so a result file can
## be read without the roster.
var display_name: String = ""

## HUMAN or AI. Always AI in an unattended bot match; recorded anyway, because a
## mixed match is the obvious next use of this harness and a result file that
## cannot say who was human would be useless for it.
var kind: String = "AI"

## Turns in the tower, as the match counts them for the reload escalation.
var turns_in_tower: int = 0

## Times this participant was granted the seat, including the grant that ends
## the opening race. Equal to [member turns_in_tower] unless the rules reset the
## count on seat loss.
var seat_takes: int = 0

## Rounds held from the tower.
var rounds_won: int = 0

## Physics ticks spent holding the tower. Seconds are derived at serialisation.
var ticks_in_tower: int = 0

## Shots this participant fired, which is to say shots fired while they held the
## tower. There is one rifle and it belongs to the seat.
var shots_fired: int = 0

## Of those, the ones that struck another participant's body.
var shots_hit: int = 0

## Times the rifle converted this participant while they were running.
var times_converted: int = 0

## Laps this participant completed -- every one of which took the tower off
## somebody. Counted from seat grants that were not the opening race.
var laps_finished: int = 0

## Of times_converted, how many were a TrapVolume or the pit rather than the rifle.
var hazard_deaths: int = 0

## Lap fraction the tracker held when the match ended.
var final_progress: float = 0.0

## Of hazard_deaths, those from a KillVolume (fell off) and from a TrapVolume (lava).
var falls: int = 0
var lava_deaths: int = 0

## Windows of 3 s in which the body moved under 1 m while running in the open.
var stalls: int = 0
var max_stall_seconds: float = 0.0

## Longest unbroken HOLD/EVALUATE spell, in seconds.
var max_hold_seconds: float = 0.0

## Times a boost pad launched this body.
var pad_launches: int = 0

## Still a live runner when the harness stopped watching.
var running_at_end: bool = false

## Seconds from each round start to this shooter's first shot, one per seat.
var first_shot_seconds: Array[float] = []



## Fraction of this participant's shots that struck a body, or 0.0 if they never
## fired. Deliberately not "1.0 when untested": an unfired rifle has no hit rate
## and reporting one would be an invented measurement.
func get_hit_rate() -> float:
	if shots_fired <= 0:
		return 0.0
	return float(shots_hit) / float(shots_fired)


func to_dictionary(sim_hz: int) -> Dictionary:
	return {
		"index": index,
		"name": display_name,
		"kind": kind,
		"turns_in_tower": turns_in_tower,
		"seat_takes": seat_takes,
		"rounds_won": rounds_won,
		"ticks_in_tower": ticks_in_tower,
		"seconds_in_tower": float(ticks_in_tower) / float(maxi(sim_hz, 1)),
		"shots_fired": shots_fired,
		"shots_hit": shots_hit,
		"hit_rate": get_hit_rate(),
		"times_converted": times_converted,
		"laps_finished": laps_finished,
		"hazard_deaths": hazard_deaths,
		"final_progress": final_progress,
		"falls": falls,
		"lava_deaths": lava_deaths,
		"stalls": stalls,
		"max_stall_seconds": max_stall_seconds,
		"max_hold_seconds": max_hold_seconds,
		"running_at_end": running_at_end,
		"pad_launches": pad_launches,
		"first_shot_seconds": first_shot_seconds,
	}
