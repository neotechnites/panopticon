class_name WeaponProjectile
extends Node3D

## One round in flight, for [constant WeaponProfile.ShotModel.PROJECTILE].
##
## [b]What this changes about the game[/b]
##
## Under hitscan the trigger and the outcome are the same event: the tower reads
## a position and the shot is already there. A runner's only defence is to not
## be seen. Give the shot travel time and the tower has to read an INTENTION
## instead -- where the runner will be in the second the round is in the air --
## and a runner who breaks stride after the muzzle flash can survive a shot that
## was perfectly aimed when it left the barrel. Across a 120 m ring at the
## default 120 m/s that is eight metres of lead on a walking target, which is
## more than a runner's own width, so leading is not a refinement of aiming; it
## is a different skill with a different counter-play.
##
## [b]Why the rifle steps this and not [code]_physics_process[/code][/b]
##
## [Rifle] advances every round it has in the air from [method Rifle.tick], on
## the same clock as the reload. That is deliberate: [method Rifle.tick] is the
## weapon's documented harness seam, and a test or a sweep that drives the
## cycle with explicit deltas has to be able to drive the flight with them too.
## A round running its own [code]_physics_process[/code] would keep flying while
## a harness held the weapon still, and a replay would stop being a replay.
##
## The node is [member Node3D.top_level] for the same reason [Tracer] is: a
## round in the air is a fact about the world, not about where the shooter has
## since turned.
##
## [b]Sweeping, not tunnelling[/b]
##
## Each step raycasts the segment just crossed rather than testing the round's
## new position, so a round cannot pass through cover however fast it is going.
## [member WeaponProfile.projectile_step_metres] caps how long one of those
## segments may be, which keeps the impact normal honest on thin geometry.
##
## [b]Cosmetic rounds[/b]
##
## A peer that is not the authority still has to SHOW the round, and the host
## has already told it where the shot ended. Such a round is configured
## [code]cosmetic[/code]: no collision mask, no areas, no gravity. It is a
## straight line to a point somebody else resolved, and bending it a second
## time would walk the picture off that line -- the streak would arrive
## somewhere the hit was not. It still flies through the same [method advance]
## as a live round, so the two cannot drift apart by having two flight paths.

## Where the streak this round leaves should start: the muzzle as it stood on
## the tick the trigger broke, not wherever the barrel has swung since. [Rifle]
## assigns it after [method launch] because the weapon is the only thing that
## knows which of its own muzzle positions fired this round -- a streak drawn
## from the current muzzle would rubber-band with the shooter's aim.
var muzzle_origin: Vector3 = Vector3.ZERO

## Metres per second, direction included. Gravity bends it in flight.
var _velocity: Vector3 = Vector3.ZERO

## Downward acceleration, m/s^2. 0.0 is a perfectly flat shot.
var _gravity: float = 0.0

## Metres of range left before the round is spent and reports a miss.
var _range_left: float = 0.0

## Longest segment, in metres, one collision step may cover.
var _step_metres: float = 2.0

## Seconds in the air, against [member _max_flight] -- a backstop, not a rule.
var _flight: float = 0.0
var _max_flight: float = 10.0

var _mask: int = 0xFFFFF
var _hit_areas: bool = false
var _exclude: Array[RID] = []

## The raycast result that ended the flight. Empty means the round was spent
## without striking anything.
var _hit: Dictionary = {}

var _resolved: bool = false
var _end_point: Vector3 = Vector3.ZERO

## True when this round is only a picture of a shot the authority already
## resolved. It collides with nothing, so it cannot invent a hit of its own.
var _cosmetic: bool = false

## Triangles in one bullet: an eight-face head plus the two crossed tail quads.
const VISUAL_TRIANGLES: int = 12

## The head's white-hot core; the tail is the profile's tracer colour, fading out.
const HEAD_COLOR: Color = Color(1.0, 0.97, 0.85, 1.0)

## Head proportions in tracer widths: the spike ahead of the core and the stub behind it.
const HEAD_TIP_WIDTHS: float = 3.0
const HEAD_BACK_WIDTHS: float = 1.0

## How much of the tail's width survives at its far end.
const TAIL_TAPER: float = 0.25

## One material and one mesh per look, shared by every round in the air.
static var _visual_material: StandardMaterial3D = null
static var _visual_meshes: Dictionary = {}

## The bullet drawn at this round's position, or null for a round nobody sees.
var _visual: MeshInstance3D = null


