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

## Tunables. Without one the rifle cannot fire and says so rather than falling
## back on invented numbers.
@export var profile: WeaponProfile

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

var _state: State = State.READY

## Seconds spent in the current state. The reload is measured as elapsed rather
## than as a countdown deliberately -- see [member reload_seconds].
var _state_elapsed: float = 0.0

## Backing store for [member reload_seconds].
var _reload_seconds: float = 0.0


## The live reload duration, in seconds.
##
## Starts at [member WeaponProfile.base_reload_seconds] and is meant to be
## written at runtime: the design calls for the rifle to get faster as a match
## progresses, so this is a property with a signal rather than a constant read
## out of the profile. The profile's value is the starting point, never the
## current truth. Writes are clamped to
## [member WeaponProfile.min_reload_seconds].
##
## Changing it mid-reload takes effect on that same reload, because the reload
## is tracked as elapsed time compared against this value rather than as a
## countdown seeded at the start. Shortening the reload below the time already
## served completes it immediately, which is the behaviour a progression rule
## wants: "reloads are 1.2 s now" should mean now, not next shot.
var reload_seconds: float:
	get:
		return _reload_seconds
	set(value):
		var clamped: float = profile.clamp_reload_seconds(value) if profile != null else maxf(value, 0.0)
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
	reload_seconds = _reload_seconds if _reload_seconds > 0.0 else profile.base_reload_seconds


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
	if profile == null or _state == State.READY:
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
			if _state_elapsed >= _reload_seconds:
				_finish_reload()
		return

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
	_resolve_shot()
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


## Restore the reload to the profile's starting value. For a match reset, so
## progression cannot leak across rounds.
func reset_reload_to_base() -> void:
	if profile == null:
		return
	reload_seconds = profile.base_reload_seconds


# --- Shot resolution ----------------------------------------------------------

## Cast the ray, announce what happened, draw the tracer.
##
## Order matters: [signal fired] goes out before [signal target_hit], so a
## listener that reacts to the tower having given itself away sees the shot even
## if a hit listener removes the target and tears down half the scene.
func _resolve_shot() -> void:
	var source: Node3D = aim_source if aim_source != null else self
	var origin: Vector3 = source.global_position
	# -Z is forward for every Node3D in Godot, cameras included, so this reads
	# the aim of a camera and of a bot's bare head pivot identically.
	var direction: Vector3 = -source.global_transform.basis.z.normalized()
	var far_point: Vector3 = origin + direction * profile.max_range

	var hit: Dictionary = _cast(origin, far_point)
	var end_point: Vector3 = far_point
	var collider: Node3D = null
	var normal: Vector3 = -direction
	if not hit.is_empty():
		end_point = hit.get("position", far_point)
		normal = hit.get("normal", -direction)
		collider = hit.get("collider", null) as Node3D

	# The tracer starts at the barrel, not the eye, so it looks like it left the
	# weapon -- but it ends where the shot truly ended, so back-projecting it
	# still gives an observer the tower's position to within the muzzle offset.
	var muzzle_node: Node3D = muzzle if muzzle != null else source
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
	if profile.tracer_lifetime <= 0.0:
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
	state_changed.emit(previous, _state)


func _begin_reload() -> void:
	_set_state(State.RELOADING)
	reload_started.emit(_reload_seconds)


func _finish_reload() -> void:
	_set_state(State.READY)
	reload_finished.emit()
