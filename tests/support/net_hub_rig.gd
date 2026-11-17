extends TestCase

## Three machines in one process, each standing in the shipped hub: a host and two clients on
## real sockets. Machine m owns seat m, so one index names both. [LossyPeer] conditions the wire.

const HUB_SCENE_PATH: String = "res://hub/hub.tscn"
const HOST: int = 0
const A: int = 1
const B: int = 2
const BRANCHES: PackedStringArray = ["Host", "ClientA", "ClientB"]
## Long enough for the slowest thing waited on: a 5 s power on a conditioned wire.
const WAIT_MS: int = 8000
## A turn is checked this long after it is asked for: past a round trip on the slowest wire used.
const TURN_SETTLE_TICKS: int = 30
const TURN_ATTEMPTS: int = 5
## The hub cat the tests lift: on open floor, away from the spawns.
const HUB_CAT: String = "Cat5"
const CAT_POWER: int = MatchRules.RunnerAbility.CAT_GRENADE

## Per machine: its session, its hub (null until built) and its local body's device.
var sessions: Array[NetSession] = [null, null, null]
var hubs: Array[Node3D] = [null, null, null]
var keys: Array[PressSource] = [null, null, null]
## The conditioned wires, null on a clean line: A's sends (intent) and the host's (snapshots).
## In place from the handshake.
var a_wire: LossyPeer
var host_wire: LossyPeer

var _port: int = -1
var _wired: bool = false
var _loss: float = 0.0
var _delay_ms: int = 0
var _saved_hz: int = 0
var _saved_scale: float = 1.0


func before_each() -> void:
	# Real time: a socket has not heard about the runner's compressed clock.
	_saved_hz = Engine.physics_ticks_per_second
	_saved_scale = Engine.time_scale
	Engine.physics_ticks_per_second = int(SIM_HZ)
	Engine.time_scale = 1.0
	process_physics_priority = -100
	for machine: int in BRANCHES.size():
		sessions[machine] = NetFixtures.make_peer(self, BRANCHES[machine], NetFixtures.settings())


## Every machine reads its socket once a tick, whatever the frame rate.
func _physics_process(_delta: float) -> void:
	for session: NetSession in sessions:
		if session != null and session.multiplayer.has_multiplayer_peer():
			session.multiplayer.poll()


func after_each() -> void:
	Engine.physics_ticks_per_second = _saved_hz
	Engine.time_scale = _saved_scale
	HubLobby.returns_to_hub = false
	for machine: int in [B, A, HOST]:
		if sessions[machine] != null:
			sessions[machine].leave()
	# A wire's forwarding lambdas hold it alive past exit; let go of them.
	for wire: LossyPeer in [a_wire, host_wire]:
		if wire == null:
			continue
		var real: MultiplayerPeer = wire.get("_real") as MultiplayerPeer
		for forwarded: Signal in [real.peer_connected, real.peer_disconnected]:
			for link: Dictionary in forwarded.get_connections():
				forwarded.disconnect(link["callable"] as Callable)


## Host and A (and B unless [param machines] is 2) connected, seated and standing in the hub.
## [param loss] and [param delay_ms] condition A's sends and the host's. False after failing loudly.
func stand_up(loss: float = 0.0, delay_ms: int = 0, machines: int = 3) -> bool:
	_port = await NetFixtures.host_and_wait(self, sessions[HOST])
	if _port < 0:
		fail("the host could not take a port")
		return false
	_wired = loss > 0.0 or delay_ms > 0
	_loss = loss
	_delay_ms = delay_ms
	if _wired:
		host_wire = _condition(sessions[HOST], loss, 7, delay_ms)
	sessions[HOST].lobby.open("Host")
	for machine: int in range(1, machines):
		if not await _join(machine):
			return false
	for machine: int in machines:
		_make_hub(machine)
	return await settle(machines)


## B arrives while the others already stand in the hub: every machine rebuilds its bodies.
## B's own hub comes up [param load_ticks] later, as a scene that takes time to load does.
func join_late(machine: int = B, load_ticks: int = 0) -> bool:
	if not await connect_late(machine):
		return false
	await step_ticks(load_ticks)
	return await load_hub(machine)


