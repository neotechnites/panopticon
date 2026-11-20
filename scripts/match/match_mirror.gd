class_name MatchMirror
extends RefCounted

## A client's match converging on the host's records (DESIGN 5): each record is diffed against the one
## taken before it and played through the controller's net_* transitions, in the order the host ran them.

var controller: MatchController
var _prev: MatchState = MatchState.new()
## The state an arming leaves, read off the controller: what the new phase's lives are diffed from.
var _armed: MatchState = MatchState.new()
## Initial conditions from the event ring, by slot: [tick, a, b]. A DEATH's hit point and direction,
## a BRAWL_THROW's throw; taken by the transition they belong to.
var _deaths: Dictionary[int, Array] = {}
var _throws: Dictionary[int, Array] = {}
var _converging: bool = false
var _used: PackedByteArray = PackedByteArray()


func _init(match_controller: MatchController) -> void:
	controller = match_controller


## True only while the first record this scene takes is replayed: history, not news.
func is_converging() -> bool:
	return _converging


func note_death(slot: int, tick: int, at: Vector3, direction: Vector3) -> void:
	_deaths[slot] = [tick, at, direction]


func note_throw(slot: int, tick: int, throw: Vector3) -> void:
	_throws[slot] = [tick, throw]


## Converge on [param cur]; [param first] when it is the first record this scene takes, which lands silently.
## Returns true when it started the match here.
func converge(cur: MatchState, first: bool) -> bool:
	if not cur.started:
		return false
	var prev: MatchState = _prev if _prev.started else null
	var starts: bool = prev == null or cur.match_serial != prev.match_serial
	_converging = first
	controller.net_set_presenting(not first)
	if starts:
		controller.net_start_match()
	if cur.participants.size() != controller.get_participants().size():
		push_error("MatchMirror: the host's match has %d participants, this one %d." % [
			cur.participants.size(), controller.get_participants().size()])
		_end_converge()
		return starts
	var rearmed: bool = starts or _rearmed(prev, cur)
	if not starts:
		if not rearmed:
			_take_lives(prev, cur)
		# A round resolved before anything re-armed it: the host said so first.
		if cur.resolve_count != prev.resolve_count and not controller.is_resolved():
			controller.net_resolve(cur.last_outcome as MatchController.Outcome)
	if rearmed:
		for i: int in cur.participants.size():
			controller.get_participants_ref()[i].rounds_won = cur.participants[i].rounds_won
		_arm(cur)
		_read_armed(cur)
		_take_lives(_armed, cur)
	if cur.finisher >= 0 and MatchController.slot_of(controller.get_finisher()) != cur.finisher:
		controller.net_arm_finisher(cur.finisher)
	if cur.kill_beat_guard >= 0 and (prev == null or prev.kill_beat_serial != cur.kill_beat_serial):
		controller.net_kill_beat(cur.kill_beat_guard, cur.kill_beat_throw)
	if cur.outcome != int(MatchController.Outcome.IN_PROGRESS) and not controller.is_resolved():
		controller.net_resolve(cur.outcome as MatchController.Outcome)
	if cur.phase == int(MatchController.Phase.MATCH_OVER) and not controller.is_match_over() and cur.winner >= 0:
		controller.net_win(cur.winner)
	controller.net_take_state(cur)
	_prev.copy_from(cur)
	_end_converge()
	return starts


func _end_converge() -> void:
	controller.net_set_presenting(true)
	_converging = false


## Forget the records taken: the next one is converged on as a scene's first.
func reset() -> void:
	_prev.started = false
	_deaths.clear()
	_throws.clear()


## A new phase or round was armed between the two records.
func _rearmed(prev: MatchState, cur: MatchState) -> bool:
	if cur.phase == int(MatchController.Phase.MATCH_OVER) or cur.phase == int(MatchController.Phase.IDLE):
		return false
	return cur.phase != prev.phase or cur.round_number != prev.round_number


## The phase the record is in, armed here as the host armed it.
func _arm(cur: MatchState) -> void:
	match cur.phase:
		MatchController.Phase.RACE:
			controller.net_start_race()
		MatchController.Phase.BRAWL:
			controller.net_start_brawl()
		_:
			if cur.guard >= 0:
				controller.net_start_round(cur.guard, cur.round_number)


func _read_armed(cur: MatchState) -> void:
	_armed.tick = _prev.tick if _prev.started else -1
	_armed.started = true
	_armed.resize(cur.participants.size())
	var participants: Array[MatchParticipant] = controller.get_participants_ref()
	for i: int in cur.participants.size():
		var entry: MatchState.Entry = _armed.participants[i]
		entry.running = participants[i].is_running
		entry.ghost = participants[i].is_ghost
		entry.shooter = participants[i].is_shooter
		entry.held = false
		entry.life = cur.participants[i].life


## Each participant's lives from [param base] to [param cur]: catches, then deaths, then each ghost's
## falls and respawns, the life counter showing the ones that began and ended between the two.
func _take_lives(base: MatchState, cur: MatchState) -> void:
	var count: int = cur.participants.size()
	_used.resize(count)
	_used.fill(0)
	for ghost: int in count:
		if not (base.participants[ghost].ghost and cur.participants[ghost].running):
			continue
		for caught: int in count:
			if _used[caught] == 0 and base.participants[caught].running and cur.participants[caught].ghost:
				controller.net_ghost_caught(ghost, caught)
				_used[caught] = 1
				break
	for i: int in count:
		var was: MatchState.Entry = base.participants[i]
		var now: MatchState.Entry = cur.participants[i]
		if was.running and not now.running and not now.shooter and _used[i] == 0:
			_die(i, now, base.tick, cur.tick)
		if not now.ghost:
			continue
		var held: bool = was.held if was.ghost else true
		var respawned: bool = now.life != was.life
		var cause: MatchParticipant.DeathCause = MatchController.cause_of(now.death_cause)
		if not held and (now.held or respawned):
			controller.net_ghost_fall(i, cause)
			held = true
		if held and (respawned or not now.held):
			controller.net_ghost_respawn(i)
			held = false
		if now.held and not held:
			controller.net_ghost_fall(i, cause)


## Slot [param i] left the running set between ticks [param since] and [param until].
func _die(i: int, now: MatchState.Entry, since: int, until: int) -> void:
	match controller.get_phase():
		MatchController.Phase.RACE:
			controller.net_race_out(i)
		MatchController.Phase.BRAWL:
			var throw: Array = _cue(_throws, i, since, until)
			controller.net_brawl_out(i, throw[1] if not throw.is_empty() else Vector3.ZERO)
		_:
			controller.net_convert(i, MatchController.cause_of(now.death_cause))
			var death: Array = _cue(_deaths, i, since, until)
			if not death.is_empty():
				controller.net_shot_dead(i, death[1], death[2])


## The cue for slot [param i] stamped in (since, until], taken; empty when there is none.
func _cue(cues: Dictionary[int, Array], i: int, since: int, until: int) -> Array:
	var cue: Array = cues.get(i, [])
	if cue.is_empty() or int(cue[0]) > until or (since >= 0 and int(cue[0]) <= since):
		return []
	cues.erase(i)
	return cue
