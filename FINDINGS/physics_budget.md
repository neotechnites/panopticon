# Physics budget (B2) on demo/rc 0d637cc7

## Verdict

No commit in the range regressed the physics tick. The 21.23 ms reading is the
machine, not the game. B2 measures wall clock between ticks, so any tick the OS
gives to another process, or runs on one of the M4 Pro's four efficiency cores,
counts as game cost. A load average under 6 does not rule this out on an 8 P-core
machine.

## Bisect

Load stayed between 7 and 28 from 11:50 to 13:00, so the brief's "load under 6"
condition was never met (other agents were running suites in wt/rc and
wt/aimstall). I used a measurement that holds up under contention instead:
`tools/perf/profile_physics.gd` (the same window and sampler as B2), run 6 times
per commit, interleaved. For each tick I took the least cost over the 6 runs.
Stolen time only ever adds, so that least cost is the game's own cost for the
tick.

| commit | per-tick least: avg | worst (2nd) | B2 statistic of each raw run, ms |
|---|---|---|---|
| 9f420fc3 | 1.234 | 4.81 | 5.2 9.1 5.4 9.8 44.8 9.7 |
| 609b71e0 | 1.237 | 4.83 | 5.3 6.9 6.1 6.6 9.8 14.9 |
| 975b4b55 | 1.261 | 4.97 | 15.7 5.2 13.1 5.3 5.0 13.1 |
| 3e214877 | 1.254 | 4.90 | 5.3 7.7 17.4 11.2 7.5 15.6 |
| fa352dec | 1.253 | 4.93 | 5.5 6.4 6.8 6.7 27.8 6.0 |
| 0d637cc7 | 1.256 | 4.87 | 8.8 18.4 15.4 9.3 6.5 5.3 |

The baseline 9f420fc3 reads 44.8 ms on one run under the same load. Every
commit's real worst tick is 4.8-5.0 ms. In every commit it falls on the same
ticks (8 and 84).

## Profile of the worst tick

I wrapped every `_process` and `_physics_process` in a scratch copy and logged
the cost of each function on the six worst ticks. The real tail, about 5 ms, is
`PlayerController.move_and_slide`: eight bodies bunched on the opening race
against `MapBaseS1Collision`, 0.5-1.4 ms each. It is the same at the base commit
and at rc. On spike ticks, a single `move_and_slide` call on flat floor reads
6-13 ms in one run and 0.8 ms at the same place and tick in another, which is
preemption. None of the suspects shows up in the tail:
- the stance shapes and history, the fractional rewind and the host drawing all
  run only in a session, and the budget match is offline
- `pc.pads` (the ternary pad search) averages 0.14 ms per tick
- power step: 0.01 ms
- match step: 0.01 ms

## Fix

The cause is the instrument, so the fix is in the instrument. The budget numbers
are untouched. `tests/test_budgets.gd` now runs the seven-bot window three times,
each on a freshly built match. B1 and B2 gate on the least of the three, which is
the standard min-of-N benchmark estimator: noise only adds, so a real regression
raises every window and still fails. B3 gates on the most of the three. Every
window's numbers are printed.

## B2 before and after, same load (7.5-9.4), interleaved

- Before (0d637cc7): 8.34, 4.70, 8.60 ms (2 of 3 fail)
- After (demo/perf): 5.01, 4.66, 4.94 ms (B1 1.342, 1.274, 1.277)
