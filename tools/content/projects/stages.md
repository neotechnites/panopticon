# stages
kind: library

Smoked reference entries for stages with no approved project yet; sv3.catalogue reads them.

## 1
said: short 10 L1+L2, guard POV in hell (Ryan on v6: "the first shot, should go til "shove" and it should start with a little bit of tracking zoomed out"): the hand at the 62 deg window puts scoped rounds 1.4 m behind the lead (2.0 s) and the middle man (3.4 s), lowers the scope at 4.0 and rides the middle man unscoped to 5.2 (on v7: the unscoped hand on the lead stared at the 066 rock he was behind); the scope comes up at 5.3 and drops the lead (start 31) in the open past the 066 lip rock (hit 6.27, 83.2 deg) and holds on him where he falls; the picture opens 4.7 (unscoped) and ends 10.1, before the shove. Mac smoke: shove 10.25, the shoved man hit in the air 10.67.
capture: --shot=s3_open_lane --stage=hell_explainer --pov=guard --bots=3 --shimmer=0 --look=social --rifle=projectile --seed=20261017 --set=start=31,22,4.8;drop_at=5.9;lower=4.0,5.3;track_to=5.2
tape: stages_hell_explainer
hud: crosshair
expect: hit Runner_1 6.17-6.37; in_frame Runner_1 +0.0-0.05; out Runner_1 +0.0-0.3; lens_clear; lens_cover <= 0.5
seconds: 5.4
in: 4.7

## 2
said: short 10 L3, the SAME tape from the back runner (the cut lands on "Shove"): the rounds land by the pack, the lead drops (6.27); the middle man jogs into the 066 rock's shadow and stops crouched at 68.6 deg (9.37 s); the POV runs the lane without a stop (42.5 deg at 7.2 s, 53.4 at 8.5, 62.4 at 9.5) eases in from 4 m (pace 0.4), eyes 14 deg down on his back, and shoves him from 1.6 m without stopping (10.25 s; the POV's own arms push out, hold and draw back, the game's first-person shove, [pov] arms 10.28-10.47, his back fills the lower frame, lens near 1.19 m, cover 0.28), the hand drops him in the air before he lands (hit 10.67, 73.6 deg), ragdolls; the POV watches him 1.1 s and runs on up S2. The POV lives.
capture: --shot=s3_open_lane --stage=hell_explainer --pov=runner --bots=3 --shimmer=0 --look=social --rifle=projectile --seed=20261017 --set=start=31,22,4.8;drop_at=5.9;lower=4.0,5.3;track_to=5.2
tape: stages_hell_explainer
expect: hit Runner_1 6.17-6.37; out Runner_1 +0.0-0.3; shove Runner_2 10.15-10.35; in_frame Runner_2 10.6-10.75; out Runner_2 10.6-10.75; alive Runner_3; lens_clear; lens_cover <= 0.5
seconds: 12.2
motion: 0.011
in: 1.2

## 4
said: Ryan (short 10, L4): "the first one to make it throws him out, and now, they're the sniper." {different shot, get up to the portal, go through, shove him, they go flying}; on v6: "get rid of the portal, make the ragdoll shot longer". The cut opens inside the tower just after the runner POV arrives through the portal (2.13; no run-up on screen), walks up behind the guard scoped at his window at pace 0.32 and shoves 1.5 s after arriving, on "throw"; the kill beat throws him for 1.3 s (beat=1.3, the original camera), and the picture runs on the POV in the tower as the sniper. Mac smoke: arrive 2.13, shove 3.63, tower_out 4.92.
capture: --shot=s3_open_lane --stage=finale --pov=runner --bots=3 --shimmer=0 --seed=20261012 --set=lead=6.0;stand=3.0;pace=0.32;beat=1.3
expect: shove Runner_0 3.48-3.78; arrive Runner_1 2.0-2.25; tower_out Runner_0 +1.2-1.4; alive Runner_1; lens_clear; lens_cover <= 0.5
seconds: 4.2
in: 2.15

