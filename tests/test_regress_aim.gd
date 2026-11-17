extends TestCase
## Playtest regressions in aim and facing: a client's view on the host, and where the guard looks and stands.

const Rig = preload("res://tests/support/net_match_rig.gd")

const HOST: int = 0
const HELL: StringName = &"bentham_ring"
const MARBLE: StringName = &"marble"
## Ticks for a reliable event and the snapshots behind it to cross loopback and be drawn.
const CROSS_TICKS: int = 30
## The same on a bad line: time is compressed fiftyfold, so 3 real ms each way is 150 ms of play.
const BAD_LINE_TICKS: int = 150
const BAD_LINE_LOSS: float = 0.2
const BAD_LINE_DELAY_MS: int = 3
## Half a degree: what the host's copy of a view may differ from the view its owner holds.
const VIEW_TOLERANCE: float = 0.0088
## What a third machine's drawing of that view may differ by: the snapshot's angle step and more.
const MIRROR_TOLERANCE: float = 0.02
## Shots a bot guard is watched for in one match; ten matches, five a map, make 500.
const GUARD_SHOTS: int = 50
## Bearings the guard is pushed out from the seat along, to meet the tower's walls, columns and rail.
const WALL_BEARINGS: int = 16
## Yaw steps the guard turns through where it meets the tower, and the pitches it looks at each.
const WALL_YAWS: int = 24
const WALL_PITCHES_DEGREES: Array[float] = [-35.0, 0.0, 20.0]

var _rig: Rig = null
var _cross: int = CROSS_TICKS
## Rounds the match is played to.
var _rounds: int = 5


func before_each() -> void:
	_rig = Rig.new()
	_cross = CROSS_TICKS


func after_each() -> void:
	if _rig != null:
		_rig.close()
		_rig = null


## A round running on every peer of a host and [param clients], [param guard_slot] in the tower.
func _start_round(map: StringName, clients: int, seats: int, guard_slot: int, bad_line: bool = false) -> bool:
	if bad_line:
		_rig.wire_loss = BAD_LINE_LOSS
		_rig.wire_delay_ms = BAD_LINE_DELAY_MS
		_cross = BAD_LINE_TICKS
	if not await _rig.connect_peers(self, clients):
		fail("the loopback handshake did not complete")
		return false
	_rig.settings().rounds_to_win_match = _rounds
	_rig.settings().map_id = map
	if not await _rig.launch(seats, guard_slot):
		fail("the match never started on every peer")
		return false
	for peer: int in _rig.peer_count():
		var controller: MatchController = _rig.controller(peer)
		if not await _rig.wait_for(func() -> bool: return controller.get_phase() == MatchController.Phase.ROUND):
			fail("peer %d never reached the round" % peer)
			return false
	return true


func _input_of(peer: int) -> BotIntentSource:
	return (_rig.matches[peer].get_node("Player") as PlayerController).intent_source as BotIntentSource


## Flat forward of [param body], unit length.
func _facing(body: PlayerController) -> Vector3:
	var forward: Vector3 = -body.global_transform.basis.z
	forward.y = 0.0
	return forward.normalized()


# --- PT2-02: "he moves left and right when going forward and backwards" -------------------------

