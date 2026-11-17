class_name NetLobby
extends Node

## Who is in the game, what they are going to be, and whether the match may
## start. The state machine between a session existing and a round being armed.
##
## [b]The authority owns the roster, absolutely[/b]
##
## Every mutator on this class does nothing on a client. A client presses ready
## and that is a REQUEST, sent to the host, granted or ignored there, and
## reflected back in the next roster broadcast -- the client's own seat table
## does not change until the host says so. This is the same rule as
## [PlayerNetLink]'s and for the same reason: there is exactly one copy of the
## truth and it is on the machine that pressed Host. A lobby that let clients
## edit their own copy would be a lobby where two people can be the guard.
##
## [b]Seats, not peers[/b]
##
## There are always [constant NetTransport.MAX_PLAYERS] seats. They are filled
## and emptied; they are never created or destroyed, and a seat's index is the
## name of its body on the wire for the whole session. That is what lets a bot
## and a remote human be interchangeable: filling a seat with a bot sets one
## enum, and everything below this class -- the snapshot, the replicator, the
## match -- carries on addressing seat 3 without knowing or caring what is in
## it. See [LobbySeat].
##
## [b]The tower is not a seat assignment[/b]
##
## [member LobbySeat.role] is the OPENING role only. Once a match is running
## the tower changes hands whenever a prisoner reaches the end, and this class
## does not track it -- ask the match layer. When
## [member MatchRules.open_with_race] is on, the correct opening assignment is
## no assignment at all: the race decides, and every seat launches
## [constant LobbySeat.Role.UNASSIGNED].
##
## [b]What this is honestly not[/b]
##
## - [b]No UI.[/b] This is the model. Drawing it is [code]ui/[/code]'s job.
## - [b]No matchmaking, no chat, no invites, no reconnect.[/b]
## - [b]No persistence.[/b] Scores live in the match, not here; a lobby that
##   returns to [constant Phase.GATHERING] has forgotten the match it just ran.

## The lobby's phase changed.
signal phase_changed(phase: Phase)

## Any part of the seat table changed. The one signal a UI needs to redraw.
signal roster_changed()

## A seat gained or lost an occupant, or a human in it turned into a bot. Fires
## alongside [signal roster_changed] for listeners that care about the specific
## seat rather than the table -- the match layer swapping a brain, say.
signal seat_occupancy_changed(seat_index: int, occupancy: LobbySeat.Occupancy)

## A seat was emptied because its occupant left. Carries the peer id it had, so
## a listener can tell a player quitting from a seat being freed by the host.
signal seat_vacated(seat_index: int, peer_id: int)

## The roster is frozen and every machine should build its bodies now. The hook
## the match layer waits on.
signal match_launching()

## A client reported its match scene bound at its seat. Authority only; see
## [method acknowledge_launch].
signal peer_launched(peer_id: int, seat_index: int)
## Authority: [param peer_id] has the scene of [param epoch] standing and can be sent its events.
signal scene_bound(peer_id: int, epoch: int)

## The host's match rules arrived or changed. See [method get_rules].
signal rules_changed()

## A peer connected and could not be seated. [param reason] is a readable line
## for a log or a disconnect message.
signal join_refused(peer_id: int, reason: String)

## Client: the host turned this machine away, and why. The session is left right after.
signal refused(reason: Refusal)

## Where the lobby stands. The whole vocabulary; there is no sixth state hiding
## in a bool somewhere.
enum Phase {
	## No session. The state before [method open] and after
	## [method close].
	IDLE,
	## Seats are filling and people are readying up. The only phase in which a
	## peer can be seated or a bot added.
	GATHERING,
	## The roster is frozen and bodies are being built, on every machine at
	## once; each client acknowledges its own with [method acknowledge_launch].
	## Ends when the match layer calls [method begin_match].
	LAUNCHING,
	## A match is running. The lobby is a spectator here: roles move around the
	## tower without it.
	IN_MATCH,
	## The match is over and its result is on screen. Ends when the host calls
	## [method return_to_lobby].
	POST_MATCH,
}

## Why a host turns a joiner away; the number that goes on the wire.
enum Refusal {
	## A match is running, and nobody joins one part-way.
	IN_MATCH,
	## Every seat holds a person.
	FULL,
	## The two builds do not speak the same game.
	VERSION,
}

## Real seconds a refused peer has to hear why and leave before the host drops it.
const REFUSAL_GRACE_SECONDS: float = 2.0

## Fewest occupants a match can start with. PANOPTICON is 1v1 at its smallest
## and a lone player in a tower has nothing to shoot, so two -- of which one
## may perfectly well be a bot.
const MIN_OCCUPANTS: int = 2

## The session this lobby runs on. Supplies the authority test, the peer roster
## and the settings.
@export var session: NetSession

## Every seat, always [constant NetTransport.MAX_PLAYERS] of them, index in
## order. Read freely; write through this class's methods, which is the only
## way the change reaches the other machines.
var seats: Array[LobbySeat] = []

