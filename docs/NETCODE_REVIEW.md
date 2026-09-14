# Netcode review

PANOPTICON is host-authoritative over ENet: one player's machine simulates the
match, up to seven others are terminals onto it, and the tower seat changing
hands never moves the authority. This is a review of that layer against the bar
"it should have very good netcode" for eight players on Tailscale or direct UDP,
plus the fixes it produced.

Everything below is measured, not estimated. The instruments are in the suite
and print their numbers on every run:

- `tests/test_net_cost.gd` — bytes on a real socket, from ENet's own counters, and
  microseconds on the host and on a client.
- `tests/test_net_conditions.gd` — 167 ms round trip, 2 ticks of jitter, 5% loss
  and a 500 ms host hitch, over a wire the test owns and can drop packets on.
- `tests/test_net_authority.gd` — what the authority refuses from a client.

---

## 1. Bandwidth

Measured with eight seats, one real client on a real UDP socket, over 120
snapshots. The byte counts are ENet's, so RPC headers and ENet framing are in
them.

| | bytes per snapshot | down per client | host up at 8 seats | up per client |
|---|---|---|---|---|
| before | 354 | 10.6 kB/s | 74.3 kB/s — **0.59 Mbit/s** | 36 B/packet, 2.2 kB/s |
| quantised only | 226 | 6.8 kB/s | 47.5 kB/s — 0.38 Mbit/s | 55 B/packet, 2.6 kB/s |
| **quantised + compressed (shipped)** | **134** | **4.0 kB/s** | **28.2 kB/s — 0.23 Mbit/s** | **26 B/packet, 1.6 kB/s** |

**62% off the host's upstream.** A poor 4G uplink is 1–2 Mbit/s; a host with
seven clients now needs 0.23 of it, where it needed 0.59. A client needs 0.013
Mbit/s up, which is noise on any connection that can carry a voice call.

### What changed

**A snapshot body carries no float** (`net_codec.gd`). Position and velocity are
centimetres in an `i16`, yaw is a fraction of a turn in a `u16`, pitch is a
scaled `i16`. 42 bytes a body became 26; a full lobby's snapshot payload went
from 341 bytes to 213.

The error this costs is five millimetres of position and five millimetres a
second of speed, which is under the noise floor of a body drawn interpolated at
30 Hz. It is not free in one place and that place is documented on the codec: a
predicting client measures its own guess against the authority's quantised
answer, so five millimetres of every reported correction is the wire. That is
two orders under `prediction_snap_metres` and is why the quantisation is this
coarse and not coarser.

**ENet's range coder is on** (`enet_transport.gd`, `NetSettings.compress_traffic`).
It takes a further 41% off a snapshot — 226 bytes to 134 — because eight bodies
of quantised integers with near-identical flag, ability, health and timer bytes
is exactly the case an adaptive entropy coder is built for. Both ends read the
same setting, because a host that compresses and a client that does not have a
connection that establishes and then reads rubbish.

**The hologram transform went from 16 bytes to 10**, quantised the same way. It
still streams at the simulation rate rather than the snapshot rate, and that is
deliberate: a decoy is a body the tower is shooting at, and it is the one
message whose size is multiplied by sixty.

### What was considered and not done

**Delta compression.** At 213 bytes of payload, against 134 on the wire after
the entropy coder, there is not enough left to be worth the acknowledgement
bookkeeping and the class of bug where a client's baseline and the host's
disagree.

**Quantising the intent.** It would save about seven bytes on the direction that
was already sending a twentieth of what the host sends — and it would cost real
accuracy, because a predicting client simulates with the intent it holds and the
authority simulates with the intent it received. Any difference between those
two is prediction error that accumulates over a round trip before it is
corrected. Float intent is the cheap half of the wire and it stays exact.

**A send rate for far or irrelevant bodies.** The ring is 120 metres across and
open; there is no body a player cannot see. Interest management here would buy a
few per cent and cost a class of bug where a body appears out of nowhere.

---

## 2. Latency

### What was wrong

Playback restarted on arrival. The client held two snapshots and slid between
them over a span reset every time a packet landed, so an early packet drew a
body fast and a late packet froze it — the exact hitch a jittery line produces,
whether or not anything was lost. There was no clock, no buffer depth to speak
of, no extrapolation, and the prediction agent's note was right on both counts:
each jittered burst cost about a tick of travel, and a snap discarded roughly a
round trip of the player's own movement.

### What changed

