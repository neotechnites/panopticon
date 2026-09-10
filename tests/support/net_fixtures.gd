class_name NetFixtures
extends RefCounted

## Builders for the networking tests: two real sessions, on two real UDP
## sockets, inside one headless process.
##
## [b]Why this is possible at all[/b]
##
## Godot's high-level multiplayer is usually described as one API per process,
## which would make a loopback test need two Godot instances, a launcher and a
## way to get a verdict back out of a child. It does not: [SceneTree] holds a
## [MultiplayerAPI] per [b]branch[/b] of the tree, so giving
## [code]/root/Case/Host[/code] and [code]/root/Case/Client[/code] one each
## gives two independent sessions that can only talk to one another through a
## socket -- which is exactly the thing under test.
##
## RPCs then resolve by node path [i]relative to each branch's root[/i], which
## is why [method make_peer] puts an identically shaped subtree under both.
## That is also the real constraint on the match layer: a body's node path must
## be the same on every machine, so bodies are named after their seat and never
## after their player.
##
## [b]Nothing here may wait forever[/b]
##
## A socket that never answers is a suite that never finishes, and this project
## runs unattended. Every wait goes through [method poll_until], which is bounded
## by the WALL clock and returns false rather than hanging. Wall clock, not
## simulated: the runner compresses simulated time fiftyfold and the network
## stack has not heard about it. This is the one place in the suite where
## [method Time.get_ticks_msec] is the right instrument.

const SESSION_SCENE_PATH: String = "res://scenes/net/net_session.tscn"
const LINK_SCENE_PATH: String = "res://scenes/net/player_net_link.tscn"
const SETTINGS_PATH: String = "res://resources/net/default_net_settings.tres"

## Longest any single wait may take, in real milliseconds. A loopback handshake
## is a couple of milliseconds; a second is four hundred times that, so
## overrunning it means something is broken rather than slow.
const WAIT_TIMEOUT_MS: int = 1000

## Ports are picked at random from this range and probed before use.
##
## Above the ephemeral range macOS and Linux hand out, so a test does not lose
## a coin toss with a browser tab, and randomised so that two runs of this suite
## at once -- which is what happens the moment anything runs tests in
## parallel -- do not collide. See [method reserve_port].
const PORT_RANGE_START: int = 40000
const PORT_RANGE_END: int = 49000

## Attempts before [method reserve_port] gives up.
const PORT_ATTEMPTS: int = 20


## A private copy of the shipped network settings.
##
## A copy because the [code].tres[/code] is one instance for the whole process:
## a test that turns interpolation off in the shared resource turns it off for
## every test that runs after it, in every other file.
static func settings() -> NetSettings:
	return (load(SETTINGS_PATH) as NetSettings).duplicate() as NetSettings


## A free UDP port, or -1 if the machine is somehow out of them.
##
## Bound and released rather than assumed. Picking a random port and hoping is
## how a suite acquires a test that fails once a fortnight on somebody else's
## machine, and a networking flake is the most expensive kind because nobody
## believes it the first three times.
static func reserve_port() -> int:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	for _attempt: int in PORT_ATTEMPTS:
		var candidate: int = rng.randi_range(PORT_RANGE_START, PORT_RANGE_END)
		var probe: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
		if probe.create_server(candidate, 1) == OK:
			probe.close()
			return candidate
	return -1


## Build one machine's branch: a node with its own [MultiplayerAPI] and a real
## [NetSession] scene under it.
##
## [param branch_name] must differ between peers -- it is the node's name -- and
## everything below it must not, because that is what the RPC path resolution
## matches on.
static func make_peer(case: Node, branch_name: String, net_settings: NetSettings) -> NetSession:
	var branch: Node = Node.new()
	branch.name = branch_name
	case.add_child(branch)
	# Its own API, so the two sessions in this process are as separate as two
	# machines and can only reach each other through the socket.
	case.get_tree().set_multiplayer(MultiplayerAPI.create_default_interface(), branch.get_path())

	var session: NetSession = (load(SESSION_SCENE_PATH) as PackedScene).instantiate() as NetSession
	session.settings = net_settings
	branch.add_child(session)
	return session


## The lobby that came with a session built by [method make_peer].
static func lobby_of(session: NetSession) -> NetLobby:
	return session.lobby


## The replicator that came with a session built by [method make_peer].
static func replicator_of(session: NetSession) -> NetReplicator:
	return session.replicator


## Add a body and its [PlayerNetLink] to a peer's branch, at a path that is the
## same on every peer.
##
## [param seat_index] names the body -- the node is called
## [code]Seat0[/code], [code]Seat1[/code] and so on -- because a body's path has
## to match across machines and a player's name does not.
##
## [param owner_peer_id] is who may drive it: a peer id for a remote human, or 0
## for a bot or for this machine's own body. That one number is the whole
## difference between the two, which is the property the match layer depends on.
##
## [param drive_locally] is whether THIS machine supplies the input -- true for
## a bot on the authority and for a client's own body, false for everybody
## else's. It is a separate argument rather than something derived here because
## the match layer has to make the same decision explicitly, and a fixture that
## guessed would be testing the guess.
static func add_seat_body(
	session: NetSession,
	seat_index: int,
	owner_peer_id: int,
	profile: MovementProfile,
	drive_locally: bool,
) -> PlayerNetLink:
	var body: PlayerController = TestFixtures.make_bot_player(profile)
	body.name = "Seat%d" % seat_index
	# Off every layer: the two peers in this process share one physics world,
	# so seat 0's body on the host and seat 0's body on the client would
	# otherwise stand inside each other and shove the thing under test around.
	body.collision_layer = 0
	body.collision_mask = 0
	session.get_parent().add_child(body)

	var link: PlayerNetLink = (load(LINK_SCENE_PATH) as PackedScene).instantiate() as PlayerNetLink
	link.session = session
	link.replicator = session.replicator
	link.controller = body
	link.seat_index = seat_index
	link.owner_peer_id = owner_peer_id
	link.local_source = body.intent_source if drive_locally else null
	body.add_child(link)
	return link


## Run frames until [param predicate] is true, or until the wall clock runs out.
##
## Returns whether it came true. Process frames, not physics frames: polling the
## socket is what [MultiplayerAPI] does on the idle frame, so a test that waited
## on physics alone could sit through a thousand ticks without ever reading a
## packet.
static func poll_until(case: Node, predicate: Callable, timeout_ms: int = WAIT_TIMEOUT_MS) -> bool:
	var tree: SceneTree = case.get_tree()
	var deadline_ms: int = Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline_ms:
		if bool(predicate.call()):
			return true
		await tree.process_frame
	return bool(predicate.call())


## Host on [param session] and wait for a client to be able to reach it.
## Returns the port, or -1 if nothing could be hosted.
static func host_and_wait(case: Node, session: NetSession) -> int:
	var port: int = reserve_port()
	if port < 0:
		return -1
	if session.host(port) != OK:
		return -1
	var up: bool = await poll_until(case, func() -> bool: return session.is_established())
	return port if up else -1


## Join [param port] from [param session] and wait for the handshake, on both
## ends: a client that is CONNECTED before the host has seen it would let a test
## send a packet into a session the host does not yet believe in.
static func join_and_wait(case: Node, session: NetSession, host_session: NetSession, port: int) -> bool:
	if session.join("127.0.0.1", port) != OK:
		return false
	var expected_peers: int = host_session.get_peer_count() + 1
	return await poll_until(
		case,
		func() -> bool:
			return session.is_established() and host_session.get_peer_count() >= expected_peers
	)
