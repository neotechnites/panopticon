class_name MatchController
extends Node

## The match: many rounds, many seat changes, exactly one winner.
##
## Every rule of the match is ENFORCED here and nowhere else, and DECIDED in
## [MatchRules]. The rifle reports what it struck and stays ignorant of what that
## means; [RingRunner] reports that it finished its lap and stays ignorant of
## what that costs; [MatchLapTracker] reports arc and rules on nothing; the
## player's body knows nothing about any of it. This node is the only place that
## turns those reports into a seat change, a round, or a match.
##
## [b]The shape of a match[/b]
##
## [codeblock]
## start_match()
##   |
##   +-- RACE ............ no shooter at all. Every participant runs the ring.
##   |     |               The first to reach the end takes the tower.
##   |     v
##   +-> ROUND ........... one participant in the tower, the rest running.
##         |               No clock.
##         |
##         +-- a runner reaches the end
##         |     -> round resolves LOSS
##         |     -> that runner TAKES THE SEAT (turn count +1, reload recomputed)
##         |     -> the outgoing shooter becomes a runner
##         |     -> the round RESTARTS from the beginning; no progress carries
##         |
##         +-- the shooter converts every runner
##               -> round resolves WIN
##               -> the shooter has won a round FROM THE TOWER
##               -> MATCH_OVER
## [/codeblock]
##
## Reaching the end never wins the match. It wins the tower. The tower is the
## prize, and holding it through a round is the win -- which is why the outcome
## of a round is still named from the shooter's point of view: [constant
## Outcome.WIN] is the shooter converting everyone, [constant Outcome.LOSS] is
## somebody arriving and taking the seat off them.
##
## [b]The seat is a role, not a body[/b]
##
## There is no "the shooter node". There are [MatchParticipant]s, one per player
## for the whole match, and exactly one of them holds the seat at a time. Taking
## the seat means: your body is put on the tower, the rifle is reparented to your
## head, your lap tracker stops, your lap-running brain (if you are AI) is
## switched off, your TOWER brain (if you are AI) is switched on, and your turn
## count goes up. It works identically for the human and for a bot, which is the
## requirement -- when a bot takes the tower the human is put on the track and
## runs like everybody else.
##
## [b]Two brains, one of them running[/b]
##
## An AI participant owns a [RingRunner] and a [TowerShooter] and is driven by
## exactly one of them, decided by where the match has just put its body:
##
## [codeblock]
## on the track -> RingRunner runs,   TowerShooter down
## in the tower -> TowerShooter runs, RingRunner down
## converted, or during the race -> neither
## human, anywhere -> neither; the keyboard drives it
## [/codeblock]
##
## The swap happens in [method _arm_tower_brain], from [method _wake_bodies], on
## the tick the placed bodies come back to life -- which is the only tick on
## which it is safe. See both. What a bot in the tower DOES with the rifle is
## still not this node's business: it is [TowerShooter]'s, and this node only
## points it at the rifle, the eye and the group of legitimate targets that the
## seat change has just changed underneath it.
##
## [b]The terminator[/b]
##
## Each turn in the tower shortens the holder's reload by
## [member MatchRules.reload_reduction_per_turn], down to
## [method MatchRules.get_reload_floor_seconds]. A shooter too weak to close out
## a round loses the seat, wins it back, and comes back faster; eventually fast
## enough. That is the only reason a match is guaranteed to end, and it is why
## [member MatchRules.turn_count_resets_on_seat_loss] defaults to false -- see
## that field for the two readings of "consecutive" and why this one is shipped.
##
## [b]Ghosts: the third role[/b]
##
## Under [constant MatchRules.GhostBehaviour.CATCH_AND_SWAP] a shot prisoner is
## not removed. They are put back on the START LINE as a GHOST -- faster than the
## living, unshootable, and chasing. Reaching a living prisoner takes their spot:
## the caught player becomes the ghost, the ghost becomes living, and the round
## carries on with the same number of prisoners running it. That is the whole
## mechanic, and it exists to satisfy one constraint the author stated plainly:
## nobody sits out.
##
## Three properties of the swap are load-bearing and are enforced here:
##
## - [b]A catch is not a conversion.[/b] It moves the living/ghost line, it does
##   not move it downwards. [method get_runners_remaining] is unchanged by a
##   catch, so [constant MatchRules.ShooterWinCondition.TOTAL_CONVERSION] still
##   means what it meant: only the RIFLE can empty the ring.
## - [b]A ghost drives the same seam.[/b] Its body is the same
##   [PlayerController], written to through the same [MoveIntent]. The bot's
##   ghost is a [RingRunner] in chase mode; the human's ghost is the keyboard.
##   Nothing about the catch is a bot-only path.
## - [b]The catch is ruled here.[/b] Not in the brain -- a brain that called its
##   own catch would be a catch only bots could make.
## - [b]A ghost is made at the start, never where it fell.[/b] The author's
##   ruling, and it is a placement onto a line several bodies may be standing on:
##   see [method _place_ghost_at_start] for the one thing that makes it safe.
##
## [b]The three ways the tower wins[/b]
##
## All of [enum MatchRules.ShooterWinCondition] is implemented, and all three
## reach the same door -- [method _resolve] with [constant Outcome.WIN], then
## [method _award_round_to_shooter]. There is no second win path:
##
## [codeblock]
## TOTAL_CONVERSION -> get_runners_remaining() == 0
## SHUTOUT_COUNT    -> get_runners_removed() >= rules.shutout_count, THIS round
## HOLD_DURATION    -> the round has been alive rules.hold_duration_seconds
## [/codeblock]
##
## The first two are checked where a runner leaves the round and nowhere else
## ([method _check_shooter_win], called from [method convert_participant]); the
## third is a clock ticked in [method _physics_process] by [method _tick_hold].
## None of them falls back on another, so a round played under one is never
## decided on the terms of a second: under SHUTOUT_COUNT an empty ring wins only
## because emptying it removed enough prisoners to satisfy the count, and under
## HOLD_DURATION an empty ring wins nothing at all until the clock runs out.
##
## [b]Not implemented, deliberately[/b]
##
## [constant MatchRules.GhostBehaviour.SPECTATOR] and
## [constant MatchRules.GhostBehaviour.CONTINUE_LAP], lives beyond
## [member MatchRules.prisoner_lives], and
## [member MatchRules.round_time_limit_seconds]. Those are deferred design
## questions and inventing answers to them here would make the answers permanent
## by accident.

## Where a match is, exhaustively.
enum Phase {
	## Built but not started. [method start_match] leaves it.
	IDLE,
	## The opening race. No shooter, no rifle in anyone's hands, everybody
	## running. Ends the moment somebody reaches the end.
	RACE,
	## One shooter, the rest running. The state a match spends its life in.
	ROUND,
	## Somebody won a round from the tower. Nothing moves and nothing resolves.
	MATCH_OVER,
}

## What a round has come to, from the shooter's point of view. Exhaustive.
enum Outcome {
	## Live. The only state in which a hit or a finished lap means anything.
	IN_PROGRESS,
	## The shooter converted every runner. Under the shipped rules this also
	## wins the match.
	WIN,
	## A runner reached the end. The shooter loses the SEAT, not the match.
	LOSS,
}

## Emitted once, when a match is armed and before the race or the first round
## starts. Carries how many players are in it.
signal match_started(participant_count: int)

## Emitted when the opening race is armed: no shooter, everyone on the ring.
signal race_started()

## Emitted when a round is armed, after the shooter is on the tower and the
## prisoners are on the start line. A seat change emits it again, because a seat
## change restarts the round.
signal round_started()

## Emitted whenever the tower changes hands, including the grant that ends the
## opening race and the first round of a match that skipped it.
##
## [param turns_in_tower] is the new holder's own count INCLUDING this turn, so
## it is 1 on their first turn. It is what the reload is computed from.
signal seat_changed(participant: MatchParticipant, turns_in_tower: int)

## Emitted once per round, on the tick it resolves. A [constant Outcome.LOSS] is
## followed immediately by [signal seat_changed] and [signal round_started].
signal round_resolved(outcome: Outcome)

## Emitted once per match, when a participant wins a round from the tower. The
## match stops here: nothing resolves afterwards.
signal match_won(participant: MatchParticipant)

## Emitted when a runner leaves the field, carrying how many are still running.
## Both endings fire it: a prisoner converted in a round, and a racer who falls
## out of the opening race.
signal runner_removed(remaining: int)

## A participant left the running set: converted in a round, or out of the race.
signal participant_converted(participant: MatchParticipant)

## Emitted when a participant becomes a ghost, by either route: the rifle
## finished them, or another ghost caught them.
signal runner_ghosted(participant: MatchParticipant)

## Emitted on the tick a killed participant's respawn hold expires and the match
## has just put their body down on the start line.
##
## The other end of [member GhostProfile.respawn_delay_seconds]:
## [signal runner_ghosted] fires when somebody DIES, this fires when they are
## PUT BACK, and between the two is the hold. Both fire even when the hold is
## zero, in that case on the same tick.
##
## Carries the participant, and is emitted after the position and the facing
## have been written but before the placement's two-frame settle has woken the
## body -- so a listener reads exactly where the match put them, with nothing
## having moved since.
signal ghost_respawned(participant: MatchParticipant)

## Emitted on the tick a ghost takes a living prisoner's spot. [param ghost] is
## the participant who WAS the ghost and is now running; [param caught] is the
## prisoner who is now the ghost. The swap has already happened when it fires.
signal ghost_caught(ghost: MatchParticipant, caught: MatchParticipant)

## Emitted on the tick one prisoner shoves another. [param victim] has already
## been launched when it fires.
signal participant_shoved(shover: MatchParticipant, victim: MatchParticipant)

## Every design parameter of the match: how many players, on what track, at what
## pace, with what reload escalation, and what counts as a win.
##
## Leave it unset and the match runs on a default-constructed [MatchRules] (see
## [method get_rules]). A sweep assigns a variant here and changes nothing else.
@export var rules: MatchRules

## The arena instance. Its origin is the ring axis and the markers are found
## under it by the three paths below.
@export var arena: Node3D

## The human's body. One participant is built around it, and it is put on the
## tower or on the track exactly like any other participant's.
##
## May be null: a match with no human is every participant AI, which is what a
## headless sweep runs.
@export var player: PlayerController

## The colours this match paints its bodies with -- one per runner seat, plus
## the guard's own. Leave it unset and the match runs on the shipped
## [code]resources/rules/default_runner_palette.tres[/code] (see [method
## get_runner_palette]), exactly the way [member rules] falls back to a default
## [MatchRules]. Ryan's to edit; nothing in this script names a colour directly.
@export var palette: RunnerPalette

## The tower's rifle. Reparented to whoever holds the seat, and stowed on this
## node while the opening race runs -- during the race the rifle is nobody's.
@export var rifle: Rifle

## Where AI bodies are parented. They live for the whole match; a converted
## runner is parked, not freed, because the round restarts the moment the seat
## changes and they are back on the ring in the same frame.
@export var runner_container: Node3D

## The body scene AI participants are built from.
@export var runner_scene: PackedScene

## Optional. The human's camera kick, so their own shove is felt. Null
## everywhere but the match scene, and a null one simply goes unfelt.
@export var shove_camera_kick: FxCameraKick

@export var start_marker_path: NodePath = ^"StartEnd/PrisonerStart"
@export var end_marker_path: NodePath = ^"StartEnd/PrisonerEnd"
@export var spawn_marker_path: NodePath = ^"Tower/TowerSpawn"

## Where the arena keeps its [RingRoute]: the levels a prisoner must lap, in
## order, and the ramps between them.
##
## Optional, and its absence is a supported map rather than a fault. An arena
## with no route node gets [method RingRoute.flat] built from
## [member MatchRules.track_radius] and the two markers -- one level, one lap,
## exactly the run the ring had before it had levels -- so everything that
## measures the route reads a route and only a route, and a flat second map
## needs no second code path anywhere.
@export var route_path: NodePath = ^"Route"

## Arm the match from [method Node._ready]. Off for a harness that wants to place
## things itself before the clock starts.
@export var auto_start: bool = true

## Physical key that restarts the whole match. Read as a physical scancode rather
## than through the input map because the map is [code]project.godot[/code]'s
## business and this scene does not get to add actions to it.
const RESTART_KEY: Key = KEY_R

## Long enough to run any reload out in a single [method Rifle.tick]. Used to
## force the weapon back to READY on a seat change without reaching into its
## state machine: tick() is the weapon's own public harness seam, and one
## enormous step lands on READY from FIRING or RELOADING alike.
const FORCE_READY_SECONDS: float = 3600.0

## Where a converted runner's body is put: straight down, well under the pit
## floor, with its collision switched off and its mesh hidden.
##
## [member MatchRules.ghost_behaviour] is [constant
## MatchRules.GhostBehaviour.NONE], which means a converted prisoner is gone from
## the world -- and this is gone from the world. It is a park rather than a
## [method Node.queue_free] only because the PARTICIPANT outlives the round: they
## are back on the ring the instant somebody takes the seat. Nothing here is a
## ghost; a parked body does not move, cannot be hit and renders nothing.
const PEN_DEPTH_METRES: float = -100.0

## Horizontal spacing between parked bodies, so two of them are not stacked in
## the same cubic metre even though neither can collide.
const PEN_SPACING_METRES: float = 4.0

## The collision layer a ghost stands on instead of its own, whenever
## [member GhostProfile.shootable] is off.
##
## Bit 20 (value [code]1 << 20[/code]), chosen deliberately against
## [member WeaponProfile.hit_mask]'s shipped default of [code]0xFFFFF[/code] --
## bits 0 through 19, which is every layer the rifle's raycast, the tower bot's
## line-of-sight probe ([code]tower_shooter.gd[/code]) and the runner's own
## perception raycast ([code]runner_perception.gd[/code]) all test, because all
## three read [member Rifle.profile]'s [member WeaponProfile.hit_mask] rather
## than inventing a mask of their own. Bit 20 sits outside every one of them, so
## a ghost placed on it is exactly as unshootable as a ghost on no layer at all
## was.
##
## What changes is that [KillVolume] and [TrapVolume] widen their OWN
## [member CollisionObject3D.collision_mask] to include this one bit
## specifically -- see the masks authored in
## [code]scenes/ring/bentham_ring.tscn[/code] -- so a hazard that has to see a
## ghost can, while nothing that merely shares the rifle's default mask finds
## one by accident.
const GHOST_HAZARD_LAYER: int = 1 << 20

## The [GhostProfile] a round runs on when [MatchRules] names none. The same
## resource [code]resources/rules/default_match_rules.tres[/code] points at, so
## a match assembled in code plays the ghost the shipped rules were written for
## rather than a second, quietly different default.
const DEFAULT_GHOST_PROFILE_PATH: String = "res://resources/rules/default_ghost_profile.tres"

## The [RunnerPalette] a match paints its bodies from when [member palette]
## names none. The same one companion resources point at, for the same reason
## [constant DEFAULT_GHOST_PROFILE_PATH] exists: a scene assembled in code gets
## the palette the game ships rather than a second, quietly different default.
const DEFAULT_PALETTE_PATH: String = "res://resources/rules/default_runner_palette.tres"

## The node holding the humanoid a body is seen as. Every body in the game comes
## from [code]scenes/player/player.tscn[/code], which calls it this.
const BODY_AVATAR_NAME: StringName = &"Avatar"

## The name of the greybox capsule mesh, painted when a body has no [PrisonerAvatar].
##
## Kept as a fallback rather than deleted: this is the only thing in the match
## that reaches into a body to change how it looks, and a body assembled without
## the model -- a test fixture, a stripped harness scene -- should still be able
## to show which of its participants are ghosts.
const BODY_MESH_NAME: StringName = &"BodyMesh"

## The [ShooterProfile] an AI in the tower plays on when [MatchRules] names
## none. The same resource [code]scenes/bot/tower_shooter.tscn[/code] ships
## with, so a bot that takes the seat here plays exactly the shooter that scene
## was tuned as rather than a second, quietly different default.
const DEFAULT_SHOOTER_PROFILE_PATH: String = "res://scenes/bot/default_shooter_profile.tres"

## The finisher's rifle, instanced from the SAME scene the guard's is authored
## from, so the prisoner who reaches the end gets the guard's gun -- model,
## optic, recoil, reload -- and not a second weapon that could drift from it.
const FINISHER_RIFLE_SCENE_PATH: String = "res://scenes/weapon/rifle.tscn"

