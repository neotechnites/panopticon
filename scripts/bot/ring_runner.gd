class_name RingRunner
extends Node

## The prisoner's brain: the opposite number to [TowerShooter].
##
## It runs one counter-clockwise lap of the ring, and how it runs it is chosen by
## [member RunnerProfile.behaviour]:
##
## - [constant RunnerProfile.Behaviour.COVER], the default, plays the game. It
##   finds real cover in whatever map it has been dropped into, holds it, watches
##   the tower, and breaks for the next piece when it believes the rifle is
##   empty or the guard is looking somewhere else.
## - [constant RunnerProfile.Behaviour.BASELINE] is the original: steer at the
##   next point on a circle and walk, forever, ignoring the tower completely.
##
## [b]Why the baseline is still here[/b]
##
## It is the control case. Every claim about the cover runner -- that it survives
## longer, that it costs the shooter its hit rate, that a difficulty knob does
## anything at all -- is a comparison, and the only honest thing to compare
## against is a prisoner that makes no decisions. Delete it to tidy up and every
## number this project has ever measured about bots becomes an opinion. It is
## also what a runner with no guard on the ring falls back to, because a prisoner
## with nobody watching has nothing to hide from.
##
## [b]The game the cover runner is playing[/b]
##
## Four facts of the design, and the whole brain falls out of them:
##
## - [b]Cover is absolute.[/b] Behind a box you cannot be hit at all -- it is a
##   line-of-sight break, not damage reduction. So the prisoner's problem is
##   never evasion. It is choosing WHEN to cross open ground.
## - [b]The rifle holds one round and the reload is long.[/b] That reload is the
##   window, and the rhythm of it is the rhythm of the round.
## - [b]Every shot draws a tracer.[/b] A shot is information: it says the rifle
##   is now empty, and a round that lands beside you says you were the target.
## - [b]The guard's attention is scarce.[/b] It can see the whole ring but only
##   through a normal field of view, so most of the track is unwatched at any
##   instant.
##
## [b]A state machine, not a planner[/b]
##
## HOLD, EVALUATE, CROSS, RECOVER, and one decision made in one place. It has no
## route, no search over futures and no model of the guard beyond a single
## delayed boolean. That is deliberate: this node is a measuring instrument as
## much as it is a character, and an instrument nobody can read in one sitting
## measures nothing anybody will trust.
##
## [b]Why it drives a PlayerController[/b]
##
## This node never drives motion itself: it never calls [code]move_and_slide[/code]
## and owns no movement numbers. It writes [member CharacterBody3D.velocity] only in
## [method configure], to clear inherited motion when placing the body at spawn. It writes a
## [MoveIntent] into a [BotIntentSource] and the same [PlayerController] that
## carries a human carries it -- same Quake acceleration, same friction, same
## floor snap, same everything. A bot with its own movement code would be
## measuring a system no player ever touches, which would make every bot match
## this project ever runs worthless as evidence. This is the hard rule of the
## file, and it survived the rewrite unchanged: the cover runner strafes and
## sprints through exactly the same seam the baseline walks through.
##
## [b]Why the finish is judged on arc, not on distance to the marker[/b]
##
## [code]PrisonerEnd[/code] is a single point at r=47.5. Runners are spread
## across the 25 m deck so they do not overlap, and one holding r=38.5 sweeps
## past that marker 9 m away. A radius test against the marker would simply
## never fire for it; the runner would walk on into the 4 m LapDivider wall at
## 0 degrees and grind against it until the harness timed out. Arc travelled is
## the only finish condition that means the same thing in every lane -- and the
## cover runner leaves its lane by design, which makes arc the only workable
## measure rather than merely the fairest one.

## Emitted once, on the tick the lap is complete. Carries the runner's own
## telemetry because it is already integrating both for the steering and it
## costs nothing to hand them over.
##
## What finishing [i]means[/i] -- a score, a door opening, a round ending -- is
## deliberately not decided here. This node reports; something else rules.
signal reached_end(elapsed_seconds: float, path_length: float)

## Emitted on every change of behaviour state.
##
## The seam a headless check hooks to ask the question this whole rewrite exists
## to answer: at the instant a runner broke cover, was the rifle reloading? A
## measurement taken from inside the brain could only ever report what the runner
## BELIEVED, which is the one thing that must not be trusted.
signal state_changed(previous: State, current: State)