## A client turns and runs on a lossy line; the host and every other peer hold the view it holds.
func _a_clients_view_is_the_hosts(map: StringName, clients: int) -> void:
	if not await _start_round(map, clients, clients + 2, HOST, true):
		return
	var host: MatchController = _rig.controller(HOST)
	for client: int in range(1, clients + 1):
		var slot: int = _rig.local_slot(client)
		var input: BotIntentSource = _input_of(client)
		var own: PlayerController = _rig.body(client, slot)
		var on_host: PlayerController = _rig.body(HOST, slot)
		var before: Vector2 = own.get_view_angles()
		# Forward and back while the mouse sweeps, as the friend played it.
		for tick: int in 120:
			input.command.move_direction = Vector2(0.0, 1.0 if (tick / 20) % 2 == 0 else -1.0)
			input.command.look_delta = Vector2(0.02, 0.003 if tick < 60 else -0.002)
			await step_ticks(1)
		input.command.move_direction = Vector2.ZERO
		await step_ticks(_cross)
		var held: Vector2 = own.get_view_angles()
		assert_gt(absf(angle_difference(before.x, held.x)), 1.0, "client %d turned" % client)
		assert_false(_rig.participant(HOST, slot).is_ghost, "client %d is still alive on the host" % client)
		var seen: Vector2 = on_host.get_view_angles()
		assert_lt(absf(angle_difference(held.x, seen.x)), VIEW_TOLERANCE, "the host holds client %d's yaw" % client)
		assert_lt(absf(held.y - seen.y), VIEW_TOLERANCE, "the host holds client %d's pitch" % client)
		for peer: int in range(1, clients + 1):
			if peer == client:
				continue
			var drawn: PlayerController = _rig.body(peer, slot)
			assert_lt(
				absf(angle_difference(held.x, drawn.rotation.y)), MIRROR_TOLERANCE,
				"peer %d draws client %d facing where it faces" % [peer, client],
			)
		# Forward only, no mouse: the body goes where its owner is looking, on the host as on its own machine.
		var from: Vector3 = on_host.global_position
		input.command.move_direction = Vector2(0.0, 1.0)
		await step_ticks(40)
		var travelled: Vector3 = on_host.global_position - from
		travelled.y = 0.0
		input.command.move_direction = Vector2.ZERO
		if assert_gt(travelled.length(), 0.5, "client %d's body runs on the host" % client):
			assert_gt(travelled.normalized().dot(_facing(own)), 0.97, "client %d runs the way it looks, not sideways" % client)
		await step_ticks(_cross)
		assert_lt(
			own.global_position.distance_to(on_host.global_position), 0.25,
			"client %d stands where the host has it" % client,
		)
	assert_eq_int(host.get_phase(), MatchController.Phase.ROUND, "the round is still on")


func test_a_clients_view_under_loss_is_the_view_the_host_holds_hell_two_peers() -> void:
	await _a_clients_view_is_the_hosts(HELL, 1)


func test_a_clients_view_under_loss_is_the_view_the_host_holds_marble_four_peers() -> void:
	await _a_clients_view_is_the_hosts(MARBLE, 3)


# --- S-10 / S-12: where the guard looks and stands when it is given the seat ---------------------

## Degrees between [param peer]'s drawing of [param slot]'s facing and the line from the seat to the start.
func _off_the_start(peer: int, slot: int) -> float:
	var controller: MatchController = _rig.controller(peer)
	var to_start: Vector3 = (controller.get(&"_start_point") as Vector3) - (controller.get(&"_tower_point") as Vector3)
	to_start.y = 0.0
	return rad_to_deg(_facing(_rig.body(peer, slot)).angle_to(to_start.normalized()))


## Every peer draws the guard in [param slot] looking at the start line, still, and in the seat.
func _the_guard_is_seated(slot: int, when: String) -> void:
	await step_ticks(_cross * 2)
	var seats: Array[Vector3] = []
	for peer: int in _rig.peer_count():
		assert_same(
			_rig.controller(peer).get_seat_participant(), _rig.participant(peer, slot),
			"peer %d: slot %d holds the tower %s" % [peer, slot, when],
		)
		assert_lt(_off_the_start(peer, slot), 5.0, "peer %d: the guard looks at the start line %s" % [peer, when])
		seats.append(_rig.body(peer, slot).global_position)
	var seat: Vector3 = _rig.controller(HOST).get(&"_tower_point") as Vector3
	assert_lt(seats[HOST].distance_to(seat), 0.5, "the guard is put on the seat %s" % when)
	# Two seconds with nobody touching anything: the guard is not thrown, and does not drift.
	for _tick: int in 12:
		await step_ticks(10)
		for peer: int in _rig.peer_count():
			var body: PlayerController = _rig.body(peer, slot)
			assert_lt(body.global_position.distance_to(seats[peer]), 0.3, "peer %d: the guard stays in the seat %s" % [peer, when])
			assert_lt(body.velocity.length(), 0.5, "peer %d: the guard is at rest %s" % [peer, when])
			assert_lt(_off_the_start(peer, slot), 5.0, "peer %d: the guard still looks at the start %s" % [peer, when])


