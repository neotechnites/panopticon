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
## - [b]No UI.[/b] This is the model. Drawing it is [code]scenes/ui/[/code]'s job.
## - [b]No matchmaking, no chat, no invites, no reconnect.[/b]
## - [b]No launch acknowledgement.[/b] [constant Phase.LAUNCHING] is the window
##   in which every machine builds bodies, but nobody reports having finished.
##   The host moves on when its own match layer calls [method begin_match], and
##   a client still loading simply misses the first few snapshots. Fixing that
##   is an ack per peer and a wait, and it is not built.
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

## A peer connected and could not be seated. [param reason] is a readable line
## for a log or a disconnect message.
signal join_refused(peer_id: int, reason: String)

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
	## once. Ends when the match layer calls [method begin_match].
	LAUNCHING,
	## A match is running. The lobby is a spectator here: roles move around the
	## tower without it.
	IN_MATCH,
	## The match is over and its result is on screen. Ends when the host calls
	## [method return_to_lobby].
	POST_MATCH,
}

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

var _phase: Phase = Phase.IDLE

## This machine's own seat, or -1 when it has none. Machine-local and never
## replicated: every peer works its own out of the roster it receives.
var _local_seat_index: int = -1

## Winner of the match just played, or -1. Not replicated, and not a score: see
## [method conclude_match] for why the lobby keeps so little of a result.
var _last_winning_seat: int = -1


func _ready() -> void:
	_build_seats()
	if session == null:
		push_error("NetLobby has no session; it cannot seat anyone.")
		return
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


func get_seat(seat_index: int) -> LobbySeat:
	if seat_index < 0 or seat_index >= seats.size():
		return null
	return seats[seat_index]


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
## Any peers already connected are seated too, which matters because
## [signal NetSession.peer_joined] for a peer that arrived before this call has
## already been and gone.
func open(local_display_name: String) -> bool:
	if not _is_authority():
		return false
	_reset_seats()

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
		if peer_id != NetTransport.AUTHORITY_PEER_ID:
			_seat_peer(peer_id)

	_set_phase(Phase.GATHERING)
	_publish()
	return true


## Empty every seat and return to [constant Phase.IDLE]. Safe at any time, on
## any machine: a client whose host vanished calls this too, through
## [signal NetSession.session_ended].
func close() -> void:
	_reset_seats()
	_local_seat_index = -1
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
	_set_phase(Phase.LAUNCHING)
	_publish()
	match_launching.emit()
	return true


## The bodies exist; the match is live. Authority only, called by the match
## layer once it has armed the first round.
##
## Nobody acknowledges having finished building. See the class docs.
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
	_set_phase(Phase.GATHERING)
	_publish()
	return true


# --- Session events -----------------------------------------------------------

func _on_peer_joined(peer_id: int) -> void:
	if not _is_authority() or peer_id == NetTransport.AUTHORITY_PEER_ID:
		return
	if _phase == Phase.IDLE:
		# A lobby nobody opened is a lobby that is not in charge of anything.
		# A session is allowed to exist without one -- a tool, a test, a
		# spectator path that has not been built yet -- and throwing a peer off
		# because a dormant component has no seat for it would make the lobby
		# mandatory by accident. When open() does run it seats whoever is
		# already connected, so nothing is lost by waiting.
		return
	if _phase != Phase.GATHERING:
		join_refused.emit(peer_id, "The match has already started.")
		session.kick_peer(peer_id)
		return
	if _seat_peer(peer_id) == null:
		join_refused.emit(peer_id, "The lobby is full.")
		session.kick_peer(peer_id)
		return
	_publish()


func _on_peer_left(peer_id: int) -> void:
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
		_publish()
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
	_publish()


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

	var previous: Phase = _phase
	_phase = phase as Phase
	roster_changed.emit()
	if _phase != previous:
		phase_changed.emit(_phase)
		if _phase == Phase.LAUNCHING:
			match_launching.emit()


## Client to authority: ready or un-ready my seat.
@rpc("any_peer", "reliable", "call_remote", 0)
func _request_ready(ready: bool) -> void:
	if not _is_authority():
		return
	var seat: LobbySeat = find_seat_by_peer(multiplayer.get_remote_sender_id())
	if seat == null:
		return
	_apply_ready(seat.index, ready)


## Client to authority: this is what to call me.
@rpc("any_peer", "reliable", "call_remote", 0)
func _request_name(display_name: String) -> void:
	if not _is_authority():
		return
	var seat: LobbySeat = find_seat_by_peer(multiplayer.get_remote_sender_id())
	if seat == null:
		return
	_apply_name(seat.index, display_name)


# --- Internals ----------------------------------------------------------------

func _is_authority() -> bool:
	return session != null and session.is_authority()


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


## Seat a connected peer, or null when there is nowhere to put them.
func _seat_peer(peer_id: int) -> LobbySeat:
	if find_seat_by_peer(peer_id) != null:
		return find_seat_by_peer(peer_id)
	var seat: LobbySeat = _first_empty_seat()
	if seat == null:
		return null
	seat.occupancy = LobbySeat.Occupancy.HUMAN
	seat.peer_id = peer_id
	# Left blank until the peer says what to call it. A host that invented a
	# name here would have to un-invent it a frame later.
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
		rpc(&"_receive_roster", NetCodec.pack_roster(int(_phase), seats, _settings().max_name_bytes))
