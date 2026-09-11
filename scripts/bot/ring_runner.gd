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
## crosses through exactly the same seam the baseline runs through.
##
## [b]And it has the whole kit, not a subset of it[/b]
##
## A prisoner runs, strafes, crouches, slides and jumps, and this brain reaches
## every one of those through [MoveIntent] rather than through a special case:
## [method _maybe_slide] raises [member MoveIntent.slide_pressed] and
## [method _maybe_jump] raises [member MoveIntent.jump_pressed], which are the
## same two fields a keyboard raises. Nothing downstream of the struct can tell
## the difference, which is why the shared costume in [PrisonerAvatar] animates a
## bot's slide and a bot's jump without knowing bots exist. A tool the bots do
## not have is a tool the bot match cannot measure, and one the tuning of the
## human's movement is therefore free to quietly break.
##
## [b]The third mode: the chase[/b]
##
## A prisoner the rifle finishes becomes a GHOST under
## [constant MatchRules.GhostBehaviour.CATCH_AND_SWAP], and a ghost has no lap to
## run. [method begin_chase] switches this brain out of the lap entirely and into
## pursuit, down the track, of the nearest living prisoner AHEAD of it;
## [method end_chase] switches it back off when the ghost takes a spot, the round
## resolves, or the match does.
## It writes the same [MoveIntent] through the same [BotIntentSource], because
## the human's ghost is the human's keyboard through that same seam and a chase
## only bots could run would be a chase nobody could measure. Whether a catch has
## happened is not decided here -- see [method MatchController._tick_ghosts].
##
## [b]Why the finish is judged on arc, not on distance to the marker[/b]
##
## [code]PrisonerEnd[/code] is a single point at r=47.5, and a runner holding the
## track at r=44.5 sweeps past it 3 m away. A radius test against the marker
## would fire late, or not at all for a body that had drifted; the runner would
## walk on into the 4 m LapDivider wall at 0 degrees and grind against it until
## the harness timed out. Arc travelled means the same thing wherever across the
## deck the body happens to be -- and the cover runner leaves the track by
## design, which makes arc the only workable measure rather than merely the
## fairest one.

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

## How close, in metres of horizontal distance, counts as having reached the
## foot of a ramp. Generous on purpose: the foot is a point on a six metre wide
## slab and a runner that arrives anywhere on it can climb.
const RAMP_ARRIVAL_METRES: float = 4.0

## How much of the run-in to a level's exit is spent drifting off the lane and
## out towards the ramp, in metres of arc.
##
## [b]This constant is what makes a bot able to finish the arena.[/b] The
## baseline has no avoidance and no waypoints; all it can do is aim at a circle
## and hold forward. So the ramp is reached by moving the CIRCLE -- gradually,
## over the last twenty metres of the lap, from the level's lane out to the
## ramp's own radius. That is the same steering the bot has always done, aimed
## at a radius that changes. Doing it as a turn at the exit instead would send a
## body radially across the deck at full speed; doing it earlier would run it
## through the cover and traps that the last stretch of every level is
## deliberately clear of.
const RAMP_APPROACH_METRES: float = 20.0

## Radial offsets a runner tries, in order, when the straight line to where it
## wanted to go turns out to have a hole in it. See [method _reachable_target].
const DETOUR_OFFSETS_METRES: Array[float] = [-4.0, 4.0, -8.0, 8.0, -12.0, 12.0]

## Fractions of a refused crossing that are tried before giving up on it.
const SHORTENED_CROSSINGS: Array[float] = [0.5, 0.25, 0.125]

## How far inboard of a deck's inner edge a crossing's chord is allowed to sag,
## in metres. One kerb's width of margin: the kerb is walkable, the void past it
## is not.
const CHORD_MARGIN_METRES: float = 1.5

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
	## it cannot see the tower until it arrives -- the price of the crossing.
	CROSS,
	## Just arrived, or just gave up on a crossing. Stopping, re-planning.
	RECOVER,
}

## The body this brain drives. Its [member PlayerController.intent_source] must
## be [member input], or the intent written here goes nowhere.
@export var controller: PlayerController

## The seam through which intent reaches [member controller].
@export var input: BotIntentSource

## Track and steering tunables. Without one the runner refuses to run rather
## than inventing a track.
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
## What is read is the runner difficulty, resolved from it. That is the seam --
## "how good are the prisoners" is a rule of the ROUND and every prisoner in a
## match obeys the same one, whereas gain, yaw ceiling, lookahead and arrival
## tolerance are tuning of this one brain and stay in [member profile].
##
## Null is normal and means "no match opinion": the scene's own
## [member runner_profile] is used, which is what a runner
## dropped into a test scene sees. [MatchController] assigns this at spawn.
@export var rules: MatchRules

## Arena centre, at deck height. Set by [method configure].
var _centre: Vector3 = Vector3.ZERO

## Whether [member _centre] is a real arena axis rather than the default zero.
##
## Only the chase reads it, and only to decide whether it may reason about the
## ring at all: a ghost made from a body this brain has never armed has no
## geometry to steer round, and steering round a centre it invented would be
## worse than the straight line it falls back to.
var _has_geometry: bool = false

## The route being run: which decks, in what order, with the ramps between them.
## Never null once [method _arm] has run -- a caller with a flat one-lap map
## hands over nothing and gets [method RingRoute.flat], so there is exactly one
## code path here and a flat arena is a route with one level on it.
var _route: RingRoute = null

## Which level of the route this runner is on. Only ever goes up, and only
## through [method _climb_to_the_next_level].
var _level: int = 0

## Where a climb has got to: 0 not climbing, 1 running out to the foot of the
## ramp, 2 on the ramp and heading for the top.
var _ramp_stage: int = 0

## Arc from the current level's entry to its exit in the travel direction, in
## radians. About 344 degrees, not 360: entry and exit straddle the seam the
## ramp trench sits in.
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

## True while this brain is a GHOST hunting the living instead of running a lap.
## See [method begin_chase].
var _chasing: bool = false

## The scene-tree group a chasing ghost draws its quarry from. The match's own
## answer to "who is alive", so the ghost cannot chase a body the round has
## already taken out of play.
var _chase_group: StringName = &""

## Whether a guard was on the ring last tick, so the brain can notice one
## arriving. [MatchController] arms the tower brain after the runners are placed,
## so the first seconds of every round are genuinely guardless.
var _had_threat: bool = false

## Where the runner is holding, or crossing to. At deck height.
var _anchor: Vector3 = Vector3.ZERO
var _has_anchor: bool = false

## Whether the current anchor is real cover the finder proved, or the track-ahead
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

