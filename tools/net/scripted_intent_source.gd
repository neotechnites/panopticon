class_name ScriptedIntentSource
extends IntentSource

## A scripted human for headless net runs. Keys go down on the real device actions and are read
## back through the body's own HumanIntentSource; movement is the bot brain's (PLAY) or a canned walk.

enum Mode { IDLE, WALK, PLAY }
enum Role { HELD, RUN, CHASE, HUNT, GUARD, BRAWL }

const KEY_ACTIONS: Dictionary[String, StringName] = {
	"1": &"ability_1", "2": &"ability_2", "3": &"ability_3", "4": &"ability_4", "5": &"ability_5",
	"q": &"ability", "e": &"interact", "f": &"shove", "b": &"emote", "n": &"emote_alt", "j": &"jump",
}
const POWER_KEYS: PackedStringArray = ["1", "2", "3", "4", "5", "q"]
const BOT_PROFILE: String = "res://characters/bots/default_bot_profile.tres"
const RUNNER_PROFILE: String = "res://characters/bots/default_runner_profile.tres"
## A deferred key gives up waiting for a valid moment after this long.
const KEY_PATIENCE_SECONDS: float = 45.0
const BRAWL_SHOVE_REST: float = 1.7
## The view counts as on its target inside this many radians: the trigger waits for it, as a person's does.
const AIM_SETTLED_RADIANS: float = 0.01

## Emitted on the tick this source pulls the trigger.
signal trigger_pulled
## Emitted on the tick a key goes down; [param valid] says the body could act on it.
signal key_pressed(key: String, valid: bool, note: String)
signal key_released(key: String)
signal role_changed(role: String)

var mode: Mode = Mode.WALK
## Canned walk: seconds on, seconds off, yaw and pitch sweep per second.
var walk_seconds: float = 3.0
var rest_seconds: float = 2.0
var yaw_rate: float = 0.15
var pitch_rate: float = 0.0
## Guard: first trigger pull, seconds after start, and the gap between pulls; 0 never fires.
var fire_at: float = 4.0
var fire_every: float = 0.0
## Guard: turn the view onto the nearest running body in sight and fire only with one in sight.
var aim_enabled: bool = false
## Guard: play the tower as a person does, scope up and from a post with a line, and fire only once
## the view has settled. Off, the guard turns to its target and pulls at once on the cadence.
var marksman: bool = false
## Hold a key back until the body can act on it.
var keys_wait: bool = true
## Not the body's source: only presses keys (and walks) on the device, from its own physics tick.
var device_only: bool = false
var device_walk: bool = false
## Fault for the checker's own test: report the press and never put the key down.
var mute_keys: bool = false

var match_controller: MatchController = null
var body: PlayerController = null

var _elapsed: float = 0.0
var _next_fire: float = -1.0
var _keys: Array[Dictionary] = []
var _repeats: Array[Dictionary] = []
var _down: Dictionary[String, float] = {}
var _last_press: float = 0.0
var _still_until: float = -1.0
var _human: HumanIntentSource = null
var _bot: BotIntentSource = null
var _brain: RunnerBrain = null
var _role: Role = Role.HELD
var _rearm: bool = true
var _aimed: MatchParticipant = null
var _brawl_rest: float = 0.0
var _walked: Dictionary[StringName, bool] = {}
var _rest_ticks: int = 0
## Keys ("j", "f") this source presses itself: until when the brain's own jumps or swings are held off,
## and since when, so the key's press is an edge and not lost in the brain's.
var _own_until: Dictionary[String, float] = {}
var _own_since: Dictionary[String, float] = {}
var _optic: WeaponOptic = null
var _posts: PackedVector3Array = PackedVector3Array()
var _posts_middle: Vector3 = Vector3.ZERO
var _post: int = -1


func _ready() -> void:
	_next_fire = fire_at
	set_physics_process(device_only)


