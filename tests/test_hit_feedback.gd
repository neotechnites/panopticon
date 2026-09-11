extends TestCase

## BEING SHOT, from the inside.
##
## Canon, in the author's words: [i]"something instant and impactful. like youve
## just been hit in the side of the head with a baseball from a pro pitcher."[/i]
##
## Three claims are made below, and each one is the answer to a way this could
## plausibly have been built wrong:
##
## [codeblock]
## 1. It is INSTANT.      Peak on the first frame, spent inside a fifth of a
##                        second. Never a ramp, never an animation.
## 2. It is CAMERA ONLY.  The body does not move, does not gain velocity, does
##                        not turn, and no MoveIntent is written. Aim comes back
##                        bit-exact.
## 3. It is PERSONAL.     The prisoner who was hit feels it. Not the shooter who
##                        hit them, not the prisoner standing next to them.
## [/codeblock]
##
## [b]Why the effect nodes are stepped by hand[/b]
##
## [FxCameraKick] and [FxHitReaction] run on [method Node._process] because they
## are rendered quantities, and a test runner drives [signal SceneTree.physics_frame].
## Both classes expose a public [code]tick(delta)[/code] for exactly this, so
## every test here calls [code]set_process(false)[/code] and steps them itself
## at the shipped physics delta -- which also makes the whole file deterministic
## rather than dependent on how many idle frames the runner happened to fit in.
##
## [b]And why [code]headless_inert[/code] is turned off[/b]
##
## Every node in [code]scripts/fx[/code] switches itself off when there is no
## display server, so a bot sweep pays nothing for feedback nobody can see. A
## headless test of the logic has to say so explicitly, which is the one licence
## [code]scenes/fx/feedback_rig.tscn[/code]'s own header grants.

const FEEDBACK_PROFILE_PATH: String = "res://scenes/fx/default_feedback_profile.tres"
const BANK_PATH: String = "res://scenes/audio/placeholder_bank.tres"
const CAMERA_PATH: NodePath = ^"Head/Camera"
const HEAD_PATH: NodePath = ^"Head"

## Height the test floor's surface sits at. Well clear of anything else a test
## in this process may have left lying around at the origin.
const FLOOR_Y: float = 500.0

## Ticks the bodies are left standing before anything is measured, so the
## measurement is of a hit and not of a body still finding the floor.
const SETTLE_TICKS: int = 30

## Ticks the camera-only experiment is run for after the hit. Comfortably longer
## than the whole reaction, so what is measured includes the recovery.
const OBSERVE_TICKS: int = 40

## The author's budget: [i]"the whole thing inside roughly 150 ms so it reads as
## an impact rather than an effect."[/i] Asserted against the amplitude that is
## LEFT at that moment rather than against the configured duration -- an
## envelope with a fade exponent of 2.5 is visually finished long before it is
## arithmetically zero, and pinning the tuning to a hard cutoff would ban the
## soft tail that stops the whip reading as a cut.
const IMPACT_BUDGET_SECONDS: float = 0.15

## Fraction of peak the SHOVE is allowed to still have at the budget.
##
## Measured on the shove and not on the whip, deliberately. The shove is the
## envelope with nothing on top of it, so a number read off it is a statement
## about the reaction's length; the whip is that envelope times a cosine, so a
## sample of it can be anything between zero and the envelope depending on where
## in the swing the tick happened to land, and asserting a bound on THAT would
## be asserting a bound on the sampling.
const RESIDUAL_AT_BUDGET: float = 0.25

## How close two positions must be to be the same position, in metres. The
## bodies are stepped by the real character controller, so this is float noise
## in a solver and not a licence for drift.
const POSITION_TOLERANCE: float = 1e-3

## How close two angles must be to be the same angle, in radians.
const ANGLE_TOLERANCE: float = 1e-5

var _profile: FeedbackProfile
var _floor: StaticBody3D
var _rifle: Rifle

## The prisoner who gets shot, and the rig that speaks for them.
var _victim: PlayerController
var _victim_kick: FxCameraKick
var _victim_reaction: FxHitReaction

