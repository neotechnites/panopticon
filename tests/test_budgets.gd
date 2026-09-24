extends TestCase

## The performance and bandwidth budgets, as tests.
##
## A periodic review finds a regression weeks after it landed. This file finds
## it on the merge that causes it: it runs the same two things the reviews
## measured -- a seven-bot match and an eight-seat net session -- and fails when
## a number leaves its budget.
##
## [b]Every budget is a measured value plus 20 % headroom[/b], taken on the Mac
## this suite runs on, and every measured value is printed on a [code]BUDGET[/code]
## line on every run so drift is visible long before the gate trips.
##
## [b]These are gates, not targets.[/b] The Mac is not Ryan's PC and the absolute
## numbers say nothing about whether the game holds 60 fps there -- see
## [code]docs/PERF_REVIEW.md[/code] §2, which is why the PC profiler exists. What
## a gate catches is a CHANGE OF ORDER: a fresh allocation back in a hot loop, a
## field added to the snapshot, a per-tick group sweep. That is regression-shaped
## and it is what this file is for.
##
## Set [code]PANOPTICON_SKIP_BUDGETS=1[/code] to skip the whole file on a machine
## too slow or too loaded to measure anything on. The skip is printed every run.

const SKIP_ENV: String = "PANOPTICON_SKIP_BUDGETS"

# --- The seven-bot match ------------------------------------------------------

const RULES_PATH: String = "res://match/rules/default_match_rules.tres"
const SHOOTER_PROFILE_PATH: String = "res://characters/bots/default_shooter_profile.tres"

## Seven bots, because seven is the full lobby and the only count the physics
## tick has ever failed at. See PERF_REVIEW §2.
const BOTS: int = 7

## Fixed, so two runs plan the same shots. The bots are not deterministic across
## machines (PERF_REVIEW §2) but a seed removes one source of spread from the
## measurement.
const SEED: int = 20260930

## Ticks run before the counters start: the opening race, the first nav bake and
## the first seat grant are setup costs, not steady state.
const WARMUP_TICKS: int = 120

## The measurement window. 1080 ticks at 60 Hz is 18 simulated seconds, which
## with the warmup is the ~20 s the budget was set over.
const MEASURE_TICKS: int = 1080

## B1 -- mean wall-clock cost of one physics tick, in milliseconds.
## Measured 1.187-1.190 ms over three runs; budget is the worst of those +20 %.
const B1_TICK_AVG_MS: float = 1.45

## B2 -- the worst tick of the window, in milliseconds, discarding the single
## highest sample as scheduler noise (see [member TickSampler.second_worst_usec]).
##
## Measured 5.41-5.85 ms over three runs; budget is the worst of those +20 %.
## Well above B1 because the tail is where the bot AI lives: one cover search
## that finds nothing costs several times an idle tick.
const B2_TICK_WORST_MS: float = 7.00

## B3 -- live [Object]s created per tick that outlive the tick, averaged.
##
## [constant Performance.OBJECT_COUNT] sampled at tick boundaries: GDScript is
## refcounted, so an object built and dropped inside one tick never appears here
## and this does NOT price the churn the perf review fixed. What it catches is
## the shape that actually regresses -- a per-tick allocation that is kept: a
## growing cache, a node spawned per tick, a signal connection leaked.
##
## Measured 0.002 -- two objects kept across a 1079 tick window, three runs
## running. A 20 % headroom on that is 2.4 objects and would fail the first time
## a respawn landed inside the window, so this one gets an absolute floor
## instead: 0.05 is twenty-five times the measured value and still twenty times
## below the one-object-per-tick shape the gate exists to catch.
const B3_OBJECTS_PER_TICK: float = 0.05

# --- The eight-seat session ---------------------------------------------------

## A full lobby: one host, seven clients.
const SEATS: int = 8

## 180 ticks at 60 Hz is 3 simulated seconds, ~90 snapshots at the shipped rate.
const NET_MEASURE_TICKS: int = 180

## Ticks run before the counters are read, so the handshake and the first roster
## are not in the window.
const NET_SETTLE_TICKS: int = 40

## B4 -- bytes the host puts on the wire per tick with a full lobby on it.
##
## What one client costs, times seven. The fixture has one real client and
## measuring seven would measure this process's own loopback, not the game.
## Measured 445.2 B/tick, identical on three runs; budget is that +20 %.
const B4_HOST_UP_BYTES_PER_TICK: float = 535.0

