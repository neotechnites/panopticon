extends TestCase

## Map 2's one barrier, proved by driving a body into it and by measuring its
## holes.
##
## The bars at 353 deg stand in the gap between the finish (345) and the start
## (5), and they are the only thing that stops RingBake from linking the start
## to the portal the SHORT way round -- 18 m backwards through this gap instead
## of 288 m forwards. So the gate is not scenery and "it looks closed" is not a
## test of it.
##
## [b]It was open, and a screenshot did not say so.[/b] On rock_bars' inherited
## 10.6 m width centred on the lane at r 52.0 the collider reached r
## 46.7007..57.3005 while the walkway runs r 46.7..59.55: 2.2495 m of bare floor
## outboard of the gate (Ryan, 2026-09-23: "the gate doesnt block anyone from
## going past it to the portal"). A body walked ROUND it. The gate is now
## 12.85 m wide with its centre at r 53.125, wall to lip.
##
## [b]Three ways past a barrier, three tests.[/b] Round the ends of it, through
## a hole in it, and over the top of it. The first is asked of the engine -- a
## capsule at sprint speed, resolved by [method CharacterBody3D.move_and_slide],
## not by arithmetic in this file. The second is asked of the collider, by
## raying the whole annulus at 2 cm and measuring the widest unblocked radial
## run. The third is asked of a number the jump arc fixes exactly.

## The scene under test. Instanced, driven, and freed.
const SCENE_PATH: String = "res://maps/marble/marble.tscn"

## The barrier's own node: marble_bars.glb, whose import ships
## MarbleBarsCollision (one StaticBody3D, one BoxShape3D, layer 1).
const BARS_NODE: String = "Bars"

## The gallery walkway the gate spans: an annulus at y 23.0 whose inner lip is
## open (a 24 m drop) and whose outer edge is the wall of cells.
const DECK_Y: float = 23.0
const WALKWAY_INNER_RADIUS: float = 46.7
const WALKWAY_OUTER_RADIUS: float = 59.55

## Where the gate stands and how wide it is, so a sampled world radius converts
## to a gate-local X exactly: local X is radial, so r = CENTRE_RADIUS + x.
const GATE_BEARING_DEG: float = 353.0
const GATE_CENTRE_RADIUS: float = 53.125

## [b]Which side of the gate the start is on.[/b] The gate's basis puts local +Z
## along the tangent of INCREASING bearing (local X points radially outward at
## bearing 353), and the start line is at 5 deg -- bearing greater than 353. So
## a body coming from the start has positive local Z, a body that has got past
## the bars has negative local Z, and the gate plane is z = 0.
const START_SIDE_LOCAL_Z: float = 1.0
const GATE_PLANE_LOCAL_Z: float = 0.0

## The shipped body: characters/player/player.tscn's own capsule, feet at the
## body's origin.
const BODY_RADIUS: float = 0.4
const BODY_HEIGHT: float = 1.8

## The bits the body stands on and the bits that must never see it. Layer 0 and
## mask 1 mean the map's colliders stop it and the scene's two kill Area3Ds
## (mask 1048577, monitoring for living bodies and ghosts) cannot find it: this
## test is about geometry, not about the match.
const BODY_LAYER: int = 0
const STATIC_COLLIDER_MASK: int = 1

## The sprint, from characters/player/default_movement_profile.tres.
const GROUND_SPEED: float = 11.0
const GRAVITY: float = 22.0
const JUMP_VELOCITY: float = 7.0

## Where the run starts, measured as arc along the lane from the gate plane, and
## how long it is driven: 120 ticks at 11 m/s covers 22 m, better than twice the
## 8 m it has to cross.
const RUN_START_ARC_METRES: float = 8.0
const DRIVE_TICKS: int = 120
const SETTLE_TICKS: int = 8

## Where the body is dropped: a hair over the deck, so it lands rather than
## starting inside the floor.
const STAND_CLEARANCE_METRES: float = 0.05

## A body this far under the deck has left the walkway over the open inner lip.
## That is a 24 m fall onto the spikes, not a way past the gate, so the drive
## stops there and the run is judged on where it was while it still had floor.
const FELL_OFF_THE_DECK_METRES: float = 1.0