## The prisoner standing next to them, who does not. Also the control body for
## the camera-only experiment: two identical bodies under identical intent, one
## of which is hit.
var _bystander: PlayerController
var _bystander_reaction: FxHitReaction

## The shooter's own rig. Its body is the one holding the rifle, which is the
## test that the reaction is not a hitmarker in disguise.
var _shooter: PlayerController
var _shooter_reaction: FxHitReaction

var _struck_directions: Array[Vector3] = []


func before_each() -> void:
	_profile = (load(FEEDBACK_PROFILE_PATH) as FeedbackProfile).duplicate() as FeedbackProfile
	# THE HIT STOP IS OFF FOR EVERY TEST BUT ITS OWN, AND THAT IS NOT FUSSINESS.
	# It writes Engine.time_scale, which the test runner itself has raised in
	# order to drive the simulation faster than real time -- so a hit stop left
	# running by a test that failed halfway would slow every test after it in the
	# same process. Its own test below turns it on, drives it through a public
	# seam that ends it deterministically, and restores the scale in after_each.
	_profile.hit_stop_enabled = false

	_floor = TestFixtures.make_floor(FLOOR_Y)
	add_child(_floor)

	_rifle = (load(TestFixtures.RIFLE_SCENE_PATH) as PackedScene).instantiate() as Rifle
	# Before it enters the tree: the rifle scene ships a WeaponInput that grabs
	# the mouse from its own _ready, and a headless run has no window to grab it
	# into -- and a test that left Input.mouse_mode captured would leak that into
	# every test after it in the same process.
	TestFixtures.silence_human_input(_rifle)
	add_child(_rifle)

	# The body's capsule is centred at y=0.9 on an origin at its feet, so a body
	# put down a few centimetres above the surface neither penetrates it nor has
	# any distance to fall.
	_victim = _make_body(Vector3(0.0, FLOOR_Y + 0.05, 0.0))
	_bystander = _make_body(Vector3(6.0, FLOOR_Y + 0.05, 0.0))
	_shooter = _make_body(Vector3(-6.0, FLOOR_Y + 0.05, 0.0))

	# One rifle in a match, held by one body, and every listener in the game
	# hears it fire. Saying who is holding it is what lets the assertions below
	# distinguish the victim from the shooter at all.
	_rifle.shooter_body = _shooter

	_victim_kick = _make_kick(_victim)
	_victim_reaction = _make_reaction(_victim, _victim_kick)
	_victim_reaction.struck.connect(_on_struck)
	_bystander_reaction = _make_reaction(_bystander, _make_kick(_bystander))
	_shooter_reaction = _make_reaction(_shooter, _make_kick(_shooter))

	await step_ticks(SETTLE_TICKS)


## Belt and braces on the global the hit stop writes. [method FxHitReaction._exit_tree]
## already ends one when the runner frees this case, and this runs first.
func after_each() -> void:
	if _victim_reaction != null and is_instance_valid(_victim_reaction):
		_victim_reaction.end_hit_stop()


# --- Personal -----------------------------------------------------------------

## The prisoner who was hit feels it. Nobody else does.
##
## [b]Both halves are failures that have shipped in other games.[/b] A reaction
## keyed off [signal Rifle.target_hit] with no owner test flashes every screen in
## the match on every hit; one keyed off the SHOOTER flashes the tower player
## when they connect, which is a hitmarker wearing the victim's clothes. This
## asserts the collider that was struck, and only that, decides whose screen goes
## white.
func test_the_reaction_fires_for_the_victim_and_for_nobody_else() -> void:
	_shoot(_victim)

	assert_true(_victim_reaction.is_reacting(), "the prisoner who was hit reacts")
	assert_false(
		_shooter_reaction.is_reacting(),
		"the shooter who hit them does not -- this is not a hitmarker",
	)
	assert_false(
		_bystander_reaction.is_reacting(),
		"and neither does the prisoner standing next to them",
	)
	assert_eq_int(_struck_directions.size(), 1, "the victim's rig announced it once")

	# And the other way round: a hit on somebody else is not the victim's.
	_shoot(_bystander)
	assert_true(_bystander_reaction.is_reacting(), "the second victim reacts to their own hit")
	assert_eq_int(
		_struck_directions.size(), 1,
		"the first victim heard nothing about somebody else being shot",
	)