static var _fingerprint: int = 0

## What this build tells a host it speaks, and what a host holds a joiner to.
var build_fingerprint: int = wire_fingerprint()

## The name this machine asks to be seated under when it joins; set before [method NetSession.join].
var local_name: String = ""

var _phase: Phase = Phase.IDLE

## Peers that have acknowledged the launch. Authority only; cleared by [method launch].
var _launched: Dictionary[int, bool] = {}
## Authority: the scene epoch each peer last said it has standing. See [method acknowledge_scene].
var _bound_epochs: Dictionary[int, int] = {}

## The host's [MatchRules], on every machine. Set by the host through
## [method set_rules]; null until it has.
var _rules: MatchRules = null

## This machine's own seat, or -1 when it has none. Machine-local and never
## replicated: every peer works its own out of the roster it receives.
var _local_seat_index: int = -1

## The scene epoch: bumped by the host whenever the scene everyone should be in changes
## (open, launch, back to the hub), replicated with the roster. 0 means none yet.
var _epoch: int = 0

## Winner of the match just played, or -1. Not replicated, and not a score: see
## [method conclude_match] for why the lobby keeps so little of a result.
var _last_winning_seat: int = -1

## Authority: the name each connected peer asked to join under. A peer absent here has not asked.
var _asked: Dictionary[int, String] = {}
## Authority: peers turned away and waiting to be dropped.
var _refused: Dictionary[int, bool] = {}

## Each peer's lobby-request allowance, and when it was last topped up, from
## [method Time.get_ticks_msec]. Wall clock: a flood arrives over a socket and
## the socket has not heard of the test runner's compressed time.
var _request_tokens: Dictionary[int, float] = {}
var _request_filled_ms: Dictionary[int, int] = {}


func _ready() -> void:
	_build_seats()
	if session == null:
		push_error("NetLobby has no session; it cannot seat anyone.")
		return
	session.session_established.connect(_on_session_established)
	session.peer_joined.connect(_on_peer_joined)
	session.peer_left.connect(_on_peer_left)
	session.session_ended.connect(_on_session_ended)


# --- Reading ------------------------------------------------------------------

func get_phase() -> Phase:
	return _phase


## This machine's seat, or null when it has none -- before [method open], or on
## a peer that connected mid-match and was refused one.
func get_local_seat() -> LobbySeat:
	if _local_seat_index < 0 or _local_seat_index >= seats.size():
		return null
	return seats[_local_seat_index]


func get_local_seat_index() -> int:
	return _local_seat_index


## The current scene epoch; see [member _epoch].
func get_epoch() -> int:
	return _epoch


## The epoch of the scene this machine is in, or 0 while the lobby names another scene.
func get_epoch_for(hub_scene: bool) -> int:
	var hub_phase: bool = _phase == Phase.GATHERING
	return _epoch if (hub_scene and hub_phase) or (not hub_scene and names_match_scene()) else 0


## True from the launch until the return to the hub: the scene every machine should be in is the match.
func names_match_scene() -> bool:
	return _phase == Phase.LAUNCHING or _phase == Phase.IN_MATCH or _phase == Phase.POST_MATCH


## The host's rules, or null before the host has published any.
func get_rules() -> MatchRules:
	return _rules


func get_seat(seat_index: int) -> LobbySeat:
	if seat_index < 0 or seat_index >= seats.size():
		return null
	return seats[seat_index]


## Authority: whether [param peer_id] has asked to join since it connected.
func has_asked(peer_id: int) -> bool:
	return _asked.has(peer_id)


## Authority: whether [param peer_id]'s copy of the scene the lobby names stands: bound hub, launched match.
func is_scene_standing(peer_id: int) -> bool:
	if _phase == Phase.IDLE or find_seat_by_peer(peer_id) == null:
		return false
	return has_bound(peer_id, _epoch) if _phase == Phase.GATHERING else has_launched(peer_id)


## The seat a peer is sitting in, or null. Never matches on 0: a peer id of
## zero means "nothing remote drives this", and every empty seat and every bot
## has one.
func find_seat_by_peer(peer_id: int) -> LobbySeat:
	if peer_id == 0:
		return null
	for seat: LobbySeat in seats:
		if seat.is_human() and seat.peer_id == peer_id:
			return seat
	return null


## Occupied seats, in index order. A fresh array each call; the seats in it are
## the live ones.
func get_occupied_seats() -> Array[LobbySeat]:
	var found: Array[LobbySeat] = []
	for seat: LobbySeat in seats:
		if seat.is_occupied():
			found.append(seat)
	return found


func get_occupant_count() -> int:
	var total: int = 0
	for seat: LobbySeat in seats:
		if seat.is_occupied():
			total += 1
	return total


## The seat starting in the tower, or null when nobody is -- which is the
## correct and expected answer under [member MatchRules.open_with_race].
func get_guard_seat() -> LobbySeat:
	for seat: LobbySeat in seats:
		if seat.is_occupied() and seat.role == LobbySeat.Role.GUARD:
			return seat
	return null