## Direction of travel around the arena, as a sign on the angle
## [code]atan2(z - centre.z, x - centre.x)[/code].
##
## This is arena canon rather than a tunable, which is why it is a constant and
## not a [BotProfile] field: the ring is run counter-clockwise, from
## PrisonerStart at +5 degrees round to PrisonerEnd at -5 degrees, and the cover
## pieces are numbered 42, 68, 96 ... 330 degrees in that order. It cannot be
## derived from the two markers, because they are only 10 degrees apart and the
## short way between them is the way the LapDivider blocks.
const TRAVEL_SIGN: float = 1.0

## Horizontal speed, in metres per second, under which a recovering runner counts
## as having come to rest. A hair over the movement profile's own friction
## epsilon, so the settle always terminates.
const SETTLED_SPEED: float = 0.35

## Seconds between cover searches while poised to break. Cheap enough to afford
## and far more often than the world changes -- but not every tick, because a
## search is a few hundred raycasts.
const EVALUATE_SEARCH_SECONDS: float = 0.35

## Fraction of the arrival tolerance inside which a holding runner stops
## shuffling. Without it the body hunts about the anchor forever, which reads as
## a nervous tic and costs the shooter a free stationary target.
const HOLD_DEADZONE: float = 0.6

## What the runner is doing. The whole of its behaviour, and small on purpose.
enum State {
	## Not playing the cover game: the baseline lap, or no guard on the ring.
	RUNNING,
	## Behind cover, settling and watching. Not yet willing to leave.
	HOLD,
	## Behind cover, watching, and poised: the crossing decision is being made
	## fresh every tick against a threshold that falls as patience runs out.
	EVALUATE,
	## Committed to a piece of open ground. Facing the destination, which means
	## it cannot see the tower until it arrives -- the price of the sprint.
	CROSS,
	## Just arrived, or just gave up on a crossing. Stopping, re-planning.
	RECOVER,
}

## The body this brain drives. Its [member PlayerController.intent_source] must
## be [member input], or the intent written here goes nowhere.
@export var controller: PlayerController

## The seam through which intent reaches [member controller].
@export var input: BotIntentSource

## Lane and steering tunables. Without one the runner refuses to run rather than
## inventing a lane.
@export var profile: BotProfile

## Difficulty, and the choice of which prisoner this is.
##
## The scene's default. A match overrides it through [MatchRules] -- see
## [method RunnerProfile.resolve] -- which is what lets a headless sweep vary the
## opposition without touching a scene. Null falls back to the baseline lap,
## because a runner with no opinion about how to play should not invent one.
@export var runner_profile: RunnerProfile

## The round's design parameters, when a match supplies them.
##
## Two things are read: [member MatchRules.bot_speed_mode] overrides
## [member BotProfile.speed_mode], and the runner difficulty is resolved from it.
## That is the seam -- "walk or sprint" and "how good are the prisoners" are
## rules of the ROUND and every prisoner in a match obeys the same ones, whereas
## gain, yaw ceiling, lookahead and arrival tolerance are tuning of this one
## brain and stay in [member profile].
##
## Null is normal and means "no match opinion": the profile's own speed mode and
## the scene's own [member runner_profile] are used, which is what a runner
## dropped into a test scene sees. [MatchController] assigns this at spawn.
@export var rules: MatchRules

## Arena centre, at deck height. Set by [method configure].
var _centre: Vector3 = Vector3.ZERO

## Arc from the start angle to the end angle in the travel direction, in
## radians. About 350 degrees, not 360: start and end straddle the LapDivider.
var _finish_arc: float = 0.0

## Arc covered so far, in radians, accumulated tick by tick so that it keeps
## counting past a full turn instead of wrapping back to zero.
var _travelled_arc: float = 0.0

## Last tick's wrapped angle, the term the accumulator differences against.
var _previous_angle: float = 0.0

## Last tick's position, for the path-length integral.
var _previous_position: Vector3 = Vector3.ZERO

var _elapsed_seconds: float = 0.0
var _path_length: float = 0.0