**A playout clock with an adaptive jitter buffer** (`net_replicator.gd`). The
client keeps its own position in the authority's tick stream and advances it on
the PHYSICS tick — the authority's ticks are what it is counting, so tying the
two together makes the buffer mean the same thing at 30 frames a second as at
240. Drawing happens on the frame, at the clock plus the sub-tick fraction.

The clock is held behind the newest snapshot by one snapshot interval plus twice
the jitter the client has MEASURED on this connection, capped at
`max_interpolation_jitter_ticks` (8 ticks, 133 ms). A LAN pays the floor. Drift
is taken out by running playback a few per cent fast or slow, never by jumping,
unless the error passes a third of a second — at which point the connection has
changed rather than drifted and jumping is honest.

**Bounded extrapolation.** Past the newest snapshot, bodies sail on along their
last velocity for up to `max_extrapolation_seconds` (150 ms), then hold. A body
that keeps running and is corrected reads as a body that kept running; a body
that freezes and teleports reads as a broken game.

**A snap replays instead of discarding.** `PlayerNetLink._reconcile` used to drop
the whole prediction buffer for any correction over a metre — a boost pad, a
shove, a kill — which deleted the last round trip of the player's own running and
turning. It now always rewinds to the authority's state and replays every
unacknowledged input on top. What a snap changes is the VIEW: it goes with the
body at once instead of drifting onto it, because drawing a launch as a graceful
slide is a lie about where the body is. After an event the facing comes from the
authority (the match re-placed the body) and the unacknowledged look deltas are
turned onto it again, so being shoved never also takes the mouse.

**Redundant intent** (`NetSettings.intent_redundancy`, default 2). Each intent
packet repeats the previous tick's. See §4 — it is a reliability fix as much as
a latency one, and it is what stops the host's input queue starving.

### Measured, at 167 ms round trip with 2 ticks of jitter and 5% loss

One tick of travel is 0.183 m at the tuned run speed; everything below is quoted
against it because that is the unit these errors actually come in.

**Prediction.** Worst correction **0.187 m — 1.02 ticks of travel** — over 125
corrections, **0 snaps**. A bad line costs ticks of travel and nothing else.

**A mirrored body**, 300 frames, before and after in the same run:

| | worst frame | spread of frame travel | frozen frames |
|---|---|---|---|
| fixed delay, no extrapolation (the old behaviour) | 0.407 m | 0.049 m | 5 |
| adaptive buffer + extrapolation | 0.337 m | 0.034 m | **0** |

The spread is the number that matters. A pop is unevenness — the body covering
two ticks of ground in one frame and none in the next — and it fell by 30%, with
the freezes gone entirely. The worst single frame is bounded by the snapshot
interval either way and says less than it looks like it does. The buffer settled
at **3.76 ticks (63 ms) of delay on 14.7 ms of measured jitter**, which is the
adaptation working: it is not the 8-tick ceiling and it is not the floor.

**A 500 ms host hitch.** Worst mirrored frame **0.389 m during** (2.1 ticks of
travel — the body sails on rather than jumping), 0.345 m on the way back, **0
prediction snaps**, and the client is still predicting its own body afterwards.
The prediction buffer holds 64 ticks, which is 1.07 s, so a half-second hitch
never runs it out.

### Still not done

**No lag compensation.** Shots are resolved against where the authority thinks
bodies are now, not where the shooter saw them. On a listen server that quietly
favours the host. It is a design question — how much the host should be favoured
is Ryan's call — not a bug, and it is the largest single thing left in this file.

---

## 3. Authority and the cheating surface

Every gameplay decision is the host's. There are exactly **four** client→host
messages, and every one of them derives the acting seat from
`multiplayer.get_remote_sender_id()` rather than trusting an index in the
packet. No node in the project calls `set_multiplayer_authority`; the authority
is peer 1 for the life of the session however often the tower changes hands,
which removes the entire class of authority-migration hijack.

| message | channel | what the host validates |
|---|---|---|
| `PlayerNetLink._receive_intent` | 1, unreliable ordered | authority; seat is remotely drivable at all; **sender owns this seat**; fixed-length frame; NaN and infinity refused; move direction clamped to the unit disc; look delta clamped to `max_look_delta_radians`; replay and reorder refused by tick; **dev keys zeroed**; **rate capped** |
| `NetLobby._request_ready` | 0, reliable | authority; **seat derived from the sender**; phase must be GATHERING; **rate capped** |
| `NetLobby._request_name` | 0, reliable | authority; seat derived from the sender; **phase must be GATHERING**; **raw length capped before it is walked**; control characters stripped, truncated to 24 bytes of UTF-8; **rate capped** |
| `NetMatch._client_ready` | 0, reliable | authority; clears only the sender's own entry; idempotent; no payload |

