class_name TowerShooter
extends Node

## The tower's brain: the opposite number to [RingRunner].
##
## It stands on the platform, turns to search the ring, decides whether a runner
## it can actually see is worth a shot, and calls [method Rifle.try_fire]. That
## is the whole of it.
##
## [b]Why it drives a PlayerController and a Rifle rather than owning either[/b]
##
## This node has no movement code and no shooting code. It never calls
## [code]move_and_slide[/code], never writes [member CharacterBody3D.velocity]
## except to clear inherited motion in [method configure], never casts the shot
## ray and never touches the reload clock. It writes a [MoveIntent] into a
## [BotIntentSource] and calls [method Rifle.try_fire], and the same controller
## and the same rifle a human holds do the rest -- same Quake acceleration, same
## look clamp, same hitscan, same enforced silence.
##
## This is the hard rule of the file, and it is [RingRunner]'s hard rule for the
## same reason: a bot with its own movement or its own weapon would be measuring
## a system no player ever touches, and this project's entire method of settling
## design questions by measurement would be worthless. If you find yourself
## computing a velocity or an impact point in here, the seam has leaked.
##
## [b]Attention is the mechanic[/b]
##
## The tower has unobstructed sightlines to the whole ring and a perfectly
## normal field of view, so at any instant it can watch maybe a third of the
## track and the rest is free ground. Everything interesting about playing the
## tower falls out of that, so the bot is built around it rather than around
## aiming:
##
## - It only ever perceives what is inside the live camera frustum. See
##   [method _is_within_view]. The frustum is read off the camera every tick, so
##   using the optic really does narrow what the bot can find -- the cost of the
##   scope is paid in the same currency a human pays it in.
## - It confirms every target with a raycast before it will act on it. See
##   [method _has_line_of_sight]. Cover is absolute: a runner behind a box is not
##   a target, is not tracked, and is not shot at.
## - Nothing downstream of [method _visible_targets] ever sees a runner that
##   failed either test. The bot cannot read a position it has not earned, which
##   is the point -- an omniscient bot in the tower would test nothing.
##
## [b]The state machine[/b]
##
## Four states, deliberately no planner. This is a measuring instrument, and an
## instrument you cannot read at a glance is not one.
##
## [codeblock]
##   SCANNING  --- a target passes both perception tests --->  ACQUIRING
##   ACQUIRING --- reaction_seconds of unbroken sight ------->  ENGAGING
##   ENGAGING  --- the shot is taken ----------------------->  RECOVERING
##   RECOVERING -- the rifle is READY again ---------------->  ENGAGING / SCANNING
##   any state --- the target is lost ---------------------->  SCANNING
## [/codeblock]
##
## [b]The shot decision is explicit[/b]
##
## A shot costs the entire reload and paints a tracer that tells every runner in
## sight where the tower is standing, so "is this shot worth taking" is a real
## decision and it is made in one readable function,
## [method get_shot_confidence], against one exported threshold,
## [member ShooterProfile.shot_confidence_threshold]. It is not implicit in an
## aim tolerance somewhere in the tracking code.

## Emitted after every state transition, including the first one out of
## [constant State.SCANNING]. The hook for a readiness tell, a debug overlay, or
## a sweep that wants to know what fraction of a round the tower spent blind.
signal state_changed(previous: State, current: State)

## Emitted when a runner passes both perception tests and becomes the bot's
## target. Carries the body, because that is what the round thinks in.
signal target_acquired(body: PlayerController)

## Emitted when the bot loses the target it had -- to cover, to the edge of its
## view, or to the target being removed from the round.
signal target_lost()

## Emitted on the tick a shot is actually taken, carrying the confidence the bot
## had in it. A sweep correlating confidence against hits is how
## [member ShooterProfile.shot_confidence_threshold] gets tuned by measurement
## rather than by argument.
signal shot_taken(confidence: float)