## [param finisher_slot] throws the guard out; the next round is running on every peer.
func _hand_the_tower_to(finisher_slot: int) -> bool:
	var host: MatchController = _rig.controller(HOST)
	var finisher: MatchParticipant = _rig.participant(HOST, finisher_slot)
	var round_before: int = host.get_round_number()
	TestFixtures.pin_the_field(host, finisher)
	host.call(&"_arm_the_finisher", finisher)
	if not await _rig.wait_for(func() -> bool: return finisher.body.is_physics_processing()):
		fail("the finisher never landed in the tower")
		return false
	# A finisher takes longer than a round trip to cross the room.
	await step_ticks(_cross * 2)
	if host.apply_shove(finisher) == null:
		fail("the finisher's shove took nobody")
		return false
	for peer: int in _rig.peer_count():
		var controller: MatchController = _rig.controller(peer)
		if not await _rig.wait_for(
			func() -> bool:
				return controller.get_round_number() == round_before + 1 \
					and controller.get_phase() == MatchController.Phase.ROUND
		):
			fail("peer %d never saw the next round" % peer)
			return false
	return true


## The opening guard, then two more seat grants, each looked at from every peer.
func _every_seat_grant_faces_the_start(map: StringName, clients: int, order: Array[int]) -> void:
	if not await _start_round(map, clients, clients + 2, order[0]):
		return
	await _the_guard_is_seated(order[0], "at the opening")
	for grant: int in range(1, order.size()):
		if not await _hand_the_tower_to(order[grant]):
			return
		await _the_guard_is_seated(order[grant], "at seat grant %d" % (grant + 1))


func test_the_guard_faces_the_start_and_keeps_the_seat_hell_two_peers_host_first() -> void:
	await _every_seat_grant_faces_the_start(HELL, 1, [0, 1, 0])


func test_the_guard_faces_the_start_and_keeps_the_seat_hell_two_peers_client_first() -> void:
	await _every_seat_grant_faces_the_start(HELL, 1, [1, 0, 1])


func test_the_guard_faces_the_start_and_keeps_the_seat_marble_two_peers_client_first() -> void:
	await _every_seat_grant_faces_the_start(MARBLE, 1, [1, 0, 1])


func test_the_guard_faces_the_start_and_keeps_the_seat_hell_four_peers() -> void:
	await _every_seat_grant_faces_the_start(HELL, 3, [2, 0, 3])


func test_the_guard_faces_the_start_and_keeps_the_seat_marble_four_peers() -> void:
	await _every_seat_grant_faces_the_start(MARBLE, 3, [0, 3, 1])