## 5
said: Ryan (short 11): "Just, how it started, vs how its going, pills, cut to forest, get both sniper and runners perspective for both". How it started, the sniper: the c4943a47 pill greybox (orange pills, grey ring boxes), the tower player on the centre platform scoped (fov 28), the hand drops the r 44.5 pill (2.07 s) and the r 38.5 pill (4.63 s) and swings onto the spared r 51.0 pill, tracking him. Guard and three pills, no powers. Mac smoke at the ref: go 1.00, hits 2.07 and 4.63, both in frame.
capture: --stage=pill_era --shot=guard_scope --pov=guard --bots=3 --fov=28 --cross=44 --seed=20261017
ref: how-started-era-c4943a47
hud: crosshair
expect: hit Runner_r44_5 1.95-2.2; in_frame Runner_r44_5 +0.0-0.05; hit Runner_r38_5 +2.45-2.7; in_frame Runner_r38_5 +2.45-2.7; go Runner_r51_0 0.9-1.1
seconds: 4.9
in: 0.6
motion: 0.012

## 6
said: Ryan (short 11): "Just, how it started, vs how its going, pills, cut to forest, get both sniper and runners perspective for both". How it started, the runner: the SAME pill match from the spared r 51.0 pill's eyes (fov 70, his own pill hidden): he sets off 1.0 s behind the other two, runs his lane, his head eases onto the nearest mate; both drop ahead of him in frame (2.07 at 9 deg right, 4.63 at 16 deg right). Mac smoke at the ref: go 1.00, hits 2.07 and 4.63, both in frame.
capture: --stage=pill_era --shot=guard_scope --pov=runner --bots=3 --fov=70 --seed=20261017
ref: how-started-era-c4943a47
expect: hit Runner_r44_5 1.95-2.2; in_frame Runner_r44_5 +0.0-0.05; hit Runner_r38_5 +2.45-2.7; in_frame Runner_r38_5 +2.45-2.7; go Runner_r51_0 0.9-1.1
seconds: 4.5
in: 1.0

## 7
said: Ryan (short 11): "Just, how it started, vs how its going, pills, cut to forest, get both sniper and runners perspective for both". How its going, the sniper: the forest, guard at the 32 deg window scoped (fov 24), three runners on the lane from 29-37 deg; the hand drops the lead in the open (2.30 s, 49.8 deg) and the middle man (3.70 s, 56.4 deg), then tracks the back man running on. One tape with ## 8. Mac smoke: hits 2.30 and 3.70, both in frame; the back man lives.
capture: --shot=s3_open_lane --stage=forest_going --map=forest --pov=guard --bots=3 --shimmer=0 --look=social --seed=20261017
tape: stages_forest_going
hud: crosshair
expect: hit Runner_1 2.2-2.4; in_frame Runner_1 +0.0-0.05; hit Runner_2 +1.3-1.5; in_frame Runner_2 +1.3-1.5; alive Runner_3; lens_clear; lens_cover <= 0.5
seconds: 4.0
in: 1.2
motion: 0.012

## 8
said: Ryan (short 11): "Just, how it started, vs how its going, pills, cut to forest, get both sniper and runners perspective for both". How its going, the runner: the SAME tape from the back man: he runs the forest lane behind the other two, eyes up the lane; the lead drops ahead of him (2.30), a flinch, the middle man drops (3.70), he runs on past them; the cut ends 1.0 s after (before the 59 deg trunk covers the lens at 4.77). Mac smoke: hits 2.30 and 3.70 in frame; he lives.
capture: --shot=s3_open_lane --stage=forest_going --map=forest --pov=runner --bots=3 --shimmer=0 --look=social --seed=20261017
tape: stages_forest_going
expect: hit Runner_1 2.2-2.4; in_frame Runner_1 +0.0-0.05; hit Runner_2 +1.3-1.5; in_frame Runner_2 +1.3-1.5; alive Runner_3; lens_clear; lens_cover <= 0.5
seconds: 3.7
in: 1.0

