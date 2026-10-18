# start_minigame
kind: short

## 1
said: pov of a runner in the tower shoving the sniper and the cinematic shot that plays after, in hell
capture: --shot=s3_open_lane --stage=finale --pov=runner --bots=3 --shimmer=0 --seed=20261012 --set=lead=6.0;stand=3.0;pace=0.32;beat=2.0
expect: shove Runner_0 3.48-3.78; arrive Runner_1 2.0-2.25; tower_out Runner_0 +1.9-2.1; alive Runner_1; lens_clear; lens_cover <= 0.5
seconds: 6.5
in: 0.9
refilm: v1

## 2
said: runner pov, looking over at the tower while hes shooting, then look forward and start doing the lava parkour section
capture: --shot=s3_open_lane --stage=parkour_sniped --pov=runner --bots=3 --shimmer=0 --look=social --rifle=projectile --seed=20261017 --set=look_to=4.4;misses=1.9,3.0,7.4;drop_at=8.6;hold_to=11.6
tape: start_minigame_v1
expect: hop1 Runner_1 4.5-4.7; hop2 Runner_1 +0.7-0.9; alive Runner_1; lens_clear; lens_cover <= 0.5
seconds: 6.4
in: 1
refilm: v1

## 3
said: pov of the sniper sniping at the runner from the previous shot
capture: --shot=s3_open_lane --stage=parkour_sniped --pov=guard --bots=3 --shimmer=0 --look=social --rifle=projectile --seed=20261017 --set=look_to=4.4;misses=1.9,3.0,7.4;drop_at=8.6;hold_to=11.6
tape: start_minigame_v1
hud: crosshair
expect: hit Runner_1 8.9-9.1; in_frame Runner_1 +0.0-0.05; lens_clear; lens_cover <= 0.5
seconds: 4.6
in: 5.4
motion: 0.012
refilm: v1,v2

## 4
said: pov of race in forest
capture: --shot=s3_open_lane --stage=forest_race --map=forest --pov=runner --bots=3 --shimmer=0 --look=social --seed=20261017
expect: race_start 0-0.5; lens_clear; lens_cover <= 0.5
seconds: 19.5
in: 1
refilm: v1

## 5
said: bust shot of runner in hell idle animating
capture: --shot=s1_cave --stage=hell_idle_bust --bots=1 --look=social --shimmer=0 --seed=20261017
expect: idle Runner_1 0.6-0.9; alive Runner_1; lens_clear; lens_cover <= 0.5
seconds: 3
in: 1.2
motion: 0.005
refilm: v1,v2

## 6
said: Shot of starting shove tower minigame in hell
capture: --shot=s3_open_lane --stage=tower_brawl --bots=3 --shimmer=0 --look=social --seed=20261017
tape: start_minigame_v2_brawl
expect: brawl_start 0.0-0.1; brawl_out Runner_1 2.6-2.9; brawl_out Runner_0 6.2-6.5; brawl_out Runner_3 7.1-7.4; brawl_won Runner_2 7.1-7.4; lens_clear; lens_cover <= 0.5
seconds: 15.5
in: 0.4
refilm: v1,v2

## script v1
pad: 0.2
| line | clip | in | len | fit | speed | text | card |
| L1 | cuts/01_v1.mp4 | 1.5 | 3.4 | wait | | Heres how i fixed the worst part about my game | |
| L2 | cuts/02_v1.mp4 | 0 | 6.4 | line | | In my game, youre either the sniper in the gaurd tower, or youre running an obsticle course to become the sniper. | |
| L3 | cuts/03_v1.mp4 | 0.214 | 4.386 | line | | but this has a problem, whos the sniper first? i wanted it to be earned | |
| L4 | cuts/04_v1.mp4 | 0 | 19.5 | line | | so, i implemented a race, every player does the course with no sniper, and the first one to complete it gets to be the sniper. this, was the worst part of my game. it wasnt fun, everyone was the same speed, and it took to long | |
| L5 | cuts/05_v1.mp4 | 0 | 3 | line | | so how did i fix it? | |
| L6 | cuts/06_v1.mp4 | 0 | 20 | line | | instead of everyone running to the tower, everyone starts in the tower, and the way you get to be the sniper, is to be the last one standing in it. so now, instead of a long drawn out boring race, its a fast, chaotic, brawl to see who goes first | |
| end | title | | 1.75 | | | beta signup in bio | |

## script v2
from: v1
notes: Agent frame check of v1 (task #601, not Ryan's notes; v1 was not shown to him): L1 the kill-beat camera loses the guard for the last 0.8 s; L3 the scope holds 2 s on empty lava after the drop; L5 the bust cuts off the top of his head; L6 the PC brawl ran untaped and diverged from the smoke (an empty room before the seat).
pad: 0.2
| line | clip | in | len | fit | speed | text | card |
| L1 | cuts/01_v1.mp4 | 1.3 | 2.7 | wait | | Heres how i fixed the worst part about my game | |
| L2 | cuts/02_v1.mp4 | 0 | 6.4 | line | | In my game, youre either the sniper in the gaurd tower, or youre running an obsticle course to become the sniper. | |
| L3 | cuts/03_v2.mp4 | 0.2 | 4.4 | line | | but this has a problem, whos the sniper first? i wanted it to be earned | |
| L4 | cuts/04_v1.mp4 | 0 | 19.5 | line | | so, i implemented a race, every player does the course with no sniper, and the first one to complete it gets to be the sniper. this, was the worst part of my game. it wasnt fun, everyone was the same speed, and it took to long | |
| L5 | cuts/05_v2.mp4 | 0 | 3 | line | | so how did i fix it? | |
| L6 | cuts/06_v2.mp4 | 0 | 15.5 | line | | instead of everyone running to the tower, everyone starts in the tower, and the way you get to be the sniper, is to be the last one standing in it. so now, instead of a long drawn out boring race, its a fast, chaotic, brawl to see who goes first | |
| end | title | | 1.75 | | | beta signup in bio | |
