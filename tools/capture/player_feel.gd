extends RefCounted

## B-roll only: seven AI prisoners made to read as seven different people.
##
## A pack of runners armed from one [RunnerProfile] is seven copies of one man.
## On camera that is the tell -- they dare at the same instant, duck at the same
## instant, and the deck moves in lockstep. This hands each seat its own profile
## instead: one of a small cast of temperaments, then a jitter on every number so
## two men of the same temperament still do not move alike.
##
## Nothing here is a balance opinion and nothing here ships. It is a lens on the
## bodies for the length of a take, called once per seat before the round starts:
##
## [codeblock]
## const FEEL := preload("res://tools/capture/player_feel.gd")
## for i: int in runners.size():
##     say(FEEL.apply(runners[i], i, runners.size(), 20260922))
## [/codeblock]
##
## Determinism is the whole contract: (take_seed, index) fixes a persona, so a
## take re-films frame for frame, and a new take_seed re-casts everyone. The cast
## is dealt from the take's seed alone, so which seat is the bold one moves
## between takes while the composition of the pack does not.
##
## [b]The bold one is guaranteed.[/b] The deal cycles the cast in order and the
## bold sprinter is first, so any count >= 1 contains at least one man who keeps
## running with the rifle on him. A shot of a guard killing people needs someone
## in the open to kill.
##
## Why these fields and not others: [RunnerBrain] reads its play through
## [method RunnerProfile.resolve], which prefers the brain's own
## [member RunnerBrain.runner_profile] whenever the round's rules name none, so a
## fresh resource per brain is the whole of the override. Movement lives on
## [BotProfile], which is per-brain and shared by default -- hence the duplicate
## before any knob is touched. [member BotProfile.track_radius] is deliberately
## NOT touched: [MatchController] writes the lane radius over it on every
## placement, and a stage frames its shot on that lane. Personality may change
## how a man runs the lane, never which lane he runs.

## The cast, in deal order. The bold sprinter is index 0 because the deal cycles
## this list, which is what guarantees the shot a killable target.
##
## Every number is a plain-language claim about a man:
##
##   bold sprinter  runs through it. Barely looks at the tower (read error high,
##                  reaction slow to believe it), only a round landing on top of
##                  him moves him, and he takes every hard jump. Long lookahead:
##                  one committed line, no hunting.
##   ducker         wants a wall. Detours far for cover, sits behind it, and
##                  refuses the hard jumps (under 0.5 the brain drops the
##                  hard-jump layer and he walks the long way round).
##   jumpy          believes the tower instantly and wrongly. Short reaction,
##                  sloppy read, any tracer within 16 m is meant for him, and he
##                  bolts out of cover almost as fast as he got in. Twitchy
##                  steering and a short lookahead read as nerves from the tower.
##   steady         the control case: near the resource defaults, so the pack has
##                  an average to make the others look like exceptions.
##   old hand       unhurried and accurate. Reads the guard's attention best of
##                  anyone (smallest error, longest memory) and uses it -- holds
##                  a long minimum, then leaves on a real window rather than a
##                  panic. Wide lazy line.
const CAST: Array[Dictionary] = [
	{
		"name": "bold sprinter",
		"boldness": 0.92, "reach": 6.0, "patience": 0.8, "hold_min": 0.15, "jump": 0.95,
		"reaction": 0.55, "read_error": 22.0, "memory": 0.8, "alarm": 3.0,
		"resample": 0.9, "steering": 8.0, "yaw": 5.0, "lookahead": 5.5,
	},
	{
		"name": "ducker",
		"boldness": 0.12, "reach": 22.0, "patience": 5.5, "hold_min": 1.6, "jump": 0.30,
		"reaction": 0.25, "read_error": 9.0, "memory": 4.0, "alarm": 12.0,
		"resample": 0.3, "steering": 5.0, "yaw": 3.2, "lookahead": 3.2,
	},
	{
		"name": "jumpy",
		"boldness": 0.45, "reach": 14.0, "patience": 1.2, "hold_min": 0.2, "jump": 0.85,
		"reaction": 0.12, "read_error": 18.0, "memory": 2.5, "alarm": 16.0,
		"resample": 0.15, "steering": 11.0, "yaw": 6.5, "lookahead": 2.4,
	},
	{
		"name": "steady",
		"boldness": 0.55, "reach": 12.0, "patience": 3.0, "hold_min": 0.5, "jump": 0.70,
		"reaction": 0.35, "read_error": 14.0, "memory": 1.5, "alarm": 6.0,
		"resample": 0.4, "steering": 6.0, "yaw": 4.0, "lookahead": 4.0,
	},
	{
		"name": "old hand",
		"boldness": 0.30, "reach": 18.0, "patience": 4.0, "hold_min": 0.9, "jump": 0.55,
		"reaction": 0.50, "read_error": 6.0, "memory": 3.0, "alarm": 8.0,
		"resample": 0.6, "steering": 4.5, "yaw": 2.8, "lookahead": 6.0,
	},
]