## Put a round in the air along [param direction] from [param origin] and hand
## it back. [param travel_range] is the distance it may cover before it is
## spent, and [param speed] its muzzle velocity -- both already adjusted for
## charge by the caller, because a round in flight has no opinion about how hard
## its trigger was squeezed.
##
## [param exclude] is the shooter's own collider, for exactly the reason
## [member Rifle.shooter_body] exists: a round launched inside its owner's
## capsule would otherwise strike it on the first step.
##
## [param cosmetic] makes the round visual-only -- see [i]Cosmetic rounds[/i]
## above. A cosmetic round never reports a hit, so a peer showing one cannot
## disagree with the host about what the shot did.
static func launch(
	parent: Node,
	origin: Vector3,
	direction: Vector3,
	speed: float,
	travel_range: float,
	profile: WeaponProfile,
	exclude: Array[RID],
	cosmetic: bool = false,
) -> WeaponProjectile:
	var round_shot: WeaponProjectile = WeaponProjectile.new()
	round_shot.configure(origin, direction, speed, travel_range, profile, exclude, cosmetic)
	parent.add_child(round_shot)
	return round_shot


## Set the round up before it enters the tree, so its first step already runs
## from the muzzle rather than from wherever its parent happens to be.
func configure(
	origin: Vector3,
	direction: Vector3,
	speed: float,
	travel_range: float,
	profile: WeaponProfile,
	exclude: Array[RID],
	cosmetic: bool = false,
) -> void:
	top_level = true
	_cosmetic = cosmetic
	_velocity = direction.normalized() * maxf(speed, 0.001)
	_gravity = maxf(profile.projectile_gravity, 0.0)
	_range_left = maxf(travel_range, 0.0)
	_step_metres = maxf(profile.projectile_step_metres, 0.05)
	_max_flight = maxf(profile.projectile_max_flight_seconds, 0.05)
	_mask = profile.hit_mask
	_hit_areas = profile.hit_areas
	_exclude = exclude
	_end_point = origin
	global_transform = Transform3D(Basis.IDENTITY, origin)

	if _cosmetic:
		# Stripped here rather than branched on in flight: the round is aimed at
		# an end point the authority has already resolved, so a mask that could
		# stop it short and a gravity that could bend it off that line are not
		# softened, they are removed.
		_mask = 0
		_hit_areas = false
		_gravity = 0.0

	if profile.draws_projectile_streak():
		_build_visual(direction, profile)


## Fly for [param delta] seconds. Returns true on the step the round resolves --
## by striking something, by running out of range, or by timing out -- after
## which the caller should read the result and free it.
##
## Never resolves twice: a caller that keeps stepping a spent round gets true
## once and false forever after, so a missed frame cannot double-report a hit.
func advance(delta: float) -> bool:
	if _resolved or delta <= 0.0:
		return false

	_flight += delta
	var remaining: float = delta
	while remaining > 0.0:
		var speed: float = _velocity.length()
		# The step is capped in METRES rather than in seconds so that the
		# segment length is the same for a slow round and a fast one, which is
		# what actually decides whether a normal is read off the right face.
		var step: float = remaining
		if speed > 0.0:
			step = minf(remaining, _step_metres / speed)

		var from: Vector3 = global_position
		if _gravity > 0.0:
			_velocity.y -= _gravity * step
		var to: Vector3 = from + _velocity * step
		var travelled: float = from.distance_to(to)

		if travelled >= _range_left:
			# Spent mid-step: stop exactly at the end of the range rather than
			# at the end of the step, or a fast round would out-range itself by
			# most of a step and a range sweep would measure the wrong number.
			var overshoot: float = travelled - _range_left
			if travelled > 0.0:
				to = to.lerp(from, overshoot / travelled)
			_range_left = 0.0
			_sweep(from, to)
			if _hit.is_empty():
				_resolve(to, {})
			return true

		_range_left -= travelled
		_sweep(from, to)
		if _resolved:
			return true

		global_position = to
		_end_point = to
		if _gravity > 0.0 and _visual != null:
			_visual.basis = WeaponProjectile.heading_basis(_velocity)
		remaining -= step

		if _flight >= _max_flight:
			_resolve(to, {})
			return true

	return false


## True once the round has stopped flying, whether it hit or not.
func is_resolved() -> bool:
	return _resolved


## True when this round is a visual-only copy of somebody else's shot. What a
## caller checks before it credits a round with anything: a cosmetic round is
## allowed to be seen and nothing else.
func is_cosmetic() -> bool:
	return _cosmetic


## True when the round resolved by striking something.
func has_hit() -> bool:
	return not _hit.is_empty()


## Where the round ended: the impact point on a hit, the end of its range on a
## miss. The value [signal Rifle.target_hit] and [signal Rifle.missed] carry.
func get_end_point() -> Vector3:
	return _end_point


## What the round struck, or null on a miss.
func get_collider() -> Node3D:
	return _hit.get("collider", null) as Node3D


## Surface normal at the impact, or the reverse of the round's own heading when
## it hit nothing.
func get_normal() -> Vector3:
	if _hit.is_empty():
		return -_velocity.normalized()
	return _hit.get("normal", -_velocity.normalized()) as Vector3


## Seconds this round has been in the air. The number a sweep correlates against
## lead error to find out what [member WeaponProfile.projectile_speed] is worth.
func get_flight_seconds() -> float:
	return _flight


# --- Internals ----------------------------------------------------------------

