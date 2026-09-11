class_name MatchResultScreen
extends CanvasLayer

## What the player is told when a match ends, and the two ways out of it.
##
## Until this existed a match resolved in silence: [MatchController] knew who had
## won, froze the world, and told nobody -- and the only way to play a second
## match was to relaunch the game. This node closes that loop. It says who won
## and in what role, and it offers Play Again and Main Menu.
##
## [b]It invents no score.[/b] Everything on the screen is read back off
## [MatchController] at the moment the screen is shown -- the winner, the role
## each participant ended in, the rounds played, how many prisoners were cleared
## out of how many. There is deliberately no tally kept here, because a second
## idea of who won is a second thing to keep in step with the first. The same
## rule the [MatchHud] follows: read state, do not mirror it.
##
## [b]What "won" means, exactly.[/b] Under the shipped rules
## ([constant MatchRules.ShooterWinCondition.TOTAL_CONVERSION]) a match is only
## ever won from the tower: [method MatchController._award_round_to_shooter] is
## the sole caller of the private win, and it fires when the seat holder has
## cleared the ring. Reaching the end wins the SEAT, never the match. So the
## winner named here is always the tower holder, and the player's own line is
## written from [method MatchParticipant.get_role_name] rather than from a guess:
## they held the tower, or they were a prisoner and the tower cleared them. The
## "prisoner survived" branch is written too, and today it is unreachable --
## total conversion cannot end a match with a prisoner still running. It exists
## so that the day [constant MatchRules.ShooterWinCondition.HOLD_DURATION] or a
## round time limit is implemented, the screen already says the true thing
## instead of the convenient one.
##
## [b]Structure lives in the scene.[/b] The layout is authored in
## [code]scenes/ui/match_result_screen.tscn[/code] and this file binds the
## [code]%[/code]-named nodes and drives text into them, exactly as
## [SettingsScreen] does. [code]MatchResultScreen.new()[/code] would hand back a
## bare [CanvasLayer] with no dialog in it; instance the scene.
##
## [b]It does not pause the tree.[/b] It does not need to: a won match has
## already been frozen by [MatchController], down to switching off every body's
## physics process, and the ghost tick and the arrival handler both refuse to do
## anything once the match is resolved. Pausing on top of that would only give
## [PauseMenu] a paused tree it did not pause and does not know to unpause.
##
## [b]The beat before the dialog.[/b] A match used to end by a dialog box
## appearing. [signal MatchController.match_won] now raises a short banner over
## the frozen arena -- the verdict and who won, nothing to press -- and only when
## it has run does the dialog appear. It is worth spelling out what it is not:
## it is not a pause (the match was already frozen), it does not delay
## [signal MatchController.match_won], it decides nothing, and
## [member MatchAnnouncementProfile.win_beat_enabled] turns it off. The dialog
## that follows is byte for byte the one that was there before.
##
## Three things keep it from becoming a tax on the person testing this game
## hundreds of times a day:
## [codeblock]
##   any key, click or pad button  -> skipped, dialog now
##   headless                      -> never runs at all
##   win_beat_seconds              -> a number in a .tres, not in this file
## [/codeblock]
## The headless case is the one with teeth. [method GameSettings.is_headless]
## gates it, so tools/harness/ and the whole test suite reach [method show_result]
## on the same frame [signal MatchController.match_won] fires, exactly as they
## did before this existed -- there is no wait to sit through in a run with no
## screen to sit in front of, and no test has to learn about a timer.
##
## The beat's sound is [constant AudioEvents.MATCH_WON], which
## [MatchAudioListener] already posts off the same signal. This file posts
## nothing; a second post would double-trigger the cue.
##
## [b]The mouse.[/b] Opening records [member Input.mouse_mode] and forces it
## visible, because a player who cannot see a cursor cannot press Play Again;
## Play Again puts back exactly what was there, so the next match starts with the
## mouse captured again without this file knowing that it was. The root [Control]
## is [constant Control.MOUSE_FILTER_STOP] across the whole viewport, which is
## what stops a click on a button also reaching [HumanIntentSource] and
## re-capturing the mouse out from under the screen.

