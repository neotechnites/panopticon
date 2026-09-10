extends TestCase

## [Rifle]: one shot, then a long enforced silence.
##
## The reload is the clock the whole match runs on, so these tests are about the
## cycle far more than about the raycast. They drive it through
## [method Rifle.tick] with explicit deltas rather than letting
## [code]_physics_process[/code] run, which is the weapon's own documented
## harness seam: a cycle measured against a real clock would be a test of how
## busy CI was.

## Distance from the muzzle to the test target, in metres.
const TARGET_DISTANCE: float = 20.0

## Half-thickness of the target box along the shot axis, so the expected impact
## point is [code]TARGET_DISTANCE - TARGET_HALF_DEPTH[/code].
const TARGET_HALF_DEPTH: float = 0.5

## A delta small enough to be "the next tick" and large enough to cross a
## boundary the weapon has already reached.
const NUDGE: float = 0.001

var _rifle: Rifle
var _profile: WeaponProfile
var _target: StaticBody3D

var _hits: int = 0
var _misses: int = 0
var _shots: int = 0
var _reload_changes: int = 0
var _last_collider: Node3D = null
var _last_hit_position: Vector3 = Vector3.ZERO
var _last_shot_origin: Vector3 = Vector3.ZERO
var _last_shot_end: Vector3 = Vector3.ZERO


func before_each() -> void:
	_target = TestFixtures.make_box_body(
		Vector3(6.0, 6.0, TARGET_HALF_DEPTH * 2.0),
		Vector3(0.0, 0.0, -TARGET_DISTANCE),
		"Target",
	)
	add_child(_target)

	_profile = TestFixtures.weapon_profile()
	_rifle = (load(TestFixtures.RIFLE_SCENE_PATH) as PackedScene).instantiate() as Rifle
	TestFixtures.silence_human_input(_rifle)
	# Assigned before the instance enters the tree: Rifle._ready seeds
	# reload_seconds from it, and the scene's own copy is a shared resource that
	# a test must never write into.
	_rifle.profile = _profile
	add_child(_rifle)

	# The rifle's own -Z is the shot line; nothing else in the scene aims it.
	_rifle.global_transform = Transform3D.IDENTITY
	# Own the clock. _physics_process is only ever a caller of tick().
	_rifle.set_physics_process(false)

	_rifle.target_hit.connect(_on_target_hit)
	_rifle.missed.connect(_on_missed)
	_rifle.fired.connect(_on_fired)
	_rifle.reload_duration_changed.connect(_on_reload_duration_changed)

	# One physics frame so the target is registered with the physics server.
	# Without it the space is empty and every shot below is a miss -- and a miss
	# reads exactly like a broken collision mask.
	await step_ticks(1)


# --- Hitscan ------------------------------------------------------------------

## A shot connects and hands back the thing it struck.
func test_a_shot_hits_and_reports_the_collider() -> void:
	assert_true(_rifle.try_fire(), "a READY rifle must take the shot")

	assert_eq_int(_shots, 1, "exactly one fired signal per shot")
	assert_eq_int(_hits, 1, "the shot should have connected")
	assert_eq_int(_misses, 0, "a hit is not also a miss")
	assert_same(_last_collider, _target, "target_hit must report the collider that was struck")

	assert_vec3_almost_eq(
		_last_hit_position,
		Vector3(0.0, 0.0, -(TARGET_DISTANCE - TARGET_HALF_DEPTH)),
		0.01,
		"the impact point is the near face of the target",
	)
	assert_vec3_almost_eq(
		_last_shot_origin, Vector3.ZERO, 0.001,
		"the shot starts at the aim source, not at the muzzle offset",
	)


## A shot with nothing in front of it is a miss, and costs exactly the same.
##
## Missing has to be as expensive as hitting or the tower can sweep the ring for
## free, which deletes the reason the reload exists.
func test_a_missing_shot_still_spends_the_reload() -> void:
	_target.position = Vector3(0.0, 500.0, 0.0)
	await step_ticks(1)

	assert_true(_rifle.try_fire(), "a READY rifle takes the shot whether or not it will connect")
	assert_eq_int(_misses, 1, "nothing was in the way, so the shot missed")
	assert_eq_int(_hits, 0, "a miss must not report a hit")
	assert_vec3_almost_eq(
		_last_shot_end, Vector3(0.0, 0.0, -_profile.max_range), 0.01,
		"a miss ends at max_range",
	)
	assert_almost_eq(
		_rifle.get_time_to_ready(),
		_profile.shot_duration + _profile.base_reload_seconds,
		1e-5,
		"a miss costs the full firing window plus reload",
	)


# --- The cycle ----------------------------------------------------------------

