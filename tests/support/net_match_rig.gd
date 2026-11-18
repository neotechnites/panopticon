extends RefCounted
## Two to four peers in one process, each running the shipped match scene in a physics world of its own.
## Built on NetFixtures; a viewport per peer keeps one machine's bodies out of another's space.

const MATCH_SCENE_PATH: String = "res://match/match.tscn"
const HUB_SCENE_PATH: String = "res://hub/hub.tscn"
const RULES_PATH: String = "res://match/rules/default_match_rules.tres"
const WORLD_NAME: String = "World"
const MATCH_NAME: String = "Match"
## Real milliseconds a loopback step may take before the rig gives up.
const STEP_TIMEOUT_MS: int = 4000
## Simulated seconds the host waits on a peer that is deliberately bound late.
const LATE_LAUNCH_TIMEOUT_SECONDS: float = 1.0

## A bad line on every peer, set before [method connect_peers]: the share of unreliable packets
## dropped, and real milliseconds every packet is held.
var wire_loss: float = 0.0
var wire_delay_ms: int = 0
## Per peer index, set before [method connect_peers]: what that peer's sends go through. A peer with
## an entry is wrapped from its handshake and can be frozen ([method freeze]).
var wire_conditions: Dictionary[int, NetConditions] = {}
var wires: NetWires = NetWires.new()
## The names the clients ask to be seated under, in joining order; one not given joins with none.
var client_names: PackedStringArray = PackedStringArray()

var sessions: Array[NetSession] = []
var matches: Array[Node3D] = []
var _case: Node = null
var _saved_settings: GameSettings = null


## Host plus [param clients] joined and seated. False rather than hanging.
func connect_peers(case: Node, clients: int) -> bool:
	_case = case
	# The match scene reads the player's settings; a test runs on defaults of its own.
	_saved_settings = SettingsStore.instance().settings
	SettingsStore.instance().settings = GameSettings.new()
	var host: NetSession = NetFixtures.make_peer(case, "Host", NetFixtures.settings())
	sessions.append(host)
	host.flow.scene_wanted.connect(_on_scene_wanted.bind(0))
	var port: int = NetFixtures.reserve_port()
	if port < 0 or host.host(port) != OK:
		return false
	_condition(host, 0)
	if not await NetFixtures.poll_until(case, func() -> bool: return host.is_established(), STEP_TIMEOUT_MS):
		return false
	host.lobby.open("Host")
	for i: int in clients:
		var client: NetSession = NetFixtures.make_peer(case, "Client%d" % (i + 1), NetFixtures.settings())
		sessions.append(client)
		client.flow.scene_wanted.connect(_on_scene_wanted.bind(i + 1))
		if i < client_names.size():
			client.lobby.local_name = client_names[i]
		if client.join("127.0.0.1", port) != OK:
			return false
		_condition(client, i + 1)
		var expected: int = host.get_peer_count() + 1
		if not await NetFixtures.poll_until(
			case,
			func() -> bool:
				return client.is_established() and host.get_peer_count() >= expected \
					and client.lobby.get_local_seat_index() >= 0,
			STEP_TIMEOUT_MS,
		):
			return false
	return true


## Wrap a peer's line as it opens, when [member wire_conditions], [member wire_loss] or
## [member wire_delay_ms] asks for a bad one.
func _condition(session: NetSession, peer: int) -> void:
	if wire_conditions.has(peer):
		wires.wrap(session, wire_conditions[peer])
		return
	if wire_loss <= 0.0 and wire_delay_ms <= 0:
		return
	var conditions: NetConditions = NetConditions.new(7 + peer * 4)
	conditions.loss = wire_loss
	conditions.delay_ms = wire_delay_ms
	wires.wrap(session, conditions)


## Stop peer [param peer] for [param ms] real milliseconds, socket and scripts (needs a wire).
func freeze(peer: int, ms: float) -> void:
	await wires.freeze(sessions[peer], ms)