## Whether the crossing now under way was judged worth sliding for. Decided
## once, in [method _begin_cross], and never revisited for the same reason
## nothing else about a crossing is: CROSS faces the destination, so there is
## nothing new to read about the tower until the body arrives.
var _cross_wants_slide: bool = false

## Whether this crossing has already pressed slide. Guards
## [method _maybe_slide] from pressing again every tick the body is still above
## [member MovementProfile.slide_min_entry_speed] -- which would still open only
## one slide, since [PlayerController] latches the buffer on the rising edge,
## but is not the one-press-per-decision discipline this brain owes the rest of
## its output. One press per crossing, and it stays true for the rest of the
## crossing even after the key has been let go.
var _cross_slid: bool = false

## Whether the key is DOWN right now. The other half of [member _cross_slid],
## and separate from it because the press and the release no longer happen at
## the two ends of the crossing -- see [method _tick_slide_release].
var _cross_slide_held: bool = false

## Whether the body has actually been seen sliding on this crossing's press.
## Until it has, the press may still be sitting in
## [member MovementProfile.slide_buffer_time] waiting for the floor or the
## cooldown, and letting go would throw it away.
var _cross_slide_open: bool = false

## Seconds since this crossing's press, so a press that never opens anything can
## be given up on rather than held for the rest of the crossing.
var _cross_slide_seconds: float = 0.0

## Seconds until this runner may press jump again. See
## [member RunnerProfile.jump_cooldown_seconds]: the brain never HOLDS jump, so
## nothing else stops one hop from running into the next.
var _jump_cooldown: float = 0.0

## How long the body has been asking to move and going nowhere against
## something solid. The unstick timer -- see [method _maybe_jump].
var _blocked_seconds: float = 0.0

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
var _slides_attempted: int = 0
var _jumps: int = 0


func _ready() -> void:
	# Fail loudly and stand still. A half-configured bot that wanders is far
	# harder to diagnose than one that never moves.
	if controller == null or input == null or profile == null:
		push_error("RingRunner needs a controller, an input and a profile; it will not run.")
		set_physics_process(false)
		return

	# Nothing to do until configure() has placed the body on the track.
	set_physics_process(false)


## Put the runner down at [param start_point] and start it.
##
## [param arena_centre] is the ring's axis at deck height; [param start_point] is
## where the body is placed, and [param end_point] is the world position of the
## PrisonerEnd marker, of which only the angle about the centre is used.
##
## The body is placed AT the start point rather than at
## [member BotProfile.track_radius] on the start point's angle, because a whole
## field starts on one line and the caller is the only thing that knows where
## along that line this one stands. The runner steers back onto the track from
## wherever it was put down.
##
## Call it after the runner is in the scene tree: it writes
## [member Node3D.global_position].
## [param route] is the run itself -- see [RingRoute]. Null is the flat-map case
## and builds a one-level route from [member BotProfile.track_radius] and the two
## markers, which is exactly the lap this brain ran before the arena had levels.
func configure(
	arena_centre: Vector3,
	start_point: Vector3,
	end_point: Vector3,
	route: RingRoute = null,
) -> void:
	if controller == null or input == null or profile == null:
		return

	var start_angle: float = _angle_of_about(arena_centre, start_point)
	controller.global_position = start_point
	controller.velocity = Vector3.ZERO
	# Face straight down the track. A runner spawned facing the wall would spend
	# its first second turning around, and that second would land in the lap
	# time as if it were running.
	controller.rotation = Vector3(0.0, _heading_of(_track_tangent(start_angle)), 0.0)

	# The anchor is handed over rather than re-derived from the body. It is the
	# angle the body was just placed at -- the lateral offset along the start
	# line is radial and does not move it -- and atan2 of the sine and cosine of
	# an angle is that angle only to within an ULP or two, which is not worth
	# introducing into a code path that used to be exact.
	_arm(arena_centre, start_point, end_point, 0.0, start_angle, route, 0)


## Start running from WHERE THE BODY ALREADY IS, [param travelled_arc] radians
## into the lap. The body is not moved and not turned.
##
## For the ghost swap: a ghost that catches a living prisoner takes their spot
## and starts running the ring from the ground it is standing on. Calling
## [method configure] there would teleport the new prisoner back to the start
## pad, which is not a swap -- and, worse, is a kinematic body being moved 300 m
## with its collision live. See [method MatchController._hold_body] for what
## that costs.
func resume(
	arena_centre: Vector3,
	start_point: Vector3,
	end_point: Vector3,
	travelled_arc: float,
	route: RingRoute = null,
	level: int = 0,
) -> void:
	if controller == null or input == null or profile == null:
		return
	# The chase's standing orders are dropped here and not in [method _arm]: a
	# lap that is being ARMED has always kept whatever was in the command, and
	# the tick that follows overwrites it anyway. Clearing it there too would be
	# a change to the ghostless round for no reason.
	input.command.clear()
	_arm(
		arena_centre,
		start_point,
		end_point,
		travelled_arc,
		_angle_of_about(arena_centre, controller.global_position),
		route,
		level,
	)


## Everything [method configure] and [method resume] share: the lap geometry, the
## accumulators, the resolved difficulty and a clean state machine.
##
## [param anchor_angle] is the angle the arc accumulator differences its first
## tick against -- the start line's angle after a configure, and the angle the
## body is standing at after a resume. It is a parameter rather than a
## measurement so that the configure path is arithmetically the code it was
## before the chase existed.
func _arm(
	arena_centre: Vector3,
	start_point: Vector3,
	end_point: Vector3,
	travelled_arc: float,
	anchor_angle: float,
	route: RingRoute,
	level: int,
) -> void:
	_centre = arena_centre
	_has_geometry = true

	# One route object per armed brain, and this brain owns the fallback it
	# builds: parenting it means it is freed with the runner instead of leaking
	# a Node per placement, and a re-arm frees the last one first.
	if _route != null and _route.get_parent() == self:
		_route.queue_free()
	_route = route
	if _route == null:
		_route = RingRoute.flat(profile.track_radius, arena_centre, start_point, end_point)
		add_child(_route)
	_level = clampi(level, 0, _route.last_index())
	_ramp_stage = 0
	_finish_arc = _route.lap_arc(_level)

	_chasing = false
	_previous_angle = anchor_angle
	_previous_position = controller.global_position
	_travelled_arc = travelled_arc
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
	_cross_wants_slide = false
	_cross_slid = false
	_cross_slide_held = false
	_cross_slide_open = false
	_cross_slide_seconds = 0.0
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
	_slides_attempted = 0
	_jumps = 0
	_jump_cooldown = 0.0
	_blocked_seconds = 0.0

	set_physics_process(true)


# --- The chase ----------------------------------------------------------------