## True when every human occupant has readied. Bots are ready by construction
## -- see [method set_ready] -- so a lobby of one human and three bots is
## waiting on exactly one button.
func is_everyone_ready() -> bool:
	for seat: LobbySeat in seats:
		if seat.is_human() and not seat.is_ready:
			return false
	return true


## True when [method launch] would succeed.
func can_launch() -> bool:
	return (
		_is_authority()
		and _phase == Phase.GATHERING
		and get_occupant_count() >= MIN_OCCUPANTS
		and is_everyone_ready()
	)


## Why [method launch] would refuse, as a readable line. Empty when it would
## not. For a log or a disabled button's tooltip; the UI is not this class's
## business but the reason is.
func describe_launch_block() -> String:
	if not _is_authority():
		return "Only the host can start the match."
	if _phase != Phase.GATHERING:
		return "The lobby is %s, not gathering." % String(Phase.keys()[_phase])
	var occupants: int = get_occupant_count()
	if occupants < MIN_OCCUPANTS:
		return "%d in the lobby; a match needs %d. Add a bot." % [occupants, MIN_OCCUPANTS]
	if not is_everyone_ready():
		return "Waiting on someone to ready up."
	return ""


func describe() -> String:
	var lines: PackedStringArray = PackedStringArray(["NetLobby(%s)" % String(Phase.keys()[_phase])])
	for seat: LobbySeat in seats:
		if seat.is_occupied():
			lines.append("  " + seat.describe())
	return "\n".join(lines)


# --- Opening and closing ------------------------------------------------------

## Take the lobby from [constant Phase.IDLE] to [constant Phase.GATHERING] and
## seat this machine.
##
## Authority only, and called once the session is established -- hosting, or
## offline for a single-player or harness run, both of which
## [method NetSession.is_authority] answers true for so neither needs a special
## case here.
##
## Peers that asked to join before this call are seated too; one that has not
## asked yet is seated when it does.
func open(local_display_name: String) -> bool:
	if not _is_authority():
		return false
	_reset_seats()
	_bump_epoch()

	var host_seat: LobbySeat = seats[0]
	host_seat.occupancy = LobbySeat.Occupancy.HUMAN
	# The host's own seat carries the local peer id, which is 0 when offline.
	# That is the right value either way: zero means no remote packet may drive
	# this body, and offline nothing can.
	host_seat.peer_id = session.get_local_peer_id()
	host_seat.display_name = _clean(local_display_name)
	host_seat.is_ready = false
	_local_seat_index = 0

	for peer_id: int in session.get_peer_ids():
		if peer_id != NetTransport.AUTHORITY_PEER_ID and _asked.has(peer_id) and not _refused.has(peer_id):
			var seat: LobbySeat = _seat_peer(peer_id)
			if seat != null:
				seat.display_name = _clean(_asked[peer_id])

	_set_phase(Phase.GATHERING)
	_publish()
	for peer_id: int in session.get_peer_ids():
		if peer_id != NetTransport.AUTHORITY_PEER_ID:
			_send_rules_to(peer_id)
	return true


## Publish the host's rules to every machine. Authority only; a copy is kept,
## so the caller may go on editing [param source].
func set_rules(source: MatchRules) -> bool:
	if not _is_authority() or source == null:
		return false
	if _rules == null:
		_rules = MatchRules.new()
	NetCodec.copy_rules(source, _rules)
	rules_changed.emit()
	if session.is_established() and session.get_peer_count() > 1:
		rpc(&"_receive_rules", NetCodec.pack_rules(_rules))
	return true


## Empty every seat and return to [constant Phase.IDLE]. Safe at any time, on
## any machine: a client whose host vanished calls this too, through
## [signal NetSession.session_ended].
func close() -> void:
	if not session.is_established():
		_asked.clear()
		_refused.clear()
	_reset_seats()
	_local_seat_index = -1
	_epoch = 0
	_rules = null
	_set_phase(Phase.IDLE)
	roster_changed.emit()


# --- Filling seats ------------------------------------------------------------

## Put a bot in the lowest empty seat. Returns its index, or -1 when the lobby
## is full or is not gathering.
##
## [b]This is how this game gets played and tested.[/b] Ryan tests alone; a bot
## in a seat is what makes a 1v3 exist at all. The seat a bot occupies is the
## same seat a remote human occupies, carries the same index on the wire, and
## is replicated by the same code -- the only difference is that no packet is
## ever accepted for it.
func add_bot(display_name: String = "") -> int:
	if not _is_authority() or _phase != Phase.GATHERING:
		return -1
	var seat: LobbySeat = _first_empty_seat()
	if seat == null:
		return -1
	seat.occupancy = LobbySeat.Occupancy.BOT
	seat.peer_id = 0
	seat.display_name = _clean(display_name if not display_name.is_empty() else "Bot %d" % (seat.index + 1))
	# Bots are ready the moment they exist. See set_ready().
	seat.is_ready = true
	seat_occupancy_changed.emit(seat.index, seat.occupancy)
	_publish()
	return seat.index


