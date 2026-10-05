class_name MannequinStage
extends Node3D

## The Debug menu's mannequins: real avatar bodies in the hub, driven by [MannequinIntent], seated so a
## real shove reaches them, shot by a real rifle. Host-local and never on the wire.

const RUNNER_SCENE: PackedScene = preload("res://characters/bots/ring_runner.tscn")
const RIFLE_SCENE: PackedScene = preload("res://weapons/rifle.tscn")
const NODE_NAME: String = "Mannequins"
## The procedural layers under the avatar's skeleton, by node name.
const LAYERS: Array[StringName] = [&"BodyLook", &"BodySpring", &"BodyContact", &"FootPlant"]
## Tunable strengths: the node under the avatar, its export, and the menu's label key.
const TUNING: Array[Array] = [
	["BodySpring", "lean_degrees", "DEBUG_MQ_T_SPRING_LEAN"],
	["BodySpring", "trail_share", "DEBUG_MQ_T_SPRING_TRAIL"],
	["BodySpring", "bounce_centimetres", "DEBUG_MQ_T_SPRING_BOUNCE"],
	["BodySpring", "spring_hertz", "DEBUG_MQ_T_SPRING_HERTZ"],
	["BodySpring", "damping", "DEBUG_MQ_T_SPRING_DAMPING"],
	["BodyContact", "squash_centimetres", "DEBUG_MQ_T_CONTACT_SQUASH"],
	["BodyContact", "reel_degrees", "DEBUG_MQ_T_CONTACT_REEL"],
	["BodyContact", "flinch_degrees", "DEBUG_MQ_T_CONTACT_FLINCH"],
	["BodyContact", "spring_hertz", "DEBUG_MQ_T_CONTACT_HERTZ"],
	["BodyContact", "damping", "DEBUG_MQ_T_CONTACT_DAMPING"],
	["BodyLook", "twist_limit_degrees", "DEBUG_MQ_T_LOOK_TWIST"],
	["BodyLook", "follow_rate", "DEBUG_MQ_T_LOOK_FOLLOW"],
	["BodyLook", "pitch_share", "DEBUG_MQ_T_LOOK_PITCH"],
	["Ragdoll", "flop_throw", "DEBUG_MQ_T_FLOP_THROW"],
	["Ragdoll", "flop_limpness", "DEBUG_MQ_T_FLOP_LIMP"],
	["Ragdoll", "flop_get_up_seconds", "DEBUG_MQ_T_FLOP_GET_UP"],
	["Ragdoll", "impulse", "DEBUG_MQ_T_DEATH_IMPULSE"],
	["Ragdoll", "buckle", "DEBUG_MQ_T_DEATH_BUCKLE"],
]
## Physics layer 2: solid to the world and each other, unseen by the hub's dais triggers (mask 1).
const BODY_LAYER: int = 2
const BODY_MASK: int = 3
const WORLD_MASK: int = 1
## Metres in front of the player a mannequin stands, and sideways between several.
const SPAWN_METRES: float = 4.0
const SPAWN_SPREAD: float = 1.4
## Chest height, metres; how far a shot is taken from, and how far a near miss passes.
const CHEST: float = 1.1
const SHOT_METRES: PackedFloat32Array = [5.0, 3.5]
const MISS_METRES: float = 0.7
## Seconds a shove's pusher and a shot's rifle stay before they go.
const PUSHER_SECONDS: float = 1.2
const RIFLE_SECONDS: float = 4.0
## Ground probe: directions, step and reach in metres; what counts as a slope, a step, a ledge.
const PROBE_DIRECTIONS: int = 24
const PROBE_STEP: float = 0.5
const PROBE_REACH: float = 14.0
const SLOPE_RISE: float = 0.12
const STEP_LIMIT: float = 0.45
const LEDGE_DROP: float = 0.35
const LEDGE_LIMIT: float = 4.0

var controller: MatchController = null
## -1 aims every control at every mannequin; otherwise the one at that index.
var selected: int = -1
## Switches reach every avatar in the scene, the player and bots included.
var reach_every_body: bool = false
## Translation key of the last thing worth telling the player.
var note: String = ""

var _bodies: Array[PlayerController] = []
var _spent: Array[Node] = []
var _spent_left: PackedFloat32Array = PackedFloat32Array()
var _base_time_scale: float = 1.0
var _slow: bool = false
var _watched: PlayerController = null
var _made: int = 0