## Emitted when the screen appears, carrying who won.
signal result_shown(winner: MatchParticipant)

## Emitted when the screen goes away, by either button or by a fresh match.
signal result_dismissed()

## Emitted immediately before the match is restarted.
signal play_again_requested()

## Emitted immediately before the main menu is asked for.
signal main_menu_requested()

## The match to report on. Without one the screen can say nothing and stays down.
@export var controller: MatchController

## The scene's pause menu, when it has one.
##
## Optional, and used for exactly one thing: leaving for the main menu is a
## teardown with an order that matters -- save the settings, unpause, release the
## mouse, and only then change scene -- and [method PauseMenu.return_to_main_menu]
## already is that order. Pointing at it means there is one teardown rather than
## two that can drift. With this unset the screen falls back on
## [member main_menu_scene_path] and does the same work itself.
@export var pause_menu: PauseMenu

## Where Main Menu goes when [member pause_menu] is unset. A path rather than a
## [PackedScene] for the same reason [MainMenu] and [PauseMenu] use one: the menu
## names the match and the match carries this node, so a [PackedScene] here would
## close the resource graph into a cycle.
@export_file("*.tscn") var main_menu_scene_path: String = "res://scenes/ui/main_menu.tscn"

## How long the beat holds and how it fades. Shared with [MatchHud], which uses
## the same resource for the handover banner, because the two are one pacing
## decision. Unset falls back on the defaults written in
## [MatchAnnouncementProfile] itself.
@export var announcements: MatchAnnouncementProfile

@onready var _root: Control = %Root
@onready var _verdict_label: Label = %Verdict
@onready var _headline_label: Label = %Headline
@onready var _detail_label: Label = %Detail
@onready var _play_again_button: Button = %PlayAgainButton
@onready var _main_menu_button: Button = %MainMenuButton
@onready var _beat: Control = %Beat
@onready var _beat_verdict_label: Label = %BeatVerdict
@onready var _beat_headline_label: Label = %BeatHeadline
@onready var _beat_hint_label: Label = %BeatHint

var _is_showing: bool = false

## Seconds of beat left to run. Zero means no beat is on screen, and is the one
## flag every other method here tests.
var _beat_remaining: float = 0.0

## What [member _beat_remaining] started at, so the fade keeps its shape.
var _beat_total: float = 0.0

## Seconds the beat has been up, which is what the skip lockout is measured
## against. Counted separately from the remainder so that editing the profile
## mid-beat cannot make a beat retroactively skippable.
var _beat_elapsed: float = 0.0

## Used when [member announcements] is unset, built once and kept.
var _fallback_announcements: MatchAnnouncementProfile = null

## Mouse mode in force before the screen appeared, restored by Play Again.
var _mouse_mode_before_show: Input.MouseMode = Input.MOUSE_MODE_CAPTURED


func _ready() -> void:
	# A won match is a frozen match, not a paused one -- but PauseMenu can still
	# be opened over this screen, and a screen whose buttons are dead behind a
	# menu the player just closed is indistinguishable from a hung game.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_play_again_button.pressed.connect(play_again)
	_main_menu_button.pressed.connect(return_to_main_menu)
	_apply_visibility(false)
	_cancel_beat()

	if controller == null:
		push_error("MatchResultScreen has no MatchController; a finished match will say nothing.")
		return
	# Two signals, both of them things that happen once and must not be missed
	# between frames. Everything the screen SAYS is polled in show_result().
	controller.match_won.connect(_on_match_won)
	controller.match_started.connect(_on_match_started)

	if pause_menu != null:
		# PauseMenu restores the mouse mode the match was using -- captured --
		# when it closes, which is right for a match and wrong on top of this.
		pause_menu.closed.connect(_on_pause_menu_closed)

	# A screen added to a match that is ALREADY over -- a scene reload, a test
	# that drives the controller before wiring this up -- still shows itself.
	if controller.is_match_over():
		show_result()