## Emitted when the bot had a loaded rifle pointed at a confirmed target and
## chose not to spend the shot, carrying the confidence it declined at. The
## counterpart to [signal shot_taken]: together they are the whole of the third
## design requirement, observable from outside.
##
## Emitted on EVERY tick the bot declines, not once per situation -- a shooter
## holding fire on a bad angle for a second emits it sixty times. That is what a
## sweep wants (it is a sampled distribution of the confidences on offer), but a
## listener that does anything expensive should throttle itself.
signal shot_declined(confidence: float)

## The bot's cycle. Exhaustive: it is always in exactly one of these.
enum State {
	## No confirmed target. The head sweeps. This is where most of a round is
	## spent and it is not idle time -- it is the tower playing the ring.
	SCANNING,
	## A target is confirmed and being tracked, but the reaction clock has not
	## run out yet. The bot will not shoot from here however good the aim looks.
	ACQUIRING,
	## Tracking a confirmed target with a loaded rifle, evaluating every tick
	## whether the shot is worth its price.
	ENGAGING,
	## The rifle is committed or reloading. The bot keeps looking and keeps
	## tracking, and does not so much as ask the weapon to fire.
	RECOVERING,
}

## The body this brain drives. Its [member PlayerController.intent_source] must
## be [member input], or the intent written here goes nowhere.
@export var controller: PlayerController

## The seam through which look intent reaches [member controller].
@export var input: BotIntentSource

## The weapon this brain fires. The bot calls [method Rifle.try_fire] and reads
## [method Rifle.can_fire]; it does not reach into the state machine.
@export var rifle: Rifle

## The zoom optic, when the shooter has one. Optional and safe to leave null:
## the bot hipfires and everything else is unchanged. When it is set, the
## perception frustum narrows with the zoom, because it is read off the same
## camera the optic drives.
@export var optic: WeaponOptic

## The camera whose field of view defines what the bot can see, and whose
## transform defines where it is looking from.
##
## Optional. Without it the bot falls back to the rifle's aim source, then to
## [member PlayerController.head], and assumes
## [member ShooterProfile.fallback_fov_degrees]. Supplying it is strongly
## preferred -- it is the only way the bot's view matches the view a human in
## the same seat would have.
@export var camera: Camera3D

## Tunables. Without one the shooter refuses to play rather than inventing a
## difficulty.
@export var profile: ShooterProfile

## The round's design parameters, when a match supplies them.
##
## Only [member MatchRules.guard_fov_degrees] is read, and only to TIGHTEN the
## bot's arc of attention: the default of 360 degrees means "no match opinion"
## and leaves the camera frustum in charge. A rule may narrow what the guard is
## considered able to see; it may not widen it past the view, because a bot that
## could see outside its own screen is the exact failure this class exists to
## avoid.
##
## [member MatchRules.guard_sightlines_unobstructed] is deliberately NOT read.
## It is a debug switch for measuring what cover is worth, and honouring it here
## would turn "cover is absolute" from a guarantee into a setting. The line of
## sight test below is unconditional.
@export var rules: MatchRules

## Group every body this shooter is willing to consider a target belongs to.
##
## The membership list is bookkeeping, not perception: being in the group only
## makes a body a CANDIDATE, and every candidate still has to pass the frustum
## test and the raycast before the bot may act on it or even read where it is.
## [code]scenes/bot/ring_runner.tscn[/code] joins this group at its root.
@export var target_group: StringName = &"prisoners"

## The bot's current target, or null. Only ever assigned from
## [method _visible_targets], so it is by construction a body that was confirmed
## visible on the tick it was chosen.
var _target: PlayerController = null

var _state: State = State.SCANNING

## Seconds the current target has been continuously visible, capped at
## [member ShooterProfile.reaction_seconds]. Reset to zero the moment sight
## breaks.
var _sighted_seconds: float = 0.0

## Direction of the search sweep, as a sign on the yaw rate.
var _scan_sign: float = 1.0

## Arc swept since the last reversal, in radians.
var _scan_swept: float = 0.0

## The current aim offset, in radians of yaw and pitch. The bot aims at target
## centre PLUS this, and believes the sum is the target -- which is why the
## error costs it hits rather than being cancelled by its own confidence check.
var _aim_error: Vector2 = Vector2.ZERO