## Physics priority given to the first-scored lap tracker; the rest count up from
## it. See [method _order_the_scoring].
##
## Positive, and deliberately so: a body ticks at the default priority of 0, and
## every tracker must sample AFTER every body has moved or one racer would be
## scored a tick stale.
const TRACKER_PRIORITY_BASE: int = 1

## Physics frames a freshly placed body spends inert before it is woken.
##
## Two rather than one because a seat change can be raised from inside a physics
## frame (a lap tracker finishing) or from an idle one (a harness, a restart key),
## and two frames is correct from either. See [method _place_body_at].
const SETTLE_PHYSICS_FRAMES: int = 2

## Scene-tree group holding exactly the bodies that are RUNNING right now.
##
## The match's answer to "who is a legitimate target". Membership is maintained
## by placement: joined when a participant is put on the track, left when they
## take the tower or are converted. It is a group rather than a list because the thing
## that needs it is an AI in the tower, which must be able to find its targets
## without a reference to this node -- the same way a human finds them, by
## looking at the ring.
##
## [b]It is not a list of AI.[/b] The human is in it whenever the human is
## running, which is the whole point: a bot holding the seat shoots at the human
## on exactly the terms a human holding the seat shoots at bots.
const RUNNER_GROUP: StringName = &"prisoners"

## How square in front of the shover a body must be to be shoved: a 90 degree
## cone, so a shove pushes who you are looking at and not who you brushed past.
const SHOVE_FACING_DOT: float = 0.5

## How hard the shover's own camera is kicked. Small on purpose -- the feedback
## is the other body leaving, not the screen moving.
const SHOVE_KICK_SCALE: float = 0.5

## Scene-tree group holding exactly the body that is IN THE TOWER right now, or
## nothing at all during the opening race.
##
## The mirror of [constant RUNNER_GROUP], and it exists for the mirror reason.
## That one is how a guard finds the prisoners without a reference to this node;
## this one is how a prisoner finds the guard -- see [RunnerPerception], which
## reads it and nothing else about the match.
##
## [b]It is not a list of humans.[/b] Whoever holds the seat is in it, human or
## AI, exactly as whoever is running is in [constant RUNNER_GROUP]. The bug it
## was added for is what happens when the two kinds are told apart: a prisoner
## could only ever find an AI guard, because an AI guard is a [TowerShooter] node
## and a human guard is a person, so a round with the human in the tower read to
## every bot on the ring as a round with NOBODY in the tower. They ran the
## baseline lap past a rifle they never believed in. Announcing the seat rather
## than the brain is what makes "there is a guard" a fact about the round instead
## of a fact about what kind of thing took it.
##
## Maintained from [method _arm_tower_brain], which is already the last word on
## who is driving which body.
const GUARD_GROUP: StringName = &"tower_guard"

## Physics frames left before the bodies placed by the last arming are woken.
var _settle_frames: int = 0

var _phase: Phase = Phase.IDLE
var _outcome: Outcome = Outcome.IN_PROGRESS

## Everyone in the match, in a fixed order. Index 0 is the human when there is
## one. The order is where they stand on the start line and the race's
## tiebreaker, which is what keeps both deterministic rather than a draw.
var _participants: Array[MatchParticipant] = []

## Who holds the tower. Null during the opening race, and only then.
var _seat: MatchParticipant = null

## Who won the match, once somebody has.
var _winner: MatchParticipant = null

## Body instance id -> participant. The rifle hands back the [CollisionObject3D]
## a ray struck; the match thinks in participants. Built at match start from the
## bodies themselves, so it survives any restructuring of the body scene.
var _participant_by_body_id: Dictionary[int, MatchParticipant] = {}

## Rounds armed so far this match. The race is not one.
var _round_number: int = 0

## How many runners the current round or race was armed with.
var _round_runner_count: int = 0

## How many times this controller has resolved a round. A regression in the
## once-only guard shows up here as a number greater than the rounds played.
var _resolve_count: int = 0

## Runners out of the current round or race: converted by the rifle, or fallen.
var _removed_count: int = 0

## Keeps the unwinnable-rules complaint to one line per round instead of one per
## frame. Both complaints share it: a win condition this node does not implement,
## and one it does implement that has been handed a number it cannot be won with.
var _warned_unimplemented_rules: bool = false

## Seconds of siege left in this round under
## [constant MatchRules.ShooterWinCondition.HOLD_DURATION].
##
## Armed by [method start_round] from [member MatchRules.hold_duration_seconds]
## and by nothing else, so it restarts with the round exactly as runner progress
## does -- a seat change is a new siege, not a continuation of the last one. It
## is 0.0 under every other win condition and is then never read.
var _hold_remaining: float = 0.0

## Backing store for the rules used when [member rules] is unset. Built on
## demand, never shared, so a caller that retunes it cannot reach into another
## controller's match.
var _fallback_rules: MatchRules

## The ghost tuning in force, resolved once per arming rather than per tick:
## [method GhostProfile.resolve] walks a property list and the answer cannot
## change inside a round. Cleared by [method start_match] and
## [method start_round] so a retuned rule set is picked up.
var _ghost_profile: GhostProfile = null

## The shipped ghost tuning, loaded once and used when [MatchRules] names none.
var _default_ghost_profile: GhostProfile = null

## Ghost swaps this controller has performed. A readout, nothing branches on it.
var _catch_count: int = 0

## The prisoner who reached the end and is hunting the guard, or null. At most
## one: the round ends the moment either of them dies.
var _finisher: MatchParticipant = null

## The second rifle, built on the first arming and kept for the match. Parked on
## this node between hunts, exactly as the guard's is during the race.
var _finisher_rifle: Rifle = null

## The shipped default palette, loaded on first use when [member palette] names
## none. See [method get_runner_palette].
var _default_palette: RunnerPalette = null

## Painted runner materials, one per [member MatchParticipant.index], built
## lazily and kept for the life of the match -- an index always names the same
## participant, so nothing here is ever invalidated.
var _runner_material_cache: Dictionary[int, Material] = {}

## The same participants' ghost-translucent materials, same cache discipline
## as [member _runner_material_cache].
var _ghost_material_cache: Dictionary[int, Material] = {}

## The one material the tower seat wears, built once: unlike a runner's colour
## it does not vary by who is sitting in the seat.
var _guard_material_cache: Material = null

# Arena geometry, cached at match start. The arena does not move.
var _centre: Vector3 = Vector3.ZERO
var _start_point: Vector3 = Vector3.ZERO
var _end_point: Vector3 = Vector3.ZERO
var _tower_point: Vector3 = Vector3.ZERO

## The route the field is running. Never null once [method _cache_geometry] has
## succeeded: either the arena's own, or a flat one built here and parented to
## this controller so it lives and dies with the match.
var _route: RingRoute = null

## True when [member _route] is the fallback this node made, and therefore this
## node's to free when the map changes.
var _route_is_ours: bool = false

var _geometry_ready: bool = false

## Seat-indexed bodies handed in by the net layer; empty means solo (player + bots).
var _net_bodies: Array[PlayerController] = []
var _net_kinds: Array[MatchParticipant.Kind] = []
var _net_names: PackedStringArray = PackedStringArray()

## Index of this machine's own participant. 0 solo and on the host.
var _local_index: int = 0

## True on a client: nothing here decides; net_* methods apply what the server decided.
var _mirror: bool = false
var _applying: bool = false


## The rule set actually in force, never null.
func get_rules() -> MatchRules:
	if rules != null:
		return rules
	if _fallback_rules == null:
		_fallback_rules = MatchRules.new()
	return _fallback_rules


## The ghost tuning actually in force, never null.
##
## [MatchRules] names one, a JSON sweep spec names one through metadata, or the
## shipped default is used -- see [method GhostProfile.resolve] and
## [constant DEFAULT_GHOST_PROFILE_PATH]. Never null, because every caller of it
## is on a path where a ghost already exists and there is no sensible way to
## abandon one halfway.
func get_ghost_profile() -> GhostProfile:
	if _ghost_profile != null:
		return _ghost_profile
	if _default_ghost_profile == null:
		_default_ghost_profile = load(DEFAULT_GHOST_PROFILE_PATH) as GhostProfile
		if _default_ghost_profile == null:
			push_warning(
				"MatchController cannot load %s; ghosts will run on GhostProfile's own defaults."
				% DEFAULT_GHOST_PROFILE_PATH
			)
			_default_ghost_profile = GhostProfile.new()
	_ghost_profile = GhostProfile.resolve(get_rules(), _default_ghost_profile)
	return _ghost_profile


func _ready() -> void:
	_install_chosen_map()
	if arena == null or rifle == null or runner_scene == null or runner_container == null:
		push_error("MatchController is missing an arena, a rifle, a runner scene or a container; no match will run.")
		return
	rifle.target_hit.connect(_on_target_hit)
	if auto_start:
		start_match()


## Wakes the bodies the last arming placed, once the physics server has caught
## up with where they were put. Does nothing on every other frame.
func _physics_process(delta: float) -> void:
	if _mirror:
		return
	if _settle_frames > 0:
		_settle_frames -= 1
		if _settle_frames == 0:
			_wake_bodies()
	# ORDER IS LOAD-BEARING, and it is worth a sentence each.
	#
	# _wake_settled_ghosts runs BEFORE _tick_respawn_holds so that a settle armed
	# by a respawn finishing on THIS tick is not decremented on the same tick it
	# was armed. Run the other way round it is: the placement writes
	# SETTLE_PHYSICS_FRAMES and the very next line takes one straight back off,
	# so the body wakes a frame early and the physics-server handshake
	# [method _hold_body] documents is one frame short of what it asks for.
	#
	# _tick_ghosts runs LAST so that a ghost placed this tick is skipped by it --
	# it now has a settle running, and a ghost inside its settle is not in the
	# world yet. See that method.
	_wake_settled_ghosts()
	_tick_respawn_holds(delta)
	_tick_ghosts(delta)
	_tick_shoves(delta)
	# LAST, and after the ghosts: the hold is the only win condition decided by
	# a clock rather than by an event, and a round it ends is a round in which
	# everything else that was going to happen this tick has already happened.
	_tick_hold(delta)


func _unhandled_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.physical_keycode == RESTART_KEY and not _mirror:
		start_match()
		get_viewport().set_input_as_handled()


# --- The map ------------------------------------------------------------------

## The arena scene the rules in force name. Empty when they name no map at all.
func get_map_scene_path() -> String:
	return MapCatalog.scene_path_for(get_rules().map_id)


## Put the map [member MatchRules.map_id] names into the scene, replacing the
## arena the scene was authored with if it is a different one.
##
## [b]Why the controller and not the match scene.[/b] The player chooses a map on
## the setup screen, that choice reaches [MatchRules] through the one path every
## other rule takes -- [method GameSettings.apply_to_match_rules], called by the
## [SettingsBoot] node in [code]scenes/match/match.tscn[/code] -- and this is the
## node that reads the rules. Loading the arena anywhere else would be a second
## path for one setting, which is exactly the thing the setup screen's header
## forbids.
##
## [b]It runs before anything is measured.[/b] From [method Node._ready], ahead
## of [method start_match], so [method _cache_geometry] reads the markers of the
## arena actually standing. The node keeps the name and the slot of the one it
## replaces, so [code]../Arena[/code] typed anywhere else still resolves.
##
## [b]Three cases where it deliberately does nothing.[/b] No arena at all (the
## caller is about to be told); an empty [member MatchRules.map_id]; and an arena
## whose [member Node.scene_file_path] is empty -- a world assembled in code, by
## a test or by a harness, which placed the arena it meant to place and is not
## this method's to overrule.
func _install_chosen_map() -> void:
	if arena == null or arena.scene_file_path.is_empty():
		return
	var wanted: String = get_map_scene_path()
	if wanted.is_empty() or wanted == arena.scene_file_path:
		return

	var packed: PackedScene = load(wanted) as PackedScene
	var replacement: Node3D = null
	if packed != null:
		replacement = packed.instantiate() as Node3D
	if replacement == null:
		push_error(
			"MatchController cannot load the map %s; the arena the scene was authored with stands."
			% wanted
		)
		return

	var parent: Node = arena.get_parent()
	if parent == null:
		replacement.free()
		return

	var slot: int = arena.get_index()
	var arena_name: StringName = arena.name
	var placement: Transform3D = arena.transform
	var replaced: Node3D = arena

	# Out of the tree BEFORE the replacement goes in, so the name is free and
	# Godot does not quietly rename the new arena to Arena2 -- which every
	# NodePath in the match scene points away from.
	parent.remove_child(replaced)
	replaced.queue_free()

	replacement.name = arena_name
	replacement.transform = placement
	parent.add_child(replacement)
	parent.move_child(replacement, slot)
	arena = replacement


# --- The match ----------------------------------------------------------------

## Tear down whatever match is running and arm a fresh one.
##
## Turn counts, rounds won and the winner all go back to zero: the terminator is
## defined over a player's history within ONE match, so carrying a count across
## restarts would hand the next match a shooter who is already fast.
func start_match() -> void:
	if arena == null or rifle == null:
		push_error("MatchController cannot start a match without an arena and a rifle.")
		return

	var active: MatchRules = get_rules()
	# Once per match, not once per round: a round now restarts on every seat
	# change and a per-round complaint would be a wall of identical warnings.
	for problem: String in active.validate():
		push_warning("MatchRules: %s" % problem)

	_cache_geometry()
	# Re-resolved from the rule set in force NOW, exactly as the tower brains
	# below are rebuilt from it.
	_ghost_profile = null
	_catch_count = 0
	_disarm_finisher()
	# Before the roster is rebuilt, while the old participants are still here to
	# be read. See the method: difficulty is drawn when a brain is BUILT.
	_release_tower_brains()
	_build_participants()
	if _participants.is_empty():
		push_error("MatchController has no participants; there is nobody to play a match.")
		return
	# Every body in this match, human and bots alike, on the shipped air
	# control. See [method _apply_air_control].
	_apply_air_control()

	for participant: MatchParticipant in _participants:
		participant.turns_in_tower = 0
		participant.rounds_won = 0
		participant.is_shooter = false
		participant.is_running = false
		_unmake_ghost(participant)
	_seat = null
	_winner = null
	_round_number = 0
	_resolve_count = 0
	_removed_count = 0
	_outcome = Outcome.IN_PROGRESS
	_warned_unimplemented_rules = false
	_hold_remaining = 0.0

	match_started.emit(_participants.size())
	if _mirror:
		return

	if active.open_with_race and _participants.size() > 1:
		start_race()
	else:
		# No race: the seat the rules name opens the match in the tower on turn
		# one, which is what a single-round harness wants, what the game did
		# before the race existed, and what the Match tab's race skip selects.
		# Everything after this line is the round the race would have armed.
		take_seat(_participants[_opening_seat()])
		start_round()


## Alias for [method start_match], for callers that read better this way.
func restart() -> void:
	start_match()


## Which participant opens a match that skips the race, clamped into the roster.
##
## [member MatchRules.opening_seat_index] is a saved player preference by the
## time it gets here, and a preference outlives the [member MatchRules.prisoner_count]
## it was chosen against. Naming a seat this match does not have therefore hands
## the tower to the nearest one that exists rather than crashing on the index --
## a player who dropped the prisoner count still gets a game.
func _opening_seat() -> int:
	return clampi(get_rules().opening_seat_index, 0, _participants.size() - 1)


## Arm the opening race: no shooter, every participant on the ring.
##
## The rifle is stowed on this node rather than left in anyone's hands, because
## "no shooter" has to be true of the world and not merely of a variable.
func start_race() -> void:
	_phase = Phase.RACE
	_outcome = Outcome.IN_PROGRESS
	_removed_count = 0
	# The race has no shooter, so it has no siege to run down.
	_hold_remaining = 0.0
	_seat = null
	_stow_rifle()
	# The race has no guard, so it has no finisher either: first past the post
	# takes the tower, unchanged, and there is nobody up there to hunt.
	_disarm_finisher()
	# "No shooter" has to be true of the BRAINS as well as of the rifle, and
	# true immediately rather than two frames from now, or the racer who held
	# the tower last shoots the field while everybody runs.
	_silence_all_tower_brains()
	# And true of what the PRISONERS can read, on the same tick and for the same
	# reason: _seat is already null above, so this empties the group. A racer who
	# still believed the last round's holder was up there would play the cover
	# game through a race nobody is shooting in. See [constant GUARD_GROUP].
	_publish_the_seat()

	_settle_frames = SETTLE_PHYSICS_FRAMES
	var racers: Array[MatchParticipant] = _participants.duplicate()
	_place_runners(racers)
	race_started.emit()


