# Architecture review — the net and match core

A fresh read of `scripts/net/`, `scripts/player/`, `scripts/match/` and
`scripts/hub/` against one question: **is the speed a property of the design, or
the residue of patching a bad one?**

Short answer up front: it is the design. See §2 for where it is not.

---

## 1. The design as it is

### Data flow

```
 CLIENT (peer N)                                  AUTHORITY (peer 1, listen server)
 ──────────────────────────────────────────────   ──────────────────────────────────────────────

 device                                            HumanIntentSource / BotIntentSource
   │ Input                                              │  (host's own seat, and every bot)
   ▼                                                    │
 HumanIntentSource ──poll()──► MoveIntent               │
   │                             │                      │
   │      ┌──────────────────────┘                      │
   │      │                                             │
   ▼      ▼                                             ▼
 PlayerController._physics_process(60 Hz)         PlayerController._physics_process(60 Hz)
   │  predicts this body, same code               ┌──►  one per seat, ALL of them
   │                                              │       │
   ├─ _record_tick() → _predicted[ ] ring         │       │
   │    (tick, intent, pos, vel, yaw, motion)     │       │
   │                                              │       │
   ▼                                              │       │
 NetCodec.pack_intents(tick, last N)              │  RemoteIntentSource._buffer[4]
   │  19 B/intent + 5 B header                    │       ▲  one taken per tick
   │  redundancy = 2 (repeats prior ticks)        │       │
   ▼                                              │       │
 rpc_id(1, _receive_intent)  ══ ch 1, unreliable_ordered ═╪══► PlayerNetLink._receive_intent
                                                  │       │      · sender_id == owner_peer_id?
                                                  │       │      · ≤ max_intent_packets_per_tick
                                                  │       │      · codec well-formed? finite?
                                                  │       │      · look_delta clamped to ±π
                                                  │       └──── RemoteIntentSource.accept(tick)
                                                  │              (drops repeats it already had)
                                                  │
                                                  │  after the tick (priority 100):
                                                  │  NetReplicator._physics_process
                                                  │       │  _tick += 1
                                                  │       │  accumulate → 30 Hz
                                                  │       ▼
                                                  │  link.sample_state(slot) × seats
                                                  │       │
                                                  │  WorldSnapshot { tick, count, states[8] }
                                                  │       │  fixed pool, no allocation
                                                  │       ▼
                                                  │  NetCodec.pack_snapshot → 26 B/body
                                                  │       │  i16 cm, u16 turn, flag byte
 NetReplicator._receive_snapshot ◄══ ch 2, unreliable_ordered ═══ rpc(_receive_snapshot)
   │                                              │
   ├─ unpack → _incoming  (refuse malformed, refuse older than newest)
   ├─ _buffer_snapshot → _playback[12] ring
   ├─ _update_delay()  → jitter measured, _delay_ticks = floor + 2×jitter
   │
   ├──────────────► link.is_predicting()? ── YES ──► receive_authoritative()
   │                     │                             └─ held; applied on the NEXT
   │                     │                                physics tick, in _reconcile()
   │                     │                                  · rewind pos/vel to authority
   │                     │                                  · yaw from own record (or
   │                     │                                    authority's, if snapped)
   │                     │                                  · restore_motion_state()
   │                     │                                  · replay unacked ticks through
   │                     │                                    controller.simulate_tick()
   │                     │                                  · error → view_offset, decayed
   │                     │
   │                     └─ NO ──► interpolated by the playout clock:
   │                                 _advance_clock() on PHYSICS (dilate ±20%)
   │                                 _draw() on FRAME  (+ sub-tick fraction)
   │                                   · find bracketing snapshots
   │                                   · PlayerState.interpolate_from(a, b, w)
   │                                   · past newest → extrapolate ≤150 ms, then hold
   │                                 link.apply_state() → transform, vel, net_floor/slide/crouch
   │                                 link._present_events() → jumped/landed/slide signals,
   │                                   once per snapshot tick, jump COUNTER not flag
   ▼
 PrisonerAvatar / MovementAudio / camera            MatchController decides everything else
                                                    ─ rounds, seats, ghosts, hits, the finisher
 MatchController.net_*(…)  ◄══ ch 0, reliable ═════  NetMatch._ev_*  (16 one-shot events)
   (applies; decides nothing)                        NetLobby._receive_roster (whole table)
```

