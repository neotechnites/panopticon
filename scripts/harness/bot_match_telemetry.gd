class_name BotMatchTelemetry
extends Node

## Watches one match and counts what a balance question is actually made of.
##
## Every number here comes from a [MatchController] SIGNAL or a [Rifle] signal.
## Nothing is read out of the match's internals and nothing is inferred from a
## field name, so this file keeps working across a re-authored match as long as
## the signals keep their meanings. Where the match grows a concept the harness
## cannot see -- a fifth signal, a new phase -- the effect is a missing column,
## not a wrong one.
##
## [b]The clock[/b]
##
## Time is counted in PHYSICS TICKS and divided by the simulated rate at the
## end. Not [method Time.get_ticks_msec], which under time compression measures
## the host machine, and not an accumulated delta, which accumulates float error
## over the tens of thousands of ticks a long match takes. A tick count is exact
## and is the same number on every machine.

## Ticks elapsed since the match started, counted by this node's own physics
## callback. [member Node.process_priority] is lowered by the installer so this
## runs before the match does, and a signal fired later in the same tick is
## attributed to the tick it happened in.
var _ticks: int = 0

var _controller: MatchController = null
var _rifle: Rifle = null

var _tallies: Dictionary[int, BotParticipantTally] = {}
var _order: Array[int] = []

var _participants_total: int = 0
var _race_ran: bool = false
var _rounds_started: int = 0
var _rounds_resolved: int = 0
var _round_wins: int = 0
var _round_losses: int = 0
var _seat_changes: int = 0
var _conversions: int = 0

## Conversions that were a hazard entry on the same tick, not a rifle hit.
var _hazard_deaths: int = 0
var _removed_tick: int = -1
var _hazard_attributed: Dictionary = {}

const STALL_WINDOW_TICKS: int = 180
const STALL_DISTANCE_METRES: float = 1.0

## The named stretches of one map, as game bearings about the arena axis and the
## radial bands a route through them can take. See docs/MAP1_SECTIONS.md.
##
## This is the only map knowledge in the harness and it is deliberately not in
## the bots: a section is a thing to MEASURE play in, and a runner that had been
## told where the forest was would stop being an instrument. A map the table has
## no entry for simply reports no sections.
const SECTION_MAP_ID: StringName = &"bentham_ring"
const SECTIONS: Array = [
	{"id": "S1", "from": 15.0, "to": 60.0, "bands": [["inner", 50.7], ["middle", 53.3], ["outer", 99.0]]},
	{"id": "S2", "from": 75.0, "to": 130.0, "bands": [["lane", 52.5], ["chain", 99.0]]},
	{"id": "S3", "from": 145.0, "to": 200.0, "bands": [["inner", 54.5], ["outer", 99.0]]},
	{"id": "S4", "from": 215.0, "to": 270.0, "bands": [["lane", 53.0], ["rocks", 99.0]]},
	{"id": "S5", "from": 292.0, "to": 338.0, "bands": [["inner", 52.0], ["stones", 99.0]]},
]
## Ticks a body must spend in a section before the way it went counts as a route.
const ROUTE_MIN_TICKS: int = 30

## Per participant: the section pass being watched, as {"id", "bands", "ticks"}.
var _pass: Dictionary = {}
var _sections_live: bool = false

## Every [TrapVolume] in the arena, as {inverse, half, centre, reach_squared, feet}.
##
## Standing in lava is counted from these and not from the trap's own signal,
## which cannot be trusted here: a feet_only trap decides depth in [method
## Node._process], and under 120x compression a body crosses six metres of lava
## between two process frames and is never once seen overlapping. The trap is
## right in the game and blind in the harness, so the harness measures the
## geometry itself.
var _traps: Array[Dictionary] = []

## Whether each life was a clean run. See [BotRunWatch].
var _runs: BotRunWatch = BotRunWatch.new(60)

## Per participant: where it stood last tick, and whether it was running.
var _last_point: Dictionary = {}
var _was_running: Dictionary = {}
## Per participant: lava flights taken, as the brain counts them.
var _hops_seen: Dictionary = {}
## Where each life ended, rounded. Diagnostics for a map bodies keep leaving.
var _removals: Array = []
## Metres a body may move in one tick before it is a re-placement, not a stride.
const TELEPORT_METRES: float = 20.0

## Per participant index: stall window origin, hold and stall streaks.
var _watch: Dictionary = {}
var _round_tick: int = -1
var _first_shot_pending: bool = false
var _rounds_without_a_shot: int = 0
var _first_shots: Array[float] = []

## Wall microseconds per physics tick, and what the bots charged inside it.
var _last_tick_usec: int = -1
var _tick_max_usec: int = 0
var _tick_sum_usec: int = 0
var _cost_max: Dictionary = {}
var _cost_sum: Dictionary = {}
var _tick_over_16ms: int = 0

## Participants turned into ghosts, by either route: shot by the rifle, or caught
## by another ghost. Zero on every ghostless match, which is what makes it safe
## to leave in the schema unconditionally.
var _ghosts_made: int = 0

