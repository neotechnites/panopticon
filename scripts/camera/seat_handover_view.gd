class_name SeatHandoverView
extends Node3D

## The tower changing hands, as the player experiences it.
##
## [b]The problem this exists to solve[/b]
##
## The seat is a role, not a body -- see [MatchController] -- so a seat change is
## implemented as [method MatchController.start_round] writing a new
## [member Node3D.global_position] onto every body in the match on one tick. The
## human's [Camera3D] is a child of their body. The most dramatic thing that can
## happen in a match therefore arrived as a single-frame teleport with nothing
## to mark it: one frame you are running the ring, the next you are 38 m away and
## 12 m up, facing a different direction, and the game has said nothing at all.
##
## This node is the whole answer. It does not change where anybody goes or when.
## It puts a camera between the two poses for about a second.
##
## [codeblock]
## seat_changed
##     |
##     +-- CAPTURE ... the pose the player is in, this instant, before
##     |               MatchController.start_round() moves anybody.
##     v
##     +-- VERIFY .... one frame later, once the placement has happened: did
##     |               the player's eye actually move? A shooter defending the
##     |               tower re-takes the seat without going anywhere, and that
##     |               is cancelled here rather than flown.
##     v
##     +-- HOLD ....... hold_seconds at the pose the player was in.
##     |                The bodies teleport underneath this; the view does not.
##     |                This is the beat that makes it read as an event.
##     v
##     +-- TRAVEL .... eased flight to wherever the player's camera now is,
##     |                arcing over the deck, field of view surging through
##     |                the middle.
##     v
##     +-- HAND BACK .. the player's own camera is made current again, the
##                      mouse is returned, and this node is inert until the
##                      next seat change.
## [/codeblock]
##
## [b]It is a camera of its own, not the player's camera moved[/b]
##
## Exactly the argument [FxSpectatorView] makes, and for the same three reasons:
## [WeaponOptic] owns the player camera's [member Camera3D.fov], [FxCameraKick]
## owns its local transform, and [PauseMenu] writes the display FOV into it.
## Driving that camera would put this node into a fight with all three. So it
## carries its own, makes it [member Camera3D.current] for the length of the
## handover, and hands the view back explicitly. The only field it ever writes on
## the player's camera is [member Camera3D.current], and the only thing it ever
## asks it for is where it is.
##
## [b]A bot taking the tower is a no-op, not a special case[/b]
##
## There is one branch on who the human is, and it is
## [method MatchController.get_human_participant] returning null in a match with
## no human in it. Everything below then does nothing, because there is no camera
## to carry. A bot-only harness match runs the identical seat-change path and
## never enters this file past the first guard.
##
## [b]Who wins when the player is dead[/b]
##
## [FxSpectatorView] does, unconditionally. If the human was spectating when a
## seat change lands, this node does not arm; if the human starts spectating
## mid-handover, this node stands down on that frame and gives the view back. Two
## nodes fighting over [member Camera3D.current] is a black screen, and the dead
## player's camera is the more urgent of the two claims.
##
## [b]"Was", not "is".[/b] The state that decides this is sampled once a frame
## and read from the previous one, because by the time a seat change is announced
## the match has already cleared the respawn hold that made the player dead. See
## [method _remember_who_is_watching] -- it is the single most load-bearing
## twenty lines in this file.
##
## [b]Both directions ship as a CUT, and the machinery is still here[/b]
##
## Ryan's words: "i dont like the camera jumping from the middle to the start
## when you loose, i dont mind that just being a jump cut." What replaced it is
## [RoundTransitionScreen], a between-rounds card raised on
## [signal MatchController.round_started] -- and every seat change restarts the
## round, so the card covers the arrival as well as the reset. Flying underneath
## an opaque screen is work nobody sees.
##
## So [member SeatHandoverProfile.fly_to_tower] and
## [member SeatHandoverProfile.fly_to_ring] both ship false and every seat change
## cuts. Everything below still exists, is still tested, and is one exported
## boolean from being back: the flight was not wrong, it was made redundant.
## What this node still does on every seat change, cut or not, is drop the
## player's zoom -- see [member SeatHandoverProfile.reset_zoom_on_handover],
## which is a bug fix and not a flourish.
##
## Strictly additive. It writes nothing any gameplay script reads, subscribes to
## signals [MatchController] already emits, and deleting it leaves the match
## exactly as it was.