## A client that looked away is put back on the start line looking down the lane, as the host placed it.
func _a_new_round_faces_a_client_runner_down_the_lane(map: StringName, clients: int) -> void:
	# A bot holds the tower; the host throws it out and the round turns over around the clients.
	var bot_slot: int = clients + 1
	if not await _start_round(map, clients, clients + 2, bot_slot):
		return
	var host: MatchController = _rig.controller(HOST)
	# The bot guard keeps the seat, where a shove can reach it.
	_rig.body(HOST, bot_slot).movement_locked = true
	await step_ticks(_cross)
	for client: int in range(1, clients + 1):
		var input: BotIntentSource = _input_of(client)
		for _tick: int in 40:
			input.command.look_delta = Vector2(0.05, 0.0)
			await step_ticks(1)
	await step_ticks(_cross)
	# Where the host's placement faces each client, read as the new round begins and before any view arrives.
	var placed: Dictionary[int, float] = {}
	host.round_started.connect(
		func() -> void:
			for client: int in range(1, clients + 1):
				placed[client] = _rig.body(HOST, _rig.local_slot(client)).rotation.y
	)
	if not await _hand_the_tower_to(HOST):
		return
	await step_ticks(_cross * 2)
	if not assert_eq_int(placed.size(), clients, "the host placed every client for the new round"):
		return
	# The thrown bot is a runner now and has not been let move: it faces as the match placed it.
	var lane: Vector3 = _facing(_rig.body(HOST, bot_slot))
	for client: int in range(1, clients + 1):
		var slot: int = _rig.local_slot(client)
		assert_lt(
			rad_to_deg(_facing(_rig.body(HOST, slot)).angle_to(lane)), 30.0,
			"the host's placement faces client %d down the lane with the others" % client,
		)
		for peer: int in _rig.peer_count():
			assert_lt(
				absf(angle_difference(_rig.body(peer, slot).rotation.y, placed[client])), MIRROR_TOLERANCE,
				"peer %d: client %d starts the round facing as the host placed it" % [peer, client],
			)


func test_a_new_round_faces_a_client_runner_down_the_lane_hell_two_peers() -> void:
	await _a_new_round_faces_a_client_runner_down_the_lane(HELL, 1)


func test_a_new_round_faces_a_client_runner_down_the_lane_marble_four_peers() -> void:
	await _a_new_round_faces_a_client_runner_down_the_lane(MARBLE, 3)


# --- S-06: "when they do shoot its through the column of the tower" ------------------------------

## Whether [param node] is part of the tower of the map it stands in.
func _is_tower(node: Node) -> bool:
	return node != null and String(node.get_path()).contains("/Tower/")


## What the drawn gun's own mesh crosses with the ViewModel at [param pose]: every triangle edge of the model,
## cast both ways (the maps' faces are one-sided). Not the bounds the clearance searches with. Empty when nothing.
func _gun_meets(rifle: Rifle, holder: PlayerController, pose: Transform3D) -> Dictionary:
	var view_model: Node3D = rifle.get_node(^"ViewModel") as Node3D
	var space: PhysicsDirectSpaceState3D = holder.get_world_3d().direct_space_state
	for node: Node in view_model.get_node(^"Model").find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		var to_world: Transform3D = rifle.global_transform * pose * (view_model.global_transform.affine_inverse() * mesh.global_transform)
		var faces: PackedVector3Array = mesh.mesh.get_faces()
		for corner: int in faces.size():
			var from: Vector3 = to_world * faces[corner]
			var to: Vector3 = to_world * faces[corner - corner % 3 + (corner + 1) % 3]
			for way: PackedVector3Array in [PackedVector3Array([from, to]), PackedVector3Array([to, from])]:
				var edge: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(way[0], way[1], rifle.profile.hit_mask)
				edge.exclude = [holder.get_rid()]
				var hit: Dictionary = space.intersect_ray(edge)
				if not hit.is_empty():
					return hit
	return {}


