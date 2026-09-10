extends TestCase

## RUNNER COLOURS: telling four grey humanoids apart.
##
## Ryan's own instruction: [i]"just make every runner a different color, and
## while theyre a ghost, make the[m] slightly translus[c]ent to tell the
## difference."[/i] Colour itself cannot be judged headless -- that is Ryan's
## call on a real screen -- so what runs here is everything that CAN be
## measured without eyes: that two participants never share a colour, that a
## participant's colour holds still for the whole match, that a ghost's colour
## is its own runner colour with alpha taken off rather than a different hue,
## and that the alpha does nothing to the layer that keeps a ghost unshootable.

## Ticks to let a freshly armed round settle before it is measured. Matches
## [code]tests/test_ghosts.gd[/code]'s own budget for the same wait.
const SETTLE_TICKS: int = 60

var _match: Node3D
var _controller: MatchController
var _rules: MatchRules
var _participants: Array[MatchParticipant] = []
var _human: MatchParticipant


func before_each() -> void:
	_match = TestFixtures.make_match()
	_controller = _match.get_node("MatchController") as MatchController
	_rules = TestFixtures.match_rules()
	_controller.rules = _rules
	add_child(_match)

	_participants = _controller.get_participants()
	_human = _participants[0]

	# Same seam test_ghosts.gd arms a known round through: hand the human the
	# tower so there is a seat holder to test the guard colour against.
	_human.tracker.lap_finished.emit(30.0, 240.0)
	await step_ticks(SETTLE_TICKS)


# --- Distinct, stable colours ---------------------------------------------------

## Every participant reads a different colour, and it does not drift.
##
## "Different" is checked pairwise across the whole roster rather than against
## one fixed list, because the roster size is a rule ([member
## MatchRules.prisoner_count]), not a constant this test should know. "Stable"
## is checked by reading the same participant's colour twice, a race apart --
## a colour that changed between two reads would make "who is who" a guess
## about which tick you looked.
func test_every_participant_gets_a_distinct_stable_colour() -> void:
	var before: Array[Color] = []
	for participant: MatchParticipant in _participants:
		before.append(_controller.get_body_color(participant))

	for i: int in before.size():
		for j: int in range(i + 1, before.size()):
			assert_false(
				before[i].is_equal_approx(before[j]),
				"%s and %s do not share a colour"
				% [_participants[i].display_name, _participants[j].display_name],
			)

	# Run the ring a while -- laps, a possible seat change -- and read again.
	await step_ticks(SETTLE_TICKS)
	for index: int in _participants.size():
		var participant: MatchParticipant = _participants[index]
		# The seat holder is excluded: RunnerPalette.guard_color is DELIBERATELY
		# not this participant's own colour while they hold the tower -- see
		# test_the_guard_wears_a_colour_no_runner_is_dealt below. Everyone else
		# must still read exactly as they did.
		if participant.is_shooter:
			continue
		assert_true(
			_controller.get_body_color(participant).is_equal_approx(before[index]),
			"%s's colour held steady across the round" % participant.display_name,
		)


# --- A ghost keeps its own hue ---------------------------------------------------