## The radial offsets driven, spanning the walkway from a capsule's width inside
## the lip to a capsule's width inside the cell wall. Nine of them, 1.50625 m
## apart, so no 12.85 m span of gate is sampled only at its middle.
const RUN_RADIUS_MIN: float = 47.1
const RUN_RADIUS_MAX: float = 59.15
const RUN_RADIUS_COUNT: int = 9

## The ray sweep. Radius at 2 cm across the whole annulus, 45 height bands from
## just over the deck to just under the gate's 8.5 m head: 643 x 45 = 28,935
## rays, and every one of them fired through the gate along its own local Z.
## Each sample owns a cell of its own step, so an opening of n cells measures
## n * step -- the convention both axes are read with below.
const RADIUS_STEP_METRES: float = 0.02
const BAND_COUNT: int = 45
const BAND_LOW_METRES: float = 0.05
const BAND_HIGH_METRES: float = 8.45
const BAND_STEP_METRES: float = (BAND_HIGH_METRES - BAND_LOW_METRES) / float(BAND_COUNT - 1)
const RAY_HALF_LENGTH_METRES: float = 1.0

## What rock_bars guarantees and what marble_bars inherited: no gap anywhere
## wider than 0.38 m, the bar pitch being 0.342. A body is 0.8 m across, so this
## is less than half of what it would take to squeeze through.
const WIDEST_ALLOWED_OPENING_METRES: float = 0.38

## The jump, exactly: apex = v^2 / 2g = 49 / 44 = 1.113636 m over the deck. A
## body that jumps at the gate presents its crown at apex + its own 1.8 m, and
## the collider's top has to be over that by a margin nobody can bunny-hop out
## of.
const JUMP_APEX_METRES: float = 1.113636
const MIN_HEAD_CLEARANCE_METRES: float = 2.0
const APEX_TOLERANCE_METRES: float = 0.001

var _marble: Node3D
var _bars: Node3D


func before_each() -> void:
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	assert_not_null(packed, "the marble scene loads")
	if packed == null:
		return
	_marble = packed.instantiate() as Node3D
	assert_not_null(_marble, "and instances as a Node3D")
	if _marble == null:
		return
	# In the tree before anything is measured or driven: global_transform reads
	# back as the identity for a node that is not, and every frame below is the
	# gate's own.
	add_child(_marble)
	await step_ticks(1)
	_bars = _marble.get_node_or_null(NodePath(BARS_NODE)) as Node3D
	assert_not_null(_bars, "and ships a %s node" % BARS_NODE)


func after_each() -> void:
	if _marble != null and is_instance_valid(_marble):
		remove_child(_marble)
		_marble.free()
	_marble = null
	_bars = null


# --- Round the ends -----------------------------------------------------------

## Nowhere on the walkway can a sprinting body run past the bars.
##
## Nine bodies, one per radial offset across the whole annulus, each dropped on
## the deck on the START side and driven at ground speed down the lane toward
## the portal with gravity on. The engine resolves every contact: the body walks
## itself from its own [code]_physics_process[/code] and this file only reads
## back where it got to. The assertion is in the gate's own frame -- the body's
## local Z must never reach the gate plane -- because "it stopped" is a claim
## about a plane, not about a bearing.
func test_a_sprinting_body_cannot_get_past_the_bars() -> void:
	if _marble == null or _bars == null:
		fail("no scene to drive a body through")
		return
	var gate_inverse: Transform3D = _bars.global_transform.affine_inverse()

	var worst_local_z: float = INF
	var worst_radius: float = 0.0
	var ticks_driven: int = 0
	for index: int in RUN_RADIUS_COUNT:
		var radius: float = lerpf(
			RUN_RADIUS_MIN, RUN_RADIUS_MAX, float(index) / float(RUN_RADIUS_COUNT - 1)
		)
		var runner: LaneRunner = _make_runner(gate_inverse)
		add_child(runner)
		runner.global_position = _on_the_deck(radius, _start_bearing_deg(radius))
		await step_ticks(SETTLE_TICKS)
		var landed: bool = runner.is_on_floor()
		runner.begin_drive()
		await step_ticks(DRIVE_TICKS)
		var closest: float = runner.closest_local_z
		var left_the_deck: bool = runner.left_the_deck
		ticks_driven += runner.driven_ticks
		remove_child(runner)
		runner.free()

		assert_true(landed, "r %.2f: the body starts standing on the walkway" % radius)
		assert_gt(
			closest, GATE_PLANE_LOCAL_Z,
			"r %.2f: the body never reaches the gate plane%s" % [
				radius, " (it fell off the lip first)" if left_the_deck else "",
			],
		)
		if closest < worst_local_z:
			worst_local_z = closest
			worst_radius = radius

	print("      %d offsets, %d ticks driven, closest approach %.3f m from the gate plane at r %.2f" % [
		RUN_RADIUS_COUNT, ticks_driven, worst_local_z, worst_radius,
	])