## Arm a round with the current seat holder in the tower.
##
## A restart is a real restart: every runner is put back on the start pad with a
## fresh lap tracker, converted runners come back, and the rifle is forced ready.
## Runner progress never carries across a seat change -- that is the design, and
## this is where it is enforced.
##
## With no seat granted yet (a match whose race is still running, or a harness
## that skipped [method start_match]), the first participant takes the tower, so
## a caller who just wants a round gets one.
func start_round() -> void:
	if _participants.is_empty():
		push_error("MatchController cannot arm a round with no participants.")
		return
	if _seat == null:
		take_seat(_participants[0])

	_phase = Phase.ROUND
	_round_number += 1
	_outcome = Outcome.IN_PROGRESS
	_removed_count = 0
	_warned_unimplemented_rules = false
	# The siege clock is armed with the round and from the rules in force now,
	# which is what makes a seat change start a fresh hold rather than hand the
	# incoming shooter the outgoing one's leftovers. Zero under every other win
	# condition, and [method _tick_hold] reads the condition before the clock.
	_hold_remaining = maxf(get_rules().hold_duration_seconds, 0.0)
	# Whatever the last round's finisher was doing, it is over: the rifle comes
	# back here and the hunt ends before any body is placed.
	_disarm_finisher()
	# A round is armed on the rules in force now, and the ghost tuning is one of
	# them. Cleared rather than re-resolved, so the walk is paid for only if a
	# prisoner is actually shot.
	_ghost_profile = null

	# Every body about to be placed goes inert until the physics server has
	# caught up. See [method _hold_body]: without it, a seat change drags both
	# the incoming and the outgoing shooter out of the arena. The tower brains
	# go down with them and the seat holder's is brought back up by
	# [method _arm_tower_brain] on the tick they are woken -- a brain aiming
	# from a stand the physics server has not caught up with yet is aiming from
	# the wrong place.
	_silence_all_tower_brains()
	# Announced with the arming and not left until the bodies wake, so that no
	# tick of the new round reads the LAST round's holder as the guard. See
	# [constant GUARD_GROUP]; [method _arm_tower_brain] says it again on the wake
	# because that is where a seat can also change.
	_publish_the_seat()
	_settle_frames = SETTLE_PHYSICS_FRAMES
	var runners: Array[MatchParticipant] = []
	for participant: MatchParticipant in _participants:
		if participant != _seat:
			runners.append(participant)
	_place_runners(runners)
	_place_in_tower(_seat)

	round_started.emit()


## Give the tower to [param participant], counting the turn and retuning the
## reload for it.
##
## Public because the seat is the match's central act and a harness must be able
## to drive it directly. It does NOT arm a round; call [method start_round]
## after, which is what the arrival path does.
func take_seat(participant: MatchParticipant) -> void:
	if participant == null:
		return
	var previous: MatchParticipant = _seat
	if previous != null and previous != participant:
		previous.is_shooter = false
		if get_rules().turn_count_resets_on_seat_loss:
			# The other reading of "consecutive": losing the seat wipes the
			# count and the terminator with it. Off by default; see the rule.
			previous.turns_in_tower = 0

	_seat = participant
	participant.is_shooter = true
	participant.is_running = false
	participant.turns_in_tower += 1

	_attach_rifle(participant)
	_apply_turn_reload(participant)
	seat_changed.emit(participant, participant.turns_in_tower)


# --- Readable state -----------------------------------------------------------

func get_phase() -> Phase:
	return _phase


func get_phase_name() -> String:
	return String(Phase.keys()[_phase])


func get_outcome() -> Outcome:
	return _outcome


func get_outcome_name() -> String:
	return String(Outcome.keys()[_outcome])


func is_resolved() -> bool:
	return _outcome != Outcome.IN_PROGRESS


func is_match_over() -> bool:
	return _phase == Phase.MATCH_OVER


## Everyone in the match, in match order. A copy: callers may iterate freely.
func get_participants() -> Array[MatchParticipant]:
	return _participants.duplicate()


## Who holds the tower, or null during the opening race.
func get_seat_participant() -> MatchParticipant:
	return _seat


## The seat holder's own turn count, including the turn they are on. 0 when
## nobody holds the seat.
func get_seat_turns() -> int:
	return _seat.turns_in_tower if _seat != null else 0


## Who won the match, or null while it is still being played.
func get_match_winner() -> MatchParticipant:
	return _winner


## The reload the tower is running on right now, in seconds.
func get_current_reload_seconds() -> float:
	return rifle.reload_seconds if rifle != null else 0.0


## Rounds armed this match. The opening race is not a round, so this is 0 while
## it runs.
func get_round_number() -> int:
	return _round_number


func get_runners_remaining() -> int:
	var remaining: int = 0
	for participant: MatchParticipant in _participants:
		if participant.is_running:
			remaining += 1
	return remaining


## How many runners the current round or race was armed with. A round has
## [member MatchRules.prisoner_count] of them; the race has every participant.
func get_runners_total() -> int:
	return _round_runner_count


## How many rounds this controller has ever resolved.
func get_resolve_count() -> int:
	return _resolve_count


## Runners out of the current round or race: converted by the rifle, or fallen.
##
## Also the shutout tally: under
## [constant MatchRules.ShooterWinCondition.SHUTOUT_COUNT] the round is won when
## this reaches [member MatchRules.shutout_count].
func get_runners_removed() -> int:
	return _removed_count


## Seconds of siege left in this round, or 0.0 when no siege is running.
##
## Non-zero only under [constant MatchRules.ShooterWinCondition.HOLD_DURATION]
## and only inside a live round. A readout, exactly as
## [method get_runners_removed] is: nothing branches on it but the clock in
## [method _tick_hold] itself.
func get_hold_remaining_seconds() -> float:
	if _phase != Phase.ROUND:
		return 0.0
	if get_rules().shooter_win_condition != MatchRules.ShooterWinCondition.HOLD_DURATION:
		return 0.0
	return maxf(_hold_remaining, 0.0)


## The participants who are ghosts right now, as a copy.
func get_ghost_participants() -> Array[MatchParticipant]:
	var ghosts: Array[MatchParticipant] = []
	for participant: MatchParticipant in _participants:
		if participant.is_ghost:
			ghosts.append(participant)
	return ghosts


## How many participants are ghosts right now.
func get_ghosts_remaining() -> int:
	var count: int = 0
	for participant: MatchParticipant in _participants:
		if participant.is_ghost:
			count += 1
	return count


## Why a participant is watching rather than playing right now.
##
## The match already knew all of this; until there was something to show the
## player it simply never had to say it. Read every frame by [FxSpectatorView]
## and by [MatchDeathScreen], both of which are strictly additive and neither of
## which the match knows exists.
enum Spectating {
	## Playing: on the ring, in the tower, or racing.
	NONE,
	## Dead and on the clock. [method get_respawn_hold_remaining] says how long
	## is left, and the body is frozen at the spot it died.
	RESPAWNING,
	## Out, with no clock: a racer who fell during the opening race and is out
	## for the rest of it, or a converted prisoner in a ghostless round. Both
	## end when the next round is armed, and neither can be counted down to.
	ELIMINATED,
}


## The human's participant, or null in a match with no human in it.
##
## [method _build_participants] puts the human at index 0 when there is one, but
## that is an implementation detail of the start line and not a promise; this
## asks.
func get_human_participant() -> MatchParticipant:
	if _local_index >= 0 and _local_index < _participants.size():
		var local: MatchParticipant = _participants[_local_index]
		if local.is_human():
			return local
	for participant: MatchParticipant in _participants:
		if participant.is_human():
			return participant
	return null


## Hand in seat-indexed bodies from the net layer. [param mirror] makes this a client.
func configure_net(
	bodies: Array[PlayerController],
	kinds: Array[MatchParticipant.Kind],
	names: PackedStringArray,
	local_index: int,
	mirror: bool,
) -> void:
	_net_bodies = bodies.duplicate()
	_net_kinds = kinds.duplicate()
	_net_names = names.duplicate()
	_local_index = local_index
	_mirror = mirror
	get_rules().prisoner_count = maxi(bodies.size() - 1, 1)


func is_networked() -> bool:
	return not _net_bodies.is_empty()


func is_mirror() -> bool:
	return _mirror


## Keep the bodies the last arming placed held for [param seconds] more.
func hold_start_for(seconds: float) -> void:
	if _mirror or seconds <= 0.0:
		return
	var frames: int = int(ceilf(seconds * float(Engine.physics_ticks_per_second)))
	_settle_frames = maxi(_settle_frames, frames)


# --- Applying the server's decisions on a client -------------------------------

func net_start_match() -> void:
	_applying = true
	start_match()
	_applying = false


func net_start_race() -> void:
	_applying = true
	start_race()
	_applying = false


func net_start_round(seat_index: int, round_number: int) -> void:
	var seat: MatchParticipant = _participant_at(seat_index)
	if seat == null:
		return
	_applying = true
	_round_number = round_number - 1
	take_seat(seat)
	start_round()
	_applying = false


func net_convert(index: int) -> void:
	_applying = true
	convert_participant(_participant_at(index))
	_applying = false


func net_race_out(index: int) -> void:
	var participant: MatchParticipant = _participant_at(index)
	if participant == null or _phase != Phase.RACE:
		return
	_applying = true
	_fall_out_of_race(participant)
	_applying = false


func net_resolve(outcome: Outcome) -> void:
	_applying = true
	_resolve(outcome)
	_applying = false


func net_win(index: int) -> void:
	var participant: MatchParticipant = _participant_at(index)
	if participant == null:
		return
	_applying = true
	_win_match(participant)
	_applying = false


func net_ghost_respawn(index: int) -> void:
	var participant: MatchParticipant = _participant_at(index)
	if participant == null or not participant.is_ghost:
		return
	_applying = true
	_finish_respawn(participant)
	_applying = false


func net_ghost_caught(ghost_index: int, caught_index: int) -> void:
	var ghost: MatchParticipant = _participant_at(ghost_index)
	var caught: MatchParticipant = _participant_at(caught_index)
	if ghost == null or caught == null or not ghost.is_ghost or not caught.is_running:
		return
	_applying = true
	_swap_with_ghost(ghost, caught)
	_applying = false


## A human seat became a bot's mid-match: the body stays, the brain takes over.
func net_seat_to_bot(index: int) -> void:
	var participant: MatchParticipant = _participant_at(index)
	if participant == null or not participant.is_human() or participant.body == null:
		return
	participant.kind = MatchParticipant.Kind.AI
	participant.brain = _find_brain(participant.body)
	if _mirror or participant.brain == null:
		return
	if participant.is_running:
		_start_running_in_place(participant, participant.tracker.get_travelled_arc(), null)
	elif participant.is_ghost:
		participant.brain.rules = get_rules()
		participant.brain.begin_chase(RUNNER_GROUP)
	elif participant.is_shooter:
		_arm_tower_brain()


func _participant_at(index: int) -> MatchParticipant:
	if index < 0 or index >= _participants.size():
		return null
	return _participants[index]


## True when a client is asked to decide something only the server may.
func _refuses_local_decision() -> bool:
	return _mirror and not _applying


## What [param participant] is watching, and why.
##
## Deliberately a QUERY and not a signal. A view that polls this is correct on
## the frame it is switched on, correct after a restart, and correct for a
## participant it was pointed at halfway through a hold -- where a view built on
## an edge would have missed the edge and shown the wrong thing until the next
## death.
func get_spectating_state(participant: MatchParticipant) -> Spectating:
	if participant == null or is_match_over():
		return Spectating.NONE
	if participant.respawn_hold_remaining > 0.0:
		return Spectating.RESPAWNING
	if participant.is_shooter or participant.is_running or participant.is_ghost:
		return Spectating.NONE
	match _phase:
		Phase.RACE:
			# The author's ruling: a racer who falls is out for the rest of the
			# race. That can be a long time, and it is the case that most needs
			# something to look at. See [method _fall_out_of_race].
			return Spectating.ELIMINATED
		Phase.ROUND:
			# A converted prisoner with no ghost to become -- ghost_behaviour
			# NONE. Under the shipped rules this arm is unreachable, because a
			# conversion always makes a ghost.
			return Spectating.ELIMINATED
		_:
			return Spectating.NONE


## True while [param participant] has no body to play and should be shown
## something else.
func is_spectating(participant: MatchParticipant) -> bool:
	return get_spectating_state(participant) != Spectating.NONE


## Seconds [param participant] still has to wait before the match puts them back
## on the start line, or 0.0 when nothing is waiting.
##
## The readout for a HUD counting a respawn down, and the seam a test asserts the
## three seconds against without reaching into a participant. See
## [member GhostProfile.respawn_delay_seconds].
func get_respawn_hold_remaining(participant: MatchParticipant) -> float:
	if participant == null:
		return 0.0
	return participant.respawn_hold_remaining


## True while [param participant]'s body is frozen where it died, waiting to be
## put back. It is on no collision layer, is not being stepped, and is skipped by
## [method _tick_ghosts] for as long as this is true.
func is_awaiting_respawn(participant: MatchParticipant) -> bool:
	return get_respawn_hold_remaining(participant) > 0.0


## Ghost swaps this controller has performed since the match started.
## The prisoner hunting the guard, or null when nobody has reached the end.
func get_finisher() -> MatchParticipant:
	return _finisher


## The finisher's rifle, or null until one has been armed this match.
func get_finisher_rifle() -> Rifle:
	return _finisher_rifle


## Hit points [param participant] has left. See [member MatchParticipant.health].
func get_health(participant: MatchParticipant) -> int:
	return 0 if participant == null else participant.health


func get_catch_count() -> int:
	return _catch_count


## The colour [param participant]'s body is wearing right now, straight off the
## mesh's live [member GeometryInstance3D.material_override]. A test seam --
## the same value a camera parked at 35-60 m would read off the deck -- rather
## than a duplicate of the palette lookup, so it is honest about a ghost's
## alpha and about the guard's temporary repaint, neither of which is in
## [member MatchParticipant.home_body_material].
func get_body_color(participant: MatchParticipant) -> Color:
	if participant == null:
		return Color.BLACK
	var mesh: MeshInstance3D = _body_mesh_of(participant.body)
	var material: StandardMaterial3D = (
		mesh.material_override as StandardMaterial3D if mesh != null else null
	)
	if material == null:
		return Color.BLACK
	return material.albedo_color


## The participants still running, as a copy.
func get_live_participants() -> Array[MatchParticipant]:
	var live: Array[MatchParticipant] = []
	for participant: MatchParticipant in _participants:
		if participant.is_running:
			live.append(participant)
	return live


## The AI brains still running, as a copy.
##
## A convenience for callers that think in [RingRunner]s. It cannot see the
## human, who has no brain and never will; [method get_live_participants] is the
## complete list.
func get_live_runners() -> Array[RingRunner]:
	var live: Array[RingRunner] = []
	for participant: MatchParticipant in _participants:
		if participant.is_running and participant.brain != null:
			live.append(participant.brain)
	return live


## Rifle hits [param participant] has left, or 0 if they are not running.
func get_lives_left(participant: MatchParticipant) -> int:
	if participant == null or not participant.is_running:
		return 0
	return participant.lives


## Which participant, if any, a physics collider belongs to.
##
## Walks up from the collider through its ancestors and asks the match-start map
## at each step, so a body with its hitbox on a child node, or reparented under a
## squad node, resolves without a change here. Returns null for the deck, the
## cover, the tower or anything else in the world.
func resolve_participant(collider: Node3D) -> MatchParticipant:
	var node: Node = collider
	while node != null:
		var id: int = node.get_instance_id()
		if _participant_by_body_id.has(id):
			return _participant_by_body_id[id]
		node = node.get_parent()
	return null


## The AI brain a collider belongs to, or null. The human's body resolves to null
## here because the human has no brain; use [method resolve_participant].
func resolve_runner(collider: Node3D) -> RingRunner:
	var participant: MatchParticipant = resolve_participant(collider)
	return participant.brain if participant != null else null


# --- Conversion ---------------------------------------------------------------