## True while the screen is up.
func is_showing() -> bool:
	return _is_showing


## Read the finished match and put it on screen.
##
## Public and idempotent: a caller that wants the screen without waiting for the
## signal may ask for it, and a second call simply refreshes the text.
func show_result() -> void:
	if controller == null:
		return
	# A caller who wants the dialog now gets the dialog now. The beat exists to
	# delay this method, never to outlive it.
	_cancel_beat()
	refresh()
	if not _is_showing:
		_is_showing = true
		_release_mouse()
		_apply_visibility(true)
		result_shown.emit(controller.get_match_winner())
	_play_again_button.grab_focus()


## Take the screen down without touching the match or the mouse.
func hide_result() -> void:
	# Unconditional, and above the guard: the R key can restart a match while
	# the beat is still running, at which point the screen is not showing and
	# there is still a banner to take down.
	_cancel_beat()
	if not _is_showing:
		return
	_is_showing = false
	_apply_visibility(false)
	result_dismissed.emit()


## Rebuild every line from the controller. Safe to call at any time.
func refresh() -> void:
	if controller == null:
		return
	var winner: MatchParticipant = controller.get_match_winner()
	var human: MatchParticipant = _human_participant()
	_verdict_label.text = _verdict_text(winner, human)
	_headline_label.text = _headline_text(winner, human)
	_detail_label.text = _detail_text(winner)


# --- The two ways out ---------------------------------------------------------

## Start a fresh match in the same scene.
##
## [method MatchController.restart] rather than a scene reload, deliberately. The
## controller's restart is the same call an all-racers-out fall already makes and
## the same one the [code]R[/code] key makes, so Play Again exercises a path the
## game exercises anyway rather than a second one written for this button. It
## puts the turn counts, the rounds won, the winner, the outcome, the round
## number and the removal counts back to zero, brings every parked and ghosted
## body back as a living prisoner with its authored collision, takes the rifle
## out of the winner's hands and arms the opening race again. A scene reload
## would do all that too -- by throwing away the arena, the audio system, the
## settings this match booted with and the player's body, and rebuilding them,
## which is a great deal of work to reach a state one call already reaches. The
## screen is not hidden here: it comes down on [signal MatchController.match_started],
## so the one thing that dismisses it is a match actually having begun.
func play_again() -> void:
	if controller == null:
		push_error("MatchResultScreen has no MatchController; there is no match to restart.")
		return
	play_again_requested.emit()
	# Restored before the match is armed, so the new match's first frame has the
	# mouse it expects rather than a cursor sitting over the crosshair.
	_restore_mouse()
	controller.restart()
	# Belt and braces: restart() emits match_started, which takes the screen
	# down. If a controller ever stops emitting it, a stuck result screen over a
	# live match is the worst failure available here.
	hide_result()


## Leave the match for the main menu.
func return_to_main_menu() -> void:
	main_menu_requested.emit()
	hide_result()
	if pause_menu != null:
		# One teardown, in one place. It saves the settings, unpauses, releases
		# the mouse and only then changes scene.
		pause_menu.return_to_main_menu()
		return

	if main_menu_scene_path.is_empty():
		push_error("MatchResultScreen has no pause menu and no main_menu_scene_path; staying in the match.")
		return
	var tree: SceneTree = get_tree()
	tree.paused = false
	_release_mouse()
	var error: Error = tree.change_scene_to_file(main_menu_scene_path)
	if error != OK:
		push_error("MatchResultScreen could not load %s: %s" % [main_menu_scene_path, error_string(error)])


# --- What it says -------------------------------------------------------------

## The one word at the top, from the human's point of view when there is a human.
func _verdict_text(winner: MatchParticipant, human: MatchParticipant) -> String:
	if winner == null:
		return "MATCH OVER"
	if human == null:
		# An AI-only match -- a headless sweep, or a player who has left. There
		# is nobody for a verdict to be about, so it reports rather than judges.
		return "MATCH OVER"
	return "VICTORY" if winner == human else "DEFEAT"


