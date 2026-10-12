extends RefCounted

## A take as data: every body's intent per physics tick, every outside write to a body, every
## trigger pull. Recorded once from the staged take; played back, it is the same shot every time.

const PHASE_SCRIPT := preload("res://tools/capture/clip_tape_phase.gd")
const VERSION: int = 2
const PRE: int = 0
const MID: int = 1
const LATE: int = 2
## Intent flag bits, in MoveIntent's field order.
const BITS: Array[String] = [
	"jump_pressed", "jump_held", "slide_pressed", "slide_held", "fire_pressed", "fire_held",
	"ability_pressed", "ability_held", "shove_pressed", "turbo_held", "godmode",
]
## The engine meta a guard hand reads: while a tape plays, only the tape pulls the trigger.
const PLAYING_META: StringName = &"clip_tape_playing"

var playing: bool = false
var path: String = ""
var header: Dictionary = {}
var _controller: MatchController = null
var _bodies: Array[PlayerController] = []
var _tick: int = -1
var _phase: int = PRE
var _mid: Dictionary = {}          # body name -> snapshot after the bodies ran
var _late: Dictionary = {}         # body name -> snapshot at the end of the physics tick
var _target: Dictionary = {}       # body name -> what the last phase left (playback)
var _intent := MoveIntent.new()
var _raw: Dictionary = {}          # body name -> the intent as handed in, before the body normalised it
var _scratch := PackedFloat32Array()
# The tape: name -> {"intent": [[tick, ...]], "late": {tick: writes after the bodies}, "pre": {tick: writes
# between ticks}}; fires [[tick, phase, rifle]]. Each write is played where it was made, so a stage decides alike.
var _tracks: Dictionary = {}
var _fires: Array = []
var _crouch_ticks: int = 0
var _fires_by_tick: Dictionary = {}
var _untaped_fires: int = 0
var _firing: bool = false
var _rifles: Dictionary = {}       # "guard" / "finisher" -> the Rifle, connected once


## Hang the three phase nodes: PRE first in every tick, MID right after the match's own bodies, LATE last.
func install(root: Window, match_root: Node, controller: MatchController, tape_path: String, play: bool) -> bool:
	_controller = controller
	path = tape_path
	playing = play
	if playing and not _load():
		return false
	Engine.set_meta(PLAYING_META, playing)
	var priorities: Array[int] = [-1000, 0, 1000]
	for phase: int in [PRE, MID, LATE]:
		var node: Node = PHASE_SCRIPT.new()
		node.name = "ClipTape%s" % ["Pre", "Mid", "Late"][phase]
		node.set("deck", self)
		node.set("phase", phase)
		node.process_physics_priority = priorities[phase]
		root.add_child(node)
		if phase == MID:
			root.move_child(node, match_root.get_index() + 1)
	print("[tape] %s %s" % ["playing" if playing else "recording", path])
	return true


func on_phase(phase: int) -> void:
	_phase = phase
	if phase == PRE:
		_tick += 1
		if _bodies.is_empty():
			_collect()
		_watch_rifle("guard", _controller.rifle)
		# The finale is a shove now; a controller without a finisher rifle has none to watch.
		if _controller.has_method(&"get_finisher_rifle"):
			_watch_rifle("finisher", _controller.call(&"get_finisher_rifle"))
	if playing and phase != MID:
		_lock_brains()
	if _bodies.is_empty():
		return
	if playing:
		_play(phase)
	else:
		_record(phase)
	if phase == MID and OS.has_environment("TAPE_TRACE"):
		for body: PlayerController in _bodies:
			print("[trace] %d %s %s %s" % [_tick, body.name, body.global_transform, body.velocity])


## Every participant's body, in match order: the guard is one of them.
func _collect() -> void:
	for participant: MatchParticipant in _controller.get_participants():
		if participant.body != null:
			_bodies.append(participant.body)
			if not _tracks.has(String(participant.body.name)):
				_tracks[String(participant.body.name)] = {"intent": [], "late": {}, "pre": {}}


# --- Recording ----------------------------------------------------------------

func _record(phase: int) -> void:
	for body: PlayerController in _bodies:
		if not is_instance_valid(body):
			continue
		var key: String = String(body.name)
		var track: Dictionary = _tracks[key]
		if phase == PRE:
			var source: BotIntentSource = body.intent_source as BotIntentSource
			_raw[key] = _intent_row(source.command if source != null else body.get_intent())
			var now: Dictionary = _snapshot(body)
			if _tick == 0 or not _late.has(key):
				track["pre"][_tick] = now
			else:
				_keep(track["pre"], _tick, _diff(_late[key], now))
		elif phase == LATE:
			_late[key] = _snapshot(body)
			_keep(track["late"], _tick, _diff(_mid[key], _late[key]))
		else:
			_mid[key] = _snapshot(body)
			var row: Array = _intent_row(body.get_intent())
			# The raw intent when it normalises to what the body consumed: normalise is not idempotent to the bit.
			if _raw.has(key):
				_intent_from([0] + (_raw[key] as Array), _intent)
				_intent.normalise()
				if body.intent_source is BotIntentSource:
					_intent.normalise()
				if _intent_row(_intent) == row:
					row = _raw[key]
			var rows: Array = track["intent"]
			if rows.is_empty() or (rows[rows.size() - 1] as Array).slice(1) != row:
				rows.append([_tick] + row)
			if body.get_intent().slide_held or body.get_intent().slide_pressed:
				_crouch_ticks += 1