## Take a runner out of the round. Returns true if they were in it.
##
## Refuses once the round is resolved, which is half of the once-only guarantee:
## a shot fired in the same frame as an arrival cannot turn a lost seat into a
## won round.
##
## What "out of the round" MEANS is [member MatchRules.ghost_behaviour]'s to
## decide, and it is the only thing that branches here: parked out of the world,
## or turned into a ghost. Either way the participant stops running, the count
## of runners falls by one, and the shooter's win condition is checked -- which
## is what keeps a ghost round winnable on exactly the terms a ghostless one is.
func convert_participant(participant: MatchParticipant) -> bool:
	if participant == null or is_resolved() or _phase != Phase.ROUND:
		return false
	if _refuses_local_decision():
		return false
	if not participant.is_running:
		return false

	participant.is_running = false
	participant.lives = 0
	var ability: RunnerPower = RunnerPower.of(participant.body)
	if ability != null:
		ability.cancel()
	if get_rules().has_ghosts():
		_make_ghost(participant)
	else:
		_park_body(participant)
	_removed_count += 1

	participant_converted.emit(participant)
	runner_removed.emit(get_runners_remaining())
	if not _mirror:
		_check_shooter_win()
	return true


## [method convert_participant], for callers holding a [RingRunner].
func remove_runner(runner: RingRunner) -> bool:
	return convert_participant(_participant_of_brain(runner))


## Land one rifle hit on [param participant], spending a life. Returns true if
## that hit converted them.
##
## The one place [member MatchRules.prisoner_lives] is spent. At the default of 1
## this is one hit, one conversion, and above 1 the runner keeps going with no
## hit reaction and no recovery, because neither is designed.
func apply_hit(participant: MatchParticipant) -> bool:
	if participant == null or is_resolved() or not participant.is_running:
		return false
	if _refuses_local_decision():
		return false
	var ability: RunnerPower = RunnerPower.of(participant.body)
	if ability != null and ability.is_hit_immune():
		return false
	if participant.is_finisher:
		# Hit points, not lives: the ghost/park path below is not reached until
		# MatchRules.finisher_health of the guard's shots have landed.
		participant.health -= 1
		if participant.health > 0:
			return false
		_disarm_finisher()
		return convert_participant(participant)
	participant.lives -= 1
	if participant.lives > 0:
		return false
	return convert_participant(participant)


## Land one finisher shot on the guard, spending a hit point. Returns true if
## that shot took the tower.
##
## The mirror of [method apply_hit] and the finisher's half of the new ending:
## at the shipped [member MatchRules.guard_health] of 1 the first shot on the
## guard resolves the round for the finisher exactly as reaching the portal used
## to, through the same [method _score_and_restart].
func apply_guard_hit(guard: MatchParticipant) -> bool:
	if guard == null or is_resolved() or _phase != Phase.ROUND:
		return false
	if not guard.is_shooter or _refuses_local_decision():
		return false
	guard.health -= 1
	if guard.health > 0:
		return false
	var scorer: MatchParticipant = _finisher
	_disarm_finisher()
	if scorer == null:
		return false
	_score_and_restart(scorer)
	return true


## Rule on [param participant] having fallen out of the arena. Returns true if
## the match did something about it.
##
## The one place a fall becomes a match event, so that the volume under the
## arena -- see [KillVolume] -- knows about geometry and nothing about roles.
## What happens depends entirely on what the faller was doing, and none of the
## three answers is a new rule:
##
## [codeblock]
## a prisoner -> convert_participant(): the rifle's own ending
## a ghost    -> put back on the start line: where a ghost is made
## the guard  -> put back on the tower: where the seat holder stands
## a racer    -> OUT, and if that was the last one, the match restarts
## [/codeblock]
##
## A prisoner goes through [method convert_participant] and no other door, which
## is what keeps a fall and a shot the same death: under the shipped rules both
## produce a ghost, on the start line, with the same grace, and under
## [constant MatchRules.GhostBehaviour.NONE] both park the body. A fall is a
## conversion rather than a hit because it is not survivable -- spending one of
## [member MatchRules.prisoner_lives] would leave a prisoner with lives to spare
## standing at the bottom of the pit, falling forever.
##
## A ghost is already out of the round; there is nothing left to take off it, and
## it has exactly one placement, so it gets that one. An [Area3D] whose mask
## includes [constant GHOST_HAZARD_LAYER] -- [KillVolume] and [TrapVolume] both
## do -- sees a ghost exactly as it sees a living prisoner, so this arm is
## reached in the ordinary course of play, not only in principle.
##
## [b]The guard is put back, unharmed, and that is a decision awaiting a
## ruling.[/b] The tower stands on an 8 m platform with a 12 m drop around it, so
## the seat holder can walk off it, and a guard at the bottom of the pit is a
## round that cannot be won and cannot be lost. Killing them would need a rule
## nobody has written -- what an empty tower means, who gets it, whether the
## round survives it -- and inventing one here would make it permanent by
## accident. Putting them back on their own spawn invents nothing.
##
## [b]A faller during the OPENING RACE is out[/b], by the author's ruling:
## [i]"if a racer falls durring the opening race they can be out. if everyone
## goes out, the match restarts."[/i] Not respawned, and not turned into a ghost
## -- there is no shooter during the race, so a conversion would mean nothing.
## See [method _fall_out_of_race] for what OUT is made of and
## [method _restart_after_an_empty_race] for the other half of the ruling.
func handle_fall(participant: MatchParticipant) -> bool:
	if participant == null or is_resolved() or _refuses_local_decision():
		return false
	match _phase:
		Phase.RACE:
			return _fall_out_of_race(participant)
		Phase.ROUND:
			if participant.is_shooter:
				return _return_seat_holder_to_tower()
			if participant.is_ghost:
				_place_ghost_at_start(participant)
				return true
			return convert_participant(participant)
		_:
			return false


## Take a racer out of the opening race for good.
##
## OUT is [method _park_body] and nothing else: the body is hidden, stripped of
## its collision, stopped, taken out of [constant RUNNER_GROUP] and buried in the
## pen, its brain is silenced and its lap tracker is stopped. That is the same
## ending a converted prisoner gets under
## [constant MatchRules.GhostBehaviour.NONE], reached through the same method,
## which is what keeps a fall from becoming a second death path.
##
## What it costs them, concretely: [member MatchParticipant.is_running] goes
## false, so they are gone from [method get_live_participants] and from
## [method get_runners_remaining], and [method _on_participant_arrived] refuses
## them -- a racer who is out cannot cross the line and cannot take the tower.
## They are out of the RACE and not out of the MATCH: they are still in
## [method get_participants], and [method start_round] puts every non-seat
## participant back on the track, so the racer who fell runs the first round as a
## prisoner like everybody else.
##
## No ghost is made whatever [member MatchRules.ghost_behaviour] says. A ghost
## exists to chase prisoners for a shooter, and the race has no shooter and no
## prisoners; a ghost armed here would be a chaser hunting the field of a race it
## was just removed from.
func _fall_out_of_race(participant: MatchParticipant) -> bool:
	if participant.body == null or not participant.is_running:
		return false

	participant.is_running = false
	participant.lives = 0
	_park_body(participant)
	_removed_count += 1

	participant_converted.emit(participant)
	runner_removed.emit(get_runners_remaining())
	_restart_after_an_empty_race()
	return true


## The second half of the ruling: an empty race restarts the match.
##
## [i]"if everyone goes out, the match restarts."[/i] With every racer in the pen
## there is nobody left to reach the end, so the race can never be scored, the
## tower can never be granted and the match would sit in
## [constant Phase.RACE] forever. [method start_match] is the restart -- the same
## one the pause menu offers -- so the field comes back on the line, the lap
## counters are fresh and the race is armed again from the top.
##
## Restarting from inside a fall is safe for the same reason
## [method _on_participant_arrived] may arm a round from inside a lap: the
## roster is unchanged, so [method _build_participants] is a no-op and no body is
## freed or instanced here. Everything else is placement, which is what
## [constant SETTLE_PHYSICS_FRAMES] exists for.
func _restart_after_an_empty_race() -> void:
	if _mirror or _phase != Phase.RACE or get_runners_remaining() > 0:
		return
	restart()


## Stand the seat holder back up on the tower without touching the round.
##
## No turn is counted, no round resolves, the reload is not retuned and the rifle
## does not move -- it is already in their hands. This is a recovery from a fall,
## not a seat change, and it is deliberately the ONLY thing about the match that
## changes.
##
## It arms the round's settle, so the placement is woken by
## [method _wake_bodies] exactly as the one [method start_round] makes is. A bot
## guard therefore comes back scanning rather than still tracking whatever it saw
## on the way down, which is the honest state for a body that has just been
## somewhere else.
func _return_seat_holder_to_tower() -> bool:
	if _seat == null or _seat.body == null or not _geometry_ready:
		return false
	_place_in_tower(_seat)
	_settle_frames = SETTLE_PHYSICS_FRAMES
	return true


# --- The shove ----------------------------------------------------------------

## Spend every shove cooldown, and resolve the taps living prisoners made.
##
## Run here, over participants, for the reason [method _tick_ghosts] is: the
## human shoves on exactly a bot's terms, and the authority is the only machine
## that decides it. The level is latched rather than trusted to be one tick
## wide, so a held button is still one shove.
func _tick_shoves(delta: float) -> void:
	for participant: MatchParticipant in _participants:
		if participant.shove_cooldown_remaining > 0.0:
			participant.shove_cooldown_remaining = maxf(
				participant.shove_cooldown_remaining - delta, 0.0
			)
		if not participant.is_running or participant.body == null:
			continue
		var pressed: bool = participant.body.get_intent().shove_pressed
		if pressed and not participant.shove_was_pressed:
			apply_shove(participant)
		participant.shove_was_pressed = pressed


## Throw the living prisoner in front of [param shover]. Returns the one
## launched, or null when there is nobody there, no charge, or no right to ask.
func apply_shove(shover: MatchParticipant) -> MatchParticipant:
	if shover == null or is_resolved() or _refuses_local_decision():
		return null
	if _phase != Phase.RACE and _phase != Phase.ROUND:
		return null
	if not shover.is_running or shover.body == null:
		return null
	if shover.shove_cooldown_remaining > 0.0:
		return null

	var forward: Vector3 = -shover.body.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 1e-6:
		return null
	forward = forward.normalized()

	var match_rules: MatchRules = get_rules()
	var victim: MatchParticipant = _shovable_from(shover, forward, match_rules.shove_range_metres)
	if victim == null:
		return null

	shover.shove_cooldown_remaining = maxf(match_rules.shove_cooldown_seconds, 0.0)
	# The same call a boost pad makes: the launch replaces the victim's velocity
	# on their next tick, so a shove is worth the same whatever they were doing.
	victim.body.launch(forward * match_rules.shove_impulse + Vector3.UP * match_rules.shove_up_impulse)
	if shove_camera_kick != null and shover.is_human():
		shove_camera_kick.strike(forward, SHOVE_KICK_SCALE)
	AudioDirector.post_event_at(AudioEvents.HAZARD_BOOST_PAD, victim.body.global_position)
	participant_shoved.emit(shover, victim)
	return victim


## The nearest living prisoner within [param radius] metres of [param shover]
## and inside its facing cone, or null. Ghosts and the guard are not there.
func _shovable_from(
	shover: MatchParticipant, forward: Vector3, radius: float
) -> MatchParticipant:
	var here: Vector3 = shover.body.global_position
	var best: MatchParticipant = null
	var best_distance: float = 0.0
	for other: MatchParticipant in _participants:
		if other == shover or not other.is_running or other.body == null:
			continue
		var offset: Vector3 = other.body.global_position - here
		offset.y = 0.0
		var distance: float = offset.length()
		if distance > radius or distance < 1e-3:
			continue
		if forward.dot(offset / distance) < SHOVE_FACING_DOT:
			continue
		if best == null or distance < best_distance:
			best = other
			best_distance = distance
	return best


# --- Ghosts -------------------------------------------------------------------

## Tick every ghost's grace clock and rule on any catch that has happened.
##
## Run from [method _physics_process] rather than from the brains, once per tick,
## over participants rather than over nodes -- so the human's ghost catches on
## exactly the terms a bot's does and there is one place a catch can happen.
##
## The check is a distance, and only a distance. It is deliberately not a shape
## query, an area or a signal off the body: those would make the catch a
## consequence of the collision solver, and a ghost is a solid capsule that
## cannot occupy a prisoner's space, so contact is not something it can reliably
## achieve. See [member GhostProfile.catch_radius_metres].
func _tick_ghosts(delta: float) -> void:
	if _phase != Phase.ROUND or is_resolved() or not get_rules().has_ghosts():
		return

	var profile: GhostProfile = get_ghost_profile()
	for ghost: MatchParticipant in _participants:
		if not ghost.is_ghost:
			continue
		if ghost.respawn_hold_remaining > 0.0 or ghost.ghost_settle_frames > 0:
			# NOT IN THE WORLD YET, by either of the two ways a ghost can not be:
			# held where it died and not yet moved, or moved and waiting out the
			# placement settle that gives it back its collision. In both it is on
			# no collision layer and is not being stepped.
			#
			# It may not catch, and -- the part that is easy to get wrong by one
			# tick -- its catch grace does not run either. The grace exists to
			# stop a swap oscillating in the moment AFTER a ghost lands, so a
			# grace spent while the body was still frozen is grace spent on
			# nothing, and a freshly landed ghost would be catchable sooner than
			# the number in [member GhostProfile.catch_grace_seconds] says. The
			# clock starts when the body does.
			continue
		if ghost.ghost_grace_remaining > 0.0:
			ghost.ghost_grace_remaining = maxf(ghost.ghost_grace_remaining - delta, 0.0)
			continue
		var caught: MatchParticipant = _catchable_from(ghost, profile.catch_radius_metres)
		if caught != null:
			_swap_with_ghost(ghost, caught)


## The nearest living prisoner within [param radius] metres of [param ghost],
## horizontally, or null.
##
## Horizontal because the deck is flat and the tower is not: a ghost standing
## under the stand is not about to catch the shooter, and the shooter is not a
## candidate anyway -- only [member MatchParticipant.is_running] participants are.
func _catchable_from(ghost: MatchParticipant, radius: float) -> MatchParticipant:
	if ghost.body == null:
		return null
	var here: Vector3 = ghost.body.global_position
	var best: MatchParticipant = null
	var best_distance: float = 0.0
	for other: MatchParticipant in _participants:
		if not other.is_running or other.body == null:
			continue
		var distance: float = _flat_distance(here, other.body.global_position)
		if distance > radius:
			continue
		if best == null or distance < best_distance:
			best = other
			best_distance = distance
	return best


## The catch: [param ghost] takes [param caught]'s spot, and they trade roles.
##
## [b]Their spot, literally.[/b] The incoming prisoner stands where the caught
## one stood and inherits the arc they had run, so a catch changes WHO is alive
## and nothing else. It is the plain reading of the canon sentence, and there is
## no switch on it: the alternative would have to be justified by something the
## prisoners jointly own, and they own nothing jointly -- there is no side for a
## catch to cost. The prisoner who was caught does not stay beside them: they are
## a ghost now, and a ghost starts at the start. See [method _make_ghost].
##
## [b]It is a swap and it conserves the count.[/b] One living prisoner goes in
## and one comes out, so [method get_runners_remaining] is the same on both
## sides of this call and the shooter's win condition cannot be moved by it. It
## is not a conversion, so [signal runner_removed] does not fire and
## [member _removed_count] does not move -- those mean "the rifle took somebody
## out", and nothing here involves the rifle.
##
## The order matters. The caught prisoner is made a ghost FIRST, which takes
## them out of [constant RUNNER_GROUP], before the incoming prisoner joins it --
## so no tick ever sees both of them as legitimate targets, and the guard cannot
## be handed a fourth prisoner for one frame.
func _swap_with_ghost(ghost: MatchParticipant, caught: MatchParticipant) -> void:
	# Read before the tracker is stopped: the caught prisoner's spot is what the
	# ghost is taking, and how far round the ring they had got IS the spot.
	var carried_arc: float = caught.tracker.get_travelled_arc()
	var source: MatchLapTracker = caught.tracker

	caught.is_running = false
	_make_ghost(caught)

	_unmake_ghost(ghost)
	_start_running_in_place(ghost, carried_arc, source)

	_catch_count += 1
	ghost_caught.emit(ghost, caught)


