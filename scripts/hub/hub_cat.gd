class_name HubCat
extends RigidBody3D

## A hub cat: shove facing it to pick it up, shove again to huck it. Host-decided; a client
## takes it from its record in the snapshot ([NetProp]). Hooked from [method MatchController.apply_shove].

enum State { REST, HELD, FLYING, GONE }
## Height off the floor of the cone check: a cat on a ledge above you is out of reach.
const REACH_HEIGHT: float = 2.0
const FACING_DOT: float = 0.5
const FALL_OUT_Y: float = -60.0
const CAT_LAYER: int = 1 << 3
const FUSE_SECONDS: float = 0.5
const RESPAWN_SECONDS: float = 4.0

## Every cat in the process; each answers only bodies of its own scene ([method _reaches]).
static var _all: Array[HubCat] = []

var _state: State = State.REST
## The body carrying it: on the host the one that lifted it, elsewhere the one this machine draws for the seat.
var _carrier: PlayerController = null
## The seat carrying this cat, -1 for nobody: the host's word on every machine.
var _carrier_seat: int = -1
var _home: Transform3D = Transform3D.IDENTITY
## The scene that placed this cat: only bodies standing in it reach it.
var _scene: Node = null
## The scene's [NetMatch], or null in a world with none.
var _net: NetMatch = null
## The pet prompt and the petting, on the machine whose player carries it.
var _view: CatView = null
## Host: physics ticks until a thrown cat goes off, or a gone one returns; 0 while neither is due.
var _ticks_left: int = 0


func _ready() -> void:
	_home = global_transform
	_scene = owner if owner != null else get_parent()
	axis_lock_angular_x = true
	axis_lock_angular_z = true
	collision_layer = CAT_LAYER
	collision_mask = 1
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	_net = NetProp.register(self)
	_view = CatView.new(get_node_or_null("Mesh") as MeshInstance3D)
	add_child(_view)


func _enter_tree() -> void:
	_all.append(self)


func _exit_tree() -> void:
	_all.erase(self)
	_set_local_held(false)


func get_state() -> State:
	return _state


func is_gone() -> bool:
	return _state == State.GONE


## Show or hide the pet prompt on this machine.
func _set_local_held(held: bool) -> void:
	if _view != null:
		_view.set_petting(held)


## True while this machine offers its own player the pet.
func is_offered_here() -> bool:
	return _view != null and _view.is_petting()


## The host's carrier changed: every machine reads the seat from the record; this one's prompt now.
func _announce_held(held: bool) -> void:
	var link: PlayerNetLink = PlayerNetLink.of(_carrier) if held and is_instance_valid(_carrier) else null
	_carrier_seat = link.seat_index if link != null else (0 if held else -1)
	# With no link there is no session, and whoever carries the cat is this machine's player.
	_set_local_held(held and (link == null or link.is_owned_here()))


## True when [param body] stands in the scene that placed this cat.
func _reaches(body: PlayerController) -> bool:
	return _scene == null or _scene.is_ancestor_of(body)


## Spend [param body]'s shove on a cat: throw the one it carries, else lift one in reach.
## True when a cat took the shove. Authority only, like the shove itself.
static func claim_shove(body: PlayerController, forward: Vector3, reach: float) -> bool:
	if body == null:
		return false
	for cat: HubCat in _all:
		if cat._carrier == body:
			cat._throw()
			return true
	var best: HubCat = _free_in_reach(body, forward, reach)
	if best == null:
		return false
	best._pick_up(body)
	return true


## True when [param body]'s swing now would lift a cat: a lift is free, so the throw can follow at
## once. Read on every machine, so the owner's swing gate predicts the cooldown the host spends.
static func swing_lifts(body: PlayerController, forward: Vector3, reach: float) -> bool:
	return body != null and not is_carrying(body) and _free_in_reach(body, forward, reach) != null


## The nearest cat at rest or flying inside [param body]'s reach and facing cone, or null.
static func _free_in_reach(body: PlayerController, forward: Vector3, reach: float) -> HubCat:
	var best: HubCat = null
	var best_distance: float = 0.0
	var here: Vector3 = body.global_position
	for cat: HubCat in _all:
		if cat._state == State.HELD or cat._state == State.GONE or not cat._reaches(body):
			continue
		var offset: Vector3 = cat.global_position - here
		if absf(offset.y) > REACH_HEIGHT:
			continue
		offset.y = 0.0
		var distance: float = offset.length()
		if distance > reach or (distance > 1e-3 and forward.dot(offset / distance) < FACING_DOT):
			continue
		if best == null or distance < best_distance:
			best = cat
			best_distance = distance
	return best


## True while [param body] holds a cat: on the host its carrier, elsewhere the seat its record names.
static func is_carrying(body: PlayerController) -> bool:
	if body == null:
		return false
	var link: PlayerNetLink = PlayerNetLink.of(body)
	for cat: HubCat in _all:
		if cat._state != State.HELD or not cat._reaches(body):
			continue
		if cat._carrier == body or (link != null and cat._carrier_seat == link.seat_index):
			return true
	return false


