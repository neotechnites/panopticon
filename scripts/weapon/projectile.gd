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


## Put a round in the air along [param direction] from [param origin] and hand
## it back. [param travel_range] is the distance it may cover before it is
## spent, and [param speed] its muzzle velocity -- both already adjusted for
## charge by the caller, because a round in flight has no opinion about how hard
## its trigger was squeezed.
##
## [param exclude] is the shooter's own collider, for exactly the reason
## [member Rifle.shooter_body] exists: a round launched inside its owner's
## capsule would otherwise strike it on the first step.
static func launch(
	parent: Node,
	origin: Vector3,
	direction: Vector3,
	speed: float,
	travel_range: float,
	profile: WeaponProfile,
	exclude: Array[RID],
) -> WeaponProjectile:
	var round_shot: WeaponProjectile = WeaponProjectile.new()
	round_shot.configure(origin, direction, speed, travel_range, profile, exclude)
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
) -> void:
	top_level = true
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

	if profile.projectile_visual_radius > 0.0:
		_build_visual(profile)


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
		remaining -= step

		if _flight >= _max_flight:
			_resolve(to, {})
			return true

	return false


## True once the round has stopped flying, whether it hit or not.
func is_resolved() -> bool:
	return _resolved


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


## A small unshaded, additive dot in the tracer's colour, so the round reads as
## the same hot thing the streak is made of. Built only when
## [member WeaponProfile.projectile_visual_radius] asks for it, which it does
## not by default: a headless sweep should not be paying for a mesh nobody
## looks at.
func _build_visual(profile: WeaponProfile) -> void:
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = profile.projectile_visual_radius
	sphere.height = profile.projectile_visual_radius * 2.0
	sphere.radial_segments = 6
	sphere.rings = 3

	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.disable_receive_shadows = true
	var tint: Color = profile.tracer_color
	tint.a = profile.get_tracer_alpha()
	material.albedo_color = tint

	var visual: MeshInstance3D = MeshInstance3D.new()
	visual.name = "Round"
	visual.mesh = sphere
	visual.material_override = material
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(visual)