### Who owns what

| Node | Owns | Knows nothing about |
|---|---|---|
| `NetTransport` / `ENetTransport` | sockets, peer ids, connection state | the game |
| `NetSession` | the transport, the peer list, `NetSettings`, "am I the authority" | seats, bodies, rounds |
| `NetLobby` | the seat table, the lobby phase machine, the published `MatchRules` | bodies, physics, who holds the tower |
| `NetReplicator` | the authority tick, the 30 Hz send, the playback buffer and playout clock, the decoy stream | how a body moves |
| `PlayerNetLink` | one seat's direction of travel: intent up, state down, prediction and reconciliation | the wire format, the match rules |
| `NetCodec` | **the entire wire format**, and nothing else | tunables, ranges, gameplay |
| `NetMatch` | seat → body → link construction; server match events → client replay | the rules themselves |
| `MatchController` | every match rule, enforced | the network, except `_mirror` |
| `PlayerController` | the physics | **networking, entirely** |

### The tick model

Three clocks, deliberately distinct, and each one is named after who owns it.

- **Simulation** — 60 Hz, `_physics_process`, on every machine that simulates a
  body. The authority runs it for all eight; a client runs it for its own body
  only, and `refresh_role()` calls `set_physics_process(false)` on the rest.
- **Snapshot** — 30 Hz, accumulated by `NetReplicator` with `fmod`, not zeroed,
  so a long frame does not drift the rate to 20.
- **Playout** — the client's own position in the authority's tick stream,
  advanced on the *physics* tick and drawn on the *frame*. This is the one that
  matters: it is a clock, not a slide reset on arrival, which is the difference
  between tolerating jitter and rendering it.

Ordering inside the tick is enforced by `process_physics_priority`: bodies at 0,
`PlayerNetLink` at 50 (record and reconcile *after* the body has moved),
`NetReplicator` at 100 (sample the result of this tick, not the last one).

### Where authority lives

`AUTHORITY_PEER_ID = 1`, fixed at `host()` and never moved. The load-bearing
decision is that **authority binds to a peer, never to a role**: the tower seat
changes hands several times a match, and if authority followed it every score
would be a mid-match host migration. Nothing under `scripts/net/` reads the
tower role, and no code path calls `set_multiplayer_authority()`. There is no
host migration; losing the host ends the match (`FAILED`, not `OFFLINE`, so a
stranded client cannot promote itself over its own empty world).

`OFFLINE` counts as authoritative. That is why single-player, the headless
harness and the listen server share one code path with no "networking is off"
branch anywhere in the match or player layers.

### The seams

| Seam | Shape | What it buys |
|---|---|---|
| `MoveIntent` | 13-field struct, 19 B on the wire | keyboard, bot and socket are indistinguishable to `PlayerController`. One movement implementation, not two. |
| `IntentSource` | `poll(delta) → MoveIntent` | `RemoteIntentSource` is a peer; `BotIntentSource` is AI; neither is a special case |
| snapshot body | fixed 26 B record, seat-keyed | a bot and a remote human occupy a seat interchangeably, because a body is named by **seat**, never by peer |
| `PlayerState` | one body at one tick | quantised, reused, interpolable |
| `WorldSnapshot` | all bodies at **one** tick | a client's world is internally consistent by construction |
| match events | 16 reliable one-shots | rules run once, on the authority; clients replay |
| `NetSettings` vs `MatchRules` | transport vs design | a rate change can never change what the game *is* |

---

## 2. Judgement

**The speed is a property of the design.** The evidence is structural, not
stylistic:

- `PlayerController._physics_process` contains **zero** network branches. Not
  one. Prediction replay is `simulate_tick()`, which sets `intent_source = null`,
  calls `_physics_process` and puts the source back — the replayed tick is the
  *same function* as the live tick, so a prediction cannot drift from the
  authority by construction rather than by discipline.
- **Exactly one class knows the wire layout.** `grep` for `StreamPeerBuffer`,
  `put_u8`, `decode_u*`, `var_to_bytes` across `scripts/` returns `net_codec.gd`
  and nothing else. Tests touch the size constants only to assert byte budgets.