## Put a bot in [param seat_index] or take it out; humans are left alone. Authority, gathering only.
func set_bot(seat_index: int, on: bool) -> bool:
	var seat: LobbySeat = get_seat(seat_index)
	if not _is_authority() or _phase != Phase.GATHERING or seat == null or seat.is_human():
		return false
	if not on:
		return seat.is_bot() and remove_occupant(seat_index)
	if seat.is_occupied():
		return true
	seat.occupancy = LobbySeat.Occupancy.BOT
	seat.peer_id = 0
	seat.display_name = _clean("Bot %d" % (seat_index + 1))
	seat.is_ready = true
	seat_occupancy_changed.emit(seat_index, seat.occupancy)
	_publish()
	return true


## Empty a seat. Authority only. Refuses the host's own seat -- leaving is
## [method NetSession.leave], not un-seating yourself and carrying on hosting.
func remove_occupant(seat_index: int) -> bool:
	if not _is_authority() or _phase != Phase.GATHERING:
		return false
	var seat: LobbySeat = get_seat(seat_index)
	if seat == null or not seat.is_occupied() or seat_index == _local_seat_index:
		return false
	var was_peer: int = seat.peer_id
	seat.clear()
	seat.index = seat_index
	seat_occupancy_changed.emit(seat_index, seat.occupancy)
	seat_vacated.emit(seat_index, was_peer)
	_publish()
	return true


## Fill the lobby out with bots up to [param target_occupants]. Returns how
## many were added.
##
## The convenience the harness and a solo player both want, and the reason it
## is a method rather than a loop at each call site: "start a 1v3" should be
## one call whether the other three are people, bots, or two of each.
func fill_with_bots(target_occupants: int) -> int:
	var added: int = 0
	while get_occupant_count() < target_occupants:
		if add_bot() < 0:
			break
		added += 1
	return added


# --- Readiness and names ------------------------------------------------------

## Ready or un-ready a seat.
##
## On the authority this is the change. On a client it is a request for its own
## seat, sent to the host; the local table does not move until the host's
## roster comes back. Calling it for somebody else's seat from a client does
## nothing at all.
##
## A bot cannot be un-readied. It has nothing to press a button with, and a
## lobby waiting on one would never start.
func set_ready(seat_index: int, ready: bool) -> bool:
	if not _is_authority():
		if seat_index != _local_seat_index:
			return false
		rpc_id(session.get_authority_peer_id(), &"_request_ready", ready)
		return true
	return _apply_ready(seat_index, ready)


## Set a seat's display name, with the same authority/request split as
## [method set_ready].
func set_display_name(seat_index: int, display_name: String) -> bool:
	if not _is_authority():
		if seat_index != _local_seat_index:
			return false
		rpc_id(session.get_authority_peer_id(), &"_request_name", _clean(display_name))
		return true
	return _apply_name(seat_index, display_name)


# --- Roles --------------------------------------------------------------------

## Put [param seat_index] in the tower and everybody else on the line.
##
## The OPENING assignment only; see the class docs. Authority only, and only
## while gathering -- roles are frozen at launch precisely so that two machines
## cannot disagree about who started where.
func assign_guard(seat_index: int) -> bool:
	if not _is_authority() or _phase != Phase.GATHERING:
		return false
	var guard: LobbySeat = get_seat(seat_index)
	if guard == null or not guard.is_occupied():
		return false
	for seat: LobbySeat in seats:
		if not seat.is_occupied():
			seat.role = LobbySeat.Role.UNASSIGNED
		else:
			seat.role = LobbySeat.Role.GUARD if seat.index == seat_index else LobbySeat.Role.PRISONER
	_publish()
	return true


## Pick the opening guard at random from the occupied seats.
##
## [param rng_seed] makes it reproducible, which is what the headless harness
## needs: a match that cannot be replayed cannot be diagnosed. Pass 0 for a
## seed off the clock.
func assign_guard_randomly(rng_seed: int = 0) -> int:
	if not _is_authority() or _phase != Phase.GATHERING:
		return -1
	var occupied: Array[LobbySeat] = get_occupied_seats()
	if occupied.is_empty():
		return -1
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	if rng_seed == 0:
		rng.randomize()
	else:
		rng.seed = rng_seed
	var chosen: int = occupied[rng.randi_range(0, occupied.size() - 1)].index
	return chosen if assign_guard(chosen) else -1


## Take everybody's opening role away.
##
## The correct state to launch in when [member MatchRules.open_with_race] is
## on: nobody starts in the tower, and the race decides who takes it. A lobby
## that named a guard anyway would be quietly overruled by the match, which is
## worse than saying nothing.
func clear_roles() -> bool:
	if not _is_authority() or _phase != Phase.GATHERING:
		return false
	for seat: LobbySeat in seats:
		seat.role = LobbySeat.Role.UNASSIGNED
	_publish()
	return true