## Stop running the ring and start hunting the nearest body in
## [param target_group].
##
## [b]This is the ghost's whole brain, and it is deliberately the dumbest thing
## that could work.[/b] A ghost has no lap, no cover game and no opinion about
## the guard -- it cannot be shot, so nothing it could hide from can reach it.
## What it has is one job: close on a living prisoner. So it steers at the
## nearest one exactly the way the baseline steers at the next point on the
## track, through the same [MoveIntent], into the same [PlayerController].
##
## [b]It does not decide anything.[/b] Whether the ghost has actually CAUGHT
## anybody is [MatchController]'s ruling, made off the catch radius in
## [GhostProfile], for the human and the bot alike -- exactly as this brain
## reports a finished lap and rules nothing about what it is worth. A brain that
## called the catch would be a catch only bots could make.
func begin_chase(target_group: StringName) -> void:
	if controller == null or input == null or profile == null:
		return
	_chase_group = target_group
	_chasing = true
	_state = State.RUNNING
	input.command.clear()
	set_physics_process(true)


## Stop chasing and drop the controls. Called when a ghost becomes living again,
## when the round ends, and when the match does.
func end_chase() -> void:
	if not _chasing:
		return
	_chasing = false
	input.command.clear()
	set_physics_process(false)


## True while this brain is hunting rather than running the ring.
func is_chasing() -> bool:
	return _chasing


## The body this ghost is currently closing on, or null when there is nobody in
## the group to chase. Exposed so a headless check can prove the chase is aimed
## at somebody rather than merely moving.
func get_chase_target() -> Node3D:
	if not _chasing or controller == null:
		return null
	return _nearest_ahead()


## Where the chase is steering this tick: a point on the ring ahead of the ghost,
## which is the quarry's own position once it is within a lookahead. Exposed so a
## headless check can prove a ghost is aimed DOWN THE TRACK rather than across
## the pit at it.
##
## The body's own position when there is nobody to chase, which is the honest
## answer -- a ghost with no quarry is steering nowhere and
## [method _tick_chase] writes it no direction at all. Ask
## [method get_chase_target] to tell that case from a quarry underfoot.
func get_chase_aim_point() -> Vector3:
	var quarry: Node3D = get_chase_target()
	if quarry == null:
		return controller.global_position if controller != null else Vector3.ZERO
	return _chase_aim_point(quarry.global_position)


# --- Readouts -----------------------------------------------------------------

## Seconds since [method configure], frozen once the lap ends.
func get_elapsed_seconds() -> float:
	return _elapsed_seconds


## Metres actually walked, measured in the horizontal plane. Compare it against
## the track's circumference to see how much the steering cost.
func get_path_length() -> float:
	return _path_length


## Fraction of the WHOLE ROUTE covered, 0.0 at the start pad and 1.0 at the end
## pad -- every level, weighted by its own lane radius, exactly as
## [method MatchLapTracker.get_progress] weights it. A single-level route makes
## this the lap fraction it always was.
func get_progress() -> float:
	if _route == null:
		return 0.0 if _finish_arc <= 0.0 else clampf(_travelled_arc / _finish_arc, 0.0, 1.0)
	return _route.progress(_level, _travelled_arc)


## Which level of the route this runner is on, 0 for the first. Telemetry, and
## what a headless check asks to prove a bot actually climbed.
func get_level() -> int:
	return _level


## Arc swept on the current level, in radians. What a ghost swap carries over.
func get_travelled_arc() -> float:
	return _travelled_arc


## The route this brain is running. Null until it has been armed.
func get_route() -> RingRoute:
	return _route


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


## Of those, how many had real cover on the far side rather than the track-ahead
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


## Crossings on which the runner actually pressed slide, of [member _crossings]
## begun. Telemetry: nothing branches on it. Compare against
## [method get_crossings] to see how often a crossing judged worth sliding for
## actually got fast enough to open one.
func get_slides_attempted() -> int:
	return _slides_attempted


## Times the runner pressed jump this lap, from either trigger. Telemetry:
## nothing branches on it, and it is here so that a match that wants to know
## whether hopping ever fired can ask rather than watch for it.
func get_jumps() -> int:
	return _jumps


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
	if _chasing:
		_tick_chase(delta)
		return

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
	var swept: bool = remaining_arc * _lane_radius() <= profile.arrival_tolerance

	if _route.has_level_above(_level):
		# The lap is run; what is left of this level is the climb. The cover
		# game does not run on a ramp and does not need to: the ramp carries a
		# wall along its whole tower-facing edge, so the climb IS cover, and a
		# runner that stopped halfway up to evaluate would be standing on the
		# one piece of ground it cannot leave sideways.
		if _ramp_stage > 0 or swept:
			_tick_ramp(delta)
			return
	elif swept:
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
		# Nobody is watching, so there is nothing tactical to hop for -- but the
		# route still has ramps and kerbs in it, and _maybe_jump's other trigger
		# is what gets a snagged body over one. It is only reached from here and
		# from the tail of the state machine below, so the BASELINE lap, which
		# returned above, never sees it.
		_maybe_jump(delta)
		return

	if not _had_threat:
		# A guard has just taken the tower. Stop running the track and start
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

	# After the state has had its say, so that what is tested is this tick's
	# intent -- the move direction _drive_towards just wrote, and the state
	# _tick_cross may just have left.
	_maybe_jump(delta)


## Run down the nearest living prisoner ahead, along the track.
##
## No interception lead and no throttle on heading error: both would make the
## catch a function of how well this brain was tuned rather than of the one
## number the mechanic is actually about, which is how much faster a ghost is
## than the living.
##
## [b]It runs the course, and it never turns round.[/b] The one thing that was
## added to pure pursuit is the ring itself -- see [method _chase_aim_point] and
## [method _nearest_ahead] -- and it was added because on a ring pure pursuit is
## not the honest instrument the paragraph above claims. Two reasons, and the
## second is the one that matters:
##
## - [b]The straight line is not a path.[/b] The deck is an annulus and the
##   middle of it is a pit. Any quarry more than a quarter of a lap away sits
##   across that hole, so "steer at the body" steers a ghost into the inner kerb
##   and leaves it grinding along it, in whichever direction the wall happens to
##   deflect it. Past the halfway point that direction is backwards, which is
##   what the ring's ghosts were actually observed doing.
## - [b]A head-on catch measures nothing.[/b] The speed multiplier is the whole
##   of the mechanic: give a ghost an advantage and it closes, take it away and
##   it never does. That sentence is only true of a STERN chase. A ghost allowed
##   to run the wrong way round meets its quarry head-on at the sum of the two
##   speeds, and catches it at any multiplier at all, including one below 1.0 --
##   the dial goes dead and the round is decided by which way round the ring the
##   two of them happened to be standing.
func _tick_chase(delta: float) -> void:
	var quarry: Node3D = _nearest_ahead()
	if quarry == null:
		# Nobody left to chase -- every prisoner is a ghost, or the round is
		# between placements. Stand still rather than wander: the match is about
		# to resolve or re-place this body either way.
		input.command.move_direction = Vector2.ZERO
		return

	var aim: Vector3 = _chase_aim_point(quarry.global_position)
	_face(aim, delta)
	_drive_towards(aim, 0.0)