## A shot prisoner becomes a ghost wearing ITS OWN colour, translucent -- not a
## second, shared ghost hue.
##
## Checked three ways: the RGB channels survive the swap to
## [method MatchController._ghost_material_for] untouched, the alpha comes down
## to [member RunnerPalette.ghost_alpha] specifically rather than to some other
## fraction, and a live ghost still cannot be hit -- translucency is visual
## only, and this is the seam that would notice if painting it had touched the
## collision layer [constant MatchController.GHOST_HAZARD_LAYER] guards.
func test_a_ghost_wears_its_own_colour_translucent() -> void:
	var victim: MatchParticipant = _controller.get_live_participants()[0]
	var living_color: Color = _controller.get_body_color(victim)
	assert_almost_eq(living_color.a, 1.0, 1e-6, "a living prisoner is painted fully opaque")

	assert_true(_controller.apply_hit(victim), "one hit finishes a prisoner at prisoner_lives 1")
	assert_true(victim.is_ghost, "the victim is now a ghost")

	var ghost_color: Color = _controller.get_body_color(victim)
	var palette: RunnerPalette = _controller.get_runner_palette()
	assert_almost_eq(ghost_color.r, living_color.r, 1e-6, "the ghost's red channel is unchanged")
	assert_almost_eq(ghost_color.g, living_color.g, 1e-6, "the ghost's green channel is unchanged")
	assert_almost_eq(ghost_color.b, living_color.b, 1e-6, "the ghost's blue channel is unchanged")
	assert_almost_eq(
		ghost_color.a, palette.ghost_alpha, 1e-6,
		"the ghost's alpha is exactly RunnerPalette.ghost_alpha",
	)
	assert_lt(ghost_color.a, 1.0, "a ghost is less than fully opaque -- \"slightly\" translucent")
	assert_gt(ghost_color.a, 0.0, "and still clearly visible, not a faint wisp")

	# Translucency is visual only: the ghost still cannot be shot. Wait out the
	# full respawn hold -- GhostProfile.respawn_delay_seconds, three seconds on
	# the shipped profile -- and the two-frame settle after it, exactly as
	# tests/test_ghosts.gd does, so this checks the WOKEN hazard layer rather
	# than the trivially-empty layer 0 a held body sits on.
	var hold: float = maxf(_rules.ghost_profile.respawn_delay_seconds, 0.0)
	await step_seconds(hold + 0.2)
	for _tick: int in SETTLE_TICKS:
		await step_ticks(1)
		if victim.body.is_physics_processing():
			break
	assert_true(victim.body.is_physics_processing(), "the ghost's placement woke within the budget")

	var mask: int = _hit_mask()
	assert_gt(float(mask), 0.0, "the weapon profile has a hit mask to test against")
	assert_eq_int(
		victim.body.collision_layer, MatchController.GHOST_HAZARD_LAYER,
		"once woken, the translucent ghost stands on the hazard layer",
	)
	assert_eq_int(
		victim.body.collision_layer & mask, 0,
		"a translucent ghost is still outside the rifle's hit mask",
	)
	assert_false(_controller.apply_hit(victim), "and the match still refuses to shoot it")

	# A round restart brings a ghost back as a living prisoner -- see
	# tests/test_ghosts.gd's own test of that -- which is the cheapest way to
	# force the translucency back off without hand-placing a chase. Whoever
	# scores the arrival cannot be the victim: a ghost's tracker is stopped and
	# cannot arrive.
	var scorer: MatchParticipant = _controller.get_live_participants()[0]
	scorer.tracker.lap_finished.emit(12.0, 96.0)
	await step_ticks(SETTLE_TICKS)

	var restored: Color = _controller.get_body_color(victim)
	assert_almost_eq(restored.a, 1.0, 1e-6, "back in the round, the participant is opaque again")
	assert_almost_eq(restored.r, living_color.r, 1e-6, "and it is still their own colour")


# --- The guard is distinct --------------------------------------------------------

## The tower seat wears a colour dealt to no runner, and gives it back the
## instant the seat changes hands.
func test_the_guard_wears_a_colour_no_runner_is_dealt() -> void:
	var seat: MatchParticipant = _controller.get_seat_participant()
	assert_not_null(seat, "a round is armed with a seat holder")

	var palette: RunnerPalette = _controller.get_runner_palette()
	var guard_color: Color = _controller.get_body_color(seat)
	assert_true(
		guard_color.is_equal_approx(palette.guard_color),
		"the seat holder is painted RunnerPalette.guard_color",
	)
	for entry: Color in palette.runner_colors:
		assert_false(
			guard_color.is_equal_approx(entry),
			"the guard colour is not one of the runner colours",
		)

	# Force the seat to change hands and check the outgoing shooter gets their
	# own colour back rather than staying grey.
	var own_color: Color = palette.color_for_index(seat.index)
	var scorer: MatchParticipant = _controller.get_live_participants()[0]
	scorer.tracker.lap_finished.emit(12.0, 96.0)
	await step_ticks(SETTLE_TICKS)

	assert_true(
		_controller.get_body_color(seat).is_equal_approx(own_color),
		"the former guard is repainted their own runner colour once they are back on the ring",
	)
	assert_true(
		_controller.get_body_color(scorer).is_equal_approx(palette.guard_color),
		"the new seat holder wears the guard colour",
	)


# --- The palette resource itself --------------------------------------------------

## The shipped palette's own invariant: the guard's colour is never one a
## runner could also be dealt. A data-level check, independent of a live
## match, so the guarantee holds even if nobody ever ghosts anybody.
func test_the_shipped_palette_never_deals_the_guard_colour_to_a_runner() -> void:
	var palette: RunnerPalette = load(
		"res://resources/rules/default_runner_palette.tres"
	) as RunnerPalette
	assert_not_null(palette, "the shipped palette loads")
	assert_gt(float(palette.runner_colors.size()), 0.0, "the shipped palette has runner colours")
	for entry: Color in palette.runner_colors:
		assert_false(
			entry.is_equal_approx(palette.guard_color),
			"no runner colour matches the guard colour",
		)


# --- Helpers ------------------------------------------------------------------

## The hit mask the match's own rifle shoots on, read off the live weapon
## rather than restated. Mirrors [code]tests/test_ghosts.gd[/code]'s own helper.
func _hit_mask() -> int:
	var rifle: Rifle = _match.get_node_or_null("Player/Head/Rifle") as Rifle
	if rifle == null or rifle.profile == null:
		return 0
	return rifle.profile.hit_mask