## The first half of [method join_late]: [param machine] is connected and seated, with no hub yet.
func connect_late(machine: int = B) -> bool:
	return await _join(machine)


## The second half: [param machine]'s hub stands and every machine has a body per seat.
func load_hub(machine: int = B) -> bool:
	_make_hub(machine)
	return await settle(machine + 1)


## [param machine] quits: its session ends and its hub goes with it.
func leave(machine: int) -> void:
	sessions[machine].leave()
	hubs[machine].queue_free()
	hubs[machine] = null


## Wait until the first [param machines] machines each hold a body per seat, every client predicts
## its own and every machine stands in the hub. Bodies are taken off each other's layers as each roster is built.
func settle(machines: int = 3) -> bool:
	var built: bool = await until(
		func() -> bool:
			for machine: int in machines:
				if ctrl(machine).get_participants().size() != machines:
					return false
			return true
	)
	if not built:
		fail("not every machine built a body per seat: %s" % str(roster_sizes()))
		return false
	var placed: bool = await until(
		func() -> bool:
			for machine: int in range(1, machines):
				var link: PlayerNetLink = net(machine).get_local_link()
				if link == null or not link.is_predicting():
					return false
			return true
	)
	if not placed:
		fail("a client's own body was never placed by a snapshot")
		return false
	var standing: bool = await until(func() -> bool: return sessions[HOST].lobby.get_unstanding_peers().is_empty())
	if not standing:
		fail("not every machine's hub stood: %s" % str(sessions[HOST].lobby.get_unstanding_peers()))
	return standing


func roster_sizes() -> Array[int]:
	var sizes: Array[int] = []
	for hub: Node3D in hubs:
		sizes.append(-1 if hub == null else ctrl(hubs.find(hub)).get_participants().size())
	return sizes


func ctrl(machine: int) -> MatchController:
	return hubs[machine].get_node("MatchController") as MatchController


func net(machine: int) -> NetMatch:
	return hubs[machine].get_node("NetMatch") as NetMatch


## Machine [param machine]'s body for [param seat]: its own is the scene's, the rest are spawned.
func body(machine: int, seat: int) -> PlayerController:
	var path: String = "Player" if machine == seat else "Runners/Seat%d" % seat
	return hubs[machine].get_node_or_null(path) as PlayerController


func power(machine: int, seat: int) -> RunnerPower:
	return RunnerPower.of(body(machine, seat))


## Machine [param machine]'s copy of the hub cat named [param cat_name] (Cat1..Cat6).
func cat(machine: int, cat_name: String) -> HubCat:
	return hubs[machine].get_node_or_null("HubWorld/Cats/" + cat_name) as HubCat


func cats(machine: int) -> Array[HubCat]:
	var found: Array[HubCat] = []
	for child: Node in hubs[machine].get_node("HubWorld/Cats").get_children():
		if child is HubCat:
			found.append(child as HubCat)
	return found


## The node that draws power cats on [param machine], or null where the build has none per machine.
func relay(machine: int) -> Node:
	return sessions[machine].get_parent().get_node_or_null("CatGrenadeRelay")


## The host's live power cat for [param seat], or null.
func grenade(seat: int) -> CatGrenade:
	var held: Variant = power(HOST, seat).get("_cat")
	return held as CatGrenade if is_instance_valid(held) else null


## What each machine has for [param seat]'s power: the authority's truth, then what A and B draw.
func drawn(seat: int) -> Array[int]:
	return [
		int(power(HOST, seat).get_active()),
		int(power(A, seat).get_shown()),
		int(power(B, seat).get_shown()),
	]


func all_draw(seat: int, which: int) -> bool:
	var seen: Array[int] = drawn(seat)
	return seen[0] == which and seen[1] == which and seen[2] == which


## Stand [param seat]'s body at [param at] facing [param yaw] and wait for the host and its
## owner to agree. The spot is set on both; the turn is a look on the owner's device, as a mouse is.
func stand(seat: int, at: Vector3, yaw: float) -> bool:
	for machine: int in ([HOST] if seat == HOST else [HOST, seat]):
		var target: PlayerController = body(machine, seat)
		target.global_position = at
		target.velocity = Vector3.ZERO
	# Turned by what the host still lacks, and again if a correction moved the view meanwhile.
	for _attempt: int in TURN_ATTEMPTS:
		(keys[seat] as Keys).turn(angle_difference(body(HOST, seat).rotation.y, yaw))
		await step_ticks(TURN_SETTLE_TICKS)
		if is_stood(seat, at, yaw):
			return true
	return false


