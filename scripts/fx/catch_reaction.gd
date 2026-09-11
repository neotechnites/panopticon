class_name FxCatchReaction
extends Control

## THE CATCH, announced to both people it happened to.
##
## Canon, in the author's words: a shot prisoner [i]"becomes a ghost: faster
## than the living, cannot be shot, must catch up to a living player and take
## their spot"[/i], and [i]"the runners arent on a team at all even a little
## bit. when you catch someone, you take their place."[/i] It is the mechanic
## that makes a round three-sided and the answer to the hard constraint that
## nobody sits idle -- and until this node existed it produced nothing at all on
## either screen. One frame you were running, the next you were a ghost, with no
## idea what had happened or who had done it.
##
## [b]What it draws[/b]
##
## [codeblock]
## you made the catch  -> a burst of THEIR colour off the edges of the screen,
##                        retreating outward, plus the kill-confirm punch. Gone
##                        in a third of a second. You took a life back.
## you were caught     -> a frame of THEIR colour closing inward, HELD, then
##                        released over half a second, plus a light whip towards
##                        where they reached from and a hard backwards drag.
##                        You have been taken.
## a bot caught a bot  -> nothing. Not an error, not a no-op with a camera call
##                        in it; this node returns before it reads a colour.
## [/codeblock]
##
## [b]How it differs from being shot, and why that is structural[/b]
##
## [FxHitReaction] draws a WHITE FULL-SCREEN FILL and whips the camera hard,
## and the whole thing is over in about 110 ms. Every one of those is inverted
## here: a colour rather than white, a frame rather than a fill, about a second
## rather than a tenth, and a pull rather than a snap. The two can never be
## confused, and neither reaction has to know the other exists to guarantee it
## -- being shot and being caught are separate signals from separate systems
## ([signal Rifle.target_hit] and [signal MatchController.ghost_caught]) and no
## catch passes through the rifle at all.
##
## The camera itself is NOT written here. Every channel goes through the one
## [FxCameraKick] the rest of [code]scripts/fx[/code] shares, because recoil,
## being shot, confirming a kill and now the catch all want the camera and the
## last writer of a frame would otherwise win. This node borrows two of its
## existing channels and adds none.
##
## [b]Who was involved, without a word of text[/b]
##
## [RunnerPalette] deals every participant a stable colour for the whole match
## and their body wears it, so a colour IS a name on this ring. The frame is
## drawn in the OTHER player's colour: the ghost who took you, or the prisoner
## you took. Nothing is spelled out, nothing has to be read, and it is correct
## at a glance from inside a camera that is already pulling away from your body.
##
## [b]It changes nothing about the catch[/b]
##
## Strictly additive, like the rest of the rig. It subscribes to a signal
## [MatchController] already emits, is subscribed to by nothing that can affect
## the match, and deleting the node restores the silence exactly. Not one line
## of [code]match_controller.gd[/code] is touched: the swap, the radius, the
## grace and who ends up where are all read-only from here.
##
## Attach as a [Control] under a [CanvasLayer] with full-rect anchors, on the
## body the local player is looking out of.

## Which side of a catch this player was on. Exhaustive.
##
## [b]Not called [code]Side[/code].[/b] Godot 4 has a global [enum @GlobalScope.Side]
## ([code]SIDE_LEFT[/code] and its three neighbours, which every [Control] anchor
## and margin is expressed in), and this is a Control. An inner enum of that name
## shadows it, and then an annotation written [code]Side[/code] binds to the
## GLOBAL one while a value written [code]Side.NONE[/code] binds to this one --
## which the type checker rejects as "Cannot assign a value of type
## FxCatchReaction.Side as Side". One name, no collision, no ambiguity.
enum CatchSide {
	## Nothing playing. Also what a catch between two bots leaves behind.
	NONE,
	## This player's ghost took somebody's spot.
	TAKE,
	## This player was the prisoner whose spot was taken.
	CAUGHT,
}

## Emitted when this player's ghost takes a spot, carrying the caught
## prisoner's colour. The hook for audio, and for anything else that wants the
## event without re-deriving which side of it we were on.
signal catch_made(caught_color: Color)