## The guard pressed against the tower turns through every bearing; wherever sliding back can clear it, the gun
## as drawn is clear of the world. The rifle is the same for a human and a bot.
func _a_rifle_held_against_the_tower_stays_out_of_it(map: StringName, guard_slot: int) -> void:
	if not await _start_round(map, 0, 2, guard_slot):
		return
	var rifle: Rifle = _rig.controller(HOST).rifle
	var body: PlayerController = _rig.body(HOST, guard_slot)
	# The runner is held on the start line so the round, and the tower, stay as they are.
	_rig.body(HOST, 1 - guard_slot).movement_locked = true
	# Posed by hand once the seat has settled: its own physics, or a bot's brain, would move it between poses.
	await step_ticks(_cross)
	body.set_physics_process(false)
	for brain: Node in body.find_children("*", "TowerShooter", true, false):
		brain.set_physics_process(false)
	var ads: RifleAds = rifle.get_node(^"Ads") as RifleAds
	var seat: Vector3 = body.global_position
	var poses: int = 0
	var reached: int = 0
	var past_cap: int = 0
	var clearance: RifleClearance = rifle.get_node_or_null(^"Clearance") as RifleClearance
	var inside: PackedStringArray = PackedStringArray()
	for bearing: int in WALL_BEARINGS:
		var out: float = TAU * bearing / WALL_BEARINGS
		body.global_position = seat
		if body.move_and_collide(Vector3(cos(out), 0.0, sin(out)) * 15.0) == null:
			continue
		for yaw: int in WALL_YAWS:
			for pitch: float in WALL_PITCHES_DEGREES:
				body.rotation = Vector3(0.0, TAU * yaw / WALL_YAWS, 0.0)
				body.head.rotation = Vector3(deg_to_rad(pitch), 0.0, 0.0)
				# The first frame lands the pose, the next is drawn with it.
				await get_tree().process_frame
				await get_tree().process_frame
				if rifle.shooter_body != body:
					fail("the guard lost the rifle at bearing %d" % bearing)
					return
				poses += 1
				var view_model: Node3D = rifle.get_node(^"ViewModel") as Node3D
				var rest: Transform3D = ads.get_current_base_pose()
				if _gun_meets(rifle, body, rest).is_empty():
					continue
				reached += 1
				# Slid back as far as it may go: the stock at the shoulder.
				var tip: Vector3 = rest * rifle.muzzle.transform.origin
				var reach: float = (rifle.global_transform.basis * tip).length()
				var capped: Transform3D = Transform3D(rest.basis, rest.origin - tip * (RifleClearance.MAX_SLIDE / reach))
				if not _gun_meets(rifle, body, capped).is_empty():
					past_cap += 1
					if clearance != null:
						assert_almost_eq(clearance.get_slide(), RifleClearance.MAX_SLIDE, 0.001, "a gun that cannot clear is held at the cap")
					continue
				var met: Dictionary = _gun_meets(rifle, body, view_model.transform)
				if not met.is_empty():
					inside.append("%s bearing %d yaw %d pitch %d: the drawn gun is in %s" % [
						map, bearing, yaw, int(pitch), (met["collider"] as Node).name,
					])
	print("          RIFLE AT THE WALL %s: %d poses, %d with the held gun reaching into the world, %d past the slide's cap, %d drawn inside" % [
		map, poses, reached, past_cap, inside.size(),
	])
	assert_gt(float(reached - past_cap), 0.0, "the guard was put where its rifle reaches into the tower and can clear it")
	for line: String in inside.slice(0, 10):
		fail(line)
	assert_eq_int(inside.size(), 0, "of %d poses against the tower the gun could clear, the ones drawn inside it" % (reached - past_cap))


func test_a_human_guards_rifle_held_against_the_tower_stays_out_of_it_hell() -> void:
	await _a_rifle_held_against_the_tower_stays_out_of_it(HELL, HOST)


func test_a_human_guards_rifle_held_against_the_tower_stays_out_of_it_marble() -> void:
	await _a_rifle_held_against_the_tower_stays_out_of_it(MARBLE, HOST)


func test_a_bot_guards_rifle_held_against_the_tower_stays_out_of_it_marble() -> void:
	await _a_rifle_held_against_the_tower_stays_out_of_it(MARBLE, 1)


