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

## 5
said: v2 of ## 3 (Ryan: "reshoot the second half with the fixes", "cut every shot by hald"): the forest sniper, the hand drops the lead (2.07 s), puts a round across the back man's eyes (2.95 s) and drops the man 2.5 m ahead of him (3.47 s); 2.0 s from 1.7.
capture: --shot=s3_open_lane --stage=forest_going --map=forest --pov=guard --bots=3 --shimmer=0 --look=social --seed=20261017 --set=pace=0.62;pov_start=24.5;pov_pace=0.8;reload=0.45;drop_lead=2.0;miss_pov=2.95;miss_by=1.3;drop_mid=3.4
tape: how_it_started_v2
hud: crosshair
expect: hit Runner_1 1.95-2.2; in_frame Runner_1 +0.0-0.05; hit ForestCollision +0.8-1.0; hit Runner_2 +1.3-1.5; in_frame Runner_2 +1.3-1.5; alive Runner_3; lens_clear; lens_cover <= 0.5
seconds: 2
in: 1.7
motion: 0.012
refilm: v2

## 6
said: v2 of ## 4 (Ryan: "more energy in the forest runner clip"): the SAME tape from the back man running hard (pace 0.8): the lead falling ahead, a flinch, a round across his eyes (2.95 s), the man 2.5 m ahead drops in front of him (3.47 s) and he runs past him; 1.85 s from 2.2, ending before the 59 deg trunk.
capture: --shot=s3_open_lane --stage=forest_going --map=forest --pov=runner --bots=3 --shimmer=0 --look=social --seed=20261017 --set=pace=0.62;pov_start=24.5;pov_pace=0.8;reload=0.45;drop_lead=2.0;miss_pov=2.95;miss_by=1.3;drop_mid=3.4
tape: how_it_started_v2
expect: hit Runner_1 1.95-2.2; in_frame Runner_1 +0.0-0.05; hit ForestCollision +0.8-1.0; hit Runner_2 +1.3-1.5; in_frame Runner_2 +1.3-1.5; alive Runner_3; lens_clear; lens_cover <= 0.5
seconds: 1.85
in: 2.2
refilm: v2

## script v2
from: v1
notes: v11 is great, only issue is the same transparent ragdolls thing, its way too long, signup in bio should always be the same length, and theres no subtitles for the whole point of the short. lastly, the engery in the second clip isnt impressive. so reshoot the second half with the fixes, add the subtitles, lengthen the title card, cut every shot by hald and then give it back. also, make a second variant, with the second half in hell instead of the forest
more energy in the forest runner clip. leave the pill runner clip exactly as it is
captions: stack
captions_size: 96
captions_plain: M1 M3
captions_reset: M3 end
game: 1.0
pad: 0.2
| line | clip | in | len | fit | speed | text | card |
| M1 | cuts/01_v1.mp4 | 0 | 2.45 | beat 2.45 | | how it started | |
| M2 | cuts/02_v1.mp4 | 0 | 2.25 | beat 2.25 | | | |
| M3 | cuts/05_v2.mp4 | 0 | 2 | beat 2 | | how it's going | |
| M4 | cuts/06_v2.mp4 | 0 | 1.85 | beat 1.85 | | | |
| end | title | | 1.75 | | | beta signup in bio | |

## 7
said: v3 of ## 5 (Ryan on v2: "honestly the how its going isnt super impressive, and youre attempt at making the forest energic just reads as it being at a higher speed"): forest_rush, the sniper at the 84 deg window: the hand drops the lead running ahead in the open (2.40 s), swings back onto the pair at the pit lip as the back man shoves the other over it (2.78 s) and drops the shover where he stands (3.50 s); 2.0 s from 1.7, game speed 1.0.
capture: --shot=s3_open_lane --stage=forest_rush --map=forest --pov=guard --bots=3 --shimmer=0 --look=social --seed=20261017 --set=pov_at=65.0,51.0;lane_mid=69.0;lane_r=49.6;victim_speed=0.65;watch=0.8;run_on=3.0;run_to=110.0;run_r=52.0;drop_pov=3.5
tape: how_it_started_v3
hud: crosshair
expect: hit Runner_3 2.3-2.5; in_frame Runner_3 +0.0-0.05; shove Runner_2 +0.3-0.5; hit Runner_1 +1.0-1.2; lens_clear; lens_cover <= 0.5
seconds: 2
in: 1.7
motion: 0.012
refilm: v3

## 8
said: v3 of ## 6 (Ryan on v2: "honestly the how its going isnt super impressive, and youre attempt at making the forest energic just reads as it being at a higher speed"): the SAME tape down the shover's eyes: the lead drops ahead of him (2.40 s), he runs onto the pit-side man, shoves him over the lip (2.78 s) and watches him tumble down the ravine; 1.85 s from 1.5, ending before the hand finds him (3.50 s).
capture: --shot=s3_open_lane --stage=forest_rush --map=forest --pov=runner --bots=3 --shimmer=0 --look=social --seed=20261017 --set=pov_at=65.0,51.0;lane_mid=69.0;lane_r=49.6;victim_speed=0.65;watch=0.8;run_on=3.0;run_to=110.0;run_r=52.0;drop_pov=3.5
tape: how_it_started_v3
expect: hit Runner_3 2.3-2.5; in_frame Runner_3 +0.0-0.05; shove Runner_2 +0.3-0.5; hit Runner_1 +1.0-1.2; lens_clear; lens_cover <= 0.5
seconds: 1.85
in: 1.5
refilm: v3

## script v3
from: v2
notes: honestly the how its going isnt super impressive, and youre attempt at making the forest energic just reads as it being at a higher speed
notes: v11 is great, only issue is the same transparent ragdolls thing, its way too long, signup in bio should always be the same length, and theres no subtitles for the whole point of the short. lastly, the engery in the second clip isnt impressive. so reshoot the second half with the fixes, add the subtitles, lengthen the title card, cut every shot by hald and then give it back. also, make a second variant, with the second half in hell instead of the forest
more energy in the forest runner clip. leave the pill runner clip exactly as it is
captions: stack
captions_size: 96
captions_plain: M1 M3
captions_reset: M3 end
game: 1.0
pad: 0.2
| line | clip | in | len | fit | speed | text | card |
| M1 | cuts/01_v1.mp4 | 0 | 2.45 | beat 2.45 | | how it started | |
| M2 | cuts/02_v1.mp4 | 0 | 2.25 | beat 2.25 | | | |
| M3 | cuts/07_v3.mp4 | 0.3 | 1.7 | beat 1.7 | | how it's going | |
| M4 | cuts/08_v3.mp4 | 0.5 | 1.35 | beat 1.35 | | | |
| end | title | | 1.75 | | | beta signup in bio | |