## Ghost swaps: a ghost reaching a living prisoner and taking their spot. The one
## number the whole mechanic is about -- a ghost round with no catches in it is a
## round where the speed advantage was not enough.
var _ghost_catches: int = 0

var _shots_fired: int = 0
var _shots_hit_participant: int = 0
var _shots_hit_world: int = 0
var _shots_hit_nothing: int = 0

## Who holds the tower and since when, so the seat's time can be closed out on
## the next change. -1 means nobody, which is the truth during the opening race.
var _seat_index: int = -1
var _seat_since_tick: int = 0

## Who fired the shot currently being resolved.
##
## Separate from [member _seat_index] because of an ordering that cost a shot
## the first time it was measured: [MatchController] connects to
## [signal Rifle.target_hit] before the harness does, so a shot that converts
## the last runner has already run the whole match-winning cascade -- resolve,
## award, freeze, [signal MatchController.match_won] -- by the time this file
## sees the hit, and the seat has been closed out. Attributing shots to the
## seat's LAST KNOWN holder instead of its CURRENT one credits that shot to the
## bot that actually took it. It is only ever wrong if a shot is fired by
## nobody, which cannot happen: there is one rifle and the match hands it to
## the seat.
var _shooter_index: int = -1

var _winner_index: int = -1
var _winner_was_seat: bool = false
var _match_over: bool = false


func install(controller: MatchController, rifle: Rifle) -> void:
	_controller = controller
	_rifle = rifle

	controller.match_started.connect(_on_match_started)
	controller.race_started.connect(_on_race_started)
	controller.round_started.connect(_on_round_started)
	controller.seat_changed.connect(_on_seat_changed)
	controller.round_resolved.connect(_on_round_resolved)
	controller.runner_removed.connect(_on_runner_removed)
	controller.runner_ghosted.connect(_on_runner_ghosted)
	controller.ghost_caught.connect(_on_ghost_caught)
	controller.match_won.connect(_on_match_won)

	rifle.fired.connect(_on_fired)
	rifle.target_hit.connect(_on_target_hit)
	rifle.missed.connect(_on_missed)
	_connect_hazards(controller.arena)
	_sections_live = controller.rules != null and controller.rules.map_id == SECTION_MAP_ID


func _connect_hazards(node: Node) -> void:
	if node == null:
		return
	if node is TrapVolume:
		var trap: TrapVolume = node as TrapVolume
		var half: Vector3 = trap.size_metres * 0.5
		_traps.append({
			"inverse": trap.global_transform.affine_inverse(),
			"centre": trap.global_position,
			"reach_squared": Vector2(half.x, half.z).length_squared(),
			"half": half,
			"feet": trap.feet_only,
		})
		(node as Area3D).body_entered.connect(_on_hazard_entered.bind(true))
	elif node is KillVolume:
		(node as Area3D).body_entered.connect(_on_hazard_entered.bind(false))
	elif node is BoostPad:
		(node as Area3D).body_entered.connect(_on_pad_entered)
	for child: Node in node.get_children():
		_connect_hazards(child)


## Runs after the hazard's own handler: a removal on this tick was the hazard's doing.
func _on_hazard_entered(body: Node3D, lava: bool) -> void:
	if _removed_tick != _ticks:
		return
	var participant: MatchParticipant = _controller.resolve_participant(body)
	if participant == null or participant.is_shooter:
		return
	if int(_hazard_attributed.get(participant.index, -1)) == _ticks:
		return
	_hazard_attributed[participant.index] = _ticks
	_hazard_deaths += 1
	var tally: BotParticipantTally = _tallies.get(participant.index, null)
	if tally != null:
		tally.hazard_deaths += 1
		if lava:
			tally.lava_deaths += 1
		else:
			tally.falls += 1
		var section: Dictionary = _section_of(body.global_position)
		if not section.is_empty():
			var entry: Dictionary = tally.section(String(section["id"]))
			var key: String = "lava" if lava else "falls"
			entry[key] = int(entry[key]) + 1


func _on_pad_entered(body: Node3D) -> void:
	var participant: MatchParticipant = _controller.resolve_participant(body)
	var tally: BotParticipantTally = _tallies.get(participant.index, null) if participant != null else null
	if tally == null:
		return
	tally.pad_launches += 1
	var section: Dictionary = _section_of(body.global_position)
	if not section.is_empty():
		var entry: Dictionary = tally.section(String(section["id"]))
		entry["flights"] = int(entry["flights"]) + 1


func _physics_process(_delta: float) -> void:
	_ticks += 1
	var now: int = Time.get_ticks_usec()
	if _last_tick_usec >= 0:
		var spent: int = now - _last_tick_usec
		_tick_max_usec = maxi(_tick_max_usec, spent)
		_tick_sum_usec += spent
		if spent > 16000:
			_tick_over_16ms += 1
		for kind: String in RingNavigation.cost_usec:
			var usec: int = int(RingNavigation.cost_usec[kind])
			_cost_max[kind] = maxi(int(_cost_max.get(kind, 0)), usec)
			_cost_sum[kind] = int(_cost_sum.get(kind, 0)) + usec
	RingNavigation.cost_usec.clear()
	_last_tick_usec = now
	if _controller != null:
		_sample_runners()
		if _trace_every > 0 and _ticks % _trace_every == 0:
			_trace_match()
			_trace_runners()
		_sample_round_wait()