## True while [param seat]'s body is within [param slack] of [param at] on the host and on its
## owner's machine, and both have it facing [param yaw].
func is_stood(seat: int, at: Vector3, yaw: float, slack: float = 0.3) -> bool:
	for machine: int in ([HOST] if seat == HOST else [HOST, seat]):
		var target: PlayerController = body(machine, seat)
		if flat_distance(target.global_position, at) > slack:
			return false
		if absf(angle_difference(target.rotation.y, yaw)) > 0.1:
			return false
	return true


## The yaw that faces a body along [param direction].
static func yaw_towards(direction: Vector3) -> float:
	return atan2(-direction.x, -direction.z)


static func flat_distance(from: Vector3, to: Vector3) -> float:
	return Vector2(from.x - to.x, from.z - to.z).length()


## A one-element tally of how often [param emitter] fires from now on.
func count(emitter: Signal) -> Array[int]:
	var tally: Array[int] = [0]
	emitter.connect(func() -> void: tally[0] += 1)
	return tally


func until(predicate: Callable, timeout_ms: int = WAIT_MS) -> bool:
	return await NetFixtures.poll_until(self, predicate, timeout_ms)


## Drop every unreliable packet [param wire] sends for [param ticks] ticks: a burst of loss.
func black_out(wire: LossyPeer, ticks: int) -> void:
	var before: float = float(wire.get("_loss"))
	wire.set("_loss", 1.0)
	await step_ticks(ticks)
	wire.set("_loss", before)


# --- Steps: the cats ---------------------------------------------------------

## A presses 5, facing the middle of the hub, and each machine draws [param seen] cats. The
## host's live cat, or null after failing.
func hold_power_cat(seen: Array[int] = [0, 1, 1]) -> CatGrenade:
	if relay(HOST) == null or relay(A) == null or relay(B) == null:
		fail("no cat relay beside each machine's session (API absent)")
		return null
	var at: Vector3 = body(HOST, A).global_position
	var yaw: float = yaw_towards(Vector3(-at.x, 0.0, -at.z).normalized())
	if not assert_true(await stand(A, at, yaw), "A faces the middle of the hub on the host and on A"):
		return null
	keys[A].tap_slot(CAT_POWER)
	var held: bool = await until(
		func() -> bool: return grenade(A) != null and cats_drawn() == seen
	)
	if not assert_true(held, "A's 5 put a cat in the hands of the host's copy of A; drawn: %s" % str(cats_drawn())):
		return null
	assert_true(grenade(A).carrier == body(HOST, A), "and it is carried by A's body")
	assert_eq_int(int(power(HOST, A).get_active()), CAT_POWER, "the host runs the cat power for A")
	return grenade(A)


## How many power cats each machine draws through its relay.
func cats_drawn() -> Array[int]:
	var seen: Array[int] = []
	for machine: int in 3:
		var shown: Dictionary = relay(machine).get("_shown")
		seen.append(shown.size())
	return seen


## The power cat [param machine] offers its own player the pet for, 0 for none.
func pet_offer(machine: int) -> int:
	return int(relay(machine).get("_held_id"))


## True while [param machine] offers its own player the pet for the hub cat.
func holds_locally(machine: int) -> bool:
	return bool(cat(machine, HUB_CAT).get("_local_held"))