- Fixed-size storage everywhere on the per-tick path. `WorldSnapshot` holds 8
  `PlayerState` for life; decode writes into them; the receive path allocates
  only the `PackedByteArray` the engine hands over.
- The input stream **is** sequence-numbered. Intents are tick-stamped, the
  authority echoes the last one it *applied* (not received) in
  `PlayerState.last_intent_tick`, and reconciliation rewinds to exactly that
  tick. `intent_redundancy` repeats the previous tick *in addition to* the
  current one on a stream that is already sequenced — it is cheap loss
  concealment layered on a correct design, not a substitute for one. The
  distinction Ryan asked about is decided in the right direction.
- `RemoteIntentSource` is a 4-deep **queue**, not a latest-wins slot, and the
  docstring gives the right reason: latest-wins breaks the arithmetic
  reconciliation depends on, because the client replayed one tick per intent.

### Same concept represented twice

1. **Identity — four names for one player.** `LobbySeat.index` (sparse, 0-7, the
   wire name), `MatchParticipant.index` (dense slot, carried by all 16 `_ev_*`
   messages), `LobbySeat.peer_id` / `PlayerNetLink.owner_peer_id` (the same fact
   stored twice — `_on_seat_occupancy_changed` must write both), and
   `PlayerNetLink.seat_index` (a copy of the first). The seat↔slot map lives only
   in `NetMatch._slot_of_seat`, and before the refactor below it was crossed
   **four different ways** in one file. This is the one genuine structural
   duplication in the codebase.
2. **Role — five representations.** `LobbySeat.role` (opening only),
   `MatchParticipant.is_shooter/is_running/is_ghost/is_finisher`,
   `PlayerController.is_guard/is_armed`, `PlayerState.is_finisher/is_armed` on
   the wire, and the scene-tree groups `prisoners` / `tower_guard`. Each is
   defended in its own docstring and the defences are sound, but a seat change
   writes "what this body is" in five places.
3. **Pose — three.** `PlayerController._sliding/_crouching/is_on_floor()`, the
   `net_slide/net_crouch/net_floor` tri-state overrides, and
   `PlayerState.sliding/crouching/on_floor`. Note the naming asymmetry:
   `is_grounded()` exists as the "read this, not `is_on_floor()`" accessor, while
   `is_sliding()`/`is_crouching()` fold the override into the same name the local
   physics uses. Two conventions for one idea.
4. **Four hand-rolled ring buffers**, each with its own `_start` / `_count` /
   `_slot(i)` trio: `PlayerNetLink._predicted`, `PlayerNetLink._recent_intents`,
   `RemoteIntentSource._buffer`, `NetReplicator._playback`. Individually correct;
   collectively the same twenty lines written four times.