# --- Through a hole -----------------------------------------------------------

## No opening across the walkway is wide enough to put a body through.
##
## The collider itself is asked, not the model: a ray along the gate's local Z
## at every 2 cm of radius across the whole annulus, in 45 height bands from the
## deck to the gate's head. Every collision body in the scene that is not part
## of the Bars is excluded by RID, so the walkway slab and the cell wall cannot
## answer for the gate. In each band the radii come back as a row of open and
## shut, and the widest contiguous unblocked run in any of them is the widest
## hole there is: it has to be under the 0.38 m rock_bars promises, which the
## bars' own 0.342 pitch is the only thing that ever comes near.
func test_no_opening_across_the_walkway_is_wider_than_a_body() -> void:
	if _marble == null or _bars == null:
		fail("no collider to sample")
		return
	var space: PhysicsDirectSpaceState3D = _bars.get_world_3d().direct_space_state
	var exclude: Array[RID] = _rids_outside_the_bars()
	assert_gt(float(exclude.size()), 0.0, "the rest of the map is excluded by RID")

	var gate: Transform3D = _bars.global_transform
	var samples: int = int((WALKWAY_OUTER_RADIUS - WALKWAY_INNER_RADIUS) / RADIUS_STEP_METRES) + 1
	var widest: float = 0.0
	var widest_height: float = 0.0
	var widest_radius: float = 0.0
	var rays: int = 0
	for band: int in BAND_COUNT:
		var height: float = BAND_LOW_METRES + float(band) * BAND_STEP_METRES
		var run: int = 0
		for step: int in samples:
			var x: float = WALKWAY_INNER_RADIUS + float(step) * RADIUS_STEP_METRES - GATE_CENTRE_RADIUS
			var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
				gate * Vector3(x, height, -RAY_HALF_LENGTH_METRES),
				gate * Vector3(x, height, RAY_HALF_LENGTH_METRES),
				STATIC_COLLIDER_MASK,
			)
			query.exclude = exclude
			rays += 1
			run = run + 1 if space.intersect_ray(query).is_empty() else 0
			var opening: float = float(run) * RADIUS_STEP_METRES
			if opening > widest:
				widest = opening
				widest_height = height
				widest_radius = (
					WALKWAY_INNER_RADIUS
					+ (float(step) - float(run - 1) * 0.5) * RADIUS_STEP_METRES
				)
	assert_eq_int(rays, BAND_COUNT * samples, "the sweep fired one ray per cell of the grid")

	assert_lt(
		widest, WIDEST_ALLOWED_OPENING_METRES,
		"the widest hole across the walkway is %.3f m (r %.2f, %.2f m over the deck), in %d rays" % [
			widest, widest_radius, widest_height, rays,
		],
	)
	print("      %d rays, widest opening %.3f m at r %.2f, %.2f m over the deck" % [
		rays, widest, widest_radius, widest_height,
	])


# --- Over the top -------------------------------------------------------------