## The settings every peer's scene will read; edit before [method launch].
func settings() -> GameSettings:
	return SettingsStore.instance().settings


## Fill to [param seats] with bots, name the guard (or -1 for the opening race), launch and bind every scene.
## A peer in [param late] is left unbound: the host starts without it and [method bind_late] brings it in.
func launch(seats: int, guard_seat: int, late: Array[int] = []) -> bool:
	var host: NetSession = sessions[0]
	var store: GameSettings = settings()
	store.skip_opening_race = guard_seat >= 0
	store.tower_seat_index = maxi(guard_seat, 0)
	store.prisoner_count = seats - 1
	var rules: MatchRules = (load(RULES_PATH) as MatchRules).duplicate() as MatchRules
	store.apply_to_match_rules(rules)
	host.lobby.set_rules(rules)
	host.lobby.fill_with_bots(seats)
	if guard_seat >= 0:
		host.lobby.assign_guard(guard_seat)
	else:
		host.lobby.clear_roles()
	for seat: LobbySeat in host.lobby.get_occupied_seats():
		host.lobby.set_ready(seat.index, true)
	if not late.is_empty():
		host.get_settings().launch_timeout_seconds = LATE_LAUNCH_TIMEOUT_SECONDS
	if not host.lobby.launch():
		return false
	for session: NetSession in sessions:
		if not await NetFixtures.poll_until(
			_case,
			func() -> bool: return session.lobby.get_phase() == NetLobby.Phase.IN_MATCH,
			STEP_TIMEOUT_MS,
		):
			return false
	matches.resize(sessions.size())
	for peer: int in sessions.size():
		if not late.has(peer):
			matches[peer] = _bind(sessions[peer])
	return await NetFixtures.poll_until(_case, _all_started, STEP_TIMEOUT_MS)


## Bind a peer [method launch] left out, and wait for the host's catch-up to land on it.
func bind_late(peer: int) -> bool:
	matches[peer] = _bind(sessions[peer])
	return await NetFixtures.poll_until(_case, func() -> bool: return net_match(peer).has_started(), STEP_TIMEOUT_MS)


func _all_started() -> bool:
	var everyone: bool = true
	for peer: int in matches.size():
		if matches[peer] == null:
			everyone = false
		elif not net_match(peer).has_started():
			return false
	return not everyone or sessions[0].lobby.get_unstanding_peers().is_empty()


## A rematch relaunches the match scene on every machine already in one: the rig stands the new one
## where [SessionFlow] would. A peer held back keeps waiting for [method bind_late].
func _on_scene_wanted(path: String, peer: int) -> void:
	if path == MATCH_SCENE_PATH and peer < matches.size() and matches[peer] != null and matches[peer].name == MATCH_NAME:
		_rebind.call_deferred(peer)


## Every bound peer still in the session stands in a started match under a newer epoch than
## [param epoch]: a rematch.
func wait_rematch(epoch: int) -> bool:
	return await wait_for(func() -> bool:
		for peer: int in matches.size():
			if matches[peer] == null or not sessions[peer].is_established():
				continue
			var net: NetMatch = net_match(peer)
			if net.get_epoch() == epoch or net.get_epoch() != sessions[0].lobby.get_epoch() or not net.has_started():
				return false
		return true)


func _rebind(peer: int) -> void:
	var world: Node = matches[peer].get_parent()
	world.get_parent().remove_child(world)
	world.queue_free()
	matches[peer] = _bind(sessions[peer])


