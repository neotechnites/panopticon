extends TestCase

## [MatchController]: the rules of the round, and the one bug that has already
## cost this project a day.
##
## Every test here instances the real [code]scenes/match/match.tscn[/code] --
## arena, tower player, rifle, HUD and all -- rather than wiring a controller up
## by hand. The rules under test are about what happens when a whole round is
## armed, and the spawn-displacement regression at the bottom of this file is
## about what the physics server does on the tick the runners enter the tree.
## Neither survives being tested on a stripped-down stand-in.

## Ticks to let a freshly armed round settle before it is measured. One second
## is far longer than the single tick the old spawn bug needed to fling the
## player across the arena, which is the point: the assertion has to be made
## after the damage would have been done, not during it.
const SETTLE_TICKS: int = 60

## How far the player may be from the tower spawn, horizontally, and still count
## as standing on the tower. The platform is 8 m in radius and the outer wall is
## at 60 m; the bug this bounds put the player at 59 m. Half a metre leaves room
## for the settle onto the platform and nothing else.
const SPAWN_TOLERANCE_METRES: float = 0.5

## The running surface, from [code]scenes/ring/test_ring.tscn[/code]: an annulus
## with the inner kerb at r=36 and the outer wall at r=60.
const DECK_INNER_RADIUS: float = 36.0
const DECK_OUTER_RADIUS: float = 60.0

## Two runners closer together than this are effectively in the same lane. The
## body capsule is 0.8 m across, so anything under a metre is contact.
const MIN_LANE_SEPARATION_METRES: float = 1.0

var _match: Node3D
var _controller: MatchController
var _player: PlayerController
var _tower_spawn: Vector3 = Vector3.ZERO

var _resolutions: int = 0
var _last_outcome: int = -1


func before_each() -> void:
	_match = TestFixtures.make_match()
	# Everything above happens before the instance enters the tree, because
	# MatchController arms the first round from _ready and that first round is
	# itself under test.
	add_child(_match)

	_controller = _match.get_node("MatchController") as MatchController
	_player = _match.get_node("Player") as PlayerController
	_controller.round_resolved.connect(_on_round_resolved)

	var arena: Node3D = _match.get_node("Arena") as Node3D
	_tower_spawn = (arena.get_node(TestFixtures.TOWER_SPAWN_PATH) as Marker3D).global_position

	await step_ticks(SETTLE_TICKS)


# --- Arming -------------------------------------------------------------------

## A round arms with one runner per lane, live, and unresolved.
func test_a_round_starts_with_a_runner_on_every_lane() -> void:
	assert_eq_int(
		_controller.get_runners_remaining(), _controller.get_runners_total(),
		"every lane should have produced a runner",
	)
	assert_false(_controller.is_resolved(), "a fresh round is not resolved")
	assert_eq_int(_controller.get_resolve_count(), 0, "a fresh round has resolved nothing")

	# Each runner is out on the deck and in a lane of its own, rather than piled
	# up at the origin or sharing a radius. The deck is the annulus r=35..60 and
	# the runners do not path around anything, so two of them on the same radius
	# would spend the round shouldering each other.
	var runners: Array[RingRunner] = _controller.get_live_runners()
	var radii: PackedFloat32Array = PackedFloat32Array()
	for index: int in runners.size():
		var radius: float = _radius_of(runners[index].controller.global_position)
		assert_between(radius, DECK_INNER_RADIUS, DECK_OUTER_RADIUS, "runner %d is on the deck" % index)
		radii.append(radius)
	for index: int in radii.size():
		for other: int in range(index + 1, radii.size()):
			assert_gt(
				absf(radii[index] - radii[other]), MIN_LANE_SEPARATION_METRES,
				"runners %d and %d must not share a lane" % [index, other],
			)


# --- The rules ----------------------------------------------------------------

## Removing every runner is the win, and only the last one is.
func test_all_runners_removed_is_a_win() -> void:
	var runners: Array[RingRunner] = _controller.get_live_runners()
	assert_gt(float(runners.size()), 1.0, "the win condition needs more than one runner to be interesting")

	for index: int in runners.size():
		var is_last: bool = index == runners.size() - 1
		assert_true(_controller.remove_runner(runners[index]), "removing a live runner succeeds")
		assert_eq_int(
			_controller.get_runners_remaining(), runners.size() - index - 1,
			"the remaining count drops by one per removal",
		)
		if not is_last:
			assert_false(
				_controller.is_resolved(),
				"the round is still live with %d runners left" % (runners.size() - index - 1),
			)

	assert_eq_int(int(_controller.get_outcome()), int(MatchController.Outcome.WIN), "an empty ring is a win")
	assert_eq_int(_resolutions, 1, "the resolution is announced once")
	assert_eq_string(_controller.get_outcome_name(), "WIN", "the outcome name follows the outcome")


## One runner reaching the end is the loss, whatever the others are doing.
##
## This is the asymmetry the game is built on: the tower has to stop all of
## them, so two out of three is not a partial success, it is a defeat.
func test_one_arrival_is_a_loss() -> void:
	var runners: Array[RingRunner] = _controller.get_live_runners()
	assert_gt(float(runners.size()), 1.0, "the loss condition needs survivors to be interesting")

	# The runner reports that it finished its lap. What that costs is the round's
	# business, which is exactly the seam being tested.
	runners[0].reached_end.emit(12.0, 96.0)

	assert_eq_int(int(_controller.get_outcome()), int(MatchController.Outcome.LOSS), "one arrival is a loss")
	assert_true(_controller.is_resolved(), "a loss resolves the round")
	assert_eq_int(_resolutions, 1, "the resolution is announced once")
	assert_gt(
		float(_controller.get_runners_remaining()), 0.0,
		"the survivors are still counted; the loss did not need them gone",
	)

	# Resolution freezes the ring: the survivors must not run on and finish laps
	# of their own after the round is over.
	await step_seconds(1.0)
	for runner: RingRunner in _controller.get_live_runners():
		assert_false(runner.is_physics_processing(), "a survivor of a resolved round is frozen")
		assert_almost_eq(
			runner.controller.get_horizontal_speed(), 0.0, 1e-6,
			"a frozen survivor is not still moving",
		)


