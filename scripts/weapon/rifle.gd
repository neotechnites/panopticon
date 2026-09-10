class_name Rifle
extends Node3D

## The tower's only tool, and the metronome the whole match runs on.
##
## One shot removes one runner. Then a long, enforced silence. Every other
## system in PANOPTICON is downstream of that rhythm: the ring's cover spacing
## is only meaningful relative to the reload, the runners' route choices are
## bets against it, and the tower's tension is entirely the cost of having
## spent it.
##
## [b]Structure[/b]
##
## Decision and act are separate, exactly as they are in [PlayerController].
## This node never touches [Input]; it exposes [method try_fire] and a thin
## [WeaponInput] calls it from a device. A bot AI calls the identical method,
## so a headless bot match exercises the real weapon -- the real raycast, the
## real reload clock -- and not a simulation of it. If you find yourself reading
## the mouse in this file, the seam has leaked.
##
## Every number lives in [WeaponProfile]. There are no weapon constants here.
##
## [b]Why a state machine and not a boolean[/b]
##
## [code]can_fire[/code] as a flag would work today and rot immediately. The
## states below are load-bearing for work that hangs off them: the tower's
## interior light changes with the reload, the shot report and the muzzle flash
## own [constant State.FIRING], runners will eventually be given a read on the
## tower's readiness, and a sweep wants to know what fraction of a match the
## weapon spent unable to answer. All of those want to subscribe to transitions,
## which a boolean cannot offer and a scattered set of booleans offers
## inconsistently.
##
## The cycle is strictly [constant State.READY] -> [constant State.FIRING] ->
## [constant State.RELOADING] -> [constant State.READY]. There is no path that
## skips the reload.
##
## [b]The options, and why they are all off[/b]
##
## The weapon can shoot several genuinely different ways -- hitscan or a round
## with travel time, perfectly accurate or scattering, flat reload or shaped,
## instant trigger or charged. None of that is a mode this file chooses; every
## one of them is a field on [WeaponProfile], every one defaults to the shipped
## behaviour, and the code paths behind them are gated on those defaults rather
## than merely parameterised by them. With the shipped profile the weapon takes
## exactly the branches it took before any of this existed: it never touches its
## RNG, never measures its own speed, never probes for range, never allocates a
## round and never runs a charge clock.
##
## That matters beyond tidiness. The point of the options is to be SWEPT -- to
## run the same rules with travel time and without and compare -- and a sweep is
## only honest if the control arm is the shipped game rather than a fresh code
## path that happens to be configured to look like it.

## The weapon's cycle. Exhaustive: the rifle is always in exactly one of these.
enum State {
	## Loaded and willing. The only state in which [method try_fire] succeeds.
	READY,
	## The shot has been taken and resolved; the weapon is committed to it for
	## [member WeaponProfile.shot_duration]. Muzzle flash and report live here.
	FIRING,
	## Enforced downtime. This is the game.
	RELOADING,
}

## Emitted after every transition, including the one out of the initial state.
## The hook for lighting, audio and readiness tells: prefer it to polling
## [method get_state] so a transition cannot be missed between frames.
signal state_changed(previous: State, current: State)

## Emitted on every shot, hit or miss, carrying the world-space line the shot
## travelled. [param end_point] is the impact point on a hit and the far end of
## [member WeaponProfile.max_range] on a miss.
##
## This is the "a shot is a broadcast" signal: anything that reacts to the tower
## having revealed itself -- runner AI, audio, a spectator overlay -- listens
## here rather than to [signal target_hit], because a miss is just as loud.
##
## Emitted at the TRIGGER, always, which is what keeps recoil and the muzzle
## report on the beat under either shot model. Under
## [constant WeaponProfile.ShotModel.PROJECTILE] the outcome is not known yet,
## so [param end_point] is the far end of the line the round was launched
## along; the hit or the miss follows some frames later. Under hitscan, which is
## shipped, the line is the resolved one and nothing has changed.
signal fired(origin: Vector3, end_point: Vector3)

## Emitted when a shot connects, and only then.
##
## A hit is terminal -- there is no health and no damage number, one hit removes
## a target -- but this weapon deliberately does not enforce that. It reports
## what it struck and where, and something else decides what that means. That
## separation is what lets the same rifle be lethal on the ring, non-lethal in a
## tutorial, and merely scored in a headless sweep, without a branch in here.
signal target_hit(collider: Node3D, hit_position: Vector3, hit_normal: Vector3)

## Emitted when a shot reaches [member WeaponProfile.max_range] without hitting
## anything. The reload is identical either way; missing costs exactly as much
## as hitting, which is the point.
signal missed(end_point: Vector3)