# --- Match flow ---------------------------------------------------------------

## Freeze the roster and tell every machine to build bodies. Authority only.
##
## Emits [signal match_launching] on every peer, which is the match layer's cue
## and the point at which seat indices become body identities.
func launch() -> bool:
	if not can_launch():
		return false
	_launched.clear()
	_bump_epoch()
	_set_phase(Phase.LAUNCHING)
	_publish()
	match_launching.emit()
	return true


## Client to host, reliable: this machine's match scene is bound, at its seat.
## The host needs no message for its own scene; the reply is whatever of the
## match the sender missed, from the match layer.
func acknowledge_launch() -> void:
	if _is_authority() or not names_match_scene():
		return
	rpc_id(NetTransport.AUTHORITY_PEER_ID, &"_request_launched", get_local_seat_index())


## A client's word that its scene for [param epoch] stands: until then nothing in it can take an RPC.
func acknowledge_scene(epoch: int) -> void:
	if not _is_authority():
		rpc_id(NetTransport.AUTHORITY_PEER_ID, &"_request_scene_bound", epoch)


## True once [param peer_id] has the scene of [param epoch] standing. The host always has.
func has_bound(peer_id: int, epoch: int) -> bool:
	return peer_id == NetTransport.AUTHORITY_PEER_ID or int(_bound_epochs.get(peer_id, -1)) == epoch


## True once [param peer_id] has acknowledged the launch. The host always has.
func has_launched(peer_id: int) -> bool:
	return peer_id == NetTransport.AUTHORITY_PEER_ID or bool(_launched.get(peer_id, false))


## Seated human peers that have not acknowledged the launch.
func get_unlaunched_peers() -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for seat: LobbySeat in seats:
		if seat.is_human() and not has_launched(seat.peer_id):
			out.append(seat.peer_id)
	return out


## The bodies exist and every peer has launched; the match is live. Authority
## only, called by the match layer.
func begin_match() -> bool:
	if not _is_authority() or _phase != Phase.LAUNCHING:
		return false
	_set_phase(Phase.IN_MATCH)
	_publish()
	return true


## The match is over. Authority only. [param winning_seat_index] is -1 for a
## match that ended without one -- a host tearing it down, or a time limit with
## no winner.
##
## The lobby stores no result. Whose win it was, and what it was worth, belong
## to the match layer, which is the only thing that understands rounds; the
## lobby only needs to know that play has stopped.
func conclude_match(winning_seat_index: int = -1) -> bool:
	if not _is_authority():
		return false
	if _phase != Phase.IN_MATCH and _phase != Phase.LAUNCHING:
		return false
	_last_winning_seat = winning_seat_index
	_set_phase(Phase.POST_MATCH)
	_publish()
	return true


## A rematch: the finished match restarts on the same map. Authority only.
func resume_match() -> bool:
	if not _is_authority() or _phase != Phase.POST_MATCH:
		return false
	_last_winning_seat = -1
	_set_phase(Phase.IN_MATCH)
	_publish()
	return true


## The winning seat of the match just played, or -1. Cleared on
## [method return_to_lobby].
func get_last_winning_seat() -> int:
	return _last_winning_seat


## Back to gathering, keeping everyone who is still connected.
##
## Readiness is dropped: a player who readied for the last match has not agreed
## to the next one, and a lobby that starts again the instant a match ends is a
## lobby nobody can leave.
func return_to_lobby() -> bool:
	if not _is_authority() or _phase != Phase.POST_MATCH:
		return false
	_last_winning_seat = -1
	for seat: LobbySeat in seats:
		seat.role = LobbySeat.Role.UNASSIGNED
		seat.is_ready = seat.is_bot()
	_bump_epoch()
	_set_phase(Phase.GATHERING)
	_publish()
	return true


# --- Session events -----------------------------------------------------------

## Authority: a peer that connects and never asks to join holds a connection for nothing; it gets the same grace.
func _on_peer_joined(peer_id: int) -> void:
	if _is_authority() and peer_id != NetTransport.AUTHORITY_PEER_ID:
		get_tree().create_timer(REFUSAL_GRACE_SECONDS, true, false, true).timeout.connect(
			_drop_refused.bind(peer_id)
		)


## A client says who it is the moment it is connected; the host seats nobody it has not heard from.
func _on_session_established() -> void:
	if not _is_authority():
		rpc_id(NetTransport.AUTHORITY_PEER_ID, &"_request_join", build_fingerprint, _clean(local_name))


