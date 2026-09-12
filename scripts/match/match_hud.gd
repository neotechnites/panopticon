class_name MatchHud
extends Control

## The whole of the match's UI: a four line readout, a centre line, a banner and
## a crosshair. No art, and deliberately little of it.
##
## [b]The game is asymmetric, so the readout is[/b]
##
## PANOPTICON is not one game with two camera positions. A guard is holding a
## tower with a bolt-action rifle against small distant targets at 35-60 m; a
## prisoner is running a ring for their life; a ghost is chasing one. Those are
## three different jobs and they do not share a single interesting number
## between them, so a HUD that showed one union of everything would be showing
## every player mostly somebody else's game.
##
## What each role gets, and why:
##
## [codeblock]
## TOWER      RELOAD 1.8 / READY   the silence after a shot, counted down
##            TURN n               how short that silence has become
##            PRISONERS n / m      the win condition, as a number going down
##            round progress       how close the match is to being over
##
## PRISONER   n M TO THE END       how much ring is left
##            PRISONERS n / m      how many of you are still alive
##            who holds the tower, on what turn, on what length of reload
##
## GHOST      CATCH A PRISONER     the job, which has just CHANGED
##            what a ghost is      faster, unshootable, takes their place
## [/codeblock]
##
## [b]What is deliberately NOT here[/b]
##
## - [b]The live reload countdown, for anyone but the guard.[/b] The runners are
##   told how LONG the tower's silence lasts -- a property of the tower, and the
##   thing the turn count is about -- but not how much of it is left. A prisoner
##   who could watch that number would run by reading the HUD instead of by
##   watching the tower, and this game is about looking at the world.
## - [b]The leading prisoner's distance, for the guard.[/b] Same reason, pointing
##   the other way: finding the runner who is nearly home is what the scope is
##   for.
## - [b]The roster.[/b] This readout used to print every participant's role and
##   turn count every frame. That is a debug dump: it is four lines of other
##   people's state to answer a question -- who am I running from, and how
##   dangerous are they -- that one line answers.
## - [b]A round timer.[/b] [member MatchRules.round_time_limit_seconds] is
##   declared and unimplemented. A clock counting down to nothing would be the
##   readout inventing a rule.
## - [b]The respawn countdown.[/b] [MatchDeathScreen] already owns it, in the
##   middle of the screen, at 64 px. Two countdowns for one wait is one too many.
##
## [b]It follows the rules in play[/b]
##
## What counts as progress depends on the rules the match is running, and those
## are swept. Every sentence here is derived from the live [MatchRules] through
## [MatchReadoutProfile] -- the runners' objective changes under
## [constant MatchRules.RunnerWinCondition.ALL_ARRIVALS], the match progress
## changes with [member MatchRules.rounds_to_win_match], and a shooter win
## condition that is declared but unimplemented is SAID to be unwinnable rather
## than described as the one that is. A HUD that quietly assumed the defaults
## would be lying to a player in exactly the matches the harness exists to run.
##
## [b]Reads state rather than mirroring it[/b]
##
## Everything countable is polled from [MatchController], [Rifle] and the
## human's own [MatchLapTracker] each frame. Nothing is cached, nothing is
## incremented here, and no count in this file can drift from the match's. Only
## the events that happen once and must not be missed between frames -- a
## resolution, a seat change, a match win -- are taken from signals, and all
## three only write a string.
##
## [b]A bot pays nothing[/b]
##
## The readout is shown only when the match has a HUMAN participant with a role,
## which is the whole of its inertness rule and is why it is stated as one
## condition rather than scattered. A bot-only match -- every headless sweep --
## hides it and runs the identical path; a bot holding the tower is simply a
## seat the human does not have, and puts the human on the prisoner readout
## rather than producing a guard readout for a body they are not in. Nothing
## here reaches for a camera, a body or an input device.
##
## [b]The handover banner[/b]
##
## One thing here is louder than a line of text, and deliberately. The tower
## changing hands is the central event of the whole design and it used to happen
## in silence: a prisoner reached the end, took the seat, and the match simply
## continued underneath everybody. [signal MatchController.seat_changed] now
## raises a banner that names who took it and holds for
## [member MatchAnnouncementProfile.handover_seconds] before fading.
##
## It is a READOUT, not a rule. It is raised from the signal the controller
## already emits, it is timed off [member Control.modulate] and a float, it
## touches nothing about the match, and switching it off in the profile leaves
## the match exactly as it was.
##
## [b]The banner is silent on purpose.[/b] There is already a cue for this event
## -- [constant AudioEvents.SEAT_CHANGED], posted by [MatchAudioListener] off the
## same [signal MatchController.seat_changed] this banner listens to, and mapped
## to a stream in [code]scenes/audio/placeholder_bank.tres[/code]. The sound and
## the banner therefore land on the same frame with no wiring between them.
## Posting the event a second time from here would double-trigger the cue, which
## is audible.
##
## [b]Legibility, in a room lit by one red lamp[/b]
##
## The arena is dark and its only light is red, so the readout is not judged
## against a grey test scene. Three things answer it and none of them is in this
## script: a dark translucent backdrop authored behind the block, a heavy black
## outline on every label, and a palette on [MatchReadoutProfile] in which
## nothing important is red. This script only chooses WHICH colour off that
## resource a line is wearing.