## Seconds since [member _aim_error] was last drawn.
var _aim_error_age: float = 0.0

## The confidence computed on the most recent tick that had a target, for
## [method get_shot_confidence].
var _confidence: float = 0.0

## The three terms that produced [member _confidence], as (aim, motion, range).
## Kept apart from their product so a sweep can see WHICH one vetoed a shot --
## "the bot never fires" and "the bot never fires because everything is too far
## away" are different bugs and the product alone cannot tell them apart.
var _confidence_terms: Vector3 = Vector3.ZERO

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

## Times [method Rifle.try_fire] was called, and times it returned true.
##
## They exist to be compared. A bot that respects the reload never asks a
## reloading weapon for a shot, so these two numbers must be equal for the whole
## of a round; a gap between them is the bug this pair is here to catch.
var _fire_attempts: int = 0
var _shots_taken: int = 0


func _ready() -> void:
	# Fail loudly and stand still. A half-configured shooter that turns and
	# fires at nothing is far harder to diagnose than one that never starts.
	if controller == null or input == null or rifle == null or profile == null:
		push_error("TowerShooter needs a controller, an input, a rifle and a profile; it will not play.")
		set_physics_process(false)
		return

	_rng = profile.make_rng()
	_resample_aim_error()

	# Nothing to do until configure() has placed the body on its stand.
	set_physics_process(false)


## Place the shooter on its stand and start it.
##
## [param spawn_point] is the world position of the tower's spawn marker and
## [param initial_yaw] the heading it starts searching from, in radians.
##
## Call it AFTER the body is in the scene tree: it writes
## [member Node3D.global_position]. A body added to the tree is registered by
## the physics server wherever it happened to be at that moment, so a caller
## instancing this scene must set [member Node3D.position] BEFORE
## [method Node.add_child] as well -- otherwise the body exists at the origin
## for one tick, which on this map is the middle of the tower platform.
func configure(spawn_point: Vector3, initial_yaw: float = 0.0) -> void:
	if controller == null or input == null or rifle == null or profile == null:
		return

	controller.global_position = spawn_point
	controller.velocity = Vector3.ZERO
	controller.rotation = Vector3(0.0, initial_yaw, 0.0)

	_target = null
	_state = State.SCANNING
	_sighted_seconds = 0.0
	_scan_sign = 1.0
	_scan_swept = 0.0
	_confidence = 0.0
	_fire_attempts = 0
	_shots_taken = 0
	_resample_aim_error()
	if optic != null:
		optic.reset_zoom()
	set_physics_process(true)


# --- Readouts -----------------------------------------------------------------

func get_state() -> State:
	return _state


## Human-readable state name, for logs and debug overlays.
func get_state_name() -> String:
	return String(State.keys()[_state])


## The body the bot is currently tracking, or null. Never a body it cannot see.
func get_target() -> PlayerController:
	return _target


## How many times the bot has asked the rifle to fire.
func get_fire_attempts() -> int:
	return _fire_attempts


## How many of those asks became shots. Equal to [method get_fire_attempts] on a
## bot that is respecting the reload.
func get_shots_taken() -> int:
	return _shots_taken


