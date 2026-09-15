# Stages: staged action for a clip, by numbers

Everything in a short is staged. Bodies are placed at explicit ring-polar
coordinates (`x = cos(deg) * r, z = sin(deg) * r`, deck y = 23, heights over
the deck) and driven by hand through a list of steps; the tower is a dial;
the lens is a number. Nothing here is reachable from a match.

```
run_clip.gd --stage=NAME ...        NAME.gd here is a plugin; else a stage in stage_driver.steps_for
stage.gd            the plugin base: bots(), tune_rules(), tune_shooter(), before_start(),
                    cast(runners), tick(), lens(), on_shove/on_shot/on_hit/on_out
lib.gd              ring_point/tangent_at/radial_at/polar, the tower's dials
                    (dead_shooter, quick_shooter, dead_eye_shooter, set_trigger,
                    stand_down, watch), disarm_pads/disarm_traps, hide_from_the_rifle,
                    show_only_the_crosshair, open_the_scope
guard_hand.gd       the guard's head as a hand on a mouse: eased arcs with an
                    overshoot and settle, a tracking beat that leads the runner,
                    breathing sway that dies before the squeeze, the shot, recoil
probe_ring.gd       headless: --clear (pad/trap-free stretches), --floor, --pads,
                    --los=deg:r:h;..., --heights, --aabb. Runs on the Mac.
```

## The primitives (`../stage_driver.gd`)

`place` (at / deg,r,h), `hold` (crouch, sway, fidget), `until` (a timed beat on
the driver's clock: "shove at 8.00 s"), `hesitate`, `run` / `lane` (speed, weave,
hop, dir, look_at, glances), `leap` / `land`, `wait_launch`, `chase`, `shove_when`,
`shove` (now, turned to a facing), `face_hold`, `advance`, `brawl` (a scrap with a
safe zone), `ability`, `turn` / `glance` / `pitch`, `look_back`, `flinch`,
`wait_flag` (shot / hit / shove / miss), `steer`, `human`, `slowfeet`, `release`.

The human layer (`{"do": "human"}`): mouse drift (a seeded random walk on the
look), every timed turn a flick that overshoots and settles, a wavering walk,
strafe shuffles on holds, hesitation, look-back, flinch; running steps take a
`glances` schedule chased by an underdamped spring, with `flinch_on: "hit"`.
Per-body timing is seeded from the take seed and the body's index
(`seed_with`), so a group never moves in lockstep.

## The plugins (the shove short, as examples)

| stage | shot | bots | the beat |
|---|---|---|---|
| `pack_sniped` | `pack_lead` (+ `--pov=runner`) | 5 | a pack of five, the tower drops one at 3.0 s; POV glances and a flinch |
| `guard_alone` | `s3_open_lane --pov=guard --hud=crosshair` | 4 | the hand drops three runners 10 m apart, one beat each |
| `faceshove` | `s3_face_side` / `s3_face_over` (+ `--pov=runner`) | 2 | two trading shoves every 1.15 s; a tracking, zooming lens |
| `cover_both` | `cover_side` | 3 | crouched behind the rock; a runner crosses and is sniped; a shove out of cover; sniped standing |
| `melee` | `s3_melee` | 5 | five brawling, seeded cadences, safe-zone throws, a chase lens |
| `conga` | `rim_side` | 7 | a creeper, the shove on the beat, five more up the line every 1.4 s |
| `lavaparkour` | `lava_parkour` (+ `--pov=runner`) | 4 | four hopping the seven S5 platforms; a chase lens; the POV stumbles once |

Each file's header carries Ryan's words for the shot, the exact capture line,
the cut, why every number is what it is, and its `--set=` dials. The first
four beats of the short (`shovecatch`, `shovecover`, `shoveedge`,
`shoveedge_look`, `shovelake`) live in `stage_driver.steps_for`.

## Writing a new one

1. Probe first: `probe_ring.gd -- --clear --pads` for ground nothing launches
   or kills a body on; `--los` for what the tower sees; `--heights` for the
   deck under a spot. Quote the numbers in the file.
2. Copy the nearest plugin. `cast()` places every body and hands out drivers;
   nothing is left to a brain. Bodies that must not be shot yet leave the
   rifle's group; the tower is `dead_shooter` until the beat, then
   `set_trigger`. Beats are `until` steps, not chases that arrive.
3. Smoke it headless on the Mac: `godot --headless --path . --script
   res://tools/capture/run_clip.gd -- --shot=X --stage=NAME --bots=N
   --seconds=S` and read the `[event]` lines: the shove, the hit, who died and
   where. `STAGE_DEBUG=1` prints every step as it finishes. Only then film it
   on the PC (`tools/content/shot.sh`).
4. Cut after the deal: bodies are placed at 0.6 s; the cut starts at `in:`
   0.9-1.8 s so nothing spawns in frame.