## Emitted as the reload begins, carrying the duration it will take. Lighting
## and audio that need to span the whole reload -- a charge tone, a dimming
## lamp -- should read the duration from here rather than from the profile,
## because the live value is [member reload_seconds] and it changes.
signal reload_started(duration: float)

## Emitted the instant the weapon becomes [constant State.READY] again.
signal reload_finished()

## Emitted whenever [member reload_seconds] actually changes value, including
## mid-reload. Match progression drives the tower's readiness tell off this.
signal reload_duration_changed(duration: float)

## Emitted when a shaped reload crosses out of its dead phase and into its
## wind-up, carrying the seconds of wind-up left.
##
## Never emitted by the shipped flat reload, which has no wind-up. The hook for
## the "it is coming back" half of the tower's readiness tell, as distinct from
## the "it is gone" half that [signal reload_started] already covers. See
## [member WeaponProfile.reload_windup_fraction].
signal reload_windup_started(remaining: float)

## Emitted when [method interrupt_reload] actually knocked a wind-up back,
## carrying the seconds now left on the reload. Never emitted by the shipped
## weapon, which is not interruptible.
signal reload_interrupted(remaining: float)

## Emitted whenever the hold on a charged shot changes, from 0.0 to 1.0. The
## hook for a charge tone or a tightening crosshair. Silent unless
## [member WeaponProfile.charge_enabled] is on.
signal charge_changed(charge: float)

## Emitted when a held shot is let go, carrying the charge it went off at --
## including 0.0 for a hold that was cancelled rather than fired. Silent unless
## [member WeaponProfile.charge_enabled] is on.
signal charge_released(charge: float)

## Emitted when a round is put in the air, carrying where it started, the
## direction it was actually launched along (spread already applied, so this is
## the true line and not the aim line) and its muzzle speed.
##
## Only ever emitted under [constant WeaponProfile.ShotModel.PROJECTILE]. A
## sweep correlating this against the [signal target_hit] that follows is how
## the lead a runner is worth gets measured.
signal projectile_launched(origin: Vector3, direction: Vector3, speed: float)

## Tunables. Without one the rifle cannot fire and says so rather than falling
## back on invented numbers.
##
## This is the weapon-INTRINSIC half of the rifle's numbers: range, hit mask,
## tracer look, the committed firing window, and the hard floor the reload may
## never go below. What the weapon IS. The match's opinion of how long the tower
## should be silent lives in [member rules] instead, and wins.
@export var profile: WeaponProfile

## The round's design parameters, when a match supplies them.
##
## Only the reload is read: [member MatchRules.base_reload_seconds] replaces the
## profile's starting value, and [member MatchRules.reload_floor_seconds] can
## tighten the profile's floor but never loosen it. The reload is a rule of the
## round rather than a property of the gun -- it is the clock the whole match
## runs on and it has to be sweepable per match -- so it is the one number a
## [MatchRules] is allowed to reach in and set.
##
## Null is normal and means "no match opinion": the profile's own values are
## used, which is what a rifle in a test scene or in the editor sees.
## [MatchController] assigns this at the start of every round.
##
## Assigning this also adopts a [WeaponProfile] the rules carry, if they carry
## one -- see [method read_rules_profile]. That is the seam by which a sweep
## varies the WEAPON as well as the round: an arm of a sweep is a [MatchRules],
## so the weapon it wants has to be reachable from one. The adopted profile is
## written into [member profile] rather than kept beside it, so
## [code]rifle.profile[/code] stays the one true answer for everything that
## reads it from outside.
@export var rules: MatchRules:
	get:
		return _rules
	set(value):
		if value == _rules:
			return
		_rules = value
		_adopt_rules_profile()

## Where the ray starts and which way it points: its -Z axis is the shot line.
##
## Normally the player's [Camera3D], so that the shot goes exactly where the
## crosshair is and there is no muzzle-to-camera parallax to explain away. Typed
## as [Node3D] rather than [Camera3D] on purpose -- a bot in a headless match has
## no camera, only a head pivot, and it must be able to aim the same rifle
## through the same field.
##
## Falls back to this node if unset.
@export var aim_source: Node3D

## Where the tracer visually starts. The ray does not come from here: the shot
## line is the camera's, always, and the muzzle only decides where the visible
## streak is anchored so it reads as leaving the barrel. Falls back to
## [member aim_source].
@export var muzzle: Node3D

