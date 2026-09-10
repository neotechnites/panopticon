# Bot harness result schema

Two files come out of a run, both JSON, both written by
`scripts/harness/bot_harness.gd`. Every field below is produced by the harness
today; nothing here is aspirational.

A run writes to `<--out>/<run id>/`, where the run id is
`YYYYMMDDTHHMMSS-<variant>` for a single-arm run and `YYYYMMDDTHHMMSS-sweep`
otherwise.

---

## `match_<variant>_<NN>.json` — `panopticon.bot_match.v1`

One per match.

| field | type | meaning |
| --- | --- | --- |
| `schema` | string | `panopticon.bot_match.v1` |
| `variant` | string | which arm of the sweep this was |
| `match_index` | int | 0-based index within the arm |
| `seed` | int | the aim-RNG seed **this match** played on (`run seed + index * 7919`); 0 means the run asked for entropy and the match is not reproducible |
| `engine` | string | Godot version string |
| `recorded_at` | string | UTC, `YYYY-MM-DD HH:MM:SS` |
| `status` | string | `RESOLVED` (somebody won) or `UNRESOLVED` (hit the tick ceiling) |
| `unresolved_reason` | string | empty when resolved; otherwise the ceiling, the phase and the round it stopped in |
| `rules` | object | every exported field of the `MatchRules` played, by reflection, plus a `<field>_name` string for each enum |
| `outcome` | object | see below |
| `duration` | object | see below |
| `participants_total` | int | players in the match |
| `rounds` | object | see below |
| `seat` | object | see below |
| `shots` | object | see below |
| `conversions` | int | runners the rifle took out of a round, over the whole match |
| `participants` | array | one object per player, see below |
| `result_path` | string | absolute path of this file |

### `outcome`

| field | type | meaning |
| --- | --- | --- |
| `winner_index` | int | match order of the winner, `-1` if unresolved |
| `winner_name` | string | display name |
| `winner_kind` | string | `AI` or `HUMAN` |
| `winner_role` | string | `TOWER`, `RUNNER` or `NONE`. **Always `TOWER` on a resolved match under the shipped rules** — a match is won by holding the tower through a round and by nothing else. Read from the match rather than assumed, so it starts saying `RUNNER` on its own the day a runner win condition ships. |
| `final_phase` | string | `MatchController.Phase` name at the moment the harness stopped watching |
| `final_round_outcome` | string | `MatchController.Outcome` name |

### `duration`

| field | type | meaning |
| --- | --- | --- |
| `simulated_seconds` | float | in-game seconds: `physics_ticks / 60` |
| `physics_ticks` | int | ticks the match ran. The authoritative clock |
| `tick_ceiling` | int | the ceiling this match was given |
| `wall_seconds` | float | real time the match cost |
| `compression_achieved` | float | `simulated_seconds / wall_seconds`. Compare against `--compression`: a large gap means the host could not retire the ticks, which costs wall clock and changes nothing about the match |

### `rounds`

`race_ran` (bool), `started`, `resolved`, `shooter_wins`, `shooter_losses` (ints).
A *shooter loss* is a lost seat, not a lost match.

### `seat`

`changes` — every time the tower changed hands, including the grant that ends
the opening race. `changes_in_rounds` — those of them somebody ran a lap for,
which excludes the opening grant of a raceless match and excludes a shooter
staying on after winning a round.

### `shots`

`fired`, `hit_participant`, `hit_world`, `hit_nothing`, `hit_rate`
(= `hit_participant / fired`, and `0.0` when nothing was fired — an unfired
rifle has no hit rate).

### `participants[]`

| field | meaning |
| --- | --- |
| `index`, `name`, `kind` | identity |
| `turns_in_tower` | the match's own turn count, which is what the reload escalation is computed from |
| `seat_takes` | times granted the tower |
| `rounds_won` | rounds held from the tower |
| `ticks_in_tower`, `seconds_in_tower` | time holding the tower |
| `shots_fired`, `shots_hit`, `hit_rate` | this player's shooting, all of it taken from the tower — there is one rifle and it belongs to the seat |
| `times_converted` | times the rifle took them out of a round |
| `laps_finished` | laps completed, each of which took the tower off somebody |

---

## `sweep.json` — `panopticon.bot_sweep.v1`

One per run, however many arms it had.

Top level: `schema`, `run_id`, `recorded_at`, `engine`, `seed` (the RUN seed),
`seed_stride`, `matches_per_variant`, `matches_total`, `unresolved_total`,
`max_simulated_seconds`, `time_compression_requested`, `wall_seconds`,
`output_directory`, `sweep_path`, and `variants`.

Each entry of `variants`:

| field | meaning |
| --- | --- |
| `variant`, `notes` | the arm and the question it was asked |
| `rules` | the full rules object, as above |
| `matches`, `resolved`, `unresolved` | counts. `resolved + unresolved == matches` |
| `tower_wins`, `runner_wins` | resolved matches by winning role |
| `seconds_median`, `seconds_mean`, `seconds_min`, `seconds_max` | simulated duration **of the resolved matches only**. An unresolved match sits at the ceiling by construction and would pull an average towards the ceiling rather than towards the truth |
| `rounds_median`, `seat_changes_median` | resolved matches only, same reason |
| `shots_fired`, `shots_hit`, `hit_rate` | across every match in the arm, resolved or not |
| `winner_counts` | winner name → matches won |
| `simulated_seconds_total`, `wall_seconds_total` | cost of the arm |

---

## What lands in the database

`tools/harness/ingest_results.py` writes one `playtests` row per sweep arm:
`kind` is always `BOT`, `guards` is always 1, `prisoners` is the arm's
`prisoner_count`, `matches` counts **every** match including unresolved ones,
`guard_wins`/`prisoner_wins` come from `tower_wins`/`runner_wins`,
`seconds_median` is the arm's median, `footage_path` is the result file, and
`verdict` is empty unless `--verdict` says what the run settled.

`guard_wins + prisoner_wins` is allowed to come out below `matches`. The
difference is the unresolved matches, and it is meant to be visible in the row.
