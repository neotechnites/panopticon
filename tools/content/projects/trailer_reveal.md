# trailer_reveal
kind: trailer
aspect: 16:9
format: Steam reveal trailer, ROUGH CUT for structure (one take per shot, first usable take kept)
ryan: "Make a ROUGH CUT of PANOPTICON's reveal trailer so Ryan can get a read on the structure. Not final quality -- speed over polish."
rules: 16:9 1920x1080 (SIZE=1920x1080 shot.sh), no HUD except the guard's scope, under 45 s, no voice, no text but the title and end cards, SR20DET as the bed, game SFX off.
v2 notes (Ryan on rough_v1): the guard stands at the tower's window, not deep inside; all runners run the course direction; the runner shot is the SAME event as the guard shot (same stage, same seed, two POVs), cut back ~1 s to the man directly behind the victim; clear line of sight when he looks up at the tower; title drops in HARD on the music's drop; music https://www.youtube.com/watch?v=OBPV0lsorwU; real-looking gameplay only (walkable deck and real cover, nobody on lava, nobody looking backwards); max 4 players a shot (1 guard + 3); spread across hell, forest and marble. Added: "EVERY shot is first-person POV -- either the guard's scope/tower view or a prisoner's first-person view. No third-person ... Title/end cards are the only non-POV frames."
music: external\src\music_v2_OBPV0lsorwU.mp4 -> voice\sr20det.ogg (SOURCES.md). The drop: 0.35 s of silence from 5.36 s, the hit at 5.703 s (sample onset); 170 bpm after it (v3 measured).
cards: cuts/title_hard.mp4 is v1's title frame looped from frame 0 (v1's title.mp4 opened on two black frames); cuts/end.mp4 is v1's.
delivery: content\trailer_reveal\final\rough_v23.mp4 (and ~/Desktop/panopticon-renders/trailer_reveal/)
tag: rough_v23
alt: rough_v20_green (v20 with the forest shots filmed in the green forest: 4g 5g 9ag 9bg, ## script rough_v20_green)
alt: rough_v22_vivaldi (v22's picture with Vivaldi, Summer RV 315 III. Presto from the top, ## script rough_v22_vivaldi)
music_vivaldi: The Modena Chamber Orchestra (Musopen), Vivaldi's Summer RV 315 III. Presto, Public Domain Mark (owner), https://commons.wikimedia.org/wiki/File:The_Modena_Chamber_Orchestra_-_Vivaldi%27s_Summer,_RV_315_-_III._Presto.ogg -> external\src\modena_summer_presto.ogg, voice\vivaldi_summer_presto.flac (0.402 s of silence added at the head).
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
capture: --shot=s3_open_lane --stage=trailer_open --pov=runner --bots=3 --rifle=projectile --set=fire_at=3.24 --seed=20261001
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
# v11 (Ryan): "the marble shot used to be behind multiple columns ... They should be two different sections of the marble map." Its own five columns again, as v5 (r 47.5, 116.4-135.6 deg); the shove wall moved to 216

## 6
said: v4 "Hell, runner POV behind a rock, peeking out -- standing (d1, re-filmed without crouch)"
capture: --shot=cover_side --stage=trailer_duel2 --bots=1 --pov=runner --rifle=projectile --seed=20261001
tape: duel
seconds: 7.5
in: 1.0
freeze: waive
# standing at 68.8 deg r 50.6 behind the pocket lip wall (hidden from the 70 deg window at h 1.0-1.8); out in the open 2.9-4.3; breaks 5.55
# v19: out in the open at 72.8 deg 3.28-3.75, runs back 3.75, behind the rock again (68.8) by 4.2; breaks 5.55 from the same spot

## 7
said: v4 "Hell, guard scope holding on that rock; the shot hits rock (d2)"
capture: --shot=cover_side --stage=trailer_duel2 --bots=1 --pov=guard --hud=crosshair --rifle=projectile --seed=20261001
tape: duel
seconds: 7.5
in: 1.0
freeze: waive
# the duel tape down the scope at the 70 deg window: squeeze 4.38, the round hits MapBaseLip066Collision at 4.72
# v19 (Ryan): "the sniper should not shoot the cover, they should shoot where the player was before the ran behind cover." Squeeze 3.83 on him in the open as he goes (lead 0); the round lands where he stood at 4.25 (MapBaseS2Collision), the rock untouched

## 8
said: v4 "Hell, runner POV breaking cover and sprinting (d3 -- Ryan: \"perfect\", keep its framing)"
capture: --shot=cover_side --stage=trailer_duel2 --bots=1 --pov=runner --rifle=projectile --seed=20261001
tape: duel
seconds: 2.2
in: 5.5
freeze: waive
# v3 d3 (05.mp4@4.5 = take 5.5): breaks 5.55, sprints r 49 from ~6.2
# v22 (Ryan): "he looks left, then it cuts to what is clearly a new shot of him running the ring and looking over ... the two shots are clearly not the same shot, when they should be." The join was a one-tick snap of the head onto the lane after a standing flick. Now one carried move from 5.55: his head swings left off the rock onto the lane as his feet break, the look over at the tower at ~6.8; duel re-taped (identical to 5.55)

## 9a
said: v5 "Forest, runner POV: a second runner beside him at the inner edge, a visible shove, he tips over the edge and drops out of frame into the mist"
capture: --map=forest --shot=pack_lead --stage=trailer_forest_pit --bots=3 --pov=runner --look=social --rifle=projectile --seed=20261001
tape: forest_pit
seconds: 2.5
in: 1.04
freeze: waive
# side by side down the lane (the victim a stride inside), he cuts in to the lip (153.4 deg r 47.25) and turns to face him at 2.30; the shove at 2.75 from 1.0 m (arms + the shover's kick), backwards over the edge and down out of frame; a third pulls up behind
# v19 (Ryan): "they shouldnt walk to the edge, look back, and get shoved ... they shold be running, and get shoved to the side". All three sprint the lane from 137.6 deg; the shover's head whips in 64 deg at 1.72 and the shipped shove lands mid-stride at 1.87 (151.6 deg r 50); he goes over the lip sideways at ~153; the shover's eyes come back to the lane and he runs on
# v20 (Ryan): "now the shove doesnt read right, its not clear whats happeneding, and tht its two shots of the same event." A longer run-up (from 124.3 deg, threading the 134-136 trees): the shover comes up on his shoulder (2.2 m to 0.5 m), a check on him at 2.3, his head turns onto him at 2.55 and holds (1.1 m off), the man's head snaps round to him at 2.8, the shove at 2.93 between the lip trees (149.9 deg), his eyes follow him out over the lip; the cut ends on that look (a rough take runs 0.09 s behind: in 1.04 ends it 0.49 s after the shove)

## 9b
said: v5 "Forest, the shoved runner's POV: the edge he was shoved from with the shover on it looking down, falling away, the mist rushing up"
capture: --map=forest --shot=pack_lead --stage=trailer_forest_pit --bots=3 --pov=runner --look=social --rifle=projectile --set=pov=victim --seed=20261001
tape: forest_pit
seconds: 1.8
in: 2.96
freeze: waive
# the forest_pit tape down Runner_1 from 0.1 s after the shove (the shover's arms still out, 1 m off), eyes held up on him: the lip shrinks above until the bank closes over it (~3.5), the mist at y -5.75 (4.49) greys it out; the cut ends 4.63 in the mist (out 4.65); floor_kill=1 lowers the KillBox for the shot only (map unchanged)
# v19 (Ryan): "the other players shouldnt just be looking at him fall, they should be running." From 0.08 s after the shove: his head comes round to the lip, the shover and the third sprint on along it (to 2.7), the bank closes over them, out at 4.02
# v20: opens on the shove (in 2.96, the rough take 0.09 s behind): his eyes already on the shover, arms out, 1.1 m off, then on the lip between its two trees; the shover turns front and runs out of it, the third runs through it (3.2-3.7), the bank closes over it (~3.9), out at 5.08

## 10a
said: v5 "Marble, runner POV: two runners both behind the same column on the inner edge, hidden from the tower; he shoves the other out into the open; cut BEFORE the shot"
capture: --map=marble --shot=pack_lead --stage=trailer_marble_column --bots=2 --pov=runner --look=social --rifle=projectile --seed=20261001
tape: marble_column
seconds: 2.2
in: 1.3
freeze: waive
# v6 (Ryan): "THREE marble_column instances next to each other ... a solid wall of cover wide enough for two runners". Spawned by the stage (marble_column.glb, r 47.5, 124.75/126.0/127.25 deg, shafts touching; maps/marble/marble.tscn untouched); both side by side in the wall's shadow from the 126 window, the victim at 126.53 r 48.55, the POV at 125.53 r 48.75; shoved along the ring out past the wall into the open

## 10b
said: v5 "Marble, guard scope, the same event: nobody in sight, one shoved out from behind the column, fires, hits"
capture: --map=marble --shot=pack_lead --stage=trailer_marble_column --bots=2 --pov=guard --hud=crosshair --rifle=projectile --seed=20261001
tape: marble_column
seconds: 2.2
in: 2.75
freeze: waive
# the marble_column tape down the scope at the 126 deg window: the shove at 3.00, he lands running on down the course; the scope leads and holds over him, squeeze 0.65 s after he lands (fired 4.07), the round in flight, hit 4.42, hit, he dies where he falls
# v7 (Ryan on 10b): "there's no visible projectile. he just shoots, isn't aimed right, and the guy disappears." Every kill stage now runs the shipped ghost rule (death pose, body held), not NONE (parked out of the world)
# v11: the wall, both runners, the guard and the tape moved 90 deg on to the 216 window (columns 214.75/216.0/217.25, victim 216.53, POV 215.53); 5b keeps 126
# v8 (Ryan): "he needs to get shot WHILE he's being shoved out ... the shove is what sealed his fate." Shove 3.00, he clears the wall's edge 3.08, squeeze 3.10 led into the stumble, hit 3.45 as he lands at 129.2 (no recovery, no running); 10a in 1.3 so its cut ends 3.42, just before the hit

## 11
said: v4 "Hell, lake platforming (t2)"
capture: --shot=lava_parkour --stage=lavaparkour --bots=3 --set=line=3 --pov=runner --seed=20261001
tape: lake
seconds: 5.5
in: 1.2
freeze: waive
# hell S5 lake: three hopping the platforms, bodies only on the platforms and banks
# v19 (Ryan): "the lava parkour scene doesnt relaly look human." The POV's eyes are his own: on the landing, then round onto the next platform before he is down, one turn a hop; every landing off-centre, so the run-ups differ (leaps at take 1.83, 2.63, 3.57, 4.25, 5.20, 6.03); a check on the second top, a stumble on the fourth (4.98); the two ahead land off-centre too

## 12
said: v4 "Marble, corridor -> portal -> rifle -> shooting the guard, white frame (g1)"
capture: --map=marble --shot=portal --stage=trailer_finish_marble --bots=2 --pov=runner --look=social --rifle=projectile --seed=20261001
tape: finish
flash: 4.19 0.045
seconds: 5.0
in: 0.9
freeze: waive
# corridor sprint from 320 deg; armed in the tower at 2.85; the kill beat 4.19 (the white frame); seat change 5.38 (cut before it)
# v22 (Ryan): "the sniper guy at the very end, is floating because we changes the map to not have the raised platform." The tower's collider still has a 0.6 m dais (r 2.2) the drawn floor does not; the stage lowers it for the shot (map unchanged), the guard stands on the room floor (y 27.05); finish re-taped

## 13
said: v4 "Hell S3, runner POV running through and bouncing on a crack"
capture: --shot=s4_edge --stage=trailer_crack --bots=2 --pov=runner --rifle=projectile --seed=20261001
tape: crack
seconds: 2.2
in: 1.7
freeze: waive
# behind the 139 deg lip rock, breaks across the gap at 2.05; the round lands where he was at 2.55; launched off the crack at 148.3 deg at 2.60, peaks 3.8 m up ~3.2
# v19: his eyes go up after the mate thrown off the crack ahead (2.23); launched himself 2.60; the round crosses ahead of the mate ~3.1, a look across at the tower, down for the landing
# v22 (Ryan): "some of that exact same jankiness in the runner pov bouncing guys shot." Three joins: a flick left in the cut's first frames (now done before it opens), a snap at the break, and in the air a whip left as he passed his run target then a snap onto the lane (~3.1). The run aims past the target and every join is carried; launched 2.63, lands ~3.78; crack re-taped (the mate, the squeeze 2.75 and the miss 3.17 unchanged)

## 14
said: v4 "Same moment from the guard scope: fires, misses, the runner launches up out of cover"
capture: --shot=s4_edge --stage=trailer_crack --bots=2 --pov=guard --hud=crosshair --rifle=projectile --seed=20261001
tape: crack
seconds: 2.0
in: 1.95
freeze: waive
# the crack tape down the scope at the 150 deg window: squeeze 2.22, miss into MapBaseS3Collision 2.55, launch 2.60
# v19 (Ryan): "the sniper shoots a guy behind cover, even though theres guys actually bouncing above it, his focus should be there." The scope rests on the wall's top; the first man up (2.23) is snapped onto and led, squeeze 2.75, the round a metre ahead of him (ground 3.17); the second man up at 2.60 rises through the scope; the hand rides them down

## 4g
said: v4 "Forest, runner POV running between trees (h1)"
capture: --map=res://maps/forest/forest_green.tscn --shot=pack_lead --stage=trailer_forest_pack --bots=3 --pov=runner --look=social --rifle=projectile --set=fire=3.15 --seed=20261001
tape: forest_pack
seconds: 5.0
in: 0.9
freeze: waive
# rough_v20_green: shot 4 in the green forest (forest_green.tscn, same geometry), same stage and tape
# v22 (Ryan): "not have the shot from the pov fo the runner. it should just be a running shot". Same take and tape; the edit uses take 1.3-3.07, out before the squeeze (3.15): nobody is hit and no round is seen. Refilmed on main 3a8cefd (the darker shade)

## 5g
said: v4 "Forest, guard scope: the kill (h2)"
capture: --map=res://maps/forest/forest_green.tscn --shot=pack_lead --stage=trailer_forest_pack --bots=3 --pov=guard --hud=crosshair --rifle=projectile --set=lift=1;fire=3.15 --seed=20261001
tape: forest_pack
seconds: 5.0
in: 0.9
freeze: waive
# rough_v20_green: shot 5 in the green forest (forest_green.tscn, same geometry), same stage and tape

## 9ag
said: v5 "Forest, runner POV: a second runner beside him at the inner edge, a visible shove, he tips over the edge and drops out of frame into the mist"
capture: --map=res://maps/forest/forest_green.tscn --shot=pack_lead --stage=trailer_forest_pit --bots=3 --pov=runner --look=social --rifle=projectile --seed=20261001
tape: forest_pit
seconds: 2.5
in: 1.04
freeze: waive
# rough_v20_green: shot 9a in the green forest (forest_green.tscn, same geometry), same stage and tape

## 9bg
said: v5 "Forest, the shoved runner's POV: the edge he was shoved from with the shover on it looking down, falling away, the mist rushing up"
capture: --map=res://maps/forest/forest_green.tscn --shot=pack_lead --stage=trailer_forest_pit --bots=3 --pov=runner --look=social --rifle=projectile --set=pov=victim --seed=20261001
tape: forest_pit
seconds: 1.8
in: 2.96
freeze: waive
# rough_v20_green: shot 9b in the green forest (forest_green.tscn, same geometry), same stage and tape

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
music: voice/vivaldi_summer_presto.flac
music_db: 3.7
music_fade: 0.02 2.5
captions: none
# v4: a1+a2 = 5.70 s, the title cuts in on the drop at 5.703 s. After it every cut ends on the 170 bpm grid (beat k at
# 5.716 + k*0.35294 s): h1 k9, h2 k13, then six beats a shot (5b k19 ... 10b k62; v5: 9a seven, 9b five), t2 k69, g1 k78, 13 k84, 14 five
# beats so the end card lands hard on k89, an 8th-beat accent (37.13 s). Lengths are frame-rounded beat boundaries.
# cuts/NN.mp4 is shot NN's cut from its in: point (shot.sh); 12's white frame is its flash: line (take 4.19, 0.045 s).
# v9: title_zoom/card2_zoom (4% push-in, frames/title.png, card2.png) back to back; 12 (g1) last, its flash (clip 3.29) ends it, hard cut to the end card.
# v10: cards rebuilt zoompan about the exact centre (cuts/title_zoom10, card2_zoom10 from the same pngs, 4%), held 2.1333 s (6 beats) and 2.4667 s (7 beats): ends on k6 and k13 of the grid; the rest of the cut is 1.74 s later.
# v12 (Ryan): "redo every forest shot exactly how it is in rough 11" -- 4, 5, 9a, 9b reshot from their tapes on main e86c171 (the new forest look); the edit is v11's.
# v13 (Ryan): the streaks "flash" opaque in the pit fall -- 4, 5, 9a, 9b reshot from their tapes on main ab13665 (streak blend fix); the edit is v11's.
# v14 (Ryan): "reshoot all the hell shots and reedit the trailer just like we did for the forest" -- 1, 2, 6, 7, 8, 11, 13, 14 reshot from their tapes on main 826cc0f (hell rock and lava textures, glow map, bilinear); the edit is v13's.
# v15 (Ryan): "screen recorded real time of the game"; hell "blown the fuck out" -- 1, 2, 6, 7, 8, 11, 13, 14 reshot in rough mode (real time, screen recorded) at the game's own lighting (no stage exposure/ambient lift); the edit is v14's.
# v19 (Ryan's notes on v18): duel, forest pit, crack and lake restaged and re-taped, 6 7 8 9a 9b 11 13 14 refilmed in rough mode; d2 in 1.6 (the peek, the shot, the miss), t2 in 2.0 (the check, the quick hop, the stumble); lengths and the grid are v18's.
# v20 (Ryan on v19): the forest shove restaged and re-taped, 9a 9b refilmed in rough mode; every other shot and the edit are v19's.
# v21 (Ryan): "reshooting any of the trailer that is not up to date with the game ... use the green forest" -- every shot refilmed in rough mode on main 18f6445, the forest lines from 4g 5g 9ag 9bg (gold forest no longer used); the edit is v20's.
# v22 (Ryan's notes on v21): h1 in 0.4 (a plain running shot, out before the squeeze; h2 is the first sight of the hit); duel, crack and finish re-taped (the joins carried, the guard on the room floor); 4g 8 13 14 12 refilmed, every other cut is v21's file; lengths and the grid are v21's.
# cuts/title_hard.mp4 and cuts/end_v3.mp4 are the v3 cards (end without the player count), kept on the PC.
| line | clip | in | len | fit | speed | text |
| a1 | cuts/01.mp4@0.35:2.70 | | | beat 2.70 | | |
| a2 | cuts/02.mp4@1.70:3.00 | | | beat 3.00 | | |
| a3 | cuts/title_zoom10.mp4@0:2.1333 | | | beat 2.1333 | | |
| a4 | cuts/card2_zoom10.mp4@0:2.4667 | | | beat 2.4667 | | |
| h1 | cuts/04g.mp4@0.4:1.7667 | | | beat 1.7667 | | |
| h2 | cuts/05g.mp4@1.6:1.4 | | | beat 1.4 | | |
| m0 | cuts/05b.mp4@0:2.1167 | | | beat 2.1167 | | |
| d1 | cuts/06.mp4@0.4:2.4833 | | | beat 2.4833 | | |
| d2 | cuts/07.mp4@1.6:2.1167 | | | beat 2.1167 | | |
| d3 | cuts/08.mp4@0:2.1167 | | | beat 2.1167 | | |
| p1 | cuts/09ag.mp4@0:2.4667 | | | beat 2.4667 | | |
| p2 | cuts/09bg.mp4@0:1.7667 | | | beat 1.7667 | | |
| m1 | cuts/10a.mp4@0:2.1167 | | | beat 2.1167 | | |
| m2 | cuts/10b.mp4@0:2.1167 | | | beat 2.1167 | | |
| t2 | cuts/11.mp4@2.0:2.4667 | | | beat 2.4667 | | |
| k1 | cuts/13.mp4@0:2.1167 | | | beat 2.1167 | | |
| k2 | cuts/14.mp4@0:1.7667 | | | beat 1.7667 | | |
| g1 | cuts/12.mp4@0.15:3.1833 | | | beat 3.1833 | | |
| e1 | cuts/end_v3.mp4@0.4:3.2 | | | beat 3.2 | | |

## script rough_v20_green
size: 1920x1080
music: voice/sr20det.ogg
music_db: -3
music_fade: 0.02 2.5
captions: none
# The alternate cut (Ryan: "a version of the trailer with the green forest, as a alt not a revision"): v20's edit, h1 h2 p1 p2 from the green forest takes.
| line | clip | in | len | fit | speed | text |
| a1 | cuts/01.mp4@0.35:2.70 | | | beat 2.70 | | |
| a2 | cuts/02.mp4@1.70:3.00 | | | beat 3.00 | | |
| a3 | cuts/title_zoom10.mp4@0:2.1333 | | | beat 2.1333 | | |
| a4 | cuts/card2_zoom10.mp4@0:2.4667 | | | beat 2.4667 | | |
| h1 | cuts/04g.mp4@0.9:1.7667 | | | beat 1.7667 | | |
| h2 | cuts/05g.mp4@1.6:1.4 | | | beat 1.4 | | |
| m0 | cuts/05b.mp4@0:2.1167 | | | beat 2.1167 | | |
| d1 | cuts/06.mp4@0.4:2.4833 | | | beat 2.4833 | | |
| d2 | cuts/07.mp4@1.6:2.1167 | | | beat 2.1167 | | |
| d3 | cuts/08.mp4@0:2.1167 | | | beat 2.1167 | | |
| p1 | cuts/09ag.mp4@0:2.4667 | | | beat 2.4667 | | |
| p2 | cuts/09bg.mp4@0:1.7667 | | | beat 1.7667 | | |
| m1 | cuts/10a.mp4@0:2.1167 | | | beat 2.1167 | | |
| m2 | cuts/10b.mp4@0:2.1167 | | | beat 2.1167 | | |
| t2 | cuts/11.mp4@2.0:2.4667 | | | beat 2.4667 | | |
| k1 | cuts/13.mp4@0:2.1167 | | | beat 2.1167 | | |
| k2 | cuts/14.mp4@0:1.7667 | | | beat 1.7667 | | |
| g1 | cuts/12.mp4@0.15:3.1833 | | | beat 3.1833 | | |
| e1 | cuts/end_v3.mp4@0.4:3.2 | | | beat 3.2 | | |

## script rough_v22_vivaldi
size: 1920x1080
music: voice/vivaldi_summer_presto.flac
music_db: 3.7
music_fade: 0.02 2.5
captions: none
# v22's edit, Vivaldi from the top: the onset at 5.298 s in the recording (the second strong beat near 5 s, after 4.328) lands on the title card's first frame (5.70); file padded 0.402 s.
# music_db 3.7: the programme at -14 LUFS integrated. Other strong beats: 3.984, 4.328, 6.127 s (recording time).
| line | clip | in | len | fit | speed | text |
| a1 | cuts/01.mp4@0.35:2.70 | | | beat 2.70 | | |
| a2 | cuts/02.mp4@1.70:3.00 | | | beat 3.00 | | |
| a3 | cuts/title_zoom10.mp4@0:2.1333 | | | beat 2.1333 | | |
| a4 | cuts/card2_zoom10.mp4@0:2.4667 | | | beat 2.4667 | | |
| h1 | cuts/04g.mp4@0.4:1.7667 | | | beat 1.7667 | | |
| h2 | cuts/05g.mp4@1.6:1.4 | | | beat 1.4 | | |
| m0 | cuts/05b.mp4@0:2.1167 | | | beat 2.1167 | | |
| d1 | cuts/06.mp4@0.4:2.4833 | | | beat 2.4833 | | |
| d2 | cuts/07.mp4@1.6:2.1167 | | | beat 2.1167 | | |
| d3 | cuts/08.mp4@0:2.1167 | | | beat 2.1167 | | |
| p1 | cuts/09ag.mp4@0:2.4667 | | | beat 2.4667 | | |
| p2 | cuts/09bg.mp4@0:1.7667 | | | beat 1.7667 | | |
| m1 | cuts/10a.mp4@0:2.1167 | | | beat 2.1167 | | |
| m2 | cuts/10b.mp4@0:2.1167 | | | beat 2.1167 | | |
| t2 | cuts/11.mp4@2.0:2.4667 | | | beat 2.4667 | | |
| k1 | cuts/13.mp4@0:2.1167 | | | beat 2.1167 | | |
| k2 | cuts/14.mp4@0:1.7667 | | | beat 1.7667 | | |
| g1 | cuts/12.mp4@0.15:3.1833 | | | beat 3.1833 | | |
| e1 | cuts/end_v3.mp4@0.4:3.2 | | | beat 3.2 | | |