## The shooter's own body, excluded from the raycast. Without it a rifle
## parented inside a [CharacterBody3D] shoots its owner's collider at point
## blank and every shot is a self-hit.
@export var shooter_body: CollisionObject3D

## Where tracers are parented. Leave unset and they parent to this node, which
## is fine because [Tracer] is top-level and so ignores the rifle's motion.
## Set it to a long-lived world node if tracers must outlive their shooter --
## a shot fired at the moment the tower dies should still give away its position.
@export var tracer_parent: Node3D

## Property name a [MatchRules] may carry to hand the round its own weapon.
##
## Looked up by name off the rules' property list rather than accessed directly,
## because [MatchRules] belongs to the match and may not have the field at all.
## When it does not, nothing happens and the weapon keeps its own profile; when
## it does, a sweep arm can swap the entire gun. That is the whole coupling.
const RULES_PROFILE_FIELD: String = "weapon_profile"

var _state: State = State.READY

## Seconds spent in the current state. The reload is measured as elapsed rather
## than as a countdown deliberately -- see [member reload_seconds].
var _state_elapsed: float = 0.0

## Seconds the weapon has been loaded and untouched. Drives the settle term of
## the spread -- see [member WeaponProfile.spread_settle_seconds]. Separate from
## [member _state_elapsed] so the cycle's own bookkeeping is untouched by it.
var _ready_elapsed: float = 0.0

## Backing store for [member reload_seconds].
var _reload_seconds: float = 0.0

## Backing store for [member rules].
var _rules: MatchRules = null

## Whether [signal reload_windup_started] has already gone out this reload, so a
## wind-up announces itself once rather than every tick.
var _windup_announced: bool = false

## The hold on a charged shot, 0.0 to 1.0. Always 0.0 while
## [member WeaponProfile.charge_enabled] is off.
var _charge: float = 0.0
var _charging: bool = false

## Rounds in the air. Empty under hitscan, and at most one long under the
## single-shot cycle unless the reload is shorter than the flight time.
var _projectiles: Array[WeaponProjectile] = []

## The shooter's speed in m/s, sampled from the aim source's own motion so that
## no extra wiring is needed to know whether the tower is walking. Stays 0.0
## unless [member WeaponProfile.moving_spread_degrees] asks for it.
var _motion_speed: float = 0.0
var _motion_sample: Vector3 = Vector3.ZERO
var _has_motion_sample: bool = false

## Scatter RNG, built on first use so a perfectly accurate weapon never makes
## one. See [member WeaponProfile.spread_seed].
var _rng: RandomNumberGenerator = null


## The live reload duration, in seconds.
##
## Starts at [method get_base_reload_seconds] and is meant to be
## written at runtime: the design calls for the rifle to get faster as a match
## progresses, so this is a property with a signal rather than a constant read
## out of the profile. [method get_base_reload_seconds] is the starting point,
## never the current truth.
##
## Changing it mid-reload takes effect on that same reload, because the reload
## is tracked as elapsed time compared against this value rather than as a
## countdown seeded at the start. Shortening the reload below the time already
## served completes it immediately, which is the behaviour a progression rule
## wants: "reloads are 1.2 s now" should mean now, not next shot.
##
## Writes are clamped to [method get_reload_floor_seconds], which is the weapon's
## own floor raised by the match's if the match asked for a tighter one.
var reload_seconds: float:
	get:
		return _reload_seconds
	set(value):
		var clamped: float = maxf(value, get_reload_floor_seconds())
		if is_equal_approx(clamped, _reload_seconds):
			return
		_reload_seconds = clamped
		reload_duration_changed.emit(_reload_seconds)


func _ready() -> void:
	if profile == null:
		push_error("Rifle has no WeaponProfile; the weapon cannot fire.")
		set_physics_process(false)
		return
	# A duration assigned before the node entered the tree is honoured but
	# re-clamped, since the floor was unknown without a profile.
	reload_seconds = _reload_seconds if _reload_seconds > 0.0 else get_base_reload_seconds()


## The clock runs on the physics tick, not the render tick, so the reload is the
## same length in a 300 fps play session and in a headless sweep with rendering
## switched off. A weapon whose cycle drifts with framerate cannot be swept.
func _physics_process(delta: float) -> void:
	tick(delta)


## Advance the weapon's clock by [param delta] seconds.
##
## Public because a harness may want to drive the cycle itself: call
## [code]set_physics_process(false)[/code] and step this with a fixed delta to
## replay a match deterministically, or to run a reload sweep far faster than
## real time. [method _physics_process] is only a caller of this.
func tick(delta: float) -> void:
	if profile == null:
		return
	# Order is deliberate. Motion and rounds in the air are facts about the
	# world and are true whatever the weapon's state is -- a round keeps flying
	# through the reload, and a weapon that is READY can still be walking. The
	# cycle goes last so a shot taken this tick is not also advanced by it.
	_step_motion(delta)
	_step_projectiles(delta)
	_step_charge(delta)
	_step_cycle(delta)


