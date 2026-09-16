extends SceneTree

## Does the map change what goes on the wire?
##
## [codeblock]
## godot --headless --path . --script res://tools/perf/profile_wire.gd -- \
##     --map=forest --ticks=180
## [/codeblock]
##
## [b]The claim under test.[/b] A map is scenery and collision; the snapshot is
## eight fixed-size [PlayerState] rows and the intent is one struct per tick.
## Nothing in [NetCodec] reads the arena, so the bytes per tick must be
## identical with a map loaded and with no map at all. That is an argument, not
## a measurement -- this script is the measurement. Run it once per map and once
## with [code]--map=[/code] and compare the printed rates.
##
## [b]What it runs.[/b] Exactly the session
## [code]tests/test_budgets.gd::test_eight_seats_stay_inside_their_wire_budget[/code]
## measures -- two [NetSession]s on two real UDP sockets in one process, eight
## seats, seat 0 owned by the client, bodies spread out and moving, a settle
## window then a measure window, [method NetTransport.take_wire_stats] read at
## both ends -- with ONE difference: when [code]--map[/code] is non-empty, that
## map's arena scene is instanced into the tree before the session is stood up,
## so the wire is measured with the real map's nodes present. Everything else,
## including the flat test floor and the seat positions, is held fixed, because
## a comparison whose control also moved measures nothing.
##
## [codeblock]
## --map=ID      catalog id (bentham_ring, marble, forest), a res:// scene path,
##               or EMPTY for no arena at all             (default "")
## --ticks=N     physics ticks in the measure window      (default 180)
## --settle=N    ticks run before the counters are read   (default 40)
## [/codeblock]
##
## Prints one line and nothing else:
## [codeblock]
## WIRE map=forest seats=8 ticks=180 host_up_B_per_tick=440.7 client_down_B_per_tick=63.0 snapshots=90
## [/codeblock]
## [code]map=none[/code] is the no-arena control. Exits 0 on success and 2 when
## the loopback handshake did not complete or the run could not be set up.
##
## [b]Why the work happens in _process[/b], and not in [method _initialize]: the
## same three headless facts [code]tools/harness/run_bot_match.gd[/code] is built
## around. [method SceneTree.quit] from [method _initialize] exits before stdout
## is flushed -- and this script's entire output is one line on stdout. Nodes
## added there are not in the tree, so every [member Node3D.global_position]
## reads back as the origin and the eight seats would be stacked in one spot.
## And a coroutine needs a running main loop to deliver the frames it parks on.
##
## [b]Nothing here may wait forever.[/b] The handshake is bounded by the WALL
## clock through [method NetFixtures.poll_until] rather than by a tick count,
## and both measure windows are bounded by a tick count. There is no path
## through this file that blocks.
##
## [b]What it found, 2026-09-16, on the Mac.[/b] Snapshot count (90) and packet
## count (100-102) are the same in every arm, and [method NetCodec.pack_snapshot]
## writes a fixed field list per seat with all eight seats replicable
## throughout, so the packed payload is map-independent by construction. The
## measured rate is not quite: 449.5 B/tick with no arena, 449.5 on
## bentham_ring, 440.7 on forest, 432.2 on marble -- a 4 % spread, reproducible
## to 0.1 B/tick across runs. That spread is the RANGE CODER, not the map:
## [member NetSettings.compress_traffic] is on in the shipped settings this
## measures, so what a packet costs depends on the VALUES in it, and a map's
## collision leaves the eight bodies at different positions than a flat floor
## does. The map changes where the players are; it does not change what a
## player costs. Nothing about the arena reaches the protocol.

const EXIT_OK: int = 0
const EXIT_BROKEN: int = 2

## A full lobby: one host, seven clients. Fixed, not an option: the question is
## what the MAP costs, so the lobby is the control and must not move.
const SEATS: int = 8

## The measure window's default, and the settle window's: the same 180 and 40
## `tests/test_budgets.gd` uses, so a number printed here is comparable to the
## B4/B5 numbers printed by every suite run.
const DEFAULT_TICKS: int = 180
const DEFAULT_SETTLE: int = 40

## Real time. [b]The one place this deliberately departs from the budget
## test[/b], which runs under the suite's 50x clock, and it is not a detail.
##
## Under compression the main loop retires up to fifty physics steps per
## iteration while [MultiplayerAPI] polls the socket once per IDLE frame, so
## many ticks' traffic is flushed as one batch and the number of batches
## depends on how fast the frame ran. A heavier map runs slower, batches more
## ticks per flush, and therefore pays LESS per-packet overhead per tick: on
## this machine that alone moved the rate 435-471 B/tick, swamping the effect
## this script exists to look for and pointing the WRONG WAY -- the arm with no
## arena at all read highest. A profiler whose answer is a function of frame
## cost cannot answer a question about the wire. At 1x every tick gets its own
## flush, the pacing is the shipped game's, and the same arm reproduces to
## 0.1 B/tick. The window costs [constant DEFAULT_TICKS] / 60 real seconds --
## three, which is nothing for a tool run by hand.
const TIME_COMPRESSION: int = 1

## Printed for the empty [code]--map[/code]: the no-arena control. The control
## has no id, and printing `map=` with nothing after it would read as a parse
## failure rather than a deliberate arm of the comparison.
const NO_MAP_LABEL: String = "none"

var _options: Dictionary = {}
var _started: bool = false
var _finished: bool = false
var _exit_code: int = EXIT_OK

var _case: Node = null
var _host: NetSession = null
var _client: NetSession = null
var _links: Array[PlayerNetLink] = []
var _snapshots: int = 0