## One number for what two builds must share to play together: wire sizes, rule fields and maps.
static func wire_fingerprint() -> int:
	if _fingerprint != 0:
		return _fingerprint
	var parts: PackedStringArray = PackedStringArray([
		str(NetCodec.INTENT_SIZE), str(NetCodec.SNAPSHOT_HEADER_SIZE), str(NetCodec.SNAPSHOT_BODY_SIZE),
		str(NetCodec.ROSTER_HEADER_SIZE), str(NetCodec.ROSTER_SEAT_FIXED_SIZE),
		str(NetCodec.GAMESTATE_HEADER), str(NetCodec.GAMESTATE_PARTICIPANT), str(NetCodec.DECOY_VERSION),
		str(MoveIntent.PRESS_KEYS),
	])
	parts.append_array(NetCodec.rules_field_names(MatchRules.new()))
	for map: MapDefinition in MapCatalog.all():
		if map != null:
			parts.append(String(map.id))
	_fingerprint = hash("|".join(parts))
	return _fingerprint


## A connected peer asks for a seat: its build's fingerprint and the name it wants.
@rpc("any_peer", "reliable", "call_remote", 0)
func _request_join(fingerprint: int, display_name: String) -> void:
	var peer_id: int = multiplayer.get_remote_sender_id()
	if not _is_authority() or peer_id == NetTransport.AUTHORITY_PEER_ID:
		return
	if not session.has_peer(peer_id) or _asked.has(peer_id):
		return
	_asked[peer_id] = display_name.substr(0, MAX_RAW_NAME_LENGTH)
	if fingerprint != build_fingerprint:
		_refuse(peer_id, Refusal.VERSION)
		return
	# A lobby nobody opened is in charge of nothing: open() seats whoever has asked by then.
	if _phase != Phase.IDLE:
		_admit(peer_id)


## Seat a peer that asked to join under its name, or tell it why not.
func _admit(peer_id: int) -> void:
	var seat: LobbySeat = find_seat_by_peer(peer_id)
	if seat == null:
		if _phase != Phase.GATHERING:
			_refuse(peer_id, Refusal.IN_MATCH)
			return
		seat = _seat_peer(peer_id)
		if seat == null:
			_refuse(peer_id, Refusal.FULL)
			return
	if _phase == Phase.GATHERING:
		seat.display_name = _clean(_asked.get(peer_id, ""))
	_publish()
	_send_rules_to(peer_id)


## Turn a peer away: it is told why, and dropped if it has not left by itself.
func _refuse(peer_id: int, reason: Refusal) -> void:
	_refused[peer_id] = true
	join_refused.emit(peer_id, String(Refusal.keys()[reason]))
	rpc_id(peer_id, &"_receive_refusal", int(reason))
	get_tree().create_timer(REFUSAL_GRACE_SECONDS, true, false, true).timeout.connect(
		_drop_refused.bind(peer_id)
	)


## Drop a peer that was refused, or that never asked, once its grace is up.
func _drop_refused(peer_id: int) -> void:
	if session.has_peer(peer_id) and (_refused.has(peer_id) or not _asked.has(peer_id)):
		session.kick_peer(peer_id)


@rpc("authority", "reliable", "call_remote", 0)
func _receive_refusal(reason: int) -> void:
	if _is_authority() or reason < 0 or reason >= Refusal.size():
		return
	refused.emit(reason as Refusal)
	# Deferred: this runs inside the socket's own poll.
	session.leave.call_deferred()


func _on_peer_left(peer_id: int) -> void:
	_asked.erase(peer_id)
	_refused.erase(peer_id)
	_request_tokens.erase(peer_id)
	_request_filled_ms.erase(peer_id)
	_launched.erase(peer_id)
	_bound_epochs.erase(peer_id)
	if not _is_authority():
		return
	var seat: LobbySeat = find_seat_by_peer(peer_id)
	if seat == null:
		return
	var seat_index: int = seat.index

	if _phase == Phase.GATHERING or not _settings().fill_vacated_seats_with_bots:
		seat.clear()
		seat.index = seat_index
		seat_occupancy_changed.emit(seat_index, seat.occupancy)
		seat_vacated.emit(seat_index, peer_id)
		# Deferred: the leaving peer's ENet link is mid-teardown inside this signal.
		_publish.call_deferred()
		return

	# Mid-match. The body exists, other bodies are racing it, and deleting it
	# would leave a guard alone in a tower with a round that cannot end. The
	# seat becomes a bot's and the match layer swaps the brain -- see
	# NetSettings.fill_vacated_seats_with_bots, which is a question for Ryan.
	seat.occupancy = LobbySeat.Occupancy.BOT
	seat.peer_id = 0
	seat.is_ready = true
	seat_occupancy_changed.emit(seat_index, seat.occupancy)
	seat_vacated.emit(seat_index, peer_id)
	_publish.call_deferred()


func _on_session_ended(_failed: bool) -> void:
	close()


# --- Replication --------------------------------------------------------------