## What a player is doing right now, as far as the readout is concerned.
##
## Not [enum MatchParticipant]'s business and not a rule: it is the four
## different readouts this HUD knows how to draw, named. [MatchParticipant]
## already carries the three flags it is derived from.
enum Role {
	## No human in this match, or no readout for them yet. Draws nothing.
	NONE,
	## Holding the tower.
	GUARD,
	## A living prisoner on the ring, in a round or in the opening race.
	PRISONER,
	## Shot, and chasing.
	GHOST,
	## Out, with nothing to play. [MatchDeathScreen] says why.
	SPECTATOR,
}

## The match to report on.
@export var controller: MatchController

## The weapon whose readiness is shown. It changes hands, but it is one object
## for the life of the match, so this reference stays correct across seat
## changes.
@export var rifle: Rifle

## The role readout's root: everything in the top-left corner, backdrop
## included. Hidden whenever [method get_role] is [constant Role.NONE], which is
## every bot-only match. Structure is authored in the scene; this script writes
## four strings and four colours. Leave unset and the readout never appears.
@export var readout_panel: Control

## Line one: what the player IS, and -- in the tower -- which turn this is.
@export var role_label: Label

## Line two, the big one: the single number that role lives on. The reload for
## the guard, the metres left for a prisoner, the orders for a ghost.
@export var primary_label: Label

## Line three: the living prisoner count, and the objective the rules in play
## actually set.
@export var objective_label: Label

## Line four, dim: who holds the tower and on what reload, or -- for the guard --
## how close the match is to being over.
@export var context_label: Label

## The restart key, bottom-left and dim. Off with
## [member MatchReadoutProfile.show_restart_hint].
@export var hint_label: Label

## Centre readout: the round's result and, at the end, the match winner.
@export var outcome_label: Label

## The handover banner's root, shown when the tower changes hands and hidden the
## rest of the time. Structure is authored in the scene; this script only makes
## it visible, writes two labels and fades it. Leave unset and the banner simply
## never appears.
@export var handover_panel: Control

## The banner's headline: who took the tower.
@export var handover_title: Label

## The banner's second line: which turn in the tower this is for them.
@export var handover_detail: Label

## How long the banner holds, and how it fades. Unset falls back on the defaults
## written in [MatchAnnouncementProfile] itself.
@export var announcements: MatchAnnouncementProfile

## Every word and colour the role readout is made of. Unset falls back on the
## defaults written in [MatchReadoutProfile] itself, so a scene that has not been
## wired up is under-tuned rather than blank.
@export var readout: MatchReadoutProfile


## Seconds of banner left to run. Zero means nothing is on screen.
var _handover_remaining: float = 0.0

## What [member _handover_remaining] started at, so the fade knows its own
## shape after the profile has been edited mid-match.
var _handover_total: float = 0.0