## The shot-to-ready state machine, unchanged since before the weapon had
## options: everything the profile added is stepped around this, not inside it.
func _step_cycle(delta: float) -> void:
	if _state == State.READY:
		_ready_elapsed += delta
		return

	_state_elapsed += delta
	if _state == State.FIRING:
		if _state_elapsed >= profile.shot_duration:
			# Carry the overshoot rather than dropping it: at a 60 Hz tick and a
			# 0.06 s flash, discarding the remainder would silently lengthen
			# every cycle by up to a tick, and a sweep would measure a reload
			# that nobody configured.
			var overshoot: float = _state_elapsed - profile.shot_duration
			_begin_reload()
			_state_elapsed = overshoot
			_announce_windup()
			if _state_elapsed >= _reload_seconds:
				_finish_reload()
		return

	_announce_windup()
	if _state_elapsed >= _reload_seconds:
		_finish_reload()


## Fire if the weapon will allow it. Returns true if a shot was actually taken.
##
## The single entry point for the act of shooting, and the seam between DECISION
## and ACT. A human presses a button and [WeaponInput] calls this; a bot decides
## it wants the shot and calls this. Neither the raycast below nor the reload it
## starts can tell which, which is what makes a headless bot match a valid way to
## answer design questions about the reload.
##
## Refusal is silent and cheap: callers -- bots especially -- are expected to
## call optimistically and read the return value, not to gate on
## [method can_fire] first and race the clock.
func try_fire() -> bool:
	if not can_fire():
		return false
	var charge: float = get_charge()
	# The one way a ready weapon can still refuse. Zero by default precisely so
	# that a bot which never holds the trigger is never refused -- see
	# [member WeaponProfile.charge_min_fraction_to_fire].
	if profile.charge_enabled and charge < profile.charge_min_fraction_to_fire:
		return false
	_end_charge(charge)
	_resolve_shot(charge)
	_set_state(State.FIRING)
	return true


## True when a call to [method try_fire] would succeed.
func can_fire() -> bool:
	return profile != null and _state == State.READY


func get_state() -> State:
	return _state


## Human-readable state name, for logs and debug overlays.
func get_state_name() -> String:
	return String(State.keys()[_state])


## Seconds until the weapon is ready again, 0.0 when it already is. Counts the
## remaining firing window as well as the reload, so it is the honest answer to
## "when may I shoot", which is what a bot's planner needs.
func get_time_to_ready() -> float:
	match _state:
		State.FIRING:
			return maxf(profile.shot_duration - _state_elapsed, 0.0) + _reload_seconds
		State.RELOADING:
			return maxf(_reload_seconds - _state_elapsed, 0.0)
		_:
			return 0.0


## Reload progress from 0.0 to 1.0, and 1.0 whenever not reloading. The value a
## readiness lamp or a UI arc should drive off.
func get_reload_progress() -> float:
	if _state != State.RELOADING:
		return 1.0
	if _reload_seconds <= 0.0:
		return 1.0
	return clampf(_state_elapsed / _reload_seconds, 0.0, 1.0)


## Restore the reload to its starting value. For a match reset, so progression
## cannot leak across rounds.
func reset_reload_to_base() -> void:
	if profile == null:
		return
	reload_seconds = get_base_reload_seconds()


## The reload this weapon starts a round on: the match's value when a
## [MatchRules] is assigned and has an opinion, otherwise the profile's own.
func get_base_reload_seconds() -> float:
	if profile == null:
		return 0.0
	if rules == null:
		return profile.base_reload_seconds
	return rules.get_base_reload_seconds(profile.base_reload_seconds)


## The floor [member reload_seconds] is clamped to: the higher of the weapon's
## own [member WeaponProfile.min_reload_seconds] and the match's
## [member MatchRules.reload_floor_seconds]. A match rule may tighten the bound,
## never drill through it -- the weapon's floor is a guarantee that the rifle
## stays single-shot rather than becoming an automatic by sweep.
func get_reload_floor_seconds() -> float:
	var weapon_floor: float = profile.min_reload_seconds if profile != null else 0.0
	if rules == null:
		return weapon_floor
	return rules.get_reload_floor_seconds(weapon_floor)


