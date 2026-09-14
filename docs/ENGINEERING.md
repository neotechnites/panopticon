# Engineering standard

The reviews found a design here, not the residue of patching one. This page is
that design as rules — not taste. Every agent and Ryan write to it.

## Invariants

- **The host decides.** Authority is peer 1, bound at `host()`, never moved, and
  never following the tower role. `OFFLINE` counts as authoritative, so
  single-player, the harness and the listen server share one code path with no
  "networking is off" branch. Every client→host message derives its seat from
  `get_remote_sender_id()`.
- **One codec knows the wire.** `NetCodec` is the complete list. Size is the
  version. Every decoder length-checks before it reads and leaves output
  cleared, never half-filled.
- **Fixed-size per-tick structs.** `WorldSnapshot` holds its eight
  `PlayerState` for life and decode writes into them. The per-tick path
  allocates nothing.
- **`PlayerController` has no network branches and is the prediction
  function.** Zero. Replay is `simulate_tick()` calling the same
  `_physics_process` the authority runs, so prediction cannot drift by
  construction rather than discipline. Intent arrives through `IntentSource`
  → `MoveIntent`; the controller never reads `Input`.
- **One identity per player.** A body is named by seat. The dense participant
  slot is a debt: cross seat↔slot only through `NetMatch`'s one map, and pay it
  off rather than extend it.
- **Events reliable, state unreliable.** Channel 0 carries the rare one-shots;
  intent, snapshots and hologram motion are unreliable ordered, because a late
  one has been overtaken. No gameplay-critical one-shot rides an unreliable
  channel. An edge that must survive loss is a counter, not a flag.
- **Budgets are tests.** `tests/test_budgets.gd` gates tick cost, retained
  objects and bytes on the wire, and prints every measured number every run.
  A gate catches a change of order, not a target.

## Hot paths

A hot path is the body of `_process`, `_physics_process`, `_integrate_forces`,
or any `tick*` / `_tick*` function. `tools/audit_hotpaths.gd` refuses twelve
things inside one:

1. `get_node(` — resolve the path once, keep the reference.
2. `find_child(ren)(` — a tree walk per tick; cache the node.
3. `get_nodes_in_group(` — allocates; fetch once per frame.
4. `str(` — format only when something is shown.
5. `"…" %` — a format per tick.
6. `"…" + "…"` — concatenation allocates.
7. `= [ … ]` — reuse a member and `clear()` it.
8. `= { … }` — reuse a member, or use a typed class.
9. `Packed*Array(` — resize a member once.
10. `.duplicate(` — take a read-only reference.
11. `.new(` — pool it.
12. `intersect_ray/shape(` — rays are spent through the cover finder's budget.

A trailing `# hot-ok: <reason>` clears one line. The reason is required and
`--list` prints it: an allowlist nobody can read is one that grows.
Allowing a whole file or rule is impossible on purpose. Write the reason for the
next reader — "pooled in `_query`", not "fine".

## Done

- Tests for the change, in the suite.
- `bash tools/test.sh` green: unit suite and hot-path audit both.
- Bot harness clean if you touched bots, match rules or physics.
- Numbers before and after in the report, from an instrument that can see it:
  the harness is a design instrument, `tools/perf/profile_match.gd` on the PC
  the performance one.
- No new concept where an existing one fits. There are six: peer, seat, body,
  intent, state, tick.
- No guards on guards. A fix names the invariant it restores. Three mechanisms
  standing in for one missing acknowledgement is a debt, written down as one.

## Modelling

One contiguous mesh per map, rock only. Mechanics are scene nodes — cover,
traps, pads, the tower. Collision is a purpose-built `-colonly` node inside the
`.glb`; the art mesh is never its own collider. Sections carry their own seeds,
so editing one diffs only that one. The build script is the model; the `.glb` is
output. Render EEVEE in the PC's console session; `--cpu` is twenty times
slower. A build that breaks its contract file is not installed. No debug texture
stands in for shape: if the form is not readable in flat grey, it is wrong.

## Content

No real names, no likenesses. No AI-generated image or audio
assets. Recordings are CC0 only, logged in `assets/audio/LICENSE.md` with id,
author and date. Ryan does the foley.
