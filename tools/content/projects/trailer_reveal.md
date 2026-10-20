# trailer_reveal
kind: trailer
aspect: 16:9
format: Steam reveal trailer, ROUGH CUT for structure (one take per shot, first usable take kept)
ryan: "Make a ROUGH CUT of PANOPTICON's reveal trailer so Ryan can get a read on the structure. Not final quality -- speed over polish."
rules: 16:9 1920x1080 (SIZE=1920x1080 shot.sh), no HUD except the guard's scope, under 45 s, no voice, no text but the title and end cards, SR20DET as the bed, game SFX off.
v2 notes (Ryan on rough_v1): the guard stands at the tower's window, not deep inside; all runners run the course direction; the runner shot is the SAME event as the guard shot (same stage, same seed, two POVs), cut back ~1 s to the man directly behind the victim; clear line of sight when he looks up at the tower; title drops in HARD on the music's drop; music https://www.youtube.com/watch?v=OBPV0lsorwU; real-looking gameplay only (walkable deck and real cover, nobody on lava, nobody looking backwards); max 4 players a shot (1 guard + 3); spread across hell, forest and marble. Added: "EVERY shot is first-person POV -- either the guard's scope/tower view or a prisoner's first-person view. No third-person ... Title/end cards are the only non-POV frames."
music: external\src\music_v2_OBPV0lsorwU.mp4 -> voice\sr20det.ogg (SOURCES.md). The drop: 0.35 s of silence from 5.36 s, the hit at 5.703 s (sample onset); 170 bpm after it (v3 measured).
cards: cuts/title_hard.mp4 is v1's title frame looped from frame 0 (v1's title.mp4 opened on two black frames); cuts/end.mp4 is v1's.
delivery: content\trailer_reveal\final\rough_v52_cutA.mp4 (and ~/Desktop/panopticon-renders/trailer_reveal/)
tag: rough_v60_beats
alt: rough_v24 (the SR20DET cut before Ryan's seven notes; ## script rough_v24)
alt: rough_v26_vivaldi (rough_v25_vivaldi with the seven notes, every cut and event on the same beats; ## script rough_v26_vivaldi)
kept: cuts\_v25\NN.mp4 are the shot files rough_v24 and rough_v25_vivaldi were cut from (every shot was refilmed for v26 on main 6547970).
alt: rough_v20_green (v20 with the forest shots filmed in the green forest: 4g 5g 9ag 9bg, ## script rough_v20_green)
alt: rough_v22_vivaldi (v22's picture with Vivaldi, Summer RV 315 III. Presto from the top, ## script rough_v22_vivaldi)
alt: rough_v23 (every shot refilmed on main 9c1502c, Vivaldi with the re-entry after the silence on the title card; ## script rough_v23)
alt: rough_v24_castcadia (v24 picture, music audition, UNLICENSED, private evaluation only: CASTCADIA, ZEROCORE (castcadia.bandcamp.com/track/zerocore), stretched 171.9 -> 170 bpm, drop on the title card; ## script rough_v24_castcadia)
alt: rough_v24_mil3sperhour (v24 picture, music audition, UNLICENSED, private evaluation only: MIL3SPERHOUR, RIVER RUINS (soundcloud.com/mil3sperhour/river-ruins), 170 bpm, drop on the title card; ## script rough_v24_mil3sperhour)
alt: rough_v25_vivaldi (the Vivaldi cut with every cut and event on the recording's measured beats: trailer_reveal.vivaldi_beats.csv; ## script rough_v25_vivaldi)
alt: rough_v24_yet (v24 picture, music audition, UNLICENSED, private evaluation only: YET soundsystem, SIBERIA (yetsoundsystem.bandcamp.com/track/siberia), stretched 164.7 -> 170 bpm, drop on the title card; ## script rough_v24_yet)
music_vivaldi: The Modena Chamber Orchestra (Musopen), Vivaldi's Summer RV 315 III. Presto, Public Domain Mark (owner), https://commons.wikimedia.org/wiki/File:The_Modena_Chamber_Orchestra_-_Vivaldi%27s_Summer,_RV_315_-_III._Presto.ogg -> external\src\modena_summer_presto.ogg, voice\vivaldi_summer_presto.flac (head trimmed 2.60 s: the re-entry after the silence lands on the title card at 5.70 s; the first alignment is voice\vivaldi_summer_presto_beat5298.flac).
size: 1920x1080
v4 (Ryan): "every shot must be exactly reproducible in engine -- run a script and record"; NO CROUCHING anywhere; max 3 prisoners + guard; guard shots on the projectile rifle (led, held over). Every shot plays a TAPE (tape: line): the staged take recorded once, then every input played back -- see ## reshoot.


## 1
said: v4 "Hell, guard POV from the window: zooms in, fires at the middle runner (keep v3 a1 event)"
capture: --shot=s3_open_lane --stage=trailer_open --pov=guard --hud=crosshair --bots=3 --rifle=projectile --set=fire_at=3.24;shimmer=0.06 --seed=20261001
tape: open
seconds: 4.0
in: 0.9
freeze: waive
# hell S2 inner lane; guard at the 115 deg window; zoom at take 1.9; squeezed 3.25, lands 3.60 (victim Runner_2)

## 2
said: v4 "Hell, the same event from the runner behind: the man ahead drops, he looks up at the tower (keep a2)"
capture: --shot=s3_open_lane --stage=trailer_open --pov=runner --bots=3 --rifle=projectile --set=fire_at=3.24;eye_at=4.3;eye_swing=0.4;eye_from=60:49;shimmer=0.06 --seed=20261001
tape: open
seconds: 5.0
in: 0.9
freeze: waive
# the open tape down Runner_3's eyes, 2.5 m behind the victim; hit at take 3.60, the look up from 3.92
# v34 (Ryan: "a random cut" in the opening): his look up at the tower was 86 deg in 0.2 s, a whip that read as a cut. On the open tape the same
# total turn is spread over 0.4 s (ticks 237-260, smoothstep), so it is a head turn; the eye meets him as he settles (eye_at 4.3). Shot 1 is untouched.
# v26 (Ryan): "when the runner looks over at the tower before the title card, he does it, then looks ever so slightly left, it looks bad." His eyes
# stay on the tower from 3.92 to past the cut (the 6 deg ease left at 4.77 is gone). The live hand no longer lands this round (v19 hand), so the take was not
# re-recorded: Runner_3's look on the open tape was rewritten from tick 287 (the same feet, to 0.1 mm); every other body and the shot are the old tape's.

## 4
said: v4 "Forest, runner POV running between trees (h1)"
capture: --map=forest --shot=pack_lead --stage=trailer_forest_pack --bots=3 --pov=runner --look=social --rifle=projectile --set=fire=3.15 --seed=20261001
tape: forest_pack
seconds: 5.0
in: 0.9
freeze: waive
# forest 14-40 deg between the lane trunks, the tail 2.2 m behind the victim; hit at take 3.55

## 4s
said: v27 (Ryan) "Forest runner-POV running shot: it looks slow and unfinished" -- refilm fast and complete: full sprint, a good line, no dead start
capture: --map=res://maps/forest/forest_green.tscn --shot=pack_lead --stage=trailer_forest_pack --bots=3 --pov=runner --look=social --rifle=projectile --set=sprint=1;fire=99 --seed=20261001
tape: forest_sprint
seconds: 4.5
in: 0.0
freeze: waive
# h1 for v27: the forest_pack stage with sprint=1, every man at a full run (pace x1.42, capped at 1.0; the tail at 1.0 on its own S line
# between the 20.7 lane trunk and the 32.9 outer trunk); no shot (fire=99). The cut opens a second into the run, the pack already at speed.

## 4t
said: v28 (Ryan) on 4s: "you did nothing about it" -- the forest POV run must read fast, intentional and finished
capture: --map=res://maps/forest/forest_green.tscn --shot=pack_lead --stage=trailer_forest_sprint --bots=3 --pov=runner --look=social --rifle=projectile --set=zone=2 --seed=20261001
tape: forest_thread
seconds: 3.6
in: 0.8
freeze: waive
# trailer_forest_sprint: a line picked through the trees at full run, close past every lane trunk, the man ahead takes it first,
# through the two-metre gap between the 32.9 and 34.5 trunks, out past the 39 trunk. See the stage header for why 4s read slow.

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
# v26 (Ryan): "in the running shots in the forest and marble, they look to robotic, because there all just following a line, they should look more like players
# runnign around." Each his own line (human_run.gd): the lead cuts in r 51.0 to 49.8, the second hugs the columns and swings out round his heels, the third starts late outside and cuts in behind.
# The hand reads the man behind while it is still on the lead (guard_hand), so the swing at 2.4 lands on him: before, it led him by the 1.7 s gap and the scope sat empty.
# v11 (Ryan): "the marble shot used to be behind multiple columns ... They should be two different sections of the marble map." Its own five columns again, as v5 (r 47.5, 116.4-135.6 deg); the shove wall moved to 216

## 6
said: v4 "Hell, runner POV behind a rock, peeking out -- standing (d1, re-filmed without crouch)"
capture: --shot=cover_side --stage=trailer_duel2 --bots=1 --pov=runner --rifle=projectile --set=shimmer=0.06 --seed=20261001
tape: duel
seconds: 7.5
in: 1.0
freeze: waive
# standing at 68.8 deg r 50.6 behind the pocket lip wall (hidden from the 70 deg window at h 1.0-1.8); out in the open 2.9-4.3; breaks 5.55
# v19: out in the open at 72.8 deg 3.28-3.75, runs back 3.75, behind the rock again (68.8) by 4.2; breaks 5.55 from the same spot
# v26 (Ryan): "in the peaking scene, they start slightly peaked, then go behind cover, then peak again. they dont need to start slightly peaked. this can be solved by
# just cutting the shot." The tower shows past the rock until take ~1.85; rough_v26's d1 opens at take 2.10 (two beats later). The Vivaldi d1 already opened at 2.50.

## 7
said: v4 "Hell, guard scope holding on that rock; the shot hits rock (d2)"
capture: --shot=cover_side --stage=trailer_duel2 --bots=1 --pov=guard --hud=crosshair --rifle=projectile --set=shimmer=0.06 --seed=20261001
tape: duel
seconds: 7.5
in: 1.0
freeze: waive
# the duel tape down the scope at the 70 deg window: squeeze 4.38, the round hits MapBaseLip066Collision at 4.72
# v19 (Ryan): "the sniper should not shoot the cover, they should shoot where the player was before the ran behind cover." Squeeze 3.83 on him in the open as he goes (lead 0); the round lands where he stood at 4.25 (MapBaseS2Collision), the rock untouched

## 8
said: v4 "Hell, runner POV breaking cover and sprinting (d3 -- Ryan: \"perfect\", keep its framing)"
capture: --shot=cover_side --stage=trailer_duel2 --bots=1 --pov=runner --rifle=projectile --set=shimmer=0.06 --seed=20261001
tape: duel
seconds: 2.6
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
capture: --map=marble --shot=pack_lead --stage=trailer_marble_column --bots=2 --pov=runner --rifle=projectile --set=late=1;lead=1.0;now=1;back_fire=0.1;kick=0.1;back_pace=0.5;follow=0.4;run_after=0.9;settle_omega=45;max_rate=55 --seed=20261001
tape: marble_column
seconds: 2.6
in: 1.75
# v41 (Ryan): "we dont even see the fucking shove from the runners pov. its jsut a shot of a person looking at a person." The cut opened 1.8 s before the shove and ended 0.2 s after it.
# in 1.75: m1 (2.0 s) has the square-up, the shove at 3.00 (1.25 s in) and him thrown 12 deg past the wall's end by its last frame. Expects: shove >= 0.5 s before the end, him inside 90% of the frame, >= 3 deg out.
freeze: waive
# v37 (Ryan): "the 3 columns for the shove wont work anymore, youll have to use the walls that are now in the map." Behind the map's ArcWall188 (r 47.2, 182.4-193.9 deg, 7.6 m),
# the guard at the 193.5 window; the v11 staging turned -23.25 deg (edge 193.85): smoke shove 3.00, exposed 3.07 at 194.1, react 3.38, squeeze 4.37, hit 4.73 at 195.0. No --look=social.
# v27 (Ryan): "the runner must NOT look over at the tower. They can't see it from behind cover." late=1: the rider's eyes stay low and follow the man out.
# v6 (Ryan): "THREE marble_column instances next to each other ... a solid wall of cover wide enough for two runners". Spawned by the stage (marble_column.glb, r 47.5, 124.75/126.0/127.25 deg, shafts touching; maps/marble/marble.tscn untouched); both side by side in the wall's shadow from the 126 window, the victim at 126.53 r 48.55, the POV at 125.53 r 48.75; shoved along the ring out past the wall into the open

## 10b
said: v5 "Marble, guard scope, the same event: nobody in sight, one shoved out from behind the column, fires, hits"
capture: --map=marble --shot=pack_lead --stage=trailer_marble_column --bots=2 --pov=guard --hud=crosshair --rifle=projectile --set=late=1;lead=1.0;now=1;back_fire=0.1;kick=0.1;back_pace=0.5;follow=0.4;run_after=0.9;settle_omega=45;max_rate=55 --seed=20261001
tape: marble_column
seconds: 3.4
in: 2.75
# v41 (Ryan): "they need to be looking at the edge of the cover, the person needs to be shoved out, they need to track them, then once that person starts running back, line up the shot and shoot."
# in 2.75: m2 opens with the scope still on the wall's end (193.9) 0.25 s before the shove; he is thrown into it, tracked (omega 10, follow 0.4, wrist 55 deg/s); he breaks back at 4.02,
# the lead goes on (settle_omega 45), squeeze 4.37 1.98 m ahead of him along his run, hit 4.73 at 201.1 deg, 0.6 s of the drop in the cut. Expects on all of it (stage header).
# v42 (Ryan): "the shove half is fine, the sniper half jumps and snaps around like a robot". The hand's speed ramps (max_accel 260 deg/s^2), every change of aim eases over 0.3 s
# (rest -> him, off the ragdoll, onto the lead); smoke: first move 3.25 (0.20 s reaction), overshoot 0.46 deg, peak 38.6 deg/s, squeeze 4.60 1.98 m led, hit 4.97 at 199.6. Re-taped.
freeze: waive
# v28 (Ryan): "the shoved ragdoll freaks out" (game fix: a flop's limbs no longer start 7 m/s behind the torso) "and after the shove the runner
# starts running the ring instead of going back behind cover. He must duck back behind cover." He lies where the throw puts him, gets up and
# sprints back for the wall (4.26); the scope, on him since 3.38, squeezes 0.1 s into his break, led (lead 1.0; 0.9-1.05 all hit on the PC, 1.1 misses); hit at 4.73, 218.3 deg, a metre short.
# v27 (Ryan): "The player gets shoved further, the sniper visibly reacts (re-aims), and then hits the shot." late=1: the shipped shove (16/7) throws him
# ~8 m clear of the wall; the scope rests on the wall's far side (215 deg); he clears the edge 3.07, the hand comes off the wall onto him at 3.37, he finds
# his feet and runs, squeeze 4.17 led on his run, hit 4.53 at 234.3 deg. marble_column re-taped.
# the marble_column tape down the scope at the 126 deg window: the shove at 3.00, he lands running on down the course; the scope leads and holds over him, squeeze 0.65 s after he lands (fired 4.07), the round in flight, hit 4.42, hit, he dies where he falls
# v7 (Ryan on 10b): "there's no visible projectile. he just shoots, isn't aimed right, and the guy disappears." Every kill stage now runs the shipped ghost rule (death pose, body held), not NONE (parked out of the world)
# v11: the wall, both runners, the guard and the tape moved 90 deg on to the 216 window (columns 214.75/216.0/217.25, victim 216.53, POV 215.53); 5b keeps 126
# v8 (Ryan): "he needs to get shot WHILE he's being shoved out ... the shove is what sealed his fate." Shove 3.00, he clears the wall's edge 3.08, squeeze 3.10 led into the stumble, hit 3.45 as he lands at 129.2 (no recovery, no running); 10a in 1.3 so its cut ends 3.42, just before the hit
# v26 (note 4, the same read on the marble shove): the shover's square-up was a 45 deg flick in six frames 0.28 s before the shove. His head comes round
# onto him over the half second before it, eased (stage_driver "smooth"); shove 3.00, squeeze 3.10, hit 3.45 as before.

## 11
said: v4 "Hell, lake platforming (t2)"
capture: --shot=lava_parkour --stage=lavaparkour --bots=3 --set=line=3;solo=1;shimmer=0.0 --pov=runner --seed=20261001
tape: lake
seconds: 5.5
in: 1.2
freeze: waive
# hell S5 lake: three hopping the platforms, bodies only on the platforms and banks
# v19 (Ryan): "the lava parkour scene doesnt relaly look human." The POV's eyes are his own: on the landing, then round onto the next platform before he is down, one turn a hop; every landing off-centre, so the run-ups differ (leaps at take 1.83, 2.63, 3.57, 4.25, 5.20, 6.03); a check on the second top, a stumble on the fourth (4.98); the two ahead land off-centre too
# v28 (Ryan): "It must not distort the lava parkour shot or the eye": shimmer=0.0 here (0.06 on every other hell shot) -- at 0.06 the near lava still smeared.
# v27 (Ryan): "Lava parkour shot: POV only, no other player." solo=1: the two ahead parked out of sight on S2; the POV is tick for tick the old take; lake re-taped.
# v26 (Ryan): "the parkour scene also looks a bit robotic. not the pov, but the other runners." The two ahead are two players: the leader two tops ahead with a look
# up at the tower on the fifth, the middle man held up on the second top (3.22-3.80, eyes on his feet) then quick; 0.03-0.58 s a top, landings to 0.63 m off centre, eyes on a spring. The POV is tick for tick the old take.

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
# v26 (Ryan): "int the final scence, the gaurd should turn around fully before getting shot." He hears the finisher arrive (2.85) and comes round 120 deg to face
# him, rifle with him, one eased turn 3.02-3.92; the kill beat is still 4.20.

## 12f
said: v27 (Ryan) "Ending: the guard getting shoved out of the tower, including the guard's POV of being flung" -- the finisher's eyes
capture: --map=marble --shot=portal --stage=trailer_finale_marble --bots=2 --pov=runner --rifle=projectile --set=wait=0.25 --seed=20261001
tape: finale
seconds: 5.2
in: 0.9
freeze: waive
# v37: refilmed on the walled marble without --look=social; smoke unchanged numbers: arrives 2.85, finale shove 3.73.
# corridor sprint from 320 deg into the portal (arrives 2.85), in the room behind the guard, scoped at the 126 window: 0.35 s, then
# straight at him; the shipped finale shove at 3.83 throws him out of the open tower (2x an ordinary shove) and the game's
# cinematic (FinaleView) takes every view for the 2.0 s kill beat. The cut ends on the shove.
# v28 (Ryan): "The cut between the runner going into the tower and walking over to push the sniper must be one continuous action with no
# random cut" and "remove the sniper vignette ... no scope view in the ending". The portal is a teleport, so g1 opens in the room on his
# arrival and he goes for the guard at once (wait=0): one take from the room, through the shove, into the game's own cinematic. 12g unused.

## 12g
said: v27 (Ryan) "including the guard's POV of being flung" -- the guard's own screen: his scope on the ring, the shove, the game's cinematic of the throw
capture: --map=marble --shot=portal --stage=trailer_finale_marble --bots=2 --pov=guard --hud=crosshair --rifle=projectile --set=wait=0 --seed=20261001
tape: finale
seconds: 3.6
in: 2.6
freeze: waive
# the finale tape down the guard's eyes: scoped on the ring at 126, the shove at 3.83, then FinaleView side-on to the throw.

## 12s
said: Ryan (v52 cut A) "it needs to just be a gameplay capture of a bot going through the portal, and shoving the gaurd, and that gaurd going flying"; "dont fake it for the trailer" (the first-person shove, main b4c50f98)
capture: --map=marble --shot=portal --stage=trailer_finale_marble --bots=2 --pov=runner --rifle=projectile --set=wait=0.25;from=311,52.4 --seed=20261001
tape: finale_fp
seconds: 5.65
in: 0.8
freeze: waive
# 12f's finale from 9 deg further back (from 311; arrives 3.60, shove 4.48, round resets 6.48): the run is 0.75 s longer so portal, FP shove and the game's own throw cinematic fill 5.65 s before the round resets.

## 13
said: v4 "Hell S3, runner POV running through and bouncing on a crack"
capture: --shot=s4_edge --stage=trailer_crack --bots=2 --pov=runner --rifle=projectile --set=shimmer=0.06;skip=1;skip_go=1.3;skip_from=142.6,52.4;skip_pace=1.1 --seed=20261001
tape: crack
seconds: 3.5
in: 1.7
freeze: waive
# v28 (Ryan): "put the green runner in front of the POV. Green does NOT bounce on the pads; they jump over them" (skip=1): the mate
# runs the r 52.4 pad column 3 deg ahead and jumps each crack (takeoff 146.0 and 156.2 deg, apex 1.05 m, never launched); the POV's
# path is the old one, his eyes held lower so green stays in frame. In the game a pad costs no forward speed, so green leads by
# ~3 deg and gains under a degree; he is on the ground running while the POV hangs 3.8 m up.
# v27 (Ryan): "cut the POV wind-up before running at the pad. Start already running." The take runs to 4.9; k1 opens after the break, him at a run.
# behind the 139 deg lip rock, breaks across the gap at 2.05; the round lands where he was at 2.55; launched off the crack at 148.3 deg at 2.60, peaks 3.8 m up ~3.2
# v19: his eyes go up after the mate thrown off the crack ahead (2.23); launched himself 2.60; the round crosses ahead of the mate ~3.1, a look across at the tower, down for the landing
# v22 (Ryan): "some of that exact same jankiness in the runner pov bouncing guys shot." Three joins: a flick left in the cut's first frames (now done before it opens), a snap at the break, and in the air a whip left as he passed his run target then a snap onto the lane (~3.1). The run aims past the target and every join is carried; launched 2.63, lands ~3.78; crack re-taped (the mate, the squeeze 2.75 and the miss 3.17 unchanged)

## 14
said: v4 "Same moment from the guard scope: fires, misses, the runner launches up out of cover"
capture: --shot=s4_edge --stage=trailer_crack --bots=2 --pov=guard --hud=crosshair --rifle=projectile --set=shimmer=0.06;skip=1;skip_go=1.3;skip_from=142.6,52.4;skip_pace=1.1 --seed=20261001
tape: crack
seconds: 2.6
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
capture: --map=res://maps/forest/forest_green.tscn --shot=pack_lead --stage=trailer_forest_pack --bots=3 --pov=guard --hud=crosshair --rifle=projectile --set=lift=1;fire=3.15;zone=2 --seed=20261001
tape: forest_pack
seconds: 5.0
in: 0.9
freeze: waive
# rough_v20_green: shot 5 in the green forest (forest_green.tscn, same geometry), same stage and tape
# v26 (note 2): the lead looks up at the tower (~1.6) and swings wide outside the 33 and 39 trunks (r 55.1-55.5), the victim starts outside the tail and cuts
# in across his line (r 52.6 to 51.4), steady on r 51.7 from ~2.4; the tail (the POV) is untouched. Squeeze 3.17, hit 3.55 at 32.0 deg, as before.

## 9ag
said: v5 "Forest, runner POV: a second runner beside him at the inner edge, a visible shove, he tips over the edge and drops out of frame into the mist"
capture: --map=res://maps/forest/forest_green.tscn --shot=pack_lead --stage=trailer_forest_pit --bots=3 --pov=runner --look=social --rifle=projectile --set=third=0 --seed=20261001
tape: forest_pit
seconds: 2.5
in: 1.04
freeze: waive
# rough_v20_green: shot 9a in the green forest (forest_green.tscn, same geometry), same stage and tape
# v27 (Ryan): "no purple player running in the background, since they aren't in the previous scene": third=0, the third man parked and hidden; forest_pit re-taped.
# v26 (Ryan): "in ths shove scene, theres just a random cut for nor eason before the player gets shoved." No edit lands there: his head snapped 19 deg in ONE
# tick at the gate (take 1.96, 1.06 s before the shove), a jump cut inside the take. Every lane join is carried now; the shove (2.93, 149.9 deg) is unchanged.

## 9bg
said: v5 "Forest, the shoved runner's POV: the edge he was shoved from with the shover on it looking down, falling away, the mist rushing up"
capture: --map=res://maps/forest/forest_green.tscn --shot=pack_lead --stage=trailer_forest_pit --bots=3 --pov=runner --look=social --rifle=projectile --set=pov=victim;third=0 --seed=20261001
tape: forest_pit
seconds: 2.3
in: 2.96
freeze: waive
# rough_v20_green: shot 9b in the green forest (forest_green.tscn, same geometry), same stage and tape

## 1v
said: v25 "first thing to do for it, extend the first shot a little further so we can start the song like on second earlier."
capture: --shot=s3_open_lane --stage=trailer_open --pov=guard --hud=crosshair --bots=3 --rifle=projectile --set=fire_at=3.24;shimmer=0.06 --seed=20261001
tape: open
seconds: 4.8
in: 0.75
freeze: waive
# rough_v25_vivaldi: shot 1 on a longer window (take 0.75-5.55), same stage and tape; cuts/01.mp4 stays v24's

## 5h
said: v25 "then, in the marble runnign shot, have someone get hit, again, on the beat."
capture: --map=marble --shot=pack_lead --stage=trailer_marble_track --bots=3 --pov=guard --hud=crosshair --rifle=projectile --set=fire=2.6 --seed=20261001
tape: marble_hit
seconds: 3.4
in: 1.8
freeze: waive
# rough_v25_vivaldi: 5b restaged with a real rifle hit. The hand rides the man behind (Runner_2) from the start; squeeze 2.62 as he
# nears the 126 column, the round meets him in the gap at 128.0 deg (hit 2.97), the shipped ghost rule (he goes limp). 5b keeps its tape.
# v26 (Ryan): "for like the marble shot, where its only the snipers pov, it should be the player in the front." The hand rides the LEAD (Runner_1) from the start:
# squeeze 2.62, hit 2.97 in the gap at 128.4 deg; the two behind flinch, look up at the tower a beat apart and run past. Paths as 5b (note 2).
# v37: ArcWall126 now stands on that stretch (smoke: the round struck it at 128.5). The stage turned +24 deg (turn dial) onto the clear 132-182 stretch, window 150: smoke squeeze 2.62, hit 2.97 at 152.4.

## 10v
said: v25 "have the shove line up with a beat of the song. both shoves, and every shot."
capture: --map=marble --shot=pack_lead --stage=trailer_marble_column --bots=2 --pov=guard --hud=crosshair --rifle=projectile --seed=20261001
tape: marble_column
seconds: 3.2
in: 2.75
freeze: waive
# rough_v25_vivaldi: 10b on a longer window (take 2.75-5.95), same stage and tape: the shot holds on him to the next downbeat

## 7v
said: v25a "the shot with the cover doesnt read anymore. they peak out, cut straight to the shot, where the player isnt even in fram. for it to read right, the player has to be in frame and we need to watch the dodge."
capture: --shot=cover_side --stage=trailer_duel2 --bots=1 --pov=guard --hud=crosshair --rifle=projectile --set=kick=0.3;shimmer=0.06 --seed=20261001
tape: duel_dodge
seconds: 2.4
in: 3.0
freeze: waive
# rough_v25_vivaldi: 7 with the scope held down through the shot (the hand's kick 0.3, as the marble scope): he stands in the open under
# the crosshair, bolts for the rock, the round lands on the ground he left. The runner and every time are the duel tape's; 7 keeps its tape.

# v60 refilm begin

## 1r
said: v60 refilm of the cold open: the guard's window from the lead-in behind the lip rock through the squeeze (v59 0-164)
capture: --shot=s3_open_lane --stage=trailer_open_pre --pov=guard --hud=crosshair --bots=3 --rifle=projectile --set=fire_at=3.24;shimmer=0.06 --seed=20261001
tape: open_pre
seconds: 4.5
in: 6.15
freeze: waive
expect: hit Runner_2 9.07-9.13

## 2r
said: v60 refilm of 2: the runner behind the victim looks up at the tower (v59 165-330)
capture: --shot=s3_open_lane --stage=trailer_open --pov=runner --bots=3 --rifle=projectile --set=fire_at=3.24;eye_at=4.3;eye_swing=0.4;eye_from=60:49;shimmer=0.06 --seed=20261001
tape: open
seconds: 4.55
in: 1.8166
freeze: waive
expect: hit Runner_2 3.57-3.63

## 2v
said: v66/v67 (Ryan, #295): 2r, the logo's older eye (pre-49fcc837 glb and textures), with its look-over landing so the tower eye sits where the title card's eye-as-O is, zoomed to its size
capture: --shot=s3_open_lane --stage=trailer_open --pov=runner --bots=3 --rifle=projectile --set=fire_at=3.24;eye_at=4.3;eye_swing=0.4;eye_from=60:49;shimmer=0.06;eye_frame=3.95:4.45:4.05:4.75:764.61:520.08:146.75;eye_assets=res://tools/content/projects/trailer_reveal/old_eye --seed=20261001
tape: open
seconds: 4.55
in: 1.8166
freeze: waive
expect: hit Runner_2 3.57-3.63; eye_framed 4.70-4.85

## 4tr
said: v60 refilm of 4t: the forest runner (v59 662-787)
capture: --map=res://maps/forest/forest_green.tscn --shot=pack_lead --stage=trailer_forest_sprint --bots=3 --pov=runner --look=social --rifle=projectile --set=zone=2 --seed=20261001
tape: forest_thread
seconds: 3.9
in: 0.4666
freeze: waive
expect: alive Runner_1

## 5gr
said: v60 refilm of 5g: the forest scope shot (v59 788-912)
capture: --map=res://maps/forest/forest_green.tscn --shot=pack_lead --stage=trailer_forest_pack --bots=3 --pov=guard --hud=crosshair --rifle=projectile --set=lift=1;fire=3.15;zone=2 --seed=20261001
tape: forest_pack
seconds: 3.85
in: 1.6666
freeze: waive
expect: hit Runner_2 3.52-3.58

## 5hr
said: v60 refilm of 5h: the marble scope shot, Movie Maker so the round's flight does not stall (v59 913-995; Ryan note 1)
capture: --map=marble --shot=pack_lead --stage=trailer_marble_track --bots=3 --pov=guard --hud=crosshair --rifle=projectile --set=fire=2.6 --seed=20261001
tape: marble_hit
seconds: 3.15
in: 1.8666
freeze: waive
expect: hit Runner_1 2.94-3.00

## 20
said: v60 beach scope: the sniper's shot on the sand (v59 996-1063; filmed untaped before, now an entry)
capture: --map=beach --shot=pack_lead --stage=trailer_beach_track --bots=3 --pov=guard --hud=crosshair --rifle=projectile --shimmer=0 --set=fire=2.6 --seed=20261001
seconds: 2.9
in: 1.6666
freeze: waive
expect: hand beat 2.59-2.65; hit Runner_1 3.12-3.18

## 6r
said: v60 refilm of 6: hell runner behind the rock (v59 1064-1129)
capture: --shot=cover_side --stage=trailer_duel2 --bots=1 --pov=runner --rifle=projectile --set=shimmer=0.06 --seed=20261001
tape: duel
seconds: 2.9
in: 1.5666
freeze: waive
expect: hit MapBaseS2Collision 4.22-4.28

## 7r
said: v60 refilm of 7: hell scope (v59 1130-1207)
capture: --shot=cover_side --stage=trailer_duel2 --bots=1 --pov=guard --hud=crosshair --rifle=projectile --set=shimmer=0.06 --seed=20261001
tape: duel
seconds: 3.05
in: 2.45
freeze: waive
expect: hit MapBaseS2Collision 4.22-4.28

## 8r
said: v60 refilm of 8: hell runner after the miss (v59 1208-1323)
capture: --shot=cover_side --stage=trailer_duel2 --bots=1 --pov=runner --rifle=projectile --set=shimmer=0.06 --seed=20261001
tape: duel
seconds: 3.7
in: 4.65
freeze: waive
expect: hit MapBaseS2Collision 4.22-4.28

## 21
said: v60 beach run: one continuous take, no splice (v59 1324-1448; Ryan note 2)
capture: --map=beach --shot=pack_lead --stage=trailer_beach_run --bots=3 --pov=runner --rifle=projectile --shimmer=0 --seed=20261001
seconds: 3.85
in: 0.4666
freeze: waive
expect: alive Runner_1

## 9agr
said: v60 refilm of 9ag: the forest shover, one take from its first frame (v59 1449-1592; Ryan note 3)
capture: --map=res://maps/forest/forest_green.tscn --shot=pack_lead --stage=trailer_forest_pit --bots=3 --pov=runner --look=social --rifle=projectile --set=third=0 --seed=20261001
tape: forest_pit
seconds: 4.2
in: 0.0333
freeze: waive
expect: shove Runner_2 2.90-2.96

## 9bgr
said: v60 refilm of 9bg: the falling victim (v59 1593-1716)
capture: --map=res://maps/forest/forest_green.tscn --shot=pack_lead --stage=trailer_forest_pit --bots=3 --pov=runner --look=social --rifle=projectile --set=pov=victim;third=0 --seed=20261001
tape: forest_pit
seconds: 3.85
in: 1.9666
freeze: waive
expect: shove Runner_2 2.90-2.96

## 10ar
said: v60 refilm of 10a: the marble runner (v59 1717-1851)
capture: --map=marble --shot=pack_lead --stage=trailer_marble_column --bots=2 --pov=runner --rifle=projectile --set=late=1;lead=1.0;now=1;back_fire=0.1;kick=0.1;back_pace=0.5;follow=0.4;run_after=0.9;settle_omega=45;max_rate=55 --seed=20261001
tape: marble_column
seconds: 4.0
in: 0.75
freeze: waive
expect: shove Runner_2 2.97-3.03

## 10br
said: v60 refilm of 10b: the scope as the victim is hit (v59 1852-2009)
capture: --map=marble --shot=pack_lead --stage=trailer_marble_column --bots=2 --pov=guard --hud=crosshair --rifle=projectile --set=late=1;lead=1.0;now=1;back_fire=0.1;kick=0.1;back_pace=0.5;follow=0.4;run_after=0.9;settle_omega=45;max_rate=55 --seed=20261001
tape: marble_column
seconds: 4.4
in: 1.75
freeze: waive
expect: shove Runner_2 2.97-3.03; hit Runner_1 4.94-5.00

## 22
said: v61 (arc 34.4: 22 frames more sand, the marble run matched at its clock 158) v60 beach portal run: the first half of the portal run on the sand, the marble run's own steps and pace, one run to one portal (v59 2010-2093; Ryan note 4)
capture: --map=beach --shot=portal --stage=trailer_beach_portal --bots=3 --pov=runner --rifle=projectile --shimmer=0 --seed=20261001 --set=arc=34.4
seconds: 4.1
in: 0.0
freeze: waive
expect: stage arrived 3.90-4.00

## 12sr
said: v60 refilm of 12s: the marble half of the portal run, the first-person shove, the guard thrown with his rifle (v59 2094-2316; Ryan notes 5, 6)
capture: --map=marble --shot=portal --stage=trailer_finale_marble --bots=2 --pov=runner --rifle=projectile --set=wait=0.25;from=311,52.4 --seed=20261001
tape: finale_fp
seconds: 5.55
in: 1.1666
freeze: waive
expect: stage arrived 3.57-3.63; stage kill 4.45-4.51

# v60 refilm end

# no-beach begin
# Cut B (decision 384): v65 with the three beach slots replaced; refilm_v65_nobeach.py builds it.

## 14r
said: no-beach cut, hell scope in the beach scope's slot (v65 996-1063): 14 refilmed with Movie Maker on the current game, the guard fires on beat 33 (1014) as the runner flies the crack
capture: --shot=s4_edge --stage=trailer_crack --bots=2 --pov=guard --hud=crosshair --rifle=projectile --set=shimmer=0.06;skip=1;skip_go=1.3;skip_from=142.6,52.4;skip_pace=1.1 --seed=20261001
tape: crack
seconds: 2.6
in: 1.95
freeze: waive
expect: hit MapBaseS3Collision 3.54-3.60

## 11r
said: no-beach cut, lava platforming in the portal run's first part (v65 2010-2089): 11 refilmed with Movie Maker on the current game, hop 3 lands on beat 83 (2048)
capture: --shot=lava_parkour --stage=lavaparkour --bots=3 --set=line=3;solo=1;shimmer=0.0 --pov=runner --seed=20261001
tape: lake
seconds: 5.5
in: 1.2
freeze: waive
expect: alive Runner_3

## 23
said: Ryan "ok, lets do a marble shot. from a runners pov, watching the sniper tower, snipe at two runners, much further ahead them themselves." In the beach run's slot (v65 1324-1448); hits on beats 50 (1365) and 53 (1428)
capture: --map=marble --shot=pack_lead --stage=trailer_marble_far --bots=3 --pov=runner --rifle=projectile --seed=20261001
seconds: 3.5
in: 0.9
freeze: waive
expect: hit Runner_2 2.29-2.35; hit Runner_3 3.34-3.40

## 24
said: Ryan on n16 "for the fucking hell sniper shot, you just cut in the shot from the bounce pads, that doesnt even hit?" -- a hell scope shot in 5hr's style: S1, the guard leads the first of three and hits him on beat 30 (952); he lies where he falls
capture: --shot=pack_lead --stage=trailer_hell_track --bots=3 --pov=guard --hud=crosshair --rifle=projectile --set=fire=2.6;shimmer=0.06 --seed=20261001
seconds: 3.0
in: 1.9
freeze: waive
expect: hit Runner_1 2.94-3.00

# no-beach end

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
grade_hell: lift 2.6 3
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
# v26 (Ryan's seven notes on v24 and v25_vivaldi, quoted on shots 2, 5b, 5h, 5g, 6, 9ag, 10a, 11, 12): open (the look only), forest_pack, marble_track, forest_pit,
# marble_column, lake and finish restaged and re-taped; every shot refilmed in rough mode on main 6547970 (the green forest's new light; its scope reticle and rifle are
# in every shot, not one). The edit is v24's but for d1: in 1.10 (take 2.10, behind the rock), five beats not seven (k28 to k33), so every cut after it is two beats
# earlier, still on the grid (the end card on k96, 39.60 s; 42.80 s). In-points follow each new take's frame lag against its v24 take (a2 d1 d2 p2 m2 +1, t2 -4), a frame less 4 ms.
# Hell grade (Ryan): "for the trailer, we have to make hell a bit birhter to match the other two maps, without making it looks blown out". Trailer only, at assembly
# (assemble.py grade): every hell line's RGB times 1 + 1.6 * (1 - max)^3 -- rock and bodies up to 2.6x, lava and embers held, hue kept, black and white fixed.
# Crosshair (Ryan): "the crosshair in v26 needs to be updated": game commit 40f846c cherry-picked; 1 1v 5g 5b 5h 7 7v 10b 10v 14 refilmed with the four-arm cross.
| line | clip | in | len | fit | speed | text | grade |
| a1 | cuts/01.mp4@0.35:2.70 | | | beat 2.70 | | | hell |
| a2 | cuts/02.mp4@1.7127:3.00 | | | beat 3.00 | | | hell |
| a3 | cuts/title_zoom10.mp4@0:2.1333 | | | beat 2.1333 | | |  |
| a4 | cuts/card2_zoom10.mp4@0:2.4667 | | | beat 2.4667 | | |  |
| h1 | cuts/04g.mp4@0.4:1.7667 | | | beat 1.7667 | | |  |
| h2 | cuts/05g.mp4@1.6:1.4 | | | beat 1.4 | | |  |
| m0 | cuts/05b.mp4@0:2.1167 | | | beat 2.1167 | | |  |
| d1 | cuts/06.mp4@1.1127:1.7833 | | | beat 1.7833 | | | hell |
| d2 | cuts/07.mp4@1.6127:2.1167 | | | beat 2.1167 | | | hell |
| d3 | cuts/08.mp4@0:2.1167 | | | beat 2.1167 | | | hell |
| p1 | cuts/09ag.mp4@0:2.4667 | | | beat 2.4667 | | |  |
| p2 | cuts/09bg.mp4@0.0127:1.7667 | | | beat 1.7667 | | |  |
| m1 | cuts/10a.mp4@0:2.1167 | | | beat 2.1167 | | |  |
| m2 | cuts/10b.mp4@0.0127:2.1167 | | | beat 2.1167 | | |  |
| t2 | cuts/11.mp4@1.9293:2.4667 | | | beat 2.4667 | | | hell |
| k1 | cuts/13.mp4@0:2.1167 | | | beat 2.1167 | | | hell |
| k2 | cuts/14.mp4@0:1.7667 | | | beat 1.7667 | | | hell |
| g1 | cuts/12.mp4@0.15:3.1833 | | | beat 3.1833 | | |  |
| e1 | cuts/end_v3.mp4@0.4:3.2 | | | beat 3.2 | | |  |

## script rough_v42
# v42 (Ryan on v41): "the shove half is fine, the sniper half jumps and snaps around like a robot". m1 is v41's; m2 the re-taped 10b (accel cap, 0.3 s aim blends).
# Six real-time takes each dropped 4-10 frames in the capture (duplicates at random frames), so 10b was filmed --movie (frame exact, no drops).
# v41's master with m2 1833-1987 <- cuts/10b.mp4 frames 0-154 (graph: final\master\rough_v42.graph.txt); psnr: only 1833-1987 differ.

## script rough_v41
# v41 (Ryan): "we dont even see the fucking shove from the runners pov" and "the way the sniper tracks is comopletely and utterly unatural". m1: the shove at 1.25 s in, him 12 deg out by its end.
# m2: the scope still on the wall's end 0.25 s, the shove, tracked (peak 54.8 deg/s), he breaks back 4.02, squeeze 4.37 1.98 m ahead along his run, hit 4.73 at 201.1 deg, 0.6 s of the drop.
# Expects on the v40 tape: m1 shove 0.20 s before the cut's end (FAIL), m2 scope on the wall's end (FAIL: opened after the shove, rest 3.5 deg off); v40's lead was 1.98 m (ok). v41 all ok.
# v40's master with m1 1713-1832 <- cuts/10a.mp4 frames 0-119 and m2 1833-1987 <- cuts/10b.mp4 frames 0-154 (graph: final\master\rough_v41.graph.txt); psnr: only 1713-1987 differ.

## script rough_v40
# v40 (Ryan): "the sniper doesnt aim, the guy gets pushed out, and he just aim bots to a spots and shoot." The scope rests on the wall's end (197.0), comes onto him 0.22 s
# after he clears it, trails the throw (follow 0.5) and overshoots 0.98 deg as he lands, corrects; onto the held-over mark, leads him as he breaks (run_after 1.0), sits on the mark
# 0.25 s and squeezes (4.88, hit 5.25 at 198.4). Peak 47.3 deg/s, lag 0.067 s. Smoke expects on v39's aim: peak 218 deg/s, lag 0.000 s, settle 0.00 s (FAIL); v40 all ok.
# v39's master with only m2 1833-1987 <- cuts/10b.mp4 frames 35-189 (graph: final\master\rough_v40.graph.txt); psnr against v39: only 1833-1987 differ.

## script rough_v39
# v39 (Ryan): "the sniper pov sucks ... you see the runner get shoved for one frame, then they go out of frame, then the sniper pans over". The scope rides him
# (guard_hand centre beat, omega 10, kick 0.1) from before the shove; he jogs back (back_pace 0.5) so the led squeeze keeps him inside half the scope; hit 4.73 at 203.4.
# Smoke expects: v38 tape worst 150% of the scope radius / 11.0 deg (FAIL); v39 tape 43% / 3.2 deg (ok). m2 1833-1987 <- cuts/10b.mp4 frames 35-189 (he clears the wall on 35).
# Seams (Ryan: "visual glitches between the last hell shot and the marble shot"): v37 spliced at v36_timing.txt's rounded seconds, not v36's real cuts (m0 843, g1 2438),
# leaving v36's gold frames at 843 and 2438-2442; and 12f@2.05 opened on two portal frames (the take arrives 2 frames after the smoke). Spliced by frame on the real cuts:
# 843-952 <- cuts/05h.mp4 frames 37-146, 2438-2581 <- cuts/12f.mp4 frames 125-268 (first frame in the room). psnr against v38: only 843, 1833-1987, 2438-2581 differ.

## script rough_v38
# v38 (Ryan): "he needs to get shoved further out so that when he gets shot during him running back, his ragdoll doesnt fly behind cover." v37's lossless master with only m1 (1713-1832 <- cuts/10a.mp4@0)
# and m2 (1833-1987 <- cuts/10b.mp4@0.7) replaced, same in/len (graph: final\master\rough_v38.graph.txt). Shove impulse 16 -> 28: hit 4.73 at 200.6 deg (was 195.0), 6.7 deg past the wall's 193.9 end, in the guard's LoS. psnr: only frames 1713-1987 differ from v37.

## script rough_v37
# v37 (Ryan): "make the next version of the trailer, by reshooting the marble map scenes only." v36's lossless master (final\master\rough_v36.mkv, 2769 frames at 60,
# its flac bed copied) with only the marble frames replaced, same in/len: m0 844-952 <- cuts/05h.mp4@0.624, m1 1713-1832 <- cuts/10a.mp4@0, m2 1833-1987 <- cuts/10b.mp4@0.7,
# g1 2443-2581 <- cuts/12f.mp4@2.05 (graph: final\master\rough_v37.graph.txt). psnr against v36: every other frame identical. 46.15 s.

## script rough_v35
size: 1920x1080
music: voice/pineberry_rush_v27.flac
music_db: -0.5
music_fade: 0.02 2.5
captions: none
# v35 (Ryan): v33 exactly, picture cut from v33's lossless master, except the forest lines (h1 h2 p1 p2), refilmed on his new forest lighting.
# v34: v33 refilmed on main fd90f016 (forest contact shadows, player dapple, haze, pollen with the scope fix b6bdd878, leaf-green fog); h1/h2 moved to the foliage-dense 55-95 stretch (zone=2), same timing; shot 2's look-up smoothed on the tape.
# Ryan: hell and marble stay v33's takes: those lines are cut from v33's own lossless master at the same times; only a2 and the forest lines are new.
# v33: v32 with 4t 5g 9ag 9bg refilmed in the green forest (forest_green.tscn) on main 4b1ca5f3+ (depth haze, pollen, darker grass, leaves 0.55, dapple, canopy blend), same tapes.
# v33 title: back to the plain-text PANOPTICON card (title_zoom10, as v30), same timing.
# v32: v31 with 4t 5g 9ag 9bg refilmed in the golden forest (maps/forest/forest.tscn; the game itself still loads forest_green) from the same tapes.
# v31: v30's edit; forest shots (4t 5g 9ag 9bg) refilmed on current main (green forest dapple, flecks, sway, canopy blend). Hell and marble are v30's takes.
# v31 title: the title screen's wordmark (ui/main_menu.tscn GameTitle: IM Fell English, glyph spacing 14, cream, dark red shadow 4 px down, outline 6), scaled to the old card's width; frames/title_logo.png, the same 4% push-in -> cuts/title_zoom10.mp4.
# v30: v29's edit; every hell shot (1 2 6 7 8 11 13 14) refilmed on main c0c5f2b1 (lava ash and sparks, pit-fire shadow wave 2048, softer shadow filter, lightmap BAKE_GLOW 61, shimmer by distance and zoom, lava that kills); trailer shimmer 0.06, 0 on the lava parkour. Forest and marble are v29's takes.
# v29 (Ryan on v28): h2 (the forest hit) held half a bar longer, taken off the end of m0; the cut moves 0.70 s later, onto the bar 6 downbeat (14.06). Nothing else moves.
# v28 (Ryan on v27): cut for Pineberry Rush's structure, not the grid. Mapped from the recording (beat k = 5.703 + k*0.3483 s, bar = 4 beats):
# the intro builds -4..0, the drop on the title (k0, 5.70); phrase one runs k0-k28 (a lift at k16 and a fill k24-27); a held, thinner bar
# k28-35 (the music sits: d1/d2 hold); phrase two k36-60 (the forest shove section on its downbeats); the break k60-67 (marble shove held
# across it); the busy run k68-91 (lava, crack, quick cuts on the rolls); the second held bar k92-95 (the finale's shove at 38.0 on k93
# territory); the end card on the k96 downbeat, 39.13 s. Title hit kept at 5.70. Every cut is on a downbeat or the bar's 3; hits sit on beats.
| line | clip | in | len | fit | speed | text |
| a1 | final/master/rough_v33.mkv@0.0000:2.9167 | | | beat 2.9167 | | |
| a2 | final/master/rough_v33.mkv@2.9167:2.7833 | | | beat 2.7833 | | |
| a3 | final/master/rough_v33.mkv@5.7000:2.1000 | | | beat 2.1000 | | |
| a4 | final/master/rough_v33.mkv@7.8000:2.0833 | | | beat 2.0833 | | |
| h1 | cuts/04t.mp4@0.7000:2.0833 | | | beat 2.0833 | | |
| h2 | cuts/05g.mp4@1.7560:2.1000 | | | beat 2.1000 | | |
| m0 | final/master/rough_v33.mkv@14.0666:1.8167 | | | beat 1.8167 | | |
| d1 | final/master/rough_v33.mkv@15.8833:1.4000 | | | beat 1.4000 | | |
| d2 | final/master/rough_v33.mkv@17.2833:1.3000 | | | beat 1.3000 | | |
| d3 | final/master/rough_v33.mkv@18.5833:2.1000 | | | beat 2.1000 | | |
| p1 | cuts/09ag.mp4@0.3100:2.0833 | | | beat 2.0833 | | |
| p2 | cuts/09bg.mp4@0.0127:1.8833 | | | beat 1.8833 | | |
| m1 | final/master/rough_v33.mkv@24.6499:2.0000 | | | beat 2.0000 | | |
| m2 | final/master/rough_v33.mkv@26.6499:2.5833 | | | beat 2.5833 | | |
| t2 | final/master/rough_v33.mkv@29.2332:2.9333 | | | beat 2.9333 | | |
| k1 | final/master/rough_v33.mkv@32.1665:2.8000 | | | beat 2.8000 | | |
| k2 | final/master/rough_v33.mkv@34.9665:1.8500 | | | beat 1.8500 | | |
| g1 | final/master/rough_v33.mkv@36.8165:2.3167 | | | beat 2.3167 | | |
| e1 | final/master/rough_v33.mkv@39.1332:3.2000 | | | beat 3.2000 | | |

## script rough_v34
size: 1920x1080
music: voice/pineberry_rush_v27.flac
music_db: -0.5
music_fade: 0.02 2.5
captions: none
# v34: v33 refilmed on main fd90f016 (forest contact shadows, player dapple, haze, pollen with the scope fix b6bdd878, leaf-green fog); h1/h2 moved to the foliage-dense 55-95 stretch (zone=2), same timing; shot 2's look-up smoothed on the tape.
# Ryan: hell and marble stay v33's takes: those lines are cut from v33's own lossless master at the same times; only a2 and the forest lines are new.
# v33: v32 with 4t 5g 9ag 9bg refilmed in the green forest (forest_green.tscn) on main 4b1ca5f3+ (depth haze, pollen, darker grass, leaves 0.55, dapple, canopy blend), same tapes.
# v33 title: back to the plain-text PANOPTICON card (title_zoom10, as v30), same timing.
# v32: v31 with 4t 5g 9ag 9bg refilmed in the golden forest (maps/forest/forest.tscn; the game itself still loads forest_green) from the same tapes.
# v31: v30's edit; forest shots (4t 5g 9ag 9bg) refilmed on current main (green forest dapple, flecks, sway, canopy blend). Hell and marble are v30's takes.
# v31 title: the title screen's wordmark (ui/main_menu.tscn GameTitle: IM Fell English, glyph spacing 14, cream, dark red shadow 4 px down, outline 6), scaled to the old card's width; frames/title_logo.png, the same 4% push-in -> cuts/title_zoom10.mp4.
# v30: v29's edit; every hell shot (1 2 6 7 8 11 13 14) refilmed on main c0c5f2b1 (lava ash and sparks, pit-fire shadow wave 2048, softer shadow filter, lightmap BAKE_GLOW 61, shimmer by distance and zoom, lava that kills); trailer shimmer 0.06, 0 on the lava parkour. Forest and marble are v29's takes.
# v29 (Ryan on v28): h2 (the forest hit) held half a bar longer, taken off the end of m0; the cut moves 0.70 s later, onto the bar 6 downbeat (14.06). Nothing else moves.
# v28 (Ryan on v27): cut for Pineberry Rush's structure, not the grid. Mapped from the recording (beat k = 5.703 + k*0.3483 s, bar = 4 beats):
# the intro builds -4..0, the drop on the title (k0, 5.70); phrase one runs k0-k28 (a lift at k16 and a fill k24-27); a held, thinner bar
# k28-35 (the music sits: d1/d2 hold); phrase two k36-60 (the forest shove section on its downbeats); the break k60-67 (marble shove held
# across it); the busy run k68-91 (lava, crack, quick cuts on the rolls); the second held bar k92-95 (the finale's shove at 38.0 on k93
# territory); the end card on the k96 downbeat, 39.13 s. Title hit kept at 5.70. Every cut is on a downbeat or the bar's 3; hits sit on beats.
| line | clip | in | len | fit | speed | text |
| a1 | final/master/rough_v33.mkv@0.0000:2.9167 | | | beat 2.9167 | | |
| a2 | cuts/02.mp4@1.9070:2.7833 | | | beat 2.7833 | | |
| a3 | final/master/rough_v33.mkv@5.7000:2.1000 | | | beat 2.1000 | | |
| a4 | final/master/rough_v33.mkv@7.8000:2.0833 | | | beat 2.0833 | | |
| h1 | cuts/04t.mp4@0.7000:2.0833 | | | beat 2.0833 | | |
| h2 | cuts/05g.mp4@1.7560:2.1000 | | | beat 2.1000 | | |
| m0 | final/master/rough_v33.mkv@14.0666:1.8167 | | | beat 1.8167 | | |
| d1 | final/master/rough_v33.mkv@15.8833:1.4000 | | | beat 1.4000 | | |
| d2 | final/master/rough_v33.mkv@17.2833:1.3000 | | | beat 1.3000 | | |
| d3 | final/master/rough_v33.mkv@18.5833:2.1000 | | | beat 2.1000 | | |
| p1 | cuts/09ag.mp4@0.3100:2.0833 | | | beat 2.0833 | | |
| p2 | cuts/09bg.mp4@0.0127:1.8833 | | | beat 1.8833 | | |
| m1 | final/master/rough_v33.mkv@24.6499:2.0000 | | | beat 2.0000 | | |
| m2 | final/master/rough_v33.mkv@26.6499:2.5833 | | | beat 2.5833 | | |
| t2 | final/master/rough_v33.mkv@29.2332:2.9333 | | | beat 2.9333 | | |
| k1 | final/master/rough_v33.mkv@32.1665:2.8000 | | | beat 2.8000 | | |
| k2 | final/master/rough_v33.mkv@34.9665:1.8500 | | | beat 1.8500 | | |
| g1 | final/master/rough_v33.mkv@36.8165:2.3167 | | | beat 2.3167 | | |
| e1 | final/master/rough_v33.mkv@39.1332:3.2000 | | | beat 3.2000 | | |

## script rough_v33
size: 1920x1080
music: voice/pineberry_rush_v27.flac
music_db: -0.5
music_fade: 0.02 2.5
captions: none
# v33: v32 with 4t 5g 9ag 9bg refilmed in the green forest (forest_green.tscn) on main 4b1ca5f3+ (depth haze, pollen, darker grass, leaves 0.55, dapple, canopy blend), same tapes.
# v33 title: back to the plain-text PANOPTICON card (title_zoom10, as v30), same timing.
# v32: v31 with 4t 5g 9ag 9bg refilmed in the golden forest (maps/forest/forest.tscn; the game itself still loads forest_green) from the same tapes.
# v31: v30's edit; forest shots (4t 5g 9ag 9bg) refilmed on current main (green forest dapple, flecks, sway, canopy blend). Hell and marble are v30's takes.
# v31 title: the title screen's wordmark (ui/main_menu.tscn GameTitle: IM Fell English, glyph spacing 14, cream, dark red shadow 4 px down, outline 6), scaled to the old card's width; frames/title_logo.png, the same 4% push-in -> cuts/title_zoom10.mp4.
# v30: v29's edit; every hell shot (1 2 6 7 8 11 13 14) refilmed on main c0c5f2b1 (lava ash and sparks, pit-fire shadow wave 2048, softer shadow filter, lightmap BAKE_GLOW 61, shimmer by distance and zoom, lava that kills); trailer shimmer 0.06, 0 on the lava parkour. Forest and marble are v29's takes.
# v29 (Ryan on v28): h2 (the forest hit) held half a bar longer, taken off the end of m0; the cut moves 0.70 s later, onto the bar 6 downbeat (14.06). Nothing else moves.
# v28 (Ryan on v27): cut for Pineberry Rush's structure, not the grid. Mapped from the recording (beat k = 5.703 + k*0.3483 s, bar = 4 beats):
# the intro builds -4..0, the drop on the title (k0, 5.70); phrase one runs k0-k28 (a lift at k16 and a fill k24-27); a held, thinner bar
# k28-35 (the music sits: d1/d2 hold); phrase two k36-60 (the forest shove section on its downbeats); the break k60-67 (marble shove held
# across it); the busy run k68-91 (lava, crack, quick cuts on the rolls); the second held bar k92-95 (the finale's shove at 38.0 on k93
# territory); the end card on the k96 downbeat, 39.13 s. Title hit kept at 5.70. Every cut is on a downbeat or the bar's 3; hits sit on beats.
| line | clip | in | len | fit | speed | text |
| a1 | cuts/01.mp4@0.5300:2.9167 | | | beat 2.9167 | | |
| a2 | cuts/02.mp4@1.9070:2.7833 | | | beat 2.7833 | | |
| a3 | cuts/title_zoom10.mp4@0.0000:2.1000 | | | beat 2.1000 | | |
| a4 | cuts/card2_zoom10.mp4@0.0000:2.0833 | | | beat 2.0833 | | |
| h1 | cuts/04t.mp4@0.7000:2.0833 | | | beat 2.0833 | | |
| h2 | cuts/05g.mp4@1.7560:2.1000 | | | beat 2.1000 | | |
| m0 | cuts/05h.mp4@0.6240:1.8167 | | | beat 1.8167 | | |
| d1 | cuts/06.mp4@1.2500:1.4000 | | | beat 1.4000 | | |
| d2 | cuts/07.mp4@2.4500:1.3000 | | | beat 1.3000 | | |
| d3 | cuts/08.mp4@0.1000:2.1000 | | | beat 2.1000 | | |
| p1 | cuts/09ag.mp4@0.3100:2.0833 | | | beat 2.0833 | | |
| p2 | cuts/09bg.mp4@0.0127:1.8833 | | | beat 1.8833 | | |
| m1 | cuts/10a.mp4@0.0000:2.0000 | | | beat 2.0000 | | |
| m2 | cuts/10b.mp4@0.7000:2.5833 | | | beat 2.5833 | | |
| t2 | cuts/11.mp4@1.4300:2.9333 | | | beat 2.9333 | | |
| k1 | cuts/13.mp4@0.7300:2.8000 | | | beat 2.8000 | | |
| k2 | cuts/14.mp4@0.2800:1.8500 | | | beat 1.8500 | | |
| g1 | cuts/12f.mp4@2.0500:2.3167 | | | beat 2.3167 | | |
| e1 | cuts/end_v3.mp4@0.4000:3.2000 | | | beat 3.2000 | | |

## script rough_v32
size: 1920x1080
music: voice/pineberry_rush_v27.flac
music_db: -0.5
music_fade: 0.02 2.5
captions: none
# v32: v31 with 4t 5g 9ag 9bg refilmed in the golden forest (maps/forest/forest.tscn; the game itself still loads forest_green) from the same tapes.
# v31: v30's edit; forest shots (4t 5g 9ag 9bg) refilmed on current main (green forest dapple, flecks, sway, canopy blend). Hell and marble are v30's takes.
# v31 title: the title screen's wordmark (ui/main_menu.tscn GameTitle: IM Fell English, glyph spacing 14, cream, dark red shadow 4 px down, outline 6), scaled to the old card's width; frames/title_logo.png, the same 4% push-in -> cuts/title_zoom31.mp4.
# v30: v29's edit; every hell shot (1 2 6 7 8 11 13 14) refilmed on main c0c5f2b1 (lava ash and sparks, pit-fire shadow wave 2048, softer shadow filter, lightmap BAKE_GLOW 61, shimmer by distance and zoom, lava that kills); trailer shimmer 0.06, 0 on the lava parkour. Forest and marble are v29's takes.
# v29 (Ryan on v28): h2 (the forest hit) held half a bar longer, taken off the end of m0; the cut moves 0.70 s later, onto the bar 6 downbeat (14.06). Nothing else moves.
# v28 (Ryan on v27): cut for Pineberry Rush's structure, not the grid. Mapped from the recording (beat k = 5.703 + k*0.3483 s, bar = 4 beats):
# the intro builds -4..0, the drop on the title (k0, 5.70); phrase one runs k0-k28 (a lift at k16 and a fill k24-27); a held, thinner bar
# k28-35 (the music sits: d1/d2 hold); phrase two k36-60 (the forest shove section on its downbeats); the break k60-67 (marble shove held
# across it); the busy run k68-91 (lava, crack, quick cuts on the rolls); the second held bar k92-95 (the finale's shove at 38.0 on k93
# territory); the end card on the k96 downbeat, 39.13 s. Title hit kept at 5.70. Every cut is on a downbeat or the bar's 3; hits sit on beats.
| line | clip | in | len | fit | speed | text |
| a1 | cuts/01.mp4@0.5300:2.9167 | | | beat 2.9167 | | |
| a2 | cuts/02.mp4@1.9070:2.7833 | | | beat 2.7833 | | |
| a3 | cuts/title_zoom31.mp4@0.0000:2.1000 | | | beat 2.1000 | | |
| a4 | cuts/card2_zoom10.mp4@0.0000:2.0833 | | | beat 2.0833 | | |
| h1 | cuts/04t.mp4@0.7000:2.0833 | | | beat 2.0833 | | |
| h2 | cuts/05g.mp4@1.7560:2.1000 | | | beat 2.1000 | | |
| m0 | cuts/05h.mp4@0.6240:1.8167 | | | beat 1.8167 | | |
| d1 | cuts/06.mp4@1.2500:1.4000 | | | beat 1.4000 | | |
| d2 | cuts/07.mp4@2.4500:1.3000 | | | beat 1.3000 | | |
| d3 | cuts/08.mp4@0.1000:2.1000 | | | beat 2.1000 | | |
| p1 | cuts/09ag.mp4@0.3100:2.0833 | | | beat 2.0833 | | |
| p2 | cuts/09bg.mp4@0.0127:1.8833 | | | beat 1.8833 | | |
| m1 | cuts/10a.mp4@0.0000:2.0000 | | | beat 2.0000 | | |
| m2 | cuts/10b.mp4@0.7000:2.5833 | | | beat 2.5833 | | |
| t2 | cuts/11.mp4@1.4300:2.9333 | | | beat 2.9333 | | |
| k1 | cuts/13.mp4@0.7300:2.8000 | | | beat 2.8000 | | |
| k2 | cuts/14.mp4@0.2800:1.8500 | | | beat 1.8500 | | |
| g1 | cuts/12f.mp4@2.0500:2.3167 | | | beat 2.3167 | | |
| e1 | cuts/end_v3.mp4@0.4000:3.2000 | | | beat 3.2000 | | |

## script rough_v31
size: 1920x1080
music: voice/pineberry_rush_v27.flac
music_db: -0.5
music_fade: 0.02 2.5
captions: none
# v31: v30's edit; forest shots (4t 5g 9ag 9bg) refilmed on current main (green forest dapple, flecks, sway, canopy blend). Hell and marble are v30's takes.
# v31 title: the title screen's wordmark (ui/main_menu.tscn GameTitle: IM Fell English, glyph spacing 14, cream, dark red shadow 4 px down, outline 6), scaled to the old card's width; frames/title_logo.png, the same 4% push-in -> cuts/title_zoom31.mp4.
# v30: v29's edit; every hell shot (1 2 6 7 8 11 13 14) refilmed on main c0c5f2b1 (lava ash and sparks, pit-fire shadow wave 2048, softer shadow filter, lightmap BAKE_GLOW 61, shimmer by distance and zoom, lava that kills); trailer shimmer 0.06, 0 on the lava parkour. Forest and marble are v29's takes.
# v29 (Ryan on v28): h2 (the forest hit) held half a bar longer, taken off the end of m0; the cut moves 0.70 s later, onto the bar 6 downbeat (14.06). Nothing else moves.
# v28 (Ryan on v27): cut for Pineberry Rush's structure, not the grid. Mapped from the recording (beat k = 5.703 + k*0.3483 s, bar = 4 beats):
# the intro builds -4..0, the drop on the title (k0, 5.70); phrase one runs k0-k28 (a lift at k16 and a fill k24-27); a held, thinner bar
# k28-35 (the music sits: d1/d2 hold); phrase two k36-60 (the forest shove section on its downbeats); the break k60-67 (marble shove held
# across it); the busy run k68-91 (lava, crack, quick cuts on the rolls); the second held bar k92-95 (the finale's shove at 38.0 on k93
# territory); the end card on the k96 downbeat, 39.13 s. Title hit kept at 5.70. Every cut is on a downbeat or the bar's 3; hits sit on beats.
| line | clip | in | len | fit | speed | text |
| a1 | cuts/01.mp4@0.5300:2.9167 | | | beat 2.9167 | | |
| a2 | cuts/02.mp4@1.9070:2.7833 | | | beat 2.7833 | | |
| a3 | cuts/title_zoom31.mp4@0.0000:2.1000 | | | beat 2.1000 | | |
| a4 | cuts/card2_zoom10.mp4@0.0000:2.0833 | | | beat 2.0833 | | |
| h1 | cuts/04t.mp4@0.7000:2.0833 | | | beat 2.0833 | | |
| h2 | cuts/05g.mp4@1.7560:2.1000 | | | beat 2.1000 | | |
| m0 | cuts/05h.mp4@0.6240:1.8167 | | | beat 1.8167 | | |
| d1 | cuts/06.mp4@1.2500:1.4000 | | | beat 1.4000 | | |
| d2 | cuts/07.mp4@2.4500:1.3000 | | | beat 1.3000 | | |
| d3 | cuts/08.mp4@0.1000:2.1000 | | | beat 2.1000 | | |
| p1 | cuts/09ag.mp4@0.3100:2.0833 | | | beat 2.0833 | | |
| p2 | cuts/09bg.mp4@0.0127:1.8833 | | | beat 1.8833 | | |
| m1 | cuts/10a.mp4@0.0000:2.0000 | | | beat 2.0000 | | |
| m2 | cuts/10b.mp4@0.7000:2.5833 | | | beat 2.5833 | | |
| t2 | cuts/11.mp4@1.4300:2.9333 | | | beat 2.9333 | | |
| k1 | cuts/13.mp4@0.7300:2.8000 | | | beat 2.8000 | | |
| k2 | cuts/14.mp4@0.2800:1.8500 | | | beat 1.8500 | | |
| g1 | cuts/12f.mp4@2.0500:2.3167 | | | beat 2.3167 | | |
| e1 | cuts/end_v3.mp4@0.4000:3.2000 | | | beat 3.2000 | | |

## script rough_v30
size: 1920x1080
music: voice/pineberry_rush_v27.flac
music_db: -0.5
music_fade: 0.02 2.5
captions: none
# v30: v29's edit; every hell shot (1 2 6 7 8 11 13 14) refilmed on main c0c5f2b1 (lava ash and sparks, pit-fire shadow wave 2048, softer shadow filter, lightmap BAKE_GLOW 61, shimmer by distance and zoom, lava that kills); trailer shimmer 0.06, 0 on the lava parkour. Forest and marble are v29's takes.
# v29 (Ryan on v28): h2 (the forest hit) held half a bar longer, taken off the end of m0; the cut moves 0.70 s later, onto the bar 6 downbeat (14.06). Nothing else moves.
# v28 (Ryan on v27): cut for Pineberry Rush's structure, not the grid. Mapped from the recording (beat k = 5.703 + k*0.3483 s, bar = 4 beats):
# the intro builds -4..0, the drop on the title (k0, 5.70); phrase one runs k0-k28 (a lift at k16 and a fill k24-27); a held, thinner bar
# k28-35 (the music sits: d1/d2 hold); phrase two k36-60 (the forest shove section on its downbeats); the break k60-67 (marble shove held
# across it); the busy run k68-91 (lava, crack, quick cuts on the rolls); the second held bar k92-95 (the finale's shove at 38.0 on k93
# territory); the end card on the k96 downbeat, 39.13 s. Title hit kept at 5.70. Every cut is on a downbeat or the bar's 3; hits sit on beats.
| line | clip | in | len | fit | speed | text |
| a1 | cuts/01.mp4@0.5300:2.9167 | | | beat 2.9167 | | |
| a2 | cuts/02.mp4@1.9070:2.7833 | | | beat 2.7833 | | |
| a3 | cuts/title_zoom10.mp4@0.0000:2.1000 | | | beat 2.1000 | | |
| a4 | cuts/card2_zoom10.mp4@0.0000:2.0833 | | | beat 2.0833 | | |
| h1 | cuts/04t.mp4@0.7000:2.0833 | | | beat 2.0833 | | |
| h2 | cuts/05g.mp4@1.7560:2.1000 | | | beat 2.1000 | | |
| m0 | cuts/05h.mp4@0.6240:1.8167 | | | beat 1.8167 | | |
| d1 | cuts/06.mp4@1.2500:1.4000 | | | beat 1.4000 | | |
| d2 | cuts/07.mp4@2.4500:1.3000 | | | beat 1.3000 | | |
| d3 | cuts/08.mp4@0.1000:2.1000 | | | beat 2.1000 | | |
| p1 | cuts/09ag.mp4@0.3100:2.0833 | | | beat 2.0833 | | |
| p2 | cuts/09bg.mp4@0.0127:1.8833 | | | beat 1.8833 | | |
| m1 | cuts/10a.mp4@0.0000:2.0000 | | | beat 2.0000 | | |
| m2 | cuts/10b.mp4@0.7000:2.5833 | | | beat 2.5833 | | |
| t2 | cuts/11.mp4@1.4300:2.9333 | | | beat 2.9333 | | |
| k1 | cuts/13.mp4@0.7300:2.8000 | | | beat 2.8000 | | |
| k2 | cuts/14.mp4@0.2800:1.8500 | | | beat 1.8500 | | |
| g1 | cuts/12f.mp4@2.0500:2.3167 | | | beat 2.3167 | | |
| e1 | cuts/end_v3.mp4@0.4000:3.2000 | | | beat 3.2000 | | |

## script rough_v29
size: 1920x1080
music: voice/pineberry_rush_v27.flac
music_db: -0.5
music_fade: 0.02 2.5
captions: none
# v29 (Ryan on v28): h2 (the forest hit) held half a bar longer, taken off the end of m0; the cut moves 0.70 s later, onto the bar 6 downbeat (14.06). Nothing else moves.
# v28 (Ryan on v27): cut for Pineberry Rush's structure, not the grid. Mapped from the recording (beat k = 5.703 + k*0.3483 s, bar = 4 beats):
# the intro builds -4..0, the drop on the title (k0, 5.70); phrase one runs k0-k28 (a lift at k16 and a fill k24-27); a held, thinner bar
# k28-35 (the music sits: d1/d2 hold); phrase two k36-60 (the forest shove section on its downbeats); the break k60-67 (marble shove held
# across it); the busy run k68-91 (lava, crack, quick cuts on the rolls); the second held bar k92-95 (the finale's shove at 38.0 on k93
# territory); the end card on the k96 downbeat, 39.13 s. Title hit kept at 5.70. Every cut is on a downbeat or the bar's 3; hits sit on beats.
| line | clip | in | len | fit | speed | text |
| a1 | cuts/01.mp4@0.5300:2.9167 | | | beat 2.9167 | | |
| a2 | cuts/02.mp4@1.9070:2.7833 | | | beat 2.7833 | | |
| a3 | cuts/title_zoom10.mp4@0.0000:2.1000 | | | beat 2.1000 | | |
| a4 | cuts/card2_zoom10.mp4@0.0000:2.0833 | | | beat 2.0833 | | |
| h1 | cuts/04t.mp4@0.7000:2.0833 | | | beat 2.0833 | | |
| h2 | cuts/05g.mp4@1.7560:2.1000 | | | beat 2.1000 | | |
| m0 | cuts/05h.mp4@0.6240:1.8167 | | | beat 1.8167 | | |
| d1 | cuts/06.mp4@1.2500:1.4000 | | | beat 1.4000 | | |
| d2 | cuts/07.mp4@2.4500:1.3000 | | | beat 1.3000 | | |
| d3 | cuts/08.mp4@0.1000:2.1000 | | | beat 2.1000 | | |
| p1 | cuts/09ag.mp4@0.3100:2.0833 | | | beat 2.0833 | | |
| p2 | cuts/09bg.mp4@0.0127:1.8833 | | | beat 1.8833 | | |
| m1 | cuts/10a.mp4@0.0000:2.0000 | | | beat 2.0000 | | |
| m2 | cuts/10b.mp4@0.7000:2.5833 | | | beat 2.5833 | | |
| t2 | cuts/11.mp4@1.4300:2.9333 | | | beat 2.9333 | | |
| k1 | cuts/13.mp4@0.7300:2.8000 | | | beat 2.8000 | | |
| k2 | cuts/14.mp4@0.2800:1.8500 | | | beat 1.8500 | | |
| g1 | cuts/12f.mp4@2.0500:2.3167 | | | beat 2.3167 | | |
| e1 | cuts/end_v3.mp4@0.4000:3.2000 | | | beat 3.2000 | | |

## script rough_v28
size: 1920x1080
music: voice/pineberry_rush_v27.flac
music_db: -0.5
music_fade: 0.02 2.5
captions: none
# v28 (Ryan on v27): cut for Pineberry Rush's structure, not the grid. Mapped from the recording (beat k = 5.703 + k*0.3483 s, bar = 4 beats):
# the intro builds -4..0, the drop on the title (k0, 5.70); phrase one runs k0-k28 (a lift at k16 and a fill k24-27); a held, thinner bar
# k28-35 (the music sits: d1/d2 hold); phrase two k36-60 (the forest shove section on its downbeats); the break k60-67 (marble shove held
# across it); the busy run k68-91 (lava, crack, quick cuts on the rolls); the second held bar k92-95 (the finale's shove at 38.0 on k93
# territory); the end card on the k96 downbeat, 39.13 s. Title hit kept at 5.70. Every cut is on a downbeat or the bar's 3; hits sit on beats.
| line | clip | in | len | fit | speed | text |
| a1 | cuts/01.mp4@0.5300:2.9167 | | | beat 2.9167 | | |
| a2 | cuts/02.mp4@1.9070:2.7833 | | | beat 2.7833 | | |
| a3 | cuts/title_zoom10.mp4@0.0000:2.1000 | | | beat 2.1000 | | |
| a4 | cuts/card2_zoom10.mp4@0.0000:2.0833 | | | beat 2.0833 | | |
| h1 | cuts/04t.mp4@0.7000:2.0833 | | | beat 2.0833 | | |
| h2 | cuts/05g.mp4@1.7560:1.4000 | | | beat 1.4000 | | |
| m0 | cuts/05h.mp4@0.6240:2.5167 | | | beat 2.5167 | | |
| d1 | cuts/06.mp4@1.2500:1.4000 | | | beat 1.4000 | | |
| d2 | cuts/07.mp4@2.4500:1.3000 | | | beat 1.3000 | | |
| d3 | cuts/08.mp4@0.1000:2.1000 | | | beat 2.1000 | | |
| p1 | cuts/09ag.mp4@0.3100:2.0833 | | | beat 2.0833 | | |
| p2 | cuts/09bg.mp4@0.0127:1.8833 | | | beat 1.8833 | | |
| m1 | cuts/10a.mp4@0.0000:2.0000 | | | beat 2.0000 | | |
| m2 | cuts/10b.mp4@0.7000:2.5833 | | | beat 2.5833 | | |
| t2 | cuts/11.mp4@1.4300:2.9333 | | | beat 2.9333 | | |
| k1 | cuts/13.mp4@0.7300:2.8000 | | | beat 2.8000 | | |
| k2 | cuts/14.mp4@0.2800:1.8500 | | | beat 1.8500 | | |
| g1 | cuts/12f.mp4@2.0500:2.3167 | | | beat 2.3167 | | |
| e1 | cuts/end_v3.mp4@0.4000:3.2000 | | | beat 3.2000 | | |

## script rough_v27
size: 1920x1080
music: voice/pineberry_rush_v27.flac
music_db: -0.5
music_fade: 0.02 2.5
captions: none
# v27 (Ryan's ten notes, decision 292): v26's structure refilmed on the current game (main b649c64 + the tracer and scope fixes), no hell grade.
# Music: Mejer "Pineberry Rush" (UNLICENSED, private evaluation only; the file stays out of git): voice/pineberry_rush_v27.flac is the
# track from 13.72 s (on the beat) placed at 0.08 s, so song 19.34 s lands on the title card's first frame (5.70); fade out 2.5 s.
# Every cut after the title is on the song's beat, 172.3 bpm: beat k at 5.703 + k * 0.348299 s, frame-rounded. The beat counts are v26's
# (a3 k0, a4 k6, h1 k13 ... k2 k82, the end card was k96); g1 k87 and g2 k95 are the new finale, the end card on k100 (40.53).
# Notes: 1 g1 12f (the finisher's eyes to the shove) + g2 12g (the guard's scope, then the game's cinematic of the throw); 2 h1 4s
# (full sprint, own line, opens at speed); 3 m0 05h (the lead hit); 4 forest_pit third=0; 5 10a late=1 (eyes low, turned off the
# gap); 6 10b late=1 (thrown 8 m clear, the scope comes off the wall onto him, then the hit); 7 lake solo=1; 8 k1 opens on the run;
# 9 the tracer/round tail no longer drawn edge-on (game fix); 10 shot 2's eye holds on the course and turns onto him after his look.
| line | clip | in | len | fit | speed | text |
| a1 | cuts/01.mp4@0.35:2.70 | | | beat 2.70 | | |
| a2 | cuts/02.mp4@1.50:3.00 | | | beat 3.00 | | |
| a3 | cuts/title_zoom10.mp4@0:2.1000 | | | beat 2.1000 | | |
| a4 | cuts/card2_zoom10.mp4@0:2.4333 | | | beat 2.4333 | | |
| h1 | cuts/04s.mp4@0.65:1.7333 | | | beat 1.7333 | | |
| h2 | cuts/05g.mp4@1.6:1.4000 | | | beat 1.4000 | | |
| m0 | cuts/05h.mp4@0.15:2.0833 | | | beat 2.0833 | | |
| d1 | cuts/06.mp4@1.1127:1.7500 | | | beat 1.7500 | | |
| d2 | cuts/07.mp4@1.6127:2.0833 | | | beat 2.0833 | | |
| d3 | cuts/08.mp4@0:2.1000 | | | beat 2.1000 | | |
| p1 | cuts/09ag.mp4@0.15:2.4333 | | | beat 2.4333 | | |
| p2 | cuts/09bg.mp4@0.0127:1.7333 | | | beat 1.7333 | | |
| m1 | cuts/10a.mp4@0.1:2.1000 | | | beat 2.1000 | | |
| m2 | cuts/10b.mp4@0.35:2.0833 | | | beat 2.0833 | | |
| t2 | cuts/11.mp4@1.9293:2.4333 | | | beat 2.4333 | | |
| k1 | cuts/13.mp4@0.6:2.1000 | | | beat 2.1000 | | |
| k2 | cuts/14.mp4@0:1.7333 | | | beat 1.7333 | | |
| g1 | cuts/12f.mp4@0.217:2.7833 | | | beat 2.7833 | | |
| g2 | cuts/12g.mp4@0.85:1.7500 | | | beat 1.7500 | | |
| e1 | cuts/end_v3.mp4@0.4:3.2 | | | beat 3.2 | | |

## script rough_v24
size: 1920x1080
music: voice/sr20det.ogg
music_db: -3
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
# Kept as cut: the shot files are the v24 takes in cuts/_v25/.
| line | clip | in | len | fit | speed | text |
| a1 | cuts/_v25/01.mp4@0.35:2.70 | | | beat 2.70 | | |
| a2 | cuts/_v25/02.mp4@1.70:3.00 | | | beat 3.00 | | |
| a3 | cuts/title_zoom10.mp4@0:2.1333 | | | beat 2.1333 | | |
| a4 | cuts/card2_zoom10.mp4@0:2.4667 | | | beat 2.4667 | | |
| h1 | cuts/_v25/04g.mp4@0.4:1.7667 | | | beat 1.7667 | | |
| h2 | cuts/_v25/05g.mp4@1.6:1.4 | | | beat 1.4 | | |
| m0 | cuts/_v25/05b.mp4@0:2.1167 | | | beat 2.1167 | | |
| d1 | cuts/_v25/06.mp4@0.4:2.4833 | | | beat 2.4833 | | |
| d2 | cuts/_v25/07.mp4@1.6:2.1167 | | | beat 2.1167 | | |
| d3 | cuts/_v25/08.mp4@0:2.1167 | | | beat 2.1167 | | |
| p1 | cuts/_v25/09ag.mp4@0:2.4667 | | | beat 2.4667 | | |
| p2 | cuts/_v25/09bg.mp4@0:1.7667 | | | beat 1.7667 | | |
| m1 | cuts/_v25/10a.mp4@0:2.1167 | | | beat 2.1167 | | |
| m2 | cuts/_v25/10b.mp4@0:2.1167 | | | beat 2.1167 | | |
| t2 | cuts/_v25/11.mp4@2.0:2.4667 | | | beat 2.4667 | | |
| k1 | cuts/_v25/13.mp4@0:2.1167 | | | beat 2.1167 | | |
| k2 | cuts/_v25/14.mp4@0:1.7667 | | | beat 1.7667 | | |
| g1 | cuts/_v25/12.mp4@0.15:3.1833 | | | beat 3.1833 | | |
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

## script rough_v23
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

## script rough_v25_vivaldi
size: 1920x1080
music: voice/vivaldi_summer_presto_v25.flac
music_db: 3.7
music_fade: 0.02 2.5
captions: none
# Ryan on v23: "extend the first shot a little further so we can start the song like on second earlier. then, extend the section title card
# 'Online...' a litte more out so it hits the beat of the song. then hold it, until the song moves again, then start in with the forest shot.
# then, in the marble runnign shot, have someone get hit, again, on the beat. and the running forest shot should make sure the shot also
# happens on the beat. then the hwole cover shot is way too long for the tempo of this song ... this can be as short as it needs to. have the
# shove line up with a beat of the song. both shoves, and every shot. pretty much, take the trailer as it is, but put everything on the beat."
# Music: voice/vivaldi_summer_presto_v25.flac is the recording from 1.2013 s (v23's file started at 2.197 s): the first note at 0.17 s,
# the re-entry on the title card at 6.717 s. The beats are measured from the audio (the tempo drifts, 137 to 132 bpm):
# tools/content/projects/trailer_reveal.vivaldi_beats.csv. The check file is final/vivaldi_beats_check.m4a (a click a beat, louder on accents).
# Read as: "hits the beat" is the phrase's last note (bar 9 beat 3, 11.51 s) with the card still up; "moves again" is the tutti re-entry with
# the bass (bar 11, 13.22 s), where the forest starts. The cover sequence is one bar a shot (4.10 s, was 6.72 s). Hits, shoves and the
# launch are on beats; a round flies 0.35 to 0.42 s against a 0.44 to 0.46 s beat, so where the hit is on the beat the squeeze is a
# sixteenth off it (a1, m0) or both are split inside a frame and a half of their beats (h2, d2, k2).
# New picture: 1v and 10v (shots 1 and 10b on longer windows), 5h (the marble shot with a real hit), title_zoom25 and card2_zoom25 (the v10 push-in at the
# same rate, 2.7 s and 4.0 s). Every other cut is v23's file on a new in-point. In-points are a frame less 4 ms (a seek lands on the frame).
# Off a beat by more than a frame: m2's squeeze (5 frames after the shove it follows), k2's first man up (36 ms), g1's white frames (they
# start two frames before the end card, which is on the beat).
# v25a (Ryan): "the shot with the cover doesnt read anymore. they peak out, cut straight to the shot, where the player isnt even in fram. for it
# to read right, the player has to be in frame and we need to watch the dodge." and "i love the beat that it ends on". d2 opened on the squeeze and
# the kick threw him out of the scope. Now d2 is 7v (the same event, the scope held down through the shot) from a beat before the squeeze: him in
# the crosshair, the shot a beat in, the round on the ground a beat later, then d3 breaks on the accent. d1, d3 and all three cut points are
# unchanged; nothing was traded, every line after d2 is where it was (the end card on 29.1, 37.450).
# The plan. Beats are bar.beat of trailer_reveal.vivaldi_beats.csv (3/4; +1/8 the eighth after, +1/16 the sixteenth); times are seconds into the cut;
# (+N) is how far the frame sits from the measured beat, in ms. Every cut is the frame nearest its beat.
# line  in beat   at       out beat  len     picture; events
# a1    start      0.000   4.1       4.100   hell, guard scope: zooms in, fires, the middle runner drops; rifle fired 2.3+1/16 2.450 (-21), runner hit 3.1 2.800 (+1)
# a2    4.1        4.100   6.1       2.617   hell, the runner behind: the man ahead drops, he looks up at the tower; runner hit (his view) 4.3 4.950 (-5)
# a3    6.1        6.717   8.1       2.617   PANOPTICON
# a4    8.1        9.333   11.1      3.883   ONLINE ASYMMETRIC MULTIPLAYER, held through the phrase's last note and the lead-in
# h1    11.1      13.217   12.1      1.350   forest, runner POV between the trees
# h2    12.1      14.567   13.2      1.817   forest, guard scope: the kill; rifle fired 12.3 15.500 (+29), runner hit 13.1 15.900 (-29)
# m0    13.2      16.383   15.1      2.283   marble, guard scope past the columns: the man behind is hit (5h); rifle fired 13.3+1/16 16.950 (-14), runner hit 14.1 17.300 (-7)
# d1    15.1      18.667   16.1      1.367   hell, runner POV: out from behind the rock
# d2    16.1      20.033   17.1      1.383   hell, guard scope (7v): he stands in the open under the crosshair, bolts for the rock as the rifle fires, the round lands on the ground he left; rifle fired 16.2 20.517 (+14), round lands 16.3 20.933 (-24)
# d3    17.1      21.417   18.1      1.350   hell, runner POV: breaks cover and sprints; breaks cover 17.1 21.433 (+24)
# p1    18.1      22.767   19.2      1.800   forest, the shover's eyes: the shove at a run; shove 19.1 24.117 (-0)
# p2    19.2      24.567   20.2      1.350   forest, the shoved man's eyes: opens on the shove, falls; shove (his view) 19.2 24.567 (-6)
# m1    20.2      25.917   21.1+1/8  1.100   marble, the shover's eyes behind the columns; shove 21.1 26.800 (+2)
# m2    21.1+1/8  27.017   23.1      2.433   marble, guard scope: shoved out, fired on, hit (10v); shoved out 21.2 27.242 (-0), rifle fired 21.2 27.317 (+75), runner hit 21.3 27.683 (-1)
# t2    23.1      29.450   24.1+1/8  1.567   hell, lake platforming: opens on a leap; leap 23.1 29.433 (-15), lands and leaps 23.2+1/8 30.108 (-14), lands 24.1 30.817 (+25)
# k1    24.1+1/8  31.017   25.2+1/8  1.783   hell, runner POV: launched off the crack; launched off the crack 24.3 31.683 (+1)
# k2    25.2+1/8  32.800   26.3      1.533   hell, guard scope: fires at the men in the air, misses; first man up 25.3 32.983 (-36), rifle fired 26.1 33.483 (+18), second man up 26.1+1/16 33.567 (-8), round lands 26.2 33.917 (+14)
# g1    26.3      34.333   29.1      3.117   marble, corridor, portal, rifle, the guard shot (white frames); through the portal 28.1 36.133 (+30), kill flash 29.1 37.417 (-34)
# e1    29.1      37.450   end       3.200   end card
| line | clip | in | len | fit | speed | text |
| a1 | cuts/01v.mp4@0.0960:4.1000 | | | beat 4.1000 | | |
| a2 | cuts/02.mp4@1.8960:2.6167 | | | beat 2.6167 | | |
| a3 | cuts/title_zoom25.mp4@0.0000:2.6167 | | | beat 2.6167 | | |
| a4 | cuts/card2_zoom25.mp4@0.0000:3.8833 | | | beat 3.8833 | | |
| h1 | cuts/04g.mp4@0.4960:1.3500 | | | beat 1.3500 | | |
| h2 | cuts/05g.mp4@1.3627:1.8167 | | | beat 1.8167 | | |
| m0 | cuts/05h.mp4@0.2960:2.2833 | | | beat 2.2833 | | |
| d1 | cuts/06.mp4@1.4960:1.3667 | | | beat 1.3667 | | |
| d2 | cuts/07v.mp4@0.3793:1.3833 | | | beat 1.3833 | | |
| d3 | cuts/08.mp4@0.0793:1.3500 | | | beat 1.3500 | | |
| p1 | cuts/09ag.mp4@0.6627:1.8000 | | | beat 1.8000 | | |
| p2 | cuts/09bg.mp4@0.0000:1.3500 | | | beat 1.3500 | | |
| m1 | cuts/10a.mp4@0.9127:1.1000 | | | beat 1.1000 | | |
| m2 | cuts/10v.mp4@0.0627:2.4333 | | | beat 2.4333 | | |
| t2 | cuts/11.mp4@2.4293:1.5667 | | | beat 1.5667 | | |
| k1 | cuts/13.mp4@0.2960:1.7833 | | | beat 1.7833 | | |
| k2 | cuts/14.mp4@0.1793:1.5333 | | | beat 1.5333 | | |
| g1 | cuts/12.mp4@0.2127:3.1167 | | | beat 3.1167 | | |
| e1 | cuts/end_v3.mp4@0.3960:3.2000 | | | beat 3.2000 | | |

## script rough_v26_vivaldi
size: 1920x1080
music: voice/vivaldi_summer_presto_v25.flac
music_db: 3.7
music_fade: 0.02 2.5
captions: none
grade_hell: lift 2.6 3
# rough_v25_vivaldi with Ryan's seven notes ("cut a veriosn of vivaldi with the fixes"; "i love the beat that it ends on, so if possible, it should still end on that beat").
# Every cut point, length and beat is v25's (## script rough_v25_vivaldi has the plan in full); the end card is on bar 29 beat 1, 37.450. The picture is the v26 takes:
# the restaged shots (2, 4g, 5g, 5h, 9ag, 10a, 10v, 11, 12) and every other shot refilmed on main 6547970. In-points move by each new take's frame lag against the
# v25 take, so every event sits on the frame it had. Note 3 needs nothing here: d1 already opens behind the rock (take 2.50). m0's hit is now the leader (note 7).
# line  in beat   at       out beat  len     picture; events
# a1    start      0.000   4.1       4.100   hell, guard scope: zooms in, fires, the middle runner drops; rifle fired 2.3+1/16 2.450 (-21), runner hit 3.1 2.800 (+1)
# a2    4.1        4.100   6.1       2.617   hell, the runner behind: the man ahead drops, he looks up at the tower; runner hit (his view) 4.3 4.950 (-5)
# a3    6.1        6.717   8.1       2.617   PANOPTICON
# a4    8.1        9.333   11.1      3.883   ONLINE ASYMMETRIC MULTIPLAYER, held through the phrase's last note and the lead-in
# h1    11.1      13.217   12.1      1.350   forest, runner POV between the trees
# h2    12.1      14.567   13.2      1.817   forest, guard scope: the kill; rifle fired 12.3 15.500 (+29), runner hit 13.1 15.900 (-29)
# m0    13.2      16.383   15.1      2.283   marble, guard scope past the columns: the man behind is hit (5h); rifle fired 13.3+1/16 16.950 (-14), runner hit 14.1 17.300 (-7)
# d1    15.1      18.667   16.1      1.367   hell, runner POV: out from behind the rock
# d2    16.1      20.033   17.1      1.383   hell, guard scope (7v): he stands in the open under the crosshair, bolts for the rock as the rifle fires, the round lands on the ground he left; rifle fired 16.2 20.517 (+14), round lands 16.3 20.933 (-24)
# d3    17.1      21.417   18.1      1.350   hell, runner POV: breaks cover and sprints; breaks cover 17.1 21.433 (+24)
# p1    18.1      22.767   19.2      1.800   forest, the shover's eyes: the shove at a run; shove 19.1 24.117 (-0)
# p2    19.2      24.567   20.2      1.350   forest, the shoved man's eyes: opens on the shove, falls; shove (his view) 19.2 24.567 (-6)
# m1    20.2      25.917   21.1+1/8  1.100   marble, the shover's eyes behind the columns; shove 21.1 26.800 (+2)
# m2    21.1+1/8  27.017   23.1      2.433   marble, guard scope: shoved out, fired on, hit (10v); shoved out 21.2 27.242 (-0), rifle fired 21.2 27.317 (+75), runner hit 21.3 27.683 (-1)
# t2    23.1      29.450   24.1+1/8  1.567   hell, lake platforming: opens on a leap; leap 23.1 29.433 (-15), lands and leaps 23.2+1/8 30.108 (-14), lands 24.1 30.817 (+25)
# k1    24.1+1/8  31.017   25.2+1/8  1.783   hell, runner POV: launched off the crack; launched off the crack 24.3 31.683 (+1)
# k2    25.2+1/8  32.800   26.3      1.533   hell, guard scope: fires at the men in the air, misses; first man up 25.3 32.983 (-36), rifle fired 26.1 33.483 (+18), second man up 26.1+1/16 33.567 (-8), round lands 26.2 33.917 (+14)
# g1    26.3      34.333   29.1      3.117   marble, corridor, portal, rifle, the guard shot (white frames); through the portal 28.1 36.133 (+30), kill flash 29.1 37.417 (-34)
# e1    29.1      37.450   end       3.200   end card
# Hell grade (Ryan): "for the trailer, we have to make hell a bit birhter to match the other two maps, without making it looks blown out". Trailer only, at assembly
# (assemble.py grade): every hell line's RGB times 1 + 1.6 * (1 - max)^3 -- rock and bodies up to 2.6x, lava and embers held, hue kept, black and white fixed.
# Crosshair (Ryan): "the crosshair in v26 needs to be updated": game commit 40f846c cherry-picked; 1 1v 5g 5b 5h 7 7v 10b 10v 14 refilmed with the four-arm cross.
| line | clip | in | len | fit | speed | text | grade |
| a1 | cuts/01v.mp4@0.0960:4.1000 | | | beat 4.1000 | | | hell |
| a2 | cuts/02.mp4@1.9127:2.6167 | | | beat 2.6167 | | | hell |
| a3 | cuts/title_zoom25.mp4@0.0000:2.6167 | | | beat 2.6167 | | |  |
| a4 | cuts/card2_zoom25.mp4@0.0000:3.8833 | | | beat 3.8833 | | |  |
| h1 | cuts/04g.mp4@0.4960:1.3500 | | | beat 1.3500 | | |  |
| h2 | cuts/05g.mp4@1.3460:1.8167 | | | beat 1.8167 | | |  |
| m0 | cuts/05h.mp4@0.2460:2.2833 | | | beat 2.2833 | | |  |
| d1 | cuts/06.mp4@1.5127:1.3667 | | | beat 1.3667 | | | hell |
| d2 | cuts/07v.mp4@0.3960:1.3833 | | | beat 1.3833 | | | hell |
| d3 | cuts/08.mp4@0.0293:1.3500 | | | beat 1.3500 | | | hell |
| p1 | cuts/09ag.mp4@0.6460:1.8000 | | | beat 1.8000 | | |  |
| p2 | cuts/09bg.mp4@0.0127:1.3500 | | | beat 1.3500 | | |  |
| m1 | cuts/10a.mp4@0.8627:1.1000 | | | beat 1.1000 | | |  |
| m2 | cuts/10v.mp4@0.0627:2.4333 | | | beat 2.4333 | | |  |
| t2 | cuts/11.mp4@2.3627:1.5667 | | | beat 1.5667 | | | hell |
| k1 | cuts/13.mp4@0.2960:1.7833 | | | beat 1.7833 | | | hell |
| k2 | cuts/14.mp4@0.1793:1.5333 | | | beat 1.5333 | | | hell |
| g1 | cuts/12.mp4@0.2127:3.1167 | | | beat 3.1167 | | |  |
| e1 | cuts/end_v3.mp4@0.3960:3.2000 | | | beat 3.2000 | | |  |

## script rough_v24_castcadia
size: 1920x1080
music: voice/alt_castcadia.flac
music_db: -3
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


## script rough_v24_mil3sperhour
size: 1920x1080
music: voice/alt_mil3sperhour.flac
music_db: -3
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


## script rough_v24_yet
size: 1920x1080
music: voice/alt_yet.flac
music_db: -3
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


## script rough_v43
# v43 (Ryan): v42 picture, new Pineberry Rush bed from the master + melody stem (tools/content/music/pineberry_bed.py): 3 bars of the melody hook (song 1.069-5.379), the loud drum bar (17.918), the drop on the title at 5.703, melody stem alone under the end card from 39.13, 2.5 s fade.

## script rough_v44
# v44 (Ryan on v43: "the ending is sick though, just time it to the final title drop not some random clip cut. take that same melody without the drums, and stick it at the begginng before the drop"): v42 picture; melody stem alone before the drop (song 55.404-61.107, 4 bars ending on a bar line), master from the drop at 5.703, melody stem alone from the final title card at 43.033.

## script rough_v45
# v45 (Ryan on v44: "you dropped the 4 drum beats, keep those at the beggining. also you ruined the end, becasue it doesnt phase out on a beat like it used to."): drop-section melody stem (song 56.773-61.083, ends on a bar line), the master's drum bar (17.893), the drop at 5.703 (aligned to v27-v42 to the sample), melody stem alone from the beat at the final title card (42.971).

## script rough_v46
# v46 (Ryan on v45: "when the melody plays a note, is when all but the melody should fall off"): v45 with the melody-alone tail from the melody note at song 56.290 (trailer 42.706, 0.33 s before the final title card).
# rough_v47_songstart (Ryan: "give me a version that starts at the beggining of the song, right when the melody fades out, right before the drums start to come in quietly"): the master from song 9.534 (a bar line, 0.9 s before the drums), 4.05 s of black before v42's picture so the drop stays on the title; same tail as v46. The black is a placeholder until the opening is re-cut.

## script rough_v48_songstart
# v48 (Ryan on v47: "start half a second earlier. and the end is still not correct. youre going to have to add some black ... to get the end to hit at the right time"): the master from song 9.034 (4.55 s of black before v42's picture); all but the melody falls off on bar 28 after the drop (song 58.296), a 4-bar phrase line; 1.68 s of black inserted before the end card so the card lands on it.

## script rough_v49_songstart
# v49 (Ryan: "split the difference on the start. .25 seconds, and then, have it fade in"): v48 with the master from song 9.284 (4.30 s of black), 1 s fade-in.

## script rough_v50_songstart
# v50: Pineberry Rush is 174 BPM (measured from the drum stem; the 0.3483 s beat used since v28 was wrong and drifted ~0.39 s by the end). Bar lines at n*1.37931 s from the file start, the drop on bar 14. v49's start (song 9.284, 1 s fade-in); all but the melody falls off on song bar 42 (57.931 s), the end card moved onto it with 1.314 s of black.

## script rough_v52_cutA
# Ryan: "can you go ahead and make this?" (pod: "trailer optional cut A: 16 before, 96 after"), "cut to melody then fade out. do the drums intro for this."; ending "a gameplay capture of a bot going through the portal, and shoving the gaurd, and that gaurd going flying".
# Picture (2648 frames, 44.13 s): v42 master 10-1987 (title on 331); 12s (main b4c50f98 FP shove, --movie, cuts\12s.mp4 0-338: portal, shove, the game's throw cinematic) 1978-2316; v42 end card 2582-2742, its frame 2742 held 144, its fade 2743-2768 (2317-2647). Lava cracks and the old ending cut.
# Music (tools/content/music/pineberry_cutA.py, voice\pineberry_cutA.flac): intro wav's first 16 beats, the mix from bar 14 for 96 beats (drop 5.517 s), melody stem from bar 38 fading to silence at the last frame; 10 ms crossfades; -0.5 dB (v42's level). Graph: final\master\rough_v52_cutA.graph.txt.

# v69 begin (marble v7 sections, task #657; stage trailer_marble_sections, same lenses and beats as the shots they replace)

## 5hb
said: v69 marble scope in 5hr's slot (996-1063): the scope eases onto Section B's wall-top activator and the round hits it on beat 33
capture: --map=marble --shot=pack_lead --stage=trailer_marble_sections --bots=3 --pov=guard --hud=crosshair --rifle=projectile --set=beat=bscope --seed=20261001
seconds: 3.15
in: 1.8666
freeze: waive
expect: hit PlateHitbox 2.92-2.99

## 23b
said: v69 marble runner POV in 23's slot (1324-1448): walking Section B, the rifle hits two activators ahead and the floor drops under the two runners there, on beats 50 and 53
capture: --map=marble --shot=pack_lead --stage=trailer_marble_sections --bots=3 --pov=runner --rifle=projectile --set=beat=bfar --seed=20261001
seconds: 3.5
in: 0.9
freeze: waive
expect: hit PlateHitbox 2.27-2.34; out Runner_3 3.85-4.05

## 10aa
said: v69 marble runner in 10ar's slot (1717-1851): the POV shoves Section A's activator on the beat (1802) and the runner ahead on the trapdoor drops
capture: --map=marble --shot=pack_lead --stage=trailer_marble_sections --bots=3 --pov=runner --rifle=projectile --set=beat=ashove --seed=20261001
seconds: 4.0
in: 0.75
freeze: waive
expect: out Runner_2 2.9-3.2

## 10ba
said: v69 marble scope in 10br's slot (1852-2009): the scope picks a runner coming out of Section A's cover into the open gap and hits him on 1986
capture: --map=marble --shot=pack_lead --stage=trailer_marble_sections --bots=3 --pov=guard --hud=crosshair --rifle=projectile --set=beat=ascope --seed=20261001
seconds: 4.4
in: 1.75
freeze: waive
expect: hit Runner_1 4.95-5.01

## 12sv
said: v69: 12sr refilmed as it is on marble v7 (the portal approach carries no section; the lip wall it passes moved to 309.6)
capture: --map=marble --shot=portal --stage=trailer_finale_marble --bots=2 --pov=runner --rifle=projectile --set=wait=0.25;from=311,52.4 --seed=20261001
tape: finale_fp
seconds: 5.55
in: 1.1666
freeze: waive
expect: stage arrived 3.57-3.63; stage kill 4.45-4.51

# v69 end

# v70 begin (task #657): the v68 marble shots unchanged, refilmed on marble v7 (531f0975)

## 5hv
said: v70 = 5hr as it is, on marble v7: v60 refilm of 5h: the marble scope shot, Movie Maker so the round's flight does not stall (v59 913-995; Ryan note 1)
capture: --map=marble --shot=pack_lead --stage=trailer_marble_track --bots=3 --pov=guard --hud=crosshair --rifle=projectile --set=fire=2.6 --seed=20261001
tape: marble_hit
seconds: 3.15
in: 1.8666
freeze: waive
expect: hit Runner_1 2.94-3.00

## 23v
said: v70 = 23 as it is, on marble v7: Ryan "ok, lets do a marble shot. from a runners pov, watching the sniper tower, snipe at two runners, much further ahead them themselves." In the beach run's slot (v65 1324-1448); hits on beats 50 (1365) and 53 (1428)
capture: --map=marble --shot=pack_lead --stage=trailer_marble_far --bots=3 --pov=runner --rifle=projectile --seed=20261001
seconds: 3.5
in: 0.9
freeze: waive
expect: hit Runner_2 2.29-2.35; hit Runner_3 3.34-3.40

## 10av
said: v70 = 10ar as it is, on marble v7: v60 refilm of 10a: the marble runner (v59 1717-1851)
capture: --map=marble --shot=pack_lead --stage=trailer_marble_column --bots=2 --pov=runner --rifle=projectile --set=late=1;lead=1.0;now=1;back_fire=0.1;kick=0.1;back_pace=0.5;follow=0.4;run_after=0.9;settle_omega=45;max_rate=55 --seed=20261001
tape: marble_column
seconds: 4.0
in: 0.75
freeze: waive
expect: shove Runner_2 2.97-3.03

## 10bv
said: v70 = 10br as it is, on marble v7: v60 refilm of 10b: the scope as the victim is hit (v59 1852-2009)
capture: --map=marble --shot=pack_lead --stage=trailer_marble_column --bots=2 --pov=guard --hud=crosshair --rifle=projectile --set=late=1;lead=1.0;now=1;back_fire=0.1;kick=0.1;back_pace=0.5;follow=0.4;run_after=0.9;settle_omega=45;max_rate=55 --seed=20261001
tape: marble_column
seconds: 4.4
in: 1.75
freeze: waive
expect: shove Runner_2 2.97-3.03; hit Runner_1 4.94-5.00

# v70 end

# v71 begin (task #657): the v70 marble shots bearing only, turned onto marble v7's sections. 23v stays at 126.5: its first victim's lane (r 48.6-48.8)
# only clears the inner edge where it is plain deck (131.6-182.4, 315-354); every section pier and column stands in that lane and A/B's walls hide him
# from the window. 12sv as v70 (the portal approach carries no section).

## 5hw
said: v71 (Ryan 08:25: "GO GET THE EXACT SAME SHOTS ONLY IN THE NEW ENVIROMENT THIS IS WHY WE HAVE FUCKING SCRIPTS FOR EVERYTHING SO THAT WE CAN MAKE CHANGES AND GET THE SAME FUCKING SHOTS"): 5hv bearing only, turn 24 -> 85.35 onto Section C's buttresses (window 150 -> 211.35, the hit 152.4 -> 213.7 between piers 208.1 and 219.4; the stage columns a pier takes are not spawned)
capture: --map=marble --shot=pack_lead --stage=trailer_marble_track --bots=3 --pov=guard --hud=crosshair --rifle=projectile --set=fire=2.6;turn=85.35 --seed=20261001
tape: marble_hit_c
seconds: 3.15
in: 1.8666
freeze: waive
expect: hit Runner_1 2.94-3.00

## 10aw
said: v71 (Ryan 08:25: "GO GET THE EXACT SAME SHOTS ONLY IN THE NEW ENVIROMENT ... GET THE SAME FUCKING SHOTS"): 10av bearing only, turn -62.3 onto ArcWall126's end 131.6 (for ArcWall188's 193.9; window 193.5 -> 131.2, the hit 200.6 -> 137.3), the open stretch with ArcWall188 and Section C's buttresses ahead in the runner's eyes. Head on the first v71: Section A's Wall1 (turn -120.6) put its activator plate on the victim in the scope; no other wall end on marble v7 has 13 deg of open, seen deck after it (A: plates; B: no ends; C piers: the next pier or ArcWall253; ArcWall306: the tower's own pier blocks the hit).
capture: --map=marble --shot=pack_lead --stage=trailer_marble_column --bots=2 --pov=runner --rifle=projectile --set=late=1;lead=1.0;now=1;back_fire=0.1;kick=0.1;back_pace=0.5;follow=0.4;run_after=0.9;settle_omega=45;max_rate=55;turn=-62.3 --seed=20261001
tape: marble_column_a
seconds: 4.0
in: 0.75
freeze: waive
expect: shove Runner_2 2.97-3.03

## 10bw
said: v71 (Ryan 08:25: "GO GET THE EXACT SAME SHOTS ONLY IN THE NEW ENVIROMENT ... GET THE SAME FUCKING SHOTS"): 10bv bearing only, the same turn -62.3 as 10aw (ArcWall126; the scope rests on its end 131.6, no prop near him)
capture: --map=marble --shot=pack_lead --stage=trailer_marble_column --bots=2 --pov=guard --hud=crosshair --rifle=projectile --set=late=1;lead=1.0;now=1;back_fire=0.1;kick=0.1;back_pace=0.5;follow=0.4;run_after=0.9;settle_omega=45;max_rate=55;turn=-62.3 --seed=20261001
tape: marble_column_a
seconds: 4.4
in: 1.75
freeze: waive
expect: shove Runner_2 2.97-3.03; hit Runner_1 4.94-5.00

# v71 end
# v71 alt23 (task #657): an alternate of 23 alone, the sniper on a lever instead of the runners (stage trailer_marble_far_lever)

## 23alt
said: Ryan 2026-10-20: "will you also please, make an alternate version of just this clip, where instead of shooting at the runners, the sniper shoots one of the levers and drops a runner into a pit?" 23v's POV as it is (eyes on the window, running, two ahead) on Section B: the round hits Trapdoor4's wall-top plate (293.5) on beat 50 (1365), the man crossing that door is on the spikes by 1398, the hole stands open to the slot's end (1448). Probe: POV 265 -> 289 at r 55 (past ArcWall253, ends 258.5), victim 281 -> 295.5 at r 53.5 (15 deg, 14 m ahead at the drop), far man 296 -> 317 at r 54 (off Trapdoor4 by 1.95 s); window 291 in the colonnade's 273.7-293.8 opening; first take at POV 255 (victim 24 deg off) read too small; the plate sits near the frame centre, the victim left, the window right.
capture: --map=marble --shot=pack_lead --stage=trailer_marble_far_lever --bots=3 --pov=runner --rifle=projectile --seed=20261001
seconds: 3.5
in: 0.9
freeze: waive
expect: hit PlateHitbox 2.30-2.34; stage dropped 2.76-2.92; out Runner_2 2.80-2.96

