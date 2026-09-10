class_name NetSettings
extends Resource

## Every number the session layer runs on, in one swappable resource.
##
## [b]Why this exists[/b]
##
## Same reason [MatchRules] exists, for a different layer. A tick rate written
## into a script is a question nobody can ask again: you cannot A/B it on a bad
## connection, you cannot lower it for a player on a phone tether, and you
## cannot raise it during a playtest to find out whether the guard's aim
## problem is the snapshot rate or the lack of lag compensation. So the ports,
## the rates and the timeouts live here, where an exported [code].tres[/code]
## can vary them per session.
##
## [b]Which resource does a number belong in?[/b]
##
## The line against [MatchRules] is sharp and worth stating, because the two
## get confused:
##
## - [NetSettings] -- TRANSPORT. Facts about carrying the game over a wire:
##   how often, on what port, how long before we give up. Change one and the
##   same game is delivered differently. It must never change what the game IS.
## - [MatchRules] -- DESIGN. What the round is. Change one and you are playing
##   a different game.
##
## If a field here would change the outcome of a round played on one machine,
## it is in the wrong file. The one field that comes closest is
## [member fill_vacated_seats_with_bots], and its doc says so.

## Port the host listens on, and the default a client dials.
##
## Unassigned by IANA, and above the ephemeral range macOS and Linux hand out
## for outbound sockets, so a host does not lose a coin toss with a browser tab
## for its own port. Also what a player will have to forward on their router if
## they host over raw UDP -- which is the whole reason [SteamTransport] exists.
@export_range(1024, 65535, 1) var port: int = 27960

## Players in one session, this machine included.
##
## Matches run 1v1 to 1v7 and are tuned for 1v1 to 1v3. Clamped to
## [constant NetTransport.MAX_PLAYERS] wherever it is used, so lowering it
## below 8 is meaningful and raising it above is not.
@export_range(2, 8, 1) var max_players: int = NetTransport.MAX_PLAYERS

# --- Replication --------------------------------------------------------------

## How many world snapshots the authority sends per second.
##
## [b]30, and the reasoning is worth keeping.[/b] The authority simulates at 60
## Hz and always will -- that is [PlayerController]'s physics tick and the rate
## every shot is resolved at. This number is only how often the RESULT of that
## simulation is described to the other machines, and it trades host upstream
## bandwidth against how far behind a remote body's drawn position is.
##
## A snapshot is about 300 bytes at eight players (see [NetCodec]). At 30 Hz
## that is 9 KB/s down to each client and, on a 1v7 listen server, 63 KB/s up
## from the host -- roughly half a megabit, which a domestic upload can carry.
## Doubling it to 60 doubles both.
##
## What 30 Hz costs is 33 ms of extra staleness on remote bodies, on top of
## latency, and it is bought back visually by [member interpolate_remote_bodies].
## What it does NOT cost is hit registration: shots are resolved on the
## authority against the authority's own 60 Hz bodies, so a client never shoots
## at an interpolated position and a lower snapshot rate cannot make a hit into
## a miss. It can make a hit FEEL like a miss, which is a lag compensation
## problem and is not solved here -- see [PlayerNetLink].
##
## Raise this first if aiming at remote bodies feels wrong. If 60 does not fix
## it, the problem was never the snapshot rate.
@export_range(10, 60, 1) var snapshot_hz: int = 30

## Whether clients play remote bodies back from a buffer instead of snapping to
## each snapshot as it lands.
##
## Off, a body teleports [member snapshot_hz] times a second and every dropped
## packet is a visible hitch. On, it is drawn one snapshot interval in the past
## and slid smoothly between the two snapshots that bracket that moment, which
## is what every shipped game does and what makes 30 Hz watchable.
##
## The delay is the price and it is real: a remote body is drawn where it was
## [member snapshot_hz] milliseconds ago plus latency. Keep it on until the
## local body gets prediction, at which point the local body must stop
## interpolating and start predicting -- see [PlayerNetLink].
@export var interpolate_remote_bodies: bool = true

## Authority ticks a body's [RemoteIntentSource] holds its last packet before
## deciding the peer has gone quiet and releasing every held button.
##
## Holding the last input is right across a dropped packet and disastrous
## across a dropped player: a peer that stops sending mid-stride would
## otherwise sprint into the distance forever. Twelve ticks is 200 ms at 60 Hz
## -- long enough to ride out a burst of loss, short enough that nobody can use
## a pulled cable as a movement tech.
@export_range(2, 120, 1) var stale_intent_ticks: int = 12

