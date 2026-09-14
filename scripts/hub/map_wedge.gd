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

## The arena this wedge sends a match to, or null while nobody has decided what
## is here. The lobby refuses to start on a wedge with none.
@export var map_scene: PackedScene = null

## The [MapCatalog] id the match runs under. Empty on an undecided wedge.
@export var map_id: StringName = &""

## What the sign says. Undecided wedges show [constant UNDECIDED_SIGN] whatever
## is typed here.
@export var title: String = ""

## The marker at the middle of the wedge. The start trigger stands on it.
@export var dais_path: NodePath = ^"Dais"

## The floating sign, billboarded so it reads from anywhere on the ring.
@export var label_path: NodePath = ^"Dais/Sign"


func _ready() -> void:
	var sign_label: Label3D = get_node_or_null(label_path) as Label3D
	if sign_label != null:
		sign_label.text = title if is_decided() else UNDECIDED_SIGN


## True when a map has been chosen for this wedge.
func is_decided() -> bool:
	return map_scene != null


## The dais marker, or null on a wedge that has none.
func get_dais() -> Marker3D:
	return get_node_or_null(dais_path) as Marker3D