## Ticks between trace lines; set by PANOPTICON_TRACE (seconds, 0 is off).
var _trace_every: int = int(60.0 * float(OS.get_environment("PANOPTICON_TRACE")))


## One diagnostic line per live runner: where it is, what it is doing, what it sees.
func _trace_runners() -> void:
	for participant: MatchParticipant in _controller.get_participants_ref():
		var brain: RingRunner = participant.brain
		if brain == null or participant.body == null or not participant.is_running:
			continue
		if not participant.body.is_physics_processing():
			continue
		var position: Vector3 = participant.body.global_position
		var perception: RunnerPerception = brain.get_perception()
		var cover: RunnerCoverFinder = brain.get("_cover")
		var anchor: Vector3 = brain.get("_anchor")
		print(
			"TRACE t=%.1f p%d %-8s bear=%6.1f pos=(%.1f,%.1f,%.1f) spd=%.2f wp=%d arc=%.1f"
			% [
				float(_ticks) / 60.0, participant.index, brain.get_state_name(),
				rad_to_deg(atan2(position.z, position.x)),
				position.x, position.y, position.z,
				participant.body.get_horizontal_speed(),
				int(brain.get("_wp")), rad_to_deg(brain.get_travelled_arc()),
			]
			+ (" threat=%d exposed=%d watched=%d shots=%d reload=%.2f hold=%.1f conf=%.2f/%.2f open=%.1f"
			% [
				int(perception.has_threat()), int(perception.is_exposed()),
				int(perception.believes_watched()), perception.get_shots_heard(),
				perception.get_believed_reload_remaining(),
				float(brain.get("_hold_seconds")), brain.get_last_break_confidence(),
				brain.get_last_break_threshold(), brain.get_last_exposed_metres(),
			])
			+ (" tgt=%d cov=%d/%d anchor=(%.1f,%.1f,%.1f) x=%d"
			% [
				int(brain.get("_has_target")), int(cover.has_result()), int(cover.is_complete()),
				anchor.x, anchor.y, anchor.z, brain.get_crossings(),
			])
		)


## Seconds a finisher has been armed, and the longest any one finisher held it.
var _finisher_ticks: int = 0
var _finisher_ticks_max: int = 0
var _finisher_armed_count: int = 0

## Ticks of the round in which the guard's brain had no visible target at all.
var _guard_starved_ticks: int = 0
var _guard_reload_ticks: int = 0
var _guard_round_ticks: int = 0

## Runners standing at the portal with their lap finished, waiting on nothing.
var _idle_at_portal_ticks: int = 0

## Starved-guard ticks with an exposed runner on the ring, and with one inside
## the arc the guard was facing.
var _guard_blind_ticks: int = 0
var _guard_blind_in_arc_ticks: int = 0
var _guard_blind_clear_ticks: int = 0

const BLIND_ARC_RADIANS: float = 1.05


## True when a ray from the guard's head reaches [param target]'s chest.
func _eye_reaches(guard: PlayerController, target: PlayerController) -> bool:
	var space: PhysicsDirectSpaceState3D = guard.get_world_3d().direct_space_state
	if space == null:
		return false
	var from: Vector3 = guard.head.global_position if guard.head != null else guard.global_position
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		from, target.global_position + Vector3.UP * 0.9
	)
	query.exclude = [guard.get_rid()]
	var hit: Dictionary = space.intersect_ray(query)
	return hit.is_empty() or (hit.get("collider", null) as Node3D) == target


## Was the starved guard merely looking elsewhere, or looking straight at an
## exposed runner and not seeing it? Sampled only on a tick with no target.
func _sample_blind(seat: MatchParticipant) -> void:
	var body: PlayerController = seat.body
	if body == null:
		return
	var forward: Vector2 = Vector2(-body.global_transform.basis.z.x, -body.global_transform.basis.z.z)
	var exposed: int = 0
	var in_arc: int = 0
	var clear: int = 0
	for participant: MatchParticipant in _controller.get_participants_ref():
		if not participant.is_running or participant.brain == null or participant.body == null:
			continue
		var perception: RunnerPerception = participant.brain.get_perception()
		if perception == null or not perception.has_threat() or not perception.is_exposed():
			continue
		exposed += 1
		var to: Vector3 = participant.body.global_position - body.global_position
		if absf(forward.angle_to(Vector2(to.x, to.z))) > BLIND_ARC_RADIANS:
			continue
		in_arc += 1
		if _eye_reaches(body, participant.body):
			clear += 1
	if exposed > 0:
		_guard_blind_ticks += 1
	if in_arc > 0:
		_guard_blind_in_arc_ticks += 1
	if clear > 0:
		_guard_blind_clear_ticks += 1


## One line per trace interval saying what the ROUND is waiting on.
func _trace_match() -> void:
	print("MATCH %s" % JSON.stringify(_round_state()))


