# 20 shorts to test

A menu, not a plan. Ryan picks one, directs it shot by shot, and the brief
records what he said. Each line: the one-liner, the beats, the capture stage it
needs, and what it tests (hook type, POV, length). No hashtags, no title cards;
a caption is the one line a player would type.

## Crazy clips (framed as a clip that just happened in a game)

1. **bro would not die.** The guard from his own scope, eight shots at one runner
   who just keeps strafing and hopping on the open deck; cut to the runner's view,
   not even looking up. Stage `missstreak`, guard POV then runner POV. Tests: the
   fail-hook, POV cut, 10 s.
2. **mid-air shove into the lava.** From the S2 bank: the runner takes the boulder
   chain, a second prisoner on the next landing shoves him at the apex, he goes
   into the river. Caption "he was so close". Stage `shovecatch`, `s2_gap` then
   runner POV. Tests: the betrayal hook, third-person, 8 s.
3. **the ghost took his spot.** Same shove, but by a ghost: the runner freezes
   mid-air, the ghost is alive in his place. Stage `ghostcatch`. Tests: whether
   the swap reads without explanation, 6 s.
4. **it shot the hologram.** Runner crouched behind the pillar throws the decoy out
   into the open; the guard's scope swings onto it and fires; the runner stands
   up and walks. Stage `decoy`, `s3_pillar` then guard POV. Tests: the misdirect
   hook, two POVs, 12 s.
5. **three pads, no cuts.** One runner's view through the S3 demon pads back to
   back, real speed, HUD on. Stage `padflight`, runner POV. Tests: the speed hook,
   no edit, 8 s.
6. **he just walked into it.** A runner at full sprint hops off the S4 ledge
   straight into the lava, from the deck edge. Caption "why". Stage `lavadeath`,
   `s4_edge`. Tests: the dumb-death hook, 5 s.
7. **the guard blinked.** Guard POV holding the scope on a runner behind a spire;
   the runner steps out the moment the reload bar hits zero and is gone before
   the shot. Stage `firefight` + `--pov=guard` on `scope_hunt`. Tests: the tension
   hook, one POV, 9 s.
8. **seven prisoners, one bullet.** Overhead-ish lap (`teaser_lap`) while the
   tower snap-shoots; count the bodies. Stage `firefight`, 7 bots. Tests: the
   scale hook, cinematic camera, 8 s.
9. **the eye follows you.** `pit_orbit` slow lap; the tower's eye turns to meet
   the camera as it stops. No stage. Tests: the creep hook, 8 s, no caption.
10. **the chain at 1x.** The full S2 boulder chain from the runner's eyes,
    landing by landing, no music. Stage `chainrun`, runner POV. Tests: the
    "can you do this" hook, 12 s.

## "In my game I added X" (Ryan's voice, the mechanic in one sentence)

11. **I added a hologram decoy.** Third-person throw, guard POV shot, runner POV
    walk; 3 s gap after the shot for "so I added a decoy and the guard falls for
    it every time". Stage `decoy`. Tests: the mechanic-reveal format, voice gap,
    15 s.
12. **I made the guard human.** Same runner, two takes: the shipped guard and the
    sloppy one, back to back, guard POV. Stage `missstreak` vs `firefight`.
    Tests: a before/after within one short, 14 s.
13. **I added a shove.** Deck angle of the S2 shove, then the same from the
    victim's eyes. Stage `shovecatch`, `s2_gap` + runner POV. Tests: two angles of
    one beat, 10 s.
14. **ghosts catch, not touch.** The ghost swap explained by showing it: shove,
    freeze, swap. Stage `ghostcatch`, 3 s gap for one sentence. Tests: whether a
    rule can be shown in 8 s.
15. **the guard has a reload bar and everyone can see it.** Guard POV reload,
    cut to a runner sprinting across the open while it fills. Stage `missstreak`,
    guard POV + `s3_open_lane`. Tests: HUD-as-mechanic, 10 s.
16. **the lava is a texture, not a trap.** Walk to the S5 lake lip and tilt up
    the lava fall (`lake_fall`), then a runner dying in it (`lavadeath`). Tests:
    the art hook next to the rule, 12 s.
17. **demon pads on islands.** `pad_flight` third-person: the pad throws the bot,
    the bot lands and keeps running. Stage `padflight`. Tests: a mechanic with no
    words at all, 8 s.
18. **before / after: greybox to hell rock.** Two stills from `tools/shot.gd` at
    the same pose, hard cut, 3 s each. `still:` entries with `at: <old commit>`.
    Tests: the transformation hook, stills only, 6 s.
19. **the scope's own view.** `scope_hunt` path zooming from the wide sweep into
    the scope on a runner in the spires; 3 s gap for "the guard sees this".
    Stage `firefight`. Tests: a camera move as the hook, 12 s.
20. **one guard, everyone else runs.** `teaser_lap` full lap, stop, turn to the
    tower; voice over the last 3 s only. No stage. Tests: the premise in one
    sentence, cinematic, 11 s.
