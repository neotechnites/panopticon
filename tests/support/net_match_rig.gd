extends RefCounted
## Two to four peers in one process, each running the shipped match scene in a physics world of its own.
## Built on NetFixtures; a viewport per peer keeps one machine's bodies out of another's space.

const MATCH_SCENE_PATH: String = "res://match/match.tscn"
const RULES_PATH: String = "res://match/rules/default_match_rules.tres"
const WORLD_NAME: String = "World"
const MATCH_NAME: String = "Match"
## Real milliseconds a loopback step may take before the rig gives up.
const STEP_TIMEOUT_MS: int = 4000

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
	var port: int = await NetFixtures.host_and_wait(case, host)
	if port < 0:
		return false
	host.lobby.open("Host")
	for i: int in clients:
		var client: NetSession = NetFixtures.make_peer(case, "Client%d" % (i + 1), NetFixtures.settings())
		sessions.append(client)
		if not await NetFixtures.join_and_wait(case, client, host, port):
			return false
		if not await NetFixtures.poll_until(
			case, func() -> bool: return client.lobby.get_local_seat_index() >= 0, STEP_TIMEOUT_MS
		):
			return false
	return true


## The settings every peer's scene will read; edit before [method launch].
func settings() -> GameSettings:
	return SettingsStore.instance().settings


## Fill to [param seats] with bots, name the guard (or -1 for the opening race), launch and bind every scene.
func launch(seats: int, guard_seat: int) -> bool:
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
	if not host.lobby.launch():
		return false
	for session: NetSession in sessions:
		if not await NetFixtures.poll_until(
			_case,
			func() -> bool: return session.lobby.get_phase() == NetLobby.Phase.LAUNCHING,
			STEP_TIMEOUT_MS,
		):
			return false
	for session: NetSession in sessions:
		matches.append(_bind(session))
	return await NetFixtures.poll_until(_case, _all_started, STEP_TIMEOUT_MS)


func _all_started() -> bool:
	for scene: Node3D in matches:
		if not net_match(matches.find(scene)).has_started():
			return false
	return sessions[0].lobby.get_phase() == NetLobby.Phase.IN_MATCH


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
	# Driven by a bot source, so a test can push the local body without a keyboard.
	var body: PlayerController = scene.get_node("Player") as PlayerController
	var input: BotIntentSource = BotIntentSource.new()
	input.name = "TestInput"
	input.shove_enabled = false
	body.add_child(input)
	body.intent_source = input
	var audio: Node = scene.get_node_or_null("GameAudio")
	if audio != null:
		audio.free()
	var music: Node = scene.get_node_or_null("Music")
	if music != null:
		music.free()
	world.add_child(scene)
	return scene


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
	if _saved_settings != null:
		SettingsStore.instance().settings = _saved_settings
		_saved_settings = null