## Authority to everyone, whenever anything changes. Reliable, because a lost
## roster is two machines disagreeing about who is playing and nothing later
## corrects it.
##
## Restricted to the node's multiplayer authority, which is
## [constant NetTransport.AUTHORITY_PEER_ID] for the life of the session
## however often the tower changes hands.
@rpc("authority", "reliable", "call_remote", 0)
func _receive_roster(payload: PackedByteArray) -> void:
	if _is_authority():
		# A client cannot dictate the roster to the host. Reaching here means
		# a peer is impersonating the server.
		return
	var phase: int = NetCodec.unpack_roster(payload, seats, _settings().max_name_bytes)
	if phase < 0 or phase > int(Phase.POST_MATCH):
		return
	_relearn_local_seat()
	_epoch = NetCodec.roster_epoch(payload)

	var previous: Phase = _phase
	_phase = phase as Phase
	roster_changed.emit()
	if _phase != previous:
		phase_changed.emit(_phase)
		if _phase == Phase.LAUNCHING:
			match_launching.emit()


## Authority to one client or everyone: the rules the match will run under.
@rpc("authority", "reliable", "call_remote", 0)
func _receive_rules(payload: PackedByteArray) -> void:
	if _is_authority():
		return
	var decoded: MatchRules = _rules if _rules != null else MatchRules.new()
	if not NetCodec.unpack_rules(payload, decoded):
		return
	_rules = decoded
	rules_changed.emit()


## Client to authority: ready or un-ready my seat.
@rpc("any_peer", "reliable", "call_remote", 0)
func _request_ready(ready: bool) -> void:
	var seat: LobbySeat = _requesting_seat()
	if seat == null:
		return
	_apply_ready(seat.index, ready)


## Client to authority: my scene for this epoch stands.
@rpc("any_peer", "reliable", "call_remote", 0)
func _request_scene_bound(epoch: int) -> void:
	# Not rate limited, as one dropped is a peer told nothing in its scene: it counts once, and only
	# for the scene the lobby names now, so repeating or alternating it gets no second answer.
	var seat: LobbySeat = find_seat_by_peer(multiplayer.get_remote_sender_id())
	if seat == null or not _is_authority() or epoch != _epoch or has_bound(seat.peer_id, epoch):
		return
	_bound_epochs[seat.peer_id] = epoch
	scene_bound.emit(seat.peer_id, epoch)


## Client to authority: my match scene is bound, at this seat.
@rpc("any_peer", "reliable", "call_remote", 0)
func _request_launched(seat_index: int) -> void:
	# Not rate limited, as one dropped is a peer left out of its match: it counts once a launch,
	# for as long as the lobby names the match scene, however late that peer's scene stands.
	var seat: LobbySeat = find_seat_by_peer(multiplayer.get_remote_sender_id())
	if seat == null or not _is_authority() or seat.index != seat_index or not names_match_scene():
		return
	if _launched.get(seat.peer_id, false):
		return
	_launched[seat.peer_id] = true
	peer_launched.emit(seat.peer_id, seat.index)


## Client to authority: this is what to call me.
@rpc("any_peer", "reliable", "call_remote", 0)
func _request_name(display_name: String) -> void:
	var seat: LobbySeat = _requesting_seat()
	if seat == null:
		return
	if _phase != Phase.GATHERING:
		# A name is a lobby fact. Accepting one mid-match would republish the
		# whole roster to everybody in the middle of a round, and there is
		# nowhere it would be drawn that it has not already been drawn.
		return
	if display_name.length() > MAX_RAW_NAME_LENGTH:
		# Cut before it is walked. [method NetCodec.sanitise_name] inspects
		# every character, and a peer may not choose how many of them the host
		# inspects.
		display_name = display_name.substr(0, MAX_RAW_NAME_LENGTH)
	_apply_name(seat.index, display_name)


## The seat a lobby request belongs to, or null when the request is refused.
##
## Three refusals in one place. This machine must be the authority; the sender
## must hold a seat, which is how the acting seat is DERIVED from the packet's
## origin and never taken from the packet; and the sender must not be asking
## faster than [member NetSettings.lobby_request_interval_seconds].
##
## The throttle is the one that is easy to miss. Every request the host grants
## is answered with a reliable broadcast of the whole roster to every peer, so
## an unthrottled client makes the host send N packets for each one it sends --
## and alternating a flag defeats any check for "did this change anything".
func _requesting_seat() -> LobbySeat:
	if not _is_authority():
		return null
	var sender_id: int = multiplayer.get_remote_sender_id()
	var seat: LobbySeat = find_seat_by_peer(sender_id)
	if seat == null:
		return null
	if not _spend_request_token(sender_id):
		return null
	return seat


## Take one request out of [param peer_id]'s allowance. False when it is empty.
##
## A bucket rather than a minimum gap, because a gap gets the wrong answer for
## the one case that matters: a player types a name and presses Ready in the
## same second, which is two requests back to back and entirely ordinary. The
## bucket holds [constant REQUEST_BURST] and refills at one per
## [member NetSettings.lobby_request_interval_seconds], so a burst of clicking
## is free and a script settles at four requests a second.
func _spend_request_token(peer_id: int) -> bool:
	var now_ms: int = Time.get_ticks_msec()
	var interval_ms: float = maxf(
		session.get_settings().lobby_request_interval_seconds * 1000.0, 1.0
	)
	var tokens: float = float(_request_tokens.get(peer_id, float(REQUEST_BURST)))
	if _request_filled_ms.has(peer_id):
		tokens += float(now_ms - _request_filled_ms[peer_id]) / interval_ms
	tokens = minf(tokens, float(REQUEST_BURST))
	_request_filled_ms[peer_id] = now_ms
	if tokens < 1.0:
		_request_tokens[peer_id] = tokens
		return false
	_request_tokens[peer_id] = tokens - 1.0
	return true