## Per-tick counters for the stall causes: a starved guard, a stuck finisher.
func _sample_round_wait() -> void:
	if _controller.get_phase() != MatchController.Phase.ROUND or _controller.is_resolved():
		return
	_guard_round_ticks += 1
	var seat: MatchParticipant = _controller.get_seat_participant()
	var guard: TowerShooter = seat.tower_brain if seat != null else null
	if guard != null and guard.is_physics_processing():
		if guard.get_target() == null:
			_guard_starved_ticks += 1
			_sample_blind(seat)
		if guard.get_state() == TowerShooter.State.RECOVERING:
			_guard_reload_ticks += 1
	if _controller.get_finisher() != null:
		if _finisher_ticks == 0:
			_finisher_armed_count += 1
		_finisher_ticks += 1
		_finisher_ticks_max = maxi(_finisher_ticks_max, _finisher_ticks)
	else:
		_finisher_ticks = 0
	for participant: MatchParticipant in _controller.get_participants_ref():
		if (
			participant.is_running and not participant.is_finisher
			and participant.tracker != null and participant.tracker.has_finished()
		):
			_idle_at_portal_ticks += 1


## Everything a stalled round is made of, as plain data.
func _round_state() -> Dictionary:
	var seat: MatchParticipant = _controller.get_seat_participant()
	var finisher: MatchParticipant = _controller.get_finisher()
	var out: Dictionary = {
		"t": float(_ticks) / 60.0,
		"phase": _controller.get_phase_name(),
		"round": _controller.get_round_number(),
		"seat": seat.index if seat != null else -1,
		"alive": _controller.get_runners_remaining(),
		"ghosts": _controller.get_ghosts_remaining(),
		"guard": _brain_state(seat),
		"finisher": -1 if finisher == null else finisher.index,
		"finisher_brain": _brain_state(finisher),
		"finisher_armed_s": float(_finisher_ticks) / 60.0,
	}
	var runners: Array = []
	for participant: MatchParticipant in _controller.get_participants_ref():
		if participant.is_shooter:
			continue
		runners.append({
			"i": participant.index,
			"run": participant.is_running,
			"ghost": participant.is_ghost,
			"fin": participant.is_finisher,
			"done": participant.tracker != null and participant.tracker.has_finished(),
			"left_m": participant.tracker.get_metres_remaining() if participant.tracker != null else -1.0,
			"state": participant.brain.get_state_name() if participant.brain != null else "",
		})
	out["runners"] = runners
	return out


## One participant's tower brain, as state name / target / shots asked and taken.
func _brain_state(participant: MatchParticipant) -> Dictionary:
	var brain: TowerShooter = participant.tower_brain if participant != null else null
	if brain == null:
		return {}
	return {
		"i": participant.index,
		"on": brain.is_physics_processing(),
		"state": brain.get_state_name(),
		"target": brain.get_target() != null,
		"asks": brain.get_fire_attempts(),
		"shots": brain.get_shots_taken(),
		"conf": brain.get_shot_confidence(),
	}


## Stall and hold streaks, sampled from each live runner's body and brain.
func _sample_runners() -> void:
	for participant: MatchParticipant in _controller.get_participants_ref():
		var tally: BotParticipantTally = _tallies.get(participant.index, null)
		var brain: RingRunner = participant.brain
		if tally == null or brain == null or participant.body == null:
			continue
		var w: Dictionary = _watch.get(participant.index, {})
		var here: Vector3 = participant.body.global_position
		var running: bool = participant.is_running and participant.body.is_physics_processing()
		var last: Vector3 = _last_point.get(participant.index, here)
		# Stopped running, or picked up and put back on the start line: either way
		# the lap ended where the body last stood, and that is what is scored.
		var was_running: bool = bool(_was_running.get(participant.index, false))
		var replaced: bool = running and last.distance_to(here) > TELEPORT_METRES
		if (was_running and not running) or replaced:
			_note_removal(participant.index, tally, last)
			_close_pass(participant.index, tally)
			_runs.close(participant.index, _ticks, _life_ending(participant))
		_was_running[participant.index] = running
		_last_point[participant.index] = here
		if not running:
			_watch[participant.index] = {}
			_close_pass(participant.index, tally)
			continue
		if not was_running or replaced:
			_runs.begin(participant.index, _ticks)
		_sample_run(participant, brain, here)
		_sample_section(participant.index, tally, here)
		_sample_hops(participant.index, tally, brain, here)
		var state: RingRunner.State = brain.get_state()
		var holding: bool = state == RingRunner.State.HOLD or state == RingRunner.State.EVALUATE
		var perception: RunnerPerception = brain.get_perception()
		var in_cover: bool = perception != null and perception.has_threat() and not perception.is_exposed()
		var hold_ticks: int = int(w.get("hold", 0)) + 1 if holding else 0
		tally.max_hold_seconds = maxf(tally.max_hold_seconds, float(hold_ticks) / 60.0)
		var position: Vector3 = participant.body.global_position
		var stall_run: int = int(w.get("stall_run", 0))
		if holding or in_cover or not w.has("origin"):
			w = {"hold": hold_ticks, "origin": position, "since": _ticks, "stall_run": 0 if holding or in_cover else stall_run}
			_watch[participant.index] = w
			continue
		if _ticks - int(w["since"]) >= STALL_WINDOW_TICKS:
			var origin: Vector3 = w["origin"]
			var moved: float = Vector2(position.x - origin.x, position.z - origin.z).length()
			if moved < STALL_DISTANCE_METRES:
				tally.stalls += 1
				stall_run += STALL_WINDOW_TICKS
				tally.max_stall_seconds = maxf(tally.max_stall_seconds, float(stall_run) / 60.0)
			else:
				stall_run = 0
			w["origin"] = position
			w["since"] = _ticks
			w["stall_run"] = stall_run
		w["hold"] = hold_ticks
		_watch[participant.index] = w