## Emitted when the handover takes the view, and when it hands back. The hook for
## anything that wants to know without polling.
signal handover_changed(active: bool)

## Which way the player is being carried. Only the duration differs; the shape of
## the move does not.
enum Direction {
	## Not carrying anybody.
	NONE,
	## The player has just taken the tower.
	TO_TOWER,
	## The player is being put on the ring -- because they lost the tower, or
	## because somebody else's seat change restarted the round around them.
	TO_RING,
}

## The match to listen to. Without one this node does nothing at all.
@export var controller: MatchController

## This node's own camera. Normally a [Camera3D] child of it. Never the player's.
@export var camera: Camera3D

## The camera the view is taken from and given back to -- normally
## [code]Player/Head/Camera[/code].
##
## Held as a reference rather than discovered, and restored EXPLICITLY, for the
## reason [member FxSpectatorView.player_camera] gives: Godot does not promise
## which camera becomes current when the current one steps down, and a match that
## came out of a handover with no camera at all would be a black screen.
@export var player_camera: Camera3D

## The human's input device, muted for the length of the handover.
##
## [b]Not politeness -- the same bug [FxSpectatorView] documents.[/b]
## [HumanIntentSource] banks mouse motion in pixels and drains it when
## [PlayerController] polls it, and a body being placed by
## [method MatchController.start_round] is held inert and not polling. A second
## of banked mouse would otherwise land on the aim in one frame the instant the
## body woke, and spin a player who has just been handed the tower.
## [method HumanIntentSource.set_active] both stops the reading and drops what
## was banked, which is exactly the pair of things wanted here.
@export var human_input: HumanIntentSource

## The human's optic, dropped to hipfire when the seat changes.
##
## Optional; see [member SeatHandoverProfile.reset_zoom_on_handover] for why it
## is worth wiring. Never driven beyond that one call -- the optic owns the
## player camera's field of view and this node owns its own camera's.
@export var optic: WeaponOptic

## Tunables. Without one this node does nothing and says so.
@export var profile: SeatHandoverProfile

## Go inert when there is no display server. A headless bot sweep has no view to
## carry and no mouse to borrow, and pays nothing for this node existing.
@export var headless_inert: bool = true

const HEADLESS_DISPLAY: String = "headless"

var _inert: bool = false

## Armed by [signal MatchController.seat_changed], but not yet carrying
## anything. See [method _take_the_view] for the one frame that sits between the
## two and why it has to.
var _armed: bool = false
var _active: bool = false
var _direction: Direction = Direction.NONE

## Seconds since the handover was armed, including the hold.
var _elapsed: float = 0.0

## The pose and lens the player's camera had at the instant the seat changed.
var _from: Transform3D = Transform3D.IDENTITY
var _from_fov: float = 0.0

## Whether this node currently has the human's input device switched off.
var _input_muted: bool = false

## Whether the human was watching rather than playing, as of the last frame that
## finished before now.
##
## [b]Remembered rather than asked for, and that is the whole point.[/b] See
## [method _remember_who_is_watching]: by the time
## [signal MatchController.seat_changed] is emitted, the match has already begun
## dismantling the round, and every flag this question would be answered from has
## been overwritten. The last settled frame is the most recent moment at which
## the answer was true.
var _was_spectating: bool = false

## Set on [signal MatchController.match_started] and cleared by the first thing
## that happens after it.
##
## The opening grant of a match emits [signal MatchController.seat_changed] like
## any other, but there is nothing to carry the player FROM: no round has been
## played, the bodies are at their authored transforms, and flying the camera in
## from the scene origin would open every match with a swoop through the floor.
## A race clears this flag, because the first arrival out of a race is a real
## handover from a real position.
var _opening: bool = false


func _ready() -> void:
	if headless_inert and DisplayServer.get_name() == HEADLESS_DISPLAY:
		_inert = true
		set_process(false)
		return
	if profile == null:
		push_error("SeatHandoverView has no SeatHandoverProfile; seat changes will cut.")
		_inert = true
		set_process(false)
		return
	if camera == null:
		push_error("SeatHandoverView has no Camera3D of its own to carry the view with.")
		_inert = true
		set_process(false)
		return
	if controller == null:
		push_error("SeatHandoverView has no MatchController to hear seat changes from.")
		_inert = true
		set_process(false)
		return
	camera.current = false
	subscribe()