## Where a chasing ghost actually steers: a point on the ring, [member
## BotProfile.lookahead_distance] further round it in the direction of play, at
## the radius the closing is worth by then.
##
## Exactly the baseline's steering, aimed at a body instead of at a fixed arc,
## and it degenerates into plain pure pursuit as the gap closes: the step is
## capped by the arc to the quarry, so once the ghost is within a lookahead of
## them the step IS the whole gap and the returned point is the quarry's own
## position. Nothing about the last few metres of a catch is therefore
## approximate; the ring only shapes the long approach, which is the only part
## of it a straight line got wrong.
##
## The radius is interpolated by the fraction of the gap this step covers rather
## than held at the track's, so a ghost converges on the quarry's lane instead of
## running the track past a prisoner who is holding cover two metres inboard of
## it -- and, because the ghost's own radius is the other end of that
## interpolation, a ghost dealt onto the start line at r=47.5 stays on the deck
## the whole way instead of cutting for the track first.
func _chase_aim_point(quarry: Vector3) -> Vector3:
	if not _has_geometry:
		# No ring to run round: steer at the body, which is what this did before
		# the ring was taken into account and is still right on a flat map.
		return quarry

	var here: Vector3 = controller.global_position

	# A quarry on a higher deck cannot be run at. The route is the only way up,
	# so the ghost is pointed at the ramp instead and the pursuit carries on
	# against THAT point -- same arc, same lookahead, same convergence. Once it
	# is standing at the foot it commits to the top, which is the one place on
	# the route where aiming along the ring would be wrong.
	var my_level: int = _route_level_of(here)
	if _route != null and _route_level_of(quarry) > my_level:
		if _flat_distance(here, _route.ramp_foot(_centre, my_level)) <= RAMP_ARRIVAL_METRES:
			return _route.ramp_top(_centre, my_level)
		quarry = _route.ramp_foot(_centre, my_level)

	var here_angle: float = _angle_of(here)
	var here_radius: float = maxf(_radius_of(here), 0.001)
	# Wrapped into [0, TAU) in the direction of travel, so it is the arc the
	# ghost would run FORWARD to reach them -- never the short way backwards.
	var gap_arc: float = wrapf((_angle_of(quarry) - here_angle) * TRAVEL_SIGN, 0.0, TAU)
	var step_arc: float = minf(profile.lookahead_distance / here_radius, gap_arc)

	var fraction: float = 1.0 if gap_arc <= 0.0 else step_arc / gap_arc
	var radius: float = lerpf(here_radius, _radius_of(quarry), fraction)
	var angle: float = here_angle + TRAVEL_SIGN * step_arc
	return Vector3(_centre.x + cos(angle) * radius, here.y, _centre.z + sin(angle) * radius)


## The living prisoner this ghost is hunting: the one the least arc AHEAD of it,
## the way the lap runs. Null when the group is empty.
##
## [b]Ahead, not nearest.[/b] Measuring the field by straight-line distance is
## what pointed a ghost backwards in the first place -- across the pit, at
## whoever happened to be nearest through it -- and it is wrong for the same
## reason [method _tick_chase] gives: the ghost cannot travel that line, and if
## it could, the catch would stop being about the speed multiplier. Arc in the
## direction of play is the distance a ghost can actually cover, so it is the
## distance it chooses on.
##
## A prisoner a few degrees BEHIND the ghost therefore reads as almost a full lap
## away and is not chased, which is deliberate and costs nothing: a catch is
## ruled on a radius by [method MatchController._tick_ghosts], not by this
## brain, so a prisoner the ghost is standing next to is caught whether or not
## the ghost was aiming at them.
##
## The group is read fresh every tick rather than cached, because membership is
## exactly what a swap changes: the prisoner this ghost just caught leaves it in
## the same frame, and a cached quarry would be chased for a tick after they
## stopped being one.
func _nearest_ahead() -> Node3D:
	if _chase_group == StringName(""):
		return null
	var here: Vector3 = controller.global_position
	var here_metres: float = _route_metres_of(here)
	var route_length: float = 0.0 if _route == null else _route.total_metres()
	var best: Node3D = null
	var best_cost: float = 0.0
	for node: Node in controller.get_tree().get_nodes_in_group(_chase_group):
		var body: Node3D = node as Node3D
		if body == null or body == controller:
			continue
		# Off the ring, the route means nothing and the straight line is all
		# there is. Same fallback as [method _chase_aim_point], for the same
		# reason.
		var cost: float = _flat_distance(here, body.global_position)
		if _has_geometry and _route != null:
			# Metres of ROUTE ahead, not arc: with three decks stacked at the
			# same angles, an arc no longer says who is in front. A prisoner one
			# level up is ahead of a ghost on the deck below even when the two
			# of them are standing on the same bearing.
			cost = _route_metres_of(body.global_position) - here_metres
			if cost < 0.0:
				cost += route_length
		if best == null or cost < best_cost:
			best = body
			best_cost = cost
	return best


## How far along the route a world point is, in metres. The chase's ordering,
## and the one measurement that survives a second deck at the same bearing.
func _route_metres_of(point: Vector3) -> float:
	if _route == null:
		return 0.0
	var level: int = _route_level_of(point)
	var swept: float = wrapf(
		(_angle_of(point) - _route.entry_angle(level)) * TRAVEL_SIGN, 0.0, TAU
	)
	return _route.metres_travelled(level, swept)


## The level of the route a world point is standing on.
func _route_level_of(point: Vector3) -> int:
	return 0 if _route == null else _route.level_for_height(point.y)


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
		profile.lookahead_distance / _lane_radius(),
		maxf(remaining_arc, 0.0),
	)
	var aim_angle: float = _previous_angle + TRAVEL_SIGN * lookahead_arc
	_face(_point_on_level(aim_angle, _aim_radius(remaining_arc - lookahead_arc)), delta)

	# Full forward, every tick, unconditionally. Throttling on heading error
	# would be a second control loop and would make lap time a function of
	# steering quality rather than of speed and distance, which is the one thing
	# this baseline exists to report cleanly.
	input.command.move_direction = Vector2(0.0, 1.0)


# --- The climb ----------------------------------------------------------------