# --- Sections -----------------------------------------------------------------

## The arena's axis. Bearings and radii are measured about it.
func _arena_centre() -> Vector3:
	var arena: Node3D = _controller.arena as Node3D if _controller != null else null
	return arena.global_position if arena != null else Vector3.ZERO


## The section [param point] stands in, or {} outside every one of them.
func _section_of(point: Vector3) -> Dictionary:
	if not _sections_live:
		return {}
	var centre: Vector3 = _arena_centre()
	var bearing: float = wrapf(rad_to_deg(atan2(point.z - centre.z, point.x - centre.x)), 0.0, 360.0)
	for section: Dictionary in SECTIONS:
		if bearing >= float(section["from"]) and bearing <= float(section["to"]):
			return section
	return {}


## Which of [param section]'s radial bands [param point] is on.
func _band_of(section: Dictionary, point: Vector3) -> String:
	var centre: Vector3 = _arena_centre()
	var radius: float = Vector2(point.x - centre.x, point.z - centre.z).length()
	for band: Array in section["bands"] as Array:
		if radius <= float(band[1]):
			return String(band[0])
	return ""


## True when a body standing at [param point] is in a trap: inside its footprint
## and, for a feet_only trap, at or below the surface it converts at.
func _in_lava(point: Vector3) -> bool:
	for trap: Dictionary in _traps:
		var centre: Vector3 = trap["centre"]
		if Vector2(point.x - centre.x, point.z - centre.z).length_squared() > float(trap["reach_squared"]):
			continue
		var local: Vector3 = (trap["inverse"] as Transform3D) * point
		var half: Vector3 = trap["half"]
		if absf(local.x) > half.x or absf(local.z) > half.z:
			continue
		if local.y <= (0.05 if bool(trap["feet"]) else half.y) and local.y >= -half.y:
			return true
	return false


## How a life ended: at the portal, or not.
func _life_ending(participant: MatchParticipant) -> String:
	var tracker: MatchLapTracker = participant.tracker
	return "portal" if tracker != null and tracker.has_finished() else "removed"


## Hand [BotRunWatch] one tick of one live body, with what the brain was doing.
##
## The brain's own fields are read here and nowhere else. A watch that inferred
## "it was waiting on a link" from a position would be guessing; the point of the
## stall table is to name the cause, so it asks.
func _sample_run(participant: MatchParticipant, brain: RingRunner, here: Vector3) -> void:
	var body: PlayerController = participant.body
	var perception: RunnerPerception = brain.get_perception()
	var state: RingRunner.State = brain.get_state()
	var threat: bool = perception != null and perception.has_threat()
	var hidden: bool = threat and not perception.is_exposed()
	var holding: bool = hidden or state == RingRunner.State.HOLD or state == RingRunner.State.EVALUATE
	# The three states that steer by facing the tower rather than by where they
	# are going. See RingRunner._watch_and_hold.
	var watching: bool = threat and (holding or state == RingRunner.State.RECOVER)
	var lane: float = 1.0
	var route: RingRoute = brain.get_route()
	if route != null:
		lane = maxf(route.lane_radius(brain.get_level()), 1.0)
	_runs.sample(
		participant.index,
		_ticks,
		here,
		body.velocity,
		-body.global_transform.basis.z,
		brain.get_travelled_arc() * lane,
		holding,
		watching,
		brain.get_state_name(),
		{
			"threat": int(threat),
			"exposed": int(perception != null and perception.is_exposed()),
			"link": int(float(brain.get("_link_aim_age")) <= RingRunner.LINK_AIM_MEMORY_SECONDS),
			"lake": int(brain.call(&"_in_lake")),
			"target": int(brain.get("_has_target")),
			"cover": int(brain.get("_target_is_cover")),
			"wp": int(brain.get("_wp")),
			"unstick": int(float(brain.get("_unstick_seconds")) > 0.0),
			"override": int(float(brain.get("_route_override")) > 0.0),
			"air": int(not body.is_on_floor()),
		},
	)


