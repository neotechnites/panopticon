extends TestCase

## The hologram over the wire: two real [NetSession] scenes on two real UDP
## sockets, one spawning a decoy and one being told where it is.
##
## The decoy RUNS, which is the whole reason it needs a stream of its own. A
## client that is only told one exists draws it where its own body happened to
## be standing, and then shoots at a hologram the host does not have there.

## How far apart the two machines' holograms may be, at any point in the life
## of one. A decoy leaves at run speed, so a single tick of drift is more than
## twice this: the bound is tight enough that only a streamed transform meets
## it.
const TOLERANCE_METRES: float = 0.05

## Ticks the decoy is watched for, and how long it is given to live. Long
## enough for it to leave the place it spawned by a good margin.
const LIFETIME_TICKS: int = 40
const DURATION_SECONDS: float = 0.5

var _host: NetSession
var _client: NetSession
var _profile: MovementProfile
var _rules: MatchRules
var _host_stub: MatchController
var _client_stub: MatchController
var _saved_hz: int = 0
var _saved_scale: float = 1.0


func before_each() -> void:
	# At real time, alone in the suite. The runner compresses the clock fifty
	# fold and a socket has not heard about it: every millisecond a packet
	# spends on the loopback interface is fifty simulated ticks of a body that
	# is running, and what would be measured is the compression rather than the
	# replication.
	_saved_hz = Engine.physics_ticks_per_second
	_saved_scale = Engine.time_scale
	Engine.physics_ticks_per_second = int(SIM_HZ)
	Engine.time_scale = 1.0
	_profile = TestFixtures.movement_profile()
	_rules = TestFixtures.match_rules()
	_rules.runner_ability = MatchRules.RunnerAbility.HOLOGRAM
	_rules.ability_duration_seconds = DURATION_SECONDS
	_rules.ability_cooldown_seconds = 5.0
	_host = NetFixtures.make_peer(self, "Host", NetFixtures.settings())
	_client = NetFixtures.make_peer(self, "Client", NetFixtures.settings())
	add_child(TestFixtures.make_floor(0.0))


func after_each() -> void:
	Engine.physics_ticks_per_second = _saved_hz
	Engine.time_scale = _saved_scale
	if _client != null:
		_client.leave()
	if _host != null:
		_host.leave()
	# Off the tree, so nothing frees them but this.
	for stub: MatchController in [_host_stub, _client_stub]:
		if stub != null:
			stub.free()
	_host_stub = null
	_client_stub = null


func test_a_clients_hologram_stands_where_the_hosts_does_and_dies_with_it() -> void:
	var host_power: RunnerPower = null
	var client_power: RunnerPower = null
	var powers: Array[RunnerPower] = await _bring_up()
	if powers.is_empty():
		return
	host_power = powers[0]
	client_power = powers[1]

	assert_true(host_power.activate(), "the runner threw a hologram")
	var host_decoy: PlayerController = host_power.get_decoy()
	assert_not_null(host_decoy, "the authority has one")
	if host_decoy == null:
		return

	var spawned: bool = await NetFixtures.poll_until(
		self, func() -> bool: return client_power.get_decoy() != null
	)
	assert_true(spawned, "and the client was told there is one")
	if not spawned:
		return

	var start: Vector3 = host_decoy.global_position
	var last: Vector3 = start
	var worst: float = 0.0
	var worst_yaw: float = 0.0
	for _tick: int in LIFETIME_TICKS:
		await step_ticks(1)
		# One idle frame for the packet the tick just produced: polling the
		# socket is what a MultiplayerAPI does between frames, not during them.
		await get_tree().process_frame
		if not is_instance_valid(host_decoy) or host_decoy.is_queued_for_deletion():
			break
		last = host_decoy.global_position
		var mirror: PlayerController = client_power.get_decoy()
		if mirror == null:
			fail("the client's hologram vanished while the host's was still running")
			return
		worst = maxf(worst, mirror.global_position.distance_to(last))
		worst_yaw = maxf(worst_yaw, absf(angle_difference(mirror.rotation.y, host_decoy.rotation.y)))

	assert_almost_eq(worst_yaw, 0.0, 0.01, "the client's hologram faced the way the host's did")
	assert_gt(
		last.distance_to(start), 1.0, "the host's hologram ran, so its transform had to stream"
	)
	assert_lt(
		worst,
		TOLERANCE_METRES,
		"the client's hologram stayed on the host's (worst gap %.3f m)" % worst,
	)


func test_the_hologram_dies_on_the_client_when_it_dies_on_the_host() -> void:
	var powers: Array[RunnerPower] = await _bring_up()
	if powers.is_empty():
		return
	assert_true(powers[0].activate(), "the runner threw a hologram")
	if not await NetFixtures.poll_until(self, func() -> bool: return powers[1].get_decoy() != null):
		fail("the client was never told there is one")
		return

	RunnerPower.shatter(powers[0].get_decoy())
	await step_ticks(1)
	assert_null(powers[0].get_decoy(), "the shot took the host's hologram")

	# One tick of transport, not one snapshot: the despawn does not wait for the
	# ability byte to go to NONE in the next snapshot.
	var gone: bool = await NetFixtures.poll_until(
		self, func() -> bool: return powers[1].get_decoy() == null
	)
	assert_true(gone, "and the client's went with it")


func test_the_hologram_expires_on_the_client_when_the_power_runs_out() -> void:
	var powers: Array[RunnerPower] = await _bring_up()
	if powers.is_empty():
		return
	assert_true(powers[0].activate(), "the runner threw a hologram")
	if not await NetFixtures.poll_until(self, func() -> bool: return powers[1].get_decoy() != null):
		fail("the client was never told there is one")
		return

	await step_seconds(DURATION_SECONDS + 0.1)
	assert_null(powers[0].get_decoy(), "the power ran out on the authority")
	var gone: bool = await NetFixtures.poll_until(
		self, func() -> bool: return powers[1].get_decoy() == null
	)
	assert_true(gone, "and the client's hologram expired with it")


# --- Fixture ------------------------------------------------------------------

## Connect the two peers, seat one body on each and arm both abilities. Returns
## [the host's power, the client's], or an empty array after failing loudly.
func _bring_up() -> Array[RunnerPower]:
	var port: int = await NetFixtures.host_and_wait(self, _host)
	if port < 0:
		fail("the host could not take a port")
		return []
	if not await NetFixtures.join_and_wait(self, _client, _host, port):
		fail("the loopback handshake did not complete")
		return []

	var host_link: PlayerNetLink = NetFixtures.add_seat_body(_host, 0, 0, _profile, true)
	var client_link: PlayerNetLink = NetFixtures.add_seat_body(_client, 0, 0, _profile, false)
	await step_ticks(1)

	_host_stub = _make_stub(_host)
	_client_stub = _make_stub(_client)
	var host_power: RunnerPower = RunnerPower.of(host_link.controller)
	var client_power: RunnerPower = RunnerPower.of(client_link.controller)
	if host_power == null or client_power == null:
		fail("the shipped body has no ability node")
		return []
	host_power.arm(_rules, _host_stub)
	client_power.arm(_rules, _client_stub)
	return [host_power, client_power]


## What [RunnerPower] needs of a match to build a decoy: a scene to instance and
## a container to put it in. Off the tree, so [MatchController] runs no match.
func _make_stub(session: NetSession) -> MatchController:
	var container: Node3D = Node3D.new()
	container.name = "Runners"
	session.get_parent().add_child(container)
	var stub: MatchController = MatchController.new()
	stub.runner_scene = load(TestFixtures.RUNNER_SCENE_PATH) as PackedScene
	stub.runner_container = container
	return stub
