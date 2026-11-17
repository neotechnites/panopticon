extends TestCase

## The host's wait for a slow client's launch acknowledgement: the bodies built for the match stand
## stacked at the scene default until the controller places them, and must simulate nothing there.

const LAUNCH_TIMEOUT_SECONDS: float = 1.0
const SEATS: int = 4
## Faster upward than a jump, a pad or a shove throws anybody.
const FLUNG_SPEED: float = 40.0

var _host: NetSession
var _client: NetSession


func before_each() -> void:
	_host = NetFixtures.make_peer(self, "Host", NetFixtures.settings())
	_client = NetFixtures.make_peer(self, "Client", NetFixtures.settings())


func after_each() -> void:
	if _client != null:
		_client.leave()
	if _host != null:
		_host.leave()


func test_no_body_moves_or_is_thrown_while_the_host_waits_for_a_client() -> void:
	var host_lobby: NetLobby = NetFixtures.lobby_of(_host)
	var client_lobby: NetLobby = NetFixtures.lobby_of(_client)
	if not await _launch_with_one_client(host_lobby, client_lobby):
		return
	var host_match: NetMatch = _bind_match(_host)
	assert_false(host_match.has_started(), "the host waits for the client's acknowledgement")
	var bodies: Array[PlayerController] = []
	var placed: Array[Vector3] = []
	for child: Node in host_match.get_children():
		var link: PlayerNetLink = child as PlayerNetLink
		if link != null and link.controller != null:
			bodies.append(link.controller)
			placed.append(link.controller.global_position)
	assert_eq_int(bodies.size(), SEATS, "one body per seat")

	# Most of the wait: every body is where it was built, having simulated nothing.
	await step_ticks(40)
	assert_false(host_match.has_started(), "still waiting")
	var drift: float = 0.0
	for i: int in bodies.size():
		drift = maxf(drift, bodies[i].global_position.distance_to(placed[i]))
	assert_true(drift < 0.01, "no unplaced body moved during the wait (worst drift %.2f m)" % drift)

	if not await NetFixtures.poll_until(self, func() -> bool: return host_match.has_started(), 3000):
		fail("the host never gave up waiting")
		return
	# Placed and woken: nobody leaves the placement carrying speed from the stack.
	var fastest: float = 0.0
	for tick: int in 40:
		await step_ticks(1)
		for body: PlayerController in bodies:
			fastest = maxf(fastest, body.velocity.y)
	assert_true(fastest < FLUNG_SPEED, "no body is thrown upward at the start (fastest %.1f m/s)" % fastest)


## Host, one client and bots up to [constant SEATS], launched, and the client told so.
func _launch_with_one_client(host_lobby: NetLobby, client_lobby: NetLobby) -> bool:
	_host.get_settings().launch_timeout_seconds = LAUNCH_TIMEOUT_SECONDS
	var port: int = await NetFixtures.host_and_wait(self, _host)
	if port < 0:
		fail("the host could not take a port")
		return false
	host_lobby.open("Host")
	if not await NetFixtures.join_and_wait(self, _client, _host, port):
		fail("the loopback handshake did not complete")
		return false
	if not await NetFixtures.poll_until(
		self, func() -> bool: return client_lobby.get_local_seat_index() >= 0
	):
		fail("the client was never seated")
		return false
	host_lobby.fill_with_bots(SEATS)
	host_lobby.assign_guard(0)
	host_lobby.set_ready(client_lobby.get_local_seat_index(), true)
	host_lobby.set_ready(0, true)
	if not host_lobby.launch():
		fail("the lobby did not launch")
		return false
	return true


## A match world and a NetMatch bound to [param session], under its branch.
func _bind_match(session: NetSession) -> NetMatch:
	var world: BotMatchWorld = BotMatchWorld.new()
	session.get_parent().add_child(world)
	world.build(TestFixtures.match_rules())
	var net_match: NetMatch = NetMatch.new()
	net_match.name = "NetMatch"
	net_match.controller = world.get_controller()
	net_match.runner_scene = load(TestFixtures.RUNNER_SCENE_PATH) as PackedScene
	net_match.runner_container = world.get_runner_container()
	net_match.session_path = session.get_path()
	world.add_child(net_match)
	return net_match