## The stage under [param scene], made on first use when [param make] is true.
static func find(scene: Node, hub: MatchController, make: bool) -> MannequinStage:
	if scene == null:
		return null
	var stage: MannequinStage = scene.get_node_or_null(NODE_NAME) as MannequinStage
	if stage == null and make:
		stage = MannequinStage.new()
		stage.name = NODE_NAME
		stage.controller = hub
		scene.add_child(stage)
	return stage


func _exit_tree() -> void:
	set_slow(false)
	watch(false)


func _physics_process(delta: float) -> void:
	var i: int = _spent.size() - 1
	while i >= 0:
		_spent_left[i] -= delta
		if _spent_left[i] <= 0.0 or not is_instance_valid(_spent[i]):
			_retire(i)
		i -= 1


# --- The bodies -----------------------------------------------------------------

func bodies() -> Array[PlayerController]:
	for i: int in range(_bodies.size() - 1, -1, -1):
		if not is_instance_valid(_bodies[i]):
			_bodies.remove_at(i)
	return _bodies


## Stand a new mannequin in front of the player, facing him.
func spawn() -> PlayerController:
	var player: PlayerController = _player()
	if player == null:
		return null
	var ahead: Vector3 = _flat(-player.global_transform.basis.z)
	var count: int = bodies().size()
	var side: float = ceilf(count * 0.5) * SPAWN_SPREAD * (1.0 if count % 2 == 1 else -1.0)
	var eye: Vector3 = player.global_position + Vector3.UP * CHEST
	var reach: float = SPAWN_METRES
	var blocked: Dictionary = _ray(eye, eye + ahead * (SPAWN_METRES + 0.6) + ahead.cross(Vector3.UP) * side)
	if not blocked.is_empty():
		reach = maxf(eye.distance_to(blocked["position"]) - 1.0, 1.2)
	var spot: Vector3 = player.global_position + ahead * reach + ahead.cross(Vector3.UP) * side
	spot.y = _floor_at(spot, player.global_position.y)
	_made += 1
	var body: PlayerController = _make_body(spot, MannequinIntent._yaw_to(spot, player.global_position), "Mannequin%d" % _made)
	_bodies.append(body)
	selected = -1
	return body


func remove(body: PlayerController) -> void:
	if not is_instance_valid(body):
		return
	if _watched == body:
		watch(false)
	_bodies.erase(body)
	_drop(body)


## Remove the mannequins the controls act on now.
func remove_selected() -> void:
	for body: PlayerController in targets().duplicate():
		remove(body)
	selected = -1


func remove_all() -> void:
	for body: PlayerController in bodies().duplicate():
		remove(body)


## The mannequins the controls act on now.
func targets() -> Array[PlayerController]:
	var all: Array[PlayerController] = bodies()
	if selected >= 0 and selected < all.size():
		var one: Array[PlayerController] = [all[selected]]
		return one
	return all


# --- What it does ---------------------------------------------------------------

func run(routine: MannequinIntent.Routine) -> void:
	note = ""
	for body: PlayerController in targets():
		var intent: MannequinIntent = _intent(body)
		if intent == null:
			continue
		_arm(body, routine == MannequinIntent.Routine.GUARD)
		var points: PackedVector3Array = _route_for(body, routine)
		var next: MannequinIntent.Routine = routine
		if (routine == MannequinIntent.Routine.LEDGE or routine == MannequinIntent.Routine.SLOPE) and points.is_empty():
			note = "DEBUG_MQ_NO_LEDGE" if routine == MannequinIntent.Routine.LEDGE else "DEBUG_MQ_NO_SLOPE"
			next = MannequinIntent.Routine.JUMP if routine == MannequinIntent.Routine.LEDGE else MannequinIntent.Routine.WALK
			points = _route_for(body, next)
		intent.follow = _player()
		intent.run(next, points)


## A real shove from [param side] of each target (its own frame: -Z in front, +X its right).
func shove_from(side: Vector3) -> void:
	for body: PlayerController in targets():
		var away: Vector3 = body.global_transform.basis * side
		var spot: Vector3 = body.global_position + _flat(away) * 1.6
		spot.y = _floor_at(spot, body.global_position.y)
		var pusher: PlayerController = _make_body(spot, MannequinIntent._yaw_to(spot, body.global_position), "Pusher%d" % (_made + _spent.size()))
		_intent(pusher).run(MannequinIntent.Routine.SHOVE, PackedVector3Array([body.global_position]))
		_spend(pusher, PUSHER_SECONDS)


