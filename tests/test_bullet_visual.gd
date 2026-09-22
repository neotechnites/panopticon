extends TestCase

## The round you SEE, against the round the game actually resolves.
##
## [WeaponProjectile] flies two kinds of round down the same [method
## WeaponProjectile.advance]: the live one the authority scores, and the
## cosmetic twin a watching peer draws. This file asserts the two things that
## keep the picture honest -- the twin rides the host's flight tick for tick
## rather than running a clock of its own, and the geometry that draws it is one
## mesh and one material shared by every round in the air, not a fresh pair per
## shot.
##
## Every flight is flown by explicit [method Rifle.tick] calls with [constant
## TestCase.SIM_DELTA]. The rig is the one [code]test_projectile_lever.gd[/code]
## uses: a private floor far above the arena, a private profile and private
## rules, and a world node that owns every round so the test can see what is in
## the air by looking at its own children.

## The private floor's top surface, far above anything the ring occupies.
const FLOOR_TOP: float = 2000.0

## Eye height above that floor. The shot line is horizontal at this height.
const EYE_HEIGHT: float = 1.6

## Where every shot in this file starts, and the rifle's own origin.
const ORIGIN: Vector3 = Vector3(0.0, FLOOR_TOP + EYE_HEIGHT, 0.0)

## Half-thickness of every test box along the shot axis.
const TARGET_HALF_DEPTH: float = 0.5

## The body the live round is fired at, in metres.
const BODY_DISTANCE: float = 30.0

## Where the cosmetic twin is told the shot ended: the body's near face, which
## is where the live round will stop, so the two flights share a length.
const REPLAY_DISTANCE: float = BODY_DISTANCE - TARGET_HALF_DEPTH

## Slow enough that the flight is many ticks long and fast enough to be a shot.
const SHOT_SPEED: float = 150.0

## Length of each replayed line in the mesh test.
const VISUAL_DISTANCE: float = 40.0

## Yaw of the second replayed line, so the two rounds cannot share a heading.
const YAW_DEGREES: float = 20.0

## How closely a round's own -Z must point down its flight line.
const AIM_DOT: float = 0.999

## The twin is the SAME arithmetic as the live round, so this is a bit-equality
## tolerance in all but name.
const TWIN_TOLERANCE: float = 1.0e-4

## Tolerance against the analytic line, which accumulates over the flight.
const LINE_TOLERANCE: float = 1.0e-3

## Ticks the paired flight must be compared over before the test believes it.
const MIN_COMPARED_TICKS: int = 8

## Ticks a flight is given before the test gives up on it.
const MAX_FLIGHT_TICKS: int = 600

var _world: Node3D
var _rifle: Rifle
var _profile: WeaponProfile
var _rules: MatchRules


func before_each() -> void:
	# One node owns the world half of the rig: the floor, the target, and --
	# because it is handed to Rifle.tracer_parent -- every round in the air.
	# Freeing it frees all of them.
	_world = Node3D.new()
	_world.name = "BulletVisualWorld"
	add_child(_world)

	var floor_body: StaticBody3D = TestFixtures.make_floor(FLOOR_TOP)
	_world.add_child(floor_body)

	_profile = TestFixtures.weapon_profile()
	_rules = TestFixtures.match_rules()

	_rifle = (load(TestFixtures.RIFLE_SCENE_PATH) as PackedScene).instantiate() as Rifle
	TestFixtures.silence_human_input(_rifle)
	# Both assigned before the instance enters the tree, and both private
	# duplicates: writing the speed lever into a shared .tres would retune every
	# later test in the same process.
	_rifle.profile = _profile
	_rifle.rules = _rules
	add_child(_rifle)

	# The rifle has no aim_source, so its own -Z is the shot line.
	_rifle.global_transform = Transform3D(Basis.IDENTITY, ORIGIN)
	# Own the clock. Rounds are advanced from tick() and from nowhere else.
	_rifle.set_physics_process(false)
	# Rounds hang here rather than on the scene root, so the test can find what
	# is in the air by looking at its own node.
	_rifle.tracer_parent = _world

	# One physics frame so the floor is registered with the physics server.
	await step_ticks(1)


