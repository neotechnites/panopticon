class_name BotRunWatch
extends RefCounted

## Whether each bot's run was CLEAN, one life at a time.
##
## A match can resolve 10 times out of 10 and still be full of bots standing in a
## corner: the winner only has to be somebody. This watches one life -- from the
## tick a body is placed to the tick it reaches the portal or is taken out -- and
## records the four things that make a run not worth watching:
##
## 1. [b]A stall[/b]: under [constant STALL_SPEED] for [constant STALL_SECONDS],
##    while alive and NOT deliberately holding cover with the tower on it.
##    Standing still behind a rock while the guard looks at you is the game; doing
##    it facing a wall is not, and the only difference is whether there is a
##    threat and whether the body is hidden from it.
## 2. [b]Wall-facing[/b]: travelling more than a right angle away from where the
##    body is pointed, for [constant WALL_SECONDS]. Sampled only above
##    [constant WALL_MIN_SPEED], because the direction of a velocity of nearly
##    zero is noise and would report every stall twice, and not at all while the
##    brain is deliberately watching the tower -- a prisoner backing into cover
##    with its eyes on the guard is playing, not broken.
## 3. [b]Backtracking[/b]: giving up more than [constant BACKTRACK_METRES] of the
##    route already run.
## 4. [b]A slow lap[/b]: longer than [constant SLOW_LAP_MULTIPLE] times the
##    field's median life. Decided at the end of the run, when there is a field
##    to take a median of.
##
## Where a stall happened is recorded with it -- bearing, radius, and what the
## brain was doing -- because the rate alone says nothing about what to fix.

## Under this many metres per second counts as stopped.
const STALL_SPEED: float = 1.0
const STALL_SECONDS: float = 1.5
const WALL_SECONDS: float = 1.0
const WALL_MIN_SPEED: float = 0.5
const BACKTRACK_METRES: float = 8.0
const SLOW_LAP_MULTIPLE: float = 2.0
## Degrees and metres a stall report is rounded to, so two stalls in one doorway
## are one row and not two.
const PLACE_DEGREES: float = 10.0
const PLACE_METRES: float = 2.0

var _open: Dictionary = {}
var _lives: Array[Dictionary] = []
var _rate: float = 60.0


func _init(sim_hz: int = 60) -> void:
	_rate = float(maxi(sim_hz, 1))


## Start watching [param index]'s next life from [param tick].
func begin(index: int, tick: int) -> void:
	close(index, tick, "replaced")
	_open[index] = {
		"index": index,
		"from": tick,
		"to": tick,
		"stall_ticks": 0,
		"wall_ticks": 0,
		"stalled": false,
		"wall_faced": false,
		"backtracked": false,
		"slow": false,
		"reason": "running",
		"best": -INF,
		"stalls": [],
		"walls": [],
	}


## One tick of one live body.
##
## [param arc_metres] is how far round the route the body has come, so that
## backtracking is measured in the direction that matters rather than as
## displacement -- a runner crossing to cover moves a long way sideways and has
## given up nothing.
func sample(
	index: int,
	tick: int,
	position: Vector3,
	velocity: Vector3,
	forward: Vector3,
	arc_metres: float,
	holding_cover: bool,
	facing_threat: bool,
	state: String,
	doing: Dictionary,
) -> void:
	var life: Dictionary = _open.get(index, {})
	if life.is_empty():
		begin(index, tick)
		life = _open[index]
	life["to"] = tick

	var flat: Vector2 = Vector2(velocity.x, velocity.z)
	var speed: float = flat.length()

	if speed < STALL_SPEED and not holding_cover:
		life["stall_ticks"] = int(life["stall_ticks"]) + 1
		if float(life["stall_ticks"]) / _rate >= STALL_SECONDS and not bool(life["stalled"]):
			life["stalled"] = true
			(life["stalls"] as Array).append(_place(position, state, doing))
	else:
		life["stall_ticks"] = 0

	var heading: Vector2 = Vector2(forward.x, forward.z)
	if speed >= WALL_MIN_SPEED and heading.length() > 0.001 and not facing_threat \
		and absf(heading.angle_to(flat)) > PI * 0.5:
		life["wall_ticks"] = int(life["wall_ticks"]) + 1
		if float(life["wall_ticks"]) / _rate >= WALL_SECONDS and not bool(life["wall_faced"]):
			life["wall_faced"] = true
			(life["walls"] as Array).append(_place(position, state, doing))
	else:
		life["wall_ticks"] = 0

	if arc_metres > float(life["best"]):
		life["best"] = arc_metres
	elif float(life["best"]) - arc_metres > BACKTRACK_METRES:
		life["backtracked"] = true