## Used when [member announcements] is unset, built once and kept.
var _fallback_announcements: MatchAnnouncementProfile = null

## Used when [member readout] is unset, built once and kept.
var _fallback_readout: MatchReadoutProfile = null


func _ready() -> void:
	if outcome_label != null:
		outcome_label.text = ""
		outcome_label.visible = false
	_hide_handover()
	if readout_panel != null:
		readout_panel.visible = false
	if controller == null:
		push_error("MatchHud has no MatchController; the match will be unreadable.")
		set_process(false)
		return
	controller.round_resolved.connect(_on_round_resolved)
	controller.race_started.connect(_on_race_started)
	controller.seat_changed.connect(_on_seat_changed)
	controller.match_won.connect(_on_match_won)


func _process(delta: float) -> void:
	_tick_handover(delta)
	tick()


## Refresh the role readout from the match. Public so a test or a harness may
## step it without waiting on a frame, exactly as [MatchDeathScreen] is stepped.
func tick() -> void:
	if controller == null or readout_panel == null:
		return
	var role: Role = get_role()
	if role == Role.NONE:
		readout_panel.visible = false
		_write_hint(false)
		return

	readout_panel.visible = true
	_write_hint(true)

	var tuning: MatchReadoutProfile = _readout()
	_write(role_label, _role_text(role), tuning.neutral_color)
	_write(primary_label, _primary_text(role), _primary_color(role))
	_write(objective_label, _objective_text(role), tuning.neutral_color)
	_write(context_label, _context_text(role), tuning.dim_color)


# --- What the player is -------------------------------------------------------

## Which readout the human in this match should be looking at.
##
## [constant Role.NONE] is the inert case and covers all of them at once: no
## controller, no readout tuning, the tuning switched off, and -- the one that
## matters for a sweep -- a match with no human participant in it at all. A bot
## holding the tower is NOT this case: it is a seat the human does not have, and
## the human is on the ring.
func get_role() -> Role:
	if controller == null or not _readout().enabled:
		return Role.NONE
	var human: MatchParticipant = controller.get_human_participant()
	if human == null:
		return Role.NONE
	if human.is_shooter:
		return Role.GUARD
	# Checked before is_running deliberately: the two are mutually exclusive on
	# a participant, and a ghost is made -- flags and all -- on the tick they
	# are shot, before the respawn hold has even begun. The orders change at the
	# moment the job does.
	if human.is_ghost:
		return Role.GHOST
	if human.is_running:
		return Role.PRISONER
	return Role.SPECTATOR


## True while the role readout is on screen. The seam a test asserts against.
func is_readout_showing() -> bool:
	return readout_panel != null and readout_panel.visible


func get_role_text() -> String:
	return role_label.text if role_label != null else ""


func get_primary_text() -> String:
	return primary_label.text if primary_label != null else ""


func get_objective_text() -> String:
	return objective_label.text if objective_label != null else ""


func get_context_text() -> String:
	return context_label.text if context_label != null else ""


# --- The four lines -----------------------------------------------------------

## Line one. The guard's carries their turn count, because the reload shortens
## with every turn and the turn number is therefore the tower's difficulty.
func _role_text(role: Role) -> String:
	var tuning: MatchReadoutProfile = _readout()
	match role:
		Role.GUARD:
			var human: MatchParticipant = controller.get_human_participant()
			var turns: int = human.turns_in_tower if human != null else 0
			return "%s%s%s %d" % [tuning.guard_role, tuning.separator, tuning.turn_word, turns]
		Role.PRISONER:
			return tuning.prisoner_role
		Role.GHOST:
			return tuning.ghost_role
		_:
			return tuning.spectator_role


## Line two: the one number the role lives on.
func _primary_text(role: Role) -> String:
	var tuning: MatchReadoutProfile = _readout()
	match role:
		Role.GUARD:
			return _reload_text()
		Role.PRISONER:
			return _distance_text()
		Role.GHOST:
			return tuning.ghost_orders
		_:
			return tuning.no_distance_text


