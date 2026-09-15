class_name RunnerCoverFinder
extends RefCounted

## The shared raycast budget every prisoner's sight test spends from, per physics frame.
## Cover itself is baked; see [method RingBake.nearest_cover_ahead].

## Raycasts every runner's perception may spend per physics frame, shared.
const RAYS_PER_FRAME: int = 80
static var _ray_frame: int = -1
static var _rays_spent: int = 0


static func _rays_left() -> bool:
	return Engine.get_physics_frames() != _ray_frame or _rays_spent < RAYS_PER_FRAME


## Take one of this frame's shared rays, or false when the frame's budget is gone.
static func take_ray() -> bool:
	if not _rays_left():
		return false
	var frame: int = Engine.get_physics_frames()
	if frame != _ray_frame:
		_ray_frame = frame
		_rays_spent = 0
	_rays_spent += 1
	return true
