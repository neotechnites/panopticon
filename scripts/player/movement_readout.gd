class_name MovementReadout
extends Control

## The instrument panel for the movement playground.
##
## One question this exists to answer: [i]does that feel right[/i]. That is not
## a question a number can answer on its own, but it is a question nobody can
## answer without one, because every technique in this game is worth a specific
## quantity of metres per second and the difference between a good hop and a
## wasted one is about one of them. So the panel is deliberately three things
## and no more:
##
## - [b]Live horizontal speed[/b], large enough to read out of the corner of the
##   eye while both hands are busy.
## - [b]A rail with a peak marker[/b], because the eye reads a position on a
##   line far faster than it reads a changing number, and because the peak is
##   what a run is scored on. The ground speed and the slide's thresholds are
##   ticked onto the rail from [MovementProfile], so the live speed is always
##   shown against the thresholds that produced it rather than against nothing.
## - [b]The hop ledger[/b]: the speed the last jump left the ground with and the
##   speed the next landing arrived with. A bunny hop that works has those two
##   numbers equal or the second one larger; a hop that does not shows the loss
##   immediately, which is otherwise almost impossible to see.
##
## It reads the body rather than being told by it -- speed is polled, and only
## the events that happen once and must not be missed (a jump, a landing, a
## slide opening) come from signals.
##
## Nothing here is part of the game. It draws no conclusions, changes no
## physics, and is only ever instanced by a dev scene.

## The body to report on.
@export var body: PlayerController

## Big live speed, in m/s.
@export var speed_label: Label

## Peak speed since the last reset.
@export var peak_label: Label

## GROUND / AIR / SLIDE, plus the slide's remaining time.
@export var state_label: Label

## The hop ledger and the controls.
@export var detail_label: Label

## Background of the speed rail. The fill, the peak marker and the threshold
## ticks are all positioned inside it, so its width sets the scale.
@export var rail: ColorRect

## Filled portion of the rail.
@export var rail_fill: ColorRect

## Peak marker riding on the rail.
@export var rail_peak: ColorRect

## Speed at the right-hand end of the rail, in m/s. Set it above anything the
## profile can reach on the ground so the ticks are not crushed together, but
## low enough that ordinary running is not a sliver.
@export_range(5.0, 100.0, 1.0) var rail_full_speed: float = 32.0

## The peak resets itself once the body has been slower than this for
## [member peak_reset_idle_seconds]. Standing still is how you say "new run"
## without needing a key bound for it.
@export_range(0.0, 5.0, 0.1) var peak_reset_speed: float = 0.2

@export_range(0.5, 30.0, 0.5) var peak_reset_idle_seconds: float = 1.5

var _peak: float = 0.0
var _idle_seconds: float = 0.0
var _launch_speed: float = 0.0
var _landing_speed: float = 0.0
var _has_hop: bool = false


func _ready() -> void:
	if body == null:
		push_error("MovementReadout has no PlayerController; there is nothing to report.")
		set_process(false)
		return
	body.jumped.connect(_on_jumped)
	body.landed.connect(_on_landed)
	_build_rail_ticks()


func _process(delta: float) -> void:
	var speed: float = body.get_horizontal_speed()
	_peak = maxf(_peak, speed)

	if speed <= peak_reset_speed:
		_idle_seconds += delta
		if _idle_seconds >= peak_reset_idle_seconds:
			_peak = 0.0
			_has_hop = false
	else:
		_idle_seconds = 0.0

	if speed_label != null:
		speed_label.text = "%5.2f m/s" % speed
	if peak_label != null:
		peak_label.text = "peak %.2f" % _peak
	if state_label != null:
		state_label.text = _describe_state()
	if detail_label != null:
		detail_label.text = _describe_detail()
	_lay_out_rail(speed)


# --- Rail ---------------------------------------------------------------------

## Put a tick and a caption on the rail at every speed the profile names, so the
## live bar is read against the ground speed and the slide's ceiling rather than
## against an unlabelled scale.
func _build_rail_ticks() -> void:
	if rail == null or body.profile == null:
		return
	var profile: MovementProfile = body.profile
	_add_tick(profile.ground_speed, "ground")
	_add_tick(profile.slide_min_entry_speed, "slide from")
	_add_tick(profile.slide_boost_speed_cap, "slide cap")


func _add_tick(speed: float, caption: String) -> void:
	var fraction: float = clampf(speed / rail_full_speed, 0.0, 1.0)

	var mark: ColorRect = ColorRect.new()
	mark.color = Color(1.0, 1.0, 1.0, 0.45)
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.set_anchors_preset(Control.PRESET_TOP_LEFT)
	rail.add_child(mark)
	mark.size = Vector2(2.0, rail.size.y)
	mark.position = Vector2(rail.size.x * fraction - 1.0, 0.0)

	var text: Label = Label.new()
	text.text = "%s %.0f" % [caption, speed]
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_theme_font_size_override(&"font_size", 15)
	text.add_theme_color_override(&"font_color", Color(0.82, 0.84, 0.88, 1.0))
	text.set_anchors_preset(Control.PRESET_TOP_LEFT)
	rail.add_child(text)
	text.position = Vector2(rail.size.x * fraction + 4.0, rail.size.y + 2.0)


func _lay_out_rail(speed: float) -> void:
	if rail == null:
		return
	var width: float = rail.size.x
	if rail_fill != null:
		rail_fill.position = Vector2.ZERO
		rail_fill.size = Vector2(width * clampf(speed / rail_full_speed, 0.0, 1.0), rail.size.y)
		rail_fill.color = _speed_colour(speed)
	if rail_peak != null:
		rail_peak.size = Vector2(4.0, rail.size.y + 12.0)
		rail_peak.position = Vector2(
			width * clampf(_peak / rail_full_speed, 0.0, 1.0) - 2.0, -6.0
		)


## Green up to the ground speed, amber to the slide ceiling, hot above it -- the
## three regimes the movement actually has.
func _speed_colour(speed: float) -> Color:
	var profile: MovementProfile = body.profile
	if profile == null or speed <= profile.ground_speed:
		return Color(0.36, 0.72, 0.44, 1.0)
	if speed <= profile.slide_boost_speed_cap:
		return Color(0.86, 0.70, 0.26, 1.0)
	return Color(0.90, 0.38, 0.24, 1.0)


# --- Text ---------------------------------------------------------------------

func _describe_state() -> String:
	if body.is_sliding():
		return "SLIDE   %.2f s left" % body.get_slide_time_remaining()
	if body.is_on_floor():
		var cooldown: float = body.get_slide_cooldown_remaining()
		if cooldown > 0.0:
			return "GROUND  slide ready in %.2f s" % cooldown
		return "GROUND  slide ready"
	return "AIR     %+.1f m/s vertical" % body.velocity.y


func _describe_detail() -> String:
	var hop: String = "hop     --"
	if _has_hop:
		hop = "hop     left %.2f  -->  landed %.2f  (%+.2f)" % [
			_launch_speed, _landing_speed, _landing_speed - _launch_speed,
		]
	return "%s\nkeys    WASD move / Space jump (hold to bunny hop) / Shift slide\npeak    resets after %.1f s standing still" % [
		hop, peak_reset_idle_seconds,
	]


func _on_jumped() -> void:
	_launch_speed = body.get_horizontal_speed()


func _on_landed(_impact_speed: float) -> void:
	_landing_speed = body.get_horizontal_speed()
	_has_hop = true