# --- Internals ----------------------------------------------------------------

func _is_authority() -> bool:
	return session != null and session.is_authority()


## Lobby requests one peer may make back to back before the throttle bites.
const REQUEST_BURST: int = 4

## Longest raw display name the host will even look at, in characters.
##
## Four times the byte budget, which is room for a name of astral-plane emoji
## and nothing beyond it. The sanitiser truncates properly; this only stops a
## peer choosing how much work the host does before it gets there.
const MAX_RAW_NAME_LENGTH: int = 256


func _settings() -> NetSettings:
	return session.get_settings() if session != null else NetSettings.new()


func _clean(raw: String) -> String:
	return NetCodec.sanitise_name(raw, _settings().max_name_bytes)


func _build_seats() -> void:
	seats.resize(NetTransport.MAX_PLAYERS)
	for i: int in NetTransport.MAX_PLAYERS:
		var seat: LobbySeat = LobbySeat.new()
		seat.index = i
		seats[i] = seat


func _reset_seats() -> void:
	for i: int in seats.size():
		seats[i].clear()
		seats[i].index = i


func _first_empty_seat() -> LobbySeat:
	var limit: int = mini(_settings().get_effective_max_players(), seats.size())
	for i: int in limit:
		if not seats[i].is_occupied():
			return seats[i]
	return null


## While gathering, a bot's seat is a person's for the asking: the launch fills the table again.
func _last_bot_seat() -> LobbySeat:
	if _phase != Phase.GATHERING:
		return null
	for i: int in range(mini(_settings().get_effective_max_players(), seats.size()) - 1, -1, -1):
		if seats[i].is_bot():
			return seats[i]
	return null


## Seat a connected peer, or null when there is nowhere to put them.
func _seat_peer(peer_id: int) -> LobbySeat:
	if find_seat_by_peer(peer_id) != null:
		return find_seat_by_peer(peer_id)
	var seat: LobbySeat = _first_empty_seat()
	if seat == null:
		seat = _last_bot_seat()
		if seat == null:
			return null
		var freed: int = seat.index
		seat.clear()
		seat.index = freed
	seat.occupancy = LobbySeat.Occupancy.HUMAN
	seat.peer_id = peer_id
	# The caller writes the name the peer asked for.
	seat.display_name = ""
	seat.is_ready = false
	seat_occupancy_changed.emit(seat.index, seat.occupancy)
	return seat


func _apply_ready(seat_index: int, ready: bool) -> bool:
	var seat: LobbySeat = get_seat(seat_index)
	if seat == null or not seat.is_occupied() or _phase != Phase.GATHERING:
		return false
	# A bot is ready and stays ready.
	var wanted: bool = true if seat.is_bot() else ready
	if seat.is_ready == wanted:
		return true
	seat.is_ready = wanted
	_publish()
	return true


func _apply_name(seat_index: int, display_name: String) -> bool:
	var seat: LobbySeat = get_seat(seat_index)
	if seat == null or not seat.is_occupied():
		return false
	var cleaned: String = _clean(display_name)
	if seat.display_name == cleaned:
		return true
	seat.display_name = cleaned
	_publish()
	return true


## Work out which seat is this machine's, from the roster as it now stands.
##
## By peer id, which is why the host's offline seat cannot be found this way
## and is not looked for: offline there is one machine, it opened the lobby,
## and its seat index has been 0 since [method open].
func _relearn_local_seat() -> void:
	var local_id: int = session.get_local_peer_id()
	if local_id == 0:
		return
	for seat: LobbySeat in seats:
		if seat.is_human() and seat.peer_id == local_id:
			_local_seat_index = seat.index
			return
	_local_seat_index = -1


func _send_rules_to(peer_id: int) -> void:
	if _rules == null or not session.is_established():
		return
	rpc_id(peer_id, &"_receive_rules", NetCodec.pack_rules(_rules))


func _bump_epoch() -> void:
	_epoch = _epoch % (NetCodec.EPOCH_MODULUS - 1) + 1


func _set_phase(phase: Phase) -> void:
	if _phase == phase:
		return
	_phase = phase
	phase_changed.emit(_phase)


## Tell everyone, and tell this machine. Authority only; a no-op elsewhere, so
## the mutators can call it unconditionally.
func _publish() -> void:
	if not _is_authority():
		return
	roster_changed.emit()
	if session.is_established() and session.get_peer_count() > 1:
		rpc(&"_receive_roster", NetCodec.pack_roster(int(_phase), seats, _settings().max_name_bytes, _epoch))