## Connect to the match. Called from [method _ready]; public so a test may point
## a hand-built instance at a live controller after the fact.
func subscribe() -> void:
	if controller == null:
		return
	if not controller.seat_changed.is_connected(_on_seat_changed):
		controller.seat_changed.connect(_on_seat_changed)
	if not controller.match_started.is_connected(_on_match_started):
		controller.match_started.connect(_on_match_started)
	if not controller.race_started.is_connected(_on_race_started):
		controller.race_started.connect(_on_race_started)


func _process(delta: float) -> void:
	tick(delta)


## Never hand a scene back with somebody else's camera current, or with the
## human's input still muted.
func _exit_tree() -> void:
	stand_down()


## Advance the handover. Public so a harness or a test may step it at a fixed
## delta, the same seam [method FxCameraKick.tick] and [method WeaponOptic.tick]
## offer.
func tick(delta: float) -> void:
	# First, and unconditionally: this runs on every frame of the match, not only
	# on the frames this node is carrying somebody.
	_remember_who_is_watching()

	if not (_armed or _active):
		return
	if profile == null or not profile.enabled:
		stand_down()
		return
	if player_camera == null or not is_instance_valid(player_camera):
		stand_down()
		return
	# The dead player's camera outranks this one. See the class notes.
	if controller != null and controller.is_spectating(controller.get_human_participant()):
		stand_down()
		return

	if _armed:
		_armed = false
		if not _take_the_view():
			return

	_elapsed += delta
	var travel: float = maxf(_travel_seconds(), 0.0001)
	var t: float = clampf((_elapsed - profile.hold_seconds) / travel, 0.0, 1.0)
	_place(t)

	if t >= 1.0:
		stand_down()


# --- Public API ---------------------------------------------------------------

## True while this node owns the view.
##
## False for the one frame between the seat changing and the handover verifying
## that the player actually moved -- see [method _take_the_view] -- and false
## forever after that if they did not.
func is_active() -> bool:
	return _active


## Which way the player is being carried, or [constant Direction.NONE].
func get_direction() -> Direction:
	return _direction


## Seconds since the handover was armed, including
## [member SeatHandoverProfile.hold_seconds]. Zero when nothing is running.
func get_elapsed_seconds() -> float:
	return _elapsed if _active else 0.0


## How far through the TRAVEL the camera is, from 0.0 to 1.0. Stays at 0.0 for
## the length of the hold, which is the readout a test asserts the beat against.
func get_travel_progress() -> float:
	if not _active or profile == null:
		return 0.0
	return clampf(
		(_elapsed - profile.hold_seconds) / maxf(_travel_seconds(), 0.0001), 0.0, 1.0
	)


## How long the whole handover takes, hold included, in seconds.
func get_total_seconds() -> float:
	if profile == null:
		return 0.0
	return profile.hold_seconds + _travel_seconds()


## Give the view back now, whatever is running. For a teardown, a scene change,
## and a test that must not leave a camera current or a mouse muted.
func stand_down() -> void:
	var was_active: bool = _active
	_active = false
	_armed = false
	_direction = Direction.NONE
	_elapsed = 0.0
	if camera != null and is_instance_valid(camera):
		camera.current = false
	# Explicitly, and in this order: the player's camera is made current before
	# the input device is given back, so a frame can never exist in which the
	# body is being aimed by a mouse whose view has not been restored.
	if was_active and player_camera != null and is_instance_valid(player_camera):
		player_camera.current = true
	_mute_input(false)
	if was_active:
		handover_changed.emit(false)


func is_inert() -> bool:
	return _inert


# --- Internals ----------------------------------------------------------------