## Credit any lava flights taken since last tick to the section they left from.
func _sample_hops(index: int, tally: BotParticipantTally, brain: RingRunner, point: Vector3) -> void:
	if not _sections_live or not brain.has_method(&"get_lake_hops"):
		return
	var hops: int = brain.get_lake_hops()
	var taken: int = hops - int(_hops_seen.get(index, 0))
	_hops_seen[index] = hops
	if taken <= 0:
		return
	var section: Dictionary = _section_of(point)
	if section.is_empty():
		return
	var entry: Dictionary = tally.section(String(section["id"]))
	entry["flights"] = int(entry["flights"]) + taken


## Note a body that stopped running, or was picked up and put back on the start
## line, against the section it was standing in when it happened.
func _note_removal(index: int, tally: BotParticipantTally, point: Vector3) -> void:
	_removals.append({
		"bearing": snappedf(wrapf(rad_to_deg(atan2(point.z, point.x)), 0.0, 360.0), 10.0),
		"radius": snappedf(Vector2(point.x, point.z).length(), 2.0),
		"y": snappedf(point.y, 1.0),
	})
	var section: Dictionary = _section_of(point)
	if section.is_empty():
		return
	var entry: Dictionary = tally.section(String(section["id"]))
	entry["removed"] = int(entry["removed"]) + 1


## Add this tick to [param index]'s section pass, closing the previous one when
## the body has walked out of the section it was in.
func _sample_section(index: int, tally: BotParticipantTally, point: Vector3) -> void:
	if not _sections_live:
		return
	var section: Dictionary = _section_of(point)
	var id: String = String(section["id"]) if not section.is_empty() else ""
	var pass_state: Dictionary = _pass.get(index, {})
	if String(pass_state.get("id", "")) != id:
		_close_pass(index, tally)
		pass_state = {"id": id, "ticks": 0, "bands": {}}
	if id.is_empty():
		_pass[index] = pass_state
		return
	pass_state["ticks"] = int(pass_state["ticks"]) + 1
	var band: String = _band_of(section, point)
	var bands: Dictionary = pass_state["bands"]
	bands[band] = int(bands.get(band, 0)) + 1
	_pass[index] = pass_state
	var entry: Dictionary = tally.section(id)
	entry["ticks"] = int(entry["ticks"]) + 1
	var seen: Dictionary = entry["bands"]
	seen[band] = int(seen.get(band, 0)) + 1
	if _in_lava(point):
		entry["lava_ticks"] = int(entry["lava_ticks"]) + 1


## Score the finished pass: the band the body spent most of it on is the route
## it took. A pass shorter than [constant ROUTE_MIN_TICKS] is somebody clipping
## a corner of the section, not a route through it.
func _close_pass(index: int, tally: BotParticipantTally) -> void:
	var pass_state: Dictionary = _pass.get(index, {})
	var id: String = String(pass_state.get("id", ""))
	if id.is_empty() or int(pass_state.get("ticks", 0)) < ROUTE_MIN_TICKS:
		_pass.erase(index)
		return
	var best: String = ""
	var best_ticks: int = -1
	for band: String in pass_state["bands"] as Dictionary:
		var ticks: int = int((pass_state["bands"] as Dictionary)[band])
		if ticks > best_ticks:
			best_ticks = ticks
			best = band
	if not best.is_empty():
		var routes: Dictionary = tally.section(id)["routes"]
		routes[best] = int(routes.get(best, 0)) + 1
	_pass.erase(index)


## Ticks the match has been running. The harness's authority on elapsed
## simulated time.
func get_ticks() -> int:
	return _ticks


func is_match_over() -> bool:
	return _match_over


# --- The match ----------------------------------------------------------------

func _on_match_started(participant_count: int) -> void:
	_participants_total = participant_count
	for participant: MatchParticipant in _controller.get_participants_ref():
		if _tallies.has(participant.index):
			continue
		var tally: BotParticipantTally = BotParticipantTally.new()
		tally.index = participant.index
		tally.display_name = participant.display_name
		tally.kind = "HUMAN" if participant.is_human() else "AI"
		_tallies[participant.index] = tally
		_order.append(participant.index)


func _on_race_started() -> void:
	_race_ran = true
	_close_seat()
	# Nobody holds the rifle during the race, and the match stows it rather than
	# leaving it in anyone's hands. A shot in this window would be a bug worth
	# seeing as an uncredited shot rather than one quietly filed under the last
	# person to hold the seat.
	_shooter_index = -1


func _on_round_started() -> void:
	_rounds_started += 1
	if _first_shot_pending:
		_rounds_without_a_shot += 1
	_round_tick = _ticks
	_first_shot_pending = true