## Who won, in what role, in one sentence -- and what the player was doing.
func _headline_text(winner: MatchParticipant, human: MatchParticipant) -> String:
	if winner == null:
		return "The match ended without a winner."

	var lines: PackedStringArray = PackedStringArray()
	if human != null and winner == human:
		lines.append("You held the tower and cleared the ring.")
	else:
		lines.append("%s held the tower and cleared the ring." % winner.display_name)
		if human != null:
			lines.append(_player_role_line(human))
	return "\n".join(lines)


## What the player themself was, in the words of the role they actually ended in.
##
## Read off the participant's own role flags -- the same three
## [method MatchParticipant.get_role_name] reads -- rather than assumed from the
## fact that somebody else won. See the class note on why the survivor branch is
## written here and is unreachable under the shipped rules.
func _player_role_line(human: MatchParticipant) -> String:
	if human.is_shooter:
		return "You were in the tower when it fell."
	if human.is_running:
		return "You were a prisoner and you survived."
	if human.is_ghost:
		return "You were a prisoner. The rifle took you and you finished as a ghost."
	return "You were a prisoner and the tower cleared you."


## The match's own numbers, all of them read back off the controller.
func _detail_text(winner: MatchParticipant) -> String:
	var lines: PackedStringArray = PackedStringArray()
	if winner != null:
		lines.append("Tower: %s, turn %d, %d round(s) held" % [
			winner.display_name, winner.turns_in_tower, winner.rounds_won,
		])
	lines.append("Rounds played: %d" % controller.get_round_number())
	lines.append("Prisoners cleared: %d of %d" % [
		controller.get_runners_removed(), controller.get_runners_total(),
	])
	if controller.get_rules().has_ghosts():
		lines.append("Ghost swaps: %d" % controller.get_catch_count())
	return "\n".join(lines)


## The human in the match, or null in an AI-only one.
func _human_participant() -> MatchParticipant:
	for participant: MatchParticipant in controller.get_participants():
		if participant.is_human():
			return participant
	return null


# --- The beat -----------------------------------------------------------------

## The public way to end a match on screen: hold the beat, then show the dialog.
##
## [method show_result] remains the way to skip straight to the dialog, and every
## existing caller of it -- a test, a screen wired to an already-finished match,
## the skip -- still gets exactly that.
func begin_result() -> void:
	if controller == null:
		return
	var seconds: float = _beat_seconds()
	if seconds <= 0.0:
		show_result()
		return
	_start_beat(seconds)


## True while the beat is on screen. The dialog is not up yet and
## [method is_showing] is still false.
func is_beating() -> bool:
	return _beat_remaining > 0.0


## End the beat early and show the dialog now. What the skip calls, and safe to
## call when no beat is running.
func skip_beat() -> void:
	if not is_beating():
		return
	show_result()


## How long the beat should run for, or 0.0 for no beat at all.
##
## Headless is 0.0 unconditionally and that is the load-bearing line in this
## file: the bot harness and the test suite must reach the dialog on the frame
## the match is won, with no timer to advance and nothing to wait for.
func _beat_seconds() -> float:
	if GameSettings.is_headless():
		return 0.0
	return _announcements().get_win_beat_seconds()


func _start_beat(seconds: float) -> void:
	if _beat == null:
		show_result()
		return
	var winner: MatchParticipant = controller.get_match_winner()
	var human: MatchParticipant = _human_participant()
	# The same two sentences the dialog will use, from the same two methods. The
	# beat is the result arriving early, not a second opinion about it.
	if _beat_verdict_label != null:
		_beat_verdict_label.text = _verdict_text(winner, human)
	if _beat_headline_label != null:
		_beat_headline_label.text = _headline_text(winner, human)
	if _beat_hint_label != null:
		# Offered only once the beat can actually be skipped, so the prompt is
		# never a lie.
		_beat_hint_label.visible = _skip_lockout_seconds() <= 0.0

	_beat_total = seconds
	_beat_remaining = seconds
	_beat_elapsed = 0.0
	_beat.modulate.a = 1.0
	_beat.visible = true
	set_process(true)
	# Input is only listened for while there is a beat to skip, so this node
	# costs a live match nothing at all.
	set_process_input(true)