## The seat has changed hands. Capture the pose the player is in RIGHT NOW,
## before anything teleports, and arm the handover.
##
## [b]Why this is a signal and not a poll[/b], unlike [FxSpectatorView]: being
## dead is a STATE that a view can join half way through, but a handover is an
## EDGE, and the whole value of this node is capturing the pose the player was in
## on the exact tick the edge happened. One frame later the body has already been
## teleported and there is nothing left to carry them from.
##
## [method MatchController.take_seat] emits this BEFORE
## [method MatchController.start_round] places anybody, which is what makes the
## capture below correct rather than lucky.
func _on_seat_changed(participant: MatchParticipant, _turns_in_tower: int) -> void:
	if _inert or profile == null or not profile.enabled:
		return
	if _opening:
		# The opening grant of a match. Nothing to carry from; see _opening.
		_opening = false
		return
	if controller == null:
		return
	var human: MatchParticipant = controller.get_human_participant()
	# A match with no human in it. The seat still changes, the bots still play,
	# and this node has nothing to do -- which is the whole of "a bot taking the
	# tower must be a no-op".
	if human == null:
		return
	if player_camera == null or not is_instance_valid(player_camera):
		return
	# The dead player's camera outranks this one. Asked of the LAST SETTLED
	# FRAME rather than of this instant -- see _remember_who_is_watching for why
	# this instant cannot answer it -- with a live check on the respawn hold
	# behind it, in case the human died in the same frame this arrived.
	if _was_spectating or controller.is_awaiting_respawn(human):
		return

	# EVERY seat change moves the human: they either take the tower, or they are
	# put back on the start line by the round restart that follows. Only the
	# duration differs -- and, since the round card, only whether it is flown at
	# all.
	var to_tower: bool = participant == human

	# Above the cut branch on purpose. Dropping the zoom is a FIX and not part of
	# the flight -- see [member SeatHandoverProfile.reset_zoom_on_handover] --
	# and a player who lost the tower mid-shot must not begin their next lap
	# looking down a 2.5x scope whether or not the seat change is carried.
	if profile.reset_zoom_on_handover and optic != null and is_instance_valid(optic):
		optic.reset_zoom()

	if not profile.flies(to_tower):
		# A jump cut: exactly what the seat change did before this node existed.
		# No camera is taken and the mouse is NOT borrowed -- the body is held
		# only for [constant MatchController.SETTLE_PHYSICS_FRAMES], which is two
		# ticks, and muting an input device for two ticks buys nothing and is one
		# more thing that can be left muted.
		_direction = Direction.NONE
		return

	_direction = Direction.TO_TOWER if to_tower else Direction.TO_RING
	_from = player_camera.global_transform
	_from_fov = player_camera.fov

	_elapsed = 0.0
	# Muted NOW rather than on the frame the view is taken: the body is already
	# being held inert by the placement this signal precedes, and every
	# millisecond of that is banked pixels waiting to spin the aim.
	_mute_input(true)
	_armed = true
	_active = false


## Decide, on the first frame after the seat changed, whether there is anything
## to carry -- and take the view if there is. Returns false when the handover was
## cancelled.
##
## [b]Why this cannot happen in [method _on_seat_changed][/b]
##
## That signal is emitted by [method MatchController.take_seat] BEFORE
## [method MatchController.start_round] moves anybody, which is exactly what
## makes the captured pose the right one -- and exactly what makes the
## DESTINATION unknown at that moment. One frame later the placement has
## happened and the question "did the player's eye actually move" has an answer.
##
## It has an interesting answer, too: a shooter who converts the whole field
## defends the tower and takes the seat again, which restarts the round and
## relocates every runner while leaving the defender standing precisely where
## they were. See [member SeatHandoverProfile.minimum_travel_metres].
##
## Nothing is shown in the meantime and no frame is lost. Godot runs the physics
## step -- where a finished lap is reported from -- before the idle step this is
## called from, and draws after both, so the deferral is invisible.
func _take_the_view() -> bool:
	if camera == null or not is_instance_valid(camera):
		_mute_input(false)
		return false
	var travelled: float = _from.origin.distance_to(player_camera.global_position)
	if travelled < profile.minimum_travel_metres:
		# The player did not go anywhere. Give the mouse back and say nothing.
		_direction = Direction.NONE
		_mute_input(false)
		return false

	camera.global_transform = _from
	camera.fov = _from_fov
	camera.current = true
	_active = true
	handover_changed.emit(true)
	return true