func _exit_tree() -> void:
	for key: String in _down.keys():
		Input.action_release(KEY_ACTIONS[key])
	for action: StringName in _walked:
		Input.action_release(action)
	if is_instance_valid(_bot):
		_bot.queue_free()


## Bind to the match this source plays in; call once the local body is known.
func bind(controller: MatchController, local_body: PlayerController) -> void:
	match_controller = controller
	body = local_body
	_human = body.get_node_or_null(^"HumanInput") as HumanIntentSource if body != null else null
	if controller == null:
		return
	if marksman and not device_only and body != null:
		# The scope answers this source, as it answers a bot's brain: headless has no captured mouse to hold.
		_optic = body.get_node_or_null(^"Optic") as WeaponOptic
		var zoom: ZoomInput = body.get_node_or_null(^"ZoomInput") as ZoomInput
		if zoom != null:
			zoom.set_active(false)
	for node: Node in controller.get_tree().get_nodes_in_group(TowerShooter.POST_GROUP):
		if node is Marker3D:
			_posts.append((node as Marker3D).global_position)
			_posts_middle += (node as Marker3D).global_position
	if not _posts.is_empty():
		_posts_middle /= float(_posts.size())
	for sig: Signal in [controller.race_started, controller.round_started, controller.brawl_started]:
		sig.connect(func() -> void: _rearm = true)
	controller.ghost_respawned.connect(func(_p: MatchParticipant) -> void: _rearm = true)
	controller.ghost_caught.connect(func(_g: MatchParticipant, _c: MatchParticipant) -> void: _rearm = true)
	controller.seat_changed.connect(func(_p: MatchParticipant, _t: int) -> void: _rearm = true)


## "3@8+2,5@14,e@>1,f@>1.5,b@20+2/15": key@seconds[+hold][/every]; ">" counts from the previous press.
func set_keys(spec: String) -> void:
	_keys.clear()
	_repeats.clear()
	for part: String in spec.split(",", false):
		var at_split: PackedStringArray = part.strip_edges().split("@")
		if at_split.size() != 2 or not KEY_ACTIONS.has(at_split[0]):
			push_error("ScriptedIntentSource: bad key spec '%s'" % part)
			continue
		var timing: String = at_split[1]
		var every: float = 0.0
		if timing.contains("/"):
			every = float(timing.get_slice("/", 1))
			timing = timing.get_slice("/", 0)
		var hold: float = 0.0
		if timing.contains("+"):
			hold = float(timing.get_slice("+", 1))
			timing = timing.get_slice("+", 0)
		var relative: bool = timing.begins_with(">")
		_keys.append({"key": at_split[0], "at": float(timing.trim_prefix(">")), "relative": relative,
			"hold": hold, "every": every})


func get_role_name() -> String:
	return String(Role.keys()[_role])


func get_aimed() -> MatchParticipant:
	return _aimed


func _physics_process(delta: float) -> void:
	_elapsed += delta
	_drive_keys(_me())
	if device_walk:
		_walk_device()


func poll(delta: float) -> MoveIntent:
	_intent.clear()
	var me: MatchParticipant = _me()
	# A held body's commands move nothing: its script waits (clock and key schedule), but a key
	# already down stays down, as a player's finger would.
	var held: bool = me != null and me.body != null and me.body.held
	if not held:
		_elapsed += delta
		_drive_keys(me)
	if _human != null:
		_intent.copy_from(_human.poll(delta))
	if held:
		return _intent
	match mode:
		Mode.WALK:
			_walk(delta)
		Mode.PLAY:
			_play(me, delta)
	if mode != Mode.PLAY and me != null and me.is_shooter:
		_guard(me)
	elif _optic != null and (me == null or not me.is_shooter):
		_optic.set_zoomed(false)
	if _elapsed < _still_until:
		_intent.move_direction = Vector2.ZERO
		if not _down.has("j"):
			_intent.jump_pressed = false
			_intent.jump_held = false
		_intent.slide_pressed = false
		_intent.slide_held = false
	return _intent


