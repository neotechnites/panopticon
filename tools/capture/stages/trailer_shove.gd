extends "res://tools/capture/stages/cover_both.gd"

## trailer_shove: cover_both, but the shot is the hand's (guard_hand.gd): the
## tower's own brain never fired on this frame in the smoke, so the guard is
## stood down and the hand drops the shoved man once he lands. Reveal trailer shot 10.
## Staged at trailer_duel's CoverS4 pocket (the 198.5 rock is behind S3's lip from
## the tower now): --set=victim=212.6,52;shover=217.5,53.5;runner=200,53;runner_to=199,53;impulse=10.5
## Dials: cover_both's, plus squeeze (0.3 s after he lands), cam/look/fov (trailer_duel's lens).

const GUARD_HAND := preload("res://tools/capture/stages/guard_hand.gd")
const DUEL := preload("res://tools/capture/stages/trailer_duel.gd")

var _hand: Node = null
var _squeezed: bool = false


func tick(delta: float) -> void:
	super.tick(delta)
	if _victim == null:
		return
	if _hand == null:
		var shooter: TowerShooter = LIB.stand_down(seat())
		if shooter == null or shooter.controller == null:
			return
		_hand = GUARD_HAND.new()
		_hand.name = "ClipGuardHand"
		clip.root.add_child(_hand)
		_hand.install(shooter.controller, controller(), elapsed())
		_hand.beats.append({"body": _victim, "seconds": 100.0, "fire_at": -1.0, "watch": true})
		_hand.park = _victim.global_position + Vector3.UP
		_hand.start_at = elapsed() + 0.2
		return
	if _rearmed and not _squeezed:
		_squeezed = true
		_hand.beats[0]["fire_at"] = elapsed() - _hand.start_at + float(option("squeeze", 0.3))
		say("the hand squeezes on the shoved man")


func lens(_delta: float) -> bool:
	return DUEL.fixed_lens(camera(), String(option("cam", "205.6,55.2,1.3")), String(option("look", "212.2,51.6,0.9")), float(option("fov", 56.0)))


func tune_rules(rules: MatchRules) -> void:
	super.tune_rules(rules)
	rules.ghost_behaviour = MatchRules.GhostBehaviour.NONE


func before_start() -> void:
	super.before_start()
	LIB.disarm_pads(clip.root)
	LIB.disarm_traps(clip.root)