## The difficulty actually in force, resolved once per [method configure] so the
## resolution cost is not paid every tick.
var _play: RunnerProfile = null

var _perception: RunnerPerception = RunnerPerception.new()
var _cover: RunnerCoverFinder = RunnerCoverFinder.new()

var _state: State = State.RUNNING

## Whether a guard was on the ring last tick, so the brain can notice one
## arriving. [MatchController] arms the tower brain after the runners are placed,
## so the first seconds of every round are genuinely guardless.
var _had_threat: bool = false

## Where the runner is holding, or crossing to. At deck height.
var _anchor: Vector3 = Vector3.ZERO
var _has_anchor: bool = false

## Whether the current anchor is real cover the finder proved, or the lane-ahead
## fallback taken when the map has none within reach. A crossing to cover is not
## over until the body is actually hidden; a crossing to open ground is over when
## it arrives, because it will never be hidden and pressing on would walk the
## runner in a circle around a point it has already reached.
var _anchor_is_cover: bool = false

## Seconds spent in the current hold, across HOLD and EVALUATE. The patience
## clock: it is what the break threshold ramps down against.
var _hold_seconds: float = 0.0

## Seconds spent in the current crossing, and what it was budgeted.
var _cross_seconds: float = 0.0
var _cross_budget: float = 0.0

var _search_countdown: float = 0.0

## The spot the current decision is about, whether it is cover or the fallback,
## and how much of the straight line to it stands in the open.
var _target: Vector3 = Vector3.ZERO
var _target_is_cover: bool = false
var _has_target: bool = false
var _exposed_metres: float = 0.0

## The confidence that carried the last crossing, and the threshold it beat.
var _last_confidence: float = 0.0
var _last_threshold: float = 0.0

## Telemetry. Nothing branches on any of it.
var _crossings: int = 0
var _crossings_to_cover: int = 0
var _crossings_believed_safe: int = 0
var _seconds_in_cover: float = 0.0
var _seconds_exposed: float = 0.0


func _ready() -> void:
	# Fail loudly and stand still. A half-configured bot that wanders is far
	# harder to diagnose than one that never moves.
	if controller == null or input == null or profile == null:
		push_error("RingRunner needs a controller, an input and a profile; it will not run.")
		set_physics_process(false)
		return

	# Nothing to do until configure() has placed the body on its lane.
	set_physics_process(false)


## Place the runner on its lane and start it.
##
## [param arena_centre] is the ring's axis at deck height; [param start_point]
## and [param end_point] are the world positions of the PrisonerStart and
## PrisonerEnd markers. Only their angles about the centre are used -- the
## radius comes from [member BotProfile.lane_radius], which is what lets several
## runners share one pair of markers without overlapping.
##
## Call it after the runner is in the scene tree: it writes
## [member Node3D.global_position].
func configure(arena_centre: Vector3, start_point: Vector3, end_point: Vector3) -> void:
	if controller == null or input == null or profile == null:
		return

	_centre = arena_centre
	var start_angle: float = _angle_of(start_point)
	var end_angle: float = _angle_of(end_point)

	# wrapf into [0, TAU) picks the long way round whenever the short way is
	# behind us, which for these two markers is exactly the lap.
	_finish_arc = wrapf((end_angle - start_angle) * TRAVEL_SIGN, 0.0, TAU)

	controller.global_position = _point_on_lane(start_angle)
	controller.velocity = Vector3.ZERO
	# Face straight down the lane. A runner spawned facing the wall would spend
	# its first second turning around, and that second would land in the lap
	# time as if it were running.
	controller.rotation = Vector3(0.0, _heading_of(_lane_tangent(start_angle)), 0.0)

	_previous_angle = start_angle
	_previous_position = controller.global_position
	_travelled_arc = 0.0
	_elapsed_seconds = 0.0
	_path_length = 0.0

	# The round's opinion of the opposition, or the scene's. Resolved here rather
	# than per tick: this is a property-list walk over MatchRules and the answer
	# cannot change inside a round.
	_play = RunnerProfile.resolve(rules, runner_profile)
	_perception.configure(controller, _play, rules)

	_state = State.RUNNING
	_had_threat = false
	_has_anchor = false
	_anchor_is_cover = false
	_anchor = Vector3.ZERO
	_hold_seconds = 0.0
	_cross_seconds = 0.0
	_cross_budget = 0.0
	_search_countdown = 0.0
	_target = Vector3.ZERO
	_target_is_cover = false
	_has_target = false
	_exposed_metres = 0.0
	_last_confidence = 0.0
	_last_threshold = 0.0
	_crossings = 0
	_crossings_to_cover = 0
	_crossings_believed_safe = 0
	_seconds_in_cover = 0.0
	_seconds_exposed = 0.0

	set_physics_process(true)


