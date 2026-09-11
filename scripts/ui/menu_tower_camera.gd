class_name MenuTowerCamera
extends Camera3D

## Orbits the title screen's tower slowly, framed off-centre.
##
## Aims at a point offset along its OWN current right vector rather than at the
## tower itself, so the tower holds the same screen x all the way round the
## orbit instead of swinging through centre-frame twice a lap.

## The tower's origin node. Orbit centre and look anchor are both read from its
## world position, so raising or moving the tower moves the shot with it.
@export var tower_path: NodePath = ^"../Tower"

## Horizontal distance from the tower axis, in metres.
@export_range(1.0, 200.0, 0.1) var orbit_radius_metres: float = 95.0

## Camera height above the tower's local origin, in metres. About the drum's
## mid-height, per the mock-up.
@export_range(-20.0, 60.0, 0.1) var orbit_height_metres: float = 0.0

## Height of the look-anchor above the tower's local origin, in metres. Above
## [member orbit_height_metres] so the camera pitches slightly upward.
@export_range(-20.0, 60.0, 0.1) var look_height_metres: float = 2.0

## How far the look-anchor is pushed off the tower axis, in metres, so the
## tower lands right of centre instead of dead centre.
@export_range(0.0, 60.0, 0.1) var lateral_offset_metres: float = 27.0

## Orbit speed. Slow on purpose -- this is a held shot, not a flythrough.
@export_range(0.0, 45.0, 0.1) var degrees_per_second: float = 7.0

@export var start_angle_degrees: float = 0.0

var _angle_degrees: float
var _tower: Node3D


func _ready() -> void:
	_tower = get_node_or_null(tower_path) as Node3D
	_angle_degrees = start_angle_degrees
	current = true
	_apply()


func _process(delta: float) -> void:
	_angle_degrees = fmod(_angle_degrees + degrees_per_second * delta, 360.0)
	_apply()


func _apply() -> void:
	var centre: Vector3 = _tower.global_position if _tower != null else Vector3.ZERO
	var rad: float = deg_to_rad(_angle_degrees)
	global_position = centre + Vector3(sin(rad) * orbit_radius_metres, orbit_height_metres, cos(rad) * orbit_radius_metres)

	var to_centre: Vector3 = (centre - global_position).normalized()
	var right: Vector3 = to_centre.cross(Vector3.UP).normalized()
	var anchor: Vector3 = centre + Vector3(0.0, look_height_metres, 0.0) - right * lateral_offset_metres
	look_at(anchor, Vector3.UP)