## B5 -- bytes one client receives per tick.
## Measured 63.6 B/tick, identical on three runs; budget is that +20 %.
const B5_CLIENT_DOWN_BYTES_PER_TICK: float = 76.5


func _skipped_by_machine() -> bool:
	if OS.get_environment(SKIP_ENV).is_empty():
		return false
	skip("%s is set; the budgets were not measured this run" % SKIP_ENV)
	print("          BUDGET skipped by %s" % SKIP_ENV)
	return true


# --- Physics ------------------------------------------------------------------

## Counts what one physics tick costs, from inside the tick loop.
##
## Wall clock between consecutive callbacks, as the harness's own
## [code]tick_ms[/code] does, and the only honest instrument here: the runner
## compresses simulated time, so a tick's DELTA is pinned at 1/60 s however long
## the machine took over it. Priority is raised so this samples last in the tick.
class TickSampler extends Node:
	var ticks: int = 0
	var worst_usec: int = 0
	## Second-highest sample. B2 gates on this: one tick in ~1080 can be stolen
	## by the OS scheduler regardless of game code, so the single worst is kept
	## for the report but the gate discards it as one forgiven outlier.
	var second_worst_usec: int = 0
	var total_usec: int = 0
	var objects_gained: int = 0
	var _last_usec: int = -1
	var _last_objects: int = -1
	var _armed: bool = false

	func _init() -> void:
		process_priority = 100

	## Start counting. Called after the warmup, so setup is not in the window.
	func arm() -> void:
		_armed = true
		_last_usec = -1
		_last_objects = -1

	func _physics_process(_delta: float) -> void:
		var now: int = Time.get_ticks_usec()
		var objects: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))
		if _armed and _last_usec >= 0:
			var spent: int = now - _last_usec
			if spent > worst_usec:
				second_worst_usec = worst_usec
				worst_usec = spent
			elif spent > second_worst_usec:
				second_worst_usec = spent
			total_usec += spent
			objects_gained += maxi(objects - _last_objects, 0)
			ticks += 1
		_last_usec = now
		_last_objects = objects


## Build the world the harness runs, with the rounds and lives raised so the
## window measures twenty seconds of play rather than ending at the first pad.
func _build_match() -> BotMatchWorld:
	var rules: MatchRules = (load(RULES_PATH) as MatchRules).duplicate() as MatchRules
	rules.prisoner_count = BOTS
	rules.rounds_to_win_match = 99
	rules.prisoner_lives = 99

	var world: BotMatchWorld = BotMatchWorld.new()
	add_child(world)
	world.build(rules)

	var controller: MatchController = world.get_controller()
	var seat: BotTowerSeat = BotTowerSeat.new()
	seat.name = "TowerSeat"
	add_child(seat)
	seat.install(controller, (load(SHOOTER_PROFILE_PATH) as ShooterProfile).duplicate() as ShooterProfile, SEED)

	controller.start_match()
	BotMatchWorld.silence_local_input(world.get_runner_container())
	return world


func test_a_seven_bot_match_stays_inside_its_physics_budget() -> void:
	if _skipped_by_machine():
		return

	var world: BotMatchWorld = _build_match()
	var sampler: TickSampler = TickSampler.new()
	sampler.name = "TickSampler"
	add_child(sampler)

	await step_ticks(WARMUP_TICKS)
	sampler.arm()
	await step_ticks(MEASURE_TICKS)

	if not assert_gt(float(sampler.ticks), float(MEASURE_TICKS) * 0.9, "the window actually ran"):
		return

	var avg_ms: float = float(sampler.total_usec) / float(sampler.ticks) / 1000.0
	var peak_ms: float = float(sampler.worst_usec) / 1000.0
	var worst_ms: float = float(sampler.second_worst_usec) / 1000.0
	var objects: float = float(sampler.objects_gained) / float(sampler.ticks)
	# Seven prisoners plus whoever holds the tower seat: the guard is a
	# participant too, and a match that lost one would measure a quieter game.
	var seats: int = world.get_controller().get_participants().size()

	print("          BUDGET physics at %d seats over %d ticks: avg %.3f ms (B1 %.2f), worst %.2f ms (B2 %.1f, peak %.2f ms), %.3f objects/tick (B3 %.2f, %d kept)" % [
		seats, sampler.ticks, avg_ms, B1_TICK_AVG_MS, worst_ms, B2_TICK_WORST_MS, peak_ms,
		objects, B3_OBJECTS_PER_TICK, sampler.objects_gained,
	])

	assert_eq_int(seats, BOTS + 1, "seven prisoners and a guard were actually in the match")
	assert_le(avg_ms, B1_TICK_AVG_MS, "B1: the mean physics tick is inside budget")
	assert_le(worst_ms, B2_TICK_WORST_MS, "B2: the worst physics tick is inside budget")
	assert_le(objects, B3_OBJECTS_PER_TICK, "B3: objects kept per tick are inside budget")