## Emitted when this player is the one caught, carrying the colour of the ghost
## that took them.
signal catch_taken(ghost_color: Color)

## The match to listen to. Without one this node has no [signal
## MatchController.ghost_caught] to hear and no palette to read a colour from,
## so it says so and goes inert.
@export var controller: MatchController

## This component's own body -- the [CharacterBody3D] the local player is
## looking out of. A catch is mine when either participant in it is this body,
## and it is nobody's when neither is, which is what makes a bot-on-bot catch
## cost one identity comparison and stop.
@export var body: CollisionObject3D

## Tunables. Without one the node does nothing and says so rather than falling
## back on invented numbers.
@export var profile: CatchProfile

## Optional. When set, the camera half is played through it. Without one the
## frame still draws, which is the correct degradation: the legible half
## survives.
@export var camera_kick: FxCameraKick

## Go inert when there is no display server.
@export var headless_inert: bool = true

const HEADLESS_DISPLAY: String = "headless"

## Metres below which the two bodies count as being in the same place, so there
## is no direction to whip towards.
##
## Not a tunable and deliberately not on the profile: it is a guard against
## normalising a zero-length vector, not a design question. A ghost catches from
## inside [member GhostProfile.catch_radius_metres], and at the bottom of that
## range the direction is noise -- [method FxCameraKick.strike] documents
## [constant Vector3.ZERO] as "not known" and uses its own fallback whip, which
## is the honest answer.
const MIN_REACH_METRES: float = 0.05

## Seconds since the catch landed, or -1.0 when nothing is playing.
var _age: float = -1.0

var _side: CatchSide = CatchSide.NONE

## The other participant's runner colour, at full alpha. See [method get_color].
var _color: Color = Color.WHITE

var _inert: bool = false


func _ready() -> void:
	if headless_inert and DisplayServer.get_name() == HEADLESS_DISPLAY:
		_inert = true
		set_process(false)
		hide()
		return
	if profile == null:
		push_error("FxCatchReaction has no CatchProfile; catches will not be shown.")
		_inert = true
		set_process(false)
		return
	if controller == null:
		push_error("FxCatchReaction has no MatchController to listen to.")
		_inert = true
		set_process(false)
		return
	if body == null:
		push_error("FxCatchReaction has no body; it cannot tell its own catches from anyone else's.")
		_inert = true
		set_process(false)
		return
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	controller.ghost_caught.connect(_on_ghost_caught)


func _process(delta: float) -> void:
	tick(delta)


## Advance the frame by [param delta] seconds. Public so a harness may step it,
## the way [method FxHitReaction.tick] and [method FxCameraKick.tick] are.
func tick(delta: float) -> void:
	if _age < 0.0:
		return
	_age += delta
	if _age >= _duration():
		_age = -1.0
		_side = CatchSide.NONE
	queue_redraw()


# --- Public API ---------------------------------------------------------------

## Play the taker's half directly, bypassing the match. [param caught_color] is
## the colour of the prisoner whose spot was taken.
##
## For a test, and for a future networked client that is TOLD it caught somebody
## rather than watching the distance check that decided it.
func play_take(caught_color: Color) -> void:
	if _inert or profile == null or not profile.enabled or not profile.take_enabled:
		return
	_begin(CatchSide.TAKE, caught_color)
	if camera_kick != null:
		camera_kick.confirm(profile.take_punch_scale)
	catch_made.emit(_color)


## Play the victim's half directly. [param ghost_color] is the colour of the
## ghost that took the spot; [param reach_direction] is the direction that ghost
## was reaching in, in world space, or [constant Vector3.ZERO] when the two were
## standing in the same place and there is no direction to give.
func play_caught(ghost_color: Color, reach_direction: Vector3) -> void:
	if _inert or profile == null or not profile.enabled or not profile.caught_enabled:
		return
	_begin(CatchSide.CAUGHT, ghost_color)
	if camera_kick != null:
		# Two channels, composed: a light turn towards where it came from, and a
		# hard pull backwards. Neither is a new channel -- see the class doc.
		camera_kick.strike(reach_direction, profile.caught_whip_scale)
		camera_kick.confirm(profile.caught_drag_scale)
	catch_taken.emit(_color)


