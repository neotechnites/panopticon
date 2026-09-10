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

## The barrel end the tracer leaves from, in the model's own coordinates.
##
## Taken from tools/modelling/rifle_build.py, which puts the tip of the muzzle
## brake at MUZZLE_Y = 1.150 along Blender's forward axis -- Godot local -Z.
const MODEL_MUZZLE: Vector3 = Vector3(0.0, 0.0, -1.150)

## How far off the aim axis the barrel end must sit, in degrees, seen from the
## eye. A view model in the lower corner is normal; one whose muzzle creeps onto
## the crosshair blinds the tower, which sits in a mirrored box for the express
## purpose of seeing the whole ring. This is the floor on "get out of the way".
const MIN_OFF_AXIS_DEGREES: float = 12.0

## The camera's near plane, from Camera3D's default. Nothing in the view model
## may cross it or the guard looks through a sliced-open receiver.
const NEAR_PLANE: float = 0.05

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


# --- The view model -----------------------------------------------------------

## The muzzle marker is the model's barrel end, not a number somebody typed.
##
## It is a sibling of the mesh under the same ViewModel transform and carries the
## model's own muzzle coordinate, so retuning where the rifle is held moves the
## tracer origin with it. Break that and the tracer starts in mid-air next to the
## gun, which is precisely the bug the marker exists to prevent.
func test_the_muzzle_marker_sits_at_the_model_s_barrel_end() -> void:
	var view_model: Node3D = _rifle.get_node_or_null(^"ViewModel") as Node3D
	assert_not_null(view_model, "scenes/weapon/rifle.tscn must carry a ViewModel node")

	var muzzle: Node3D = _rifle.muzzle
	assert_not_null(muzzle, "Rifle.muzzle must still resolve after the mesh was attached")
	assert_same(
		muzzle.get_parent(), view_model,
		"the muzzle rides the ViewModel transform, so it cannot drift from the barrel",
	)
	assert_vec3_almost_eq(
		muzzle.position, MODEL_MUZZLE, 1e-4,
		"the muzzle marker is at the model's own barrel end, in the model's coordinates",
	)

	var mesh: MeshInstance3D = _find_mesh(view_model)
	assert_not_null(mesh, "the ViewModel must actually contain the imported rifle mesh")
	assert_true(mesh.visible, "the view model is drawn, or the guard is holding nothing")


## The view model stays out of the guard's way, and out of the near plane.
##
## Both numbers are framing, which cannot be judged headless -- but the two
## failure modes that matter are arithmetic and can be: geometry behind the near
## plane (the receiver sliced open across the screen) and a barrel end that has
## crept back onto the crosshair.
func test_the_view_model_clears_the_crosshair_and_the_near_plane() -> void:
	var view_model: Node3D = _rifle.get_node_or_null(^"ViewModel") as Node3D
	assert_not_null(view_model, "scenes/weapon/rifle.tscn must carry a ViewModel node")

	# The rifle root is at identity and its aim source is itself, so local space
	# here is exactly what camera space is in a match: the origin is the eye and
	# -Z is the shot line.
	var mesh: MeshInstance3D = _find_mesh(view_model)
	assert_not_null(mesh, "the ViewModel must actually contain the imported rifle mesh")
	var box: AABB = mesh.global_transform * mesh.get_aabb()
	assert_lt(
		box.end.z, -NEAR_PLANE,
		"every vertex of the view model sits in front of the camera's near plane",
	)

	var to_muzzle: Vector3 = _rifle.to_local(_rifle.muzzle.global_position)
	assert_gt(
		rad_to_deg(to_muzzle.angle_to(Vector3.FORWARD)), MIN_OFF_AXIS_DEGREES,
		"the barrel end sits well off the aim axis, so it never covers the crosshair",
	)
	assert_gt(to_muzzle.x, 0.0, "the rifle is held to the right of the bore line")
	assert_lt(to_muzzle.y, 0.0, "and below the eye, so the guard looks down onto the scope")


## Hanging a mesh on the rifle did not move a single shot.
##
## The ray is the eye's on purpose -- no parallax between the crosshair and where
## the round goes -- and the muzzle only decides where the visible streak starts.
## This test is the guarantee that the two never got confused: the muzzle is more
## than a metre from the eye, and the shot still starts at the eye and lands dead
## ahead.
func test_the_view_model_does_not_move_the_shot_line() -> void:
	var offset: float = _rifle.muzzle.global_position.distance_to(_rifle.global_position)
	assert_gt(offset, 1.0, "the muzzle is out at the barrel end, a long way from the aim source")

	assert_true(_rifle.try_fire(), "a READY rifle must take the shot")
	assert_vec3_almost_eq(
		_last_shot_origin, Vector3.ZERO, 0.001,
		"the ray still starts at the aim source and not at the barrel",
	)
	assert_vec3_almost_eq(
		_last_hit_position,
		Vector3(0.0, 0.0, -(TARGET_DISTANCE - TARGET_HALF_DEPTH)),
		0.01,
		"and still lands where it did before the mesh existed",
	)


## The mesh belongs to the rifle, so it changes hands with the seat.
##
## MatchController._attach_rifle reparents this whole scene onto the new holder's
## head and resets its transform. Anything the view model needs has to survive
## that, which is why the mesh and the muzzle are children of the rifle rather
## than nodes the tower's body owns.
func test_the_view_model_survives_a_seat_change() -> void:
	var muzzle_before: Node3D = _rifle.muzzle
	var mesh_before: MeshInstance3D = _find_mesh(_rifle)
	assert_not_null(mesh_before, "the rifle carries its own mesh before the seat changes")
	# In the RIFLE's frame, so a seat that faces a different way does not read as
	# the view model having moved.
	var offset_before: Vector3 = _rifle.to_local(muzzle_before.global_position)

	# Exactly what MatchController._attach_rifle does, minus the participant.
	var seat: Node3D = Node3D.new()
	seat.name = "NewSeat"
	add_child(seat)
	seat.global_transform = Transform3D(
		Basis(Vector3.UP, deg_to_rad(140.0)), Vector3(7.0, 1.65, -3.0)
	)
	var previous: Node = _rifle.get_parent()
	previous.remove_child(_rifle)
	seat.add_child(_rifle)
	_rifle.transform = Transform3D.IDENTITY

	assert_same(_rifle.muzzle, muzzle_before, "the muzzle node is the same node after the move")
	assert_true(_rifle.muzzle.is_inside_tree(), "and it is still in the tree")
	assert_same(_find_mesh(_rifle), mesh_before, "the mesh moved with the rifle")
	assert_true(mesh_before.is_inside_tree(), "and is still in the tree")

	assert_vec3_almost_eq(
		_rifle.to_local(_rifle.muzzle.global_position), offset_before, 1e-4,
		"the barrel end sits at the same offset from the new holder's eye",
	)


## First [MeshInstance3D] anywhere under [param root], or null.
##
## Found by type rather than by path: the mesh's name comes from inside
## assets/models/rifle.glb, and a reimport is allowed to change it.
func _find_mesh(root: Node) -> MeshInstance3D:
	for child: Node in root.get_children():
		var found: MeshInstance3D = child as MeshInstance3D
		if found != null:
			return found
		var deeper: MeshInstance3D = _find_mesh(child)
		if deeper != null:
			return deeper
	return null


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