# --- Bandwidth ----------------------------------------------------------------

var _host: NetSession = null
var _client: NetSession = null
var _links: Array[PlayerNetLink] = []
var _snapshots: int = 0


func after_each() -> void:
	_links.clear()
	if _client != null:
		_client.leave()
	if _host != null:
		_host.leave()


## Two sessions on two real UDP sockets, eight seats, seat 0 owned by the client.
## The same shape as [code]tests/test_net_cost.gd[/code] stands up, kept short.
func _stand_up_session() -> bool:
	var profile: MovementProfile = TestFixtures.movement_profile()
	_host = NetFixtures.make_peer(self, "Host", NetFixtures.settings())
	_client = NetFixtures.make_peer(self, "Client", NetFixtures.settings())
	add_child(TestFixtures.make_floor(0.0))

	var port: int = await NetFixtures.host_and_wait(self, _host)
	if port < 0:
		return false
	if not await NetFixtures.join_and_wait(self, _client, _host, port):
		return false
	var client_id: int = _client.get_local_peer_id()

	for seat: int in SEATS:
		var owner_id: int = client_id if seat == 0 else 0
		_links.append(NetFixtures.add_seat_body(_host, seat, owner_id, profile, seat != 0))
		var mirror: PlayerNetLink = NetFixtures.add_seat_body(_client, seat, owner_id, profile, seat == 0)
		mirror.controller.collision_layer = 0
		mirror.controller.collision_mask = 1
	# Spread out and keep everything moving: a snapshot of eight identical,
	# motionless rows is not a snapshot this game ever sends.
	for i: int in _links.size():
		var link: PlayerNetLink = _links[i]
		link.controller.collision_layer = 0
		link.controller.collision_mask = 1
		link.controller.global_position = Vector3(float(i) * 3.0 - 10.0, 0.1, 0.0)
		var source: BotIntentSource = link.local_source as BotIntentSource
		if source != null:
			source.command.move_direction = Vector2(sin(float(i) * 0.7), cos(float(i) * 0.7))
			source.command.look_delta.x = 0.004

	_host.replicator.snapshot_sent.connect(func(_t: int, _c: int) -> void: _snapshots += 1)
	await step_ticks(NET_SETTLE_TICKS)
	return true


func test_eight_seats_stay_inside_their_wire_budget() -> void:
	if _skipped_by_machine():
		return
	if not await _stand_up_session():
		fail("the loopback handshake did not complete")
		return

	var _discard_host: Dictionary = _host.transport.take_wire_stats()
	var _discard_client: Dictionary = _client.transport.take_wire_stats()
	_snapshots = 0
	await step_ticks(NET_MEASURE_TICKS)
	var host_stats: Dictionary = _host.transport.take_wire_stats()

	if not assert_gt(float(_snapshots), 10.0, "the host actually sent snapshots in the window"):
		return

	# Per TICK, not per wall-clock second: the runner compresses simulated time
	# and a socket has not heard about it, so the only rate that means anything
	# is the one the traffic is paced against.
	var down_per_tick: float = float(int(host_stats.get("sent_bytes", 0))) / float(NET_MEASURE_TICKS)
	# One client is measured; a full lobby is the host talking to seven of them.
	var host_up_per_tick: float = down_per_tick * float(SEATS - 1)

	print("          BUDGET wire at %d seats over %d ticks: host up %.1f B/tick (B4 %.0f), client down %.1f B/tick (B5 %.0f), %d snapshots" % [
		SEATS, NET_MEASURE_TICKS, host_up_per_tick, B4_HOST_UP_BYTES_PER_TICK,
		down_per_tick, B5_CLIENT_DOWN_BYTES_PER_TICK, _snapshots,
	])

	assert_le(host_up_per_tick, B4_HOST_UP_BYTES_PER_TICK, "B4: host upstream is inside budget")
	assert_le(down_per_tick, B5_CLIENT_DOWN_BYTES_PER_TICK, "B5: a client's downstream is inside budget")