func _primary_color(role: Role) -> Color:
	var tuning: MatchReadoutProfile = _readout()
	match role:
		Role.GUARD:
			var armed: bool = rifle != null and rifle.can_fire()
			return tuning.ready_color if armed else tuning.reloading_color
		Role.GHOST:
			return tuning.ghost_color
		Role.PRISONER:
			return tuning.prisoner_color
		_:
			return tuning.dim_color


## READY, or the honest time to the next shot -- which counts the firing window
## as well as the reload, because that is when the trigger will actually answer
## again. Guard only; see the class docs for why the runners do not get it.
func _reload_text() -> String:
	var tuning: MatchReadoutProfile = _readout()
	if rifle == null:
		return tuning.no_distance_text
	if rifle.can_fire():
		return tuning.ready_text
	return "%s %s" % [
		tuning.reload_word,
		String.num(rifle.get_time_to_ready(), tuning.reload_decimals),
	]


## Metres of route left to run, off the human's own [MatchLapTracker].
##
## The tracker measures ARC, which is radius-independent on purpose -- a runner
## who cuts to the inside kerb still has to cover the whole ring -- and it does
## it per level, because the arena is three decks of three different sizes. So
## the number here is every level still owed, each taken at its own lane radius,
## which is the only conversion under which a metre means the same thing on the
## bottom deck and the top one.
##
## It is a readout of the distance being scored, not a second opinion about it.
## The route, the arc and the finish are the tracker's; this only puts them in a
## unit a player can act on, and it counts the whole run down rather than
## restarting at each ramp -- a prisoner needs to know how far the TOWER is, not
## how far this lap is.
func _distance_text() -> String:
	var tuning: MatchReadoutProfile = _readout()
	var human: MatchParticipant = controller.get_human_participant()
	if human == null or human.tracker == null:
		return tuning.no_distance_text
	var tracker: MatchLapTracker = human.tracker
	if tracker.has_finished():
		return tuning.arrived_text
	if tracker.get_route() == null or tracker.get_finish_arc() <= 0.0:
		return tuning.no_distance_text
	return "%d %s" % [int(roundf(tracker.get_metres_remaining())), tuning.distance_suffix]


## Line three: how many prisoners are still alive, and what the rules in play
## say winning is. Both roles get the count; they read it from opposite ends.
func _objective_text(role: Role) -> String:
	var tuning: MatchReadoutProfile = _readout()
	var rules: MatchRules = controller.get_rules()
	var counts: String = tuning.prisoner_count_text(
		controller.get_runners_remaining(), controller.get_runners_total()
	)

	if role == Role.GHOST:
		return tuning.join(PackedStringArray([counts, _ghost_terms()]))

	var objective: String = ""
	if controller.get_phase() == MatchController.Phase.RACE:
		objective = tuning.race_objective
	elif role == Role.GUARD:
		objective = tuning.shooter_objective(rules)
	else:
		objective = tuning.runner_objective(rules)
	return tuning.join(PackedStringArray([counts, objective]))


## What a ghost IS, composed from the live [GhostProfile] rather than restated:
## a swept ghost speed is the speed the readout claims, and a round in which
## ghosts CAN be shot does not get told they cannot.
func _ghost_terms() -> String:
	var tuning: MatchReadoutProfile = _readout()
	var profile: GhostProfile = controller.get_ghost_profile()
	var parts: PackedStringArray = PackedStringArray([tuning.ghost_take_place_text])
	if profile != null:
		parts.append("%.1f%s" % [profile.speed_multiplier, tuning.ghost_speed_suffix])
		if not profile.shootable:
			parts.append(tuning.ghost_unshootable_text)
	return tuning.join(parts)