## The gate is taller than the top of a jump plus the body doing the jumping.
##
## A jump leaves the deck at 7.0 m/s against 22.0 m/s^2, so the feet reach
## v^2 / 2g = 1.1136 m and the crown 1.8 m above that. The collider's top is
## measured off the shape's own faces rather than trusted from the scene, and
## has to stand clear of that crown by a margin.
func test_the_gate_is_taller_than_a_jump() -> void:
	if _marble == null or _bars == null:
		fail("no collider to measure")
		return
	var apex: float = JUMP_VELOCITY * JUMP_VELOCITY / (2.0 * GRAVITY)
	assert_almost_eq(
		apex, JUMP_APEX_METRES, APEX_TOLERANCE_METRES,
		"a %.1f m/s jump under %.1f m/s^2 tops out at v*v/(2g)" % [JUMP_VELOCITY, GRAVITY],
	)

	var bounds: AABB = _bars_collider_world_bounds()
	assert_gt(bounds.size.y, 0.0, "the bars ship a collider with faces in it")
	if bounds.size.y <= 0.0:
		return
	var top: float = bounds.position.y + bounds.size.y
	var crown: float = DECK_Y + apex + BODY_HEIGHT
	var margin: float = top - crown
	assert_gt(
		margin, MIN_HEAD_CLEARANCE_METRES,
		"the collider's top (y %.3f) clears the crown of a jumping body (%.3f = deck %.1f + apex %.4f + body %.1f)" % [
			top, crown, DECK_Y, apex, BODY_HEIGHT,
		],
	)

	# The same collider is what the other two tests lean on, so say out loud that
	# it spans the walkway wall to lip rather than leaving that to the sweep.
	var radii: Vector2 = _bars_collider_radius_span()
	assert_le(radii.x, WALKWAY_INNER_RADIUS + RADIUS_STEP_METRES, "and it reaches the open inner lip")
	assert_ge(radii.y, WALKWAY_OUTER_RADIUS - RADIUS_STEP_METRES, "and the wall of cells")
	print("      collider top y %.3f, jump crown %.3f, margin %.3f m, radii %.4f..%.4f" % [
		top, crown, margin, radii.x, radii.y,
	])


# --- The body that walks itself -----------------------------------------------

## A capsule that drives itself down the lane.
##
## It exists so the engine resolves the collision: the test sets it going and
## reads back where it got to, and every contact in between is
## [method CharacterBody3D.move_and_slide]'s. It steers off its OWN position
## every tick -- the tangent of decreasing bearing -- so it runs the lane rather
## than a straight line chosen in advance, and it presses into whatever stops it
## for as long as it is driven.
class LaneRunner extends CharacterBody3D:
	var speed: float = 0.0
	var gravity: float = 0.0
	var deck_y: float = 0.0
	var fall_limit: float = 0.0
	var gate_inverse: Transform3D = Transform3D.IDENTITY

	## Nearest the gate plane this body has been, in the gate's local frame,
	## measured only while it is being driven and only while it has floor under
	## the walkway to be driven on.
	var closest_local_z: float = INF
	var driven_ticks: int = 0
	var left_the_deck: bool = false

	var _driving: bool = false

	func begin_drive() -> void:
		closest_local_z = INF
		_driving = true

	func _physics_process(delta: float) -> void:
		var here: Vector3 = global_position
		if _driving and here.y < deck_y - fall_limit:
			# Over the open inner lip: a 24 m fall onto the spikes, not a way
			# past the gate. Stop driving rather than free-fall under the bars
			# and call that a crossing.
			left_the_deck = true
			_driving = false
		if _driving:
			var bearing: float = atan2(here.z, here.x)
			# Toward the portal is toward DECREASING bearing, which is the
			# reverse of the tangent (-sin, 0, cos).
			velocity.x = sin(bearing) * speed
			velocity.z = -cos(bearing) * speed
		else:
			velocity.x = 0.0
			velocity.z = 0.0
		velocity.y -= gravity * delta
		move_and_slide()
		if not _driving:
			return
		driven_ticks += 1
		closest_local_z = minf(closest_local_z, (gate_inverse * global_position).z)


# --- Helpers ------------------------------------------------------------------