# --- Readouts -----------------------------------------------------------------

## Seconds since [method configure], frozen once the lap ends.
func get_elapsed_seconds() -> float:
	return _elapsed_seconds


## Metres actually walked, measured in the horizontal plane. Compare it against
## the lane circumference to see how much the steering cost.
func get_path_length() -> float:
	return _path_length


## Fraction of the lap covered, 0.0 at the start pad and 1.0 at the end pad.
func get_progress() -> float:
	if _finish_arc <= 0.0:
		return 0.0
	return clampf(_travelled_arc / _finish_arc, 0.0, 1.0)


func get_state() -> State:
	return _state


## The state as a string, for logs and result files.
func get_state_name() -> String:
	return String(State.keys()[_state])


## The difficulty in force, after [MatchRules] has had its say. Null until
## [method configure].
func get_play_profile() -> RunnerProfile:
	return _play


## What this runner can perceive. Exposed so a headless check can prove the
## gating rather than take it on trust.
func get_perception() -> RunnerPerception:
	return _perception


## True when this runner is playing the cover game rather than the baseline lap.
func is_playing_cover() -> bool:
	return _play != null and _play.plays_cover()


## Crossings begun since [method configure].
func get_crossings() -> int:
	return _crossings


## Of those, how many had real cover on the far side rather than the lane-ahead
## fallback. A runner whose crossings are mostly fallbacks is a runner on a map
## the search cannot read, and it will behave almost exactly like the baseline.
func get_crossings_to_cover() -> int:
	return _crossings_to_cover


## Of those, how many the runner BELIEVED it was starting inside a reload. The
## honest version of this number is measured from outside, off the rifle, on
## [signal state_changed]; this one is what the runner thought it knew.
func get_crossings_believed_safe() -> int:
	return _crossings_believed_safe


## Seconds spent where a shot from the tower could not have reached this body.
func get_seconds_in_cover() -> float:
	return _seconds_in_cover


## Seconds spent where one could.
func get_seconds_exposed() -> float:
	return _seconds_exposed


## The confidence that carried the last crossing, and the threshold it had to
## beat. Together they say whether a break was a decision or an act of patience.
func get_last_break_confidence() -> float:
	return _last_confidence


func get_last_break_threshold() -> float:
	return _last_threshold


## Metres of open ground on the move the runner last decided about. Zero means it
## was not a crossing at all, only a shuffle behind the same piece of cover.
func get_last_exposed_metres() -> float:
	return _exposed_metres


# --- The loop -----------------------------------------------------------------

func _physics_process(delta: float) -> void:
	var position: Vector3 = controller.global_position

	_elapsed_seconds += delta
	# Horizontal only: a step down onto the deck is not progress round the ring.
	_path_length += Vector2(
		position.x - _previous_position.x,
		position.z - _previous_position.z,
	).length()
	_previous_position = position

	# Difference of wrapped angles, re-wrapped to the shortest step. At 11 m/s
	# and r>=36 a physics tick turns at most ~0.005 rad, so this can never
	# mistake a step forward for a step back.
	var angle: float = _angle_of(position)
	_travelled_arc += wrapf((angle - _previous_angle) * TRAVEL_SIGN, -PI, PI)
	_previous_angle = angle

	var remaining_arc: float = _finish_arc - _travelled_arc
	if remaining_arc * profile.lane_radius <= profile.arrival_tolerance:
		_finish()
		return

	if not is_playing_cover():
		_run_baseline(remaining_arc, delta)
		return

	_perception.tick(delta)
	if not _perception.has_threat():
		# Nobody in the tower. A prisoner with nobody watching has nothing to
		# hide from, so it runs -- which is also what keeps the opening race,
		# where there is no shooter at all, a race.
		if _had_threat:
			_had_threat = false
			_set_state(State.RUNNING)
		_run_baseline(remaining_arc, delta)
		return

	if not _had_threat:
		# A guard has just taken the tower. Stop running the lane and start
		# playing: RECOVER is the state that re-plans from wherever the body is.
		_had_threat = true
		_has_anchor = false
		_set_state(State.RECOVER)

	if _perception.is_exposed():
		_seconds_exposed += delta
	else:
		_seconds_in_cover += delta

	match _state:
		State.RECOVER:
			_tick_recover(remaining_arc, delta)
		State.HOLD:
			_tick_hold(remaining_arc, delta)
		State.EVALUATE:
			_tick_evaluate(remaining_arc, delta)
		State.CROSS:
			_tick_cross(remaining_arc, delta)
		_:
			_set_state(State.RECOVER)
			_tick_recover(remaining_arc, delta)


