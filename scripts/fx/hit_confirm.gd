class_name FxHitConfirm
extends Control

## Tells the tower player whether the shot connected, on the frame it resolves.
##
## [b]Why this is the most important component in the layer[/b]
##
## The tower has one bullet and then several seconds of enforced silence. In
## those seconds the only thing the player needs to know is binary: did that take
## someone out. Everything else -- who it was, how many are left, what the reload
## is -- is already on the HUD and can be read at leisure. The hit answer cannot:
## it decides whether the next seconds are spent relocating or re-acquiring, and
## it has to arrive faster than reading.
##
## So it is drawn at the centre of the screen, where the eye already is, and it
## is drawn as a SHAPE rather than as a word or a number.
##
## [b]Why a hit and a miss are different in three ways at once[/b]
##
## A hit draws four ticks converging on the crosshair, bright white, that pop
## outwards over a quarter of a second. A miss draws two flat dashes either side,
## dim grey, gone in less than half that. Shape, brightness and duration all
## differ, so the two are told apart by orientation alone at the edge of vision,
## by brightness alone in a glance, and by neither being needed at all if the
## player is colour-blind -- there is no colour coding to miss.
##
## A miss draws something rather than nothing on purpose. Absence carries the
## information in principle, but in practice it is indistinguishable from a
## broken effect or a blink, and a player who has just spent their only round
## should never be left auditing the feedback system instead of the ring.
##
## [b]Why it needs the [MatchController][/b]
##
## [signal Rifle.target_hit] fires for the deck, the cover and the tower wall as
## readily as for a person -- the weapon reports what it struck and deliberately
## does not decide what that means. A hitmarker on a concrete pillar would be a
## lie about the only thing the player is asking, so the collider is put through
## [method MatchController.resolve_participant], which is the match's own answer
## to "is that a player", and only a non-null result draws a hitmarker.
##
## Leave [member controller] null and every world hit reads as a kill. That is
## correct for a weapon test scene with nothing but targets in it and wrong for a
## match, so point it at the controller.
##
## Attach as a [Control] under a [CanvasLayer] with full-rect anchors, alongside
## whatever crosshair the HUD already draws.

## What the last shot did, as far as this component is concerned.
enum Mark {
	## Nothing drawn.
	NONE,
	## A participant was struck. The only outcome that earns a hitmarker.
	CONFIRMED,
	## The shot stopped on the world.
	WORLD,
	## The shot reached maximum range without stopping.
	MISS,
}

## Emitted when a mark is raised, for anything downstream that wants the same
## classification without redoing it -- audio, a killfeed, a stat counter.
signal shot_classified(mark: Mark)

## The weapon to listen to. A node reference rather than a path resolved once, so
## it survives [MatchController] reparenting the rifle onto a new seat holder.
@export var rifle: Rifle

## The match, used only to ask whether a collider is a person. Optional; see the
## class description for what null means.
@export var controller: MatchController

## This rig's own body, when it has one. There is exactly ONE rifle in a match and
## it is reparented onto whoever holds the tower, so every listener in the game
## hears every shot -- including the shots an AI seat holder takes. Set this to
## the body this rig belongs to and a mark is raised only while
## [member Rifle.shooter_body] is that body, which is precisely
## [MatchController]'s own record of who is holding the weapon.
##
## Leave it null and every shot by anyone counts, which is right for a weapon
## test scene with one shooter in it and wrong for a match.
@export var owner_body: CollisionObject3D

## Tunables.
@export var profile: FeedbackProfile

## Optional. When set, a confirmed kill also gets a small translation-only camera
## punch through it.
@export var camera_kick: FxCameraKick

## Go inert when there is no display server.
@export var headless_inert: bool = true

const HEADLESS_DISPLAY: String = "headless"

## The four diagonals a hitmarker's ticks lie on, as unit vectors.
const HIT_TICKS: Array[Vector2] = [
	Vector2(-0.70710678, -0.70710678),
	Vector2(0.70710678, -0.70710678),
	Vector2(-0.70710678, 0.70710678),
	Vector2(0.70710678, 0.70710678),
]

## Which side of centre each miss dash sits on.
const MISS_SIDES: Array[float] = [-1.0, 1.0]

var _mark: Mark = Mark.NONE
var _age: float = 0.0
var _inert: bool = false


func _ready() -> void:
	if headless_inert and DisplayServer.get_name() == HEADLESS_DISPLAY:
		_inert = true
		set_process(false)
		hide()
		return
	if profile == null:
		push_error("FxHitConfirm has no FeedbackProfile; no hitmarker will be drawn.")
		_inert = true
		set_process(false)
		return
	if rifle == null:
		push_error("FxHitConfirm has no Rifle to listen to.")
		_inert = true
		set_process(false)
		return
	# A hitmarker must never eat a click meant for a menu.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	rifle.target_hit.connect(_on_target_hit)
	rifle.missed.connect(_on_missed)


func _process(delta: float) -> void:
	tick(delta)