## Finish [param index]'s life. [param reason] is "portal", "removed" or
## "replaced"; a life that never started is not recorded.
func close(index: int, tick: int, reason: String) -> void:
	var life: Dictionary = _open.get(index, {})
	_open.erase(index)
	if life.is_empty():
		return
	life["to"] = tick
	life["reason"] = reason
	_lives.append(life)


## Close every open life. Called once, when the match stops.
func finish(tick: int) -> void:
	for index: int in _open.keys():
		close(index, tick, "match ended")


## Rate, counts, and the stalls, as plain data.
func to_dictionary() -> Dictionary:
	_mark_the_slow_ones()
	var clean: int = 0
	var stalled: int = 0
	var wall: int = 0
	var back: int = 0
	var slow: int = 0
	var stalls: Array = []
	var walls: Array = []
	for life: Dictionary in _lives:
		if bool(life["stalled"]):
			stalled += 1
		if bool(life["wall_faced"]):
			wall += 1
		if bool(life["backtracked"]):
			back += 1
		if bool(life["slow"]):
			slow += 1
		if _is_clean(life):
			clean += 1
		for place: Dictionary in life["stalls"] as Array:
			stalls.append(place)
		for place: Dictionary in life["walls"] as Array:
			walls.append(place)
	return {
		"lives": _lives.size(),
		"clean": clean,
		"clean_rate": 0.0 if _lives.is_empty() else float(clean) / float(_lives.size()),
		"stalled": stalled,
		"wall_faced": wall,
		"backtracked": back,
		"slow": slow,
		"median_life_seconds": _median_seconds(),
		"stalls": stalls,
		"walls": walls,
	}


static func _is_clean(life: Dictionary) -> bool:
	return not bool(life["stalled"]) and not bool(life["wall_faced"]) \
		and not bool(life["backtracked"]) and not bool(life["slow"])


## The median life, in seconds, over the lives that reached the portal. A life
## cut short by the rifle is not a lap time and would drag the median down.
func _median_seconds() -> float:
	var finished: Array[float] = []
	for life: Dictionary in _lives:
		if String(life["reason"]) == "portal":
			finished.append(float(int(life["to"]) - int(life["from"])) / _rate)
	if finished.is_empty():
		return 0.0
	finished.sort()
	return finished[finished.size() / 2]


func _mark_the_slow_ones() -> void:
	var median: float = _median_seconds()
	if median <= 0.0:
		return
	for life: Dictionary in _lives:
		var seconds: float = float(int(life["to"]) - int(life["from"])) / _rate
		life["slow"] = seconds > median * SLOW_LAP_MULTIPLE


## Where a stall happened and what the brain was doing, rounded so two stalls in
## one doorway read as one place.
static func _place(position: Vector3, state: String, doing: Dictionary) -> Dictionary:
	var bearing: float = wrapf(rad_to_deg(atan2(position.z, position.x)), 0.0, 360.0)
	var radius: float = Vector2(position.x, position.z).length()
	var out: Dictionary = {
		"bearing": snappedf(bearing, PLACE_DEGREES),
		"radius": snappedf(radius, PLACE_METRES),
		"y": snappedf(position.y, 0.5),
		"state": state,
	}
	out.merge(doing)
	return out