## The second trigger pull inside a cycle is refused, at every point in it.
func test_a_second_shot_during_the_reload_is_refused() -> void:
	assert_true(_rifle.try_fire(), "the first shot is allowed")
	assert_eq_int(int(_rifle.get_state()), int(Rifle.State.FIRING), "a shot enters FIRING")

	assert_false(_rifle.try_fire(), "no second shot during the firing window")
	assert_false(_rifle.can_fire(), "can_fire agrees with try_fire during FIRING")

	# Into the reload proper.
	_rifle.tick(_profile.shot_duration + NUDGE)
	assert_eq_int(int(_rifle.get_state()), int(Rifle.State.RELOADING), "FIRING gives way to RELOADING")
	assert_false(_rifle.try_fire(), "no second shot at the start of the reload")

	# Most of the way through it.
	_rifle.tick(_rifle.reload_seconds * 0.9)
	assert_eq_int(int(_rifle.get_state()), int(Rifle.State.RELOADING), "still reloading at 90%")
	assert_false(_rifle.try_fire(), "no second shot at 90% of the reload")

	assert_eq_int(_shots, 1, "four trigger pulls, one shot")


## The weapon comes back, and comes back on time.
func test_firing_resumes_after_the_reload() -> void:
	assert_true(_rifle.try_fire(), "the first shot is allowed")

	# One tick short of ready: still refused. This is the assertion that catches
	# an off-by-one that would hand the tower a free early shot.
	_rifle.tick(_profile.shot_duration + _rifle.reload_seconds - NUDGE)
	assert_false(_rifle.can_fire(), "the weapon is not ready one millisecond early")

	_rifle.tick(NUDGE * 2.0)
	assert_eq_int(int(_rifle.get_state()), int(Rifle.State.READY), "the cycle ends in READY")
	assert_almost_eq(_rifle.get_time_to_ready(), 0.0, 1e-6, "a READY weapon is ready now")
	assert_almost_eq(_rifle.get_reload_progress(), 1.0, 1e-6, "reload progress is complete")

	assert_true(_rifle.try_fire(), "the weapon fires again once the reload is served")
	assert_eq_int(_shots, 2, "two cycles, two shots")


# --- Runtime reload changes ---------------------------------------------------

## [member Rifle.reload_seconds] is live, and shortening it means *now*.
##
## Match progression is meant to speed the rifle up as a round wears on, so the
## reload is tracked as elapsed time compared against the current value rather
## than as a countdown seeded when the reload began. Cutting it below the time
## already served must therefore end the reload on the spot -- if it only took
## effect on the following shot, every progression rule in the game would be one
## cycle late.
func test_a_runtime_reload_change_takes_effect() -> void:
	assert_almost_eq(
		_rifle.reload_seconds, _profile.base_reload_seconds, 1e-6,
		"the rifle starts at the profile's base reload",
	)

	# A change before firing changes the whole next cycle.
	_rifle.reload_seconds = 1.0
	assert_eq_int(_reload_changes, 1, "changing the duration announces it")
	assert_true(_rifle.try_fire(), "the shot is allowed")
	assert_almost_eq(
		_rifle.get_time_to_ready(), _profile.shot_duration + 1.0, 1e-5,
		"the shortened reload governs the cycle it was set before",
	)

	# Half a second into a one second reload...
	_rifle.tick(_profile.shot_duration + 0.5)
	assert_eq_int(int(_rifle.get_state()), int(Rifle.State.RELOADING), "mid-reload")
	assert_almost_eq(_rifle.get_reload_progress(), 0.5, 0.02, "half the reload is served")

	# ...cut the reload below the time already served, and it is over.
	_rifle.reload_seconds = _profile.min_reload_seconds
	_rifle.tick(NUDGE)
	assert_eq_int(
		int(_rifle.get_state()), int(Rifle.State.READY),
		"shortening the reload below the time already served ends it immediately",
	)

	# The floor is the profile's, and it is not negotiable: a runaway
	# progression rule must not be able to turn a single-shot rifle automatic.
	_rifle.reload_seconds = 0.0
	assert_almost_eq(
		_rifle.reload_seconds, _profile.min_reload_seconds, 1e-6,
		"reload_seconds is clamped to WeaponProfile.min_reload_seconds",
	)

	# And a round reset puts the progression back.
	_rifle.reset_reload_to_base()
	assert_almost_eq(
		_rifle.reload_seconds, _profile.base_reload_seconds, 1e-6,
		"reset_reload_to_base undoes progression so it cannot leak across rounds",
	)


# --- Signal capture -----------------------------------------------------------

func _on_target_hit(collider: Node3D, hit_position: Vector3, _hit_normal: Vector3) -> void:
	_hits += 1
	_last_collider = collider
	_last_hit_position = hit_position


func _on_missed(end_point: Vector3) -> void:
	_misses += 1
	_last_shot_end = end_point


func _on_fired(origin: Vector3, end_point: Vector3) -> void:
	_shots += 1
	_last_shot_origin = origin
	_last_shot_end = end_point


func _on_reload_duration_changed(_duration: float) -> void:
	_reload_changes += 1