# --- Reload shape -------------------------------------------------------------
#
# The DURATION belongs to [MatchRules] and nothing here touches it. What the
# weapon owns is the SHAPE of that duration -- see
# [member WeaponProfile.reload_windup_fraction] -- so every function below is a
# reading of whatever number [member reload_seconds] currently holds.

## Seconds of the current reload that are wind-up rather than dead time. 0.0 for
## the shipped flat reload.
##
## A fraction of the LIVE duration, so a reload the match has shortened has a
## proportionally shorter wind-up and the shape survives progression intact.
func get_reload_windup_seconds() -> float:
	if profile == null:
		return 0.0
	return profile.get_windup_seconds(_reload_seconds)


## True while the reload is in its wind-up: still not ready, but visibly coming
## back, and the only window in which [method interrupt_reload] bites.
## Always false for the shipped flat reload.
func is_winding_up() -> bool:
	if _state != State.RELOADING:
		return false
	var windup: float = get_reload_windup_seconds()
	return windup > 0.0 and _state_elapsed >= _reload_seconds - windup


## Knock the wind-up back to its start. Returns true if it actually did.
##
## The weapon deliberately has no opinion about what interrupts it -- being
## shot, sprinting, falling, taking the seat -- exactly as it has no opinion
## about what a hit means. It exposes the verb and something with a design
## decision calls it.
##
## Refuses, and returns false, unless [member WeaponProfile.reload_interruptible]
## is on AND the reload is currently winding up. Both are off in the shipped
## weapon, so this is a no-op there. The cost is bounded by construction: an
## interrupt can never take longer than the wind-up, so a weapon cannot be
## locked out indefinitely by repeated interruption.
func interrupt_reload() -> bool:
	if profile == null or not profile.reload_interruptible:
		return false
	if not is_winding_up():
		return false
	var windup: float = get_reload_windup_seconds()
	_state_elapsed = maxf(_reload_seconds - windup, 0.0)
	_windup_announced = false
	var remaining: float = maxf(_reload_seconds - _state_elapsed, 0.0)
	reload_interrupted.emit(remaining)
	return true


# --- Charged shot -------------------------------------------------------------
#
# All of this is dead while [member WeaponProfile.charge_enabled] is off, which
# is shipped. [method try_fire] keeps working either way: it takes the shot at
# whatever charge exists, which is 0.0 for a caller that never held one. That is
# what lets [TowerShooter] and every other bot drive a charged weapon through
# the same single entry point a human uses.

## The hold on the current shot, 0.0 to 1.0. Always 0.0 when charging is off.
func get_charge() -> float:
	return _charge


## True while a hold is accumulating.
func is_charging() -> bool:
	return _charging


## Start holding. Returns true if a hold is now running.
##
## Refuses when charging is off or the weapon is not [constant State.READY]:
## there is nothing to charge into during a reload, and pretending otherwise
## would let a shooter bank a charge through the downtime the whole game is
## built on.
func begin_charge() -> bool:
	if profile == null or not profile.charge_enabled:
		return false
	if _state != State.READY:
		return false
	if _charging:
		return true
	_charging = true
	_set_charge(0.0)
	return true


## Let the hold go and take the shot. Returns true if a shot was taken.
##
## With charging off this is simply [method try_fire], so an input layer can
## call it unconditionally and the weapon decides which design it is playing.
##
## A release that the weapon refuses -- below
## [member WeaponProfile.charge_min_fraction_to_fire] -- spends the hold anyway.
## A released trigger is released; letting it silently keep charging would make
## the tell a runner reads off the tower a lie.
func release_charge() -> bool:
	if profile == null or not profile.charge_enabled:
		return try_fire()
	if not _charging:
		return false
	var held: float = _charge
	var took_shot: bool = try_fire()
	if not took_shot:
		_end_charge(held)
	return took_shot


## Drop the hold without firing, for a menu, a death, or losing the seat.
func cancel_charge() -> void:
	if not _charging:
		return
	_end_charge(_charge)


# --- Accuracy -----------------------------------------------------------------

## The scatter cone's half-angle in degrees the NEXT shot would fire into.
##
## 0.0 for the shipped weapon at all times. Exposed rather than kept private
## because it is what a crosshair should bloom on and what a headless check
## should assert against -- a spread nobody can read is a spread nobody can
## tune.
##
## The range term is only included when the profile asks for one, since finding
## the distance costs a raycast.
func get_current_spread_degrees() -> float:
	if profile == null or not profile.has_spread():
		return 0.0
	var distance: float = -1.0
	if profile.needs_range_probe() and is_inside_tree():
		var source: Node3D = aim_source if aim_source != null else self
		var aim: Vector3 = -source.global_transform.basis.z.normalized()
		distance = _probe_distance(source.global_position, aim, profile.max_range)
	return profile.get_spread_degrees(_motion_speed, _ready_elapsed, distance, _charge)


