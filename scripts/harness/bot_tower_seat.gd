class_name BotTowerSeat
extends Node

## Puts a [TowerShooter] brain behind whoever currently holds the tower.
##
## [b]The gap this fills, stated plainly[/b]
##
## [MatchController] moves the rifle onto the seat holder's head and silences
## their [RingRunner], because a body in the tower does not run laps. It does
## not give them anything to aim with: the shipped match has a human in the
## tower, and [code]scenes/bot/tower_shooter.tscn[/code] is a whole body of its
## own rather than a brain the match can hand to an existing participant. So a
## match played entirely by AI has, today, an INERT tower -- a shooter that
## never fires, a round that can never be won from the tower, and therefore a
## match that can never end. That is not a bug in the match; it is a seam the
## match has not been asked for yet.
##
## This node closes the seam from OUTSIDE the match, on the harness's side of
## the line. It attaches one [TowerShooter] per AI body, lazily, and runs
## exactly the one belonging to the current seat. Should [MatchController] grow
## a tower brain of its own, delete this file and the harness keeps working: it
## touches nothing the match owns.
##
## [b]What it depends on[/b]
##
## Four signals -- [signal MatchController.race_started],
## [signal MatchController.round_started],
## [signal MatchController.round_resolved] and
## [signal MatchController.match_won] -- and
## [method MatchController.get_seat_participant]. Nothing else. In particular it
## does not care how many rounds a match has, how the seat is decided, or what
## the phases are called; it re-reads the seat every time a round is armed.

## Attached brains, keyed by the instance id of the body they steer. Keyed by id
## rather than by participant so that a roster rebuilt between matches cannot
## resurrect a brain pointing at a freed body.
var _shooters: Dictionary[int, TowerShooter] = {}

var _controller: MatchController = null
var _profile: ShooterProfile = null
var _seed: int = 0


## Start following [param controller]'s seat.
##
## [param profile] is copied per body, so the aim RNG can be seeded per
## participant without retuning the shared resource; [param seed_value] of 0
## means "seed from entropy", exactly as [member ShooterProfile.aim_random_seed]
## does, and gives up reproducibility in exchange for independent samples.
func install(controller: MatchController, profile: ShooterProfile, seed_value: int) -> void:
	_controller = controller
	_profile = profile
	_seed = seed_value

	controller.race_started.connect(_on_race_started)
	controller.round_started.connect(_on_round_started)
	controller.round_resolved.connect(_on_round_resolved)
	controller.match_won.connect(_on_match_won)


## The brain currently playing the tower, or null during the race and after the
## match is over.
func get_active_shooter() -> TowerShooter:
	var seat: MatchParticipant = _controller.get_seat_participant() if _controller != null else null
	if seat == null or seat.body == null:
		return null
	var found: TowerShooter = _shooters.get(seat.body.get_instance_id(), null)
	if found == null or not found.is_physics_processing():
		return null
	return found


# --- Following the seat -------------------------------------------------------

## The opening race has no shooter. That has to be true of the brains as well as
## of the rifle, or the racer who happens to be nearest the tower shoots the
## field while everybody runs.
func _on_race_started() -> void:
	_stand_down_all()


## A round is armed and the seat holder is already standing on the tower, so
## their body's position is the stand to configure from.
func _on_round_started() -> void:
	_stand_down_all()
	if _controller == null:
		return
	var seat: MatchParticipant = _controller.get_seat_participant()
	if seat == null or seat.body == null:
		return

	var shooter: TowerShooter = _ensure_shooter(seat)
	if shooter == null:
		return
	# Re-read both every round: the rules may be swept between matches and the
	# rifle is one instance that the match reparents onto whoever holds the seat.
	shooter.rules = _controller.get_rules()
	shooter.rifle = _controller.rifle
	shooter.configure(seat.body.global_position, seat.body.rotation.y)


## A resolved round is over for everyone, including the tower. Standing the
## brain down here rather than waiting for the next round means no shot can land
## in the gap between a seat being lost and the next round being armed.
func _on_round_resolved(_outcome: MatchController.Outcome) -> void:
	_stand_down_all()


func _on_match_won(_participant: MatchParticipant) -> void:
	_stand_down_all()


func _stand_down_all() -> void:
	for shooter: TowerShooter in _shooters.values():
		if is_instance_valid(shooter):
			shooter.set_physics_process(false)


# --- Attachment ---------------------------------------------------------------

## The brain for [param participant]'s body, built on first use.
##
## Built rather than instanced from [code]scenes/bot/tower_shooter.tscn[/code]
## because that scene is a BODY. The participant already has a body, a head, a
## camera and an optic -- the same ones it runs the ring with, which is the
## whole point of a seat that changes hands -- so what is missing is only the
## brain, and the brain is a bare [Node] with five references.
func _ensure_shooter(participant: MatchParticipant) -> TowerShooter:
	var body: PlayerController = participant.body
	var id: int = body.get_instance_id()
	var existing: TowerShooter = _shooters.get(id, null)
	if existing != null and is_instance_valid(existing):
		return existing

	var input: BotIntentSource = body.intent_source as BotIntentSource
	if input == null:
		push_error(
			"BotTowerSeat cannot drive %s: its intent_source is not a BotIntentSource."
			% participant.display_name
		)
		return null

	var shooter: TowerShooter = TowerShooter.new()
	shooter.name = "HarnessTowerShooter"
	shooter.controller = body
	shooter.input = input
	shooter.rifle = _controller.rifle
	shooter.optic = body.get_node_or_null(^"Optic") as WeaponOptic
	shooter.camera = body.get_node_or_null(^"Head/Camera") as Camera3D
	shooter.profile = _make_profile(participant.index)
	shooter.rules = _controller.get_rules()
	# Everything the match puts on the ring is in this group and the match takes
	# the seat holder out of it, so the shooter's candidate list is exactly the
	# live runners without the harness having to maintain one.
	shooter.target_group = MatchController.RUNNER_GROUP
	# Every export is set BEFORE the node enters the tree: TowerShooter._ready
	# refuses to play and disables itself if any of them is missing.
	body.add_child(shooter)

	_install_optic_driver(body, shooter.optic)
	_shooters[id] = shooter
	return shooter


## A private, per-participant copy of the shooter profile.
##
## The seed is derived from the harness seed and the participant index so that
## the four bots in a match miss in different directions while the whole match
## still replays identically from the same [code]--seed[/code]. A harness seed
## of 0 is passed straight through, which [method ShooterProfile.make_rng] reads
## as "seed from entropy".
func _make_profile(index: int) -> ShooterProfile:
	var copy: ShooterProfile = _profile.duplicate() as ShooterProfile
	if _seed != 0:
		copy.aim_random_seed = _seed + index + 1
	return copy


## Move the optic onto the physics tick for the rest of the match. See
## [BotOpticDriver] for why a headless run cannot leave it on the render tick.
func _install_optic_driver(body: PlayerController, optic: WeaponOptic) -> void:
	if optic == null or body.get_node_or_null(^"HarnessOpticDriver") != null:
		return
	optic.set_process(false)
	var driver: BotOpticDriver = BotOpticDriver.new()
	driver.name = "HarnessOpticDriver"
	driver.optic = optic
	# After the shooter, which is added first and left at the default priority,
	# so the optic advances carrying this tick's zoom decision.
	driver.process_priority = 100
	body.add_child(driver)
