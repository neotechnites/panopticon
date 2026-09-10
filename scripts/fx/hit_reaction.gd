class_name FxHitReaction
extends Control

## What being shot looks like from the inside: one held white frame and a hard
## camera whip, both finished inside a third of a second.
##
## [b]The brief, and why there is no animation in this file[/b]
##
## Being shot should feel like being hit in the side of the head with a baseball
## from a pro pitcher. A baseball does not have a wind-up from the receiving end.
## It is one discontinuity and then the world is different, and the entire design
## of this component follows from that: everything is at full amplitude on the
## frame the shot resolves and monotonically smaller afterwards. There is no
## ease-in anywhere, no ragdoll, no death camera, and nothing that has to finish
## before the player gets control back -- the reaction is decoration on top of a
## conversion that has already happened.
##
## It is also the most frequent event in the game, which is the argument for
## brevity rather than against it. An effect seen once a match may be indulgent;
## one seen every few seconds sets the register, and a half-second of held screen
## becomes minutes of a match spent watching.
##
## [b]Two channels, because one is not enough and three is too many[/b]
##
## The flash says SOMETHING HAPPENED, instantly and unmissably, and is the only
## part that survives being looked away from. The camera whip says something
## happened TO YOU, FROM OVER THERE -- it carries the direction, which the flash
## cannot, and it carries roll, which is the one rotation a first-person camera
## never gets from aiming and therefore the one that cannot be mistaken for the
## player's own movement.
##
## [b]How the victim is identified[/b]
##
## [signal Rifle.target_hit] carries the collider that was struck. This component
## walks up from it looking for its own [member body], the same walk
## [method MatchController.resolve_participant] does, so a hitbox on a child node
## resolves without a change here. There is no dependency on the match: a body
## with this attached reacts correctly in a bare test scene.
##
## Note that this fires on every hit LANDED, not on every conversion. With
## [member MatchRules.prisoner_lives] above one that is the difference between a
## hit reaction and a death reaction, and a hit reaction is the one that is
## wanted.
##
## Attach as a [Control] under a [CanvasLayer] with full-rect anchors, on the
## body that might be shot.

## Emitted the instant a hit on this body is recognised, carrying the direction
## the shot was travelling in world space. The hook for audio and for anything
## else that wants the event without re-deriving it.
signal struck(world_direction: Vector3)

## The weapon to listen to. A node reference rather than a path resolved once, so
## it survives [MatchController] reparenting the rifle onto a new seat holder.
## In a match there is exactly one rifle and everybody listens to it.
@export var rifle: Rifle

## This component's own body -- the [CharacterBody3D] that can be shot. A hit is
## mine when the struck collider is this node or anything under it.
@export var body: CollisionObject3D

## Tunables.
@export var profile: FeedbackProfile

## Optional. When set, the whip is played through it. Without one the flash still
## fires, which is the correct degradation: the loud half survives.
@export var camera_kick: FxCameraKick

## Go inert when there is no display server.
@export var headless_inert: bool = true

const HEADLESS_DISPLAY: String = "headless"

var _age: float = -1.0
var _inert: bool = false


func _ready() -> void:
	if headless_inert and DisplayServer.get_name() == HEADLESS_DISPLAY:
		_inert = true
		set_process(false)
		hide()
		return
	if profile == null:
		push_error("FxHitReaction has no FeedbackProfile; hits will not be shown.")
		_inert = true
		set_process(false)
		return
	if rifle == null:
		push_error("FxHitReaction has no Rifle to listen to.")
		_inert = true
		set_process(false)
		return
	if body == null:
		push_error("FxHitReaction has no body; it cannot tell its own hits from anyone else's.")
		_inert = true
		set_process(false)
		return
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	rifle.target_hit.connect(_on_target_hit)


func _process(delta: float) -> void:
	tick(delta)


## Advance the flash by [param delta] seconds. Public so a harness may step it.
func tick(delta: float) -> void:
	if _age < 0.0:
		return
	_age += delta
	if _age >= profile.flash_seconds:
		_age = -1.0
	queue_redraw()


# --- Public API ---------------------------------------------------------------

## Play the reaction directly, bypassing the weapon. [param world_direction] is
## the direction the shot was travelling; pass [constant Vector3.ZERO] when it is
## unknown and a default whip is used.
##
## For a test, and for a future networked client that is told it was hit rather
## than watching the raycast that did it.
func react(world_direction: Vector3) -> void:
	if _inert or profile == null or not profile.enabled or not profile.hit_reaction_enabled:
		return
	# Restart rather than blend. A second hit inside a tenth of a second is a
	# second discontinuity, and averaging two of those produces neither.
	_age = 0.0
	if camera_kick != null:
		camera_kick.strike(world_direction)
	struck.emit(world_direction)
	queue_redraw()


## Alpha of the full-screen flash right now: full through the hold and falling
## afterwards, 0.0 when spent. Exposed so a headless check can assert the
## reaction ran and finished without a viewport to look at.
func get_flash_alpha() -> float:
	if _age < 0.0 or profile == null:
		return 0.0
	if _age <= profile.flash_hold_seconds:
		return profile.flash_color.a
	var falling: float = profile.flash_seconds - profile.flash_hold_seconds
	if falling <= 0.0:
		return 0.0
	var fallen: float = (_age - profile.flash_hold_seconds) / falling
	if fallen >= 1.0:
		return 0.0
	return profile.flash_color.a * pow(1.0 - fallen, profile.flash_fade_exponent)


## True while the reaction is playing.
func is_reacting() -> bool:
	return _age >= 0.0


## Seconds since the hit landed, or -1.0 when nothing is playing.
func get_age() -> float:
	return _age


func is_inert() -> bool:
	return _inert


# --- Drawing ------------------------------------------------------------------

## One rectangle. There is no cheaper way to interrupt a player's vision and no
## reason to want a more expensive one -- a vignette, a crack overlay or a blood
## texture would all need art, and all of them read as slower than a flat frame.
func _draw() -> void:
	var alpha: float = get_flash_alpha()
	if alpha <= 0.0:
		return
	var colour: Color = profile.flash_color
	colour.a = alpha
	draw_rect(Rect2(Vector2.ZERO, size), colour)


# --- Signals ------------------------------------------------------------------

func _on_target_hit(collider: Node3D, _hit_position: Vector3, hit_normal: Vector3) -> void:
	if not _is_me(collider):
		return
	# The surface normal at the impact points back towards the shooter, so the
	# bullet was travelling the other way. Deriving the direction from the normal
	# rather than from the shooter's position means this works for a hit reported
	# by a network peer, where there is no shooter node to ask.
	react(-hit_normal)


## Walk up from the struck collider looking for this component's own body. Mirrors
## [method MatchController.resolve_participant], so a body whose hitbox sits on a
## child node, or which has been reparented under a squad node, resolves without
## a change here.
func _is_me(collider: Node3D) -> bool:
	var node: Node = collider
	while node != null:
		if node == body:
			return true
		node = node.get_parent()
	return false
