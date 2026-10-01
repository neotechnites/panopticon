# trailer_reveal
kind: trailer
aspect: 16:9
format: Steam reveal trailer, ROUGH CUT for structure (one take per shot, first usable take kept)
ryan: "Make a ROUGH CUT of PANOPTICON's reveal trailer so Ryan can get a read on the structure. Not final quality -- speed over polish."
rules: 16:9 1920x1080 (SIZE=1920x1080 shot.sh), no HUD except the guard's scope, under 45 s, no voice, no text but the title and end cards, SR20DET as the bed, game SFX off.
v2 notes (Ryan on rough_v1): the guard stands at the tower's window, not deep inside; all runners run the course direction; the runner shot is the SAME event as the guard shot (same stage, same seed, two POVs), cut back ~1 s to the man directly behind the victim; clear line of sight when he looks up at the tower; title drops in HARD on the music's drop; music https://www.youtube.com/watch?v=OBPV0lsorwU; real-looking gameplay only (walkable deck and real cover, nobody on lava, nobody looking backwards); max 4 players a shot (1 guard + 3); spread across hell, forest and marble. Added: "EVERY shot is first-person POV -- either the guard's scope/tower view or a prisoner's first-person view. No third-person ... Title/end cards are the only non-POV frames."
music: external\src\music_v2_OBPV0lsorwU.mp4 -> voice\sr20det.ogg (SOURCES.md). The drop: 0.35 s of silence from 5.36 s, the hit at 5.703 s (sample onset); 170 bpm after it (v3 measured).
cards: cuts/title_hard.mp4 is v1's title frame looped from frame 0 (v1's title.mp4 opened on two black frames); cuts/end.mp4 is v1's.
delivery: content\trailer_reveal\final\rough_v2.mp4

## 1
said: "guard POV from the tower, runners moving on the ring, scope zooms in, fires" -- v2: "the guard stands where a PLAYER stands -- at the tower's edge/window"
capture: --shot=s3_open_lane --stage=trailer_open --pov=guard --hud=crosshair --bots=3 --rifle=projectile --set=fire_at=3.24 --seed=20261001
seconds: 4.0
in: 0.9
freeze: waive
# hell S2 inner lane; guard at the 115 deg window; zoom at take 1.9, the kill at take 3.60 (victim 114.3 deg r 49.3)
# v3: the projectile rifle (120 m/s, 22 g), led and held over; squeezed 3.25, lands 3.61 -- v2's beat

## 2
said: "cut back in time ~1 s to a runner POV directly behind another runner, the runner ahead is hit and drops; the POV turns to look up at the tower" -- v2: the SAME scenario as shot 1, clear line to the tower
capture: --shot=s3_open_lane --stage=trailer_open --pov=runner --bots=3 --look=social --rifle=projectile --set=fire_at=3.24 --seed=20261001
seconds: 5.0
in: 0.9
freeze: waive
# the same take as shot 1 down Runner_3's eyes (2.9 deg, 2.5 m directly behind the victim); hit at take 3.60, the look up 86 deg right 8 up from 3.92

## 3
said: "runners moving together between cover under fire" -- v2: first person, forest
capture: --map=forest --shot=pack_lead --stage=trailer_forest_pack --bots=3 --pov=runner --look=social --rifle=projectile --set=fire=3.15 --seed=20261001
seconds: 5.0
in: 0.9
freeze: waive
# forest 14-40 deg between the lane trunks (IN r 49.9 at 14.96/20.73/26.09, OUT r 53.8 at 32.94/39.2), the tail 2.2 m behind the victim; hit at take 3.55 (32 deg r 51.7, a gap); the look up at the tower 0.4-1.5 s after

## 4
said: "the hook's scoped hit" -- v2: the same take as 3 down the scope, guard at the 45 deg window
capture: --map=forest --shot=pack_lead --stage=trailer_forest_pack --bots=3 --pov=guard --hud=crosshair --rifle=projectile --set=lift=1;fire=3.15 --seed=20261001
seconds: 5.0
in: 0.9
freeze: waive
# zoom at take 2.0, the kill at 3.55 (v3: projectile, squeezed 3.15, lands 3.55)