## Advance the mark's clock by [param delta] seconds. Public for the same reason
## [method Rifle.tick] is: a harness may want to step it by hand.
func tick(delta: float) -> void:
	if _mark == Mark.NONE:
		return
	_age += delta
	if _age >= _duration_of(_mark):
		_mark = Mark.NONE
		_age = 0.0
	queue_redraw()


# --- Public API ---------------------------------------------------------------

## Raise a mark directly, bypassing the weapon. For a test, and for a future
## networked client that is told about its own hits rather than casting them.
func show_mark(mark: Mark) -> void:
	if _inert or profile == null or not profile.enabled:
		return
	if mark == Mark.CONFIRMED and not profile.hit_confirm_enabled:
		return
	if mark != Mark.CONFIRMED and not profile.miss_mark_enabled:
		return
	_mark = mark
	_age = 0.0
	if mark == Mark.CONFIRMED and camera_kick != null:
		camera_kick.confirm()
	shot_classified.emit(mark)
	queue_redraw()


## Take whatever is on screen down immediately. For a round reset or a seat
## change, so a mark cannot survive into a round it does not describe.
func clear() -> void:
	if _mark == Mark.NONE:
		return
	_mark = Mark.NONE
	_age = 0.0
	queue_redraw()


## True when the shot that just happened was this rig's own. See
## [member owner_body].
func is_holding_the_rifle() -> bool:
	return owner_body == null or (rifle != null and rifle.shooter_body == owner_body)


## The mark currently on screen, or [constant Mark.NONE].
func get_mark() -> Mark:
	return _mark


## Seconds the current mark has been up.
func get_mark_age() -> float:
	return _age


## Current alpha multiplier of the mark, 1.0 the instant it appears and 0.0 when
## it is spent. Exposed so a headless check can assert the fade runs without a
## viewport to look at, exactly as [method Tracer.get_fade] is.
func get_fade() -> float:
	if _mark == Mark.NONE:
		return 0.0
	var duration: float = _duration_of(_mark)
	if duration <= 0.0:
		return 0.0
	var remaining: float = clampf(1.0 - _age / duration, 0.0, 1.0)
	var exponent: float = (
		profile.hitmarker_fade_exponent
		if _mark == Mark.CONFIRMED
		else profile.miss_mark_fade_exponent
	)
	return pow(remaining, exponent)


func is_inert() -> bool:
	return _inert


# --- Drawing ------------------------------------------------------------------

func _draw() -> void:
	if _mark == Mark.NONE or profile == null:
		return
	var centre: Vector2 = size * 0.5
	if _mark == Mark.CONFIRMED:
		_draw_hitmarker(centre)
	else:
		_draw_miss_mark(centre)


## Four ticks on the diagonals, travelling outwards as they fade. The outward
## travel is what makes it read as an impact rather than as a symbol switching
## on, and it costs one lerp.
func _draw_hitmarker(centre: Vector2) -> void:
	var fade: float = get_fade()
	var travelled: float = profile.hitmarker_spread_pixels * (1.0 - fade)
	var inner: float = profile.hitmarker_gap_pixels + travelled
	var outer: float = inner + profile.hitmarker_length_pixels
	var colour: Color = profile.hitmarker_color
	colour.a = profile.hitmarker_color.a * fade
	for direction: Vector2 in HIT_TICKS:
		draw_line(
			centre + direction * inner,
			centre + direction * outer,
			colour,
			profile.hitmarker_width_pixels,
			true,
		)


## Two flat dashes, left and right. Horizontal against the hitmarker's diagonals,
## so the two shapes share no edge orientation and cannot be confused at speed.
func _draw_miss_mark(centre: Vector2) -> void:
	var fade: float = get_fade()
	var inner: float = profile.miss_mark_gap_pixels
	var outer: float = inner + profile.miss_mark_length_pixels
	var colour: Color = profile.miss_mark_color
	colour.a = profile.miss_mark_color.a * fade
	for sign_x: float in MISS_SIDES:
		draw_line(
			centre + Vector2(sign_x * inner, 0.0),
			centre + Vector2(sign_x * outer, 0.0),
			colour,
			profile.miss_mark_width_pixels,
			true,
		)


# --- Signals ------------------------------------------------------------------

func _on_target_hit(collider: Node3D, _hit_position: Vector3, _hit_normal: Vector3) -> void:
	if not is_holding_the_rifle():
		return
	show_mark(_classify(collider))


func _on_missed(_end_point: Vector3) -> void:
	if not is_holding_the_rifle():
		return
	show_mark(Mark.MISS)


## Was that a person or was that a wall. The match owns the answer, because the
## map from collider to participant is built when the match starts and nothing
## else has it.
func _classify(collider: Node3D) -> Mark:
	if controller == null:
		return Mark.CONFIRMED
	return Mark.CONFIRMED if controller.resolve_participant(collider) != null else Mark.WORLD


func _duration_of(mark: Mark) -> float:
	if profile == null:
		return 0.0
	return profile.hitmarker_seconds if mark == Mark.CONFIRMED else profile.miss_mark_seconds