## The direction the shot was travelling is carried through to the whip.
##
## The reaction derives it from the impact NORMAL rather than from the shooter's
## position -- see [method FxHitReaction._on_target_hit] -- which is what lets a
## networked client that is merely TOLD it was hit still snap the right way.
func test_the_whip_knows_which_way_the_shot_was_going() -> void:
	var travelling: Vector3 = Vector3(1.0, 0.0, 0.0)
	_rifle.target_hit.emit(_victim, _victim.global_position, -travelling)

	if not assert_eq_int(_struck_directions.size(), 1, "the hit was announced"):
		return
	assert_vec3_almost_eq(
		_struck_directions[0], travelling, 1e-5,
		"the direction handed on is the one the bullet was going, not the one it came from",
	)

	assert_true(_victim_kick.is_active(), "the whip is armed on the frame the hit landed")
	_advance(SIM_DELTA)
	# Read off the SHOVE rather than off the rotation. The shove follows the
	# bullet and is a plain decay, so it is non-zero on every frame of the
	# reaction; the rotation is a decaying OSCILLATION and passes through zero
	# twice a cycle, so a single sample of it can legitimately be nothing.
	var shove: Vector3 = _victim_kick.get_position_offset()
	assert_gt(shove.length(), 0.0, "and the camera was shoved")
	assert_gt(
		shove.normalized().dot(_victim_kick.to_camera_local(travelling)), 0.9,
		"along the direction the bullet was travelling, not against it",
	)


# --- Instant ------------------------------------------------------------------

## Full intensity on the frame the shot resolves, and spent inside the budget.
##
## A baseball has no wind-up from the receiving end. Every channel is asserted to
## be at its maximum on the first sample and monotonically smaller afterwards --
## if anybody ever eases this in, the peak moves off tick zero and this fails.
func test_the_hit_peaks_on_the_first_frame_and_then_only_decays() -> void:
	_shoot(_victim)

	# The flash, before a single tick has been taken: this is what the player
	# sees on the frame the shot resolved.
	assert_almost_eq(
		_victim_reaction.get_flash_alpha(), _profile.flash_color.a, 1e-6,
		"the flash is at full alpha before anything has been stepped",
	)

	var peak: float = 0.0
	var peak_index: int = -1
	var samples: PackedFloat32Array = PackedFloat32Array()
	var shove: PackedFloat32Array = PackedFloat32Array()
	for index: int in OBSERVE_TICKS:
		_advance(SIM_DELTA)
		var magnitude: float = _victim_kick.get_rotation_offset().length()
		samples.append(magnitude)
		shove.append(_victim_kick.get_position_offset().length())
		if magnitude > peak:
			peak = magnitude
			peak_index = index

	assert_gt(peak, 0.0, "the camera was whipped at all")

	# [b]The whip is an oscillation, so its ENVELOPE peaks at t=0 and its
	# sampled angle peaks a quarter of a cycle later.[/b] That is the physics of
	# a head that snaps and rebounds, and it is what stops one swing back to
	# centre reading as a camera lerp -- so the assertion is that the maximum
	# arrives within that quarter cycle and not that it arrives on tick zero.
	# Derived from the profile, so retuning the frequency retunes the bound.
	var half_cycle_ticks: float = 0.5 / _profile.impact_frequency_hz / SIM_DELTA
	assert_le(
		float(peak_index), half_cycle_ticks + 1.0,
		"the whip is at its biggest on the first swing, not on a later rebound",
	)

	# The shove, which is the pure envelope with no oscillation on it, is at its
	# maximum on the very first frame and never rises again. This is the
	# no-ramp claim stated where it can be stated exactly.
	for index: int in range(1, shove.size()):
		if shove[index] > shove[index - 1] + 1e-6:
			fail("the shove grew at tick %d -- something eased the hit in" % index)
			break

	var budget_index: int = mini(int(IMPACT_BUDGET_SECONDS * SIM_HZ), shove.size() - 1)
	assert_le(
		shove[budget_index], shove[0] * RESIDUAL_AT_BUDGET,
		"by %.0f ms the hit is down to noise -- it read as an impact, not an effect"
		% (IMPACT_BUDGET_SECONDS * 1000.0),
	)
	assert_almost_eq(
		_victim_reaction.get_flash_alpha(), 0.0, 1e-6,
		"and the flash is long gone by the end of the run",
	)