## A bot holds the tower against running bots; no shot it takes is aimed into the tower. The line it checks
## before it fires is the one the shot takes, so a led or erring aim across a column is held, not fired.
func _a_bot_guard_aims_out_of_its_own_tower(map: StringName) -> void:
	var shots: Array[int] = [0]
	var into_tower: PackedStringArray = PackedStringArray()
	# One long match: the tower changes hands between bots and the shots keep coming.
	_rounds = 99
	if not await _start_round(map, 0, 5, 1):
		return
	var host: MatchController = _rig.controller(HOST)
	var rifle: Rifle = host.rifle
	var mask: int = rifle.profile.hit_mask
	# The human on the start line is no part of this.
	_rig.body(HOST, HOST).movement_locked = true
	rifle.fired.connect(
		func(_origin: Vector3, _end: Vector3) -> void:
			var eye: Node3D = rifle.aim_source
			if eye == null or rifle.shooter_body == null or host.get_seat_participant().is_human():
				return
			shots[0] += 1
			var space: PhysicsDirectSpaceState3D = eye.get_world_3d().direct_space_state
			var from: Vector3 = eye.global_position
			var aim: Vector3 = -eye.global_transform.basis.z.normalized()
			var ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
				from, from + aim * rifle.profile.max_range, mask
			)
			ray.exclude = [rifle.shooter_body.get_rid()]
			ray.hit_from_inside = true
			var hit: Dictionary = space.intersect_ray(ray)
			if not hit.is_empty() and _is_tower(hit["collider"] as Node):
				into_tower.append("%s shot %d from %v aimed %v met %s after %.2f m" % [
					map, shots[0], from, aim, (hit["collider"] as Node).name, from.distance_to(hit["position"] as Vector3),
				])
	)
	var seconds: int = 0
	while shots[0] < GUARD_SHOTS and seconds < 3600 and host.get_phase() != MatchController.Phase.MATCH_OVER:
		await step_ticks(60)
		seconds += 1
	print("          BOT GUARD %s: %d shots in %d s of play, %d aimed into the tower" % [map, shots[0], seconds, into_tower.size()])
	if not assert_ge(float(shots[0]), float(GUARD_SHOTS), "the bot guard took shots to judge"):
		return
	for line: String in into_tower:
		fail("the bot guard aimed into its own tower: %s" % line)
	assert_eq_int(into_tower.size(), 0, "of %d shots, the ones aimed into the tower" % shots[0])


func test_a_bot_guard_aims_out_of_its_own_tower_hell_first_match() -> void:
	await _a_bot_guard_aims_out_of_its_own_tower(HELL)


func test_a_bot_guard_aims_out_of_its_own_tower_hell_second_match() -> void:
	await _a_bot_guard_aims_out_of_its_own_tower(HELL)


func test_a_bot_guard_aims_out_of_its_own_tower_hell_third_match() -> void:
	await _a_bot_guard_aims_out_of_its_own_tower(HELL)


func test_a_bot_guard_aims_out_of_its_own_tower_hell_fourth_match() -> void:
	await _a_bot_guard_aims_out_of_its_own_tower(HELL)


func test_a_bot_guard_aims_out_of_its_own_tower_hell_fifth_match() -> void:
	await _a_bot_guard_aims_out_of_its_own_tower(HELL)


func test_a_bot_guard_aims_out_of_its_own_tower_marble_first_match() -> void:
	await _a_bot_guard_aims_out_of_its_own_tower(MARBLE)


func test_a_bot_guard_aims_out_of_its_own_tower_marble_second_match() -> void:
	await _a_bot_guard_aims_out_of_its_own_tower(MARBLE)


func test_a_bot_guard_aims_out_of_its_own_tower_marble_third_match() -> void:
	await _a_bot_guard_aims_out_of_its_own_tower(MARBLE)


func test_a_bot_guard_aims_out_of_its_own_tower_marble_fourth_match() -> void:
	await _a_bot_guard_aims_out_of_its_own_tower(MARBLE)


func test_a_bot_guard_aims_out_of_its_own_tower_marble_fifth_match() -> void:
	await _a_bot_guard_aims_out_of_its_own_tower(MARBLE)