## The shooter's speed in m/s as the weapon measures it. 0.0 unless
## [member WeaponProfile.moving_spread_degrees] asked the weapon to look.
func get_shooter_speed() -> float:
	return _motion_speed


## Seconds the weapon has been loaded and untouched, which is what
## [member WeaponProfile.spread_settle_seconds] is measured against.
func get_settled_seconds() -> float:
	return _ready_elapsed


# --- Rounds in flight ---------------------------------------------------------

## How many rounds are currently in the air. Always 0 under hitscan, which is
## the shipped model, so this doubles as the assertion that the default weapon
## allocates nothing.
func get_projectiles_in_flight() -> int:
	return _projectiles.size()


## Delete every round in the air without resolving it: no hit, no miss, no
## signal. For a round reset or a teardown, where a shot fired by a tower that
## no longer exists should not land on a runner in the next round.
func clear_projectiles() -> void:
	for round_shot: WeaponProjectile in _projectiles:
		if is_instance_valid(round_shot):
			round_shot.queue_free()
	_projectiles.clear()


# --- Rules-supplied weapon ----------------------------------------------------

## The [WeaponProfile] [param source] carries, or null when it carries none.
##
## Read off the property list by name rather than accessed directly, because
## [MatchRules] is the match's file and may simply not have the field. This is
## the whole of the coupling and it is one-directional: the weapon asks, the
## rules do not have to answer, and nothing breaks either way.
##
## It exists because an arm of a sweep IS a [MatchRules] -- the harness builds
## one per variant and changes nothing else -- so a weapon option that cannot be
## reached from one is an option that can never be measured, which is the same
## as not having it.
static func read_rules_profile(source: MatchRules) -> WeaponProfile:
	if source == null:
		return null
	for entry: Dictionary in source.get_property_list():
		if String(entry.get("name", "")) == RULES_PROFILE_FIELD:
			return source.get(RULES_PROFILE_FIELD) as WeaponProfile
	return null


# --- Shot resolution ----------------------------------------------------------

## Cast the ray, announce what happened, draw the tracer.
##
## Order matters: [signal fired] goes out before [signal target_hit], so a
## listener that reacts to the tower having given itself away sees the shot even
## if a hit listener removes the target and tears down half the scene.
func _resolve_shot(charge: float) -> void:
	var source: Node3D = aim_source if aim_source != null else self
	var origin: Vector3 = source.global_position
	# -Z is forward for every Node3D in Godot, cameras included, so this reads
	# the aim of a camera and of a bot's bare head pivot identically.
	var aim: Vector3 = -source.global_transform.basis.z.normalized()
	var travel_range: float = profile.get_charged_range(charge)
	# Returns `aim` itself, untouched, for a profile with no spread -- so the
	# shipped weapon's shot line is the aim line and not a zero-width draw off
	# an RNG that was never constructed.
	var direction: Vector3 = _scatter(origin, aim, travel_range, charge)
	var far_point: Vector3 = origin + direction * travel_range
	# The tracer starts at the barrel, not the eye, so it looks like it left the
	# weapon -- but it ends where the shot truly ended, so back-projecting it
	# still gives an observer the tower's position to within the muzzle offset.
	var muzzle_node: Node3D = muzzle if muzzle != null else source

	if profile.is_projectile():
		# The outcome is not known yet, so the broadcast carries the line the
		# round was launched along and the hit or miss follows it later. The
		# round leaves the eye rather than the barrel for the same reason the
		# ray does: no parallax to explain away between the crosshair and where
		# the shot actually goes.
		_launch(origin, direction, travel_range, charge)
		_spawn_tracer(muzzle_node.global_position, far_point)
		fired.emit(origin, far_point)
		return

	var hit: Dictionary = _cast(origin, far_point)
	var end_point: Vector3 = far_point
	var collider: Node3D = null
	var normal: Vector3 = -direction
	if not hit.is_empty():
		end_point = hit.get("position", far_point)
		normal = hit.get("normal", -direction)
		collider = hit.get("collider", null) as Node3D

	_spawn_tracer(muzzle_node.global_position, end_point)

	fired.emit(origin, end_point)
	if collider != null:
		target_hit.emit(collider, end_point, normal)
	else:
		missed.emit(end_point)