func _process(delta: float) -> void:
	if not is_beating():
		set_process(false)
		return
	_beat_elapsed += delta
	_beat_remaining -= delta
	if _beat_hint_label != null and not _beat_hint_label.visible \
			and _beat_elapsed >= _skip_lockout_seconds():
		_beat_hint_label.visible = true
	if _beat_remaining <= 0.0:
		show_result()
		return
	if _beat == null:
		return
	var fade: float = MatchAnnouncementProfile.fade_within(
		_announcements().win_beat_fade_seconds, _beat_total
	)
	if fade > 0.0 and _beat_remaining < fade:
		_beat.modulate.a = clampf(_beat_remaining / fade, 0.0, 1.0)


## Any key, any click, any pad button.
##
## [method Node._input] rather than [method Node._unhandled_input], and rather
## than an action: the beat has to answer a key nobody bound, and the dialog it
## is standing in front of is reached by every other input path there is. The
## event is marked handled so the press that skipped the beat does not also press
## Play Again, open the pause menu, or re-capture the mouse on its way past.
func _input(event: InputEvent) -> void:
	if not is_beating():
		return
	if _beat_elapsed < _skip_lockout_seconds():
		return
	if not _is_skip(event):
		return
	get_viewport().set_input_as_handled()
	skip_beat()


func _is_skip(event: InputEvent) -> bool:
	var key: InputEventKey = event as InputEventKey
	if key != null:
		return key.pressed and not key.echo
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button != null:
		return button.pressed
	var pad: InputEventJoypadButton = event as InputEventJoypadButton
	if pad != null:
		return pad.pressed
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	if touch != null:
		return touch.pressed
	return false


func _skip_lockout_seconds() -> float:
	return maxf(_announcements().win_beat_skip_lockout_seconds, 0.0)


## Take the beat down at once. Safe at any time and safe twice.
func _cancel_beat() -> void:
	_beat_remaining = 0.0
	_beat_total = 0.0
	_beat_elapsed = 0.0
	set_process(false)
	set_process_input(false)
	if _beat != null:
		_beat.modulate.a = 1.0
		_beat.visible = false


## The tuning, whether or not the scene supplied any.
func _announcements() -> MatchAnnouncementProfile:
	if announcements != null:
		return announcements
	if _fallback_announcements == null:
		_fallback_announcements = MatchAnnouncementProfile.new()
	return _fallback_announcements


# --- Wiring -------------------------------------------------------------------

func _on_match_won(_participant: MatchParticipant) -> void:
	begin_result()


## A match has begun, so the last one's result is stale. This is the only thing
## that dismisses the screen, which is what makes the R key, an all-racers-out
## restart and the Play Again button all leave it in the same state.
func _on_match_started(_participant_count: int) -> void:
	hide_result()


## PauseMenu puts back the mouse mode the MATCH was using when it closes, which
## is normally captured. Correct for a match, wrong over a result screen.
func _on_pause_menu_closed() -> void:
	if not _is_showing or GameSettings.is_headless():
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Remember the mouse the match was using and put a cursor on screen.
##
## A no-op with no display server. The bot harness and the test suite run
## headless, there is no mouse there to release, and a suite that left
## [member Input.mouse_mode] written leaks that state into every test after it.
func _release_mouse() -> void:
	if GameSettings.is_headless():
		return
	_mouse_mode_before_show = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Put back exactly the mouse mode the match was using before the screen appeared.
func _restore_mouse() -> void:
	if GameSettings.is_headless():
		return
	Input.mouse_mode = _mouse_mode_before_show


func _apply_visibility(visible_now: bool) -> void:
	if _root != null:
		_root.visible = visible_now