## Turn [param participant] into a ghost, and put them back on the start line.
##
## Not a park: the body stays in the world. What changes is what it IS -- out of
## the target group, off the physics layer the rifle's ray reads, onto the ghost
## colour, faster, driven by the chase instead of the lap -- and WHERE it is,
## which is the start, on the author's ruling: [i]"a ghost shold be placed back
## at the start"[/i]. A ghost no longer picks up from where the prisoner fell.
##
## Called on the tick the rifle finishes a prisoner and on the tick a ghost
## catches one. Both routes set the grace clock. It survives the move to the
## start line rather than being made redundant by it: the grace is what stops a
## swap oscillating, and it has to hold whether or not the placement happened.
func _make_ghost(participant: MatchParticipant) -> void:
	var profile: GhostProfile = get_ghost_profile()
	var body: PlayerController = participant.body
	if body == null:
		return

	participant.is_ghost = true
	participant.is_shooter = false
	participant.is_running = false
	participant.ghost_grace_remaining = maxf(profile.catch_grace_seconds, 0.0)
	body.died.emit()

	participant.tracker.stop()
	_silence_brain(participant)
	_silence_tower_brain(participant)

	body.remove_from_group(RUNNER_GROUP)
	body.visible = true
	body.speed_scale = maxf(profile.speed_multiplier, 0.0)
	_tint_body(participant, _ghost_material_for(participant))
	# Inert NOW; moved to the start line after
	# [member GhostProfile.respawn_delay_seconds]; collision and motion back
	# two physics frames after that. See [method _place_ghost_at_start].
	_place_ghost_at_start(participant)

	# Armed immediately even when a respawn hold is running, and harmlessly so:
	# a brain writes nothing but a [MoveIntent] through [BotIntentSource], and a
	# held body's [method Node._physics_process] is off, so nobody reads it. The
	# alternative -- deferring the chase to the end of the hold -- would leave
	# [method RingRunner.is_chasing] lying about a participant who is
	# unambiguously a ghost for those three seconds.
	if participant.brain != null and not _mirror:
		participant.brain.rules = get_rules()
		participant.brain.begin_chase(RUNNER_GROUP)

	runner_ghosted.emit(participant)


## Put a freshly made ghost down on the start line, in its own place on it.
##
## [b]Which place is the whole of the problem.[/b] The field is dealt sideways
## across the width of the track at one start angle -- see
## [method _start_place_for] -- so "the start" is a LINE with several bodies
## standing on it, and dropping a ghost on the marker itself would drop it inside
## whoever is there. So a ghost is dealt out of the same line by the same
## function, against the FULL roster rather than against the round's runners.
##
## That one difference is what makes the placement safe, and it is arithmetic
## rather than luck. A round deals [code]N-1[/code] runners and this deals a
## ghost out of [code]N[/code], so every ghost lane falls exactly half a spacing
## from every runner lane, whatever N is; two ghosts are a full spacing apart
## because no two participants share an index; and a participant's lane is the
## same one every time they are ghosted, so a ghost made twice in a round lands
## twice in the same clear place. The opening race is the one arming that deals
## out of N as well, and no ghost can exist during it.
##
## The move itself goes through [method _hold_body] like every other placement in
## this file. It has to: this is a kinematic body being sent up to a lap's worth
## of ring with a live capsule, which is precisely the trap that method
## documents. It is woken by [method _wake_settled_ghosts].
##
## [b]The placement WAITS.[/b] [member GhostProfile.respawn_delay_seconds] --
## three seconds on the shipped profile -- is served here, and it is the one
## place it is served, so every route into this method gets it: shot, trapped,
## fallen, or a ghost a hazard is returning. The body is made inert FIRST and
## moved AFTERWARDS, which is the whole of what makes the wait safe. See
## [method _tick_respawn_holds] for the clock and [method _finish_respawn] for
## the placement it eventually performs.
func _place_ghost_at_start(participant: MatchParticipant) -> void:
	var body: PlayerController = participant.body
	if body == null or not _geometry_ready:
		return
	_snapshot_death(participant)
	# Inert before anything else, and before the delay is even read. Whatever
	# killed this body, it stops being a thing in the world on THIS tick and not
	# three seconds from now: off every layer and mask, velocity zeroed, not
	# stepped. See [method _hold_body] -- it also clears any respawn hold, so the
	# assignment below is the only one in force.
	_hold_body(participant)
	if _mirror:
		# The server says when the respawn lands; see net_ghost_respawn.
		return
	var delay: float = maxf(get_ghost_profile().respawn_delay_seconds, 0.0)
	if delay > 0.0:
		participant.respawn_hold_remaining = delay
		return
	_finish_respawn(participant)


## Run the respawn clock down, and place whoever it has finished with.
##
## A seconds clock rather than a frame count, unlike
## [member MatchParticipant.ghost_settle_frames], because this is a DESIGN
## duration a designer typed into a resource and it must be three seconds at any
## framerate, where the settle is a physics-server handshake and is correctly
## counted in the server's own frames.
##
## Held bodies are not stepped, so nothing about them can change while this
## runs; the only thing that can end a hold early is another placement, which
## clears it through [method _hold_body].
func _tick_respawn_holds(delta: float) -> void:
	for participant: MatchParticipant in _participants:
		if participant.respawn_hold_remaining <= 0.0:
			continue
		participant.respawn_hold_remaining = maxf(
			participant.respawn_hold_remaining - delta, 0.0
		)
		if participant.respawn_hold_remaining <= 0.0:
			_finish_respawn(participant)


## Put a held body down on the start line, in its own place on it, and arm its
## settle. The second half of [method _place_ghost_at_start], separated only by
## the wait.
func _finish_respawn(participant: MatchParticipant) -> void:
	participant.respawn_hold_remaining = 0.0
	var body: PlayerController = participant.body
	if body == null or not _geometry_ready:
		return
	# Re-asserted rather than assumed. The hold above already did this and
	# nothing steps a held body, but this is the one method that MOVES a live
	# capsule the length of the ring and [method _hold_body] is what makes that
	# legal; a future caller that reaches it by another route must not be able to
	# skip it. It is idempotent, and it clears the hold flag this method has
	# already cleared.
	_hold_body(participant)
	var place: Vector3 = _start_place_for(participant.index, _participants.size())
	body.global_position = place
	# Facing down the track, exactly as a prisoner placed on the line is. A human
	# ghost dropped facing the wall would spend its first second turning round,
	# and a ghost's first second is the one in which the field is still nearby.
	body.rotation = Vector3(0.0, _heading_of(_track_tangent(_angle_of(place))), 0.0)
	participant.ghost_settle_frames = SETTLE_PHYSICS_FRAMES
	ghost_respawned.emit(participant)


## Give ghosts placed on the start line their collision and their motion back,
## once the physics server has caught up with where they were put.
##
## [b]Ghosts settle on their own clock, and that is deliberate.[/b] Re-arming
## [member _settle_frames] would be the obvious reuse and it would be wrong: that
## counter ends in [method _wake_bodies], which ends in
## [method _arm_tower_brain], which reconfigures the shooter in the tower -- so a
## bot guard would forget the prisoner it was tracking every time it hit one. A
## ghost is made in the MIDDLE of a round; nothing about the round is restarting.
func _wake_settled_ghosts() -> void:
	for participant: MatchParticipant in _participants:
		if participant.ghost_settle_frames <= 0:
			continue
		participant.ghost_settle_frames -= 1
		if participant.ghost_settle_frames > 0:
			continue
		if participant.is_ghost:
			_wake_ghost(participant)
		elif participant.is_shooter or participant.is_running:
			# The ghost stopped being one inside its own settle -- a catch, on
			# the tick after it was made. Somebody has to give the body back its
			# collision or it plays the rest of the round as a spectator, and
			# whoever put it back in the round did not hold it.
			_wake_body(participant)


## The collision a GHOST wakes up with, which is not the collision it was
## authored with.
##
## [constant GHOST_HAZARD_LAYER] rather than the body's own layer, so the
## rifle's ray -- and every other query run on [member WeaponProfile.hit_mask]
## -- passes through exactly as if the ghost were on no layer at all, while a
## hazard [Area3D] whose mask has been widened to include that one bit
## ([KillVolume], [TrapVolume]) still finds it. [member GhostProfile.shootable]
## is the switch that measures the other answer: a shootable ghost goes back on
## its own home layer, where the rifle -- and every hazard, which already
## watches that layer -- can find it. The MASK is the authored one either way,
## so a ghost still stands on the deck and still cannot walk through the ring's
## cover: it is unhittable, not incorporeal.
func _wake_ghost(participant: MatchParticipant) -> void:
	var body: PlayerController = participant.body
	if body == null:
		return
	var profile: GhostProfile = get_ghost_profile()
	body.collision_layer = (
		participant.home_collision_layer if profile.shootable else GHOST_HAZARD_LAYER
	)
	body.collision_mask = participant.home_collision_mask
	body.set_physics_process(not _mirror)


## Take the ghost back off [param participant]: their colour, their pace, their
## collision and their brain. Idempotent, and silent on anybody who is not one.
func _unmake_ghost(participant: MatchParticipant) -> void:
	if not participant.is_ghost:
		return
	participant.is_ghost = false
	participant.ghost_grace_remaining = 0.0
	# Somebody has put this participant back in the round; a respawn that fired
	# afterwards would drag a living prisoner to the start line.
	participant.respawn_hold_remaining = 0.0

	var body: PlayerController = participant.body
	if body != null:
		body.speed_scale = 1.0
		body.collision_layer = participant.home_collision_layer
		body.collision_mask = participant.home_collision_mask
		_tint_body(participant, participant.home_body_material)

	if participant.brain != null:
		participant.brain.end_chase()


## Put [param participant] back in the round WITHOUT moving their body, holding
## [param travelled_arc] radians of lap.
##
## The other half of the catch. [method _place_on_track] cannot be used: it writes
## a position, and on a woken body that is motion rather than a teleport -- see
## [method _hold_body] for what a 300 m one costs. A prisoner who has just taken
## somebody's spot is standing in it already.
func _start_running_in_place(
	participant: MatchParticipant, travelled_arc: float, source: MatchLapTracker
) -> void:
	var active: MatchRules = get_rules()
	var body: PlayerController = participant.body
	if body == null:
		return

	participant.is_shooter = false
	participant.is_running = true
	participant.lives = maxi(active.prisoner_lives, 1)

	body.add_to_group(RUNNER_GROUP)
	# One route, so the carried arc and the arc it is now measured against are
	# the same level's, which is what makes adopt_progress mean anything. The
	# LEVEL is read off the outgoing tracker for the same reason the arc is: a
	# prisoner caught on the top deck is replaced on the top deck, and a swap
	# that reset them to the bottom lap would hand the ghost a spot nobody had.
	var carried_level: int = 0 if source == null else source.get_level()
	participant.tracker.begin(body, _centre, _route, active.lap_arrival_tolerance)
	if source != null:
		participant.tracker.adopt_progress(source)

	if participant.brain != null:
		participant.brain.profile.track_radius = _route.lane_radius(carried_level)
		participant.brain.rules = active
		if not _mirror:
			participant.brain.resume(
				_centre, _start_point, _end_point, travelled_arc, _route, carried_level
			)


## The palette this match paints its bodies from: [member palette] when the
## scene names one, the shipped default otherwise, loaded once. Never null --
## a [RunnerPalette] constructed from nothing still has [member
## RunnerPalette.guard_color] to fall back on.
func get_runner_palette() -> RunnerPalette:
	if palette != null:
		return palette
	if _default_palette == null:
		_default_palette = load(DEFAULT_PALETTE_PATH) as RunnerPalette
		if _default_palette == null:
			push_warning(
				"MatchController cannot load %s; every body will wear the guard colour."
				% DEFAULT_PALETTE_PATH
			)
			_default_palette = RunnerPalette.new()
	return _default_palette


## [param participant]'s own distinct, stable colour for the whole match. Built
## once from [method RunnerPalette.color_for_index] and cached by index -- an
## index always names the same participant for the life of a match, so the
## same body is never repainted a different shade of itself.
func _runner_material_for(participant: MatchParticipant) -> Material:
	if _runner_material_cache.has(participant.index):
		return _runner_material_cache[participant.index]
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = get_runner_palette().color_for_index(participant.index)
	_runner_material_cache[participant.index] = material
	return material


## [param participant]'s SAME colour, translucent -- a ghost reads as who it is
## and as a ghost in the same glance rather than one flat colour meaning both.
## [member RunnerPalette.ghost_alpha] is the "slightly" in "slightly
## translucent": alpha comes off the colour; the colour itself never does.
func _ghost_material_for(participant: MatchParticipant) -> Material:
	if _ghost_material_cache.has(participant.index):
		return _ghost_material_cache[participant.index]
	var runner_palette: RunnerPalette = get_runner_palette()
	var runner_color: Color = runner_palette.color_for_index(participant.index)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(runner_color.r, runner_color.g, runner_color.b, runner_palette.ghost_alpha)
	_ghost_material_cache[participant.index] = material
	return material


## The one material the tower seat wears, distinct from every runner colour so
## the guard reads as a role rather than as whichever runner happens to be
## sitting there. Built once: this does not vary by participant.
func _guard_material() -> Material:
	if _guard_material_cache != null:
		return _guard_material_cache
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = get_runner_palette().guard_color
	_guard_material_cache = material
	return material


## Give [param participant] its own colour for the whole match and paint it on
## now, before anything else has touched the body. Sets [member
## MatchParticipant.home_body_material] directly rather than letting [method
## _tint_body] lazily capture whatever the scene shipped with -- the assigned
## colour IS this participant's home look from here on, not the flat material
## [code]scenes/bot/ring_runner.tscn[/code] or [code]scenes/player/player.tscn[/code]
## happens to author.
func _assign_runner_color(participant: MatchParticipant) -> void:
	var material: Material = _runner_material_for(participant)
	participant.home_body_material = material
	participant.home_material_read = true
	_tint_body(participant, material)


## Paint [param participant]'s body mesh, remembering the authored material the
## first time so it can be put back exactly.
func _tint_body(participant: MatchParticipant, material: Material) -> void:
	var mesh: MeshInstance3D = _body_mesh_of(participant.body)
	if mesh == null:
		return
	if not participant.home_material_read:
		participant.home_body_material = mesh.material_override
		participant.home_material_read = true
	mesh.material_override = material


## The one mesh that IS [param body] on screen, and so the one whose colour says
## living or ghost.
##
## The humanoid under [constant BODY_AVATAR_NAME] when there is one, which is
## every body the shipped scenes build; the greybox capsule otherwise. Asking the
## avatar for its mesh rather than walking the subtree is deliberate -- the
## imported model is a Skeleton3D with a skinned child, and a search for "the
## MeshInstance3D" would start returning the wrong one the day anything else is
## hung on a prisoner.
func _body_mesh_of(body: PlayerController) -> MeshInstance3D:
	if body == null:
		return null
	var avatar: PrisonerAvatar = body.get_node_or_null(NodePath(BODY_AVATAR_NAME)) as PrisonerAvatar
	if avatar != null and avatar.mesh != null:
		return avatar.mesh
	return body.get_node_or_null(NodePath(BODY_MESH_NAME)) as MeshInstance3D


# --- Participants -------------------------------------------------------------

## Build the roster, once per match, reusing bodies where the size has not
## changed.
##
## A match has [method MatchRules.get_participant_count] players: one in the
## tower and [member MatchRules.prisoner_count] on the ring. The human, when
## there is one, takes the first slot; AI bodies fill the rest.
func _build_participants() -> void:
	var wanted: int = get_rules().get_participant_count()
	if _participants.size() == wanted:
		return

	for participant: MatchParticipant in _participants:
		# The human's body belongs to the scene and is only borrowed.
		if not participant.is_human() and participant.body != null:
			participant.body.queue_free()
	_participants.clear()
	_participant_by_body_id.clear()

	if not _net_bodies.is_empty():
		for slot: int in _net_bodies.size():
			_participants.append(_make_net_participant(slot))
	elif player != null:
		_participants.append(_make_human_participant())

	while _participants.size() < wanted:
		var slot: int = _participants.size()
		var ai: MatchParticipant = _make_ai_participant(slot)
		if ai == null:
			break
		_participants.append(ai)

	for index: int in _participants.size():
		var participant: MatchParticipant = _participants[index]
		participant.index = index
		if participant.body != null:
			_participant_by_body_id[participant.body.get_instance_id()] = participant
			_assign_runner_color(participant)


