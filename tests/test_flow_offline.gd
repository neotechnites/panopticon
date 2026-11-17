extends TestCase
## What an online session leaves behind for offline play.

const HUB_SCENE_PATH: String = "res://hub/hub.tscn"

var _session: NetSession = null


func after_each() -> void:
	HubLobby.returns_to_hub = false
	if _session != null:
		_session.leave()


func _offline_hub(parent: Node) -> Node3D:
	var hub: Node3D = (load(HUB_SCENE_PATH) as PackedScene).instantiate() as Node3D
	hub.name = "Hub"
	TestFixtures.silence_human_input(hub)
	var lobby: HubLobby = hub.get_node("HubLobby") as HubLobby
	lobby.changes_scene = false
	lobby.session_path = ^"/root/NoSuchSession"
	(hub.get_node("NetMatch") as NetMatch).session_path = ^"/root/NoSuchSession"
	for extra: String in ["HubWorld/WorldEnvironment", "GameAudio", "PauseMenu"]:
		var node: Node = hub.get_node_or_null(extra)
		if node != null:
			node.free()
	parent.add_child(hub)
	return hub


## Lift the hub cat Cat5 with the local body, walk the body away, and report how far the cat is from it.
func _carry_distance(hub: Node3D) -> float:
	await step_ticks(10)
	var body: PlayerController = hub.get_node("Player") as PlayerController
	var cat: HubCat = hub.get_node("HubWorld/Cats/Cat5") as HubCat
	var target: Vector3 = cat.global_position
	body.global_position = target + Vector3(1.2, 0.2, 0.0)
	body.velocity = Vector3.ZERO
	await step_ticks(5)
	var toward: Vector3 = (target - body.global_position)
	toward.y = 0.0
	assert_true(HubCat.claim_shove(body, toward.normalized(), 3.0), "the body's shove lifts the cat in reach")
	assert_true(HubCat.is_carrying(body), "and the game says the body carries it")
	# Walk off with it: a carried cat rides in the hands.
	body.global_position += Vector3(8.0, 0.0, 0.0)
	await step_ticks(30)
	return cat.global_position.distance_to(body.global_position)


func test_control_a_fresh_offline_hub_carries_a_cat() -> void:
	var branch: Node = Node.new()
	branch.name = "Fresh"
	add_child(branch)
	get_tree().set_multiplayer(MultiplayerAPI.create_default_interface(), branch.get_path())
	var hub: Node3D = _offline_hub(branch)
	var distance: float = await _carry_distance(hub)
	assert_lt(distance, 3.0, "a carried cat stays with its carrier in a hub that never went online")


func test_an_offline_hub_after_an_online_session_still_carries_a_cat() -> void:
	_session = NetFixtures.make_peer(self, "Played", NetFixtures.settings())
	var port: int = await NetFixtures.host_and_wait(self, _session)
	assert_true(port > 0, "the machine hosted a session")
	_session.leave()
	var branch: Node = _session.get_parent()
	assert_true(branch.multiplayer.multiplayer_peer is OfflineMultiplayerPeer, "leaving a session puts the engine's offline peer back")
	var hub: Node3D = _offline_hub(branch)
	var distance: float = await _carry_distance(hub)
	assert_lt(distance, 3.0, "a carried cat stays with its carrier in an offline hub entered after an online session")