Everything else is host→client and annotated `@rpc("authority", ...)`, which
Godot's own transport filter enforces on top of the `is_authority()` check each
handler makes: the roster, the match rules, the world snapshot and the hologram
stream can only come from peer 1, so a client cannot hand the lobby a different
rule set, move every body in the world, or invent a seat for itself. Seats are
assigned by the host in `NetLobby._on_peer_joined`; no client supplies a seat
index anywhere, in any message.

### Gaps found and closed

**A client could pick its own runner power.** `MoveIntent.ability_slot` is a dev
test key: it selects a power DIRECTLY, skipping the fallback to
`MatchRules.runner_ability`. A modified client setting it every tick got Armor
Lock — and `is_hit_immune()` with it — in a match whose rules said abilities were
off, and Active Camo the same way. The host now zeroes the field unless
`NetSettings.accept_remote_ability_slot` is on, which it is not by default. The
headless harness drives abilities through this field, so it is a host-side flag
rather than a second code path.

**Turbo and godmode could have leaked in.** They were never packed, but
`unpack_intent` wrote every field of a caller-owned struct EXCEPT those two, and
`MoveIntent.copy_from` does copy them. Safe only by the accident that the
authority never fills that struct from a local intent. They are now cleared
explicitly on decode, so the format cannot carry them by any future route.

**No rate limit on lobby requests.** Every granted ready or rename answers with a
reliable broadcast of the whole roster to every peer, so an unthrottled client
made the host send N packets for each one it sent — and alternating a flag
defeats any "did this change anything" check. There is now a token bucket per
peer: four requests back to back are free (a player typing a name and pressing
Ready in one second is two of them), refilling at one per 250 ms.

**A rename was accepted mid-match**, republishing the roster to everybody in the
middle of a round. Now GATHERING only.

**An unbounded name string was walked character by character** before being
truncated to 24 bytes. Cut to 256 characters before the sanitiser sees it.

**No cap on intent packets per tick.** A peer sending faster than it simulates
gained nothing — the authority consumes one intent per tick from a four-deep
queue — but it could spend the host's CPU proving it. Capped at four packets per
peer per tick, which is twice what a bursty line needs.

### Not a gap

Turbo on a client is rubber-banding, not speed: the client predicts with the
multiplier, the host simulates without it, and the next snapshot corrects it.
Godmode on a client changes nothing, because `apply_hit` runs on the host against
the host's own copy of the intent. The host's own dev keys are local input on the
machine that is the server, which is what a listen server means.

---

## 4. Reliability and ordering

Channel 0 carries everything rare and reliable: the roster, the rules, and every
match event — round start and the tower handover with it, kills, catches, the
round outcome, the match winner, respawns, the finisher arming, the kill beat,
every rifle shot, hit and miss. Channel 1 is intent, 2 is the world snapshot, 3
is hologram motion; those three are unreliable ordered, which is right, because
a late one has been overtaken by a newer one and retransmitting it would spend
latency to deliver a worse answer.

**No gameplay-critical one-shot rides an unreliable channel.** Kills, catches,
round state and pad launches were checked specifically: the first three are
reliable events, and a boost pad launch is not an event at all — it is absolute
position and velocity in the next snapshot, which self-heals.

### Gaps found and closed

**A dropped intent packet lost a press.** Intent edges — jump, slide, shove, the
trigger — are consumed once and gone, so a dropped packet was a press the player
made and the game ignored. On a 5% line that is one press in twenty. Each packet
now repeats the previous tick's intent; the authority's `accept()` refuses the
repeats it has already had, so nothing downstream knows it is happening.

Measured at 5% loss with jitter, as the fraction of ticks whose input the
authority actually SIMULATED: **83.3% with one intent a packet, 97.0% with two.**
Worse than 95% at one, because jitter starves the host's input queue as well as
loss does — a tick that brings no packet repeats the last command and does not
advance the acknowledgement, which is the "one tick of travel" the prediction
agent measured. The repeat fixes both, which is why it lands above the line's own
delivery rate. Three would cover two losses in a row; it costs nineteen bytes
and the setting is there.

**A jump could be lost or merged.** `PlayerState.jumped` was an EDGE on the
unreliable snapshot channel sampled at half the simulation rate: a dropped
snapshot lost the jump, and two hops inside one interval arrived as one. It is a
COUNT now, wrapping at 8, riding in three bits the flag byte already had spare,
and a mirror fires once per increment it sees. Costs nothing and survives both.