## A real rifle round past each target's chest, inside a metre.
func near_miss() -> void:
	note = ""
	for body: PlayerController in targets():
		if not _fire_at(body, true):
			note = "DEBUG_MQ_NO_LINE"


## A real rifle hit on each target: the body dies as a shot prisoner does.
func shoot() -> void:
	note = ""
	for body: PlayerController in targets():
		if not _fire_at(body, false):
			note = "DEBUG_MQ_NO_LINE"


## Walk each target off its corpse: the avatar stands back up the way a respawned body does.
func stand_up() -> void:
	for body: PlayerController in targets():
		var intent: MannequinIntent = _intent(body)
		if intent != null:
			intent.run(MannequinIntent.Routine.NUDGE)


# --- Switches -------------------------------------------------------------------

func set_layer(layer: StringName, on: bool) -> void:
	for avatar: PrisonerAvatar in _avatars():
		var node: Node = avatar.find_child(String(layer), true, false)
		if node != null:
			node.set(&"enabled", on)


func is_layer_on(layer: StringName) -> bool:
	for avatar: PrisonerAvatar in _avatars():
		var node: Node = avatar.find_child(String(layer), true, false)
		if node != null:
			return bool(node.get(&"enabled"))
	return true


## The death ragdoll (and anything else the avatar hands its ragdoll), on or off.
func set_ragdoll(on: bool) -> void:
	for avatar: PrisonerAvatar in _avatars():
		var ragdoll: Node = avatar.get_node_or_null(^"Ragdoll")
		if ragdoll == null or not avatar.has_meta(&"mannequin_ragdoll") and avatar.get(&"_ragdoll") == null:
			continue
		avatar.set_meta(&"mannequin_ragdoll", true)
		if not on and ragdoll.call(&"is_active"):
			ragdoll.call(&"stop")
		avatar.set(&"_ragdoll_pending", false)
		avatar.set(&"_ragdoll", ragdoll if on else null)


func is_ragdoll_on() -> bool:
	for avatar: PrisonerAvatar in _avatars():
		return avatar.get(&"_ragdoll") != null
	return true


# --- Tuning ---------------------------------------------------------------------

func _tuned_node(avatar: PrisonerAvatar, node_name: String) -> Node:
	return avatar.find_child(node_name, true, false)


## The export's (low, high, step) on the first target's avatar, or zeros when there is none.
func tuning_range(node_name: String, property: String) -> Vector3:
	for avatar: PrisonerAvatar in _avatars():
		var node: Node = _tuned_node(avatar, node_name)
		if node == null:
			continue
		for info: Dictionary in node.get_property_list():
			if info["name"] == property:
				var parts: PackedStringArray = String(info["hint_string"]).split(",")
				return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
	return Vector3.ZERO


func tuning_value(node_name: String, property: String) -> float:
	for avatar: PrisonerAvatar in _avatars():
		var node: Node = _tuned_node(avatar, node_name)
		if node != null:
			return float(node.get(property))
	return 0.0


func set_tuning(node_name: String, property: String, value: float) -> void:
	for avatar: PrisonerAvatar in _avatars():
		var node: Node = _tuned_node(avatar, node_name)
		if node != null:
			node.set(property, value)


## Put every tuned export back to its script default.
func reset_tuning() -> void:
	for row: Array in TUNING:
		for avatar: PrisonerAvatar in _avatars():
			var node: Node = _tuned_node(avatar, String(row[0]))
			if node != null:
				node.set(String(row[1]), (node.get_script() as Script).get_property_default_value(String(row[1])))


## The current values as plain `name = value` lines.
func tuning_text() -> String:
	var lines: PackedStringArray = []
	for row: Array in TUNING:
		lines.append("%s.%s = %s" % [row[0], row[1], String.num(tuning_value(String(row[0]), String(row[1])), 3)])
	return "\n".join(lines)


## Engine time at a quarter, or back to what it was.
func set_slow(on: bool) -> void:
	if on == _slow:
		return
	if on:
		_base_time_scale = Engine.time_scale
	Engine.time_scale = _base_time_scale * (0.25 if on else 1.0)
	_slow = on


func is_slow() -> bool:
	return _slow