# --- The loop -----------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_tick_aim_error(delta)

	# Standing orders, rewritten every tick so a stale one cannot leak: the
	# tower does not walk. Movement is written through the intent source rather
	# than simply skipped, because the controller must run its normal ground
	# phase -- friction, floor snap, the lot -- exactly as it does for a human
	# who is standing still.
	input.command.move_direction = Vector2.ZERO
	input.command.sprint_held = false

	var target: PlayerController = _choose_target(_visible_targets())
	if target == null:
		_forget_target()
		_scan(delta)
		_drive_optic(0.0, Vector2.ZERO)
		_set_state(State.RECOVERING if not rifle.can_fire() else State.SCANNING)
		return

	if target != _target:
		_target = target
		_sighted_seconds = 0.0
		_resample_aim_error()
		target_acquired.emit(target)

	# Track first, always. The aim errors come back from the same call that
	# wrote this tick's look intent, so the confidence below is scored against
	# the aim the bot actually has rather than the one it is heading for.
	var aim_error: Vector2 = _track(target, delta)
	var distance: float = _eye_position().distance_to(_aim_point(target))
	_drive_optic(distance, aim_error)

	_sighted_seconds = minf(_sighted_seconds + delta, profile.reaction_seconds)

	# The reload, respected rather than raced. The bot keeps looking and keeps
	# tracking through it -- a human watching a runner does not close their eyes
	# for two seconds -- but it does not ask the weapon for anything, so
	# _fire_attempts stays equal to _shots_taken.
	if not rifle.can_fire():
		_set_state(State.RECOVERING)
		return

	if _sighted_seconds < profile.reaction_seconds:
		_set_state(State.ACQUIRING)
		return

	_set_state(State.ENGAGING)
	_confidence = _compute_confidence(target, aim_error, distance)
	if _confidence < profile.shot_confidence_threshold:
		shot_declined.emit(_confidence)
		return

	# One last raycast on the exact tick of the shot. _visible_targets() already
	# proved this line clear this tick, so this is belt and braces -- but the
	# guarantee that the bot never fires at a runner behind cover is worth
	# stating locally, next to the trigger, rather than three functions away.
	if not _has_line_of_sight(target):
		return

	_fire_attempts += 1
	if rifle.try_fire():
		_shots_taken += 1
		shot_taken.emit(_confidence)
		_set_state(State.RECOVERING)


# --- Perception ---------------------------------------------------------------

## Every candidate the bot can genuinely see right now.
##
## The one door through which a runner's position may enter this brain. A body
## that is not in the group, is not inside the live view frustum, or does not
## have a clear line from the eye is not in the returned list and is not
## reachable from anywhere else in the file -- which is the whole of the first
## and second design requirements, enforced structurally rather than by care.
func _visible_targets() -> Array[PlayerController]:
	var found: Array[PlayerController] = []
	for node: Node in get_tree().get_nodes_in_group(target_group):
		var body: PlayerController = node as PlayerController
		if body == null or body == controller:
			continue
		if not _is_within_view(body):
			continue
		if not _has_line_of_sight(body):
			continue
		found.append(body)
	return found


## The most central of the candidates, or null when there are none.
##
## Nearest-to-the-crosshair rather than nearest-in-metres on purpose: the bot
## has already turned some distance towards whatever it is looking at, and
## picking by distance would make it abandon a nearly-aimed shot for a closer
## runner it would have to swing all the way round to. Thrash costs shots.
func _choose_target(candidates: Array[PlayerController]) -> PlayerController:
	var best: PlayerController = null
	var best_offset: float = INF
	for body: PlayerController in candidates:
		var local: Vector3 = _eye().to_local(_aim_point(body))
		var offset: float = Vector2(local.x, local.y).length()
		if offset < best_offset:
			best_offset = offset
			best = body
	return best


## True when [param body] falls inside the frustum the bot is currently looking
## through.
##
## Read off the camera every call rather than cached, so the optic narrowing the
## field really does narrow what the bot can find. That is the cost of the
## scope, and it has to be paid in the same currency a human pays it in or the
## optic is a free upgrade for AI only.
func _is_within_view(body: PlayerController) -> bool:
	var local: Vector3 = _eye().to_local(_aim_point(body))
	# -Z is forward for every Node3D in Godot, cameras included.
	if local.z >= 0.0:
		return false

	var half: Vector2 = _view_half_angles()
	var horizontal: float = absf(atan2(local.x, -local.z))
	var vertical: float = absf(atan2(local.y, Vector2(local.x, local.z).length()))
	return horizontal <= half.x and vertical <= half.y