## Everything is over, and the camera is back exactly where it was.
##
## "Exactly" is the load-bearing word. A per-frame lerp towards a target settles
## NEAR the base and leaves the player pointing a fraction off where they aimed,
## once per hit, forever. [FxCameraKick] is a closed-form function of elapsed
## time that reaches zero, so the transform at rest is the transform it started
## from -- which is what [method FxCameraKick.is_at_rest] asserts.
func test_the_reaction_ends_and_gives_the_camera_back() -> void:
	var camera: Camera3D = _victim.get_node(CAMERA_PATH) as Camera3D
	var aim_before: Vector3 = -camera.global_transform.basis.z

	_shoot(_victim)
	_advance(maxf(_profile.flash_seconds, _profile.impact_recover_seconds) + 4.0 * SIM_DELTA)

	assert_false(_victim_reaction.is_reacting(), "the flash is spent")
	assert_almost_eq(_victim_reaction.get_flash_alpha(), 0.0, 1e-6, "and draws nothing")
	assert_false(_victim_kick.is_active(), "no channel of the kick is still running")
	assert_true(_victim_kick.is_at_rest(), "the camera is sitting exactly on its base")
	assert_vec3_almost_eq(
		-camera.global_transform.basis.z, aim_before, 1e-5,
		"the player is pointing exactly where they were pointing",
	)


# --- Camera only --------------------------------------------------------------

## Being hit moves the camera and NOTHING else.
##
## The experiment is two identical bodies on one floor under identical (empty)
## intent, one of which is shot. Whatever the character controller does to a
## standing body it does to both, so any difference between them is the hit --
## and the assertion is that there is no difference at all.
##
## [b]The seam, stated.[/b] [PlayerController] never reads [Input]; it asks an
## [IntentSource] for a [MoveIntent] and applies physics to that. Nothing in
## [code]scripts/fx[/code] holds a reference to a body, an intent or a velocity,
## and the [MoveIntent] the victim's [BotIntentSource] carries is asserted
## untouched below -- so the hit cannot have gone round the seam either.
func test_being_hit_moves_the_camera_and_not_the_body() -> void:
	var head: Node3D = _victim.get_node(HEAD_PATH) as Node3D
	var intent: MoveIntent = TestFixtures.bot_input_of(_victim).command

	var victim_from: Vector3 = _victim.global_position
	var bystander_from: Vector3 = _bystander.global_position
	var yaw_before: float = _victim.global_rotation.y
	var pitch_before: float = head.rotation.x

	_shoot(_victim)

	var moved: bool = false
	for _tick: int in OBSERVE_TICKS:
		await step_ticks(1)
		_advance(SIM_DELTA)
		if _victim_kick.get_rotation_offset().length() > 0.0:
			moved = true

	assert_true(moved, "the camera was actually kicked, so the rest of this means something")

	# The body. Compared against the control rather than against zero, so a
	# character controller that settles a millimetre into a floor does not read
	# as a hit having shoved somebody.
	assert_vec3_almost_eq(
		_victim.global_position - victim_from, _bystander.global_position - bystander_from,
		POSITION_TOLERANCE,
		"the prisoner who was hit went exactly as far as the prisoner who was not",
	)
	assert_vec3_almost_eq(
		_victim.velocity, _bystander.velocity, POSITION_TOLERANCE,
		"and is carrying exactly the same velocity",
	)
	assert_almost_eq(
		_victim.global_rotation.y, yaw_before, ANGLE_TOLERANCE,
		"the body's yaw -- which is half the aim -- was never written",
	)
	assert_almost_eq(
		head.rotation.x, pitch_before, ANGLE_TOLERANCE,
		"and neither was the head's pitch, which is the other half",
	)

	# The seam.
	assert_vec2_eq(intent.move_direction, Vector2.ZERO, "no move intent was written")
	assert_vec2_eq(intent.look_delta, Vector2.ZERO, "and no look intent either")
	assert_false(intent.jump_pressed, "nothing pressed jump")
	assert_false(intent.slide_pressed, "nothing pressed slide")


