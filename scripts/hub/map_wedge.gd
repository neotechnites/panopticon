class_name MapWedge
extends Node3D

## One 36 degree slice of the hub ring: the map that stands there, its dais, and
## the sign over it.
##
## Nine of the ten wedges are undecided, and the whole of "undecided" is a null
## [member map_scene]. Nothing here keeps a second flag for it, so a wedge
## becomes real by being given a scene and an id and by nothing else.

## What stands on the sign of an undecided wedge.
const UNDECIDED_SIGN: String = "?"

## Metres from the sign inside which it starts fading, so a sign you are
## standing under never fills the view.
const FADE_METRES: float = 6.0

## What the sign is held down to when you are on top of it.
const FADE_FLOOR: float = 0.12

## The arena this wedge sends a match to, or null while nobody has decided what
## is here. The lobby refuses to start on a wedge with none.
@export var map_scene: PackedScene = null

## The [MapCatalog] id the match runs under. Empty on an undecided wedge.
@export var map_id: StringName = &""

## Translation key of what the sign says. Undecided wedges show
## [constant UNDECIDED_SIGN] whatever is typed here.
@export var title: String = ""

## The marker at the middle of the wedge. The start trigger stands on it.
@export var dais_path: NodePath = ^"Dais"

## The floating sign, billboarded so it reads from anywhere on the ring.
@export var label_path: NodePath = ^"Dais/Sign"


var _sign: Label3D = null
var _sign_alpha: float = 1.0


func _ready() -> void:
	_sign = get_node_or_null(label_path) as Label3D
	if _sign == null:
		set_process(false)
		return
	_sign.text = tr(title) if is_decided() else UNDECIDED_SIGN
	_sign_alpha = _sign.modulate.a


func _process(_delta: float) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera == null:
		return
	fade_sign_from(camera.global_position)


## Hold the sign's alpha to [method sign_alpha_at] the viewer's distance.
func fade_sign_from(viewer: Vector3) -> void:
	if _sign != null:
		_sign.modulate.a = _sign_alpha * sign_alpha_at(viewer.distance_to(_sign.global_position))


## How opaque the sign is [param distance] metres away: full out on the ring,
## down to [constant FADE_FLOOR] on the dais under it.
func sign_alpha_at(distance: float) -> float:
	return lerpf(FADE_FLOOR, 1.0, clampf(distance / FADE_METRES, 0.0, 1.0))


## True when a map has been chosen for this wedge.
func is_decided() -> bool:
	return map_scene != null


## The dais marker, or null on a wedge that has none.
func get_dais() -> Marker3D:
	return get_node_or_null(dais_path) as Marker3D
