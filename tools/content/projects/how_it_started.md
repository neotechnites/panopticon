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

## 9
said: v4 of ## 7 (Ryan on v3: "they dont really read as the same, i think to omuch is going on now in the second half"; ruling: a shot-for-shot twin of ## 1): pill_twin, the pill_era take restaged in the forest by its numbers: the guard at the 0 deg window scoped to fov 28 (pill 28), three abreast on lanes r 51.5/53.5/55.3 at 8 m/s (pill 38.5/44.5/51 at walk 8; r 51-55 is the forest's one trunk-free band, 345.5-31.5 deg), the inner man 2.5 m up (the pill's inner lane gains that by the drop), the outer man held to 1.0 s; the hand parked 4 deg left of the pack, on the middle man from 0.9, drops him at 2.05 (pill 2.07) at 16.9 deg, 49.4 m off, dead centre (pill 44.5 m), holds on him to 2.6. 2.45 s from 0.6, as ## 1 plays.
capture: --shot=s3_open_lane --stage=pill_twin --map=forest --pov=guard --bots=3 --shimmer=0 --look=social --seed=20261017 --set=window=0;eye_r=4.4;start=2;lanes=51.5,53.5,55.3;look=8;inner_ahead=2.5
tape: how_it_started_v4
hud: crosshair
expect: hit Runner_2 1.95-2.15; in_frame Runner_2 +0.0-0.05; alive Runner_3; lens_clear; lens_cover <= 0.5
seconds: 2.6
in: 0.6
motion: 0.012
refilm: v4

## 10
said: v4 of ## 8 (as ## 9): the SAME tape down the held outer man's eyes at fov 70 (pill 70): he goes at 1.0, head eased right onto the mate, who drops at 2.05 6.5 m off, 9.4 deg right, in frame (pill: 2.07, 9 deg right); no trunk within 8 m fills over 0.35 of his frame, the mate never hidden. 2.25 s from 1.0, as ## 2 plays.
capture: --shot=s3_open_lane --stage=pill_twin --map=forest --pov=runner --bots=3 --shimmer=0 --look=social --seed=20261017 --set=window=0;eye_r=4.4;start=2;lanes=51.5,53.5,55.3;look=8;inner_ahead=2.5
tape: how_it_started_v4
expect: hit Runner_2 1.95-2.15; in_frame Runner_2 +0.0-0.05; alive Runner_3; lens_clear; lens_cover <= 0.5
seconds: 2.4
in: 1.0
refilm: v4

## script v4
from: v3
notes: ok, v11 would be fine, but they dont really read as the same, i think to omuch is going on now in the second half. i dont know how to get it to read as "this is the same thing but now it looks really good" because frankly it doesnt look super sexy or anything.
alright, go ahead, try making that for both 11 and 12
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
| M3 | cuts/09_v4b.mp4 | 0 | 2.45 | beat 2.45 | | how it's going | |
| M4 | cuts/10_v4b.mp4 | 0 | 2.25 | beat 2.25 | | | |
| end | title | | 1.75 | | | beta signup in bio | |

## 11
said: v5 of ## 9 (Ryan on v4: "11 is still doesnt read right", "the second half of 11 obviously"; 12 reads: its men are fov-28 big, side-on in the open, the drop mid-frame with nothing between): pill_twin moved to the forest's lip-tree gap (34.6-75.9 deg, no trunk at r 47.45 between the 45 deg arch and the lane; probe_ring --los eye 45:4.4:5.9: a standing man at r 51.9 seen 48-61 and 63-67 deg, a lying one 53-55 and 58-60; the lip bushes at 47/52/64, boulder at 56 and the in-lane trunks at 46.8/61.8 r 49.9 hide him elsewhere). The guard at the 45 deg arch scoped to fov 28 (now at 28 from the first frame: 09_v4b was filmed mid zoom-in, its men half size), three on lanes r 52.6/52.15/51.7 at 8 m/s from 43 deg (the trunks here stand inside the lane at r 49.9, so the pack keeps outside them: the ahead man outermost, the held POV innermost); the hand parked 4 deg left of the pack, on the middle man from 0.9, drops him at 2.05 (pill 2.07) at 58.2 deg, ~48 m off, dead centre, in the clear 58-60 (the 54.0 trunk 3.8 m behind-left of him, the 61.8 trunk 3.3 m ahead-right), holds on him to 2.6. 2.45 s from 0.6, as ## 1 plays.
capture: --shot=s3_open_lane --stage=pill_twin --map=forest --pov=guard --bots=3 --shimmer=0 --look=social --seed=20261017 --set=window=45;eye_r=4.4;start=43;lanes=52.6,52.15,51.7;look=-8;inner_ahead=2.5
tape: how_it_started_v5
hud: crosshair
expect: hit Runner_2 1.95-2.15; in_frame Runner_2 +0.0-0.05; alive Runner_3; lens_clear; lens_cover <= 0.5
seconds: 2.6
in: 0.6
motion: 0.012
refilm: v5

## 12
said: v5 of ## 10 (as ## 11; 10_v4b had the 16.2 deg wall trunk 1.25 m off the POV filling half his frame through the drop): the SAME tape down the held man's eyes at fov 70 on the innermost lane r 51.7: he goes at 1.0, head eased 8 deg LEFT (outward; bearing rising, right is inward) onto the mate 0.45 m outside him, who drops at 2.05 5.8 m off, 4.5 deg right, dead centre (pill 6.5 m, 9 deg; mirrored side); PILL_PROBE: his 9:16 frame 0.00 blocked within 8 m at the drop, under 0.26 from 1.0 (the 54.0 r 53.8 trunk 2.1 m left slides out by 2.0, the 61.8 r 49.9 trunk holds the right edge to 3.0), the mate seen throughout. 2.25 s from 1.0, as ## 2 plays.
capture: --shot=s3_open_lane --stage=pill_twin --map=forest --pov=runner --bots=3 --shimmer=0 --look=social --seed=20261017 --set=window=45;eye_r=4.4;start=43;lanes=52.6,52.15,51.7;look=-8;inner_ahead=2.5
tape: how_it_started_v5
expect: hit Runner_2 1.95-2.15; in_frame Runner_2 +0.0-0.05; alive Runner_3; lens_clear; lens_cover <= 0.5
seconds: 2.4
in: 1.0
refilm: v5

## script v5
from: v4
notes: holy fuck. seriously on the ragdoll? the death animation on the grey background is using a weird fucking model of the character. the onld in game one with a bunch of filters on it. it looks like the version of the character your supposed to see from 100 ft away when it gets low rezed. everything else is good. short 12 is good, 11 is still doesnt read right. short 9 is good, with the one acception that at the end, the very very end, the sniper sits looing at nothing for like a second
the second half of 11 obviously
notes: ok, v11 would be fine, but they dont really read as the same, i think to omuch is going on now in the second half. i dont know how to get it to read as "this is the same thing but now it looks really good" because frankly it doesnt look super sexy or anything.
alright, go ahead, try making that for both 11 and 12
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
| M3 | cuts/11_v5.mp4 | 0 | 2.45 | beat 2.45 | | how it's going | |
| M4 | cuts/12_v5.mp4 | 0 | 2.25 | beat 2.25 | | | |
| end | title | | 1.75 | | | beta signup in bio | |