func _keep(writes: Dictionary, tick: int, changed: Dictionary) -> void:
	if not changed.is_empty():
		writes[tick] = changed


func _watch_rifle(id: String, rifle: Rifle) -> void:
	if rifle != null and _rifles.get(id) != rifle:
		_rifles[id] = rifle
		rifle.fired.connect(_on_fired.bind(id))


func _on_fired(_origin: Vector3, _end: Vector3, id: String) -> void:
	if playing:
		if not _firing:
			_untaped_fires += 1
			print("[tape] WARNING an untaped %s shot at tick %d" % [id, _tick])
		return
	# Inside the bodies' own tick (a brain's trigger) plays at MID, after them; after MID plays at LATE.
	_fires.append([_tick, MID if _phase == PRE else LATE, id])


## No brain pulls a trigger while a tape plays: every shot is the tape's.
func _lock_brains() -> void:
	for body: PlayerController in _bodies:
		if not is_instance_valid(body):
			continue
		for child: Node in body.get_children():
			var brain: TowerShooter = child as TowerShooter
			if brain != null and brain.profile != null:
				brain.profile.shot_confidence_threshold = 2.0
				brain.profile.sure_shot_confidence = 2.0


## Write the tape. Called once when the clip ends.
func finish() -> void:
	for body: PlayerController in _bodies:
		if is_instance_valid(body):
			print("[tape] end %s %v %v" % [body.name, body.global_position, body.rotation])
	if playing:
		print("[tape] played %d ticks, %d untaped shots" % [_tick + 1, _untaped_fires])
		return
	var out_tracks: Dictionary = {}
	for key: String in _tracks:
		var track: Dictionary = _tracks[key]
		var out: Dictionary = {"intent": track["intent"]}
		for when: String in ["late", "pre"]:
			var by_tick: Dictionary = {}
			for tick: int in track[when]:
				by_tick[str(tick)] = _encode(track[when][tick])
			out[when] = by_tick
		out_tracks[key] = out
	var data: Dictionary = header.duplicate()
	data["tape"] = VERSION
	data["ticks"] = _tick + 1
	data["physics_ticks_per_second"] = Engine.physics_ticks_per_second
	data["crouch_ticks"] = _crouch_ticks
	data["fires"] = _fires
	data["bodies"] = out_tracks
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		printerr("[tape] cannot write %s" % path)
		return
	file.store_string(JSON.stringify(data, "", true, true))
	file.close()
	print("[tape] wrote %s: %d ticks, %d bodies, %d shots, %d crouched ticks" % [path, _tick + 1, out_tracks.size(), _fires.size(), _crouch_ticks])


# --- Playing ------------------------------------------------------------------

func _load() -> bool:
	var text: String = FileAccess.get_file_as_string(path)
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY or int((data as Dictionary).get("tape", 0)) != VERSION:
		printerr("[tape] %s is not a tape" % path)
		return false
	header = data
	if int(header.get("physics_ticks_per_second", 60)) != Engine.physics_ticks_per_second:
		printerr("[tape] recorded at %d ticks/s, playing at %d" % [int(header["physics_ticks_per_second"]), Engine.physics_ticks_per_second])
		return false
	for key: String in (header["bodies"] as Dictionary):
		var raw: Dictionary = header["bodies"][key]
		var track: Dictionary = {"intent": raw["intent"], "cursor": 0}
		for when: String in ["late", "pre"]:
			var writes: Dictionary = {}
			for tick: String in (raw[when] as Dictionary):
				writes[int(tick)] = _decode(raw[when][tick])
			track[when] = writes
		_tracks[key] = track
	for fire: Variant in header.get("fires", []):
		var at: Array = fire
		var slot: String = "%d:%d" % [int(at[0]), int(at[1])]
		var rifles: Array = _fires_by_tick.get(slot, [])
		rifles.append(String(at[2]) if at.size() > 2 else "guard")
		_fires_by_tick[slot] = rifles
	return true


func _play(phase: int) -> void:
	for body: PlayerController in _bodies:
		if not is_instance_valid(body):
			continue
		var key: String = String(body.name)
		if not _tracks.has(key):
			continue
		var track: Dictionary = _tracks[key]
		if phase == MID:
			_mid[key] = _snapshot(body)
			continue
		var target: Dictionary = (_mid[key] if phase == LATE else _target.get(key, {})).duplicate()
		var writes: Dictionary = track["late" if phase == LATE else "pre"]
		if writes.has(_tick):
			target.merge(writes[_tick], true)
		_write(body, target)
		_target[key] = target
		_feed(body, track, _tick + 1 if phase == LATE else _tick)
	_pull(phase)