func _cast(from: Vector3, to: Vector3) -> Dictionary:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if space == null:
		return {}
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = profile.hit_mask
	query.collide_with_areas = profile.hit_areas
	query.collide_with_bodies = true
	if shooter_body != null:
		query.exclude = [shooter_body.get_rid()]
	return space.intersect_ray(query)


## Tracers are fire-and-forget: [Tracer] frees itself, so no reference is kept
## and no pool is maintained. A single-shot weapon produces at most one tracer
## per cycle, and pooling that would be bookkeeping in exchange for nothing.
func _spawn_tracer(from: Vector3, to: Vector3) -> void:
	# One gate, on the profile, so a disabled tracer, a zeroed lifetime and a
	# zeroed width cannot disagree about whether geometry gets built. A sweep
	# arm with the tracer off allocates nothing at all.
	if not profile.draws_tracer():
		return
	var parent: Node = tracer_parent if tracer_parent != null else self
	Tracer.spawn(parent, from, to, profile)


# --- State machine ------------------------------------------------------------

func _set_state(next: State) -> void:
	if next == _state:
		return
	var previous: State = _state
	_state = next
	_state_elapsed = 0.0
	if _state == State.READY:
		_ready_elapsed = 0.0
	state_changed.emit(previous, _state)


func _begin_reload() -> void:
	_set_state(State.RELOADING)
	_windup_announced = false
	reload_started.emit(_reload_seconds)


func _finish_reload() -> void:
	_set_state(State.READY)
	reload_finished.emit()


# --- Per-tick work behind the options -----------------------------------------
#
# Every function here returns on its first line for the shipped profile. That is
# the shape the whole file is built to: an option costs the default weapon a
# boolean read, not a branch it takes.

## Sample how fast the shooter is going, from the aim source's own motion.
##
## Deliberately measured rather than wired: the rifle is parented onto whoever
## holds the seat, so its aim source moves exactly as the shooter does, and
## asking for a [CharacterBody3D] reference would be a second thing to connect
## in three scenes and a fourth in the harness. Skipped entirely unless the
## profile has a movement penalty to apply.
func _step_motion(delta: float) -> void:
	if not profile.tracks_shooter_speed() or not is_inside_tree():
		_motion_speed = 0.0
		_has_motion_sample = false
		return
	var source: Node3D = aim_source if aim_source != null else self
	var here: Vector3 = source.global_position
	if _has_motion_sample and delta > 0.0:
		_motion_speed = here.distance_to(_motion_sample) / delta
	_motion_sample = here
	_has_motion_sample = true


## Advance the hold on a charged shot.
##
## A charge only survives [constant State.READY]. Spending the shot or losing
## the state drops it, so nothing can be banked across the reload -- the
## downtime is the game and a stored charge would be a way around it.
func _step_charge(delta: float) -> void:
	if not profile.charge_enabled:
		return
	if _state != State.READY:
		if _charging:
			_end_charge(_charge)
		return
	if not _charging and profile.charge_auto_begins_when_ready:
		begin_charge()
	if not _charging:
		return
	var full: float = maxf(profile.charge_full_seconds, 0.0)
	_set_charge(1.0 if full <= 0.0 else minf(_charge + delta / full, 1.0))


## Fly every round in the air, and report the ones that landed.
##
## Walked backwards so a round resolving does not shuffle the ones behind it.
## Under the shipped hitscan model the array is always empty and this is one
## [method Array.is_empty] call per tick.
func _step_projectiles(delta: float) -> void:
	if _projectiles.is_empty():
		return
	var index: int = _projectiles.size() - 1
	while index >= 0:
		var round_shot: WeaponProjectile = _projectiles[index]
		if not is_instance_valid(round_shot):
			_projectiles.remove_at(index)
		elif round_shot.advance(delta):
			_projectiles.remove_at(index)
			_report(round_shot)
			round_shot.queue_free()
		index -= 1


## Turn a resolved round into the same [signal target_hit] or [signal missed]
## a hitscan shot would have emitted. The point of the exercise: nothing
## downstream can tell which model fired.
func _report(round_shot: WeaponProjectile) -> void:
	if round_shot.has_hit():
		target_hit.emit(
			round_shot.get_collider(), round_shot.get_end_point(), round_shot.get_normal()
		)
	else:
		missed.emit(round_shot.get_end_point())


## Put a round in the air along the line the shot actually took.
func _launch(origin: Vector3, direction: Vector3, travel_range: float, charge: float) -> void:
	var parent: Node = tracer_parent if tracer_parent != null else self
	var exclude: Array[RID] = []
	if shooter_body != null:
		exclude.append(shooter_body.get_rid())
	var speed: float = profile.get_charged_projectile_speed(charge)
	_projectiles.append(
		WeaponProjectile.launch(parent, origin, direction, speed, travel_range, profile, exclude)
	)
	projectile_launched.emit(origin, direction, speed)