## Cut the reaction short. For a round reset, so a frame cannot survive into a
## round it does not describe.
func clear() -> void:
	if _age < 0.0:
		return
	_age = -1.0
	_side = CatchSide.NONE
	queue_redraw()


## Which side of a catch is being drawn right now. See [enum CatchSide].
func get_side() -> CatchSide:
	return _side


## True while anything is on screen.
func is_reacting() -> bool:
	return _age >= 0.0


## Seconds since the catch landed, or -1.0 when nothing is playing.
func get_age() -> float:
	return _age


## The other participant's colour, at FULL alpha.
##
## Taken from [method RunnerPalette.color_for_index] and not from
## [method MatchController.get_body_color], and the difference is the point.
## The live body colour is honest about what the mesh is wearing -- a ghost's is
## at [member RunnerPalette.ghost_alpha], and the seat holder's is the guard
## grey -- and both of those would make the frame say "a ghost" or "the guard"
## when the only question it is answering is WHICH PLAYER. Identity is the
## palette entry; translucency is a separate statement made on the body, where
## it belongs.
func get_color() -> Color:
	return _color


## Opacity of the frame right now, 0.0 when nothing is playing. Exposed so a
## headless check can assert the reaction ran and finished with no viewport to
## look at, exactly as [method FxHitReaction.get_flash_alpha] is.
func get_alpha() -> float:
	if _age < 0.0 or profile == null:
		return 0.0
	if _side == CatchSide.TAKE:
		var open: float = maxf(profile.take_open_seconds, 0.0)
		if open <= 0.0:
			return 0.0
		var gone: float = _age / open
		if gone >= 1.0:
			return 0.0
		return profile.take_alpha * pow(1.0 - gone, profile.take_open_exponent)
	if _side == CatchSide.CAUGHT:
		var held: float = (
			maxf(profile.caught_close_seconds, 0.0)
			+ maxf(profile.caught_hold_seconds, 0.0)
		)
		if _age <= held:
			return profile.caught_alpha
		var fade: float = maxf(profile.caught_fade_seconds, 0.0)
		if fade <= 0.0:
			return 0.0
		var fallen: float = (_age - held) / fade
		if fallen >= 1.0:
			return 0.0
		return profile.caught_alpha * pow(1.0 - fallen, profile.caught_fade_exponent)
	return 0.0


## Thickness of the frame right now as a fraction of the shorter screen axis,
## 0.0 when nothing is playing.
##
## The two sides run this in opposite directions and that is the whole gesture:
## the taker's retreats outward off the edges, the victim's grows inward and
## stays. Exposed for the same headless reason as [method get_alpha].
func get_thickness_fraction() -> float:
	if _age < 0.0 or profile == null:
		return 0.0
	if _side == CatchSide.TAKE:
		var open: float = maxf(profile.take_open_seconds, 0.0)
		if open <= 0.0:
			return 0.0
		var gone: float = clampf(_age / open, 0.0, 1.0)
		return profile.take_thickness_fraction * pow(1.0 - gone, profile.take_open_exponent)
	if _side == CatchSide.CAUGHT:
		var close: float = maxf(profile.caught_close_seconds, 0.0)
		if close <= 0.0:
			return profile.caught_thickness_fraction
		var closed: float = clampf(_age / close, 0.0, 1.0)
		return profile.caught_thickness_fraction * pow(closed, profile.caught_close_exponent)
	return 0.0


func is_inert() -> bool:
	return _inert


# --- Internals ----------------------------------------------------------------

## Start a side. Restarts rather than blends, for the same reason
## [method FxHitReaction.react] does: a second catch inside a second is a second
## event, and averaging two of them produces neither.
func _begin(side: CatchSide, color: Color) -> void:
	_side = side
	_age = 0.0
	_color = Color(color.r, color.g, color.b, 1.0)
	queue_redraw()