## Half-width and half-height of the view, in radians, after the margin and the
## match's arc rule.
##
## [member Camera3D.fov] is the VERTICAL angle under Godot's default
## [constant Camera3D.KEEP_HEIGHT], and the horizontal arc -- the one that
## decides how much of a ring a tower can watch -- has to be derived from it
## through the aspect ratio. Doing that wrong does not error; it silently gives
## the bot a different ring from the one a human plays.
func _view_half_angles() -> Vector2:
	var fov: float = camera.fov if camera != null else profile.fallback_fov_degrees
	var vertical: float = deg_to_rad(fov) * 0.5
	var horizontal: float = atan(tan(vertical) * profile.view_aspect)

	# The match may narrow the arc the guard is considered able to see, never
	# widen it: 360 degrees is "no opinion" and leaves the camera in charge.
	if rules != null and rules.guard_fov_degrees < 360.0:
		horizontal = minf(horizontal, deg_to_rad(rules.guard_fov_degrees) * 0.5)

	return Vector2(horizontal, vertical) * profile.fov_margin


## True when nothing is between the eye and [param body].
##
## Unconditional, and the reason cover works. The mask is the RIFLE's
## [member WeaponProfile.hit_mask], so what the bot believes blocks a shot and
## what actually blocks a shot are the same set of layers by construction --
## sharing that number is what stops the bot from confidently firing into a box
## the weapon collides with but the perception ignored.
func _has_line_of_sight(body: PlayerController) -> bool:
	var space: PhysicsDirectSpaceState3D = controller.get_world_3d().direct_space_state
	if space == null:
		return false

	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		_eye_position(), _aim_point(body)
	)
	query.collision_mask = rifle.profile.hit_mask if rifle.profile != null else 0xFFFFF
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = [controller.get_rid()]

	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		# Nothing at all in the way, including the target. That happens when the
		# ray ends inside the target's own capsule, which is where it is aimed.
		return true
	return (hit.get("collider", null) as Node3D) == body


## Where on [param body] the bot aims: its origin raised by
## [member ShooterProfile.target_aim_height].
func _aim_point(body: PlayerController) -> Vector3:
	return body.global_position + Vector3.UP * profile.target_aim_height


## The node the bot looks and shoots from.
##
## The rifle's own aim source when it has one, so perception and the shot line
## are the same line -- a bot that checked one line and fired down another would
## report hit rates that mean nothing.
func _eye() -> Node3D:
	if rifle.aim_source != null:
		return rifle.aim_source
	if camera != null:
		return camera
	if controller.head != null:
		return controller.head
	return controller


func _eye_position() -> Vector3:
	return _eye().global_position


# --- Looking ------------------------------------------------------------------

## Sweep the head. The whole of the bot's behaviour when it has nothing.
##
## A constant rate in one direction, reversing once it has covered
## [member ShooterProfile.scan_sweep_degrees], with the pitch eased back to the
## profile's resting angle so the next acquisition does not start with the
## target below the view.
func _scan(delta: float) -> void:
	var rate: float = profile.scan_yaw_rate * _scan_sign
	_scan_swept += profile.scan_yaw_rate * delta
	if _scan_swept >= profile.get_scan_sweep_radians():
		_scan_swept = 0.0
		_scan_sign = -_scan_sign

	var pitch_error: float = profile.get_scan_pitch_radians() - _current_pitch()
	# aim() takes RADIANS PER SECOND and does the per-tick scaling itself.
	# Writing MoveIntent.look_delta directly here would need the value
	# pre-multiplied by delta, and getting that wrong does not raise an error --
	# the yaw aliases past a whole turn every tick. See BotIntentSource.aim.
	input.aim(rate, _clamp_pitch_rate(pitch_error * profile.tracking_gain), delta)


