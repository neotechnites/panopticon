@tool
extends Node3D

## Pick which tower model is live; the other is hidden and stops colliding.

@export_enum("carved", "arches") var variant: int = 1:
	set(value):
		variant = value
		_apply()

func _ready() -> void:
	_apply()

func _apply() -> void:
	var rocks: Array[Node] = [get_node_or_null("Rock"), get_node_or_null("RockArches")]
	for i: int in rocks.size():
		var rock: Node3D = rocks[i] as Node3D
		if rock == null:
			continue
		var live: bool = i == variant
		rock.visible = live
		for body: Node in rock.find_children("*", "StaticBody3D", true, false):
			(body as StaticBody3D).collision_layer = 1 if live else 0