# --- Bots ---------------------------------------------------------------------

## A victim with no camera is a no-op, not an error.
##
## An AI prisoner in a match has no feedback rig at all, so the case that
## actually has to hold is the degraded one: a reaction wired to a body and to no
## [FxCameraKick]. The flash half still runs -- which is the correct degradation,
## the loud half survives -- and the missing camera is simply skipped.
func test_a_victim_with_no_camera_still_works() -> void:
	var bot: PlayerController = _make_body(Vector3(0.0, FLOOR_Y + 0.05, 8.0))
	var reaction: FxHitReaction = _make_reaction(bot, null)
	await step_ticks(2)

	assert_false(reaction.is_inert(), "the reaction is live even without a camera")

	_shoot(bot)
	assert_true(reaction.is_reacting(), "a bot victim reacts")
	assert_almost_eq(
		reaction.get_flash_alpha(), _profile.flash_color.a, 1e-6,
		"at full strength, with no camera to whip",
	)

	reaction.tick(_profile.flash_seconds + SIM_DELTA)
	assert_false(reaction.is_reacting(), "and it finishes on its own clock")


## The whole layer switches off when the master switch does.
##
## The one thing a sweep, a bug report or a designer chasing a feel problem all
## want first: turn it off and the game is exactly the greybox it was.
func test_the_master_switch_turns_the_reaction_off() -> void:
	_profile.enabled = false
	_shoot(_victim)
	assert_false(_victim_reaction.is_reacting(), "nothing flashed")
	assert_false(_victim_kick.is_active(), "and nothing moved the camera")

	_profile.enabled = true
	_profile.hit_reaction_enabled = false
	_shoot(_victim)
	assert_false(_victim_reaction.is_reacting(), "and the victim's own switch works alone")


# --- The tunables -------------------------------------------------------------

## The shipped numbers are in the register the canon asks for.
##
## Not a tuning opinion -- the values themselves are Ryan's to move -- but a
## guard on the SHAPE: no ramp on the flash, a whip that exists, and a reaction
## whose longest channel is still under a third of a second. A profile edited
## into a half-second cinematic fails here, which is the point.
func test_the_shipped_profile_is_instant_and_short() -> void:
	var shipped: FeedbackProfile = load(FEEDBACK_PROFILE_PATH) as FeedbackProfile
	if not assert_not_null(shipped, "the shipped feedback profile loads"):
		return

	assert_true(shipped.enabled, "the layer ships on")
	assert_true(shipped.hit_reaction_enabled, "and so does the victim's half of it")
	assert_true(shipped.impact_shake_enabled, "the camera whip ships on")
	assert_gt(shipped.flash_color.a, 0.5, "the flash is unmissable")
	assert_gt(
		shipped.flash_hold_seconds, 0.0,
		"the flash is HELD at full alpha first -- a hard cut, never a fade in",
	)
	assert_le(shipped.flash_seconds, 0.2, "and is gone inside a fifth of a second")
	assert_le(
		shipped.impact_recover_seconds, 0.35,
		"the whip decays to nothing inside a third of a second",
	)
	assert_gt(
		shipped.impact_roll_degrees, 0.0,
		"there is roll -- the one rotation a first-person camera cannot get from aiming",
	)

	# The drama pass. Ryan, on the first version: [i]"getting shot should be a bit
	# more dramatic than it is now."[/i] These are floors, not the tuning -- the
	# numbers are his to move upwards -- and they exist so that a later edit that
	# quietly halved the hit has to argue with a test.
	assert_ge(shipped.impact_yaw_degrees, 12.0, "the whip is a real whip, not a nudge")
	assert_ge(shipped.impact_roll_degrees, 10.0, "and it rolls hard enough to feel like a blow")
	assert_ge(shipped.impact_punch_metres, 0.12, "and the view is shoved the way the bullet went")
	assert_almost_eq(shipped.flash_color.a, 1.0, 1e-6, "the flash is a full white frame")
	assert_true(shipped.hit_stop_enabled, "and the world hitches on the frame you are hit")
	assert_le(
		shipped.hit_stop_seconds, 0.1,
		"for well under a tenth of a second -- longer reads as a frame drop",
	)