## One seat's participant from the net roster: a human wears no brain, a bot keeps its own.
func _make_net_participant(slot: int) -> MatchParticipant:
	var body: PlayerController = _net_bodies[slot]
	var participant: MatchParticipant = MatchParticipant.new()
	participant.kind = _net_kinds[slot]
	participant.display_name = _net_names[slot]
	participant.body = body
	participant.home_collision_layer = body.collision_layer
	participant.home_collision_mask = body.collision_mask
	participant.tracker = _attach_tracker(body)
	participant.tracker.lap_finished.connect(_on_participant_arrived.bind(participant))
	if participant.kind == MatchParticipant.Kind.AI:
		participant.brain = _find_brain(body)
		if participant.brain != null:
			participant.brain.profile = participant.brain.profile.duplicate() as BotProfile
	return participant


func _make_human_participant() -> MatchParticipant:
	var participant: MatchParticipant = MatchParticipant.new()
	participant.kind = MatchParticipant.Kind.HUMAN
	participant.display_name = MatchRules.get_participant_name(0, true)
	participant.body = player
	participant.home_collision_layer = player.collision_layer
	participant.home_collision_mask = player.collision_mask
	participant.tracker = _attach_tracker(player)
	participant.tracker.lap_finished.connect(_on_participant_arrived.bind(participant))
	return participant


## Instance one AI body, place it, and wire a brain and a tracker to it.
##
## Where it is put down here is only a holding position; the round decides where
## it actually starts. Putting it somewhere at all is the point: a body added to
## the tree is registered by the physics server at the position it holds AT THAT
## MOMENT, and a body added at the scene default sits at the origin -- which is
## the tower spawn. Three capsules materialising inside the shooter threw them
## across the arena once already, so each one is dealt its own place on the start
## line before it ever enters the tree.
func _make_ai_participant(slot: int) -> MatchParticipant:
	var body: PlayerController = runner_scene.instantiate() as PlayerController
	if body == null:
		push_error("MatchController's runner scene does not have a PlayerController at its root.")
		return null

	body.name = "Runner_%d" % slot
	body.position = runner_container.to_local(_start_place_for(slot, get_rules().get_participant_count()))
	runner_container.add_child(body)

	var brain: RingRunner = _find_brain(body)
	if brain == null:
		push_error("MatchController's runner scene has no RingRunner brain; the runner will not run.")
		body.queue_free()
		return null

	# Duplicate the profile: the scene's is a shared resource, and writing the
	# match's track radius into it would retune every runner ever spawned from
	# it, including the ones already running.
	var profile: BotProfile = brain.profile.duplicate() as BotProfile
	brain.profile = profile

	var participant: MatchParticipant = MatchParticipant.new()
	participant.kind = MatchParticipant.Kind.AI
	# Named through the rules so the seat the Match tab offered and the seat the
	# HUD reports are the same string. See [method MatchRules.get_participant_name].
	participant.display_name = MatchRules.get_participant_name(slot, player != null)
	participant.body = body
	participant.brain = brain
	participant.home_collision_layer = body.collision_layer
	participant.home_collision_mask = body.collision_mask
	participant.tracker = _attach_tracker(body)
	participant.tracker.lap_finished.connect(_on_participant_arrived.bind(participant))
	return participant


func _attach_tracker(body: PlayerController) -> MatchLapTracker:
	var existing: MatchLapTracker = _find_tracker(body)
	if existing != null:
		return existing
	var tracker: MatchLapTracker = MatchLapTracker.new()
	tracker.name = "LapTracker"
	body.add_child(tracker)
	return tracker


func _find_tracker(body: Node) -> MatchLapTracker:
	for child: Node in body.get_children():
		var tracker: MatchLapTracker = child as MatchLapTracker
		if tracker != null:
			return tracker
	return null


## The brain, found by type rather than by path.
func _find_brain(body: Node) -> RingRunner:
	for child: Node in body.get_children():
		var brain: RingRunner = child as RingRunner
		if brain != null:
			return brain
	return null


func _participant_of_brain(brain: RingRunner) -> MatchParticipant:
	if brain == null:
		return null
	for participant: MatchParticipant in _participants:
		if participant.brain == brain:
			return participant
	return null


# --- Placement ----------------------------------------------------------------

func _cache_geometry() -> void:
	var start_marker: Marker3D = arena.get_node_or_null(start_marker_path) as Marker3D
	var end_marker: Marker3D = arena.get_node_or_null(end_marker_path) as Marker3D
	var spawn_marker: Marker3D = arena.get_node_or_null(spawn_marker_path) as Marker3D
	if start_marker == null or end_marker == null or spawn_marker == null:
		push_error("MatchController cannot find the PrisonerStart/PrisonerEnd/TowerSpawn markers.")
		_geometry_ready = false
		return
	_centre = arena.global_position
	_start_point = start_marker.global_position
	_end_point = end_marker.global_position
	_tower_point = spawn_marker.global_position
	_cache_route()
	_geometry_ready = true


## Find the arena's [RingRoute], or build the flat one that stands in for it.
##
## The fallback is not a degraded mode. A map with one deck IS a route with one
## level on it, and building it here rather than branching at every call site is
## what keeps [MatchLapTracker], [RingRunner] and [MatchHUD] free of any opinion
## about how many decks an arena has.
func _cache_route() -> void:
	if _route_is_ours and _route != null and is_instance_valid(_route):
		_route.queue_free()
	_route = null
	_route_is_ours = false

	var authored: RingRoute = arena.get_node_or_null(route_path) as RingRoute
	if authored != null and authored.level_count() > 0:
		_route = authored
		var problems: PackedStringArray = authored.validate()
		if not problems.is_empty():
			# Reported, not refused: a route with a complaint against it still
			# runs, and a match that would not start because a level's inner
			# radius was a centimetre out would be worse than the complaint.
			push_warning(
				"MatchController: the arena's route is not sound -- %s" % ", ".join(problems)
			)
		return

	_route = RingRoute.flat(
		get_rules().track_radius, _centre, _start_point, _end_point
	)
	_route_is_ours = true
	add_child(_route)


## The route the match is being run on. Null before the geometry is cached.
##
## Exposed because the HUD counts metres off it, the round card frames the arena
## off it, and a test asks it what the field is actually being scored against
## rather than reconstructing the arithmetic.
func get_route() -> RingRoute:
	return _route


## Put every participant in [param runners] on the start line and start them
## running.
##
## [b]One track.[/b] Everybody runs the same circle, from the same line, to the
## same marker. There is nothing here to equalise and no handicap to compensate
## for: the opening race is first past the post and a round is a chase, and both
## are scored off the same arc against the same finish.
##
## The one thing that separates two bodies is where they stand ON the line. Two
## capsules cannot start in the same cubic metre -- the depenetration solver
## resolves that by throwing both of them out of the arena, which this project
## has already paid for twice -- so the field is dealt out sideways across the
## width of the track and closes up again the moment it is moving. See
## [method _start_place_for].
func _place_runners(runners: Array[MatchParticipant]) -> void:
	_round_runner_count = runners.size()
	if not _geometry_ready:
		return

	for index: int in runners.size():
		_place_on_track(runners[index], _start_place_for(index, runners.size()))

	_order_the_scoring(runners)


## Decide, before anybody runs, who takes the tower if two of them arrive on the
## same physics tick.
##
## [b]Why this is needed at all[/b]
##
## Arrival is resolved the instant it happens -- [signal MatchLapTracker.lap_finished]
## goes straight to [method _on_participant_arrived], which grants the seat and
## restarts the round -- so within one tick the first tracker to be processed
## takes everything and the rest are re-armed before they can report. That is
## sound: an arrival IS immediate, and a match must not sit on a decision for a
## frame. It does mean the tie would otherwise be settled by whatever order the
## physics server happens to hold the trackers in, which is a decision nobody
## made and which can change when an unrelated node is added to the scene.
##
## A dead heat is the normal case, not a freak one: everybody runs one track
## from one line, so a field of identical bots crosses together to the tick. So
## the order is set here, deliberately, in one place, and it is match order --
## the lowest [member MatchParticipant.index] takes the seat, which is what the
## match already did without saying so. Nothing about the race changes: a racer
## who arrives on an EARLIER tick is scored on that tick and wins outright. Only
## a dead heat reads this.
func _order_the_scoring(runners: Array[MatchParticipant]) -> void:
	for rank: int in runners.size():
		var participant: MatchParticipant = runners[rank]
		if participant.tracker != null:
			participant.tracker.process_physics_priority = TRACKER_PRIORITY_BASE + rank


## Put one participant down at [param start_point] and start them running the
## track.
##
## [param start_point] is the exact world position the body is placed at, which
## is its own place on the start line rather than the arena's marker. Everything
## that then judges the run -- [MatchLapTracker] for the score and [RingRunner]
## for the brain's own stopping point -- is given the same start and the same
## arena end marker, so a prisoner is scored against the line their brain is
## running at and there is no second opinion about where their run ends. Both
## read only the ANGLES, and the lateral offset does not change an angle.
func _place_on_track(participant: MatchParticipant, start_point: Vector3) -> void:
	var active: MatchRules = get_rules()

	participant.is_shooter = false
	participant.is_running = true
	participant.lives = maxi(active.prisoner_lives, 1)
	participant.is_finisher = false
	participant.health = maxi(active.prisoner_lives, 1)

	var body: PlayerController = participant.body
	body.is_guard = false
	# A round restart brings every ghost back as a living prisoner: the colour,
	# the pace, the collision and the chase all come off BEFORE the placement, so
	# _hold_body has the authored layers to switch off and _wake_bodies has them
	# to put back.
	_unmake_ghost(participant)
	# Back to this participant's own colour. A no-op for a body _unmake_ghost
	# just repainted; load-bearing for the outgoing shooter, who was never a
	# ghost and is still wearing _guard_material() from _place_in_tower.
	_tint_body(participant, participant.home_body_material)
	_hold_body(participant)
	var ability: RunnerPower = RunnerPower.of(body)
	if ability != null:
		ability.arm(active, self)
	# A body on the track runs; it does not play the tower. The outgoing shooter
	# arrives here on every seat change with its tower brain still loaded.
	_silence_tower_brain(participant)
	if participant.brain != null and not _mirror:
		# The brain reads pace from the rules and geometry from its profile. The
		# split is the seam: "walk or sprint" is a rule of the round, "how hard
		# does it steer" is tuning of the brain. configure() places the body.
		participant.brain.profile.track_radius = _route.lane_radius(0)
		participant.brain.rules = active
		participant.brain.configure(_centre, start_point, _end_point, _route)
	else:
		body.global_position = start_point
		body.velocity = Vector3.ZERO
		# Face down the track. A human teleported to the start line facing the
		# outer wall would spend their first second turning round, and that
		# second is part of the race.
		body.rotation = Vector3(
			0.0, _heading_of(_track_tangent(_angle_of(start_point))), 0.0
		)

	body.add_to_group(RUNNER_GROUP)
	participant.tracker.begin(body, _centre, _route, active.lap_arrival_tolerance)


func _place_in_tower(participant: MatchParticipant) -> void:
	if participant == null:
		return
	participant.is_shooter = true
	participant.is_running = false
	participant.is_finisher = false
	participant.health = maxi(get_rules().guard_health, 1)

	var body: PlayerController = participant.body
	body.is_guard = true
	# A ghost can take the tower: they were a prisoner when the seat changed
	# hands, and the round restarts around them like anybody else.
	_unmake_ghost(participant)
	# The guard's own colour, distinct from every runner's -- see
	# RunnerPalette.guard_color -- so the seat reads as a role and not as
	# whichever runner happens to be sitting in it.
	_tint_body(participant, _guard_material())
	_hold_body(participant)
	body.global_position = _tower_point
	body.velocity = Vector3.ZERO
	# Out of the target group, which is the whole of "the tower cannot be shot":
	# an AI shooter's candidate list IS this group, so a seat holder left in it
	# would be a legitimate target for the next occupant -- and, but for
	# [TowerShooter]'s own self-check, for itself.
	body.remove_from_group(RUNNER_GROUP)
	participant.tracker.stop()
	# The lap brain goes down here; the tower brain comes up in
	# [method _arm_tower_brain] once the body has been woken.
	_silence_brain(participant)


## Make a body inert for the placement: visible, but solid to nothing and moving
## under its own power not at all. [method _wake_bodies] undoes it.
##
## [b]This is the spawn-ejection trap in its second and nastier form, and it cost
## an afternoon.[/b] The known form is a body ADDED to the tree at the origin:
## the physics server registers it where it was at that moment. The form that
## bites a MATCH is a body MOVED while another body stands on the point it is
## moving away from -- which is every seat change, because the incoming shooter
## is put exactly where the outgoing one is standing.
##
## Setting [member Node3D.global_position] on a [CharacterBody3D] is not a
## teleport as far as the physics server is concerned. The body is kinematic, so
## the server treats the change as MOTION from the transform it last flushed to
## the new one, and a kinematic body that moves CARRIES whatever is standing at
## the start of that motion. Measured, with the tower at the origin: the outgoing
## shooter is sent to the track, picks up the incoming shooter who has just been
## put on the tower, and deposits it 38 m away on top of itself; both then slide
## off the deck and out to the wall at r=59, gaining height the whole way, while
## the node graph insists the shooter is standing on the tower. Ordering the two
## placements the other way round does not help: only the last transform written
## in a frame is ever flushed, so the server sees the same swap either way.
##
## What does help is placing the body with nothing to collide with, and turning
## its collision back on once the server has flushed the new transform -- which
## is [constant SETTLE_PHYSICS_FRAMES] frames later. The position is correct
## IMMEDIATELY, so the HUD, a test and this file all read the truth; only the
## physics is deferred, and only by two frames.
func _hold_body(participant: MatchParticipant) -> void:
	var body: PlayerController = participant.body
	var ability: RunnerPower = RunnerPower.of(body)
	if ability != null:
		ability.cancel()
	body.visible = true
	body.velocity = Vector3.ZERO
	body.collision_layer = 0
	body.collision_mask = 0
	body.set_physics_process(false)
	# Whoever is holding the body now owns waking it. A ghost settle still
	# running would otherwise hand this body its GHOST collision back two frames
	# into a round that has just placed it as a prisoner.
	participant.ghost_settle_frames = 0
	# And a respawn hold still running would otherwise teleport this body to the
	# start line seconds into a round that has already put it somewhere else.
	# [method _place_ghost_at_start] and [method _finish_respawn] both call this
	# BEFORE they set their own clocks, so cancelling here is free for them and
	# correct for every other placement in the file.
	participant.respawn_hold_remaining = 0.0


## Give every placed body its collision and its motion back. Converted runners
## are left parked: they are out of the round and must stay unhittable.
func _wake_bodies() -> void:
	for participant: MatchParticipant in _participants:
		if not (participant.is_shooter or participant.is_running):
			continue
		_wake_body(participant)
	_arm_tower_brain()


## One body's authored collision and motion, back on.
func _wake_body(participant: MatchParticipant) -> void:
	var body: PlayerController = participant.body
	if body == null:
		return
	body.collision_layer = participant.home_collision_layer
	body.collision_mask = participant.home_collision_mask
	body.set_physics_process(not _mirror)


## Snapshot where [param participant]'s body is standing and which way it is
## facing, for [FxSpectatorView] to anchor its shot on.
##
## Read before [method _park_body] buries the body or [method
## _place_ghost_at_start] holds it -- both move or freeze the body afterwards,
## and the camera needs the spot it actually died at, not wherever the match
## puts it next.
func _snapshot_death(participant: MatchParticipant) -> void:
	var body: PlayerController = participant.body
	if body == null:
		return
	participant.death_position = body.global_position
	var forward: Vector3 = -body.global_transform.basis.z
	forward.y = 0.0
	participant.death_facing = (
		forward.normalized() if forward.length_squared() > 1e-6 else Vector3.FORWARD
	)


## Put a converted runner's body out of the world: hidden, uncollidable, stopped
## and buried. See [constant PEN_DEPTH_METRES].
func _park_body(participant: MatchParticipant) -> void:
	var body: PlayerController = participant.body
	_snapshot_death(participant)
	# A body being buried is not coming back to the start line.
	participant.respawn_hold_remaining = 0.0
	_unmake_ghost(participant)
	participant.tracker.stop()
	_silence_brain(participant)
	_silence_tower_brain(participant)
	body.velocity = Vector3.ZERO
	body.set_physics_process(false)
	body.remove_from_group(RUNNER_GROUP)
	body.visible = false
	body.collision_layer = 0
	body.collision_mask = 0
	body.global_position = _pen_point(participant.index)


## Where body number [param index] is put when it is out of the world. Distinct
## per participant, so two parked or vacated bodies never share a point.
func _pen_point(index: int) -> Vector3:
	return _centre + Vector3(
		float(index) * PEN_SPACING_METRES, PEN_DEPTH_METRES, 0.0
	)


