class_name NetPowerRig
extends TestCase

## Three machines in one process for the power tests: a host and two clients on real sockets,
## each with a body for seat 0 (the host's) and seat 1 (client A's). B owns nothing: it is the
## third peer, there to see what the other two do. [LossyPeer] conditions the wire.

const HOST_SEAT: int = 0
const A_SEAT: int = 1
const START: Array[Vector3] = [Vector3(0.0, 0.1, 0.0), Vector3(6.0, 0.1, 0.0)]
## Long enough for the slowest thing waited on: a power's run plus a conditioned wire.
const WAIT_MS: int = 4000

var host: NetSession
var a: NetSession
var b: NetSession
var rules: MatchRules
var profile: MovementProfile
## Per machine, the links by seat.
var host_links: Array[PlayerNetLink] = []
var a_links: Array[PlayerNetLink] = []
var b_links: Array[PlayerNetLink] = []
## The host's own device and client A's.
var host_keys: PressSource
var a_keys: PressSource
## The conditioned wires, null on a clean line: A's sends (intent) and the host's (snapshots).
var a_wire: LossyPeer
var host_wire: LossyPeer

var _stubs: Array[MatchController] = []
var wires: NetWires = NetWires.new()
var _saved_hz: int = 0
var _saved_scale: float = 1.0


func before_each() -> void:
	# Real time: a socket has not heard about the runner's compressed clock.
	_saved_hz = Engine.physics_ticks_per_second
	_saved_scale = Engine.time_scale
	Engine.physics_ticks_per_second = int(SIM_HZ)
	Engine.time_scale = 1.0
	process_physics_priority = -100
	profile = TestFixtures.movement_profile()
	rules = TestFixtures.match_rules()
	rules.ability_duration_seconds = 1.0
	rules.ability_cooldown_seconds = 0.0
	host = NetFixtures.make_peer(self, "Host", NetFixtures.settings())
	a = NetFixtures.make_peer(self, "ClientA", NetFixtures.settings())
	b = NetFixtures.make_peer(self, "ClientB", NetFixtures.settings())
	add_child(TestFixtures.make_floor(0.0))
	wires.clear()
	for session: NetSession in [host, a]:
		session.connection_state_changed.connect(_wrap.bind(session))
	for session: NetSession in [a, b]:
		session.replicator.event_received.connect(_present_event.bind(session))


## Every machine reads its socket once a tick, whatever the frame rate: the engine polls on
## idle frames, and a loaded machine runs eight ticks to a frame.
func _physics_process(_delta: float) -> void:
	for session: NetSession in [host, a, b]:
		if session != null and session.multiplayer.has_multiplayer_peer():
			session.multiplayer.poll()


func after_each() -> void:
	Engine.physics_ticks_per_second = _saved_hz
	Engine.time_scale = _saved_scale
	for session: NetSession in [b, a, host]:
		if session != null:
			session.leave()
	wires.clear()
	for stub: MatchController in _stubs:
		if is_instance_valid(stub):
			stub.free()
	_stubs.clear()


## Connect all three, build the bodies and arm every power. [param loss] and [param delay_ms]
## condition A's sends and the host's; B stands only at [method stand_late] when [param b_late].
func stand_up(loss: float = 0.0, delay_ms: int = 0, b_late: bool = false) -> bool:
	var port: int = await NetFixtures.host_and_wait(self, host)
	if port < 0:
		fail("the host could not take a port")
		return false
	for client: NetSession in [a, b]:
		if not await NetFixtures.join_and_wait(self, client, host, port):
			fail("a loopback handshake did not complete")
			return false
	if loss > 0.0 or delay_ms > 0:
		a_wire = _condition(a, loss, 11, delay_ms)
		host_wire = _condition(host, loss, 7, delay_ms)
	# The host sends snapshots only to machines standing in its epoch.
	var standing: Array[NetSession] = [a]
	if not b_late:
		standing.append(b)
	if not await NetFixtures.stand(self, host, standing):
		fail("the clients never stood in the host's epoch")
		return false
	var a_id: int = a.get_local_peer_id()
	host_links = [
		NetFixtures.add_seat_body(host, HOST_SEAT, 1, profile, true),
		NetFixtures.add_seat_body(host, A_SEAT, a_id, profile, false),
	]
	a_links = [
		NetFixtures.add_seat_body(a, HOST_SEAT, 1, profile, false),
		NetFixtures.add_seat_body(a, A_SEAT, a_id, profile, true),
	]
	b_links = [
		NetFixtures.add_seat_body(b, HOST_SEAT, 1, profile, false),
		NetFixtures.add_seat_body(b, A_SEAT, a_id, profile, false),
	]
	for links: Array[PlayerNetLink] in [host_links, a_links, b_links]:
		for seat: int in links.size():
			var body: PlayerController = links[seat].controller
			body.collision_mask = 1
			body.global_position = START[seat]
	host_keys = _give_keys(host_links[HOST_SEAT])
	a_keys = _give_keys(a_links[A_SEAT])
	await step_ticks(1)
	for session: NetSession in [host, a, b]:
		var stub: MatchController = _make_stub(session)
		_stubs.append(stub)
		for links: Array[PlayerNetLink] in [host_links, a_links, b_links]:
			for link: PlayerNetLink in links:
				if link.session == session:
					RunnerPower.of(link.controller).arm(rules, stub)
	# A predicts once the host's first snapshot has placed its body, and sends commands once it has heard the world.
	var placed: bool = await until(func() -> bool:
		return a_links[A_SEAT].is_predicting() and a.replicator.get_latest_tick() >= 0)
	if not placed:
		fail("client A's body was never placed by a snapshot")
	return placed