func _me() -> MatchParticipant:
	return match_controller.get_human_participant() if match_controller != null else null


# --- Keys ---------------------------------------------------------------------

func _drive_keys(me: MatchParticipant) -> void:
	for key: String in _down.keys():
		if _elapsed >= _down[key]:
			_down.erase(key)
			Input.action_release(KEY_ACTIONS[key])
			key_released.emit(key)
	while not _keys.is_empty():
		var entry: Dictionary = _keys[0]
		var due: float = float(entry.at) + (_last_press if bool(entry.relative) else 0.0)
		if _elapsed < due or not _press(entry, me, due):
			break
		_keys.pop_front()
		if float(entry.every) > 0.0:
			entry.at = _elapsed + float(entry.every)
			entry.relative = false
			_repeats.append(entry)
	for entry: Dictionary in _repeats:
		if _elapsed >= float(entry.at) and _press(entry, me, float(entry.at)):
			entry.at = _elapsed + float(entry.every)


## Put one key down. False while it is being held back for a moment the body can use it.
func _press(entry: Dictionary, me: MatchParticipant, due: float) -> bool:
	var key: String = String(entry.key)
	if _down.has(key):
		return false
	if key == "b" or key == "n":
		# An emote wants a body at rest on the floor: stop first, press once it has.
		_still_until = maxf(_still_until, _elapsed + 0.5)
	if key == "j" or key == "f":
		# The brain's jumps or swings stand aside, so this key's press is an edge of its own.
		if not _owned(key):
			_own_since[key] = _elapsed
		_own_until[key] = maxf(_own_until.get(key, -1.0), _elapsed + 0.25 + float(entry.hold))
	var note: String = _why_not(key, me)
	if not note.is_empty() and keys_wait and _elapsed < due + KEY_PATIENCE_SECONDS:
		return false
	if not mute_keys:
		Input.action_press(KEY_ACTIONS[key])
	# One tick at least, so the press edge is read before the release.
	_down[key] = _elapsed + maxf(float(entry.hold), 0.0) + 0.02
	_last_press = _elapsed
	if key == "b" or key == "n" or key == "3":
		_still_until = _elapsed + float(entry.hold) + 0.3
	key_pressed.emit(key, note.is_empty(), note)
	return true


## Why this body could not act on [param key] this tick, or empty when it can.
func _why_not(key: String, me: MatchParticipant) -> String:
	if me == null or me.body == null:
		return "no-body"
	if me.body.held or not me.body.is_physics_processing():
		return "held"
	var in_hub: bool = match_controller.get_phase() == MatchController.Phase.HUB
	if not in_hub and not me.is_running:
		return "role-%s" % me.get_role_name()
	var power: RunnerPower = RunnerPower.of(me.body)
	match key:
		"1", "2", "3", "4", "5", "q":
			if power == null or power.rules == null:
				return "unarmed"
			if power.get_active() != MatchRules.RunnerAbility.NONE:
				return "busy-%d" % int(power.get_active())
			# One power at a time: a second power key in the tick of the first is ignored by the body.
			for other: String in _down:
				if other != key and POWER_KEYS.has(other):
					return "busy-key-%s" % other
			if power.get_cooldown_remaining() > 0.0:
				return "cooldown"
			if key == "q" and power.rules.runner_ability == MatchRules.RunnerAbility.NONE:
				return "no-picked-power"
		"e":
			if power == null or power.get_active() != MatchRules.RunnerAbility.CAT_GRENADE:
				return "no-cat"
		"j":
			if me.body.movement_locked:
				return "locked"
			if not me.body.is_on_floor():
				return "airborne"
			if _elapsed < _own_since.get(key, 0.0) + 0.05:
				return "settling"
		"f":
			if me.body.is_armed:
				return "armed"
			if me.body.shove_cooldown_remaining > 0.0:
				return "cooldown"
			if not me.body.swing_cost.is_valid() or float(me.body.swing_cost.call()) < 0.0:
				return "refused"
			if _elapsed < _own_since.get(key, 0.0) + 0.05:
				return "settling"
		"b", "n":
			if me.body.movement_locked:
				return "locked"
			if not me.body.is_on_floor():
				return "airborne"
			if me.body.velocity.length() > 0.3:
				_rest_ticks = 0
				return "moving"
			_rest_ticks += 1
			if _rest_ticks < 20:
				return "settling"
			_rest_ticks = 0
	return ""