## Line four, dim. The guard gets match progress -- how close this is to being
## over. Everybody else gets the tower: who is in it, on which turn, and how long
## their silence between shots lasts.
func _context_text(role: Role) -> String:
	var dev_text: String = _dev_text()
	if dev_text != "":
		return dev_text
	var boost_text: String = _speed_boost_text()
	if boost_text != "":
		return boost_text
	if role == Role.PRISONER:
		var ability_text: String = _ability_text()
		if ability_text != "":
			return ability_text
	var tuning: MatchReadoutProfile = _readout()
	var rules: MatchRules = controller.get_rules()
	if role == Role.GUARD:
		var human: MatchParticipant = controller.get_human_participant()
		return tuning.match_progress(rules, human.rounds_won if human != null else 0)

	var seat: MatchParticipant = controller.get_seat_participant()
	if seat == null:
		return tuning.empty_tower_text
	return tuning.join(PackedStringArray([
		"%s %s" % [tuning.guard_role, seat.display_name],
		"%s %d" % [tuning.turn_word, seat.turns_in_tower],
		"%s%s" % [
			String.num(controller.get_current_reload_seconds(), tuning.reload_decimals),
			tuning.reload_length_suffix,
		],
	]))


## Dev toggles on the human's body: T turbo, Y invincible. Empty when off.
func _dev_text() -> String:
	var human: MatchParticipant = controller.get_human_participant()
	if human == null or human.body == null:
		return ""
	var intent: MoveIntent = human.body.get_intent()
	var flags: PackedStringArray = PackedStringArray()
	if intent.godmode:
		flags.append("INVINCIBLE (Y)")
	if intent.turbo_held:
		flags.append("TURBO (T)")
	return " · ".join(flags)


## Line four's override while the human's own body is under a
## [method PlayerController.apply_speed_boost]. Empty when it is not.
func _speed_boost_text() -> String:
	var human: MatchParticipant = controller.get_human_participant()
	if human == null or human.body == null:
		return ""
	var remaining: float = human.body.get_speed_boost_remaining()
	if remaining <= 0.0:
		return ""
	return "SPEED x%d — %.1fs" % [int(human.body.get_speed_boost_multiplier()), remaining]


## Line four for a prisoner carrying a power: its name and where it is in its cycle.
func _ability_text() -> String:
	var human: MatchParticipant = controller.get_human_participant()
	var rules: MatchRules = controller.get_rules()
	if human == null or rules.runner_ability == MatchRules.RunnerAbility.NONE:
		return ""
	var ability: RunnerPower = RunnerPower.of(human.body)
	if ability == null:
		return ""
	var title: String = MatchRules.runner_ability_title(rules.runner_ability).to_upper()
	if ability.is_active():
		return "%s — %.1fs" % [title, ability.get_remaining()]
	if ability.get_cooldown_remaining() > 0.0:
		return "%s — READY IN %.0fs" % [title, ability.get_cooldown_remaining()]
	return "%s — READY" % title


func _write(label: Label, text: String, colour: Color) -> void:
	if label == null:
		return
	label.text = text
	label.modulate = colour


func _write_hint(visible_now: bool) -> void:
	if hint_label == null:
		return
	var tuning: MatchReadoutProfile = _readout()
	hint_label.visible = visible_now and tuning.show_restart_hint
	if hint_label.visible:
		hint_label.text = tuning.restart_hint
		hint_label.modulate = tuning.dim_color


# --- The centre line ----------------------------------------------------------

## The centre label carries the last thing that HAPPENED, and is never cleared.
##
## A seat change fires round_resolved, seat_changed and round_started within one
## tick, so a label cleared on round_started would blank the result on the frame
## it appeared. Each handler simply overwrites, and the order of emission means
## the last word belongs to the most informative event.
func _on_round_resolved(outcome: MatchController.Outcome) -> void:
	if outcome_label == null:
		return
	if outcome == MatchController.Outcome.WIN:
		var seat: MatchParticipant = controller.get_seat_participant()
		# Emitted before the seat can change hands, so this is still the shooter
		# who did it.
		outcome_label.text = "%s HELD THE TOWER" % (seat.display_name if seat != null else "nobody")
	else:
		# Which arrival ended it depends on the rule in play: under ALL_ARRIVALS
		# it took every prisoner still in the round, and "a runner reached the
		# end" would be describing a different game.
		outcome_label.text = _readout().runner_objective(controller.get_rules()).to_upper()