# --- The baseline -------------------------------------------------------------

## Pure pursuit of a point further along the same circle.
##
## The body's wish direction is local-space and the controller yaws the whole
## body, so there is only one way for a bot to go somewhere: turn until it is
## pointing there, and hold forward. That is also how a human plays -- mouse to
## aim, W to move -- which is the point.
func _run_baseline(remaining_arc: float, delta: float) -> void:
	# Never aim past the finish, or the last few metres are run at an angle.
	var lookahead_arc: float = minf(
		profile.lookahead_distance / profile.lane_radius,
		remaining_arc,
	)
	_face(_point_on_lane(_previous_angle + TRAVEL_SIGN * lookahead_arc), delta)

	# Full forward, every tick, unconditionally. Throttling on heading error
	# would be a second control loop and would make lap time a function of
	# steering quality rather than of speed and distance, which is the one thing
	# this baseline exists to report cleanly.
	input.command.move_direction = Vector2(0.0, 1.0)
	input.command.sprint_held = wants_sprint()


# --- The cover game -----------------------------------------------------------

## Stopping, and working out what to do next.
##
## Entered on arrival at cover, on giving up a crossing, and on a guard taking
## the tower. It is a real state rather than a function call because a body that
## has just sprinted 20 m is still carrying 11 m/s, and deciding to hold while
## sliding past the box you meant to hold is how a runner ends up back in the
## open having done nothing.
func _tick_recover(remaining_arc: float, delta: float) -> void:
	_watch_and_hold(delta)

	if _perception.is_exposed():
		# Standing still where the rifle can reach is the one thing a prisoner
		# must never do. Re-plan and go, whatever the confidence says.
		_plan_and_cross(remaining_arc)
		return

	if controller.get_horizontal_speed() > SETTLED_SPEED:
		return

	_hold_seconds = 0.0
	_search_countdown = 0.0
	_set_state(State.HOLD)


## Behind cover, settling. The only thing that happens here is time passing.
func _tick_hold(remaining_arc: float, delta: float) -> void:
	_watch_and_hold(delta)
	_hold_seconds += delta

	if _perception.is_exposed():
		_plan_and_cross(remaining_arc)
		return

	if _hold_seconds >= _play.min_hold_seconds:
		_set_state(State.EVALUATE)


## Behind cover, poised. The decision, made fresh every tick.
func _tick_evaluate(remaining_arc: float, delta: float) -> void:
	_watch_and_hold(delta)
	_hold_seconds += delta

	if _perception.is_exposed():
		_plan_and_cross(remaining_arc)
		return

	_search_countdown -= delta
	if _search_countdown <= 0.0 or not _has_target:
		_search_countdown = EVALUATE_SEARCH_SECONDS
		_choose_target(remaining_arc)

	_last_confidence = _crossing_confidence()
	_last_threshold = _break_threshold()
	if _last_confidence >= _last_threshold:
		_begin_cross(_target, _target_is_cover)