## Half-width of the jitter on each knob, in the knob's own units.
##
## Sized to separate two men of the same temperament without turning one into
## another: a sprinter at boldness 0.92 +/- 0.06 is still the man who runs
## through it, and a ducker at 0.12 +/- 0.06 still never dares. The wider spreads
## are on the knobs the eye actually reads at 30 m -- how far he detours, how long
## he sits, how hard he corners -- and the tight ones on knobs that flip a
## behaviour rather than shade it (jump confidence crosses the brain's 0.5
## hard-jump threshold, so it moves least).
const JITTER: Dictionary = {
	"boldness": 0.06, "reach": 3.0, "patience": 0.7, "hold_min": 0.12, "jump": 0.05,
	"reaction": 0.06, "read_error": 3.0, "memory": 0.5, "alarm": 2.0,
	"resample": 0.08, "steering": 1.2, "yaw": 0.6, "lookahead": 0.7,
}

## The seat the deal itself draws on: -1, which no real seat can be, so the deal's
## stream cannot collide with any seat's stream.
const DEAL_SEAT: int = -1

## The scramble. Odd 64-bit constants from the usual integer mixers; they are odd
## so the multiply stays invertible and every input bit reaches the high bits.
## GDScript ints are int64 and wrap on overflow, which is exactly what a mixer
## wants. The mask keeps every intermediate non-negative, because a negative seed
## and its masked twin are different streams and only one of them is reproducible
## by hand.
const TAKE_STRIDE: int = 2862933555777941757
const SEAT_STRIDE: int = 2654435761
const MIX_ODD: int = 6364136223846793005
const MASK_63: int = 0x7FFFFFFFFFFFFFFF


