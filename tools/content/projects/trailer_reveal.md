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

## 5b
said: v4 "Marble, guard POV scoped in, tracking runners"
capture: --map=marble --shot=pack_lead --stage=trailer_marble_track --bots=3 --pov=guard --hud=crosshair --rifle=projectile --seed=20261001
tape: marble_track
seconds: 2.2
in: 1.6
freeze: waive
# guard at the 126 deg window, scope in at take 0.8 on the lead, swings back to the man behind at 2.4; three past the stage-spawned column run 1.7-3.7; no shot

## 6
said: v4 "Hell, runner POV behind a rock, peeking out -- standing (d1, re-filmed without crouch)"
capture: --shot=cover_side --stage=trailer_duel2 --bots=1 --pov=runner --look=social --rifle=projectile --seed=20261001
tape: duel
seconds: 7.5
in: 1.0
freeze: waive
# standing at 68.8 deg r 50.6 behind the pocket lip wall (hidden from the 70 deg window at h 1.0-1.8); out in the open 2.9-4.3; breaks 5.55

## 7
said: v4 "Hell, guard scope holding on that rock; the shot hits rock (d2)"
capture: --shot=cover_side --stage=trailer_duel2 --bots=1 --pov=guard --hud=crosshair --rifle=projectile --seed=20261001
tape: duel
seconds: 7.5
in: 1.0
freeze: waive
# the duel tape down the scope at the 70 deg window: squeeze 4.38, the round hits MapBaseLip066Collision at 4.72

## 8
said: v4 "Hell, runner POV breaking cover and sprinting (d3 -- Ryan: \"perfect\", keep its framing)"
capture: --shot=cover_side --stage=trailer_duel2 --bots=1 --pov=runner --look=social --rifle=projectile --seed=20261001
tape: duel
seconds: 2.2
in: 5.5
freeze: waive
# v3 d3 (05.mp4@4.5 = take 5.5): breaks 5.55, sprints r 49 from ~6.2

## 9a
said: v4 "Forest, runner POV shoving another runner off the inner edge into the pit"
capture: --map=forest --shot=pack_lead --stage=trailer_forest_pit --bots=3 --pov=runner --look=social --rifle=projectile --seed=20261001
tape: forest_pit
seconds: 2.2
in: 1.35
freeze: waive
# the victim cuts to the lip at 151.6 deg between the lip trunks; the shover comes up outside him and shoves at 2.45 (152.8 deg r 48.0), then looks down; a third stops at r 48.9

## 9b
said: v4 "Forest, the shoved runner's POV falling into the pit through the mist, watching the others above"
capture: --map=forest --shot=pack_lead --stage=trailer_forest_pit --bots=3 --pov=runner --look=social --rifle=projectile --set=pov=victim --seed=20261001
tape: forest_pit
seconds: 2.2
in: 2.25
freeze: waive
# the forest_pit tape down Runner_1: shoved 2.45, through the mist (y -5.75..-11.6), out at the floor 4.42; the forest kills at y 0 (above the mist), so this stage lowers its KillBox to the floor for the shot only (floor_kill=1; map unchanged)

## 10a
said: v4 "Marble, runner POV behind a column on the inner edge, shoves the runner beside him out of cover; cut BEFORE the shot"
capture: --map=marble --shot=pack_lead --stage=trailer_marble_column --bots=2 --pov=runner --look=social --rifle=projectile --seed=20261001
tape: marble_column
seconds: 2.2
in: 1.6
freeze: waive
# columns spawned by the stage (marble_column.glb, r 47.5, 116.4-135.6 deg; maps/marble/marble.tscn untouched); shove 3.00 at 126.0 deg, lands in the gap 3.40; the cut ends 3.72, before the squeeze at 3.87

## 10b
said: v4 "Marble, guard scope, a beat earlier: sees him pushed out from the column, fires, hits"
capture: --map=marble --shot=pack_lead --stage=trailer_marble_column --bots=2 --pov=guard --hud=crosshair --rifle=projectile --seed=20261001
tape: marble_column
seconds: 2.2
in: 2.6
freeze: waive
# the marble_column tape down the scope at the 126 deg window: shove 3.00, squeeze 3.87 (lead 0, 0.45 s after he lands), hit 4.22

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

## 13
said: v4 "Hell S3, runner POV running through and bouncing on a crack"
capture: --shot=s4_edge --stage=trailer_crack --bots=2 --pov=runner --look=social --rifle=projectile --seed=20261001
tape: crack
seconds: 2.2
in: 1.7
freeze: waive
# behind the 139 deg lip rock, breaks across the gap at 2.05; the round lands where he was at 2.55; launched off the crack at 148.3 deg at 2.60, peaks 3.8 m up ~3.2

## 14
said: v4 "Same moment from the guard scope: fires, misses, the runner launches up out of cover"
capture: --shot=s4_edge --stage=trailer_crack --bots=2 --pov=guard --hud=crosshair --rifle=projectile --seed=20261001
tape: crack
seconds: 2.0
in: 1.85
freeze: waive
# the crack tape down the scope at the 150 deg window: squeeze 2.22, miss into MapBaseS3Collision 2.55, launch 2.60

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
# v4: a1+a2 = 5.70 s, the title cuts in on the drop at 5.703 s. After it every cut ends on the 170 bpm grid (beat k at
# 5.716 + k*0.35294 s): h1 k9, h2 k13, then six beats a shot (5b k19 ... 10b k62), t2 k69, g1 k78, 13 k84, 14 five
# beats so the end card lands hard on k89, an 8th-beat accent (37.13 s). Lengths are frame-rounded beat boundaries.
# cuts/NN.mp4 is shot NN's cut from its in: point (shot.sh); 12's white frame is its flash: line (take 4.19, 0.045 s).
# cuts/title_hard.mp4 and cuts/end_v3.mp4 are the v3 cards (end without the player count), kept on the PC.
| line | clip | in | len | fit | speed | text |
| a1 | cuts/01.mp4@0.35:2.70 | | | beat 2.70 | | |
| a2 | cuts/02.mp4@1.70:3.00 | | | beat 3.00 | | |
| a3 | cuts/title_hard.mp4@0:1.5 | | | beat 1.5 | | |
| h1 | cuts/04.mp4@0.9:1.7 | | | beat 1.7 | | |
| h2 | cuts/05.mp4@1.6:1.4 | | | beat 1.4 | | |
| m0 | cuts/05b.mp4@0:2.1167 | | | beat 2.1167 | | |
| d1 | cuts/06.mp4@0.4:2.4833 | | | beat 2.4833 | | |
| d2 | cuts/07.mp4@2.0:2.1167 | | | beat 2.1167 | | |
| d3 | cuts/08.mp4@0:2.1167 | | | beat 2.1167 | | |
| p1 | cuts/09a.mp4@0:2.1167 | | | beat 2.1167 | | |
| p2 | cuts/09b.mp4@0:2.1167 | | | beat 2.1167 | | |
| m1 | cuts/10a.mp4@0:2.1167 | | | beat 2.1167 | | |
| m2 | cuts/10b.mp4@0:2.1167 | | | beat 2.1167 | | |
| t2 | cuts/11.mp4@1.0:2.4667 | | | beat 2.4667 | | |
| g1 | cuts/12.mp4@0.6:3.1833 | | | beat 3.1833 | | |
| k1 | cuts/13.mp4@0:2.1167 | | | beat 2.1167 | | |
| k2 | cuts/14.mp4@0:1.7667 | | | beat 1.7667 | | |
| e1 | cuts/end_v3.mp4@0.4:3.2 | | | beat 3.2 | | |
