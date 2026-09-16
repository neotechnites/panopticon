# Bot sweep: maps 1, 2 and 3

Every number here comes from one run of the headless harness on seed 20260930,
`--compression 60`, ceiling 600 simulated seconds. 150 matches: 20 at the
shipped guard on each map, then 10 each at blind / 0.2 / 0.8. Reproduce any arm
with

```
godot --headless --path . --script res://tools/harness/run_sweep.gd -- \
    --spec=res://tools/harness/sweeps/balance_<map>[_spread].json \
    --matches=<20|10> --seed=20260930
python3 tools/harness/summarise_balance.py tools/harness/runs/<run id>
```

The six specs are `tools/harness/sweeps/balance_{bentham_ring,marble,forest}[_spread].json`.
`summarise_balance.py` prints the table below straight from the result files.

Two columns carry most of the argument and are worth defining. **guard blind %**
is the fraction of a round the guard has no line on anybody
(`stall.guard_blind_fraction`). **first shot (s)** is the mean seconds from a
round starting to the rifle's first shot in it, pooled over every round in the
arm. Together they say how long the ring gives a runner before the tower can
act, and how much of the lap the runner can spend unseen.

An arm at guard_skill 0 shows 0.0 % resolved. That is correct, not a failure: a
match is won by holding the tower through a round, a blind guard never does, so
every match runs to the ceiling. The number that matters there is **runner round
win %**, which must be 100.

## The three maps side by side, shipped guard

| | map 1 bentham_ring | map 2 marble | map 3 forest |
| --- | --- | --- | --- |
| matches | 20 | 20 | 20 |
| resolved | 100 % | 100 % | 100 % |
| median match | 131.8 s | 64.8 s | 39.9 s |
| rounds/match (median) | 3.0 | 1.5 | 1.0 |
| runners win | 78.0 % of rounds | 41.2 % | 13.0 % |
| guard hit rate | 29.1 % | 34.6 % | 51.2 % |
| guard blind | 26.3 % of a round | 4.0 % | 3.1 % |
| first shot | 10.44 s | 1.64 s | 2.29 s |
| hazard deaths | 0 | 0 | 0 |
| clean-run rate | 91.3 % | 95.4 % | 100.0 % |
| cover points baked | 192 | 164 | **1** |
| jump links / pad links | 49 / 7 | 0 / 0 | 0 / 0 |

A match on map 3 is a third the length of one on map 1 and ends in a single
round. The guard's hit rate climbs 29 → 35 → 51 % across the three, and the
runners' share of rounds falls 78 → 41 → 13 %. The two new maps are both harder
on runners than map 1; forest is harder by a wide margin.

## Full matrix

