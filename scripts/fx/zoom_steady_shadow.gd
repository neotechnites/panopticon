class_name ZoomSteadyShadow
extends DirectionalLight3D
## A sun whose shadow map keeps its unzoomed texel size while the camera zooms: the engine fits
## the map to the view frustum, so a narrower fov re-fits it and the dapple swims and sharpens.

## The authored max distance, which holds at the camera's widest (unzoomed) fov.
var _authored: float = 0.0
var _camera_id: int = 0
var _base_fov: float = 0.0


func _ready() -> void:
	_authored = directional_shadow_max_distance
	process_priority = 1000  # after the optic's fov write, so the fit never lags a frame


func _process(_delta: float) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null or camera.projection != Camera3D.PROJECTION_PERSPECTIVE:
		return
	if camera.get_instance_id() != _camera_id:
		_camera_id = camera.get_instance_id()
		_base_fov = camera.fov
	_base_fov = maxf(_base_fov, camera.fov)
	var size: Vector2 = get_viewport().get_visible_rect().size
	var aspect: float = size.x / maxf(size.y, 1.0)
	var near: float = camera.near
	var far: float = minf(_authored, camera.far)
	# The engine's fit is the sphere round the frustum slice near..far; hold its radius.
	var k0: float = _spread(camera, _base_fov, aspect)
	var r2: float = 0.25 * (far - near) * (far - near) + far * far * k0
	var a: float = 0.25 + _spread(camera, camera.fov, aspect)
	var c: float = 0.25 * near * near - r2
	directional_shadow_max_distance = (0.5 * near + sqrt(0.25 * near * near - 4.0 * a * c)) / (2.0 * a)


## Squared distance of a frustum corner off its axis, per unit depth squared.
static func _spread(camera: Camera3D, fov: float, aspect: float) -> float:
	var t: float = tan(deg_to_rad(fov) * 0.5)
	if camera.keep_aspect == Camera3D.KEEP_WIDTH:
		t /= aspect
	return t * t * (1.0 + aspect * aspect)