# --- Movement -----------------------------------------------------------------

func _walk(delta: float) -> void:
	if _elapsed < 1.0:
		return
	var cycle: float = fmod(_elapsed - 1.0, walk_seconds + rest_seconds)
	if cycle < walk_seconds:
		_intent.move_direction = Vector2(0.0, 1.0)
		var burst: int = int((_elapsed - 1.0) / (walk_seconds + rest_seconds))
		_intent.look_delta = Vector2(yaw_rate * delta, pitch_rate * delta * (1.0 if burst % 2 == 0 else -1.0))


## Hub wandering on the device: forward and strafe in turns, jumps and mouse look.
func _walk_device() -> void:
	var phase: int = int(_elapsed / 1.5) % 4
	var still: bool = _elapsed < _still_until
	_hold(&"move_forward", phase != 2 and not still)
	_hold(&"move_left", phase == 1 and not still)
	_hold(&"move_right", phase == 3 and not still)
	_hold(&"move_back", phase == 2 and not still)
	_hold(&"jump", fmod(_elapsed, 2.3) < 0.1 and not still)
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.relative = Vector2(6.0, sin(_elapsed) * 3.0)
	Input.parse_input_event(motion)


func _hold(action: StringName, on: bool) -> void:
	_walked[action] = true
	if on and not Input.is_action_pressed(action):
		Input.action_press(action)
	elif not on and Input.is_action_pressed(action):
		Input.action_release(action)


func _play(me: MatchParticipant, delta: float) -> void:
	var role: Role = _role_of(me)
	if role != _role or (_rearm and role != Role.HELD):
		_enter(role, me)
	match _role:
		Role.RUN, Role.CHASE, Role.HUNT:
			var command: MoveIntent = _bot.poll(delta)
			_intent.move_direction = command.move_direction
			_intent.look_delta = command.look_delta
			if not _owned("j"):
				_intent.jump_pressed = command.jump_pressed
				_intent.jump_held = command.jump_held
			_intent.slide_pressed = command.slide_pressed
			_intent.slide_held = command.slide_held
			if not _owned("f"):
				_intent.shove_pressed = _intent.shove_pressed or command.shove_pressed
		Role.GUARD:
			_guard(me)
		Role.BRAWL:
			_brawl(me, delta)


func _role_of(me: MatchParticipant) -> Role:
	if me == null or me.body == null or me.body.held or not me.body.is_physics_processing():
		return Role.HELD
	var phase: MatchController.Phase = match_controller.get_phase()
	if phase == MatchController.Phase.BRAWL:
		return Role.BRAWL if me.is_running else Role.HELD
	if phase != MatchController.Phase.RACE and phase != MatchController.Phase.ROUND:
		return Role.HELD
	if me.is_shooter:
		return Role.GUARD
	if me.is_finisher:
		return Role.HUNT
	if me.is_running:
		return Role.RUN
	if me.is_ghost:
		return Role.CHASE
	return Role.HELD