## The victim's own hit sound is a cue in the shipped bank, and it is flat.
##
## [constant AudioEvents.PLAYER_HIT_TAKEN] is deliberately not
## [constant AudioEvents.RIFLE_HIT]: that one is the impact as the world hears
## it, positional and attenuated, posted for every hit anybody lands. This one
## plays only on the machine it happened to, and there is no distance to a sound
## made inside your own head.
func test_the_victims_hit_has_a_flat_cue_in_the_bank() -> void:
	assert_true(
		AudioEvents.ALL.has(AudioEvents.PLAYER_HIT_TAKEN),
		"the event is in the roll call, so a bank is incomplete without it",
	)
	assert_false(
		AudioEvents.POSITIONAL.has(AudioEvents.PLAYER_HIT_TAKEN),
		"and it is not one of the positional ones",
	)

	var bank: AudioBank = load(BANK_PATH) as AudioBank
	if not assert_not_null(bank, "the shipped bank loads"):
		return
	var cue: AudioCue = bank.get_cue(AudioEvents.PLAYER_HIT_TAKEN)
	if not assert_not_null(cue, "the bank carries a cue for it"):
		return
	assert_not_null(cue.stream, "the cue has a stream behind it")
	assert_false(cue.positional, "the cue is flat, not placed in the world")
	assert_eq_int(bank.missing_events().size(), 0, "and the bank is still complete")


## The hit stop: the world slows, and it gives the clock back exactly.
##
## [b]The assertion that matters is the restore, not the slow.[/b]
## [member Engine.time_scale] is global and this is the only thing in the project
## that writes it, so the failure worth catching is not "it did not hitch" -- it
## is "it hitched and never stopped", which would leave the whole game running at
## a tenth speed with nothing on screen to say why.
##
## Ended through the public seam rather than by sleeping on a wall clock: the
## deadline is in real microseconds by design (see
## [member FeedbackProfile.hit_stop_enabled]), and a test that waited for real
## time would be a test whose result depended on how busy the machine was.
func test_the_hit_stop_slows_the_world_and_gives_the_clock_back() -> void:
	var before: float = Engine.time_scale
	_profile.hit_stop_enabled = true
	_profile.hit_stop_seconds = 0.07
	_profile.hit_stop_scale = 0.12

	_shoot(_victim)

	assert_true(_victim_reaction.is_hit_stopped(), "the world is hitched")
	assert_lt(Engine.time_scale, before, "and is running slower than it was")
	assert_almost_eq(
		Engine.time_scale, before * _profile.hit_stop_scale, 1e-6,
		"by exactly the profile's factor, applied to whatever scale was in force",
	)
	assert_almost_eq(
		_victim_reaction.get_hit_stop_base_scale(), before, 1e-6,
		"and it remembered the scale it has to put back",
	)

	# A second hit inside the first stop must not compound. This is the failure
	# that would make the game get permanently slower the more you were shot.
	_shoot(_victim)
	assert_almost_eq(
		Engine.time_scale, before * _profile.hit_stop_scale, 1e-6,
		"a second hit inside the first stop does not stack",
	)
	assert_almost_eq(
		_victim_reaction.get_hit_stop_base_scale(), before, 1e-6,
		"and does not adopt the slowed scale as the one to restore",
	)

	_victim_reaction.end_hit_stop()
	assert_false(_victim_reaction.is_hit_stopped(), "the stop ended")
	assert_almost_eq(Engine.time_scale, before, 1e-6, "and the clock is exactly back")

	# And the other two doors out of it.
	_shoot(_victim)
	assert_true(_victim_reaction.is_hit_stopped(), "hitched again")
	_victim_reaction.clear()
	assert_almost_eq(Engine.time_scale, before, 1e-6, "clear() gives the clock back too")


