# how_it_started
kind: short

## 1
said: how it started, pills: sniper perspective
capture: --stage=pill_era --shot=guard_scope --pov=guard --bots=3 --fov=28 --cross=44 --seed=20261017
hud: crosshair
expect: hit Runner_r44_5 1.95-2.2; in_frame Runner_r44_5 +0.0-0.05; hit Runner_r38_5 +2.45-2.7; in_frame Runner_r38_5 +2.45-2.7; go Runner_r51_0 0.9-1.1
seconds: 4.9
in: 0.6
motion: 0.012
ref: how-started-era-c4943a47
refilm: v1

## 2
said: how it started, pills: runners perspective
capture: --stage=pill_era --shot=guard_scope --pov=runner --bots=3 --fov=70 --seed=20261017
expect: hit Runner_r44_5 1.95-2.2; in_frame Runner_r44_5 +0.0-0.05; hit Runner_r38_5 +2.45-2.7; in_frame Runner_r38_5 +2.45-2.7; go Runner_r51_0 0.9-1.1
seconds: 4.5
in: 1
ref: how-started-era-c4943a47
refilm: v1

## 3
said: vs how its going, cut to forest: sniper perspective
capture: --shot=s3_open_lane --stage=forest_going --map=forest --pov=guard --bots=3 --shimmer=0 --look=social --seed=20261017
tape: how_it_started_v1_m3
hud: crosshair
expect: hit Runner_1 2.2-2.4; in_frame Runner_1 +0.0-0.05; hit Runner_2 +1.3-1.5; in_frame Runner_2 +1.3-1.5; alive Runner_3; lens_clear; lens_cover <= 0.5
seconds: 4
in: 1.2
motion: 0.012
refilm: v1

## 4
said: how its going, forest: runners perspective
capture: --shot=s3_open_lane --stage=forest_going --map=forest --pov=runner --bots=3 --shimmer=0 --look=social --seed=20261017
tape: how_it_started_v1_m3
expect: hit Runner_1 2.2-2.4; in_frame Runner_1 +0.0-0.05; hit Runner_2 +1.3-1.5; in_frame Runner_2 +1.3-1.5; alive Runner_3; lens_clear; lens_cover <= 0.5
seconds: 3.7
in: 1
refilm: v1

## script v1
captions: none
game: 1.0
pad: 0.2
| line | clip | in | len | fit | speed | text | card |
| M1 | cuts/01_v1.mp4 | 0 | | beat 4.9 | | | |
| M2 | cuts/02_v1.mp4 | 0 | | beat 4.5 | | | |
| M3 | cuts/03_v1.mp4 | 0 | | beat 4 | | | |
| M4 | cuts/04_v1.mp4 | 0 | | beat 3.7 | | | |
| end | title | | 1 | | | beta signup in bio | |