## Stop a participant's lap-running brain and drop the controls it was holding.
## A shooter does not run laps, and neither does a converted runner.
func _silence_brain(participant: MatchParticipant) -> void:
	if participant.brain == null:
		return
	participant.brain.set_physics_process(false)
	if participant.brain.input != null:
		participant.brain.input.command.clear()


## Stop a ghost's chase and drop the controls it was holding. Silent on a
## participant who is not chasing, and on the human, who has no brain to stop --
## a human ghost stops because the body it drives has been stopped.
func _end_chase(participant: MatchParticipant) -> void:
	if participant.brain != null:
		participant.brain.end_chase()


# --- The tower's brain --------------------------------------------------------

## Put the right brain behind every body, now that the placement has settled.
##
## This is the seat change as the BODIES experience it. [method take_seat] moves
## the rifle and counts the turn; this decides who is actually driving.
##
## [b]Why it runs from [method _wake_bodies] and not from [method take_seat][/b]
##
## Two reasons, both measured rather than assumed. A placed body is inert for
## [constant SETTLE_PHYSICS_FRAMES] frames -- see [method _hold_body] -- so a
## brain started any earlier would be writing intent at a controller whose
## physics is switched off, and aiming from a stand the physics server has not
## flushed yet. And this is deliberately the LAST word on the subject: anything
## else that has attached a [TowerShooter] to one of these bodies is stood down
## here and, if it is on the seat holder, adopted rather than duplicated. Two
## shooters on one body do not take turns -- they both write a look rate into
## the same [MoveIntent] every tick, from two different aim errors, and the head
## shakes between them.
func _arm_tower_brain() -> void:
	_silence_all_tower_brains()
	# BEFORE the early return below, and that is the whole point of it: the
	# human's round takes that return, and the prisoners still have to be told
	# there is somebody up there. See [constant GUARD_GROUP].
	_publish_the_seat()
	if _mirror or _phase != Phase.ROUND or _seat == null or _seat.is_human():
		# The opening race has no shooter, and a human in the tower is driven by
		# the human. Either way every brain stays down: an AI that fought the
		# player for their own look axis would be the worst bug in the game.
		return

	var shooter: TowerShooter = _tower_brain_of(_seat)
	if shooter == null:
		return

	var body: PlayerController = _seat.body
	# Re-pointed on EVERY seat change, because every one of these moved. There
	# is one rifle and [method _attach_rifle] has just reparented it onto this
	# body's head and repointed its aim source at this body's eye; the camera
	# whose frustum decides what the bot can see and the optic that narrows it
	# are this body's too. A brain left pointing at the previous holder's head
	# would search the ring from a node standing on the track.
	shooter.rifle = rifle
	shooter.rules = get_rules()
	shooter.target_group = RUNNER_GROUP
	shooter.camera = body.get_node_or_null(^"Head/Camera") as Camera3D
	shooter.optic = body.get_node_or_null(^"Optic") as WeaponOptic
	# The profile is deliberately NOT reassigned here. [TowerShooter] draws its
	# aim RNG from the profile in _ready, so writing one now would retune the
	# shooter without re-drawing its seed -- a difficulty that is half the new
	# setting and half the old one, which is the worst of the three states. A
	# rule set that has genuinely changed is picked up by
	# [method _release_tower_brains] at the next [method start_match]. Leaving
	# it alone also means a brain somebody else built and tuned -- the headless
	# harness seeds its own -- is driven rather than quietly overridden.
	# Where the body ALREADY is, never where it ought to be. configure() writes
	# global_position, and on a woken body that is motion, not a teleport -- see
	# [method _hold_body] for what that costs. Passing the current position
	# makes the write a no-op the physics server has nothing to do with.
	shooter.configure(body.global_position, body.rotation.y)


## Stop a participant's tower brain and drop the controls it was holding.
##
## The mirror of [method _silence_brain]. Idempotent, and silent when the brain
## was not running: clearing a [MoveIntent] that a live [RingRunner] wrote this
## tick would cost that runner a tick of movement for no reason.
func _silence_tower_brain(participant: MatchParticipant) -> void:
	var shooter: TowerShooter = _find_tower_brain(participant)
	if shooter == null or not shooter.is_physics_processing():
		return
	shooter.set_physics_process(false)
	if shooter.input != null:
		shooter.input.command.clear()


func _silence_all_tower_brains() -> void:
	for participant: MatchParticipant in _participants:
		_silence_tower_brain(participant)


## Say who is in the tower, in the one place a prisoner can read it: put the seat
## holder's body in [constant GUARD_GROUP] and take everybody else out.
##
## Rebuilt rather than patched on the way past, because the states this has to be
## right in are the ones where a seat CHANGED -- the outgoing holder is still
## carrying yesterday's membership and there is no other tick on which to take it
## off them. It is called on every arming, so the walk is paid once a round.
##
## Empty during the opening race, and that is not an oversight: the race has no
## shooter, and [RunnerPerception] falling back to the baseline lap when it finds
## no guard is what keeps the race a race.
func _publish_the_seat() -> void:
	for participant: MatchParticipant in _participants:
		if participant.body != null and participant.body.is_in_group(GUARD_GROUP):
			participant.body.remove_from_group(GUARD_GROUP)
	if _phase != Phase.ROUND or _seat == null or _seat.body == null:
		return
	_seat.body.add_to_group(GUARD_GROUP)


## The tower brain already on [param participant]'s body, or null.
##
## Found by TYPE, exactly as [method _find_brain] finds the lap-running one, and
## then cached on the participant. Searching rather than trusting the cache the
## first time is what lets a brain this node did not build be ADOPTED instead of
## duplicated -- the headless harness has historically attached its own, and a
## body driven by two shooters is the failure described in
## [method _arm_tower_brain].
func _find_tower_brain(participant: MatchParticipant) -> TowerShooter:
	if participant == null:
		return null
	if participant.tower_brain != null and is_instance_valid(participant.tower_brain):
		return participant.tower_brain
	if participant.body == null:
		return null
	for child: Node in participant.body.get_children():
		var shooter: TowerShooter = child as TowerShooter
		if shooter != null:
			participant.tower_brain = shooter
			return shooter
	return null


## The brain that plays the tower for [param participant], built on first use.
##
## Built rather than instanced from [code]scenes/bot/tower_shooter.tscn[/code],
## because that scene is a whole BODY. The participant already has a body, a
## head, a camera and an optic -- the same ones it runs the ring with, which is
## the entire point of a seat that is a role -- so the only thing missing is the
## brain, and the brain is a bare [Node] with five references.
##
## Null for the human, who is driven from the keyboard, and null for any body
## whose intent does not come from a [BotIntentSource]: a [MoveIntent] written
## somewhere the controller never polls produces a shooter that looks wired and
## never turns.
func _tower_brain_of(participant: MatchParticipant) -> TowerShooter:
	if participant == null or participant.is_human() or participant.body == null:
		return null
	var existing: TowerShooter = _find_tower_brain(participant)
	if existing != null:
		return existing

	var body: PlayerController = participant.body
	var input: BotIntentSource = body.intent_source as BotIntentSource
	if input == null:
		push_error(
			"MatchController cannot give %s the tower: its intent_source is not a BotIntentSource."
			% participant.display_name
		)
		return null

	var profile: ShooterProfile = _shooter_profile_for(participant)
	if profile == null:
		return null

	var shooter: TowerShooter = TowerShooter.new()
	shooter.name = "TowerBrain"
	shooter.controller = body
	shooter.input = input
	shooter.rifle = rifle
	shooter.optic = body.get_node_or_null(^"Optic") as WeaponOptic
	shooter.camera = body.get_node_or_null(^"Head/Camera") as Camera3D
	shooter.rules = get_rules()
	# The match's own answer to "who is a legitimate target", so the bot's
	# candidate list is exactly the live runners and the match does not have to
	# maintain a second list that could disagree with the first.
	shooter.target_group = RUNNER_GROUP
	# Every reference is set BEFORE the node enters the tree, for two reasons:
	# TowerShooter._ready refuses to play and disables itself if any of the four
	# required ones is missing, and it seeds its aim RNG from the profile there.
	# A profile assigned afterwards retunes the shooter but cannot re-draw its
	# seed.
	shooter.profile = profile
	body.add_child(shooter)
	participant.tower_brain = shooter
	return shooter


## A private [ShooterProfile] for [param participant], chosen by the rules.
##
## This is where match DIFFICULTY is decided, and it is decided from
## [MatchRules] so that a headless sweep can vary it per match and per
## participant without touching a scene. See
## [member MatchRules.ai_shooter_profiles].
##
## The chosen resource is duplicated, never used directly:
## [member MatchRules.ai_shooter_aim_seed] is written into the COPY, and a sweep
## that wrote it into the .tres would hand every later match in the same process
## a shooter an earlier one had quietly retuned.
func _shooter_profile_for(participant: MatchParticipant) -> ShooterProfile:
	var active: MatchRules = get_rules()
	var chosen: ShooterProfile = active.get_ai_shooter_profile_for(participant.index)
	if chosen == null:
		chosen = load(DEFAULT_SHOOTER_PROFILE_PATH) as ShooterProfile
	if chosen == null:
		push_error(
			"MatchController cannot load %s and the rules name no ShooterProfile; %s will stand in the tower doing nothing."
			% [DEFAULT_SHOOTER_PROFILE_PATH, participant.display_name]
		)
		return null

	var copy: ShooterProfile = chosen.duplicate() as ShooterProfile
	var seed_value: int = active.get_ai_shooter_seed_for(participant.index)
	if seed_value != 0:
		copy.aim_random_seed = seed_value
	return copy


## Throw away the tower brains a previous match built, so the next one is played
## on the rules in force NOW.
##
## Difficulty is drawn once, when a brain is built: see the comment in
## [method _arm_tower_brain] for why a live brain cannot simply be handed a new
## [ShooterProfile]. Rebuilding is therefore the only way a swept [MatchRules]
## reaches a controller that has already played a match, and it costs one [Node]
## per AI participant per match.
##
## Removed from the tree as well as freed, so that a brain queued for deletion
## cannot still be found by [method _find_tower_brain] on the same frame.
func _release_tower_brains() -> void:
	for participant: MatchParticipant in _participants:
		var shooter: TowerShooter = _find_tower_brain(participant)
		participant.tower_brain = null
		if shooter == null:
			continue
		shooter.set_physics_process(false)
		var parent: Node = shooter.get_parent()
		if parent != null:
			parent.remove_child(shooter)
		shooter.queue_free()


# --- The rifle ----------------------------------------------------------------

## Move the rifle onto [param participant]'s head and point it at their eye.
##
## This is what "the seat is a role" means in practice: there is one rifle, and
## it belongs to whoever is in the tower. The human's trigger is switched off
## whenever the holder is not the human, so a bot in the tower cannot be fired by
## somebody else's mouse.
func _attach_rifle(participant: MatchParticipant) -> void:
	if rifle == null:
		return
	var body: PlayerController = participant.body
	var head: Node3D = body.head if body.head != null else body
	if rifle.get_parent() != head:
		var parent: Node = rifle.get_parent()
		if parent != null:
			parent.remove_child(rifle)
		head.add_child(rifle)
	rifle.transform = Transform3D.IDENTITY

	# The shot line is the eye's, so a bot aims the same rifle through the same
	# field with no camera of its own -- a head pivot is enough.
	var camera: Camera3D = head.get_node_or_null(^"Camera") as Camera3D
	rifle.aim_source = camera if camera != null else head
	rifle.shooter_body = body
	rifle.rules = get_rules()

	# Ads lives on the rifle, but the optic that drives it lives on whoever's
	# head the rifle just moved onto -- the same reason aim_source is rewired
	# above rather than wired once in the scene.
	var ads: RifleAds = rifle.get_node_or_null(^"Ads") as RifleAds
	if ads != null:
		ads.optic = body.get_node_or_null(^"Optic") as WeaponOptic

	_set_human_trigger(participant.is_human() and participant.index == _local_index and not _mirror)


## Take the rifle out of everyone's hands. The opening race has no shooter, and
## that has to be true of the world, not just of a variable.
func _stow_rifle() -> void:
	if rifle == null:
		return
	if rifle.get_parent() != self:
		var parent: Node = rifle.get_parent()
		if parent != null:
			parent.remove_child(rifle)
		add_child(rifle)
	rifle.aim_source = null
	rifle.shooter_body = null
	var ads: RifleAds = rifle.get_node_or_null(^"Ads") as RifleAds
	if ads != null:
		ads.optic = null
	_set_human_trigger(false)


func _set_human_trigger(active: bool) -> void:
	_set_trigger(rifle, active)


## Hand [param weapon]'s trigger to the mouse, or take it away.
func _set_trigger(weapon: Rifle, active: bool) -> void:
	if weapon == null:
		return
	var trigger: WeaponInput = _find_trigger(weapon)
	if trigger != null:
		trigger.set_active(active)


func _find_trigger(node: Node) -> WeaponInput:
	for child: Node in node.get_children():
		var trigger: WeaponInput = child as WeaponInput
		if trigger != null:
			return trigger
	return null


## Retune the rifle for the holder's turn count and force it ready.
##
## The escalation is the match's terminator. It is applied on the seat change
## rather than at round start so that a holder who wins a round and starts
## another gets the turn they have earned, and so the HUD's reload readout is
## correct the instant the tower changes hands.
func _apply_turn_reload(participant: MatchParticipant) -> void:
	if rifle == null:
		return
	var active: MatchRules = get_rules()
	rifle.rules = active
	var weapon_base: float = rifle.profile.base_reload_seconds if rifle.profile != null else 0.0
	var weapon_floor: float = rifle.profile.min_reload_seconds if rifle.profile != null else 0.0
	rifle.reload_seconds = active.get_reload_seconds_for_turn(
		participant.get_turn_index(), weapon_base, weapon_floor
	)
	rifle.tick(FORCE_READY_SECONDS)


# --- The finisher -------------------------------------------------------------

## Hand [param participant] a rifle instead of the tower.
##
## Everything else about them is unchanged: they stay [member
## MatchParticipant.is_running] and stay in [constant RUNNER_GROUP], so the guard
## may still shoot them and every count of the round still counts them. What they
## gain is a gun and [member MatchRules.finisher_health] hit points; what they
## lose is the portal win.
func _arm_the_finisher(participant: MatchParticipant) -> void:
	# One finisher at a time: there is one second rifle, and the round ends the
	# moment the hunt does. A later arrival stands at the portal unarmed.
	if participant == null or _finisher != null or _seat == null or _mirror:
		return
	var weapon: Rifle = _finisher_weapon()
	if weapon == null:
		# Nothing to arm them with: the round ends the way it used to rather
		# than leaving a finisher standing at a portal that does nothing.
		_score_and_restart(participant)
		return

	_finisher = participant
	participant.is_finisher = true
	participant.health = maxi(get_rules().finisher_health, 1)
	# They have arrived; a lap brain still steering would walk them off the end.
	_silence_brain(participant)
	_attach_finisher_rifle(participant, weapon)
	_hunt_the_guard(participant, weapon)


## The second rifle, built on first use and kept for the life of the match.
func _finisher_weapon() -> Rifle:
	if _finisher_rifle != null and is_instance_valid(_finisher_rifle):
		return _finisher_rifle
	var scene: PackedScene = load(FINISHER_RIFLE_SCENE_PATH) as PackedScene
	var weapon: Rifle = scene.instantiate() as Rifle if scene != null else null
	if weapon == null:
		push_error(
			"MatchController cannot load %s; the finisher will stand unarmed."
			% FINISHER_RIFLE_SCENE_PATH
		)
		return null
	weapon.name = "FinisherRifle"
	add_child(weapon)
	# The scene's own trigger is live from _ready, and this gun is nobody's yet.
	_set_trigger(weapon, false)
	weapon.target_hit.connect(_on_finisher_hit)
	_finisher_rifle = weapon
	return weapon