## Make one AI prisoner play like its own person, for a capture.
##
## [param index] is the seat, [param count] the size of the pack it is cast in,
## [param take_seed] the take. Returns the one-line persona the stage prints, or
## an empty string if there is no brain to dress.
static func apply(brain: RunnerBrain, index: int, count: int, take_seed: int) -> String:
	if brain == null:
		push_error("player_feel.apply: no brain for seat %d." % index)
		return ""
	var seats: int = maxi(maxi(count, 1), index + 1)
	var seat: int = clampi(index, 0, seats - 1)
	var part: Dictionary = CAST[_deal(seats, take_seed)[seat]]

	# One stream per seat, drawn in a fixed order below, so the same seat of the
	# same take gets the same man however many seats are cast around him.
	var stream: int = _stream_seed(take_seed, seat)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = stream

	# A FRESH profile every time. The resource a scene or a preset hands out is
	# shared by every brain that loads it, and mutating it would cast the whole
	# pack as one man -- the exact fault this file exists to remove.
	var play: RunnerProfile = RunnerProfile.new()
	# All of them watch the tower; boldness, not behaviour, is what makes one of
	# them run through it. BASELINE would blind a man to the rifle entirely, and a
	# man who never reacts is not a person, he is a prop.
	play.behaviour = RunnerProfile.Behaviour.COVER
	play.boldness = _knob(part, "boldness", rng, 0.0, 1.0)
	play.cover_reach_metres = _knob(part, "reach", rng, 1.0, 60.0)
	play.cover_patience_seconds = _knob(part, "patience", rng, 0.0, 30.0)
	play.hold_min_seconds = _knob(part, "hold_min", rng, 0.0, 10.0)
	play.jump_confidence = _knob(part, "jump", rng, 0.0, 1.0)
	play.reaction_seconds = _knob(part, "reaction", rng, 0.0, 3.0)
	play.attention_read_error_degrees = _knob(part, "read_error", rng, 0.0, 90.0)
	play.threat_memory_seconds = _knob(part, "memory", rng, 0.0, 20.0)
	play.tracer_alarm_metres = _knob(part, "alarm", rng, 0.0, 30.0)
	play.attention_resample_seconds = _knob(part, "resample", rng, 0.02, 5.0)
	# Carried on the resource as well as on the brain so that anything reading the
	# profile on its own -- a perception configured straight from it -- draws the
	# same stream rather than falling back to entropy.
	play.perception_seed = stream
	brain.runner_profile = play
	# Non-zero by construction (see [method _stream_seed]), which is what makes the
	# brain prefer it over its seat-index default and keeps two takes apart.
	brain.perception_seed = stream

	# Movement is per-brain but the resource behind it is usually one shared
	# instance; duplicate before touching a knob or seat 0's nerves become
	# everyone's. track_radius and arrival_tolerance are left exactly as placement
	# set them: the lane is the shot's, not the man's.
	var moves: BotProfile = BotProfile.new()
	if brain.profile != null:
		moves = brain.profile.duplicate() as BotProfile
	# How hard he corrects, how fast his hands are, how far ahead he is looking.
	# Together these are the difference between a man on a rail and a man running.
	moves.steering_gain = _knob(part, "steering", rng, 0.1, 30.0)
	moves.max_yaw_rate = _knob(part, "yaw", rng, 0.1, 20.0)
	moves.lookahead_distance = _knob(part, "lookahead", rng, 0.5, 30.0)
	brain.profile = moves

	return "%d %s: boldness %.2f, reach %.1f, patience %.1f, jump %.2f" % [
		seat, String(part["name"]),
		play.boldness, play.cover_reach_metres, play.cover_patience_seconds, play.jump_confidence,
	]


## One knob: the archetype's number, jittered by its own half-width, held inside
## the range the resource exports. Draws exactly one number from [param rng], so
## the order of the calls in [method apply] is part of the determinism.
static func _knob(
	part: Dictionary, key: String, rng: RandomNumberGenerator, low: float, high: float,
) -> float:
	if not part.has(key) or not JITTER.has(key):
		push_error("player_feel: no such knob '%s'." % key)
		return low
	var spread: float = float(JITTER[key])
	return clampf(float(part[key]) + rng.randf_range(-spread, spread), low, high)


## Which archetype each seat plays, for a pack of [param seats] on this take.
##
## The cast is cycled so every temperament appears before any repeats and the
## bold sprinter always appears at all, then shuffled so the bold one is not
## always seat 0. The shuffle draws on the take's seed alone, so every seat
## computes the same deal without anyone having to hold it between calls.
static func _deal(seats: int, take_seed: int) -> PackedInt32Array:
	var deal: PackedInt32Array = PackedInt32Array()
	deal.resize(seats)
	for i: int in seats:
		deal[i] = i % CAST.size()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = _stream_seed(take_seed, DEAL_SEAT)
	# Fisher-Yates, back to front: every ordering equally likely, no bias towards
	# leaving the first-dealt temperaments where they started.
	for i: int in range(seats - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var held: int = deal[i]
		deal[i] = deal[j]
		deal[j] = held
	return deal


## A seat's own stream: the take and the seat folded together and scrambled.
##
## Folding alone is not enough -- take 20260922 seat 3 and take 20260923 seat 2
## would land on the same number, and neighbouring seats would get neighbouring
## streams, which reads as neighbouring men. The shift-multiply-shift is there to
## destroy that neighbourliness. Always odd, therefore never 0, which is the value
## [RunnerBrain] reads as "no seed, use the seat index".
static func _stream_seed(take_seed: int, index: int) -> int:
	var mixed: int = (take_seed * TAKE_STRIDE + (index + 1) * SEAT_STRIDE) & MASK_63
	mixed = ((mixed ^ (mixed >> 29)) * MIX_ODD) & MASK_63
	mixed = (mixed ^ (mixed >> 31)) & MASK_63
	return mixed | 1