## Committed. Facing the destination and running at it.
##
## Nothing reconsiders in here, and that is the design. Turning to look at the
## tower halfway across would cost the sprint its direction, and a prisoner who
## changes its mind in the middle of the open ground is a prisoner standing in
## the open ground. The commitment is what makes the decision in EVALUATE worth
## making well.
func _tick_cross(_remaining_arc: float, delta: float) -> void:
	_cross_seconds += delta
	_face(_anchor, delta)
	_drive_towards(_anchor, 0.0)
	input.command.sprint_held = _play.sprint_while_crossing or wants_sprint()

	# Arriving is not the same as being behind it. The tolerance lets a runner
	# stop up to a metre and a half short, which on the leading edge of a shadow
	# is still in the open, so a crossing to real cover runs until the world
	# agrees the body is hidden. Only the fallback target -- open ground, which
	# is never hidden -- is finished on distance alone.
	var arrived: bool = _flat_distance(controller.global_position, _anchor) \
		<= _play.cover_arrival_tolerance
	var settled: bool = arrived and (not _anchor_is_cover or not _perception.is_exposed())
	if settled or _cross_seconds >= _cross_budget:
		_set_state(State.RECOVER)


# --- Deciding -----------------------------------------------------------------

## How good this crossing looks, from 0 to 1. The runner's whole opinion of risk,
## in one number, so that a sweep has one thing to move.
##
## Three terms, each in [0, 1], and each a belief rather than a fact:
##
## - [b]The window.[/b] How much of the crossing fits inside the reload the
##   runner believes is left. One means "the rifle cannot possibly be back before
##   I am behind the next box".
## - [b]Attention.[/b] Applied only to the part of the crossing the window does
##   NOT cover, because a reloading rifle cannot fire wherever the guard is
##   looking. This is the whole reason the reload is the rhythm of the game: it
##   is the one thing that makes the guard's attention irrelevant.
## - [b]Exposure.[/b] How much open ground this is at all, falling from 1.0 at
##   [member RunnerProfile.free_crossing_metres] to 0.0 at
##   [member RunnerProfile.max_crossing_metres]. The counterpart of the shooter's
##   range term.
func _crossing_confidence() -> float:
	if _exposed_metres <= 0.0:
		# Not a crossing at all: the whole path runs behind something. Moving up
		# inside your own cover is free and a prisoner should never spend a
		# second of its patience on the decision. This is most of what a good
		# player does between gaps, and pricing it as if it were open ground was
		# what made the first version of this runner creep.
		return 1.0

	var speed: float = maxf(_crossing_speed(), 0.001)
	var open_seconds: float = _exposed_metres / speed

	var window: float = clampf(
		_perception.get_believed_reload_remaining() / open_seconds, 0.0, 1.0
	)

	var attention: float = 1.0
	if _perception.believes_watched():
		attention = _play.watched_confidence_penalty

	var exposure: float = 1.0
	if _exposed_metres > _play.free_crossing_metres:
		var span: float = maxf(
			_play.max_crossing_metres - _play.free_crossing_metres, 0.0001
		)
		exposure = clampf((_play.max_crossing_metres - _exposed_metres) / span, 0.0, 1.0)

	return exposure * (window + (1.0 - window) * attention)


## The confidence a crossing has to beat right now.
##
## [b]Impatience is the thing that stops a round deadlocking.[/b] A ring of
## prisoners who all hide perfectly give the guard nothing to shoot at, which
## gives them no reload to run in, which is a stalemate that ends in a timeout
## and measures nothing. So the threshold falls linearly from
## [member RunnerProfile.break_confidence_threshold] at
## [member RunnerProfile.min_hold_seconds] to zero at
## [member RunnerProfile.max_hold_seconds], and a prisoner that has been pinned
## long enough will take anything. Patient runners survive longer and finish
## slower; that trade is the difficulty curve.
func _break_threshold() -> float:
	var span: float = maxf(_play.max_hold_seconds - _play.min_hold_seconds, 0.0001)
	var patience: float = clampf(
		(_hold_seconds - _play.min_hold_seconds) / span, 0.0, 1.0
	)
	return _play.break_confidence_threshold * (1.0 - patience)


## Commit to [param target].
func _begin_cross(target: Vector3, is_cover: bool) -> void:
	_has_target = false
	_anchor = target
	_has_anchor = true
	_anchor_is_cover = is_cover
	_cross_seconds = 0.0

	var distance: float = _flat_distance(controller.global_position, target)
	# The budget is generous and exists only to notice a crossing that will never
	# finish -- shoved by another prisoner, or caught on a corner. A runner still
	# walking at a spot it cannot reach is the one failure that looks exactly
	# like patience from outside.
	_cross_budget = (distance / maxf(_crossing_speed(), 0.001)) \
		* _play.cross_timeout_multiple + 1.0

	_crossings += 1
	if is_cover:
		_crossings_to_cover += 1
	if _perception.get_believed_reload_remaining() > 0.0:
		_crossings_believed_safe += 1
	_set_state(State.CROSS)