## The tower changed hands. Close the outgoing holder's time and open the new
## one's, then take the counts the match keeps rather than keeping a second
## copy of them here: the turn count is the match's own, and a harness that
## recomputed it would eventually disagree with the reload it explains.
func _on_seat_changed(participant: MatchParticipant, turns_in_tower: int) -> void:
	var previous_index: int = _seat_index
	_close_seat()
	_seat_changes += 1

	# Which seat changes were EARNED by a lap, and which were not. Three ways
	# the tower changes hands and only one of them is a lap:
	#
	# - the opening grant of a match with no race: nobody has run anything yet;
	# - a shooter who won a round and stays on for another (rounds_to_win_match
	#   above one), which the match expresses as a fresh seat grant to the same
	#   participant;
	# - anybody else taking the seat, which under every shipped rule means they
	#   reached the end, in the race or in a round.
	var opening_grant: bool = not _race_ran and _rounds_started == 0
	var retained: bool = previous_index == participant.index
	var earned: bool = not opening_grant and not retained

	_seat_index = participant.index
	_shooter_index = participant.index
	_seat_since_tick = _ticks

	var tally: BotParticipantTally = _tallies.get(participant.index, null)
	if tally == null:
		return
	tally.turns_in_tower = turns_in_tower
	tally.seat_takes += 1
	if earned:
		tally.laps_finished += 1


func _on_round_resolved(outcome: MatchController.Outcome) -> void:
	_rounds_resolved += 1
	if outcome == MatchController.Outcome.WIN:
		_round_wins += 1
	elif outcome == MatchController.Outcome.LOSS:
		_round_losses += 1


func _on_runner_removed(_remaining: int) -> void:
	_conversions += 1
	_removed_tick = _ticks
	# The rifle's hit handler has already credited the shot. What is recorded
	# here is the conversion, which under prisoner_lives > 1 is not the same
	# event and must not be counted from the shot.


func _on_runner_ghosted(_participant: MatchParticipant) -> void:
	_ghosts_made += 1


## A ghost took a living prisoner's spot. Counted, and deliberately NOT counted
## as a conversion: a catch conserves the number of living prisoners and only the
## rifle lowers it, so folding the two together would make a ghost match look
## like a shooter who never missed.
func _on_ghost_caught(_ghost: MatchParticipant, _caught: MatchParticipant) -> void:
	_ghost_catches += 1


func _on_match_won(participant: MatchParticipant) -> void:
	_close_seat()
	_match_over = true
	_winner_index = participant.index
	var seat: MatchParticipant = _controller.get_seat_participant()
	_winner_was_seat = seat != null and seat.index == participant.index

	var tally: BotParticipantTally = _tallies.get(participant.index, null)
	if tally != null:
		tally.rounds_won = participant.rounds_won
	for other: MatchParticipant in _controller.get_participants_ref():
		var entry: BotParticipantTally = _tallies.get(other.index, null)
		if entry != null and other.tracker != null:
			entry.final_progress = other.tracker.get_progress()


func _close_seat() -> void:
	if _seat_index < 0:
		return
	var tally: BotParticipantTally = _tallies.get(_seat_index, null)
	if tally != null:
		tally.ticks_in_tower += _ticks - _seat_since_tick
	_seat_index = -1


# --- The rifle ----------------------------------------------------------------

func _on_fired(_origin: Vector3, _end_point: Vector3) -> void:
	_shots_fired += 1
	var tally: BotParticipantTally = _tallies.get(_shooter_index, null)
	if tally != null:
		tally.shots_fired += 1
		if _first_shot_pending and _round_tick >= 0:
			var seconds: float = float(_ticks - _round_tick) / 60.0
			tally.first_shot_seconds.append(seconds)
			_first_shots.append(seconds)
	_first_shot_pending = false
	_charge_shot_to_its_target()


## Credit the shot to whoever the tower was aiming at, in the section they stood
## in, and say whether the guard's own line reached their chest -- which is the
## test [RunnerCoverFinder] calls cover, asked from the far end.
func _charge_shot_to_its_target() -> void:
	if not _sections_live or _controller == null:
		return
	var seat: MatchParticipant = _controller.get_seat_participant()
	var guard: TowerShooter = seat.tower_brain if seat != null else null
	var quarry: PlayerController = guard.get_target() if guard != null else null
	if quarry == null or seat.body == null:
		return
	var struck: MatchParticipant = _controller.resolve_participant(quarry)
	var tally: BotParticipantTally = _tallies.get(struck.index, null) if struck != null else null
	if tally == null:
		return
	var section: Dictionary = _section_of(quarry.global_position)
	if section.is_empty():
		return
	var entry: Dictionary = tally.section(String(section["id"]))
	entry["shot_at"] = int(entry["shot_at"]) + 1
	if _eye_reaches(seat.body, quarry):
		entry["shot_at_uncovered"] = int(entry["shot_at_uncovered"]) + 1


## A shot struck SOMETHING. Whether that something was a player is the match's
## question to answer, and [method MatchController.resolve_participant] is the
## public way to ask it -- the alternative, comparing the collider against a
## roster this file kept, would silently stop working the day a body grows a
## separate hitbox node.
func _on_target_hit(collider: Node3D, _hit_position: Vector3, _hit_normal: Vector3) -> void:
	var struck: MatchParticipant = _controller.resolve_participant(collider)
	if struck == null:
		_shots_hit_world += 1
		return

	_shots_hit_participant += 1
	var shooter: BotParticipantTally = _tallies.get(_shooter_index, null)
	if shooter != null:
		shooter.shots_hit += 1
	var victim: BotParticipantTally = _tallies.get(struck.index, null)
	if victim != null:
		victim.times_converted += 1
		var section: Dictionary = _section_of(collider.global_position)
		if not section.is_empty():
			var entry: Dictionary = victim.section(String(section["id"]))
			entry["converted"] = int(entry["converted"]) + 1


