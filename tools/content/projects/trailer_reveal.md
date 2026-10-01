# trailer_reveal
kind: trailer
aspect: 16:9
format: Steam reveal trailer, ROUGH CUT for structure (one take per shot, first usable take kept)
ryan: "Make a ROUGH CUT of PANOPTICON's reveal trailer so Ryan can get a read on the structure. Not final quality -- speed over polish."
rules: 16:9 1920x1080 (SIZE=1920x1080 shot.sh), no HUD except the guard's scope, under 45 s, no voice, no text but the title and end cards, SR20DET as the bed, game SFX off.
v2 notes (Ryan on rough_v1): the guard stands at the tower's window, not deep inside; all runners run the course direction; the runner shot is the SAME event as the guard shot (same stage, same seed, two POVs), cut back ~1 s to the man directly behind the victim; clear line of sight when he looks up at the tower; title drops in HARD on the music's drop; music https://www.youtube.com/watch?v=OBPV0lsorwU; real-looking gameplay only (walkable deck and real cover, nobody on lava, nobody looking backwards); max 4 players a shot (1 guard + 3); spread across hell, forest and marble. Added: "EVERY shot is first-person POV -- either the guard's scope/tower view or a prisoner's first-person view. No third-person ... Title/end cards are the only non-POV frames."
music: external\src\music_v2_OBPV0lsorwU.mp4 -> voice\sr20det.ogg (SOURCES.md). The drop: 0.35 s of silence from 5.36 s, the hit at 5.703 s (sample onset); 170 bpm after it (v3 measured).
cards: cuts/title_hard.mp4 is v1's title frame looped from frame 0 (v1's title.mp4 opened on two black frames); cuts/end.mp4 is v1's.
delivery: content\trailer_reveal\final\rough_v4.mp4 (and ~/Desktop/panopticon-renders/trailer_reveal/)
tag: rough_v4
size: 1920x1080
v4 (Ryan): "every shot must be exactly reproducible in engine -- run a script and record"; NO CROUCHING anywhere; max 3 prisoners + guard; guard shots on the projectile rifle (led, held over). Every shot plays a TAPE (tape: line): the staged take recorded once, then every input played back -- see ## reshoot.


## 1
said: v4 "Hell, guard POV from the window: zooms in, fires at the middle runner (keep v3 a1 event)"
capture: --shot=s3_open_lane --stage=trailer_open --pov=guard --hud=crosshair --bots=3 --rifle=projectile --set=fire_at=3.24 --seed=20261001
tape: open
seconds: 4.0
in: 0.9
freeze: waive
# hell S2 inner lane; guard at the 115 deg window; zoom at take 1.9; squeezed 3.25, lands 3.60 (victim Runner_2)

## 2
said: v4 "Hell, the same event from the runner behind: the man ahead drops, he looks up at the tower (keep a2)"
capture: --shot=s3_open_lane --stage=trailer_open --pov=runner --bots=3 --look=social --rifle=projectile --set=fire_at=3.24 --seed=20261001
tape: open
seconds: 5.0
in: 0.9
freeze: waive
# the open tape down Runner_3's eyes, 2.5 m behind the victim; hit at take 3.60, the look up from 3.92

## 4
said: v4 "Forest, runner POV running between trees (h1)"
capture: --map=forest --shot=pack_lead --stage=trailer_forest_pack --bots=3 --pov=runner --look=social --rifle=projectile --set=fire=3.15 --seed=20261001
tape: forest_pack
seconds: 5.0
in: 0.9
freeze: waive
# forest 14-40 deg between the lane trunks, the tail 2.2 m behind the victim; hit at take 3.55

## 5
said: v4 "Forest, guard scope: the kill (h2)"
capture: --map=forest --shot=pack_lead --stage=trailer_forest_pack --bots=3 --pov=guard --hud=crosshair --rifle=projectile --set=lift=1;fire=3.15 --seed=20261001
tape: forest_pack
seconds: 5.0
in: 0.9
freeze: waive
# the forest_pack tape down the scope; zoom at take 2.0, squeezed 3.15, lands 3.55

## 11
said: v4 "Hell, lake platforming (t2)"
capture: --shot=lava_parkour --stage=lavaparkour --bots=3 --set=line=3 --pov=runner --look=social --seed=20261001
tape: lake
seconds: 5.5
in: 1.2
freeze: waive
# hell S5 lake: three hopping the platforms, bodies only on the platforms and banks