## How long the side currently playing runs for.
func _duration() -> float:
	if profile == null:
		return 0.0
	if _side == CatchSide.TAKE:
		return profile.get_take_seconds()
	if _side == CatchSide.CAUGHT:
		return profile.get_caught_seconds()
	return 0.0


# --- Drawing ------------------------------------------------------------------

## Four rectangles around the edge of the screen. There is no cheaper way to put
## a colour in a player's peripheral vision and no reason to want a more
## expensive one: a shader, a texture or a particle would all need art, and all
## of them read as slower than four flat rects. It is the same argument
## [method FxHitReaction._draw] makes for its one rectangle.
##
## A FRAME and not a fill, deliberately. A player who has just been caught is
## about to be shown their own body from a spectator camera, and a player who
## has just caught somebody is about to need the whole ring; neither is served
## by having the middle of the screen painted over. The shot's flash may cover
## everything because it lasts a tenth of a second. This does not.
func _draw() -> void:
	var alpha: float = get_alpha()
	var fraction: float = get_thickness_fraction()
	if alpha <= 0.0 or fraction <= 0.0:
		return
	var thickness: float = minf(size.x, size.y) * fraction
	if thickness <= 0.0:
		return
	var colour: Color = _color
	colour.a = alpha
	# Top and bottom run the full width; the sides are inset between them, so no
	# pixel in a corner is painted twice and the alpha stays even all the way
	# round.
	draw_rect(Rect2(0.0, 0.0, size.x, thickness), colour)
	draw_rect(Rect2(0.0, size.y - thickness, size.x, thickness), colour)
	var inner_height: float = maxf(size.y - thickness * 2.0, 0.0)
	draw_rect(Rect2(0.0, thickness, thickness, inner_height), colour)
	draw_rect(Rect2(size.x - thickness, thickness, thickness, inner_height), colour)


# --- Signals ------------------------------------------------------------------

## [signal MatchController.ghost_caught], sorted onto a side.
##
## [b]The bot path is this function's first three lines and nothing else.[/b]
## Bots catch and are caught constantly -- it is the ordinary business of a
## round -- so a catch neither of whose participants is this body must cost a
## pointer comparison and return, with no colour read, no camera call, no signal
## emitted and nothing drawn. It is the identical path, and it is inert.
func _on_ghost_caught(ghost: MatchParticipant, caught: MatchParticipant) -> void:
	if _inert:
		return
	if _is_me(caught):
		play_caught(_color_of(ghost), _reach_direction(ghost, caught))
		return
	if _is_me(ghost):
		play_take(_color_of(caught))


## The direction the ghost was reaching in, flattened onto the deck.
##
## Read at the moment the signal fires, which is the only moment it is readable:
## [method MatchController._swap_with_ghost] holds the caught body exactly where
## it died and does NOT move the incoming prisoner -- it takes the spot by
## standing in it -- so both bodies are still where the catch happened when this
## runs. One frame later the respawn hold expires and the ghost is on the start
## line.
##
## Flat because the deck is flat: a catch is two people on the same floor, and a
## vertical component would only ever be the difference between two capsule
## origins.
func _reach_direction(ghost: MatchParticipant, caught: MatchParticipant) -> Vector3:
	if ghost == null or caught == null or ghost.body == null or caught.body == null:
		return Vector3.ZERO
	var delta: Vector3 = caught.body.global_position - ghost.body.global_position
	delta.y = 0.0
	if delta.length() < MIN_REACH_METRES:
		return Vector3.ZERO
	return delta.normalized()


## [param participant]'s stable palette colour. Never the live body colour; see
## [method get_color].
func _color_of(participant: MatchParticipant) -> Color:
	if participant == null or controller == null:
		return Color.WHITE
	return controller.get_runner_palette().color_for_index(participant.index)


## Walk up from the participant's body looking for this component's own. Mirrors
## [method FxHitReaction._is_me], so a body reparented under a squad node
## resolves without a change here.
func _is_me(participant: MatchParticipant) -> bool:
	if participant == null or participant.body == null:
		return false
	var node: Node = participant.body
	while node != null:
		if node == body:
			return true
		node = node.get_parent()
	return false