## Look out of the first target's eyes (its first-person arms on a held rifle), or back out of the player's.
func watch(on: bool) -> void:
	var player: PlayerController = _player()
	if on:
		var all: Array[PlayerController] = targets()
		if all.is_empty():
			return
		var eye: Camera3D = all[0].get_node_or_null(^"Head/Camera") as Camera3D
		if eye == null:
			return
		_watched = all[0]
		eye.make_current()
		PrisonerAvatar.set_viewed_body(_watched)
	elif _watched != null:
		_watched = null
		PrisonerAvatar.release_viewed_body()
		var own: Camera3D = player.get_node_or_null(^"Head/Camera") as Camera3D if player != null else null
		if own != null:
			own.make_current()


func is_watching() -> bool:
	return is_instance_valid(_watched)


# --- Making and unmaking --------------------------------------------------------

func _make_body(spot: Vector3, yaw: float, node_name: String) -> PlayerController:
	var body: PlayerController = RUNNER_SCENE.instantiate() as PlayerController
	for unwanted: StringName in [&"Brain", &"BotInput"]:
		var node: Node = body.get_node_or_null(NodePath(String(unwanted)))
		if node != null:
			body.remove_child(node)
			node.free()
	var intent: MannequinIntent = MannequinIntent.new()
	intent.name = "MannequinInput"
	body.add_child(intent)
	body.intent_source = intent
	body.name = node_name
	body.collision_layer = BODY_LAYER
	body.collision_mask = BODY_MASK
	body.position = spot
	body.rotation = Vector3(0.0, yaw, 0.0)
	add_child(body)
	if controller != null:
		controller.debug_add_hub_body(body)
	return body


func _drop(body: PlayerController) -> void:
	if controller != null:
		controller.debug_remove_hub_body(body)
	if body.get_parent() == self:
		remove_child(body)
	body.queue_free()


func _spend(node: Node, seconds: float) -> void:
	_spent.append(node)
	_spent_left.append(seconds)


func _retire(i: int) -> void:
	var node: Node = _spent[i]
	_spent.remove_at(i)
	_spent_left.remove_at(i)
	if not is_instance_valid(node):
		return
	if node is PlayerController:
		_drop(node as PlayerController)
	else:
		node.queue_free()


## Put a rifle in [param body]'s hands as the guard, or take it away.
func _arm(body: PlayerController, armed: bool) -> void:
	var held: Rifle = _rifle_of(body)
	body.is_guard = armed
	if armed and held == null and body.head != null:
		var rifle: Rifle = _make_rifle()
		body.head.add_child(rifle)
		rifle.aim_source = body.get_node_or_null(^"Head/Camera") as Node3D
		rifle.shooter_body = body
	elif not armed and held != null:
		held.get_parent().remove_child(held)
		held.queue_free()


func _rifle_of(body: PlayerController) -> Rifle:
	if body.head == null:
		return null
	for child: Node in body.head.get_children():
		if child is Rifle:
			return child as Rifle
	return null


## A rifle nobody's mouse fires.
func _make_rifle() -> Rifle:
	var rifle: Rifle = RIFLE_SCENE.instantiate() as Rifle
	var trigger: Node = rifle.get_node_or_null(^"HumanTrigger")
	if trigger != null:
		trigger.process_mode = Node.PROCESS_MODE_DISABLED
	if controller != null:
		rifle.rules = controller.get_rules()
	return rifle


## Fire one real round at [param body] from a clear side: into the chest, or past it on the side away from the player.
func _fire_at(body: PlayerController, miss: bool) -> bool:
	var chest: Vector3 = body.global_position + Vector3.UP * CHEST
	var player: PlayerController = _player()
	var toward: Vector3 = _flat(player.global_position - body.global_position) if player != null else _flat(-body.global_transform.basis.z)
	var across: Vector3 = toward.cross(Vector3.UP)
	for metres: float in SHOT_METRES:
		for from: Vector3 in [chest + across * metres, chest - across * metres, chest - toward * metres]:
			if not _ray(from, chest, body).is_empty() or not _ray(chest, from, body).is_empty():
				continue
			var aim: Vector3 = chest
			if miss:
				var past: Vector3 = (chest - from).normalized().cross(Vector3.UP) * MISS_METRES
				aim = chest + (past if past.dot(toward) <= 0.0 else -past)
			var rifle: Rifle = _make_rifle()
			add_child(rifle)
			rifle.global_position = from
			rifle.look_at(aim)
			if not miss:
				rifle.target_hit.connect(_on_hit.bind(body))
			rifle.try_fire()
			_spend(rifle, RIFLE_SECONDS)
			return true
	return false


