class_name BotOpticDriver
extends Node

## Runs a [WeaponOptic]'s transition on the PHYSICS tick instead of the render
## tick, for the duration of a headless bot match.
##
## [b]Why the harness needs this at all[/b]
##
## [method WeaponOptic._process] is the right place for the zoom in a played
## game: the FOV is a rendered quantity and a 60 Hz ramp is visibly stepped on a
## 144 Hz display. Headless, that same choice makes the optic a function of how
## fast the host machine happens to loop, and the optic is not cosmetic to a
## bot -- [method TowerShooter._is_within_view] reads the live camera FOV every
## tick, so a zoom that advances at a different rate is a shooter with a
## different field of view, which is a different game.
##
## So the harness switches [method Node.set_process] off on the optic and calls
## its public [method WeaponOptic.tick] with the physics delta instead, which is
## exactly what that method documents itself as being for. The zoom then takes
## the same number of SIMULATED seconds on every machine and at every time
## compression, and two runs of the same seed produce the same shots.
##
## [member Node.process_priority] is raised by the installer so this runs after
## the [TowerShooter] that decides the zoom, and the optic therefore reaches the
## next tick's perception already carrying this tick's decision.

## The optic to advance. Set before this node enters the tree.
@export var optic: WeaponOptic


func _physics_process(delta: float) -> void:
	if optic != null:
		optic.tick(delta)