## Stand the bot brain up for [param role], the way MatchController does for a bot seat.
func _enter(role: Role, me: MatchParticipant) -> void:
	_role = role
	if role != Role.HELD:
		_rearm = false
	_ensure_brain(me)
	if _brain != null:
		_brain.end_chase()
		_brain.set_physics_process(false)
		_bot.command.clear()
	role_changed.emit(get_role_name())
	if _brain == null or role == Role.HELD or role == Role.GUARD or role == Role.BRAWL:
		return
	var rules: MatchRules = match_controller.get_rules()
	var route: RingRoute = match_controller.get_route()
	_brain.rules = rules
	match role:
		Role.RUN:
			if route == null or me.tracker == null:
				return
			var level: int = me.tracker.get_level()
			_brain.profile.track_radius = route.lane_radius(level)
			_brain.resume(match_controller._centre, match_controller._start_point, match_controller._end_point,
				me.tracker.get_travelled_arc(), route, level)
		Role.CHASE:
			_brain.begin_chase(MatchController.RUNNER_GROUP)
		Role.HUNT:
			_brain.begin_hunt(MatchController.GUARD_GROUP)


func _ensure_brain(me: MatchParticipant) -> void:
	if _brain != null or me == null or me.body == null:
		return
	_bot = BotIntentSource.new()
	_bot.name = "HarnessBotInput"
	me.body.add_child(_bot)
	_bot.configure(me.body.profile)
	_brain = RunnerBrain.new()
	_brain.name = "HarnessBrain"
	_brain.controller = me.body
	_brain.input = _bot
	_brain.profile = (load(BOT_PROFILE) as BotProfile).duplicate() as BotProfile
	_brain.runner_profile = load(RUNNER_PROFILE) as RunnerProfile
	_brain.seat_index = me.index
	add_child(_brain)


## The tower: face the nearest running body in sight, hold the scope on it, pull on the cadence.
func _guard(me: MatchParticipant) -> void:
	_intent.move_direction = Vector2.ZERO
	var want: Vector2 = _aim_view(me) if aim_enabled else Vector2.INF
	var steady: bool = want.is_finite() or not aim_enabled
	if want.is_finite():
		var view: Vector2 = me.body.get_view_angles()
		_intent.look_delta = Vector2(angle_difference(want.x, view.x), -(want.y - view.y))
		_intent.aim_held = true
		if marksman:
			# Scope up, then the shot: from the hip the round goes anywhere in the rule's cone.
			steady = _intent.look_delta.length() <= AIM_SETTLED_RADIANS and (_optic == null or _optic.is_fully_zoomed())
	elif not aim_enabled:
		_intent.look_delta = Vector2(yaw_rate * get_physics_process_delta_time(), 0.0)
	if marksman and aim_enabled:
		_intent.move_direction = _walk_to_post(me)
		if _optic != null:
			_optic.set_zoomed(want.is_finite())
	if _next_fire > 0.0 and _elapsed >= _next_fire and steady:
		_intent.fire_pressed = true
		_intent.fire_held = true
		trigger_pulled.emit()
		_next_fire = _elapsed + fire_every if fire_every > 0.0 else -1.0


## Where a person stands to see the lane: the map's guard post nearest the bearing of a runner, if it has posts.
func _walk_to_post(me: MatchParticipant) -> Vector2:
	if _posts.is_empty():
		return Vector2.ZERO
	var here: Vector3 = me.body.global_position
	var gaze: Vector3 = _aimed.body.global_position if _aimed != null and _aimed.body != null else Vector3.INF
	if not gaze.is_finite():
		# Nobody in sight from here: go and look where the nearest runner by bearing is.
		var stand: Vector2 = _flat(_posts[_post] if _post >= 0 else here)
		var least: float = INF
		for p: MatchParticipant in match_controller.get_participants_ref():
			if p != me and p.body != null and p.is_running and absf(stand.angle_to(_flat(p.body.global_position))) < least:
				least = absf(stand.angle_to(_flat(p.body.global_position)))
				gaze = p.body.global_position
	if gaze.is_finite():
		var held: float = absf(_flat(_posts[_post]).angle_to(_flat(gaze))) - TowerShooter.POST_SWITCH_HYSTERESIS if _post >= 0 else INF
		for index: int in _posts.size():
			var offset: float = absf(_flat(_posts[index]).angle_to(_flat(gaze)))
			if offset < held:
				held = offset
				_post = index
	if _post < 0:
		return Vector2.ZERO
	var away: Vector3 = _posts[_post] - here
	away.y = 0.0
	var distance: float = away.length()
	if distance <= TowerShooter.POST_REACHED_METRES:
		return Vector2.ZERO
	var frame: Basis = me.body.global_transform.basis
	return Vector2(away.dot(frame.x), -away.dot(frame.z)) / distance * minf(distance / TowerShooter.POST_EASE_METRES, 1.0)