func _on_race_started() -> void:
	if outcome_label != null:
		outcome_label.text = _readout().race_objective
	# A race is the tower being empty, so a banner naming its last holder is
	# stale. This also covers a restart, which starts with a race.
	_hide_handover()


func _on_seat_changed(participant: MatchParticipant, turns_in_tower: int) -> void:
	_show_handover(participant, turns_in_tower)
	if outcome_label != null:
		# "TOWER TAKEN BY" rather than "X takes the tower": the human's name is
		# "You", and the second phrasing reads as broken English for half the
		# participants in every match.
		outcome_label.text = "TOWER TAKEN BY %s (turn %d)" % [
			participant.display_name, turns_in_tower,
		]


func _on_match_won(participant: MatchParticipant) -> void:
	if outcome_label != null:
		outcome_label.text = "MATCH WON BY %s" % participant.display_name
	# The win beat on [MatchResultScreen] takes the screen from here, and two
	# announcements over each other read as one unreadable one.
	_hide_handover()


# --- The handover banner ------------------------------------------------------

## Raise the banner for a seat change and start its clock.
##
## Bot-safe by construction, which is the point of writing it this way: this is
## a Label and a float on the local machine's HUD, so a bot taking the tower runs
## exactly the same line and simply gets named in it. Nothing here reaches for a
## camera, a body or a player.
func _show_handover(participant: MatchParticipant, turns_in_tower: int) -> void:
	# Ryan: the centre-screen text is in the way. Banner off.
	if true or handover_panel == null or participant == null:
		return
	var seconds: float = _announcements().get_handover_seconds()
	if seconds <= 0.0:
		_hide_handover()
		return

	if handover_title != null:
		handover_title.text = _handover_title(participant)
	if handover_detail != null:
		handover_detail.text = "TURN %d" % turns_in_tower

	_handover_total = seconds
	_handover_remaining = seconds
	handover_panel.modulate.a = 1.0
	handover_panel.visible = true


## Who took it, in a sentence that survives the human being called "You".
##
## The naive "%s takes the tower" reads as broken English for the one
## participant in every match whose name is a pronoun, which is why the centre
## label below phrases itself as "TOWER TAKEN BY". A banner is the wrong place
## for that dodge -- it is the loudest thing on screen -- so the human gets the
## sentence that is actually true of them.
func _handover_title(participant: MatchParticipant) -> String:
	if participant.is_human():
		return "YOU TAKE THE TOWER"
	return "%s TAKES THE TOWER" % participant.display_name.to_upper()


## Count the banner down and fade it out. Called every frame, including frames
## on which no banner is up, where it costs one float comparison.
func _tick_handover(delta: float) -> void:
	if _handover_remaining <= 0.0 or handover_panel == null:
		return
	_handover_remaining -= delta
	if _handover_remaining <= 0.0:
		_hide_handover()
		return
	var fade: float = MatchAnnouncementProfile.fade_within(
		_announcements().handover_fade_seconds, _handover_total
	)
	if fade > 0.0 and _handover_remaining < fade:
		handover_panel.modulate.a = clampf(_handover_remaining / fade, 0.0, 1.0)


## Take the banner down at once, with no fade. Safe to call at any time and
## safe to call twice.
func _hide_handover() -> void:
	_handover_remaining = 0.0
	_handover_total = 0.0
	if handover_panel != null:
		handover_panel.modulate.a = 1.0
		handover_panel.visible = false


# --- Tuning -------------------------------------------------------------------

## The announcement tuning, whether or not the scene supplied any.
func _announcements() -> MatchAnnouncementProfile:
	if announcements != null:
		return announcements
	if _fallback_announcements == null:
		_fallback_announcements = MatchAnnouncementProfile.new()
	return _fallback_announcements


## The readout tuning, whether or not the scene supplied any.
func _readout() -> MatchReadoutProfile:
	if readout != null:
		return readout
	if _fallback_readout == null:
		_fallback_readout = MatchReadoutProfile.new()
	return _fallback_readout
