extends RefCounted

## Capture-only: makes a line of live prisoners read as a line of PEOPLE.
##
## The brains are the shipped ones ([RunnerBrain]) running the lap exactly as
## the harness runs them -- nothing here drives a body, and nothing here knows
## about a map. What varies is the [RunnerProfile] each seat is handed and the
## seed it plays from, which is the surface the brain already exposes: one man
## breaks cover early and one sits behind it, one jumps the gaps and one goes
## round, one flinches at a round landing ten metres away and one barely looks
## up. Seeded from the take, so a clip repeats.
##
## Ryan, on the first dailies: "the people hes shooting at are retarded. they
## need to look like real players." A driven lane cannot do that -- it is a rail
## with a weave on it. This hands the playing back to the brain and only varies
## who each man is.
##
## Two calls, from the stage's cast(), in this order:
## [codeblock]
## CAST.vary(brains, seed)              # who each man is
## CAST.restart(brains, points)         # where he starts, and re-arm on the new profile
## [/codeblock]
## [method restart] is not optional. [RunnerBrain.configure] resolves the
## profile once and caches it, and the brains do not exist yet when a stage's
## before_start runs, so a profile set afterwards is read by nobody until the
## brain is armed again. configure() also places the body, which is why there is
## no separate move.
##
## [b]tune_rules must clear the round's profile[/b]: RunnerProfile.resolve gives
## [member MatchRules.ai_runner_profile] priority over the brain's own, so a
## round that exports one hands every seat the same man and everything below is
## ignored. [method free_the_seats] does that on the private rules copy.

## The spread of each dial across the seats. Kept here and not in the stage so
## two shots that both use this layer get the same cast of characters.
const BOLDNESS := Vector2(0.20, 0.95)
const COVER_REACH := Vector2(7.0, 17.0)
const COVER_PATIENCE := Vector2(0.6, 3.6)
const HOLD_MIN := Vector2(0.12, 0.95)
const JUMP_CONFIDENCE := Vector2(0.30, 0.95)
const REACTION := Vector2(0.16, 0.52)
## How near a round has to land before he jukes. The low end is a man who only
## moves when it is close; the high end is one who bolts at anything.
const TRACER_ALARM := Vector2(4.5, 12.0)
const RESAMPLE := Vector2(0.22, 0.62)
const READ_ERROR := Vector2(6.0, 22.0)


## Give every brain in [param brains] its own way of playing. Call it before the
## match starts, because [RunnerBrain.configure] reads the profile once.
static func vary(brains: Array, seed: int) -> void:
	for index: int in brains.size():
		var brain: RunnerBrain = brains[index] as RunnerBrain
		if brain == null:
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("runner-cast:%d:%d" % [seed, index])
		var play: RunnerProfile = _base_of(brain).duplicate(true) as RunnerProfile
		play.behaviour = RunnerProfile.Behaviour.COVER
		play.boldness = rng.randf_range(BOLDNESS.x, BOLDNESS.y)
		play.cover_reach_metres = rng.randf_range(COVER_REACH.x, COVER_REACH.y)
		play.cover_patience_seconds = rng.randf_range(COVER_PATIENCE.x, COVER_PATIENCE.y)
		play.hold_min_seconds = rng.randf_range(HOLD_MIN.x, HOLD_MIN.y)
		play.jump_confidence = rng.randf_range(JUMP_CONFIDENCE.x, JUMP_CONFIDENCE.y)
		play.reaction_seconds = rng.randf_range(REACTION.x, REACTION.y)
		play.tracer_alarm_metres = rng.randf_range(TRACER_ALARM.x, TRACER_ALARM.y)
		play.attention_resample_seconds = rng.randf_range(RESAMPLE.x, RESAMPLE.y)
		play.attention_read_error_degrees = rng.randf_range(READ_ERROR.x, READ_ERROR.y)
		var own: int = hash("runner-seed:%d:%d" % [seed, index]) & 0x7FFFFFFF
		play.perception_seed = own if own != 0 else 1
		brain.runner_profile = play
		brain.perception_seed = play.perception_seed


## Clear the round's one-profile-for-everyone so each brain plays its own.
static func free_the_seats(rules: MatchRules) -> void:
	if rules == null:
		return
	rules.set("ai_runner_profile", null)
	if rules.has_meta(&"ai_runner_profile"):
		rules.remove_meta(&"ai_runner_profile")


## Arm each brain again at [param points], one each, in order: a lap with men
## strung along it rather than a rank abreast, every one of them re-reading the
## profile [method vary] just gave him. The points are the caller's -- this file
## holds no map knowledge -- and so is [param centre], the arena centre the lap
## angles are measured from.
static func restart(brains: Array, points: Array, centre: Vector3 = Vector3.ZERO) -> int:
	var placed: int = 0
	for index: int in mini(brains.size(), points.size()):
		var brain: RunnerBrain = brains[index] as RunnerBrain
		if brain == null or brain.controller == null:
			continue
		brain.configure(centre, points[index], brain._end_point, brain.get_route())
		placed += 1
	return placed


## Every RunnerBrain under [param root], in tree order.
static func brains_under(root: Node) -> Array:
	var found: Array = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is RunnerBrain:
			found.append(node)
		for child: Node in node.get_children():
			stack.append(child)
	found.reverse()
	return found


static func _base_of(brain: RunnerBrain) -> RunnerProfile:
	if brain.runner_profile != null:
		return brain.runner_profile
	return RunnerProfile.new()