## Note, once a frame, whether the human is watching rather than playing.
##
## [b]This is not a cache; it is the only honest place to ask.[/b] The question
## the handover has to answer is "was this player dead when the tower changed
## hands", and by the time [signal MatchController.seat_changed] arrives the
## match has already answered a different question. Two things happen first, in
## this order, inside the same call stack:
##
## [codeblock]
## MatchController._score_and_restart()
##   _resolve(LOSS)
##     _freeze_runners()   -> respawn_hold_remaining = 0.0 on EVERY runner,
##                            including the dead one. A player two seconds into
##                            a three second hold now reads as alive.
##   take_seat(scorer)
##     previous.is_shooter = false
##                         -> the OUTGOING shooter is now neither a shooter nor
##                            a runner nor a ghost, and MatchController's
##                            phase-derived fallback reads that as ELIMINATED:
##                            a player who has never been more alive reads as
##                            watching. start_round() makes them a runner again
##                            a few lines later.
##     seat_changed.emit() -> and only now does this node hear about it.
## [/codeblock]
##
## Both of those are correct for the match and useless to this node: asked at
## that instant, [method MatchController.is_spectating] says the living are dead
## and the dead are living, and it says so in exactly the two cases that matter
## -- the player who lost the tower, and the player who was shot. The last frame
## that finished before any of it started is the most recent moment at which the
## answer was about the PLAYER rather than about a half-dismantled round.
func _remember_who_is_watching() -> void:
	if _inert or controller == null:
		return
	_was_spectating = controller.is_spectating(controller.get_human_participant())


func _on_match_started(_participant_count: int) -> void:
	_opening = true
	stand_down()


func _on_race_started() -> void:
	# A race has placed everybody at a real position, so the arrival that ends it
	# is a handover with something to fly from.
	_opening = false


func _travel_seconds() -> float:
	if profile == null:
		return 0.0
	return (
		profile.to_tower_seconds
		if _direction == Direction.TO_TOWER
		else profile.to_ring_seconds
	)


## Where the camera is and what it is looking at, [param t] of the way through
## the travel.
##
## The destination is read LIVE off the player's camera every frame rather than
## captured once, so a body that is still settling -- or one the physics server
## drops a few centimetres onto the deck two frames after it is placed, which is
## exactly what [method MatchController._hold_body] arranges -- is arrived at
## where it ended up rather than where it was first written.
func _place(t: float) -> void:
	var to: Transform3D = player_camera.global_transform
	var eased: float = _shape(t)

	var here: Vector3 = _from.origin.lerp(to.origin, eased)
	# Over the deck rather than through the cover. A sine is zero at both ends,
	# so the arc adds nothing to either pose and the arrival is exact.
	here.y += profile.arc_height_metres * sin(PI * t)
	camera.global_position = here

	# Quaternion slerp, not an interpolation of Euler angles: the two poses can
	# be most of a turn apart -- the tower faces the ring and a runner faces
	# along it -- and Euler blending on that takes the long way round and rolls
	# the horizon on the way.
	camera.global_basis = Basis(
		Quaternion(_from.basis.orthonormalized()).slerp(
			Quaternion(to.basis.orthonormalized()), eased
		)
	)

	# Ends on whatever the player's camera is at right now, which after
	# reset_zoom_on_handover is their un-zoomed display FOV -- so a player who
	# was scoped when the seat changed is pulled out of the scope by the flight
	# instead of finding themselves out of it on arrival.
	camera.fov = (
		lerpf(_from_fov, player_camera.fov, eased)
		+ profile.fov_surge_degrees * sin(PI * t)
	)


## The same smoothstep blend [method WeaponOptic._shape] applies, for the same
## reason: a move that lurches into motion and stops dead reads as a teleport.
func _shape(t: float) -> float:
	if profile == null:
		return t
	var smoothing: float = clampf(profile.smoothing, 0.0, 1.0)
	if smoothing <= 0.0:
		return t
	var eased: float = t * t * (3.0 - 2.0 * t)
	return lerpf(t, eased, smoothing)


## Take the mouse off the body, or give it back. Idempotent.
func _mute_input(muted: bool) -> void:
	if _input_muted == muted:
		return
	_input_muted = muted
	if human_input != null and is_instance_valid(human_input):
		human_input.set_active(not muted)