## Run out to the foot of the ramp, then up it.
##
## Two waypoints and no cleverness, which is the whole point: Ryan asked for "a
## simple ramp from one to the next" and a bot that needed a path-finder to use
## one would mean the arena was wrong, not that the bot was. The foot is reached
## by the same steering everything else here uses -- face it, hold forward -- and
## the body is already most of the way out to it because
## [method _run_baseline] has spent the last twenty metres drifting the lane
## outwards. See [constant RAMP_APPROACH_METRES].
##
## The climb ends on HEIGHT, not on arriving at the top marker. A runner shoved
## off the top of the ramp by another body, or one that crests it two metres
## wide of the mark, is still up; making it walk to a point first would leave it
## circling on the deck it had already reached.
func _tick_ramp(delta: float) -> void:
	var here: Vector3 = controller.global_position

	if _route.is_standing_on(_level + 1, here.y):
		_climb_to_the_next_level()
		return

	if _ramp_stage == 0:
		_ramp_stage = 1
	if _ramp_stage == 1:
		var foot: Vector3 = _route.ramp_foot(_centre, _level)
		if _flat_distance(here, foot) > RAMP_ARRIVAL_METRES:
			_face(foot, delta)
			_drive_towards(foot, 0.0)
			return
		_ramp_stage = 2

	var top: Vector3 = _route.ramp_top(_centre, _level)
	_face(top, delta)
	_drive_towards(top, 0.0)


## Bank the level and start the next lap from where the body is standing.
##
## The arc accumulator is reset and re-anchored rather than carried. A climb
## sweeps forward past the level's exit, and carrying that overshoot would
## credit the ramp's own arc twice -- once as the tail of the lap below and once
## as the head of the lap above. [MatchLapTracker] does the same thing for the
## same reason, and the two agree because they are the same rule written twice
## on purpose: the brain steers by it, the tracker scores by it, and neither is
## allowed to be the other's authority.
func _climb_to_the_next_level() -> void:
	_level = mini(_level + 1, _route.last_index())
	_ramp_stage = 0
	_finish_arc = _route.lap_arc(_level)
	_travelled_arc = 0.0
	_previous_angle = _angle_of(controller.global_position)
	_has_anchor = false
	_has_target = false
	_anchor_is_cover = false
	_set_state(State.RUNNING)


# --- The cover game -----------------------------------------------------------

## Stopping, and working out what to do next.
##
## Entered on arrival at cover, on giving up a crossing, and on a guard taking
## the tower. It is a real state rather than a function call because a body that
## has just crossed 20 m is still carrying 11 m/s, and deciding to hold while
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
## tower halfway across would cost the crossing its direction, and a prisoner who
## changes its mind in the middle of the open ground is a prisoner standing in
## the open ground. The commitment is what makes the decision in EVALUATE worth
## making well.
func _tick_cross(_remaining_arc: float, delta: float) -> void:
	_cross_seconds += delta
	_face(_anchor, delta)
	_drive_towards(_anchor, 0.0)
	_maybe_slide()
	_tick_slide_release(delta)

	# Arriving is not the same as being behind it. The tolerance lets a runner
	# stop up to a metre and a half short, which on the leading edge of a shadow
	# is still in the open, so a crossing to real cover runs until the world
	# agrees the body is hidden. Only the fallback target -- open ground, which
	# is never hidden -- is finished on distance alone.
	var arrived: bool = _flat_distance(controller.global_position, _anchor) \
		<= _play.cover_arrival_tolerance
	var settled: bool = arrived and (not _anchor_is_cover or not _perception.is_exposed())
	if settled or _cross_seconds >= _cross_budget:
		# Let go of the key, if [method _tick_slide_release] has not already. It
		# usually has -- a slide is a second and a crossing is longer -- and
		# what is left for this to catch is the crossing that ends WHILE the
		# body is still sliding: the commitment was to THIS crossing, and
		# RECOVER is a new decision. Either way, the release is what lets the
		# NEXT crossing's press register as a fresh edge:
		# [method BotIntentSource.hold_slide] only raises
		# [member MoveIntent.slide_pressed] on a rising edge of the held flag,
		# and a held flag nobody lowered never rises again.
		if _cross_slide_held:
			input.hold_slide(false)
			_cross_slide_held = false
		_set_state(State.RECOVER)


## Press slide, once, the instant this crossing is both worth it and fast
## enough to open one -- and hold it, because [member MovementProfile.slide_requires_hold]
## is on and [PlayerController] ends a slide the same tick it opens if the hold
## goes unanswered.
##
## [b]Why [method BotIntentSource.hold_slide] and not a bare press[/b]
##
## [method PlayerController._update_slide_exit] runs at the end of every tick,
## after [method PlayerController._try_begin_slide] can have opened one, and
## checks [member MoveIntent.slide_held] before the timer or the speed floor
## ever get a say. A bot that set [member MoveIntent.slide_pressed] alone -- the
## edge [method BotIntentSource.poll] hands out for exactly one tick -- would
## leave [member MoveIntent.slide_held] false, and the slide it just opened
## would close again on that same tick's exit check: a real state transition
## that no render frame ever samples as true, which reads from outside as no
## slide at all. [method BotIntentSource.hold_slide] sets both: the edge, once,
## on the tick [member MoveIntent.slide_held] rises from false to true, and the
## level, which [method BotIntentSource.poll] leaves alone so it persists tick
## to tick the way a device's held key does. This brain still only presses
## once -- see [member _cross_slid] -- and still lets go once, in
## [method _tick_cross], which is what re-arms the edge for the next crossing.
##
## [member MovementProfile.slide_min_entry_speed] is read off the body's own
## profile rather than restated here, for the same reason [method _crossing_speed]
## does: a brain with its own idea of the body's numbers would mistime them.
func _maybe_slide() -> void:
	if not _cross_wants_slide or _cross_slid or controller.is_sliding():
		return
	if controller.profile == null:
		return
	if controller.get_horizontal_speed() < controller.profile.slide_min_entry_speed:
		return
	# The OTHER half of what [method PlayerController._press_asks_for_a_slide]
	# tests, and it has to be asked here for the same reason the speed floor
	# does: this brain presses ONCE per crossing, so a press the controller
	# reads as a crouch is a crossing that never slides.
	#
	# The number is read off the body's own profile rather than restated, and
	# the vector is this tick's -- [method _tick_cross] has already written it
	# through [method _drive_towards] -- so what is tested here is exactly what
	# the controller will test, not a brain's guess at it.
	#
	# [b]Why waiting is right and the buffer is not enough.[/b]
	# [method _tick_cross] faces the anchor and drives at it on the same tick,
	# so [member MoveIntent.move_direction] is only near-forward once the yaw
	# has caught up with the turn -- and a crossing entered at speed can begin
	# with the body pointed most of a half-turn away. A press made then falls
	# through to the crouch and leaves [member MovementProfile.slide_buffer_time]
	# (0.12 s) to carry it, which at [member BotProfile.max_yaw_rate] closes
	# less than half a radian: enough for a small correction, nowhere near
	# enough for a real turn, and the press is silently spent either way. So the
	# press waits for the heading instead of gambling on the buffer. Nothing is
	# lost by waiting -- [member _cross_wants_slide] stays true for the whole
	# crossing, and the body is at crossing speed the entire time.
	if input.command.move_direction.y < controller.profile.slide_min_forward_intent:
		return
	input.hold_slide(true)
	_cross_slid = true
	_cross_slide_held = true
	_cross_slide_open = false
	_cross_slide_seconds = 0.0
	_slides_attempted += 1


