# stages
kind: library

Smoked reference entries for stages with no approved project yet; sv3.catalogue reads them.

## 1
said: short 10 L1, guard POV in hell: the hand at the 62 deg window puts a round 1.4 m behind the lead (2.0 s) and the middle man (3.4 s), then drops the lead in the open past the 066 lip rock (hit 5.86 s, 82.3 deg); the picture ends before the shove. Mac smoke: shove 9.98, the shoved man hit in the air 10.40.
capture: --shot=s3_open_lane --stage=hell_explainer --pov=guard --bots=3 --shimmer=0 --look=social --rifle=projectile --seed=20261017
tape: stages_hell_explainer
hud: crosshair
expect: hit Runner_1 5.75-5.95; in_frame Runner_1 +0.0-0.05; out Runner_1 +0.0-0.3; lens_clear; lens_cover <= 0.5
seconds: 8.4
in: 1.2

## 2
said: short 10 L2+L3, the SAME tape from the back runner: the rounds land by the pack, the lead drops; the middle man jogs into the 066 rock's shadow and stops crouched at 68.6 deg (9.37 s); the POV runs the lane without a stop (42.5 deg at 7.2 s, 53.4 at 8.5, 62.4 at 9.5) and shoves him from 1.8 m in stride (9.98 s), the hand drops him in the air before he lands (hit 10.40, 73.6 deg), ragdolls; the POV watches 1.1 s and runs on up S2. The POV lives.
capture: --shot=s3_open_lane --stage=hell_explainer --pov=runner --bots=3 --shimmer=0 --look=social --rifle=projectile --seed=20261017
tape: stages_hell_explainer
expect: hit Runner_1 5.75-5.95; out Runner_1 +0.0-0.3; shove Runner_2 9.9-10.1; in_frame Runner_2 10.35-10.5; out Runner_2 10.35-10.5; alive Runner_3; lens_clear; lens_cover <= 0.5
seconds: 12.2
motion: 0.011
in: 1.2

## 3
said: Ryan (short 10, L4): "the first one to make it throws him out, and now, they're the sniper." {different shot, get up to the portal, go through, shove him, they go flying}. Hell, 4 players, no powers, no hub: runner POV runs 5.0 m into the portal at 345 deg, arrives in the tower, walks up behind the guard scoped at his window and shoves; the game's kill beat throws him (2.0 s) and the POV takes the tower. Mac smoke: arrive 2.04, shove 6.93, tower_out 8.93.
capture: --shot=s3_open_lane --stage=finale --pov=runner --bots=3 --shimmer=0 --seed=20261012
expect: shove Runner_0 6.8-7.1; arrive Runner_1 1.9-2.2; tower_out Runner_0 +1.9-2.1; alive Runner_1; lens_clear; lens_cover <= 0.5
seconds: 9.8
in: 1.2

## 4
said: Ryan (short 10, L4): "the first one to make it throws him out, and now, they're the sniper." {different shot, get up to the portal, go through, shove him, they go flying}. The ## 3 finale cut for a 3.5 s voice line: the runner POV runs 6.0 m into the portal at 345 deg (picture opens 1.2 s before the arrival), walks up behind the guard scoped at his window at pace 1.0 and shoves 0.89 s after arriving; the kill beat throws him and the POV takes the tower. Mac smoke: arrive 2.12, shove 3.01, tower_out 5.00.
capture: --shot=s3_open_lane --stage=finale --pov=runner --bots=3 --shimmer=0 --seed=20261012 --set=lead=6.0;stand=3.0;pace=1.0
expect: shove Runner_0 2.85-3.15; arrive Runner_1 2.0-2.25; tower_out Runner_0 +1.9-2.1; alive Runner_1; lens_clear; lens_cover <= 0.5
seconds: 4.9
in: 0.9

## 5
said: Ryan (short 11): "Just, how it started, vs how its going, pills, cut to forest, get both sniper and runners perspective for both". How it started, the sniper: the c4943a47 pill greybox (orange pills, grey ring boxes), the tower player on the centre platform scoped (fov 28), the hand drops the r 44.5 pill (2.07 s) and the r 38.5 pill (4.63 s) and swings onto the spared r 51.0 pill, tracking him. Guard and three pills, no powers. Mac smoke at the ref: go 1.00, hits 2.07 and 4.63, both in frame.
capture: --stage=pill_era --shot=guard_scope --pov=guard --fov=28 --cross=44 --seed=20261017
ref: how-started-era-c4943a47
hud: crosshair
expect: hit Runner_r44_5 1.95-2.2; in_frame Runner_r44_5 +0.0-0.05; hit Runner_r38_5 +2.45-2.7; in_frame Runner_r38_5 +2.45-2.7; go Runner_r51_0 0.9-1.1
seconds: 4.9
in: 0.6
motion: 0.012

## 6
said: Ryan (short 11): "Just, how it started, vs how its going, pills, cut to forest, get both sniper and runners perspective for both". How it started, the runner: the SAME pill match from the spared r 51.0 pill's eyes (fov 70, his own pill hidden): he sets off 1.0 s behind the other two, runs his lane, his head eases onto the nearest mate; both drop ahead of him in frame (2.07 at 9 deg right, 4.63 at 16 deg right). Mac smoke at the ref: go 1.00, hits 2.07 and 4.63, both in frame.
capture: --stage=pill_era --shot=guard_scope --pov=runner --fov=70 --seed=20261017
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