func _initialize() -> void:
	_options = BotHarness.parse_arguments({
		"map": "",
		"ticks": DEFAULT_TICKS,
		"settle": DEFAULT_SETTLE,
	})
	BotHarness.apply_time_compression(TIME_COMPRESSION)


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		# Deliberately not awaited: _run parks on physics and process frames,
		# and this main loop is what delivers them.
		_run()
		return false
	if _finished:
		quit(_exit_code)
		return true
	return false


func _run() -> void:
	if bool(_options.get("_error", false)):
		printerr("Bad command line; nothing was measured.")
		_shut_down(EXIT_BROKEN)
		return

	var map_id: String = String(_options.get("map", ""))
	var ticks: int = maxi(int(_options.get("ticks", DEFAULT_TICKS)), 1)
	var settle: int = maxi(int(_options.get("settle", DEFAULT_SETTLE)), 0)

	_case = Node.new()
	_case.name = "WireProfile"
	root.add_child(_case)

	if not _instance_map(map_id):
		_shut_down(EXIT_BROKEN)
		return

	if not await _stand_up_session(settle):
		printerr("The loopback handshake did not complete; nothing was measured.")
		_shut_down(EXIT_BROKEN)
		return

	# Drain both ends: the handshake, the roster and the first snapshots are
	# setup cost, not steady state, and pop_statistic is destructive so reading
	# is how they leave the window.
	var _drain_host: Dictionary = _host.transport.take_wire_stats()
	var _drain_client: Dictionary = _client.transport.take_wire_stats()
	_snapshots = 0

	await _step_ticks(ticks)
	var host_stats: Dictionary = _host.transport.take_wire_stats()

	# Per TICK, not per wall-clock second: the traffic is paced against the tick,
	# so that is the only rate a comparison can be made in. It also survives a
	# change of clock, which a per-second rate would not.
	#
	# The host in this process talks to ONE real client, so what it sent is that
	# client's downstream; a full lobby is the same conversation with seven of
	# them. Measuring seven here would measure this process's own loopback
	# rather than the game. Identical arithmetic to B4/B5 in test_budgets.gd,
	# on purpose: the two numbers have to mean the same thing.
	var down_per_tick: float = float(int(host_stats.get("sent_bytes", 0))) / float(ticks)
	var host_up_per_tick: float = down_per_tick * float(SEATS - 1)

	print("WIRE map=%s seats=%d ticks=%d host_up_B_per_tick=%.1f client_down_B_per_tick=%.1f snapshots=%d" % [
		map_id if not map_id.is_empty() else NO_MAP_LABEL,
		SEATS, ticks, host_up_per_tick, down_per_tick, _snapshots,
	])

	if _snapshots <= 0:
		printerr("The host sent no snapshots in the window; the rate above is not a measurement.")
		_shut_down(EXIT_BROKEN)
		return
	_shut_down(EXIT_OK)


## Put the real map's nodes in the tree, before anything networked exists.
##
## An empty [param map_id] is the control arm and instances nothing.
##
## [b]The id is checked before it is resolved, not after.[/b]
## [method MapCatalog.scene_path_for] is deliberately forgiving -- an id it does
## not know falls back to the default map, because its callers are a running
## match and an unattended sweep and neither is a reason to hand the player an
## empty world. For a profiler that fallback is the worst thing that could
## happen: [code]--map=frest[/code] would silently measure bentham_ring, the arm
## would agree with the bentham_ring arm to the byte, and the run would report
## exactly the null result this script exists to test for. So an unknown id is
## refused here rather than quietly honoured.
func _instance_map(map_id: String) -> bool:
	if map_id.is_empty():
		return true
	var names_a_scene: bool = map_id.begins_with("res://")
	if not (MapCatalog.has(StringName(map_id)) if not names_a_scene else ResourceLoader.exists(map_id)):
		printerr("No map '%s'; refusing to fall back to the default and measure the wrong arm." % map_id)
		return false
	var path: String = MapCatalog.scene_path_for(StringName(map_id))
	if path.is_empty():
		printerr("No scene for map '%s'." % map_id)
		return false
	var scene: PackedScene = load(path) as PackedScene
	if scene == null:
		printerr("Cannot load %s for map '%s'." % [path, map_id])
		return false
	var arena: Node = scene.instantiate()
	if arena == null:
		printerr("Cannot instance %s for map '%s'." % [path, map_id])
		return false
	arena.name = "Arena"
	_case.add_child(arena)
	return true


## Two sessions on two real UDP sockets, eight seats, seat 0 owned by the
## client. The shape [code]tests/test_budgets.gd[/code] stands up, unchanged:
## every value here is load-bearing for the comparison, so none of it is an
## option.
func _stand_up_session(settle: int) -> bool:
	var profile: MovementProfile = TestFixtures.movement_profile()
	_host = NetFixtures.make_peer(_case, "Host", NetFixtures.settings())
	_client = NetFixtures.make_peer(_case, "Client", NetFixtures.settings())
	# Kept even when a map is loaded: the seats stand on the same flat ground in
	# every arm, so the only thing that changed between arms is the map's nodes.
	_case.add_child(TestFixtures.make_floor(0.0))

	var port: int = await NetFixtures.host_and_wait(_case, _host)
	if port < 0:
		return false
	if not await NetFixtures.join_and_wait(_case, _client, _host, port):
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
	await _step_ticks(settle)
	return true


## Advance the simulation by [param count] physics ticks. Bounded by the count,
## so no window can outlive its argument.
func _step_ticks(count: int) -> void:
	for _i: int in count:
		await physics_frame


## Close both sockets, then let [method _process] retire the run. Sessions are
## left rather than dropped so the far end sees a disconnect instead of a
## silence it has to time out.
func _shut_down(code: int) -> void:
	_links.clear()
	if _client != null:
		_client.leave()
	if _host != null:
		_host.leave()
	_exit_code = code
	_finished = true