## Turn towards [param body] and return the aim error the bot BELIEVES its shot
## has, in radians of yaw and pitch.
##
## [b]Two different errors, and confusing them costs the whole difficulty dial[/b]
##
## The bot STEERS towards a led point and JUDGES its shot against an un-led one,
## and they have to be different quantities:
##
## - [b]Steering[/b] aims at the target plus
##   [member ShooterProfile.target_lead_seconds] of its velocity, because a
##   proportional controller trails a moving target by a fixed angle and the lead
##   is what cancels that trail. Not projectile lead -- the rifle is hitscan and
##   its round arrives instantly.
## - [b]Judging[/b] measures the barrel against where the bot believes the BODY
##   is, right now, because that is where the shot will actually land. Scoring
##   against the led point instead measures the residual of the tracking loop,
##   which settles at [code]angular_speed / tracking_gain[/code] no matter how
##   good the lead is -- so a perfectly tracking bot would report itself
##   permanently off target and decline every shot at anything that moves. That
##   was the first version of this function and it fired twice in three minutes.
##
## Believed, not true: both points carry [member _aim_error], so a bot whose hand
## is off by a degree reports itself on target and misses by a degree. Judging
## against the TRUE position instead would let the bot decline exactly the shots
## its own aim error spoiled, and the difficulty knob would quietly do nothing.
func _track(body: PlayerController, delta: float) -> Vector2:
	var believed_point: Vector3 = _aim_point(body)
	var steer_point: Vector3 = believed_point + body.velocity * profile.target_lead_seconds

	var steer_error: Vector2 = _angles_to(steer_point)
	input.aim(
		clampf(
			steer_error.x * profile.tracking_gain,
			-profile.max_yaw_rate,
			profile.max_yaw_rate,
		),
		_clamp_pitch_rate(steer_error.y * profile.tracking_gain),
		delta,
	)
	return _angles_to(believed_point)


## Yaw and pitch from where the bot is currently pointing to [param point], in
## radians, with [member _aim_error] folded in so the answer is the bot's own
## belief rather than the truth.
func _angles_to(point: Vector3) -> Vector2:
	var to_target: Vector3 = point - _eye_position()
	var flat: float = Vector2(to_target.x, to_target.z).length()

	# Same construction as RingRunner._steer: a signed heading error in the
	# horizontal plane, positive when the target is off to the bot's right, and
	# positive yaw_rate turns right, so the sign passes straight through.
	var forward: Vector3 = -controller.global_transform.basis.z
	var yaw: float = Vector2(forward.x, forward.z).angle_to(
		Vector2(to_target.x, to_target.z)
	) + _aim_error.x

	var pitch: float = atan2(to_target.y, flat) + _aim_error.y - _current_pitch()
	return Vector2(yaw, pitch)


func _clamp_pitch_rate(rate: float) -> float:
	return clampf(rate, -profile.max_pitch_rate, profile.max_pitch_rate)


## Head pitch in radians. Read off the head node rather than kept here, because
## [PlayerController] owns the clamp and a second copy of the number would drift
## the first time the body hit the pitch limit.
func _current_pitch() -> float:
	if controller.head == null:
		return 0.0
	return controller.head.rotation.x


# --- Aim error ----------------------------------------------------------------

func _tick_aim_error(delta: float) -> void:
	_aim_error_age += delta
	if _aim_error_age >= profile.aim_error_resample_seconds:
		_resample_aim_error()


## Draw a fresh offset uniformly from a disc of
## [member ShooterProfile.aim_error_degrees] radius.
##
## Uniform over the DISC, not over the radius: sampling the radius uniformly
## would pile the offsets up near the centre and make the bot better than its
## own difficulty setting says, which is precisely the sort of quiet dishonesty
## that makes a measured hit rate unusable.
func _resample_aim_error() -> void:
	_aim_error_age = 0.0
	var limit: float = profile.get_aim_error_radians()
	if limit <= 0.0:
		_aim_error = Vector2.ZERO
		return
	var angle: float = _rng.randf_range(-PI, PI)
	var radius: float = limit * sqrt(_rng.randf())
	_aim_error = Vector2(cos(angle), sin(angle)) * radius


# --- The shot decision --------------------------------------------------------

## Confidence in the shot as of the last tick that had a target, from 0 to 1.
## What [signal shot_taken] and [signal shot_declined] carry, exposed so a HUD
## or a sweep can watch the decision being made rather than only its outcome.
func get_shot_confidence() -> float:
	return _confidence


## The aim, motion and range terms behind [method get_shot_confidence], in that
## order, each from 0 to 1. Their product is the confidence.
func get_confidence_terms() -> Vector3:
	return _confidence_terms