## Raycast the segment just crossed. Resolves the round if it struck anything.
func _sweep(from: Vector3, to: Vector3) -> void:
	if _cosmetic:
		return
	if from.is_equal_approx(to):
		return
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if space == null:
		return
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = _mask
	query.collide_with_areas = _hit_areas
	query.collide_with_bodies = true
	query.exclude = _exclude
	var result: Dictionary = space.intersect_ray(query)
	if result.is_empty():
		return
	_resolve(result.get("position", to) as Vector3, result)


func _resolve(at: Vector3, result: Dictionary) -> void:
	_resolved = true
	_end_point = at
	_hit = result
	global_position = at


## The bullet: a bright head with a short tail fading behind it, one shared mesh
## and one shared material, its nose on [param direction].
func _build_visual(direction: Vector3, profile: WeaponProfile) -> void:
	_visual = MeshInstance3D.new()
	_visual.name = "Round"
	_visual.mesh = WeaponProjectile.visual_mesh_for(profile)
	_visual.material_override = WeaponProjectile.visual_material()
	_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visual.transform = Transform3D(WeaponProjectile.heading_basis(direction), Vector3.ZERO)
	add_child(_visual)


## A basis whose -Z is [param direction], for a mesh built nose-forward.
static func heading_basis(direction: Vector3) -> Basis:
	var forward: Vector3 = direction.normalized()
	var up: Vector3 = Vector3.UP if absf(forward.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	return Basis.looking_at(forward, up)


## The bullet mesh for [param profile]'s tail length, width and colour, built once per look.
static func visual_mesh_for(profile: WeaponProfile) -> Mesh:
	var tint: Color = profile.tracer_color
	tint.a = profile.get_tracer_alpha()
	var key: String = "%.3f|%.3f|%08x" % [profile.projectile_visual_length, profile.tracer_width, tint.to_rgba32()]
	var cached: Mesh = _visual_meshes.get(key, null) as Mesh
	if cached == null:
		cached = _build_bullet_mesh(profile.projectile_visual_length, profile.tracer_width, tint)
		_visual_meshes[key] = cached
	return cached


## The one bullet material: the tracer's unshaded alpha blend, coloured by the vertices.
static func visual_material() -> StandardMaterial3D:
	if _visual_material == null:
		_visual_material = Tracer.build_material(Color.WHITE)
		_visual_material.vertex_color_use_as_albedo = true
	return _visual_material


## Nose at -Z: an eight-face head, then two crossed
## quads tapering and fading to nothing [param length] metres behind it.
static func _build_bullet_mesh(length: float, width: float, tint: Color) -> ArrayMesh:
	var half: float = width * 0.5
	var tip: Vector3 = Vector3(0.0, 0.0, -width * HEAD_TIP_WIDTHS)
	var back: Vector3 = Vector3(0.0, 0.0, width * HEAD_BACK_WIDTHS)
	var ring: Array[Vector3] = [
		Vector3(half, 0.0, 0.0), Vector3(0.0, half, 0.0), Vector3(-half, 0.0, 0.0), Vector3(0.0, -half, 0.0),
	]
	var tool: SurfaceTool = SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index: int in ring.size():
		var a: Vector3 = ring[index]
		var b: Vector3 = ring[(index + 1) % ring.size()]
		_add_triangle(tool, HEAD_COLOR, tip, a, b)
		_add_triangle(tool, HEAD_COLOR, back, b, a)
	var faded: Color = tint
	faded.a = 0.0
	var far: Vector3 = Vector3(0.0, 0.0, maxf(length, width))
	_add_tail_quad(tool, Vector3(half, 0.0, 0.0), back, far, tint, faded)
	_add_tail_quad(tool, Vector3(0.0, half, 0.0), back, far, tint, faded)
	return tool.commit()


static func _add_triangle(tool: SurfaceTool, color: Color, a: Vector3, b: Vector3, c: Vector3) -> void:
	tool.set_color(color)
	tool.add_vertex(a)
	tool.set_color(color)
	tool.add_vertex(b)
	tool.set_color(color)
	tool.add_vertex(c)


## One tail quad from [param near] to [param far], [param half_width] wide at the head
## and [constant TAIL_TAPER] of that at the end.
static func _add_tail_quad(
	tool: SurfaceTool, half_width: Vector3, near: Vector3, far: Vector3, near_color: Color, far_color: Color
) -> void:
	var far_half: Vector3 = half_width * TAIL_TAPER
	var near_a: Vector3 = near - half_width
	var near_b: Vector3 = near + half_width
	var far_a: Vector3 = far - far_half
	var far_b: Vector3 = far + far_half
	tool.set_color(near_color)
	tool.add_vertex(near_a)
	tool.set_color(near_color)
	tool.add_vertex(near_b)
	tool.set_color(far_color)
	tool.add_vertex(far_b)
	tool.set_color(near_color)
	tool.add_vertex(near_a)
	tool.set_color(far_color)
	tool.add_vertex(far_b)
	tool.set_color(far_color)
	tool.add_vertex(far_a)