5. **Authority predicates.** `NetTransport.is_authority()` →
   `NetSession.is_authority()` → latched `_is_authority` in both `NetReplicator`
   and `PlayerNetLink` → `NetMatch.is_authority()` → `MatchController._mirror`.
   The latching is deliberate and documented (a state change must not flip a role
   mid-frame). The problem is at the end: `MatchController` runs **two different
   rules under one field** — 26 sites guard on bare `_mirror` ("this machine
   never does this at all") and 5 on `_refuses_local_decision()` ("only while
   replaying the server"). The second rule has a name; the first does not.

### Classes that know the wire layout

`NetCodec`. That is the complete list. **Grade: A.**

### Special-case branches in the hot path

Enumerated honestly, and most are not special cases:

- `NetReplicator._physics_process`: authority/client split (structural), plus one
  early return for `peer_count <= 1` (offline and lone host share a shape).
- `NetReplicator._draw`: three — `lag <= 0 or count == 1`, `to_index == 0`,
  `from_state == null`. All three are genuine edge states of a jitter buffer
  (ahead of the newest, clamped to the back, a body that appeared this snapshot).
- `PlayerNetLink._physics_process`: six early returns. Five are role and
  lifecycle. **One reads like a patch**: `if controller.net_floor >= 0:
  _take_own_footing()` — "mirrored while it was parked, its own physics answers
  for it again". It is correct, but it detects a state transition by sniffing a
  field the *other* code path wrote, rather than being told the body woke up.
- `PlayerNetLink._reconcile`: three bail-outs (`acked < 0`, `first == 0`,
  `predicted.tick != acked`), each a distinct and documented failure mode.
- `PlayerController`: none.

### Fixes that paper over a missing invariant

- **The launch handshake.** `NetLobby` states plainly that there is **no launch
  acknowledgement**. The consequences are a 10 s `READY_TIMEOUT_SECONDS` in
  `NetMatch`, then `_is_bindable_phase` widened to accept `IN_MATCH` (whose own
  comment says "this is the fix rather than an afterthought"), then `_catch_up()`
  to re-send the reliable one-shots a late client missed. Three mechanisms
  standing in for one missing ack. It is the largest piece of compensation in the
  codebase and it is documented as such, which is the right way to owe a debt.
- **`MoveIntent` mixes wire fields with local-only dev fields**
  (`turbo_held`, `godmode`). Because the struct is shared and reused,
  `NetCodec.unpack_intent_at` has to *scrub* two fields it does not carry, with a
  comment explaining that a field the format does not carry keeps whatever the
  last owner put there. The codec is compensating for a struct that should not
  have had those fields on it.
- **Deferral as ordering.** `_publish.call_deferred()` and
  `rpc.call_deferred(&"_ev_seat_to_bot")` both exist because they run inside a
  peer's disconnect signal. Correct, and an ordering invariant enforced by
  timing rather than by structure.
- `_watched_rifles` keyed by instance id, and `rebuild_hub()` removing children
  before `queue_free` so a new `Link0` is not renamed `Link0@2`: both are engine
  facts made explicit, not design debt.

### Grades

| Area | Grade | Why |
|---|---|---|
| Transport | **A** | One interface, two backends, state machine owned by the base class so two backends cannot disagree about "connected"; the unimplemented one is a specification with a refusal attached rather than a half-working stub. |
| Codec | **A** | One file, one format, fixed-size records, validation before every read, size *is* the version; quantisation chosen against a stated error budget rather than by feel. |
| Replication | **A−** | One packet per tick for the whole world, playout clock with measured adaptive jitter buffer and bounded extrapolation; loses a half grade to the decoy being a second per-tick stream with its own version byte and epoch. |
| Prediction / reconciliation | **A** | Replay is literally the same `_physics_process`; rewinds position to the authority and yaw to the player's own record; a snap changes the *view*, not the buffer. |
| Lobby / session lifecycle | **B+** | Authority owns the roster absolutely, clients request and are answered; token-bucket throttle on the reliable broadcast amplifier. No launch acknowledgement, and three mechanisms compensating for it. |
| Hub ↔ match switch | **B** | Genuinely one body path and one snapshot path (`hub_mode` is a flag, not a fork), but the switch is a whole-tree `change_scene_to_file` carrying state in a `static var returns_to_hub`, and a roster change rebuilds every hub body from scratch. |
| Authority / validation | **A−** | Every cheap check is present and in the right layer: the codec refuses malformed and NaN, the link clamps look deltas (because the sane range is a tunable the codec must not know), the seat check is `sender_id == owner_peer_id`. No lag compensation and no movement audit — both acknowledged, both design questions. |
| Tests | **A** | Not assertions about structure: a real UDP socket with ENet's own byte counters, a wire the test owns and drops 5% of, 167 ms RTT with jitter, a 500 ms host hitch. `test_net_authority` tests what the host *refuses*. This is the reason the rest of the grades can be trusted. |

---

## 3. What a clean design would be

For this exact game — 8 players, host-authoritative, 30 Hz, one map, simple
physics — the minimal set is:

**Concepts (6):** peer, seat, body, intent, state, tick.
**Messages (4):** intent up (unreliable, sequenced, redundant); snapshot down
(unreliable, ordered, whole-world, one tick); roster (reliable, whole table);
match events (reliable, one-shot).
**Rules (3):** one authority fixed at host time; one codec; prediction on the
same controller the authority runs.

**The current code is already that.** Not approximately — the concept list, the
message list and the three rules map onto the shipped files one-to-one, and the
things a codebase of this kind usually accretes (a networked movement variant, a
second controller, per-body state packets, a latest-wins input slot, authority
following a role) are all absent, each with a docstring saying why.

Two departures, both small and both named above:

1. **A seventh concept — the participant slot.** The match layer counts dense
   slots; everything else names sparse seats. A clean design would carry the seat
   index into `MatchParticipant` and delete the mapping. That is a real change
   with real risk, and it is not today's job — today's job was to make sure the
   mapping is crossed one way instead of four.
2. **A fifth message — the decoy stream.** Justified (a hologram is a body the
   tower shoots at, so it streams at 60 Hz, not 30) but it is a second wire
   format with its own version byte, its own epoch and its own channel.

Everything else on a "clean design" wishlist — delta compression, interest
management, lag compensation, host migration — is *correctly absent*, and the
review document says so with numbers. At 213 bytes of payload and 134 on the
wire, delta compression buys less than the bug class it introduces.

---

## 4. Refactors done

No behaviour change on the shipped path. `bash tools/test.sh` green before and
after; bot harness clean.

### 1. `NetMatch` — one seat↔slot map

The seat/slot boundary was crossed four ways in one file: the `_slot_of_seat`
dictionary, `_links[who.index]` (array position as slot),
`_lobby.get_occupied_seats()[participant.index]` (position in a *filtered list*
as slot, twice), and `_link_for_seat()`. Added the inverse map `_seat_of_slot`
with `_seat_index_of(slot)` and `_link_of_slot(slot)`, and routed the other three
through them.

This also removes a latent mis-address: deriving a seat from a slot by position
in `get_occupied_seats()` is correct only while that list never shrinks. With the
shipped `fill_vacated_seats_with_bots = true` it does not, so the behaviour is
identical. With that setting off, a player leaving mid-match shifts every later
index, and `_on_participant_shoved` would have sent the shove cue to the wrong
peer while `_on_match_won` reported the wrong winning seat.

### 2. `NetReplicator` — one way to put a snapshot on a body

`_present()` and `_draw_extrapolated(snapshot, 0.0)` computed the identical set
of `(link, state)` pairs by iterating in opposite directions — one over snapshot
bodies calling `find_link`, the other over links calling `find_seat`. Deleted
`_present`; the interpolation-off path is now the zero-seconds case of the
routine playback already uses.

### 3. `NetMatch` — one spelling for the client-replay guard

Sixteen `_ev_*` handlers shared one rule and wrote it four ways: `if
is_authority(): return`, `if not is_authority(): <whole body indented>`, `if not
is_authority() and x.is_finite():`, and — in the three rifle handlers — no guard
at all, relying on `_weapon_of()` returning null on the authority. Introduced
`_replays()` ("this machine replays the server's decisions rather than making
them"); every handler now opens `if not _replays(): return`, and `_weapon_of` no
longer hides a guard inside a lookup.

### Verification

```
bash tools/test.sh
  before: PASS 408 tests, 406 passed, 0 failed, 2 skipped, 4154 checks, 73.0 s
  after:  PASS 408 tests, 406 passed, 0 failed, 2 skipped, 4154 checks, 73.1 s

godot --headless --script res://tools/harness/run_bot_match.gd -- --matches=5
  after:  CLEAN  5 matches, 0 unresolved
```

One thing to flag: **the bot harness is not deterministic run to run**, and it is
not deterministic on `ec1e27a` either. Three baseline runs on the unmodified tree
gave 5/5, 5/5 and 4/5 (one match hitting the 600 s ceiling unresolved), with
different winners and lap times each time from the same `--seed 20260930`. That
pre-dates this branch and is unrelated to these refactors — nothing changed here
is even reachable offline, where no session is established — but it means
"bots 10/10" is currently a flaky bar rather than a gate. Worth a look
separately.

### Considered and not done

- **Collapse the seat/slot identity spaces.** The right fix, too large for a
  no-behaviour-change pass.
- **A shared ring-buffer helper** for the four hand-rolled ones. Speculative:
  they have different element types and two of them have different overflow
  policies.
- **Name the bare `_mirror` rule in `MatchController`.** 26 call sites is a lot
  of churn for a rename, and the two rules there are genuinely different rather
  than duplicated — worth doing deliberately, not as a drive-by.