func after_each() -> void:
	if is_instance_valid(_rifle):
		_rifle.clear_projectiles()
		_rifle.queue_free()
	if is_instance_valid(_world):
		_world.queue_free()


# --- One flight, two rounds ---------------------------------------------------

## The cosmetic twin is the host's round, drawn -- not a second flight.
##
## A watching peer has to show the round crossing the gap while the host resolves
## it, and the only way the streak can be trusted is if the picture is at the
## same place on the same tick as the thing being pictured. So this test fires
## the live round and launches its twin on the same tick, down the same line,
## and then walks the two of them forward together: every tick both positions
## must agree with each other to [constant TWIN_TOLERANCE], and both must agree
## with the analytic line [code]origin + forward * speed * t[/code]. Comparing
## the pair alone would pass if they drifted off the line in step, and comparing
## against the line alone would not notice the picture lagging; the claim needs
## both halves.
func test_the_visual_round_rides_the_host_flight() -> void:
	_add_body(BODY_DISTANCE, "Body")
	await step_ticks(1)

	_rules.guard_projectile_speed = SHOT_SPEED
	assert_true(_rifle.try_fire(), "a READY rifle must take the shot")
	assert_eq_int(_rifle.get_projectiles_in_flight(), 1, "the live round is in the air")

	# The twin goes up on the firing tick, before anything is stepped: a replay
	# that arrived a tick late would be a tick behind for the whole flight.
	_rifle.show_remote_shot(ORIGIN, ORIGIN + Vector3.FORWARD * REPLAY_DISTANCE, _rifle.reload_seconds)
	assert_eq_int(_rifle.get_visual_rounds_in_flight(), 1, "and the cosmetic twin beside it")

	var ticks: int = 0
	var compared: int = 0
	var on_line_ticks: int = 0
	while _both_in_the_air() and ticks < MAX_FLIGHT_TICKS:
		_rifle.tick(SIM_DELTA)
		ticks += 1
		if not _both_in_the_air():
			break

		var live: WeaponProjectile = _round_in_world(false)
		var twin: WeaponProjectile = _round_in_world(true)
		if live == null or twin == null:
			fail("both rounds are reachable under the rifle's tracer parent on tick %d" % ticks)
			break

		var flown: float = float(ticks) * SIM_DELTA
		if not assert_vec3_almost_eq(
			twin.global_position, live.global_position, TWIN_TOLERANCE,
			"the twin is where the live round is on tick %d" % ticks,
		):
			break
		if not assert_vec3_almost_eq(
			live.global_position, ORIGIN + Vector3.FORWARD * SHOT_SPEED * flown, LINE_TOLERANCE,
			"and both are on origin + forward * speed * t on tick %d" % ticks,
		):
			break
		compared += 1

		# The shooter's own eye is the origin (no camera here). The bullet is drawn
		# on the muzzle-to-line blend, sized in view angle between the floor and the cap.
		var visual: MeshInstance3D = _visual_of(twin)
		var blend: float = 1.0 - clampf(SHOT_SPEED * flown / WeaponProjectile.MUZZLE_BLEND_METRES, 0.0, 1.0)
		var expected_at: Vector3 = twin.global_position + (_rifle.muzzle.global_position - ORIGIN) * blend
		if not assert_vec3_almost_eq(
			twin.get_visual_position(), expected_at, LINE_TOLERANCE,
			"the bullet is drawn on the muzzle blend at %.1f m" % (SHOT_SPEED * flown),
		):
			break
		var distance: float = twin.get_visual_position().distance_to(ORIGIN)
		var expected_scale: float = clampf(
			1.0,
			distance * WeaponProjectile.MIN_VIEW_RADIANS / _profile.tracer_width,
			distance * WeaponProjectile.MAX_VIEW_RADIANS / _profile.tracer_width,
		)
		assert_true(visual != null and visual.visible, "the bullet is drawn at %.1f m" % distance)
		if not assert_almost_eq(
			twin.get_visual_scale(), expected_scale, 1.0e-6,
			"and sized between the view-angle floor and cap at %.1f m" % distance,
		):
			break
		if blend <= 0.0:
			on_line_ticks += 1

	assert_gt(float(on_line_ticks), 0.0, "past the blend the bullet rides the flight line itself")
	assert_gt(
		float(compared), float(MIN_COMPARED_TICKS) - 1.0,
		"the pair was compared over a real flight, not one or two ticks of it",
	)
	# Neither round is left in the sky: the live one stops at the body's near
	# face and the twin runs out of the range the authority gave it.
	var cleared: int = _fly_until_the_sky_is_empty(ticks)
	assert_lt(
		float(cleared), float(MAX_FLIGHT_TICKS),
		"both rounds left the air rather than running to the flight cap",
	)
	assert_eq_int(_rifle.get_projectiles_in_flight(), 0, "no live round is left flying")
	assert_eq_int(_rifle.get_visual_rounds_in_flight(), 0, "and no cosmetic one either")


