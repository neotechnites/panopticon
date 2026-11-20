# The bot-guard aim test stall

`tests/test_regress_aim.gd::test_a_bot_guard_aims_out_of_its_own_tower_hell_*` sometimes ran into the
runner's 90 s per-test timeout. It is a game bug: under catch-and-swap ghosts, a round can livelock.

## What was ruled out

- **Leaked state from earlier tests.** The stall reproduces with no earlier test at all: a file holding
  only copies of the hell match (`--only`) stalled 2 times in 115 matches. About 2% a match, over the
  file's five hell matches, is roughly one suite run in twelve: "sometimes". Three full-suite runs in
  order were clean (15 hell matches).
- **The playout clock against fixed-step physics.** A match runs at a flat 0.52 s of wall per 10 s of
  play, slower only in bursts that hit all four parallel processes at once (machine load). The stalled
  matches kept advancing physics frames at that same rate, so the clock is not involved.

## The cause

Hypothesis 2. Instrumented, a stalled match is round N with one live runner hiding in a cover point the
tower cannot see (hell, about (23.3, 23.0, 45.7)), two bot ghosts, and the guard scanning with no target.
41 catches in 193 s; no shot for the rest of the match.

1. A runner in cover is bounded by `cover_patience_seconds` (3 s), then leaves. The patience is meant to
   guarantee the run moves on.
2. A ghost catches it there. The catch keeps the run (arc, level) but `RunnerBrain.resume` starts a fresh
   brain, so the incoming prisoner, exposed and assuming it is watched, takes the nearest cover ahead, the
   same point, with its patience clock at zero.
3. Two ghosts, each back from the start in about 3 s hold + 1.6 s run, arrive on average every ~2.3 s,
   inside the 3 s patience. In the one trace where the patience did run out, the runner was caught 0.1 s
   out of the cover and the incoming one took the same cover again.

The guard cannot see the point, a catch never changes the live count, and the round has no time limit (by
design, deferred in `MatchRules.round_time_limit_seconds`), so the round never ends. The test's own bound
(3600 s of play) is longer than the runner's 90 s wall, so it shows as a timeout.

This is a real game hang. Any round where the last runner is a bot that hides there and the ghosts are
bots plays forever.

## The fix

A catch changes who is alive and nothing else (the rule `_swap_with_ghost` states). The bot's cover is part
of the run, like the arc the tracker already hands over with `adopt_progress`:

- `RunnerBrain.get_cover_hold()` gives the caught run's cover: the point and the seconds held, or the point
  it last left. `_swap_with_ghost` reads it before the chase resets the caught brain and passes it through
  `_start_running_in_place` to `resume`.
- The incoming brain keeps holding that point with the time already held, so patience bounds the hiding
  across any number of catches.
- A run never takes the cover it last left again (`_find_cover` treats it as taken). The incoming prisoner
  is told which one that is.

Fail-first tests in `tests/test_ghosts.gd`: `test_a_bot_caught_in_cover_hands_over_the_time_already_held`
and `test_a_bot_caught_leaving_cover_does_not_take_it_again`. Both failed before the fix and pass after it.

## After

175 hell matches with the same stall detector (60 s of play without a shot), none stalled, against 2
in 115 before.