| variant | matches | resolved % | rounds/match (median) | median match length (s) | guard blind % | first shot (s) | hazard deaths | clean-run rate % | guard hit rate % | runner round win % | guard hit% running | strafing | airborne | cover |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| bentham_ring_default | 20 | 100.0 | 3.0 | 131.8 | 26.3 | 10.44 | 0 | 91.3 | 29.1 | 78.0 | 75/256 (29.3%) | 5/36 (13.9%) | 51/193 (26.4%) | 16/21 (76.2%) |
| bentham_ring_blind | 10 | 0.0 | - | - | 76.4 | 36.70 | 0 | 93.3 | 98.0 | 100.0 | 1/1 (100.0%) | - | 2/2 (100.0%) | 45/46 (97.8%) |
| bentham_ring_skill_02 | 10 | 50.0 | 11.0 | 415.3 | 30.9 | 13.30 | 0 | 94.3 | 15.6 | 96.1 | 36/218 (16.5%) | 11/46 (23.9%) | 36/280 (12.9%) | 8/41 (19.5%) |
| bentham_ring_skill_08 | 10 | 100.0 | 1.0 | 49.2 | 27.1 | 7.29 | 0 | 86.5 | 65.2 | 0.0 | 26/40 (65.0%) | 2/2 (100.0%) | 2/4 (50.0%) | - |
| marble_default | 20 | 100.0 | 1.5 | 64.8 | 4.0 | 1.64 | 0 | 95.4 | 34.6 | 41.2 | 77/225 (34.2%) | 0/1 (0.0%) | - | 4/8 (50.0%) |
| marble_blind | 10 | 0.0 | - | - | 70.5 | 28.97 | 0 | 97.9 | 56.2 | 100.0 | 8/23 (34.8%) | - | - | 55/89 (61.8%) |
| marble_skill_02 | 10 | 100.0 | 8.0 | 272.4 | 3.8 | 3.13 | 0 | 100.0 | 17.5 | 85.3 | 82/479 (17.1%) | 1/2 (50.0%) | 0/1 (0.0%) | 5/20 (25.0%) |
| marble_skill_08 | 10 | 100.0 | 1.0 | 39.9 | 1.6 | 0.37 | 0 | 100.0 | 55.6 | 0.0 | 25/45 (55.6%) | 2/6 (33.3%) | - | 3/3 (100.0%) |
| forest_default | 20 | 100.0 | 1.0 | 39.9 | 3.1 | 2.29 | 0 | 100.0 | 51.2 | 13.0 | 62/122 (50.8%) | 1/2 (50.0%) | - | 2/3 (66.7%) |
| forest_blind | 10 | 0.0 | - | - | 84.1 | 31.67 | 0 | 97.0 | 100.0 | 100.0 | 1/1 (100.0%) | - | - | 94/94 (100.0%) |
| forest_skill_02 | 10 | 90.0 | 6.0 | 197.3 | 5.7 | 3.37 | 0 | 89.1 | 19.8 | 87.8 | 115/577 (19.9%) | - | - | 4/23 (17.4%) |
| forest_skill_08 | 10 | 100.0 | 1.0 | 38.6 | 0.2 | 0.41 | 0 | 100.0 | 58.8 | 0.0 | 30/47 (63.8%) | 0/4 (0.0%) | - | - |

A `-` in a by-state cell means the rifle never fired at a target in that state;
an unfired rifle has no hit rate. `-` in the median columns is an arm where no
match resolved.

## The blind-guard bar

Map 1's bar is that a guard with `guard_skill 0` and a one-degree field of view
loses every round and the map kills nobody. Both new maps clear it:

| | runners win | hazard deaths | clean-run rate |
| --- | --- | --- | --- |
| bentham_ring_blind | 100.0 % of rounds | 0 | 93.3 % |
| marble_blind | 100.0 % | 0 | 97.9 % |
| forest_blind | 100.0 % | 0 | 97.0 % |

So the bake and the brain read both new maps correctly in the sense the bar
tests: the runners can finish a lap, and nothing about the geometry kills them
on its own. Nothing was broken in that direction and nothing was fixed for it.

A blind guard still fires occasionally — a one-degree arc is not zero, and a
runner who walks through it is shot at point-blank, which is why those arms show
high hit rates on tiny shot counts (1, 23 and 1 shots at a running target). That
is the arc, not the guard.

## Map 2, marble

Median match 64.8 s over 1.5 rounds, runners take 41.2 % of rounds, guard hits
34.6 %. Against map 1 that is half the match length and about half the round
share.

The reason is sightline, not the drop. The guard is blind 4.0 % of a round
against map 1's 26.3 %, and the rifle's first shot lands 1.64 s into a round
against map 1's 10.44 s. A runner on the marble gallery is visible from the
lodge from the moment the round arms and stays visible almost the whole lap. The
walkway is a clean annulus with nothing standing on it — the map doc says so
outright, "Nothing on the lane" — so the 164 cover points the bake finds are
shadow thrown by the wall's own pilasters and cell reveals at the outer margin,
off the running line. The guard fires 225 shots at running targets across 20
matches and only 8 at a target in cover.

**The gallery drop is not killing anyone: 0 hazard deaths in 50 matches,
including the blind arm where nothing else can kill.** The bots walk the lane
and never step off the open inner edge. As a balance lever the spike floor is
currently inert — it is a threat to a human who panics, and nothing at all to
the AI. Clean-run rate 95.4 %, so the lane itself paths well.

