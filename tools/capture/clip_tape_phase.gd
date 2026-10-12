extends Node

## One of the tape's three points in a physics tick (clip_tape.gd): PRE, MID or LATE.

var deck: RefCounted = null
var phase: int = 0


func _physics_process(_delta: float) -> void:
	if deck != null:
		deck.on_phase(phase)
