class_name MatchState
extends RefCounted

## Everything lasting about a match, as the host has it on one tick (DESIGN 3.4 MatchState): what a
## mirror converges on. Written by [method MatchController.capture_state]; [NetCodec] owns its bytes.

const NONE: int = -1

## One participant's lasting state.
class Entry:
	extends RefCounted
	var running: bool = false
	var ghost: bool = false
	var shooter: bool = false
	## A ghost still held where it died: its respawn has not landed.
	var held: bool = false
	var finisher: bool = false
	## Bumped on every respawn, so a death and respawn inside one interval is still seen (u8).
	var life: int = 0
	var rounds_won: int = 0
	var turns_in_tower: int = 0
	var lives: int = 0
	## Host ticks; 0 is none.
	var respawn_end_tick: int = 0
	var grace_end_tick: int = 0
	var death_cause: int = 0

	func copy_from(other: Entry) -> void:
		running = other.running
		ghost = other.ghost
		shooter = other.shooter
		held = other.held
		finisher = other.finisher
		life = other.life
		rounds_won = other.rounds_won
		turns_in_tower = other.turns_in_tower
		lives = other.lives
		respawn_end_tick = other.respawn_end_tick
		grace_end_tick = other.grace_end_tick
		death_cause = other.death_cause


## The host tick this state is of.
var tick: int = 0
## False before the match has started: nothing else is meaningful.
var started: bool = false
var phase: int = 0
var round_number: int = 0
## Slots, or [constant NONE].
var guard: int = NONE
var finisher: int = NONE
var winner: int = NONE
var outcome: int = 0
## Bumped by every match start, so a restart into the same phase is seen (u8).
var match_serial: int = 0
## Rounds resolved this match (u8), and how the newest one went: a round resolved and re-armed in one tick.
var resolve_count: int = 0
var last_outcome: int = 0
## The siege clock's end; 0 when none runs.
var hold_end_tick: int = 0
## Bumped by every finale shove (u8); the guard it threw and the throw.
var kill_beat_serial: int = 0
var kill_beat_guard: int = NONE
var kill_beat_throw: Vector3 = Vector3.ZERO
var brawl_end_tick: int = 0
var brawl_winner: int = NONE
var participants: Array[Entry] = []


## Size the roster to [param count], keeping the entries already made.
func resize(count: int) -> void:
	while participants.size() < count:
		participants.append(Entry.new())
	participants.resize(count)


func copy_from(other: MatchState) -> void:
	tick = other.tick
	started = other.started
	phase = other.phase
	round_number = other.round_number
	guard = other.guard
	finisher = other.finisher
	winner = other.winner
	outcome = other.outcome
	match_serial = other.match_serial
	resolve_count = other.resolve_count
	last_outcome = other.last_outcome
	hold_end_tick = other.hold_end_tick
	kill_beat_serial = other.kill_beat_serial
	kill_beat_guard = other.kill_beat_guard
	kill_beat_throw = other.kill_beat_throw
	brawl_end_tick = other.brawl_end_tick
	brawl_winner = other.brawl_winner
	resize(other.participants.size())
	for i: int in participants.size():
		participants[i].copy_from(other.participants[i])


## Seconds from [member tick] to [param end_tick], or 0 for none or past.
func seconds_to(end_tick: int) -> float:
	return 0.0 if end_tick <= tick else float(end_tick - tick) / float(NetCodec.TICK_RATE)