## [param point] on the ground plane, told from the middle of the posts.
func _flat(point: Vector3) -> Vector2:
	return Vector2(point.x - _posts_middle.x, point.z - _posts_middle.z)


## The view that puts this body's camera on the chest of the nearest running body it can see.
func _aim_view(me: MatchParticipant) -> Vector2:
	_aimed = null
	var camera: Node3D = me.body.get_node_or_null(^"Head/Camera") as Node3D
	if camera == null:
		return Vector2.INF
	var eye: Vector3 = camera.global_position
	var best: float = INF
	var at: Vector3 = Vector3.INF
	for p: MatchParticipant in match_controller.get_participants_ref():
		if p == me or p.body == null or not p.is_running:
			continue
		# Where this machine draws it, as a person aims: the host draws others a little behind.
		var link: PlayerNetLink = PlayerNetLink.of(p.body)
		var chest: Vector3 = (link.drawn_position() if link != null else p.body.global_position) + Vector3.UP * 0.9
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(eye, chest)
		query.exclude = [me.body.get_rid()]
		var hit: Dictionary = me.body.get_world_3d().direct_space_state.intersect_ray(query)
		if (not hit.is_empty() and hit.collider != p.body) or eye.distance_to(chest) >= best:
			continue
		best = eye.distance_to(chest)
		at = chest
		_aimed = p
	if _aimed == null:
		return Vector2.INF
	var rifle: Rifle = match_controller.rifle
	var speed: float = rifle.get_shot_speed() if rifle != null else 0.0
	if speed > 0.0:
		# Lead a travelling shot as the tower bot does: flight time, then the fall over it.
		var velocity: Vector3 = _aimed.body.velocity
		var flight: float = (at - eye + velocity * ((at - eye).length() / speed)).length() / speed
		at += velocity * flight
		if rifle.profile != null:
			at.y += 0.5 * rifle.profile.projectile_gravity * flight * flight
	var dir: Vector3 = (at - eye).normalized()
	return Vector2(atan2(-dir.x, -dir.z), asin(clampf(dir.y, -1.0, 1.0)))


## The tower fight: walk at the nearest standing rival and shove it.
func _brawl(me: MatchParticipant, delta: float) -> void:
	_brawl_rest = maxf(_brawl_rest - delta, 0.0)
	var here: Vector3 = me.body.global_position
	var target: MatchParticipant = null
	var best: float = INF
	for p: MatchParticipant in match_controller.get_participants_ref():
		if p == me or p.body == null or not p.is_running:
			continue
		var d: float = here.distance_to(p.body.global_position)
		if d < best:
			best = d
			target = p
	if target == null:
		return
	var to: Vector3 = target.body.global_position - here
	var want_yaw: float = atan2(-to.x, -to.z)
	_intent.look_delta = Vector2(angle_difference(want_yaw, me.body.get_view_angles().x), 0.0)
	_intent.move_direction = Vector2(0.0, 1.0 if best > 1.2 else 0.0)
	if best < 2.2 and _brawl_rest <= 0.0 and not _owned("f"):
		_intent.shove_pressed = true
		_brawl_rest = BRAWL_SHOVE_REST


## True while [param key] is this source's to press: the brain's own presses of it stand aside.
func _owned(key: String) -> bool:
	return _elapsed < _own_until.get(key, -1.0)