## The shipped match scene for one peer, in its own world, at the same path on every peer.
func _bind(session: NetSession) -> Node3D:
	var world: SubViewport = SubViewport.new()
	world.name = WORLD_NAME
	world.own_world_3d = true
	world.size = Vector2i(64, 64)
	session.get_parent().add_child(world)
	var scene: Node3D = (load(MATCH_SCENE_PATH) as PackedScene).instantiate() as Node3D
	scene.name = MATCH_NAME
	TestFixtures.silence_human_input(scene)
	(scene.get_node("NetMatch") as NetMatch).session_path = session.get_path()
	_give_test_input(scene.get_node("Player") as PlayerController)
	# The death views switch themselves off headless; these tests read them.
	(scene.get_node("DeathScreen") as MatchDeathScreen).headless_inert = false
	(scene.get_node("SpectatorView") as FxSpectatorView).headless_inert = false
	var audio: Node = scene.get_node_or_null("GameAudio")
	if audio != null:
		audio.free()
	var music: Node = scene.get_node_or_null("Music")
	if music != null:
		music.free()
	world.add_child(scene)
	return scene


## The shipped hub on every peer instead of a match: no launch, one body per seated human.
func bind_hubs() -> void:
	matches.resize(sessions.size())
	for peer: int in sessions.size():
		var world: SubViewport = SubViewport.new()
		world.name = WORLD_NAME
		world.own_world_3d = true
		world.size = Vector2i(64, 64)
		sessions[peer].get_parent().add_child(world)
		var hub: Node3D = (load(HUB_SCENE_PATH) as PackedScene).instantiate() as Node3D
		hub.name = "Hub"
		TestFixtures.silence_human_input(hub)
		var lobby: HubLobby = hub.get_node("HubLobby") as HubLobby
		lobby.changes_scene = false
		lobby.session_path = sessions[peer].get_path()
		(hub.get_node("NetMatch") as NetMatch).session_path = sessions[peer].get_path()
		_give_test_input(hub.get_node("Player") as PlayerController)
		var audio: Node = hub.get_node_or_null("GameAudio")
		if audio != null:
			audio.free()
		world.add_child(hub)
		matches[peer] = hub


## Driven by a bot source, so a test can push the local body without a keyboard.
func _give_test_input(body: PlayerController) -> void:
	var input: BotIntentSource = BotIntentSource.new()
	input.name = "TestInput"
	input.shove_enabled = false
	body.add_child(input)
	body.intent_source = input


func controller(peer: int) -> MatchController:
	return matches[peer].get_node("MatchController") as MatchController


func net_match(peer: int) -> NetMatch:
	return matches[peer].get_node("NetMatch") as NetMatch


## The participant in [param slot] as [param peer] holds it.
func participant(peer: int, slot: int) -> MatchParticipant:
	return controller(peer).get_participants()[slot]


## [param peer]'s copy of the body in [param slot].
func body(peer: int, slot: int) -> PlayerController:
	return participant(peer, slot).body


func avatar(peer: int, slot: int) -> PrisonerAvatar:
	return PrisonerAvatar.of(body(peer, slot))


## The limp-body node of [param peer]'s copy of [param slot].
func ragdoll(peer: int, slot: int) -> Node:
	return avatar(peer, slot).get_node("Ragdoll")


func peer_count() -> int:
	return sessions.size()


## The slot [param peer]'s own player holds.
func local_slot(peer: int) -> int:
	var human: MatchParticipant = controller(peer).get_human_participant()
	return human.index if human != null else -1


## Hold a move direction on [param peer]'s own body.
func drive(peer: int, direction: Vector2) -> void:
	var input: BotIntentSource = (matches[peer].get_node("Player") as PlayerController).intent_source as BotIntentSource
	if input != null:
		input.command.move_direction = direction


## Run frames until [param predicate], bounded by the wall clock.
func wait_for(predicate: Callable, timeout_ms: int = STEP_TIMEOUT_MS) -> bool:
	return await NetFixtures.poll_until(_case, predicate, timeout_ms)


## Leave every session and hand the player's settings back.
func close() -> void:
	for i: int in range(sessions.size() - 1, -1, -1):
		if sessions[i] != null:
			sessions[i].leave()
	wires.clear()
	# Static, and read by the result screen in every other test file.
	HubLobby.returns_to_hub = false
	if _saved_settings != null:
		SettingsStore.instance().settings = _saved_settings
		_saved_settings = null