**A client that loaded slowly ended up in an inert match.** The host starts
without a peer that has not reported after 10 seconds, and starting moves the
lobby phase to IN_MATCH — at which point the late client's `NetMatch._ready`
refused to bind at all, leaving it in a match scene with no bodies, no links and
no way back. It binds in IN_MATCH now, and `_client_ready` arriving after the
start sends that peer a catch-up: the match is running, and this is the round it
is on. The bodies need nothing, because a snapshot is absolute.

**A client was never told the host had gone.** `NetMatch` did not subscribe to
`session_ended`, so a client whose host quit kept running a match scene full of
frozen bodies with nothing deciding anything. It now stops and emits `host_lost`.
There is still no host migration and there should not be: promoting a client
means handing it a world it never simulated, and no amount of state transfer
makes the round it interrupts fair.

### Checked and already correct

**The hub→match scene switch against the first snapshots.** The session, lobby
and replicator live at `/root/NetSession` and survive the scene change. Before
the switch a client's replicator has no links, so an arriving snapshot is
buffered and drawn on nobody; the host sends nothing until it has bodies of its
own; both ends flush their playback on any connection state change. Nothing
crashes and nothing is half-applied.

**Joining mid-hub.** A peer arriving during GATHERING is seated and every hub
rebuilds its bodies from the new roster; a peer arriving once a match is running
is refused and disconnected rather than half-seated.

**A truncated or forged packet.** Every decoder length-checks before it reads,
refuses a body count above the session's cap, and leaves its output cleared
rather than half-filled — a snapshot describing three of five bodies would draw
the other two as players who had stopped moving.

---

## 5. Robustness

**MTU.** Asserted in the suite: a full eight-seat snapshot is 213 bytes of
payload, the most redundant intent packet this build can send is 81, and a
hologram transform is 10 — all against a 1200-byte bound that any path worth
playing on carries without fragmenting. A fragmented UDP datagram is lost whole
when any one of its fragments is, so the headroom is the point.

**Compression.** On, both ends, from one setting. See §1.

**Peer timeout.** ENet's own default gives a dead peer up to thirty seconds. In a
1v1 that is half a minute of a player standing in an empty ring. Now 8 seconds
(`NetSettings.peer_timeout_seconds`), with the floor at a quarter of that so a
brief stall is not a disconnection.

**A 500 ms host hitch.** Measured in §2: remote bodies extrapolate for 150 ms and
then hold rather than freezing and teleporting, the playout clock catches up by
dilation rather than jumping, the prediction buffer (1.07 s) never runs out, and
the client takes no snaps coming out of it.

**Reconnect.** Still not implemented. A session is created, played and destroyed,
and a player who drops has their seat handed to a bot. For a lobby this size that
is the right trade; it is written down here so the next person does not have to
rediscover that it was a decision.

---

## 6. Cost

Measured at eight seats, 500 iterations each. A 60 Hz tick is 16 667 µs.

| | per snapshot | share of a tick |
|---|---|---|
| host: sample eight bodies and pack | 27.8 µs | 0.17% |
| client: unpack eight bodies and take them | 19.3 µs | 0.12% |
| client: one frame of playback | 16.1 µs | 0.10% |

The host pays its cost 30 times a second, not 60, so replication is under a
millisecond of every simulated second on either end. It is not a number to
optimise; it is a number to notice if it ever changes by an order.

---

## What changed, by file

| file | change |
|---|---|
| `scripts/net/net_codec.gd` | quantised snapshot bodies (42→26 B); jump counter instead of a jump flag; intent packets carry N intents; dev keys cleared on decode; quantised hologram transform (16→10 B) |
| `scripts/net/net_replicator.gd` | playout clock, adaptive jitter buffer, bounded extrapolation, snapshot ring in place of a two-snapshot slide |
| `scripts/net/player_net_link.gd` | snaps replay instead of discarding; redundant intent; per-tick intent packet cap; ability-slot gate; harness seams |
| `scripts/net/player_state.gd` | `jumped` → `jump_counter` |
| `scripts/net/net_lobby.gd` | per-peer token bucket, phase gate on renames, raw name length cap |
| `scripts/net/net_match.gd` | binds in IN_MATCH, catch-up for a late client, `host_lost` |
| `scripts/net/net_transport.gd`, `enet_transport.gd` | wire statistics, range coder, peer timeouts, MTU constant |
| `scripts/net/net_settings.gd` | the nine new numbers, each with the reasoning on the field |
| `tests/test_net_cost.gd`, `test_net_conditions.gd`, `test_net_authority.gd` | new |