## Largest per-tick look delta the authority will accept from a client, in
## radians.
##
## A client's packet is hostile input. [NetCodec] rejects a malformed one and
## rejects NaN; a well-formed packet claiming a thousand radians of yaw in one
## tick is what an aimbot sends, and it is clamped here because the sane range
## is a gameplay question the codec has no business knowing.
##
## PI is a half turn in a single tick -- beyond any real flick, and still short
## of a rotation large enough to alias the yaw. Note the limit of this: it
## bounds ONE tick. Sustained impossible movement is a server-side movement
## audit and is not implemented.
@export_range(0.1, 12.566, 0.001) var max_look_delta_radians: float = PI

# --- Timeouts -----------------------------------------------------------------

## Wall-clock seconds a join may sit in [constant NetTransport.ConnectionState.CONNECTING]
## before it is abandoned as failed.
##
## [b]Wall clock, deliberately.[/b] Every other duration in this project is
## simulated time, because the headless runner compresses the clock to run a 35
## second lap in under a second. A socket does not know that. A timeout
## measured in simulated seconds would fire fifty times early under the test
## runner and turn every networking test into a flake, so [NetSession] measures
## this one against [method Time.get_ticks_msec].
##
## Without this, a client dialling a host that is not there waits on ENet's own
## timeout, which on some platforms is a very long time and on a headless test
## rig is indistinguishable from a hang.
@export_range(0.5, 60.0, 0.1) var connect_timeout_seconds: float = 5.0

# --- Lobby --------------------------------------------------------------------

## Longest display name accepted from a peer, in bytes of UTF-8.
##
## A name is the only free-form text that crosses this wire, which makes it the
## only place a peer can spend the host's memory or paint the host's screen.
## [NetCodec] truncates to this and strips control characters; nothing
## downstream needs to think about it again.
@export_range(1, 64, 1) var max_name_bytes: int = 24

## Whether a seat whose human drops mid-match is taken over by a bot rather
## than left empty.
##
## [b]This is the one field here that touches design, and it needs Ryan's
## ruling.[/b] Matches are 1v1 to 1v3; one player quitting a 1v1 leaves a guard
## alone in a tower with nothing to shoot, and a round that cannot end. Handing
## the body to a bot keeps the match playable and matches the project's own
## position that a seat filled by a bot and a seat filled by a human are
## interchangeable. The argument against is that it changes who you were
## playing against without asking.
##
## [NetLobby] only changes the seat's occupancy and says so with
## [signal NetLobby.seat_occupancy_changed]. Actually swapping the brain on the
## body is the match layer's job, and it is free to ignore this.
@export var fill_vacated_seats_with_bots: bool = true


## Snapshot interval in simulated seconds, the form the replicator accumulates
## against.
func get_snapshot_interval() -> float:
	return 1.0 / float(maxi(snapshot_hz, 1))


## [member max_players], clamped to what the transport can actually carry.
func get_effective_max_players() -> int:
	return clampi(max_players, 2, NetTransport.MAX_PLAYERS)


## Problems with these settings, as human-readable lines. Empty means usable.
##
## Checks only what is objectively broken, never what is merely unusual: a
## player on a bad line turning the snapshot rate down to 10 is doing the thing
## this resource exists to allow.
func validate() -> PackedStringArray:
	var problems: PackedStringArray = PackedStringArray()
	if port < 1024:
		problems.append("port is %d; ports below 1024 need root on macOS and Linux." % port)
	if max_players < 2:
		problems.append("max_players is %d; a session needs a host and at least one guest." % max_players)
	if max_players > NetTransport.MAX_PLAYERS:
		problems.append(
			"max_players is %d, above the transport cap of %d; it will be clamped."
			% [max_players, NetTransport.MAX_PLAYERS]
		)
	if snapshot_hz > Engine.physics_ticks_per_second:
		# Not broken -- the replicator simply sends one per tick -- but it means
		# the number is not doing what whoever set it thought it was doing.
		problems.append(
			"snapshot_hz is %d, above the %d Hz simulation; the authority cannot produce snapshots it has not simulated."
			% [snapshot_hz, Engine.physics_ticks_per_second]
		)
	if stale_intent_ticks < 2:
		problems.append(
			"stale_intent_ticks is %d; a single dropped packet would stop the body dead."
			% stale_intent_ticks
		)
	return problems