## How good this shot looks, from 0 (do not) to 1 (certain).
##
## THE decision, in one place, as three independent terms multiplied together so
## that any one of them can veto the shot on its own:
##
## 1. [b]Aim[/b] -- 1.0 pointing exactly at the believed target, falling linearly
##    to 0.0 at [member ShooterProfile.aim_tolerance_degrees].
## 2. [b]Motion[/b] -- halved when the target crosses the view at
##    [member ShooterProfile.max_comfortable_track_rate], because a crossing
##    runner is a harder shot and a missed shot costs the whole reload.
## 3. [b]Range[/b] -- 1.0 out to [member ShooterProfile.confident_range], falling
##    linearly to 0.0 at [member ShooterProfile.max_engagement_range].
##
## Multiplied rather than averaged deliberately: an average lets a perfect aim
## on a 100 m sprinting target still clear a middling threshold, and the whole
## point of the reload is that such a shot should usually not be taken.
func _compute_confidence(body: PlayerController, aim_error: Vector2, distance: float) -> float:
	var aim_term: float = clampf(
		1.0 - aim_error.length() / maxf(profile.get_aim_tolerance_radians(), 0.0001),
		0.0,
		1.0,
	)

	# Angular speed across the view: only the component of the target's velocity
	# perpendicular to the sightline moves it across the bot's screen. A runner
	# coming straight at the tower is a stationary target and should be scored
	# as one.
	var to_target: Vector3 = _aim_point(body) - _eye_position()
	var range_to_target: float = maxf(to_target.length(), 0.0001)
	var direction: Vector3 = to_target / range_to_target
	var crossing: Vector3 = body.velocity - direction * body.velocity.dot(direction)
	var angular_speed: float = crossing.length() / range_to_target
	var motion_term: float = 1.0 / (
		1.0 + angular_speed / maxf(profile.max_comfortable_track_rate, 0.0001)
	)

	var range_term: float = 1.0
	if distance > profile.confident_range:
		var span: float = maxf(profile.max_engagement_range - profile.confident_range, 0.0001)
		range_term = clampf((profile.max_engagement_range - distance) / span, 0.0, 1.0)

	_confidence_terms = Vector3(aim_term, motion_term, range_term)
	return aim_term * motion_term * range_term


# --- Optic --------------------------------------------------------------------

## Ask the optic for the zoom the current situation wants.
##
## Idempotent by [method WeaponOptic.zoom_in]'s contract, so this may be called
## every tick, and it is: the decision is cheap and holding it in a variable
## would be a second copy of the optic's own state.
##
## The hazard the centre-fraction test exists for: zooming NARROWS the view, so
## zooming on a target near the edge of vision loses it the instant the
## transition starts, which drops the bot back to scanning, which zooms out,
## which re-acquires -- an oscillation that never fires a shot.
func _drive_optic(distance: float, aim_error: Vector2) -> void:
	if optic == null or not profile.wants_optic():
		return
	if _target == null or distance < profile.optic_min_distance:
		optic.zoom_out()
		return

	var half: Vector2 = _zoomed_half_angles() * profile.optic_centre_fraction
	optic.set_zoomed(absf(aim_error.x) <= half.x and absf(aim_error.y) <= half.y)


## The half-angles the view WOULD have at full zoom. Computed from the optic's
## own target FOV rather than the live one, so the test asks "will the target
## still be in view once I have zoomed" instead of "is it in view now", which is
## the question that actually prevents the oscillation.
func _zoomed_half_angles() -> Vector2:
	var fov: float = optic.get_zoomed_fov()
	if fov <= 0.0:
		fov = profile.fallback_fov_degrees
	var vertical: float = deg_to_rad(fov) * 0.5
	return Vector2(atan(tan(vertical) * profile.view_aspect), vertical) * profile.fov_margin


# --- State --------------------------------------------------------------------

func _forget_target() -> void:
	if _target == null:
		return
	_target = null
	_sighted_seconds = 0.0
	_confidence = 0.0
	_confidence_terms = Vector3.ZERO
	target_lost.emit()


func _set_state(next: State) -> void:
	if next == _state:
		return
	var previous: State = _state
	_state = next
	state_changed.emit(previous, _state)