## B stands in the host's epoch now, and is sent the world from then on.
func stand_late() -> bool:
	return await NetFixtures.stand(self, host, [b])


func power_of(links: Array[PlayerNetLink], seat: int) -> RunnerPower:
	return RunnerPower.of(links[seat].controller)


func body_of(links: Array[PlayerNetLink], seat: int) -> PlayerController:
	return links[seat].controller


## What each machine has for [param seat]'s power: the authority's truth, then what A and B draw.
func drawn(seat: int) -> Array[int]:
	return [
		int(power_of(host_links, seat).get_active()),
		int(power_of(a_links, seat).get_shown()),
		int(power_of(b_links, seat).get_shown()),
	]


## True once all three machines have [param which] for [param seat].
func all_draw(seat: int, which: int) -> bool:
	var seen: Array[int] = drawn(seat)
	return seen[0] == which and seen[1] == which and seen[2] == which


func until(predicate: Callable, timeout_ms: int = WAIT_MS) -> bool:
	return await NetFixtures.poll_until(self, predicate, timeout_ms)


## Drop every unreliable packet [param wire] sends for [param ticks] ticks: a burst of loss.
func black_out(wire: LossyPeer, ticks: int) -> void:
	var before: float = wire.conditions.loss
	wire.conditions.loss = 1.0
	await step_ticks(ticks)
	wire.conditions.loss = before


## Stop the host's or A's machine for [param ms] real milliseconds, socket and scripts.
func freeze(session: NetSession, ms: float) -> void:
	await wires.freeze(session, ms)


## Freeze the host for [param ticks] ticks: it simulates nothing while its socket fills.
func stall_host(ticks: int) -> void:
	host.get_parent().process_mode = Node.PROCESS_MODE_DISABLED
	await step_ticks(ticks)
	host.get_parent().process_mode = Node.PROCESS_MODE_INHERIT


## Turn the knobs of the wire [param session] has had since its handshake: swapped in later,
## the engine forgets its peers and refuses every send.
func _condition(session: NetSession, loss: float, rng_seed: int, delay_ms: int) -> LossyPeer:
	var wire: LossyPeer = wires.of(session)
	if wire == null:
		return null
	wire.conditions.loss = loss
	wire.conditions.delay_ms = delay_ms
	wire.conditions.reseed(rng_seed)
	return wire


func _wrap(_state: NetTransport.ConnectionState, session: NetSession) -> void:
	var real: MultiplayerPeer = session.multiplayer.multiplayer_peer
	if wires.of(session) != null or real == null:
		return
	if real.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		return
	wires.wrap(session)


## A client's cat blast, drawn as [NetMatch] draws it in a scene: the rig has no scene of its own.
func _present_event(type: NetEvents.Type, payload: PackedByteArray, _tick: int, session: NetSession) -> void:
	if type == NetEvents.Type.CAT_BLAST:
		CatView.play_blast(session.get_parent(), NetCodec.event_point(payload, 1))


func _give_keys(link: PlayerNetLink) -> PressSource:
	var keys: PressSource = PressSource.new()
	keys.name = "Keys"
	link.controller.add_child(keys)
	link.controller.intent_source = keys
	link.local_source = keys
	link.refresh_role()
	return keys


## What [RunnerPower] needs of a match to build a decoy or a cat; off the tree, so it runs no match.
func _make_stub(session: NetSession) -> MatchController:
	var container: Node3D = Node3D.new()
	container.name = "Runners"
	session.get_parent().add_child(container)
	var stub: MatchController = MatchController.new()
	stub.runner_scene = load(TestFixtures.RUNNER_SCENE_PATH) as PackedScene
	stub.runner_container = container
	return stub