## 9
said: short 4 L1, Ryan: "pov of the sniper shooting at some runners and missing, hell map, right at the end, they hit one, and we cut a little after the animation plays out": rs_snipe (ragdoll_short#40) on this build, the guard's scope on hell, 3 runners: a round misses (lands 2.25 s), a second misses (3.95), the third drops Runner_3 (5.65) and old=1 plays the pre-ragdoll Death clip on him; the picture runs on 1.9 s past the hit so the clip plays out. Mac smoke: misses 2.25 and 3.95, hit 5.65.
capture: --shot=s3_open_lane --stage=rs_snipe --pov=guard --bots=3 --seed=20261017 --shimmer=0 --set=old=1;plan=0m,1m,2h;start=1.0
hud: crosshair
expect: hit Runner_3 5.55-5.75; lens_clear; lens_cover <= 0.5
seconds: 5.0
in: 2.6
motion: 0.005

## 10
said: short 4 M2, Ryan: "shot of the animation in a grey space jsut playing, with a slow fade in of an image i will provide": death_void, one prisoner alone in a grey void (every mesh but his hidden, a grey background, a floor that only catches his shadow), ragdoll off, the lens 4.6 m off at fov 40, he faces 35 deg off it; at 1.6 s he plays the old (pre-ragdoll) Death clip once and lies there. Mac smoke: death 1.62.
capture: --shot=s3_open_lane --stage=death_void --bots=1 --seed=20261017 --shimmer=0
expect: death Runner_1 1.5-1.7; lens_clear
seconds: 3.6
in: 1.2
motion: 0.002

## 11
said: short 4 L3, Ryan: "slow zoom out shot of the old hell map": hell_pullback, a live 3-runner bot match on the hell ring (map 1); the lens opens close on the tower (deg 0, r 14, 6 m up, fov 45) and pulls straight back and up the shaft over 8 s to polish_aerial's high spot (deg 0, r 36, 34 m up, fov 70), the tower shrinking as the pit, deck and far gallery come into frame. Mac smoke: the move 1.00-9.00, the lens clear.
capture: --shot=pit_orbit --stage=hell_pullback --bots=3 --seed=20261017 --shimmer=0
expect: pullback start 0.9-1.1; pullback end 8.9-9.1; lens_clear; lens_cover <= 0.5
seconds: 8.2
in: 1.0

## 12
said: short 4 L4, Ryan: "a sniper pov, missing shots, then cut to the runner pov near the end, and he watches the person in front of him get shot": hell_explainer's take (stages#1) with the scope held throughout (no lower, no track_to): the hand puts scoped rounds behind the lead (fired 2.02, lands 2.43) and the middle man (3.42, lands 3.80), then drops the lead in the open (6.27, 83.2 deg, in frame). One tape with ## 13: the line plays this scope through the misses, then cuts to ## 13, the back runner's POV, near the end as the lead in front of him is shot. Mac smoke: misses 2.43 and 3.80, hit 6.27 in frame.
capture: --shot=s3_open_lane --stage=hell_explainer --pov=guard --bots=3 --shimmer=0 --look=social --rifle=projectile --seed=20261017 --set=start=31,22,4.8;drop_at=5.9
tape: stages_hell_explainer_scoped
hud: crosshair
expect: hit Runner_1 6.17-6.37; in_frame Runner_1 +0.0-0.05; lens_clear; lens_cover <= 0.5
seconds: 9.0
in: 1.0
motion: 0.012

## 13
said: short 4 L4, the runner half of ## 12: the SAME tape from the back runner: the rounds land by the pack (2.43, 3.80), he runs on behind the middle man and the lead, and the lead, in front of him, drops in his frame (6.27, in_frame from the runner's lens). Mac smoke: hit 6.27 in frame.
capture: --shot=s3_open_lane --stage=hell_explainer --pov=runner --bots=3 --shimmer=0 --look=social --rifle=projectile --seed=20261017 --set=start=31,22,4.8;drop_at=5.9
tape: stages_hell_explainer_scoped
expect: hit Runner_1 6.17-6.37; in_frame Runner_1 +0.0-0.05; lens_clear; lens_cover <= 0.5
seconds: 6.5
in: 1.0
motion: 0.011

## 14
said: short 4 L5, Ryan: "clip montage of the sniper hitting people dead ... and if we can, get one that freaks out and break the players model and go flying" / "didnt i say it has to be in the forest?": forest_going's guard scope (stages#7) with the lead's death ragdoll impulse at 1400 (fling; shipped 70), so the first kill throws him; the middle man drops after. Mac smoke: hits 2.30 and 3.70, both in frame; the back man lives.
capture: --shot=s3_open_lane --stage=forest_going --map=forest --pov=guard --bots=3 --shimmer=0 --look=social --seed=20261017 --set=fling=1400
hud: crosshair
expect: hit Runner_1 2.2-2.4; in_frame Runner_1 +0.0-0.05; hit Runner_2 +1.3-1.5; in_frame Runner_2 +1.3-1.5; alive Runner_3; lens_clear; lens_cover <= 0.5
seconds: 6.5
in: 1.2
motion: 0.012

## 15
said: short 4 L5, the forest sniper montage: forest_window (ragdoll_short#14) at the tight scope (fov 10), the guard at the 32 deg window drops Runner_1 on the open stretch (2.60 s, 51.1 deg) and Runner_3 (7.80 s, 65.0 deg), each filling a good part of the scope. Mac smoke: hits 2.60 and 7.80.
capture: --map=forest --shot=s3_open_lane --stage=forest_window --pov=guard --bots=3 --seed=20261012 --shimmer=0 --set=scope_fov=10
hud: crosshair
expect: hit Runner_1 2.5-2.7; hit Runner_3 +5.1-5.3; lens_clear; lens_cover <= 0.5
seconds: 9.0
in: 1.0
motion: 0.005

## 16
said: short 4 L6, Ryan: "a bunch of runners shoving each other with the ragdoll": the melee scrap at a short's cap, three runners (count=3; 4 players with the guard) on the clear deck at 195 deg r 52 all shoving each other (each shove flops the victim), the chase lens in the scrap; cut from 2.2 s, after a body passes through the lens at 1.9 s; the line then cuts to ## 17, a runner POV in a real round shoving a man into the pit. Mac smoke: 10 shoves 1.47-8.02 s, 6 of them 3.72-5.90.
capture: --shot=s3_melee --stage=melee --bots=3 --seed=20261017 --shimmer=0 --set=count=3
expect: shove Runner_2 1.4-1.55; shove Runner_3 +0.5-0.65; lens_clear; lens_cover <= 0.5
seconds: 5.9
in: 2.2

## 17
said: short 4 L6, Ryan: "other pov shots of a "real game" where the runners are getting shoved": rs_pitshove (ragdoll_short#22) untaped, the POV runner (Runner_2) runs down the man on the inside and shoves him over the rim into the pit (4.20 s, 49.2 deg r 48.8), stops at 57 deg and watches him fall (in the pit 6.28), the eye on the POV. Mac smoke: shove 4.20, out 6.28 (the taped numbers).
capture: --shot=s3_open_lane --stage=rs_pitshove --pov=runner --bots=3 --seed=7 --shimmer=0 --set=pack=3;shove_gap=1.3;turn_gap=2.6;shover_r=50.2;from=13;back=8.5;after_to=57
expect: shove Runner_2 4.1-4.3; out Runner_1 +2.0-2.2; lens_clear; lens_cover <= 0.5
seconds: 6.4
in: 1.0

## 18
said: short 4 L7, Ryan: "pov runner makes it through the portal, shoves, and the usual cinematic shot": finale (stages#4) from before the portal: the runner POV runs the last 6 m into the portal (lead=6.0) and arrives in the tower (2.13), walks up behind the scoped guard (pace 0.32) and shoves him (3.63), and the shipped 2.0 s kill beat (beat=2.0) throws him out on the original camera (tower_out 5.63). Mac smoke: arrive 2.13, shove 3.63, tower_out 5.63.
capture: --shot=s3_open_lane --stage=finale --pov=runner --bots=3 --shimmer=0 --seed=20261012 --set=lead=6.0;stand=3.0;pace=0.32;beat=2.0
expect: shove Runner_0 3.48-3.78; arrive Runner_1 2.0-2.25; tower_out Runner_0 +1.9-2.1; alive Runner_1; lens_clear; lens_cover <= 0.5
seconds: 6.5
in: 0.9

## 19
said: Ryan (short 9, L4): "so, i implemented a race, every player does the course with no sniper, and the first one to complete it gets to be the sniper. this, was the worst part of my game. it wasnt fun, everyone was the same speed, and it took to long" {pov of race in forest}. The game's own opening race (start_race) in the forest, four racers and nobody in the tower, the other three on their race brains (bot shoves off: the take fails a shoved POV): the POV (stage_driver steps on the line its own brain ran, human eyes) runs 2nd-3rd to ~9 s then 2-4 m behind two racers, the leader 10-14 deg up the course, all at the same pace; nobody finishes inside the cut (a lap is ~28.6 s). Mac smoke: race_start 0.02, no seat the whole race.
capture: --shot=s3_open_lane --stage=forest_race --map=forest --pov=runner --bots=3 --shimmer=0 --look=social --seed=20261017
tape: stages_forest_race
expect: race_start 0-0.5; lens_clear; lens_cover <= 0.5
seconds: 19.5
in: 1.0

## 20
said: Ryan (short 9, L5): "so how did i fix it?" {bust shot of runner in hell idle animating}. One prisoner stood on bare S1 deck (42 deg r 52), the whole head to mid chest at eye height from 2.5 m (fov 30, aim 0.1 m over the head bone), the S1 spires behind him, the rig's shipped Idle breathing, a handheld drift on the lens; nobody shoots. Mac smoke: idle 0.65, Idle playing at 0.00 m/s.
capture: --shot=s1_cave --stage=hell_idle_bust --bots=1 --look=social --shimmer=0 --seed=20261017
expect: idle Runner_1 0.6-0.9; alive Runner_1; lens_clear; lens_cover <= 0.5
seconds: 3.0
in: 1.2
motion: 0.005

## 21
said: Ryan (short 9, L2): "In my game, youre either the sniper in the gaurd tower, or youre running an obsticle course to become the sniper." {runner pov, looking over at the tower while hes shooting, then look forward and start doing the lava parkour section}. ONE take with ## 22: the runner on the S5 near bank (290.4 deg) looks over at the tower's 305 deg window (0.1 deg off it from 1.4 s) while the hand puts two rounds by him (1.92, 3.02; they land on the 286 lip beside him), turns forward at 4.4 and hops the S5 lava platforms (lands 4.60, 5.38, 6.27, 6.97); the cut ends 7.4, before the next squeeze. Two more players stand out of frame up the S1 lane. Mac smoke: as listed.
capture: --shot=s3_open_lane --stage=parkour_sniped --pov=runner --bots=3 --shimmer=0 --look=social --rifle=projectile --seed=20261017 --set=look_to=4.4;misses=1.9,3.0,7.4;drop_at=8.6;hold_to=11.6
tape: stages_parkour_sniped
expect: hop1 Runner_1 4.5-4.7; hop2 Runner_1 +0.7-0.9; alive Runner_1; lens_clear; lens_cover <= 0.5
seconds: 6.4
in: 1.0

## 22
said: Ryan (short 9, L3): "but this has a problem, whos the sniper first? i wanted it to be earned" {pov of the sniper sniping at the runner from the previous shot}. The SAME tape from the guard at the 305 deg window, scoped (fov 20), continuing where ## 21 leaves off: the hand rides the parkour runner hop to hop across the lava platforms, a round by him (squeeze 7.42, lands 7.77), then the drop as he leaves the 322 deg top (squeeze 8.60, hit 8.98, in frame), the hand holding on him to 11.6. Mac smoke: hit 8.98 in frame.
capture: --shot=s3_open_lane --stage=parkour_sniped --pov=guard --bots=3 --shimmer=0 --look=social --rifle=projectile --seed=20261017 --set=look_to=4.4;misses=1.9,3.0,7.4;drop_at=8.6;hold_to=11.6
tape: stages_parkour_sniped
hud: crosshair
expect: hit Runner_1 8.9-9.1; in_frame Runner_1 +0.0-0.05; lens_clear; lens_cover <= 0.5
seconds: 4.6
in: 7.0
motion: 0.012

## 23
said: Ryan (short 9, L6): "everyone starts in the tower, and the way you get to be the sniper, is to be the last one standing in it. so now, instead of a long drawn out boring race, its a fast, chaotic, brawl to see who goes first" {Shot of starting shove tower minigame in hell}. The game's own opening tower brawl (start_brawl): four players in the tower room, only the shove, the game's brawl bots shove each other out of the windows (outs 2.75, 6.37, 7.28); the last one standing (Runner_2) takes the seat (8.80) and the lens, hung under the ceiling against the 0 deg pier, stays on him and closes in (fov 72 to 40 over 2.5 s) as he takes the window as the sniper. Mac smoke: as listed.
capture: --shot=s3_open_lane --stage=tower_brawl --bots=3 --shimmer=0 --look=social --seed=20261017
tape: stages_tower_brawl
expect: brawl_start 0.0-0.1; brawl_out Runner_1 2.6-2.9; brawl_out Runner_0 6.2-6.5; brawl_out Runner_3 7.1-7.4; brawl_won Runner_2 7.1-7.4; lens_clear; lens_cover <= 0.5
seconds: 20.0
in: 0.4