## 5
said: "a runner pinned behind cover ... cut on that frame to the runner breaking cover and sprinting" -- v2: his own eyes, real cover (hell's 61.7-71.3 pocket lip wall, no lava)
capture: --shot=cover_side --stage=trailer_duel2 --bots=1 --pov=runner --look=social --rifle=projectile --seed=20261001
seconds: 7.5
in: 1.0
freeze: waive
# crouched 68.8 deg r 50.6 to take 2.4; peek past the wall's end, in the open from 2.9, eyes on the window; back at 4.2; the round hits MapBaseLip066Collision at 4.33; breaks at 5.55, sprints r 49 from 5.9

## 6
said: "the scope holding on that cover; the runner peeks; shot hits stone; the scope shows the reload" -- v2: the same take as 5, guard at the 70 deg window
capture: --shot=cover_side --stage=trailer_duel2 --bots=1 --pov=guard --hud=crosshair --rifle=projectile --seed=20261001
seconds: 7.5
in: 1.0
freeze: waive
# squeeze 4.30, rock hit 4.33 (v3 projectile: squeeze 4.36, the rock 4.70); the hand tracks the sprint 6.1-8.4 (71-97 deg) without firing

## 7
said: "a prisoner shoves another out of cover into the open, who is shot" -- v2: down the shover's eyes, forest
capture: --map=forest --shot=pack_lead --stage=trailer_forest_shove --bots=2 --pov=runner --look=social --rifle=projectile --set=lead=0;squeeze=0 --seed=20261001
seconds: 4.5
in: 0.9
freeze: waive
# victim crouched 100.8 deg r 51.8 behind the trunk at 100.66 (blocked from the 90 deg window eye 99.5-101.5); shove 2.01, lands 103.3 deg at 2.40, the hand drops him at 2.70 (v3 projectile: squeezed on landing 2.42 at where he stands, lands 2.81)

## 8
said: "a runner jumping across the lava cracks or a gap, timed between shots" -- v2: first person, three in the line
capture: --shot=lava_parkour --stage=lavaparkour --bots=3 --set=line=3 --pov=runner --look=social --seed=20261001
seconds: 5.5
in: 1.2
freeze: waive
# hell S5 lake: bodies only on the platforms and banks; no hit or out events in 10 s

## 9
said: "a runner reaches the end, picks up the finisher rifle, shoots the guard (the white-frame hit), POV flips into the tower" -- v2: marble's corridor
capture: --map=marble --shot=portal --stage=trailer_finish_marble --bots=2 --pov=runner --look=social --rifle=projectile --seed=20261001
seconds: 5.0
in: 0.9
freeze: waive
# corridor sprint from 320 deg; armed in the tower at 2.85; kill beat 4.17; seat change 5.34 (cut before it)
# v3 projectile: kill beat 4.19, seat change 5.38

## 10
said: "variety: hell" -- v2: first person in a pack of three
capture: --map=bentham_ring --shot=pack_lead --stage=trailer_ring --bots=3 --pov=runner --look=social --set=count=3;start=86;rs=48.6,49.6,48.0 --seed=20261001
seconds: 3
in: 1.2
freeze: waive
# S2 inner rock lane 86-118 deg, r 47.5-49.6

## 11
said: "variety: forest"
capture: --map=forest --shot=pack_lead --stage=trailer_ring --bots=3 --pov=runner --look=social --set=count=3;start=137;rs=51.3,52.3,51.0 --seed=20261001
seconds: 2.6
in: 1.2
freeze: waive
# tree-free corridor 137-162 deg; a tree near 164 at ~4.0 s, past the cut

## 12
said: "variety: marble"
capture: --map=marble --shot=pack_lead --stage=trailer_ring --bots=3 --pov=runner --look=social --set=count=3;start=300;rs=50.5,52.3,49.3 --seed=20261001
seconds: 3
in: 1.2
freeze: waive
# down the corridor 300-335 deg

## 13
said: v3 "the bounce pads -- hell S3/S4 lava cracks launching a runner, first-person"
capture: --shot=s4_edge --stage=polish_crack_s3 --bots=3 --pov=runner --look=social --rifle=projectile --set=wait=1.6;pov=1 --seed=20261001
seconds: 4.5
in: 0.9
freeze: waive
# S3 grid lane r 52.4 up onto the 160 crack, down the second man's eyes: the first launches at take 2.71, his own at 3.49

## 14
said: v3 bounce pads, S3
capture: --shot=s4_edge --stage=polish_crack_s3 --bots=3 --pov=runner --look=social --rifle=projectile --set=wait=1.6;pov=0 --seed=20261001
seconds: 4.0
in: 0.9
freeze: waive
# the lead man, a clear lane to the 160 crack; launched at take 2.71

## 15
said: v3 bounce pads, S4
capture: --shot=s4_edge --stage=polish_crack_run --bots=3 --pov=runner --look=social --rifle=projectile --set=wait=1.4;pov=0 --seed=20261001
seconds: 5.5
in: 0.9
freeze: waive
# the lead man up the S4 lane onto the 212 crack (take 2.50), over the lava onto 227 (3.77) and on to 242

## 16
said: v3 bounce pads, S4
capture: --shot=s4_edge --stage=polish_crack_run --bots=3 --pov=runner --look=social --rifle=projectile --set=wait=1.4;pov=1 --seed=20261001
seconds: 5.5
in: 0.9
freeze: waive
# the second man: the lead flies off 212 ahead (2.50); his own 212 at 3.25, 227 at 4.52

## 17
said: v3 "hell S1's platforming part, first-person" -- read as the hell lake platforms (S1 is the spire forest; the platforms are the S5 lake)
capture: --shot=lava_parkour --stage=lavaparkour --bots=3 --set=line=3 --pov=runner --look=social --rifle=projectile --seed=20261002
seconds: 6.0
in: 1.2
freeze: waive
# down the last man's eyes hopping the seven lake platforms

## 18
said: v3 platforming, a second take
capture: --shot=lava_parkour --stage=lavaparkour --bots=3 --set=line=3 --pov=runner --look=social --rifle=projectile --seed=20261003
seconds: 6.0
in: 1.2
freeze: waive
# the same line, another seed

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
