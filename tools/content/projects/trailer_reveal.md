# trailer_reveal
kind: trailer
aspect: 16:9
format: Steam reveal trailer, ROUGH CUT for structure (one take per shot, first usable take kept)
ryan: "Make a ROUGH CUT of PANOPTICON's reveal trailer so Ryan can get a read on the structure. Not final quality -- speed over polish."
rules: 16:9 1920x1080 (SIZE=1920x1080 shot.sh), no HUD except the guard's scope, under 45 s, no voice, no text but the title and end cards, SR20DET as the bed, game SFX off.
v2 notes (Ryan on rough_v1): the guard stands at the tower's window, not deep inside; all runners run the course direction; the runner shot is the SAME event as the guard shot (same stage, same seed, two POVs), cut back ~1 s to the man directly behind the victim; clear line of sight when he looks up at the tower; title drops in HARD on the music's drop; music https://www.youtube.com/watch?v=OBPV0lsorwU; real-looking gameplay only (walkable deck and real cover, nobody on lava, nobody looking backwards); max 4 players a shot (1 guard + 3); spread across hell, forest and marble. Added: "EVERY shot is first-person POV -- either the guard's scope/tower view or a prisoner's first-person view. No third-person ... Title/end cards are the only non-POV frames."
music: external\src\music_v2_OBPV0lsorwU.mp4 -> voice\sr20det.ogg (SOURCES.md). The drop: 0.35 s of silence from 5.36 s, the hit at 5.703 s (sample onset); 170 bpm after it (v3 measured).
cards: cuts/title_hard.mp4 is v1's title frame looped from frame 0 (v1's title.mp4 opened on two black frames); cuts/end.mp4 is v1's.
delivery: content\trailer_reveal\final\rough_v27.mp4 (and ~/Desktop/panopticon-renders/trailer_reveal/)
tag: rough_v27
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
capture: --shot=s3_open_lane --stage=trailer_open --pov=guard --hud=crosshair --bots=3 --rifle=projectile --set=fire_at=3.24 --seed=20261001
tape: open
seconds: 4.0
in: 0.9
freeze: waive
# hell S2 inner lane; guard at the 115 deg window; zoom at take 1.9; squeezed 3.25, lands 3.60 (victim Runner_2)

## 2
said: v4 "Hell, the same event from the runner behind: the man ahead drops, he looks up at the tower (keep a2)"
capture: --shot=s3_open_lane --stage=trailer_open --pov=runner --bots=3 --rifle=projectile --set=fire_at=3.24;eye_at=4.05;eye_swing=0.4;eye_from=60:49 --seed=20261001
tape: open
seconds: 5.0
in: 0.9
freeze: waive
# the open tape down Runner_3's eyes, 2.5 m behind the victim; hit at take 3.60, the look up from 3.92
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
capture: --shot=cover_side --stage=trailer_duel2 --bots=1 --pov=runner --rifle=projectile --seed=20261001
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
# v26 (note 4, the same read on the marble shove): the shover's square-up was a 45 deg flick in six frames 0.28 s before the shove. His head comes round
# onto him over the half second before it, eased (stage_driver "smooth"); shove 3.00, squeeze 3.10, hit 3.45 as before.

## 11
said: v4 "Hell, lake platforming (t2)"
capture: --shot=lava_parkour --stage=lavaparkour --bots=3 --set=line=3 --pov=runner --seed=20261001
tape: lake
seconds: 5.5
in: 1.2
freeze: waive
# hell S5 lake: three hopping the platforms, bodies only on the platforms and banks
# v19 (Ryan): "the lava parkour scene doesnt relaly look human." The POV's eyes are his own: on the landing, then round onto the next platform before he is down, one turn a hop; every landing off-centre, so the run-ups differ (leaps at take 1.83, 2.63, 3.57, 4.25, 5.20, 6.03); a check on the second top, a stumble on the fourth (4.98); the two ahead land off-centre too
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
seconds: 1.8
in: 2.96
freeze: waive
# rough_v20_green: shot 9b in the green forest (forest_green.tscn, same geometry), same stage and tape

## 1v
said: v25 "first thing to do for it, extend the first shot a little further so we can start the song like on second earlier."
capture: --shot=s3_open_lane --stage=trailer_open --pov=guard --hud=crosshair --bots=3 --rifle=projectile --set=fire_at=3.24 --seed=20261001
tape: open
seconds: 4.8
in: 0.75
freeze: waive
# rough_v25_vivaldi: shot 1 on a longer window (take 0.75-5.55), same stage and tape; cuts/01.mp4 stays v24's

## 5h
said: v25 "then, in the marble runnign shot, have someone get hit, again, on the beat."
capture: --map=marble --shot=pack_lead --stage=trailer_marble_track --bots=3 --pov=guard --hud=crosshair --rifle=projectile --set=fire=2.6 --seed=20261001
tape: marble_hit
seconds: 3.0
in: 1.8
freeze: waive
# rough_v25_vivaldi: 5b restaged with a real rifle hit. The hand rides the man behind (Runner_2) from the start; squeeze 2.62 as he
# nears the 126 column, the round meets him in the gap at 128.0 deg (hit 2.97), the shipped ghost rule (he goes limp). 5b keeps its tape.
# v26 (Ryan): "for like the marble shot, where its only the snipers pov, it should be the player in the front." The hand rides the LEAD (Runner_1) from the start:
# squeeze 2.62, hit 2.97 in the gap at 128.4 deg; the two behind flinch, look up at the tower a beat apart and run past. Paths as 5b (note 2).

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
capture: --shot=cover_side --stage=trailer_duel2 --bots=1 --pov=guard --hud=crosshair --rifle=projectile --set=kick=0.3 --seed=20261001
tape: duel_dodge
seconds: 2.4
in: 3.0
freeze: waive
# rough_v25_vivaldi: 7 with the scope held down through the shot (the hand's kick 0.3, as the marble scope): he stands in the open under
# the crosshair, bolts for the rock, the round lands on the ground he left. The runner and every time are the duel tape's; 7 keeps its tape.

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