func _on_hit(collider: Node3D, _at: Vector3, _normal: Vector3, body: PlayerController) -> void:
	if not is_instance_valid(body) or collider == null:
		return
	if collider != body and not body.is_ancestor_of(collider):
		return
	var intent: MannequinIntent = _intent(body)
	if intent != null:
		intent.run(MannequinIntent.Routine.STAND)
	body.died.emit()


# --- Routes ---------------------------------------------------------------------

func _route_for(body: PlayerController, routine: MannequinIntent.Routine) -> PackedVector3Array:
	var here: Vector3 = body.global_position
	var player: PlayerController = _player()
	var toward: Vector3 = _flat(player.global_position - here) if player != null else _flat(-body.global_transform.basis.z)
	var across: Vector3 = toward.cross(Vector3.UP)
	match routine:
		MannequinIntent.Routine.WALK:
			return PackedVector3Array([here + across * 4.0, here - across * 4.0])
		MannequinIntent.Routine.JUMP:
			return PackedVector3Array([here + across * 1.5, here - across * 1.5])
		MannequinIntent.Routine.SPRINT:
			var centre: Vector3 = here - toward * 4.0
			return PackedVector3Array([
				centre + across * 5.0 + toward * 3.0, centre + across * 5.0 - toward * 3.0,
				centre - across * 5.0 - toward * 3.0, centre - across * 5.0 + toward * 3.0,
			])
		MannequinIntent.Routine.SLOPE, MannequinIntent.Routine.LEDGE:
			return _probe(here, routine == MannequinIntent.Routine.LEDGE)
	return PackedVector3Array()


## The nearest change of floor around [param from]: a walkable slope or step, or a drop to step off.
func _probe(from: Vector3, ledge: bool) -> PackedVector3Array:
	var base: float = _floor_at(from, from.y)
	var best: PackedVector3Array = PackedVector3Array()
	var best_distance: float = INF
	for i: int in PROBE_DIRECTIONS:
		var angle: float = TAU * float(i) / float(PROBE_DIRECTIONS)
		var direction: Vector3 = Vector3(sin(angle), 0.0, cos(angle))
		var last: float = base
		var d: float = PROBE_STEP
		while d <= PROBE_REACH and d < best_distance:
			var spot: Vector3 = from + direction * d
			var hit: Dictionary = _ray(Vector3(spot.x, last + 2.5, spot.z), Vector3(spot.x, last - LEDGE_LIMIT, spot.z))
			if hit.is_empty():
				break
			var height: float = (hit["position"] as Vector3).y
			var change: float = height - last
			if ledge and -change >= LEDGE_DROP:
				best = PackedVector3Array([from + direction * maxf(d - 1.0, 0.0), from + direction * (d + 1.5)])
				best_distance = d
				break
			if absf(change) > STEP_LIMIT:
				break
			if not ledge and absf(height - base) >= SLOPE_RISE:
				var start: float = maxf(d - 2.0, 0.0)
				best = PackedVector3Array([from + direction * start, from + direction * (d + 3.0)])
				best_distance = d
				break
			last = height
			d += PROBE_STEP
	return best


# --- Reading the world ----------------------------------------------------------

func _player() -> PlayerController:
	if controller == null:
		return null
	var human: MatchParticipant = controller.get_human_participant()
	return human.body if human != null else controller.player


func _intent(body: PlayerController) -> MannequinIntent:
	return body.intent_source as MannequinIntent if is_instance_valid(body) else null


func _avatars() -> Array[PrisonerAvatar]:
	var found: Array[PrisonerAvatar] = []
	var roots: Array[Node] = []
	if reach_every_body and get_parent() != null:
		roots.append(get_parent())
	else:
		roots.assign(targets())
	for root: Node in roots:
		for node: Node in root.find_children("*", "PrisonerAvatar", true, false):
			found.append(node as PrisonerAvatar)
	return found


func _floor_at(spot: Vector3, near: float) -> float:
	var hit: Dictionary = _ray(Vector3(spot.x, near + 2.0, spot.z), Vector3(spot.x, near - 6.0, spot.z))
	return (hit["position"] as Vector3).y + 0.05 if not hit.is_empty() else near


func _ray(from: Vector3, to: Vector3, skip: CollisionObject3D = null) -> Dictionary:
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to, WORLD_MASK)
	if skip != null:
		query.exclude = [skip.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query)


static func _flat(v: Vector3) -> Vector3:
	var out: Vector3 = Vector3(v.x, 0.0, v.z)
	return out.normalized() if out.length_squared() > 1e-6 else Vector3.FORWARD