## Off in code, on in the file. A profile built from nothing must never write a
## global that a headless sweep is relying on.
func test_the_hit_stop_is_off_by_default_in_code() -> void:
	assert_false(
		FeedbackProfile.new().hit_stop_enabled,
		"a default-constructed profile does not touch Engine.time_scale",
	)
	var before: float = Engine.time_scale
	_profile.hit_stop_enabled = false
	_shoot(_victim)
	assert_false(_victim_reaction.is_hit_stopped(), "and with it off, nothing hitches")
	assert_almost_eq(Engine.time_scale, before, 1e-6, "the clock was never written")


# --- Fixtures -----------------------------------------------------------------

## One body from the shipped player scene, driven by a bot source that is never
## given anything to do. Placed before it enters the tree, which is how
## [MatchController] does it and why -- see [method MatchController._hold_body].
func _make_body(where: Vector3) -> PlayerController:
	var body: PlayerController = TestFixtures.make_bot_player(TestFixtures.movement_profile())
	body.position = where
	add_child(body)
	return body


## An [FxCameraKick] on [param body]'s own camera, stepped by hand.
func _make_kick(body: PlayerController) -> FxCameraKick:
	var kick: FxCameraKick = FxCameraKick.new()
	kick.name = "CameraKick_%s" % body.get_instance_id()
	# The one licence scenes/fx/feedback_rig.tscn grants: a test that needs the
	# logic to actually run without a display server says so.
	kick.headless_inert = false
	kick.profile = _profile
	kick.camera = body.get_node(CAMERA_PATH) as Camera3D
	add_child(kick)
	kick.set_process(false)
	return kick


## An [FxHitReaction] listening to the one rifle on behalf of [param body].
## [param kick] may be null, which is the bot case.
func _make_reaction(body: PlayerController, kick: FxCameraKick) -> FxHitReaction:
	var reaction: FxHitReaction = FxHitReaction.new()
	reaction.name = "HitReaction_%s" % body.get_instance_id()
	reaction.headless_inert = false
	reaction.profile = _profile
	reaction.rifle = _rifle
	reaction.body = body
	reaction.camera_kick = kick
	add_child(reaction)
	reaction.set_process(false)
	return reaction


## Report a rifle hit on [param body] through the signal the real weapon emits.
##
## The normal points back at the shooter, so the bullet was travelling the other
## way; see [method FxHitReaction._on_target_hit] for why the direction is
## derived from the normal rather than from a shooter node.
func _shoot(body: PlayerController) -> void:
	var here: Vector3 = body.global_position + Vector3(0.0, 1.0, 0.0)
	var from_shooter: Vector3 = (here - _shooter.global_position).normalized()
	_rifle.target_hit.emit(body, here, -from_shooter)


## Step every effect node in this test by [param seconds] of simulated time, in
## whole physics ticks, through the public harness seam both classes expose.
func _advance(seconds: float) -> void:
	var ticks: int = maxi(int(roundf(seconds / SIM_DELTA)), 1)
	for _tick: int in ticks:
		_victim_kick.tick(SIM_DELTA)
		_victim_reaction.tick(SIM_DELTA)
		_bystander_reaction.tick(SIM_DELTA)
		_shooter_reaction.tick(SIM_DELTA)


func _on_struck(world_direction: Vector3) -> void:
	_struck_directions.append(world_direction)