## A body carrying the shipped capsule, on no layer and masked to the map.
func _make_runner(gate_inverse: Transform3D) -> LaneRunner:
	var runner: LaneRunner = LaneRunner.new()
	runner.name = "LaneRunner"
	runner.collision_layer = BODY_LAYER
	runner.collision_mask = STATIC_COLLIDER_MASK
	runner.speed = GROUND_SPEED
	runner.gravity = GRAVITY
	runner.deck_y = DECK_Y
	runner.fall_limit = FELL_OFF_THE_DECK_METRES
	runner.gate_inverse = gate_inverse
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.radius = BODY_RADIUS
	capsule.height = BODY_HEIGHT
	var holder: CollisionShape3D = CollisionShape3D.new()
	holder.name = "Collision"
	holder.shape = capsule
	# Authored standing, feet at the body's origin, exactly as player.tscn.
	holder.position = Vector3(0.0, BODY_HEIGHT * 0.5, 0.0)
	runner.add_child(holder)
	return runner


## The bearing a run at [param radius] starts from: the gate's own, plus the arc
## that puts the body [constant RUN_START_ARC_METRES] up the lane on the start
## side.
func _start_bearing_deg(radius: float) -> float:
	return GATE_BEARING_DEG + rad_to_deg(RUN_START_ARC_METRES / radius)


## A point standing on the deck at [param radius] and [param bearing_deg].
func _on_the_deck(radius: float, bearing_deg: float) -> Vector3:
	var bearing: float = deg_to_rad(bearing_deg)
	return Vector3(
		cos(bearing) * radius,
		DECK_Y + STAND_CLEARANCE_METRES,
		sin(bearing) * radius,
	)


## Every node under [param root], [param root] itself included.
func _descendants(root: Node) -> Array[Node]:
	var out: Array[Node] = [root]
	var index: int = 0
	while index < out.size():
		for child: Node in out[index].get_children():
			out.append(child)
		index += 1
	return out


## True for the barrier's own parts -- its imported body, its shape, its mesh.
func _is_inside_the_barrier(node: Node) -> bool:
	var walker: Node = node
	while walker != null and walker != _marble:
		if walker == _bars:
			return true
		walker = walker.get_parent()
	return false


## The RID of every collision body in the scene that is NOT part of the Bars, so
## a ray through the gate can only be answered by the gate.
func _rids_outside_the_bars() -> Array[RID]:
	var out: Array[RID] = []
	for node: Node in _descendants(_marble):
		var body: CollisionObject3D = node as CollisionObject3D
		if body == null or _is_inside_the_barrier(body):
			continue
		out.append(body.get_rid())
	return out


## Every collision shape under the Bars, so the collider is measured from what
## the physics server actually has rather than from the scene's description.
func _bars_shapes() -> Array[CollisionShape3D]:
	var out: Array[CollisionShape3D] = []
	for node: Node in _descendants(_bars):
		var holder: CollisionShape3D = node as CollisionShape3D
		if holder != null and holder.shape != null:
			out.append(holder)
	return out


## Every corner of a box shape, in the shape's own local space.
func _box_corners(box: BoxShape3D) -> Array[Vector3]:
	var half: Vector3 = box.size * 0.5
	var out: Array[Vector3] = []
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				out.append(Vector3(sx * half.x, sy * half.y, sz * half.z))
	return out


## The world-space box the bars' own faces fill.
func _bars_collider_world_bounds() -> AABB:
	var bounds: AABB = AABB()
	var started: bool = false
	for holder: CollisionShape3D in _bars_shapes():
		var box: BoxShape3D = holder.shape as BoxShape3D
		if box == null:
			continue
		var to_world: Transform3D = holder.global_transform
		for corner: Vector3 in _box_corners(box):
			var point: Vector3 = to_world * corner
			if not started:
				bounds = AABB(point, Vector3.ZERO)
				started = true
			else:
				bounds = bounds.expand(point)
	return bounds


## The nearest and furthest the bars' faces stand from the ring axis.
func _bars_collider_radius_span() -> Vector2:
	var near: float = INF
	var far: float = 0.0
	for holder: CollisionShape3D in _bars_shapes():
		var box: BoxShape3D = holder.shape as BoxShape3D
		if box == null:
			continue
		var to_world: Transform3D = holder.global_transform
		for corner: Vector3 in _box_corners(box):
			var point: Vector3 = to_world * corner
			var radius: float = Vector2(point.x, point.z).length()
			near = minf(near, radius)
			far = maxf(far, radius)
	return Vector2(near, far)