## Announce the wind-up once, on the tick the reload crosses into it.
func _announce_windup() -> void:
	if _windup_announced or not is_winding_up():
		return
	_windup_announced = true
	reload_windup_started.emit(maxf(_reload_seconds - _state_elapsed, 0.0))


func _set_charge(value: float) -> void:
	var clamped: float = clampf(value, 0.0, 1.0)
	if is_equal_approx(clamped, _charge):
		return
	_charge = clamped
	charge_changed.emit(_charge)


## End a hold, whether it was fired or dropped, and say what it was worth.
func _end_charge(held: float) -> void:
	if not _charging and _charge <= 0.0:
		return
	_charging = false
	_set_charge(0.0)
	charge_released.emit(held)


# --- Scatter ------------------------------------------------------------------

## The direction a shot actually leaves along.
##
## Returns [param aim] ITSELF for a profile with no spread, rather than a
## zero-angle deflection of it. That is not an optimisation: a zero-width random
## draw would still be a floating-point round trip through a normalisation, and
## the shipped weapon's contract is that the shot line and the aim line are the
## same vector.
func _scatter(origin: Vector3, aim: Vector3, travel_range: float, charge: float) -> Vector3:
	if not profile.has_spread():
		return aim
	var distance: float = -1.0
	if profile.needs_range_probe():
		distance = _probe_distance(origin, aim, travel_range)
	var cone: float = profile.get_spread_degrees(_motion_speed, _ready_elapsed, distance, charge)
	if cone <= 0.0:
		return aim
	return _deflect(aim, deg_to_rad(cone))


## [param aim] pushed off by a random angle inside a cone of half-angle
## [param half_angle].
##
## Uniform over the disc the cone projects onto, not over the angle, so a wider
## cone does not pile shots up in the middle: the group a sweep measures is the
## group the number describes.
func _deflect(aim: Vector3, half_angle: float) -> Vector3:
	var rng: RandomNumberGenerator = _spread_rng()
	var angle: float = half_angle * sqrt(rng.randf())
	var roll: float = rng.randf() * TAU
	# Any vector not parallel to the aim seeds the cross section; UP fails only
	# when firing exactly vertically, hence the fallback.
	var side: Vector3 = aim.cross(Vector3.UP)
	if side.length_squared() < 1e-6:
		side = aim.cross(Vector3.RIGHT)
	side = side.normalized()
	var up: Vector3 = side.cross(aim).normalized()
	var offset: Vector3 = (side * cos(roll) + up * sin(roll)) * tan(angle)
	return (aim + offset).normalized()


## Metres from the muzzle to whatever the centre line is pointing at, for
## [member WeaponProfile.spread_growth_per_100m]. The full range when the line
## is pointing at nothing, because a shot into the sky is the longest shot
## there is.
func _probe_distance(origin: Vector3, aim: Vector3, travel_range: float) -> float:
	var probe: Dictionary = _cast(origin, origin + aim * travel_range)
	if probe.is_empty():
		return travel_range
	return origin.distance_to(probe.get("position", origin) as Vector3)


## The scatter RNG, built on first use and never built at all by a weapon with
## no spread. Seeded from [member WeaponProfile.spread_seed] so a sweep can hold
## the draw sequence fixed across arms and measure the setting rather than the
## luck.
func _spread_rng() -> RandomNumberGenerator:
	if _rng == null:
		_rng = RandomNumberGenerator.new()
		if profile != null and profile.spread_seed != 0:
			_rng.seed = profile.spread_seed
		else:
			_rng.randomize()
	return _rng


## Take the weapon the rules are handing out, if they are handing one out.
##
## Written into [member profile] rather than held alongside it, so that
## [code]rifle.profile[/code] remains the single answer for [MatchController],
## [TowerShooter] and [WeaponFeel], all of which read it. A second, hidden
## profile would be a class of bug nobody would find twice.
##
## Runs at the moment [member rules] is assigned rather than on the next tick,
## which matters: [MatchController] sets the rules and then immediately reads
## the profile's reload numbers off the weapon, and it has to read the new
## weapon's.
func _adopt_rules_profile() -> void:
	var supplied: WeaponProfile = read_rules_profile(_rules)
	if supplied == null or supplied == profile:
		return
	profile = supplied
	_rng = null
	reload_seconds = get_base_reload_seconds()
