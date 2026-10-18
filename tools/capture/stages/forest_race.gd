extends "res://tools/capture/stages/stage.gd"

## forest_race: short 9 line L4, Ryan: "so, i implemented a race, every player does the course with no sniper, and the
## first one to complete it gets to be the sniper. this, was the worst part of my game. it wasnt fun, everyone was the
## same speed, and it took to long" {pov of race in forest}. The game's own opening race (start_race), bot brains run it.
## [code]--stage=forest_race --shot=s3_open_lane --map=forest --pov=runner --bots=3 --shimmer=0 --look=social --seed=20261017 --frame=810x1440 --seconds=22[/code]
## run_clip opens a round in stage mode; the first tick re-arms the race. Four bodies, all racers, seat none all race.
## Mac smoke (seed 20261017): race_start 0.02, lap ~28.6 s (race_won Runner_2 at 28.63, past the cut); Runner_3 runs 2nd
## of 4 with Runner_2 ~5 deg ahead in frame. Window 1.0-20.5 s: near >= 0.56 m, cover <= 0.56, no run >= 0.1 s.
## Runner_0 / Runner_1 trade shoves the whole lap (cover 1.0 for 1.45 s): not ridden.
## Dials (--set=): ride (Runner_3: the racer ridden, 2nd of 4 off this seed), log_every (1.0 s between [race] lines).

const RIDE: String = "Runner_3"

var _started: bool = false
var _pov: PlayerController = null
var _next_log: float = 0.0
var _won: bool = false


func bots() -> int:
	return 3


func tune_rules(rules: MatchRules) -> void:
	rules.open_with_race = true
	rules.open_with_tower_brawl = false
	rules.runner_ability = MatchRules.RunnerAbility.NONE


func tick(_delta: float) -> void:
	var match_controller: MatchController = controller()
	if not _started:
		_started = true
		match_controller.race_started.connect(func() -> void: _event("race_start  %d" % match_controller.get_participants().size()))
		match_controller.seat_changed.connect(_on_seat)
		match_controller.participant_converted.connect(func(p: MatchParticipant) -> void: _event("out  %s" % p.body.name))
		match_controller.start_race()
		for p: MatchParticipant in match_controller.get_participants():
			if p.body != null and String(p.body.name) == String(option("ride", RIDE)):
				_pov = p.body
		if _pov != null:
			stage_body(_pov)
		say("forest_race: %d racers, POV %s" % [match_controller.get_participants().size(), _pov.name if _pov != null else "none"])
	if elapsed() < _next_log:
		return
	_next_log = elapsed() + float(option("log_every", 1.0))
	var seat_holder: MatchParticipant = match_controller.get_seat_participant()
	var line: String = "phase %s seat %s" % [match_controller.get_phase_name(), seat_holder.body.name if seat_holder != null else "none"]
	for p: MatchParticipant in match_controller.get_participants():
		if p.body == null:
			continue
		var progress: float = p.tracker.get_progress() if p.tracker != null else -1.0
		line += " | %s%s %.1f deg r %.1f p %.3f%s" % ["*" if p.body == _pov else "", p.body.name, LIB.bearing_of(p.body.global_position),
			LIB.radius_of(p.body.global_position), progress, " SHOOTER" if p.is_shooter else ""]
	print("[race] %6.2f  %s" % [elapsed(), line])


## First past the post takes the tower; later seat changes are rounds, not the race.
func _on_seat(p: MatchParticipant, _turns: int) -> void:
	if not _won:
		_won = true
		_event("race_won  %s" % p.body.name)


func _event(message: String) -> void:
	print("[event] %6.2f  %s" % [elapsed(), message])
