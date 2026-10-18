# stages
kind: library

Smoked reference entries for stages with no approved project yet; sv3.catalogue reads them.

## 1
said: short 10 L1, guard POV in hell: the hand at the 62 deg window puts a round 1.4 m behind the lead (2.0 s) and the middle man (3.4 s), then drops the lead in the open past the 066 lip rock (hit 5.86 s, 82.3 deg); the picture ends before the shove. Mac smoke: shove 10.00, the shoved man hit in the air 10.43.
capture: --shot=s3_open_lane --stage=hell_explainer --pov=guard --bots=3 --shimmer=0 --look=social --rifle=projectile --seed=20261017
tape: stages_hell_explainer
hud: crosshair
expect: hit Runner_1 5.75-5.95; in_frame Runner_1 +0.0-0.05; out Runner_1 +0.0-0.3; lens_clear; lens_cover <= 0.5
seconds: 8.4
in: 1.2

## 2
said: short 10 L2+L3, the SAME tape from the back runner: the rounds land by the pack, the lead drops; the middle man stops crouched in the 066 rock's shadow at 69.0 deg, the POV walks up and shoves him from 1.8 m (10.00 s), the hand drops him in the air before he lands (hit 10.43, 74.2 deg), ragdolls; the POV watches 1.1 s and runs on up S2. The POV lives.
capture: --shot=s3_open_lane --stage=hell_explainer --pov=runner --bots=3 --shimmer=0 --look=social --rifle=projectile --seed=20261017
tape: stages_hell_explainer
expect: hit Runner_1 5.75-5.95; out Runner_1 +0.0-0.3; shove Runner_2 9.9-10.1; in_frame Runner_2 10.35-10.5; out Runner_2 10.35-10.5; alive Runner_3; lens_clear; lens_cover <= 0.5

seconds: 13.0
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
seconds: 4.6
in: 0.9