## Re-plan from wherever the body is and go, without asking the confidence.
## Used only where standing still is not an option: in the open.
func _plan_and_cross(remaining_arc: float) -> void:
	_choose_target(remaining_arc)
	_last_confidence = 0.0
	_last_threshold = 0.0
	_begin_cross(_target, _target_is_cover)


## Run a search, settle on a destination, and price the open ground on the way.
##
## Done together and cached, rather than per tick, because the price is a
## raycast per sample and the answer cannot change while the runner stands still.
## What DOES change every tick is the believed reload, which is why the
## confidence is recomputed every tick and this is not.
func _choose_target(remaining_arc: float) -> void:
	_search_cover(remaining_arc)
	_target = _next_target(remaining_arc)
	_target_is_cover = _cover.has_result()
	_exposed_metres = _measure_exposure(_target)
	_has_target = true


## Metres of the straight line to [param target] on which a shot from the tower
## could reach a body.
##
## [b]The number the whole decision turns on.[/b] Length is not risk: sliding
## twenty metres along the back of a wall is free and stepping six metres across
## a gap is not, and a runner that priced both by distance would wait to do the
## first and hurry the second. Sampled against the same line-of-sight test the
## rifle shoots on, so a gap the shooter cannot see through does not count as
## one.
func _measure_exposure(target: Vector3) -> float:
	var from: Vector3 = controller.global_position
	var distance: float = _flat_distance(from, target)
	if distance <= 0.0:
		return 0.0

	var eye: Vector3 = _perception.get_threat_eye()
	var lift: Vector3 = Vector3.UP * _play.cover_test_height
	var samples: int = maxi(_play.path_samples, 2)
	var open: int = 0
	for index: int in samples:
		# Sampled at the midpoints of equal segments, so neither endpoint --
		# each of which is a place the runner has already decided about -- can
		# dominate the answer.
		var fraction: float = (float(index) + 0.5) / float(samples)
		if _perception.has_clear_line(from.lerp(target, fraction) + lift, eye):
			open += 1
	return distance * float(open) / float(samples)


## Where to go next: the cover the last search found, or -- when the map has none
## within reach -- the far end of the search arc on this runner's own lane.
##
## The fallback is not a failure mode, it is the last stretch of every lap. The
## finish line stands in the open by design, and a prisoner that refused to cross
## open ground with no cover on the far side would never finish a round.
func _next_target(remaining_arc: float) -> Vector3:
	if _cover.has_result():
		return _cover.get_position()
	var arc: float = minf(_play.get_cover_search_arc_radians(), maxf(remaining_arc, 0.0))
	return _point_on_lane(_previous_angle + TRAVEL_SIGN * arc)


## Ask the world where the next piece of cover is. See [RunnerCoverFinder]: it
## raycasts, and it is told nothing about this or any other arena.
func _search_cover(remaining_arc: float) -> void:
	var space: PhysicsDirectSpaceState3D = controller.get_world_3d().direct_space_state
	if space == null:
		return
	_cover.search(
		_perception,
		_play,
		space,
		controller.global_position,
		_centre,
		TRAVEL_SIGN,
		profile.lane_radius,
		remaining_arc,
	)


# --- Driving the body ---------------------------------------------------------

## Face the tower and hold station on the anchor.
##
## The runner watches the guard by TURNING TO LOOK AT IT and strafing, which is
## how a human would do it and is the only way the perception gate can be honest:
## the field-of-view test in [RunnerPerception] is taken off this body's head, so
## a runner that faced its destination while holding would be reading a guard it
## was not looking at.
func _watch_and_hold(delta: float) -> void:
	_face(_perception.get_threat_eye(), delta)
	if _has_anchor:
		_drive_towards(_anchor, _play.cover_arrival_tolerance * HOLD_DEADZONE)
	else:
		input.command.move_direction = Vector2.ZERO
	input.command.sprint_held = false