## Fire the rifle where the take fired it.
func _pull(phase: int) -> void:
	var slot: String = "%d:%d" % [_tick, phase]
	if not _fires_by_tick.has(slot):
		return
	for id: String in _fires_by_tick[slot]:
		var rifle: Rifle = _rifles.get(id) as Rifle
		_firing = true
		var ok: bool = rifle != null and rifle.try_fire()
		_firing = false
		print("[tape] tick %d %s shot %s" % [_tick, id, "fired" if ok else "REFUSED (%s)" % (rifle.get_state_name() if rifle != null else "no rifle")])


## The recorded intent for [param tick], through whichever path the body reads this tick.
func _feed(body: PlayerController, track: Dictionary, tick: int) -> void:
	var rows: Array = track["intent"]
	var cursor: int = int(track["cursor"])
	while cursor + 1 < rows.size() and int(rows[cursor + 1][0]) <= tick:
		cursor += 1
	track["cursor"] = cursor
	_intent.clear()
	if not rows.is_empty() and int(rows[cursor][0]) <= tick:
		_intent_from(rows[cursor], _intent)
	var source: BotIntentSource = body.intent_source as BotIntentSource
	if source != null:
		source.shove_enabled = false
		source.command.copy_from(_intent)
	body.set_intent(_intent)


# --- Body state ---------------------------------------------------------------

func _snapshot(body: PlayerController) -> Dictionary:
	body.capture_motion_state(_scratch)
	var optic: WeaponOptic = body.get_node_or_null(^"Optic") as WeaponOptic
	return {
		"xform": body.global_transform,
		"vel": body.velocity,
		"head": body.head.rotation.x if body.head != null else 0.0,
		"motion": _scratch.duplicate(),
		"zoom": optic.is_zoom_requested() if optic != null else false,
	}


func _diff(before: Dictionary, after: Dictionary) -> Dictionary:
	var changed: Dictionary = {}
	for field: String in after:
		if before.get(field) != after[field]:
			changed[field] = after[field]
	return changed


## Put [param target]'s fields on the body where they differ from what it has now.
func _write(body: PlayerController, target: Dictionary) -> void:
	if target.has("xform") and body.global_transform != target["xform"]:
		body.global_transform = target["xform"]
	if target.has("vel") and body.velocity != target["vel"]:
		body.velocity = target["vel"]
	if target.has("motion"):
		body.capture_motion_state(_scratch)
		if _scratch != target["motion"]:
			body.restore_motion_state(target["motion"])
	if target.has("head") and body.head != null and body.head.rotation.x != float(target["head"]):
		body.head.rotation.x = target["head"]
	var optic: WeaponOptic = body.get_node_or_null(^"Optic") as WeaponOptic
	if target.has("zoom") and optic != null and optic.is_zoom_requested() != bool(target["zoom"]):
		optic.set_zoomed(bool(target["zoom"]))


func _intent_row(intent: MoveIntent) -> Array:
	var bits: int = 0
	for index: int in BITS.size():
		if bool(intent.get(BITS[index])):
			bits |= 1 << index
	return [intent.move_direction.x, intent.move_direction.y, intent.look_delta.x, intent.look_delta.y, bits, intent.ability_slot]


static func _intent_from(row: Array, out: MoveIntent) -> void:
	out.move_direction = Vector2(float(row[1]), float(row[2]))
	out.look_delta = Vector2(float(row[3]), float(row[4]))
	var bits: int = int(row[5])
	for index: int in BITS.size():
		out.set(BITS[index], (bits & (1 << index)) != 0)
	out.ability_slot = int(row[6])


static func _encode(state: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for field: String in state:
		var value: Variant = state[field]
		if value is Vector3:
			out[field] = [value.x, value.y, value.z]
		elif value is Transform3D:
			var t: Transform3D = value
			out[field] = [t.basis.x.x, t.basis.x.y, t.basis.x.z, t.basis.y.x, t.basis.y.y, t.basis.y.z,
				t.basis.z.x, t.basis.z.y, t.basis.z.z, t.origin.x, t.origin.y, t.origin.z]
		elif value is PackedFloat32Array:
			out[field] = Array(value)
		else:
			out[field] = value
	return out


static func _decode(state: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for field: String in state:
		var value: Variant = state[field]
		match field:
			"vel":
				out[field] = Vector3(float(value[0]), float(value[1]), float(value[2]))
			"xform":
				var v: Array = value
				out[field] = Transform3D(
					Vector3(float(v[0]), float(v[1]), float(v[2])), Vector3(float(v[3]), float(v[4]), float(v[5])),
					Vector3(float(v[6]), float(v[7]), float(v[8])), Vector3(float(v[9]), float(v[10]), float(v[11])))
			"motion":
				out[field] = PackedFloat32Array(value)
			"zoom":
				out[field] = bool(value)
			_:
				out[field] = float(value)
	return out