func _pick_up(body: PlayerController) -> void:
	_ticks_left = 0
	_carrier = body
	_state = State.HELD
	collision_layer = 0
	collision_mask = 0
	freeze = true
	_announce_held(true)


func _throw() -> void:
	var velocity: Vector3 = CatView.throw_velocity(_carrier)
	global_transform = CatView.carry_transform(_carrier)
	_carrier = null
	_announce_held(false)
	_state = State.FLYING
	collision_layer = CAT_LAYER
	collision_mask = 1
	freeze = false
	sleeping = false
	linear_velocity = velocity
	angular_velocity = Vector3.UP * CatView.THROW_SPIN
	_ticks_left = _ticks(FUSE_SECONDS)


## Boom at the cat's spot, then the cat sits out a few seconds at home.
func _explode() -> void:
	var at: Vector3 = global_position + Vector3.UP * 0.3
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	if _net != null and _net.is_active():
		_net.get_session().replicator.send_event(NetEvents.Type.CAT_BLAST, NetCodec.pack_point(0, at))
	_go()
	CatView.play_blast(_stage(), at)
	_ticks_left = _ticks(RESPAWN_SECONDS)


## The cat went off: hidden at home until it returns.
func _go() -> void:
	_state = State.GONE
	_carrier = null
	_carrier_seat = -1
	_set_local_held(false)
	visible = false
	collision_layer = 0
	collision_mask = 0
	global_transform = _home


## The cat is back on its spot.
func _returned() -> void:
	_state = State.REST
	visible = true
	collision_layer = CAT_LAYER
	collision_mask = 1
	global_transform = _home


## [NetProp]: state and carrying seat (u8: state, seat + 1 above it), position and yaw (it turns about Y only).
func net_record(_tick: int) -> PackedByteArray:
	var buffer: StreamPeerBuffer = StreamPeerBuffer.new()
	buffer.put_u8(_state | ((_carrier_seat + 1) << 2))
	buffer.put_16(NetCodec.quantise_metres(global_position.x))
	buffer.put_16(NetCodec.quantise_metres(global_position.y))
	buffer.put_16(NetCodec.quantise_metres(global_position.z))
	buffer.put_u16(NetCodec.quantise_turn(rotation.y))
	return buffer.data_array


func net_apply(record: PackedByteArray, _tick: int) -> void:
	if record.size() != 9:
		return
	# A client's cat is only drawn: a static body takes each teleport now, a kinematic one a step late.
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	var state: State = (record[0] & 3) as State
	if state == State.GONE:
		if _state != State.GONE:
			_go()
		return
	if _state == State.GONE:
		_returned()
	_state = state
	var seat: int = (record[0] >> 2) - 1
	if seat != _carrier_seat:
		_carrier_seat = seat
		var link: PlayerNetLink = _link_of_seat(seat)
		_carrier = link.controller if link != null and state == State.HELD else null
		_set_local_held(link != null and link.is_owned_here())
	if state != State.HELD:
		global_transform = Transform3D(
			Basis(Vector3.UP, NetCodec.turn_of(record.decode_u16(7))), NetCodec.metres_at(record, 1)
		)


## The link of [param seat] on this machine, or null.
func _link_of_seat(seat: int) -> PlayerNetLink:
	if _net == null or not _net.is_active() or seat < 0:
		return null
	return _net.get_session().replicator.find_link(seat)


## Where a blast is drawn: the running scene, or beside the cat when there is none.
func _stage() -> Node:
	var scene: Node = get_tree().current_scene
	return scene if scene != null else get_parent()


func _physics_process(_delta: float) -> void:
	if not NetProp.is_authority(self):
		# Carried in the hands this machine draws, whichever body draws that seat now.
		if _state == State.HELD and not is_instance_valid(_carrier):
			var link: PlayerNetLink = _link_of_seat(_carrier_seat)
			_carrier = link.controller if link != null else null
		if _state == State.HELD and is_instance_valid(_carrier):
			global_transform = CatView.carry_transform(_carrier)
		return
	if _ticks_left > 0:
		_ticks_left -= 1
		if _ticks_left == 0:
			if _state == State.GONE:
				_returned()
			else:
				_explode()
			return
	match _state:
		State.HELD:
			if not is_instance_valid(_carrier) or not _carrier.is_inside_tree():
				_drop()
			else:
				# Carried in the hands the host draws: a remote carrier's, its playout behind (render-only, off every layer).
				var link: PlayerNetLink = PlayerNetLink.of(_carrier)
				global_transform = CatView.carry_transform(_carrier)
				if link != null:
					global_position += link.drawn_offset()
		State.FLYING:
			if global_position.y < FALL_OUT_Y:
				_settle(_home)
			elif sleeping:
				_settle(Transform3D(Basis(Vector3.UP, rotation.y), global_position))


func _drop() -> void:
	_carrier = null
	_announce_held(false)
	_state = State.FLYING
	collision_layer = CAT_LAYER
	collision_mask = 1
	freeze = false
	sleeping = false
	linear_velocity = Vector3.ZERO


func _settle(where: Transform3D) -> void:
	_state = State.REST
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform = where


func _ticks(seconds: float) -> int:
	return maxi(roundi(seconds / maxf(get_physics_process_delta_time(), 0.0001)), 1)