If marble wants map 1's shape, the thing to add is something on the lane that
breaks line to the centre — the guard needs to lose the runner for a quarter of
the lap, and right now he loses him for a twenty-fifth.

## Map 3, forest

Median match 39.9 s, one round, runners take 13.0 % of rounds, guard hits
51.2 %. This is the outlier: the tower wins 87 % of rounds and a match is over
in one.

The measured cause is that the forest lane offers no cover at all. **RingBake
finds one cover point on the whole map** (map 1: 192, marble: 164), and that one
point is the fallen-log fence at 350°. The reason is geometric: every occluder
on map 3 stands in the outer leaf wall at r 57.3 — the twelve forest trunks are
pilasters in that wall — and the guard's eye is at the centre of the ring on the
tree. Shadows from an outer-wall occluder fall radially outward, away from the
lane, so nothing on the wall shades the running line at r 52. Consequently the
guard is blind 3.1 % of a round and hits 51 % of what he shoots at.

Lane width is not the problem; the absence of anything standing *inside* the
lane is. The fix is map content — something on the annulus between r 46.7 and
57.3 that stands between the tree and the runner — and belongs in
`tools/modelling/forest_build.py`, not in the bot code. Clean-run rate is
100.0 %, so the pathing is fine; the runners are simply shot.

Hazard deaths: 0. The bramble pit never fires, for the same reason the marble
spikes never do.

## The guard_skill lever

The lever behaves the same on all three maps and is not a map property:

| guard_skill | runners win (ring / marble / forest) |
| --- | --- |
| 0.0 blind | 100 % / 100 % / 100 % |
| 0.2 | 96.1 % / 85.3 % / 87.8 % |
| 0.5 shipped | 78.0 % / 41.2 % / 13.0 % |
| 0.8 | 0.0 % / 0.0 % / 0.0 % |

0.8 is a wall everywhere — the runners take zero rounds on every map, and a
match is one round and about 40 s. 0.2 is close to unplayable for the tower on
map 1, where half the matches hit the 600 s ceiling and the median is 11 rounds.
The interesting range is between 0.2 and 0.5, and it is much narrower on the new
maps than on map 1: marble and forest go from 85-88 % runner rounds to 41 % and
13 % over that step, where map 1 goes 96 % to 78 %.

## One fix landed during this sweep

`RingBake._sample_cover` was a pure shadow map: any deck the guard's eye could
not see counted as cover, whether or not a runner could ever use it. On marble
that made the spike floor at y −1.0 and the dome at y 33 into 1,673 phantom
cover points — 1,837 baked where 164 were real. It now keeps a shadow cell only
if its 4-connected same-deck patch touches a cell the eye can see; a floor with
no lit border is another room, not cover. The height list is also sorted and
deduped against every accepted deck of a column, closing a latent path where an
unsorted two-deck column could emit its lower deck twice (that path fires on no
shipped map today — the duplicate count was 0 before and after).

Counts, before → after: bentham_ring 196 → 192, marble 1837 → 164, forest
1 → 1. Bake time ring 725 → 309 ms, marble 484 → 190 ms. No map knowledge was
added: the new constants are a float-equality epsilon and four grid neighbour
offsets, and the flood's step tolerance is derived from `AGENT_MAX_CLIMB` and
`AGENT_MAX_SLOPE_DEGREES`. It costs no extra raycasts — the flood reuses the
sight results the first pass already took.

Two tests pin it in `tests/test_runner.gd`:
`test_every_cover_deck_is_one_the_eye_can_see_somewhere` and
`test_the_bake_emits_each_deck_of_a_sample_column_once`. Reverting only
`_sample_cover` fails the first.

**Every number in this document is from after that fix.** It moved the
behaviour on two of the three maps, because it changes which cell is nearest
cover, not only how many exist: map 1 went from 74.0 % to 78.0 % runner rounds
and 124.5 s to 131.8 s median, and forest's 0.2 arm from 82.8 % to 87.8 %.
Marble's arms are bit-identical before and after — its 1,673 phantom points were
already being discarded downstream by the y-tolerance in `nearest_cover_ahead`,
so they cost bake time and memory but never changed a match. Every arm
reproduces exactly on a re-run at the same seed.