# --- Another player's eye ----------------------------------------------------

## A bystander's camera far off the line draws the bullet from its first tick, at least full size.
const BYSTANDER_METRES: float = 80.0


func test_the_bullet_is_seen_whole_from_another_players_eye() -> void:
	var camera: Camera3D = Camera3D.new()
	_world.add_child(camera)
	camera.global_position = ORIGIN + Vector3.RIGHT * BYSTANDER_METRES
	camera.current = true
	await step_ticks(1)

	_rules.guard_projectile_speed = SHOT_SPEED
	_rifle.show_remote_shot(ORIGIN, ORIGIN + Vector3.FORWARD * VISUAL_DISTANCE, _rifle.reload_seconds)
	_rifle.tick(SIM_DELTA)
	var twin: WeaponProjectile = _round_in_world(true)
	assert_not_null(twin, "the replay is in the air")
	var visual: MeshInstance3D = _visual_of(twin) if twin != null else null
	assert_true(visual != null and visual.visible, "a bystander sees the bullet on its first tick")
	var distance: float = twin.get_visual_position().distance_to(camera.global_position) if twin != null else 0.0
	assert_almost_eq(
		twin.get_visual_scale() if twin != null else 0.0,
		maxf(1.0, distance * WeaponProjectile.MIN_VIEW_RADIANS / _profile.tracer_width), 1.0e-6,
		"and lifted to the view-angle floor, %.0f m from their eye" % BYSTANDER_METRES,
	)
	camera.current = false
	camera.queue_free()


## A round with no muzzle offset starts at the eye: hidden on the trigger frame,
## drawn one tick later.
func test_the_bullet_is_hidden_at_the_eye_itself() -> void:
	var exclude: Array[RID] = []
	var round_shot: WeaponProjectile = WeaponProjectile.launch(
		_world, ORIGIN, Vector3.FORWARD, SHOT_SPEED, VISUAL_DISTANCE, _profile, exclude, true
	)
	var visual: MeshInstance3D = _visual_of(round_shot)
	assert_true(visual != null and not visual.visible, "at the eye the bullet is not drawn")
	assert_almost_eq(round_shot.get_visual_scale(), 0.0, 1.0e-6, "and its scale is zero")
	round_shot.advance(SIM_DELTA)
	assert_true(visual != null and visual.visible, "one tick out it is drawn")
	assert_gt(round_shot.get_visual_scale(), 0.0, "at a size above zero")
	assert_vec3_almost_eq(
		round_shot.get_visual_position(), round_shot.global_position, LINE_TOLERANCE,
		"and, with no muzzle to blend from, exactly on the flight line",
	)
	round_shot.queue_free()


# --- One mesh, one material ---------------------------------------------------