## Turn towards [param point] at this tick's allowed rate.
func _face(point: Vector3, delta: float) -> void:
	var to_target: Vector3 = point - controller.global_position

	# Signed heading error in the horizontal plane: positive means the target is
	# off to the runner's right.
	var forward: Vector3 = -controller.global_transform.basis.z
	var error: float = Vector2(forward.x, forward.z).angle_to(
		Vector2(to_target.x, to_target.z)
	)

	# aim() takes RADIANS PER SECOND and does the per-tick scaling itself.
	# Writing MoveIntent.look_delta here instead would need the value
	# pre-multiplied by delta, and getting that wrong does not raise an error --
	# the yaw aliases past a whole turn every tick and the movement quietly
	# loses speed, which reads as a physics bug and has cost this project time
	# once already. Positive yaw_rate turns right, and positive error means the
	# target is to the right, so the sign passes straight through.
	input.aim(
		clampf(error * profile.steering_gain, -profile.max_yaw_rate, profile.max_yaw_rate),
		0.0,
		delta,
	)


## Walk towards [param point], whatever direction the body happens to be facing.
##
## [member MoveIntent.move_direction] is BODY-LOCAL -- x is the right-hand axis,
## y is forward -- which is what lets a prisoner keep its eyes on the tower and
## still move sideways along the track. It is the same two-axis input a human
## holds on the keyboard, and it is the only thing this brain ever writes.
func _drive_towards(point: Vector3, deadzone: float) -> void:
	var to_target: Vector3 = point - controller.global_position
	var flat: Vector2 = Vector2(to_target.x, to_target.z)
	if flat.length() <= deadzone:
		input.command.move_direction = Vector2.ZERO
		return

	var basis: Basis = controller.global_transform.basis
	var right: Vector2 = Vector2(basis.x.x, basis.x.z)
	var forward: Vector2 = Vector2(-basis.z.x, -basis.z.z)
	input.command.move_direction = Vector2(flat.dot(right), flat.dot(forward)).normalized()


## The ground speed a crossing is planned at, read from the movement profile the
## body actually carries rather than restated here. A brain with its own idea of
## how fast it moves would mis-time every window it ever read.
func _crossing_speed() -> float:
	if controller.profile == null:
		return 1.0
	return controller.profile.get_ground_speed(_play.sprint_while_crossing or wants_sprint())


## Whether to hold sprint on the lane: the match's rule when there is one, the
## profile's mode otherwise. One place, so no caller grows its own idea of it.
func wants_sprint() -> bool:
	if rules != null:
		return rules.wants_sprint()
	return profile.wants_sprint()


func _finish() -> void:
	set_physics_process(false)
	# Release the controls rather than freeze the body: friction brings it to a
	# stop over a metre or so, exactly as letting go of the keys would, and it
	# leaves the LapDivider 4 m ahead untouched.
	input.command.clear()
	reached_end.emit(_elapsed_seconds, _path_length)


func _set_state(next: State) -> void:
	if next == _state:
		return
	var previous: State = _state
	_state = next
	state_changed.emit(previous, _state)


# --- Ring geometry -------------------------------------------------------------

## Angle of a world point about the arena axis, in radians.
func _angle_of(point: Vector3) -> float:
	return atan2(point.z - _centre.z, point.x - _centre.x)


## The point on this runner's lane at the given angle, at deck height.
func _point_on_lane(angle: float) -> Vector3:
	return _centre + Vector3(cos(angle), 0.0, sin(angle)) * profile.lane_radius


## Unit tangent to the lane at the given angle, pointing the way the lap runs.
func _lane_tangent(angle: float) -> Vector3:
	return Vector3(-sin(angle), 0.0, cos(angle)) * TRAVEL_SIGN


## Body yaw, in radians, that points the controller's forward axis along
## [param direction]. Forward is -Z, hence the double negation.
func _heading_of(direction: Vector3) -> float:
	return atan2(-direction.x, -direction.z)


## Horizontal distance between two world points. A step down onto the deck is not
## distance to a spot on it.
func _flat_distance(from: Vector3, to: Vector3) -> float:
	return Vector2(to.x - from.x, to.z - from.z).length()