## Let go of the slide key the moment the SLIDE ends, rather than when the
## crossing does.
##
## [b]Why this exists.[/b] The key does two things, and which one depends
## entirely on how long it has been down. A slide runs
## [member MovementProfile.slide_max_duration] -- a second -- and then
## [method PlayerController._update_slide_exit] closes it on the timer. The
## crouch has no timer: it is a held state, so the instant the slide's second is
## spent, a key still down stops being a slide and legitimately becomes a
## CROUCH, at [member MovementProfile.crouch_speed], well under walking pace.
## A bot that held the key to the end of its crossing therefore slid for the
## first second and crouch-walked the rest of it -- slowly, in the open, on the
## one stretch of ground where being slow is what gets a prisoner shot. Measured
## on the PC, not reasoned about: 59 ticks of slide followed by 180 ticks of
## crouch.
##
## [b]Why not simply press without holding.[/b] Because
## [member MovementProfile.slide_requires_hold] is on and a slide with nobody
## holding the key closes on the same tick it opens. The hold is required; what
## was wrong was its LENGTH. So the key goes down for exactly the slide and
## comes up the tick the body stops sliding, and the body is the thing asked --
## [method PlayerController.is_sliding], the same state the exit check rules on.
##
## [b]The press that never opens anything.[/b] Speed and forward intent are
## checked before pressing, but the cooldown is not, so a press can still land
## on a tick that cannot open a slide. Its edge then sits in
## [member MovementProfile.slide_buffer_time] hoping for a tick that can, and
## letting go before that window is spent would throw the press away. Once it IS
## spent, the press is dead and the key is doing nothing but crouching, so it
## comes up. Both numbers are read off the body's own profile, for the reason
## every number in this brain is.
func _tick_slide_release(delta: float) -> void:
	if not _cross_slide_held or controller.profile == null:
		return
	_cross_slide_seconds += delta

	if controller.is_sliding():
		_cross_slide_open = true
		return

	# Not sliding: either the slide is over, or it never began.
	if _cross_slide_open or _cross_slide_seconds >= controller.profile.slide_buffer_time:
		input.hold_slide(false)
		_cross_slide_held = false



# --- Jumping ------------------------------------------------------------------

## Decide whether to hop this tick, and press jump if so.
##
## [b]The runner presses, and never holds.[/b] That one choice is most of what
## this function is. [member MovementProfile.auto_bunny_hop] is on, so
## [method PlayerController._try_jump] re-launches on the landing tick for as
## long as [member MoveIntent.jump_held] is true: a bot that held the key would
## chain hops down the whole crossing with about four ticks of floor in every
## hundred and eighty, which costs it ground acceleration for the entire
## distance and -- worse -- never leaves the floor under it long enough for
## [method PlayerController._try_begin_slide] to open anything. Holding jump
## would quietly delete the slide, which is the better tool. So this raises
## [member MoveIntent.jump_pressed] alone, once, exactly as
## [method _maybe_slide] presses once per crossing, and
## [member RunnerProfile.jump_cooldown_seconds] is the wait before it may again.
##
## [b]The two triggers, and why neither is a die roll.[/b] A hop buys two things
## and costs one. It buys the friction that is NOT applied on the tick a body
## leaves the ground -- see the comment in
## [method PlayerController._physics_process], where skipping ground friction on
## the launch frame is called out as the whole of why a bunny hop keeps its
## speed -- and it buys a body that is not on the line a rifle led along the
## floor. It costs steering: [method PlayerController._air_accelerate] is a far
## weaker instrument than the ground one. So:
##
## 1. [b]Crossing open ground.[/b] Only in [constant State.CROSS], only after
##    this crossing's slide has had its chance, only with
##    [member RunnerProfile.jump_min_remaining_metres] still to run, and only
##    where a hop buys one of the two things above: SURPLUS SPEED the ground is
##    about to take back (the body is over [member MovementProfile.ground_speed],
##    which on the flat it never is at the end of a slide and off a ramp it may
##    well be), or EXPOSURE worth breaking the rifle's floor-lead on (more open
##    ground on this crossing than [member RunnerProfile.free_crossing_metres],
##    which is the runner's own line between ground worth worrying about and a
##    step between two boxes). Neither of those is a die roll and neither needs a
##    number this file invented.
## 2. [b]Getting unstuck.[/b] Anywhere, in any state, when the body is asking to
##    move, is against something ([method CharacterBody3D.is_on_wall]), and has
##    been under [member RunnerProfile.jump_blocked_speed] for
##    [member RunnerProfile.jump_blocked_seconds]. This is the one that matters
##    for a ring that is about to be three decks joined by ramps: a lip, a kerb,
##    or the seam at the foot of a ramp is a wall this brain's steering will
##    grind against forever, because nothing in [method _drive_towards] knows
##    what a step is. The wall test is what makes it safe near a pit, and it is
##    not a detail: a hole is not a wall. A body walking off the edge of the deck
##    is never [method CharacterBody3D.is_on_wall] and never
##    [method CharacterBody3D.is_on_floor], so neither trigger can fire there,
##    and the runner falls into the pit exactly as it does today -- which is the
##    arena's known bug to fix, not this one's to make worse.
##
## [b]What is deliberately NOT here.[/b] No hop out of cover, because a body that
## breaks a silhouette above a box it is hiding behind has given away the one
## thing the cover game is about. No hop while a slide is live or a slide press
## is still in the buffer, for the reason above: the slide is worth more. No hop
## in the air, which the floor test settles, so a coyote-timed hop off a ledge --
## [member MovementProfile.coyote_time] is 0.1 s, and the pit is what is under
## the ledge -- is not reachable from here. And nothing at all on the BASELINE
## lap or in the chase: the first is the control case, and the second is a ghost,
## which has nothing to be measured about.
func _maybe_jump(delta: float) -> void:
	_jump_cooldown = maxf(_jump_cooldown - delta, 0.0)

	if not _play.jump_enabled or controller.profile == null:
		_blocked_seconds = 0.0
		return

	# Everything below wants a body on the ground with the key free. A press
	# made in the air is spent on nothing; a press made during a slide ends the
	# slide -- see [method PlayerController._try_jump], which calls
	# [method PlayerController._end_slide] on success -- and a press made while
	# this crossing's slide is still sitting in
	# [member MovementProfile.slide_buffer_time] throws that press away by
	# taking the floor out from under it.
	if not controller.is_on_floor() or controller.is_sliding() or _cross_slide_held:
		_blocked_seconds = 0.0
		return

	var asking_to_move: bool = input.command.move_direction.length_squared() > 0.25
	var speed: float = controller.get_horizontal_speed()

	# Trigger 2 first, because being stuck outranks going fast: a body pinned
	# against a step is not going fast, so the two can never both be true, and
	# the timer has to be maintained on every tick either way.
	if asking_to_move and controller.is_on_wall() and speed < _play.jump_blocked_speed:
		_blocked_seconds += delta
		if _blocked_seconds >= _play.jump_blocked_seconds and _jump_cooldown <= 0.0:
			_blocked_seconds = 0.0
			_press_jump()
		return
	_blocked_seconds = 0.0

	if _jump_cooldown > 0.0:
		return

	# Trigger 1, and everything it asks is about THIS crossing. Nothing here
	# re-reads the tower: CROSS faces the destination, so the exposure the
	# crossing was committed on is the freshest thing there is to go on -- the
	# same argument [method _begin_cross] makes about the slide.
	if _state != State.CROSS or not _has_anchor or not asking_to_move:
		return

	# The slide comes first, always. A crossing judged worth sliding for has not
	# had its slide yet until [method _maybe_slide] presses, and that press waits
	# for the heading to come round -- so hopping here would take the floor away
	# from a slide that was still waiting for it, which is the same mistake
	# holding jump would make, only quieter.
	if _cross_wants_slide and not _cross_slid:
		return

	# Not on the approach. See [member RunnerProfile.jump_min_remaining_metres].
	if _flat_distance(controller.global_position, _anchor) <= _play.jump_min_remaining_metres:
		return

	# Two things a hop can be worth, and it needs one of them.
	#
	# SPEED. Above the body's own ground speed there is surplus, and surplus is
	# exactly what the ground takes back: [method PlayerController._physics_process]
	# skips friction entirely on the tick a body leaves the floor, which is the
	# whole of why a bunny hop keeps what it arrived with. Below ground speed
	# there is nothing to protect and the hop is pure cost, so it is not taken.
	# On flat ground a slide ends at almost exactly ground speed -- 14 m/s off
	# the entry boost, bled back to about 10.9 by a second of slide_friction --
	# so this clause is deliberately near-silent on the deck and is really about
	# the ramps: a slide taken downhill leaves under slope assist, and a body
	# that arrives on a lower deck carrying more than it can accelerate to is a
	# body with something to lose.
	#
	# EXPOSURE. A rifle led along the floor is led at a body ON the floor. That
	# is worth breaking on a crossing the profile does not already consider free
	# -- [member RunnerProfile.free_crossing_metres] is the runner's own line
	# between open ground worth worrying about and a step between two boxes, and
	# reusing it here means this trigger moves when a sweep moves that, instead
	# of needing a second opinion about the same question.
	var surplus: bool = speed > controller.profile.ground_speed
	var worth_breaking: bool = _exposed_metres > _play.free_crossing_metres
	if not surplus and not worth_breaking:
		return
	_press_jump()