## Every round in the air draws the same geometry and the same material.
##
## The look of a round is a fixed [constant WeaponProjectile.VISUAL_TRIANGLES]
## triangles, identical for every shot, so building a mesh and a material per
## round would be an allocation per trigger pull for a shape that never differs.
## What differs between two shots is the heading, and the heading belongs in the
## transform: the shared mesh is authored down one axis and each round is TURNED
## onto its own line. This test fires two replays twenty degrees apart and
## asserts exactly that -- one mesh object, one material object, and two bases
## that each point their own -Z down their own shot line.
func test_one_bullet_mesh_and_material_are_shared() -> void:
	_rules.guard_projectile_speed = SHOT_SPEED

	var straight: Vector3 = Vector3.FORWARD
	var yawed: Vector3 = Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(YAW_DEGREES))
	_rifle.show_remote_shot(ORIGIN, ORIGIN + straight * VISUAL_DISTANCE, _rifle.reload_seconds)
	_rifle.show_remote_shot(ORIGIN, ORIGIN + yawed * VISUAL_DISTANCE, _rifle.reload_seconds)
	assert_eq_int(_rifle.get_visual_rounds_in_flight(), 2, "both replays put a round in the air")

	var rounds: Array[WeaponProjectile] = _rounds_in_world()
	assert_eq_int(rounds.size(), 2, "and both are reachable under the rifle's tracer parent")
	if rounds.size() != 2:
		return

	var first: MeshInstance3D = _visual_of(rounds[0])
	var second: MeshInstance3D = _visual_of(rounds[1])
	assert_not_null(first, "the first round carries a MeshInstance3D named Round")
	assert_not_null(second, "the second round carries one too")
	if first == null or second == null:
		return

	assert_same(second.mesh, first.mesh, "both rounds draw the one shared mesh")
	assert_same(
		second.material_override, first.material_override,
		"and wear the one shared material",
	)

	var mesh: ArrayMesh = first.mesh as ArrayMesh
	assert_not_null(mesh, "the shared mesh is an ArrayMesh")
	if mesh != null:
		assert_eq_int(int(mesh.get_surface_count()), 1, "built as a single surface")
		var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		assert_eq_int(
			vertices.size(), WeaponProjectile.VISUAL_TRIANGLES * 3,
			"non-indexed, so it is three vertices per declared triangle",
		)

	# The shape is shared; the heading is not. Each round's own -Z is its line.
	assert_gt(
		(-first.transform.basis.z).dot(straight), AIM_DOT,
		"the first round is turned onto the line it was replayed along",
	)
	assert_gt(
		(-second.transform.basis.z).dot(yawed), AIM_DOT,
		"and the second onto its own, twenty degrees off the first",
	)


# --- Rig ----------------------------------------------------------------------

## A static box on the shot line, [param distance] metres down it.
func _add_body(distance: float, node_name: String) -> StaticBody3D:
	var body: StaticBody3D = TestFixtures.make_box_body(
		Vector3(6.0, 6.0, TARGET_HALF_DEPTH * 2.0),
		ORIGIN + Vector3.FORWARD * distance,
		node_name,
	)
	_world.add_child(body)
	return body


## True while the rifle is flying one live round and one cosmetic one.
func _both_in_the_air() -> bool:
	return _rifle.get_projectiles_in_flight() > 0 and _rifle.get_visual_rounds_in_flight() > 0


## Step the weapon until nothing is left flying, and return the total tick count
## including the [param ticks] already spent.
func _fly_until_the_sky_is_empty(ticks: int) -> int:
	var total: int = ticks
	while total < MAX_FLIGHT_TICKS:
		if _rifle.get_projectiles_in_flight() == 0 and _rifle.get_visual_rounds_in_flight() == 0:
			break
		_rifle.tick(SIM_DELTA)
		total += 1
	return total


## Every live [WeaponProjectile] hanging off the rifle's tracer parent, in the
## order they were launched. Rounds already freed are not in the air.
func _rounds_in_world() -> Array[WeaponProjectile]:
	var found: Array[WeaponProjectile] = []
	for child: Node in _world.get_children():
		var round_shot: WeaponProjectile = child as WeaponProjectile
		if round_shot == null or round_shot.is_queued_for_deletion():
			continue
		found.append(round_shot)
	return found


## The one round of the asked-for kind, or null when there is not exactly one.
func _round_in_world(cosmetic: bool) -> WeaponProjectile:
	var found: WeaponProjectile = null
	for round_shot: WeaponProjectile in _rounds_in_world():
		if round_shot.is_cosmetic() != cosmetic:
			continue
		if found != null:
			return null
		found = round_shot
	return found


## The [MeshInstance3D] a round draws itself with, by the name the contract
## gives it, or null when the round has no visual.
func _visual_of(round_shot: WeaponProjectile) -> MeshInstance3D:
	for child: Node in round_shot.get_children():
		if child.name == "Round":
			return child as MeshInstance3D
	return null