## Stand [param seat] in reach of the hub cat, facing it, and shove. False after failing.
func lift_hub_cat(seat: int) -> bool:
	var target: Vector3 = cat(HOST, HUB_CAT).global_position
	var from: Vector3 = body(HOST, seat).global_position
	var toward: Vector3 = Vector3(target.x - from.x, 0.0, target.z - from.z).normalized()
	var stand_at: Vector3 = target - toward * 1.5
	stand_at.y = from.y + 0.1
	var yaw: float = yaw_towards(toward)
	var stood: bool = await stand(seat, stand_at, yaw)
	if not assert_true(stood, "seat %d stands in reach of the hub cat, facing it" % seat):
		return false
	keys[seat].tap(&"shove_pressed")
	var lifted: bool = await until(func() -> bool: return HubCat.is_carrying(body(HOST, seat)))
	if not assert_true(lifted, "on the host, seat %d's body carries a hub cat" % seat):
		return false
	return assert_true(
		cat(HOST, HUB_CAT).get("_carrier") == body(HOST, seat),
		"and it is the host's own copy of the cat in reach",
	)


# --- Building -----------------------------------------------------------------

func _join(machine: int) -> bool:
	var session: NetSession = sessions[machine]
	var expected: int = sessions[HOST].get_peer_count() + 1
	if session.join("127.0.0.1", _port) != OK:
		fail("machine %d could not start joining" % machine)
		return false
	if _wired and machine == A:
		a_wire = _condition(session, _loss, 11, _delay_ms)
	var joined: bool = await until(
		func() -> bool:
			return session.is_established() and sessions[HOST].get_peer_count() >= expected
	)
	if not joined:
		fail("a loopback handshake did not complete")
		return false
	var seated: bool = await until(func() -> bool: return session.lobby.get_local_seat() != null)
	if not seated or session.lobby.get_local_seat_index() != machine:
		fail("machine %d was not given seat %d" % [machine, machine])
		return false
	return true


## Wrap [param session]'s socket. Only before it has a peer: swapped in under a live
## connection, the engine forgets who it is connected to.
func _condition(session: NetSession, loss: float, rng_seed: int, delay_ms: int) -> LossyPeer:
	var real: MultiplayerPeer = session.multiplayer.multiplayer_peer
	var wire: LossyPeer = LossyPeer.new(real, loss, rng_seed, delay_ms)
	session.multiplayer.multiplayer_peer = wire
	return wire


## The shipped hub on [param machine]'s branch, named Hub everywhere so node paths agree.
func _make_hub(machine: int) -> void:
	var session: NetSession = sessions[machine]
	var hub: Node3D = (load(HUB_SCENE_PATH) as PackedScene).instantiate() as Node3D
	hub.name = "Hub"
	TestFixtures.silence_human_input(hub)
	var lobby: HubLobby = hub.get_node("HubLobby") as HubLobby
	lobby.changes_scene = false
	lobby.session_path = session.get_path()
	(hub.get_node("NetMatch") as NetMatch).session_path = session.get_path()
	# Before the hub enters the tree: NetMatch reads the body's source when it builds the link.
	var own: PlayerController = hub.get_node("Player") as PlayerController
	var device: Keys = Keys.new()
	device.name = "Keys"
	own.add_child(device)
	own.intent_source = device
	keys[machine] = device
	# One world per process: a second WorldEnvironment or audio director is an engine complaint.
	# The pause menu is settings UI with its own tests; nothing here opens it.
	for extra: String in ["HubWorld/WorldEnvironment", "GameAudio", "PauseMenu"]:
		var node: Node = hub.get_node_or_null(extra)
		if node != null:
			node.free()
	# Every roster this hub builds comes off the shared world's body layer the tick it is built.
	var controller: MatchController = hub.get_node("MatchController") as MatchController
	controller.match_started.connect(func(_count: int) -> void: _untangle(controller))
	hubs[machine] = hub
	session.get_parent().add_child(hub)


## All three machines' bodies share one physics world; none may push another.
func _untangle(controller: MatchController) -> void:
	for participant: MatchParticipant in controller.get_participants():
		participant.home_collision_layer = 0
		if participant.body != null:
			participant.body.collision_layer = 0


## A [PressSource] that can also turn its body: one look, spent on the next tick polled.
class Keys:
	extends PressSource

	var _turn: float = 0.0

	## Turn the view by [param radians] of yaw on the next tick.
	func turn(radians: float) -> void:
		_turn += radians

	func poll(delta: float) -> MoveIntent:
		var intent: MoveIntent = super(delta)
		# The body applies a look as rotate_y(-x).
		intent.look_delta = Vector2(-_turn, 0.0)
		_turn = 0.0
		return intent