## Raise the jump edge, once, and start the cooldown.
##
## [member MoveIntent.jump_held] is left alone on purpose and must stay that way
## -- see the first paragraph of [method _maybe_jump]. The edge is consumed by
## [method BotIntentSource.poll] on the tick the controller reads it, so unlike
## the slide there is nothing here to let go of later.
func _press_jump() -> void:
	input.command.jump_pressed = true
	_jump_cooldown = _play.jump_cooldown_seconds
	_jumps += 1


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

	# Decided once, here, and never revisited -- see [member _cross_wants_slide].
	# A slide is a commitment to this heading at a burst of speed and a lower
	# profile, and crossing real open ground ([member _exposed_metres], not a
	# shuffle inside the same cover) is what makes that trade worth it: the
	# ground still has to be covered, sliding covers it faster, and a lower
	# profile is never a bad thing to have while doing it. Deliberately NOT
	# gated on [method RunnerPerception.believes_watched] -- that belief is
	# itself a delayed, noisy read of a second system, and stacking it onto the
	# exposure test does not make the decision more honest, it just makes the
	# whole thing fire so rarely nobody ever sees it happen. The guard being
	# watched is the reason crossing open ground is dangerous at all; it is not
	# a separate permission slip a slide needs on top of that.
	_cross_wants_slide = _exposed_metres >= _play.slide_min_exposed_metres
	_cross_slid = false
	_cross_slide_held = false
	_cross_slide_open = false
	_cross_slide_seconds = 0.0

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
	var wanted: Vector3 = _next_target(remaining_arc)
	var wanted_is_cover: bool = _cover.has_result()
	_target = _reachable_target(wanted)
	# A detour is not the cover that was found. Saying otherwise would make
	# [method _tick_cross] wait for the perception to agree the body is hidden
	# at a spot chosen only because there was floor on the way to it.
	_target_is_cover = wanted_is_cover and _target.is_equal_approx(wanted)
	_exposed_metres = _measure_exposure(_target)
	_has_target = true