## Move the finisher's rifle onto their head and point it at their eye.
## [method _attach_rifle] for the tower's gun, with the same wiring.
func _attach_finisher_rifle(participant: MatchParticipant, weapon: Rifle) -> void:
	var body: PlayerController = participant.body
	var head: Node3D = body.head if body.head != null else body
	if weapon.get_parent() != head:
		var parent: Node = weapon.get_parent()
		if parent != null:
			parent.remove_child(weapon)
		head.add_child(weapon)
	weapon.transform = Transform3D.IDENTITY

	var camera: Camera3D = head.get_node_or_null(^"Camera") as Camera3D
	weapon.aim_source = camera if camera != null else head
	weapon.shooter_body = body
	weapon.rules = get_rules()
	var ads: RifleAds = weapon.get_node_or_null(^"Ads") as RifleAds
	if ads != null:
		ads.optic = body.get_node_or_null(^"Optic") as WeaponOptic
	weapon.tick(FORCE_READY_SECONDS)

	# The human's trigger, the same one the tower's rifle hands the mouse.
	_set_trigger(weapon, participant.is_human() and participant.index == _local_index and not _mirror)


## Point a bot finisher at the guard with the brain it plays the tower on.
##
## The same [TowerShooter] the participant would hold the seat with, re-pointed
## at [constant GUARD_GROUP] and at the finisher's own rifle -- which is exactly
## what [method _arm_tower_brain] does to it on a seat change, so a brain reused
## here is re-pointed rather than left carrying the hunt. The bot stands where it
## finished and shoots; it does not close the range.
func _hunt_the_guard(participant: MatchParticipant, weapon: Rifle) -> void:
	if participant.is_human() or _mirror:
		return
	var hunter: TowerShooter = _tower_brain_of(participant)
	if hunter == null:
		return
	var body: PlayerController = participant.body
	hunter.rifle = weapon
	hunter.rules = get_rules()
	hunter.target_group = GUARD_GROUP
	hunter.camera = body.get_node_or_null(^"Head/Camera") as Camera3D
	hunter.optic = body.get_node_or_null(^"Optic") as WeaponOptic
	# Where the body ALREADY is: configure() writes global_position, and on a
	# woken body that is motion rather than a teleport. See [method _hold_body].
	hunter.configure(body.global_position, body.rotation.y)


## End the hunt and take the second rifle back. Idempotent, and safe to call on a
## match that never armed a finisher.
func _disarm_finisher() -> void:
	if _finisher != null:
		_finisher.is_finisher = false
		_silence_tower_brain(_finisher)
		_finisher = null
	if _finisher_rifle == null or not is_instance_valid(_finisher_rifle):
		return
	_set_trigger(_finisher_rifle, false)
	if _finisher_rifle.get_parent() != self:
		var parent: Node = _finisher_rifle.get_parent()
		if parent != null:
			parent.remove_child(_finisher_rifle)
		add_child(_finisher_rifle)
	_finisher_rifle.aim_source = null
	_finisher_rifle.shooter_body = null
	var ads: RifleAds = _finisher_rifle.get_node_or_null(^"Ads") as RifleAds
	if ads != null:
		ads.optic = null


## A shot from the finisher's rifle landed. Only the guard is worth anything.
func _on_finisher_hit(collider: Node3D, _hit_position: Vector3, _hit_normal: Vector3) -> void:
	if _phase != Phase.ROUND or is_resolved() or _mirror:
		return
	var hit: MatchParticipant = resolve_participant(collider)
	if hit == null or not hit.is_shooter:
		RunnerPower.shatter(RunnerPower.decoy_of(collider))
		return
	apply_guard_hit(hit)


# --- Resolution ---------------------------------------------------------------

func _on_target_hit(collider: Node3D, _hit_position: Vector3, _hit_normal: Vector3) -> void:
	if _phase != Phase.ROUND or is_resolved() or _mirror:
		return
	var participant: MatchParticipant = resolve_participant(collider)
	if participant == null:
		# The world, or a hologram: a decoy shatters and converts nobody.
		RunnerPower.shatter(RunnerPower.decoy_of(collider))
		return
	apply_hit(participant)


## Somebody reached the end. What that is worth depends entirely on the phase:
## in the race it is the tower, in a round it is the tower AND the round, and it
## is never the match.
func _on_participant_arrived(
	_elapsed_seconds: float, _path_length: float, participant: MatchParticipant
) -> void:
	if participant == null or not participant.is_running or _mirror:
		return

	match _phase:
		Phase.RACE:
			# First past the post takes the seat and the race is over. Later
			# arrivals in the same frame find the phase already changed.
			take_seat(participant)
			start_round()
		Phase.ROUND:
			if is_resolved():
				return
			if get_rules().finisher_hunts_guard:
				# The end of the route is no longer the end of the round: the
				# prisoner is handed a rifle and has to kill the guard for it.
				_arm_the_finisher(participant)
				return
			match get_rules().runner_win_condition:
				MatchRules.RunnerWinCondition.FIRST_ARRIVAL:
					_score_and_restart(participant)
				MatchRules.RunnerWinCondition.ALL_ARRIVALS:
					# Every runner still in the round has to make it. The one
					# who completes the set takes the seat.
					if _all_running_have_finished():
						_score_and_restart(participant)
		_:
			return


## A runner scored: the round is over, the seat changes hands, and the round
## starts again from the beginning. The outgoing shooter is put on the track by
## [method start_round] like everybody else.
func _score_and_restart(scorer: MatchParticipant) -> void:
	_resolve(Outcome.LOSS)
	take_seat(scorer)
	start_round()


func _all_running_have_finished() -> bool:
	for participant: MatchParticipant in _participants:
		if participant.is_running and not participant.tracker.has_finished():
			return false
	return true


## Resolve a WIN if [member MatchRules.shooter_win_condition] has been met by a
## runner having just left the round.
##
## Called from [method convert_participant] and from nowhere else, so it answers
## the two EVENT-driven conditions. The third,
## [constant MatchRules.ShooterWinCondition.HOLD_DURATION], is a clock and is
## answered by [method _tick_hold]; it is named here with an empty arm rather
## than left to the default, because falling through to the default would print
## "not implemented" about a condition that is.
##
## No condition falls back on another. A member added to the enum later lands in
## the default arm, complains once per round, and produces a round the shooter
## cannot win -- which is the loud failure [MatchRules] asks for, and better than
## a sweep quietly measuring a different rule than the one it selected.
func _check_shooter_win() -> void:
	if is_resolved() or _mirror:
		return
	var active: MatchRules = get_rules()
	match active.shooter_win_condition:
		MatchRules.ShooterWinCondition.TOTAL_CONVERSION:
			if get_runners_remaining() == 0:
				_resolve(Outcome.WIN)
				_award_round_to_shooter()
		MatchRules.ShooterWinCondition.SHUTOUT_COUNT:
			# Removals of THIS round: _removed_count is re-zeroed by
			# [method start_round], so a shutout is never assembled out of the
			# leavings of the rounds before a seat change.
			#
			# An unset count is refused rather than read as "all of them". See
			# [member MatchRules.shutout_count]: guessing here would play total
			# conversion under another name.
			if active.shutout_count <= 0:
				_warn_unwinnable("shutout_count is unset")
				return
			if _removed_count >= active.shutout_count:
				_resolve(Outcome.WIN)
				_award_round_to_shooter()
		MatchRules.ShooterWinCondition.HOLD_DURATION:
			# Deliberately nothing. Clearing the ring is not a hold, and making
			# it one here would be total conversion wearing the siege's name.
			pass
		_:
			_warn_unwinnable(
				"shooter_win_condition %s is not implemented"
				% String(MatchRules.ShooterWinCondition.keys()[active.shooter_win_condition])
			)


## Run the siege clock down and resolve a WIN when it reaches zero.
##
## The one place [constant MatchRules.ShooterWinCondition.HOLD_DURATION] is
## decided. It ends the round through the same [method _resolve] and
## [method _award_round_to_shooter] every other win goes through, so a hold win
## counts a round, escalates a turn and ends a match on exactly the terms a
## conversion win does.
##
## What it does NOT do is test for an arrival. It does not have to: under
## [constant MatchRules.RunnerWinCondition.FIRST_ARRIVAL] an arrival has already
## resolved the round LOSS and restarted it with a fresh clock before this can
## fire, and under [constant MatchRules.RunnerWinCondition.ALL_ARRIVALS] a
## prisoner who reached the end without the rest of the field has not taken the
## tower and so has not broken the siege. Adding a separate arrival test would be
## inventing a third interaction between two rules that already compose.
func _tick_hold(delta: float) -> void:
	if _phase != Phase.ROUND or is_resolved():
		return
	var active: MatchRules = get_rules()
	if active.shooter_win_condition != MatchRules.ShooterWinCondition.HOLD_DURATION:
		return
	if active.hold_duration_seconds <= 0.0:
		# Unset, and refused for the same reason an unset shutout count is: a
		# hold of no seconds would be won on the tick the round armed, which is
		# not a siege, it is a bug that looks like one.
		_warn_unwinnable("hold_duration_seconds is unset")
		return
	if _hold_remaining <= 0.0:
		# Armed by a round that started before the rules named this condition.
		# Arm it now rather than winning instantly on a clock nobody set.
		_hold_remaining = active.hold_duration_seconds
		return
	_hold_remaining = maxf(_hold_remaining - delta, 0.0)
	if _hold_remaining > 0.0:
		return
	_resolve(Outcome.WIN)
	_award_round_to_shooter()


## Say once per round that these rules cannot be won from the tower.
##
## One line per round, not one per frame: [method _check_shooter_win] is called
## on every conversion and [method _tick_hold] on every physics tick, and the
## complaint is about the rule set rather than about the moment.
func _warn_unwinnable(reason: String) -> void:
	if _warned_unimplemented_rules:
		return
	_warned_unimplemented_rules = true
	push_warning("MatchController: %s; this round cannot be won from the tower." % reason)


## The shooter held the tower through a round. That, and only that, wins a match.
func _award_round_to_shooter() -> void:
	if _seat == null:
		return
	_seat.rounds_won += 1
	if _seat.rounds_won >= maxi(get_rules().rounds_to_win_match, 1):
		_win_match(_seat)
		return
	# More rounds to defend: the same player keeps the seat and begins another
	# turn in the tower, which is a turn like any other and earns its reduction.
	take_seat(_seat)
	start_round()


func _win_match(participant: MatchParticipant) -> void:
	_phase = Phase.MATCH_OVER
	_winner = participant
	_freeze_everyone()
	_set_human_trigger(false)
	match_won.emit(participant)


func _resolve(outcome: Outcome) -> void:
	if is_resolved():
		return
	_outcome = outcome
	_resolve_count += 1
	_freeze_runners()
	round_resolved.emit(_outcome)


## Stop the survivors dead the moment the round is decided.
##
## Not cosmetic: without it, the runners still on the ring after a seat change go
## on to finish their own laps a second later and score a seat change of their
## own. The guard in [method _resolve] would swallow those, but a frozen ring is
## the honest picture of a round that is over.
func _freeze_runners() -> void:
	for participant: MatchParticipant in _participants:
		if participant.is_running or participant.is_ghost:
			# A ghost is stopped with the runners, and for the same reason: a
			# chase that carried on past the resolution would catch somebody in a
			# round that is already over, and the guard in [method _tick_ghosts]
			# would swallow it -- but a ring still moving is not the honest
			# picture of a round that is decided.
			_silence_brain(participant)
			_end_chase(participant)
			participant.tracker.stop()
			# A respawn hold that outlived the round would drop its body on the
			# start line of a round that is already decided.
			participant.respawn_hold_remaining = 0.0
			participant.body.velocity = Vector3.ZERO


## Stop everything, including the tower. Only a won match does this.
func _freeze_everyone() -> void:
	# Cancel any pending wake, or the settle tick would put the bodies back on
	# their feet a frame after the match ended.
	_settle_frames = 0
	for participant: MatchParticipant in _participants:
		_silence_brain(participant)
		_silence_tower_brain(participant)
		_end_chase(participant)
		participant.tracker.stop()
		participant.respawn_hold_remaining = 0.0
		participant.body.velocity = Vector3.ZERO
		participant.body.set_physics_process(false)


# --- Ring geometry ------------------------------------------------------------

func _angle_of(point: Vector3) -> float:
	return atan2(point.z - _centre.z, point.x - _centre.x)


func _point_on_track(radius: float, angle: float) -> Vector3:
	return _centre + Vector3(cos(angle), 0.0, sin(angle)) * radius


func _track_tangent(angle: float) -> Vector3:
	return Vector3(-sin(angle), 0.0, cos(angle)) * RingRunner.TRAVEL_SIGN


## Where body number [param index] of a field of [param count] stands on the
## start line.
##
## Across the width of the track, never on a track of its own: every one of
## these is at the start marker's own angle and they differ only in how far out
## along that line they stand, so every body owes the same arc from the same
## angle to the same finish. Once they are moving they steer back to
## [member MatchRules.track_radius] and share the space.
##
## The spread is centred on the track, so the middle of the field is on it and
## adding a body widens the line symmetrically instead of pushing everybody
## outward towards the wall.
func _start_place_for(index: int, count: int) -> Vector3:
	var active: MatchRules = get_rules()
	var middle: float = float(maxi(count, 1) - 1) * 0.5
	var offset: float = (float(index) - middle) * active.start_line_spacing_metres
	# The FIRST level's lane, and its deck. Everybody starts at the bottom: the
	# levels above are somewhere a prisoner earns, not somewhere the match deals
	# them.
	var place: Vector3 = _point_on_track(
		_route.lane_radius(0) + offset, _angle_of(_start_point)
	)
	place.y = _route.deck_height(0)
	return place


## Body yaw, in radians, that points the controller's forward axis along
## [param direction]. Forward is -Z, hence the double negation.
func _heading_of(direction: Vector3) -> float:
	return atan2(-direction.x, -direction.z)


## Horizontal distance between two world points. The deck is flat and the tower
## is not: a ghost standing under the stand is not next to the shooter.
func _flat_distance(from: Vector3, to: Vector3) -> float:
	return Vector2(to.x - from.x, to.z - from.z).length()


# --- Air control --------------------------------------------------------------

## The [MovementProfile] every body in this match is running, built from
## [member MatchRules.air_control_id]. Null until a match has been armed.
##
## One object shared by the whole field, deliberately: the presets exist to be
## judged, and a preset felt against opponents that move differently is not the
## preset being felt.
var _air_control_profile: MovementProfile = null


## The profile the bodies in this match are running. Null before the first
## [method start_match]; the seam a test asserts the chosen preset by.
func get_air_control_profile() -> MovementProfile:
	return _air_control_profile


## Put the shipped air control on every body in the roster.
##
## [b]Where it comes from.[/b] [member MatchRules.air_control_id] is not written
## by anything any more -- there is no picker, see [AirControlCatalog] -- so it
## sits at its own default, [constant AirControlCatalog.DEFAULT_ID]. This node
## reads the rules, so this is where that default lands, exactly as
## [method _install_chosen_map] reads the map.
##
## [b]Why [method PlayerController.set_profile] and not an assignment.[/b] The
## walkable slope, the floor snap length and the [IntentSource]'s own copy are
## all read ONCE, at ready. Assigning [member PlayerController.profile] would
## leave a body obeying one profile's physics with another profile's slope, and
## it would look exactly like a physics bug.
##
## [b]Why the look settings are written into it.[/b]
## [method AirControlCatalog.profile_for] hands back a private duplicate of
## [code]scenes/player/default_movement_profile.tres[/code] -- it must, or a
## menu would retune the shipped game -- and mouse sensitivity and invert-Y live
## on that profile. [PauseMenu] writes them into the SHIPPED instance on every
## [signal SettingsStore.applied], which the bodies are no longer holding, so
## this node follows that signal and writes them into the profile they ARE
## holding. Without it the sensitivity slider would move nothing mid-match.
func _apply_air_control() -> void:
	var wanted: StringName = get_rules().air_control_id
	# An empty id is a rule set that has no opinion -- a bespoke harness world --
	# and every body keeps the profile its own scene carries. The same empty case
	# [method _install_chosen_map] honours for the arena.
	if String(wanted).is_empty():
		return
	var profile: MovementProfile = AirControlCatalog.profile_for(wanted)
	if profile == null:
		push_warning(
			"MatchController could not build the air control %s; every body keeps the profile its scene carries."
			% wanted
		)
		return
	_air_control_profile = profile

	var store: SettingsStore = SettingsStore.instance()
	if not store.applied.is_connected(_on_look_settings_applied):
		store.applied.connect(_on_look_settings_applied)
	_on_look_settings_applied()

	for participant: MatchParticipant in _participants:
		if participant.body != null:
			participant.body.set_profile(profile)


## Keep the look preferences on the live profile in step with the store. See
## [method _apply_air_control].
func _on_look_settings_applied() -> void:
	if _air_control_profile != null:
		SettingsStore.instance().settings.apply_to_movement_profile(_air_control_profile)