## 12
said: v4 "Marble, corridor -> portal -> rifle -> shooting the guard, white frame (g1)"
capture: --map=marble --shot=portal --stage=trailer_finish_marble --bots=2 --pov=runner --look=social --rifle=projectile --seed=20261001
tape: finish
flash: 4.19 0.045
seconds: 5.0
in: 0.9
freeze: waive
# corridor sprint from 320 deg; armed in the tower at 2.85; the kill beat 4.19 (the white frame); seat change 5.38 (cut before it)

## reshoot
# Every shot is a stage (tools/capture/stages/) played from its tape (tools/content/projects/trailer_reveal/tapes/<tape>.json):
# seed, map, rifle, spawns, every body's intent per physics tick, every outside write (place, launch, the guard's aim
# and zoom) and every trigger pull, at 60 ticks/s, brains off. Change a texture, model or animation and reshoot: the
# same bodies, paths, inputs, timing, camera and shots. A tape is only re-recorded when the action itself changes.
#   one shot:      tools/content/shot.sh trailer_reveal <id>          (e.g. 1, 5b, 10b; cuts\<NN>.mp4 on the PC)
#   every shot:    tools/content/reshoot_all.sh trailer_reveal         (sync, every shot, assemble rough_v4, dailies, copy to the Mac)
#   new action:    edit the stage, tools/content/tape.sh trailer_reveal <id>, commit the tape, reshoot

## script
size: 1920x1080
music: voice/sr20det.ogg
music_db: -3
music_fade: 0.02 2.5
captions: none
# a1+a2 = 5.70 s: the title cuts in on the drop at 5.703 s. cuts/09f.mp4 is 09 with a white frame 3.30-3.345 (the kill beat, take 4.20).
# v3 tail on the beat grid: 170.0 bpm, beat k at 5.716 + k*0.35294 s (librosa percussive onsets, kicks on integer k);
# g1 ends on k61 (27.25), cuts every 2 beats to k77 then every beat, the end card hard on k81 (34.30), the
# strongest accent (every 8th beat from k73). Lengths are the frame-rounded beat boundaries.
# cuts/end_v3.mp4 is end.mp4 without "1-8 players" (Wishlist on Steam moved up into its line); in at 0.4, past the fade.
| line | clip | in | len | fit | speed | text |
| a1 | cuts/01.mp4@0.35:2.70 | | | beat 2.70 | | |
| a2 | cuts/02.mp4@1.70:3.00 | | | beat 3.00 | | |
| a3 | cuts/title_hard.mp4@0:1.5 | | | beat 1.5 | | |
| h1 | cuts/03.mp4@0.9:1.7 | | | beat 1.7 | | |
| h2 | cuts/04.mp4@1.6:1.5 | | | beat 1.5 | | |
| d1 | cuts/05.mp4@0.4:2.4 | | | beat 2.4 | | |
| d2 | cuts/06.mp4@2.0:2.1 | | | beat 2.1 | | |
| d3 | cuts/05.mp4@4.5:2.2 | | | beat 2.2 | | |
| d4 | cuts/06.mp4@5.2:2.0 | | | beat 2.0 | | |
| t1 | cuts/07.mp4@0.2:2.4 | | | beat 2.4 | | |
| t2 | cuts/08.mp4@1.0:2.6 | | | beat 2.6 | | |
| g1 | cuts/09f.mp4@0.6:3.15 | | | beat 3.15 | | |
| c1 | cuts/14.mp4@1.45:0.7 | | | beat 0.7 | | |
| c2 | cuts/17.mp4@1.0:0.7 | | | beat 0.7 | | |
| c3 | cuts/16.mp4@1.25:0.7167 | | | beat 0.7167 | | |
| c4 | cuts/15.mp4@1.25:0.7 | | | beat 0.7 | | |
| c5 | cuts/18.mp4@1.5:0.7 | | | beat 0.7 | | |
| c6 | cuts/13.mp4@2.23:0.7167 | | | beat 0.7167 | | |
| c7 | cuts/15.mp4@2.52:0.7 | | | beat 0.7 | | |
| c8 | cuts/17.mp4@3.0:0.7167 | | | beat 0.7167 | | |
| c9 | cuts/16.mp4@3.47:0.35 | | | beat 0.35 | | |
| c10 | cuts/18.mp4@3.5:0.35 | | | beat 0.35 | | |
| c11 | cuts/13.mp4@3.0:0.35 | | | beat 0.35 | | |
| c12 | cuts/15.mp4@3.95:0.35 | | | beat 0.35 | | |
| e1 | cuts/end_v3.mp4@0.4:3.2 | | | beat 3.2 | | |