## Whatever else happens, a round resolves exactly once.
##
## Both resolution paths are fired after the round is already decided: a second
## arrival, and then the removal of every remaining runner, which unguarded
## would turn the loss into a win. The counter is the assertion --
## [method MatchController.get_resolve_count] exists for precisely this.
func test_the_round_resolves_exactly_once() -> void:
	var runners: Array[RingRunner] = _controller.get_live_runners()
	runners[0].reached_end.emit(12.0, 96.0)
	assert_eq_int(int(_controller.get_outcome()), int(MatchController.Outcome.LOSS), "the first arrival decides it")

	# A second arrival in the same frame, and a third.
	runners[1].reached_end.emit(12.5, 97.0)
	runners[2].reached_end.emit(13.0, 98.0)

	# And a shot that lands after the loss must not be able to convert it.
	for runner: RingRunner in _controller.get_live_runners():
		assert_false(
			_controller.remove_runner(runner),
			"a resolved round refuses further removals",
		)

	assert_eq_int(int(_controller.get_outcome()), int(MatchController.Outcome.LOSS), "the outcome never changed")
	assert_eq_int(_controller.get_resolve_count(), 1, "exactly one resolution for one round")
	assert_eq_int(_resolutions, 1, "exactly one round_resolved signal for one round")

	# A restart is a new round, and gets its own single resolution.
	_controller.start_round()
	await step_ticks(SETTLE_TICKS)
	assert_false(_controller.is_resolved(), "a restarted round is live again")
	for runner: RingRunner in _controller.get_live_runners():
		_controller.remove_runner(runner)
	assert_eq_int(_controller.get_resolve_count(), 2, "two rounds played, two resolutions")


# --- Regression ---------------------------------------------------------------

## Spawning the runners must not move the player off the tower.
##
## [b]The bug.[/b] [MatchController] instanced each runner and added it to the
## tree at the scene's default transform -- the origin -- and only then called
## [method RingRunner.configure] to put it on its lane. The physics server
## registers a body where it is on the tick it enters the tree, and the tower
## spawn [i]is[/i] the origin, so three 0.8 m capsules materialised inside the
## shooter's own capsule. Depenetration resolved the overlap the only way it
## could and threw the player out to the arena's outer wall, 59 m away, before
## the runners had moved anywhere.
##
## [b]Why it needs a test and not a comment.[/b] It is invisible after the fact:
## by the time anything could look, the runners are correctly on their lanes and
## a shape query at the tower finds nothing wrong. The only evidence is where the
## player ended up. It survived one fix attempt because the ejection is not
## instantaneous -- it takes a few ticks -- so a check made on the spawn frame
## saw nothing. And it will come back the moment somebody adds a fourth spawn
## site, or reorders [method MatchController._spawn_runners] so the placement
## follows the [method Node.add_child] again.
##
## [b]What the fix is.[/b] The body's position is written [i]before[/i] it enters
## the tree, so it is never registered at the origin at all.
func test_spawning_runners_does_not_displace_the_player() -> void:
	# before_each has already armed a round and let it settle for a second.
	var drift: float = _horizontal_distance(_player.global_position, _tower_spawn)
	assert_lt(
		drift, SPAWN_TOLERANCE_METRES,
		"the player must still be on the tower after the opening round is armed",
	)

	# And again on a restart, which spawns three more bodies while the player is
	# already standing on the spawn point rather than arriving at it. This is the
	# strictest form of the assertion: the player was settled and stationary, the
	# restart puts it back on the same marker, so the position must not move at
	# all. Measured reproduction of the old order put it 1.8 m in the air here.
	var settled_at: Vector3 = _player.global_position
	_controller.start_round()
	await step_ticks(SETTLE_TICKS)
	assert_vec3_almost_eq(
		_player.global_position, settled_at, 0.05,
		"arming a round must not move a stationary player one way or the other",
	)
	assert_lt(
		_horizontal_distance(_player.global_position, _tower_spawn), SPAWN_TOLERANCE_METRES,
		"the player must still be on the tower after a restart re-spawns the runners",
	)

	# The player is standing, not falling through the platform or riding it up.
	assert_almost_eq(
		_player.global_position.y, _tower_spawn.y, 0.5,
		"the player is standing on the tower platform",
	)
	assert_true(_player.is_on_floor(), "the player is on the tower platform, not in the air")

	# The runners went where they were meant to go, which is the other half of
	# the same fix: nothing was displaced, in either direction.
	var runners: Array[RingRunner] = _controller.get_live_runners()
	assert_eq_int(runners.size(), _controller.get_runners_total(), "all runners survived the spawn")
	for index: int in runners.size():
		assert_gt(
			_radius_of(runners[index].controller.global_position), 30.0,
			"runner %d is out on the ring, not at the origin" % index,
		)


# --- Helpers ------------------------------------------------------------------

func _on_round_resolved(outcome: MatchController.Outcome) -> void:
	_resolutions += 1
	_last_outcome = int(outcome)


func _radius_of(point: Vector3) -> float:
	return Vector2(point.x, point.z).length()


func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