func _on_missed(_end_point: Vector3) -> void:
	_shots_hit_nothing += 1


# --- The report ---------------------------------------------------------------

## Fold the final state of the roster in and close the open seat. Called once,
## by [BotMatchRunner], on the tick the match stops -- including a match stopped
## by the tick ceiling, which is why this is not done from
## [method _on_match_won].
func finalise() -> void:
	_close_seat()
	if _controller == null:
		return
	for participant: MatchParticipant in _controller.get_participants_ref():
		var tally: BotParticipantTally = _tallies.get(participant.index, null)
		if tally == null:
			continue
		tally.turns_in_tower = participant.turns_in_tower
		tally.rounds_won = participant.rounds_won
		tally.running_at_end = participant.is_running and not _match_over
		if participant.tracker != null:
			tally.final_progress = participant.tracker.get_progress()
		_close_pass(participant.index, tally)
	_runs.finish(_ticks)
	if _first_shot_pending and _rounds_started > 0:
		_rounds_without_a_shot += 1


func get_hit_rate() -> float:
	if _shots_fired <= 0:
		return 0.0
	return float(_shots_hit_participant) / float(_shots_fired)


## Everything measured, as plain data. [param sim_hz] is the simulated physics
## rate the ticks were counted at.
func to_dictionary(sim_hz: int) -> Dictionary:
	var participants: Array = []
	for index: int in _order:
		var tally: BotParticipantTally = _tallies.get(index, null)
		if tally != null:
			participants.append(tally.to_dictionary(sim_hz))

	return {
		"participants_total": _participants_total,
		"rounds": {
			"race_ran": _race_ran,
			"started": _rounds_started,
			"resolved": _rounds_resolved,
			"shooter_wins": _round_wins,
			"shooter_losses": _round_losses,
		},
		"seat": {
			"changes": _seat_changes,
			"changes_in_rounds": _laps_total(),
		},
		"shots": {
			"fired": _shots_fired,
			"hit_participant": _shots_hit_participant,
			"hit_world": _shots_hit_world,
			"hit_nothing": _shots_hit_nothing,
			"hit_rate": get_hit_rate(),
		},
		"conversions": _conversions,
		"hazard_deaths": _hazard_deaths,
		"tick_ms": _tick_dictionary(),
		"first_shot_seconds": _first_shots,
		"rounds_without_a_shot": _rounds_without_a_shot,
		"ghosts": {
			"made": _ghosts_made,
			"catches": _ghost_catches,
		},
		"stall": _stall_dictionary(sim_hz),
		"clean_runs": _runs.to_dictionary(),
		"removals": _removals,
		"participants": participants,
	}


## Why the round was still going: the causes, in ticks, and the final state.
func _stall_dictionary(sim_hz: int) -> Dictionary:
	var rate: float = float(maxi(sim_hz, 1))
	var round_ticks: float = float(maxi(_guard_round_ticks, 1))
	var out: Dictionary = {
		"round_seconds": float(_guard_round_ticks) / rate,
		"guard_starved_fraction": float(_guard_starved_ticks) / round_ticks,
		"guard_reloading_fraction": float(_guard_reload_ticks) / round_ticks,
		"finisher_armed_count": _finisher_armed_count,
		"finisher_armed_seconds_max": float(_finisher_ticks_max) / rate,
		"idle_at_portal_seconds": float(_idle_at_portal_ticks) / rate,
		"guard_blind_fraction": float(_guard_blind_ticks) / round_ticks,
		"guard_blind_in_arc_fraction": float(_guard_blind_in_arc_ticks) / round_ticks,
		"guard_blind_clear_fraction": float(_guard_blind_clear_ticks) / round_ticks,
	}
	if _controller != null:
		out["final"] = _round_state()
	return out


func _tick_dictionary() -> Dictionary:
	var ticks: float = float(maxi(_ticks - 1, 1))
	var out: Dictionary = {  # hot-ok: named _tick*, but built once when the match ends
		"max": float(_tick_max_usec) / 1000.0,
		"avg": float(_tick_sum_usec) / ticks / 1000.0,
		"over_16ms": _tick_over_16ms,
	}
	for kind: String in _cost_max:
		out["%s_max" % kind] = float(_cost_max[kind]) / 1000.0  # hot-ok: result keys, built once
		out["%s_avg" % kind] = float(_cost_sum[kind]) / ticks / 1000.0  # hot-ok: result keys, built once
	return out


## Seat changes that somebody actually ran a lap for. The number a balance
## question about the tower is usually asking after.
func _laps_total() -> int:
	var total: int = 0
	for tally: BotParticipantTally in _tallies.values():
		total += tally.laps_finished
	return total


func get_winner_index() -> int:
	return _winner_index


func winner_held_the_tower() -> bool:
	return _winner_was_seat