## [param target], if there is floor all the way to it; something nearby that
## there IS floor all the way to, if not.
##
## [b]This is the other half of the pit fix, and the half [RunnerCoverFinder]
## cannot do.[/b] That file now refuses to propose cover it cannot walk to, but
## the open-ground fallback in [method _next_target] never came from it: it is a
## point on the lane ahead, invented here, and on a deck with holes cut through
## it that point is sometimes on the far side of one. A prisoner whose only plan
## is "run at a spot twenty metres up the track" will walk into a pit, and it
## was doing exactly that.
##
## The detour is deliberately dumb: same bearing, a few metres inboard or
## outboard, first one with floor wins. A pit is a few metres across and the
## deck is fourteen to twenty-five wide, so stepping sideways is always the
## answer when there is one. When there is not -- standing at the lip of
## something with nothing reachable ahead at all -- the target is pulled back to
## the edge of the hole, which is a place to stand and think again rather than a
## place to fall from.
func _reachable_target(target: Vector3) -> Vector3:
	var world: World3D = controller.get_world_3d()
	if world == null:
		return target
	var space: PhysicsDirectSpaceState3D = world.direct_space_state
	if space == null:
		return target

	var from: Vector3 = controller.global_position
	if RunnerCoverFinder.path_is_walkable(space, _play, from, target):
		return target

	var level: RingLevel = null if _route == null else _route.level_at(_level)
	var angle: float = _angle_of(target)
	var radius: float = _radius_of(target)
	for offset: float in DETOUR_OFFSETS_METRES:
		var detour_radius: float = radius + offset
		if level != null:
			detour_radius = clampf(
				detour_radius, level.inner_radius + 2.0, level.outer_radius - 2.0
			)
		var candidate: Vector3 = _point_on_level(angle, detour_radius)
		if RunnerCoverFinder.path_is_walkable(space, _play, from, candidate):
			return candidate

	# Still nothing. Shorten the crossing instead of widening it: half the arc,
	# then a quarter of it. A shorter chord sags less and clears less ground, so
	# a hole that swallowed the long version is usually simply not on the short
	# one -- and a runner that advances five metres is a runner that will get
	# another search from somewhere new.
	var arc: float = wrapf((angle - _previous_angle) * TRAVEL_SIGN, -PI, PI)
	for fraction: float in SHORTENED_CROSSINGS:
		var nearer: Vector3 = _point_on_track(_previous_angle + TRAVEL_SIGN * arc * fraction)
		if RunnerCoverFinder.path_is_walkable(space, _play, from, nearer):
			return nearer

	return RunnerCoverFinder.last_walkable_point(space, _play, from, target)


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
## within reach -- the far end of the search arc on the track itself.
##
## The fallback is not a failure mode, it is the last stretch of every lap. The
## finish line stands in the open by design, and a prisoner that refused to cross
## open ground with no cover on the far side would never finish a round.
func _next_target(remaining_arc: float) -> Vector3:
	if _cover.has_result():
		return _cover.get_position()
	var arc: float = minf(_play.get_cover_search_arc_radians(), maxf(remaining_arc, 0.0))
	return _point_on_track(_previous_angle + TRAVEL_SIGN * _chord_limited_arc(arc))


## [param wanted] arc, shortened to whatever a STRAIGHT LINE can actually cross.
##
## [b]A crossing is a chord, and a chord sags.[/b] This brain does not follow the
## track to its target -- [method _drive_towards] walks at it in a straight line
## -- and a straight line between two points on a circle passes inside that
## circle, by more the further apart they are. On a disc that is free. On an
## ANNULUS, past about seventy degrees, the middle of the chord is over the hole
## in the middle of the map, and a runner that took it would walk off the inner
## kerb and fall to the courtyard.
##
## That was true before there were three levels and it was simply never caught:
## the destination was floor-tested and the way there was not. Now that
## [method RunnerCoverFinder.path_is_walkable] tests the way there, an
## over-long fallback stops being a fall and starts being a refusal, which is
## worse -- a runner that will not move. So the arc is capped here at the point
## where the chord's own midpoint would reach the deck's inner edge, and the
## fallback becomes a crossing the runner can make.
func _chord_limited_arc(wanted: float) -> float:
	if _route == null:
		return wanted
	var level: RingLevel = _route.level_at(_level)
	if level == null or level.inner_radius <= 0.0:
		return wanted
	# The chord between two points at radius r, an arc apart, comes closest to
	# the axis at r * cos(arc / 2). Both ends matter, so the tighter of the two
	# radii sets the limit.
	var reach: float = minf(_radius_of(controller.global_position), _lane_radius())
	var edge: float = level.inner_radius + CHORD_MARGIN_METRES
	if reach <= edge:
		return wanted
	return minf(wanted, 2.0 * acos(clampf(edge / reach, -1.0, 1.0)))


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
		_lane_radius(),
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
	return controller.profile.ground_speed


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


## The same angle, about a centre that has not been stored yet. [method configure]
## places the body before [method _arm] caches [member _centre], and placing it
## needs the angle.
func _angle_of_about(centre: Vector3, point: Vector3) -> float:
	return atan2(point.z - centre.z, point.x - centre.x)


## The lane radius of the level being run: the circle this brain steers, and the
## radius a metre of its progress is worth.
##
## [member BotProfile.track_radius] is no longer that circle -- it is one
## arena's bottom deck -- so nothing in this file reads it directly any more
## except the flat-map fallback that builds a route out of it.
func _lane_radius() -> float:
	return 44.5 if _route == null else _route.lane_radius(_level)


## The point on this level's lane at the given angle, on this level's deck.
func _point_on_track(angle: float) -> Vector3:
	return _point_on_level(angle, _lane_radius())


## The point at [param radius] on this level, at its deck height. Only the
## horizontal part is ever used -- [method _face] and [method _drive_towards]
## both flatten -- but the height is right so that a target handed to
## [method _measure_exposure] is priced against a chest on the right deck.
func _point_on_level(angle: float, radius: float) -> Vector3:
	var height: float = _centre.y if _route == null else _route.deck_height(_level)
	return Vector3(_centre.x + cos(angle) * radius, height, _centre.z + sin(angle) * radius)


## The radius the baseline aims at with [param remaining_arc] of lap left: the
## level's lane, easing out to the foot of its ramp over the last
## [constant RAMP_APPROACH_METRES]. See that constant for why the drift is done
## by moving the circle rather than by adding a waypoint.
func _aim_radius(remaining_arc: float) -> float:
	var lane: float = _lane_radius()
	if _route == null or not _route.has_level_above(_level):
		return lane
	var level: RingLevel = _route.level_at(_level)
	if level == null or level.ramp_foot_radius <= 0.0:
		return lane
	var approach_arc: float = RAMP_APPROACH_METRES / lane
	if remaining_arc >= approach_arc:
		return lane
	var eased: float = clampf(1.0 - maxf(remaining_arc, 0.0) / approach_arc, 0.0, 1.0)
	return lerpf(lane, level.ramp_foot_radius, eased)


## Unit tangent to the track at the given angle, pointing the way the lap runs.
func _track_tangent(angle: float) -> Vector3:
	return Vector3(-sin(angle), 0.0, cos(angle)) * TRAVEL_SIGN


## Body yaw, in radians, that points the controller's forward axis along
## [param direction]. Forward is -Z, hence the double negation.
func _heading_of(direction: Vector3) -> float:
	return atan2(-direction.x, -direction.z)


## Distance of a world point from the arena axis, in the horizontal plane.
func _radius_of(point: Vector3) -> float:
	return Vector2(point.x - _centre.x, point.z - _centre.z).length()


## Horizontal distance between two world points. A step down onto the deck is not
## distance to a spot on it.
func _flat_distance(from: Vector3, to: Vector3) -> float:
	return Vector2(to.x - from.x, to.z - from.z).length()
