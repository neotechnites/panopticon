# how_it_started_hell
kind: short

## 1
said: how it started, pills: sniper perspective. how_it_started's ## 1 take as v2 plays it (Ryan: "leave the pill runner clip exactly as it is"): not filmed here, the table plays ../how_it_started/cuts/01_v1.mp4.

## 2
said: how it started, pills: runners perspective. how_it_started's ## 2 take as v2 plays it: not filmed here, the table plays ../how_it_started/cuts/02_v1.mp4.

## 3
said: vs how its going, cut to hell: sniper perspective (Ryan: "make a second variant, with the second half in hell instead of the forest"). stages ## 1, the hell_explainer guard POV: 2.0 s from 4.4, the hand swings onto the lead and drops him (5.86 s), holding where he falls.
capture: --shot=s3_open_lane --stage=hell_explainer --pov=guard --bots=3 --shimmer=0 --look=social --rifle=projectile --seed=20261017
tape: how_it_started_hell_v1
hud: crosshair
expect: hit Runner_1 5.75-5.95; in_frame Runner_1 +0.0-0.05; out Runner_1 +0.0-0.3; lens_clear; lens_cover <= 0.5
seconds: 2
in: 4.4
motion: 0.012
refilm: v1

## 4
said: how its going, hell: runners perspective. stages ## 2, the SAME tape from the back runner: 1.85 s from 9.6, he runs in on the crouched middle man, shoves him (10.25 s), the hand drops him in the air (10.67 s), he ragdolls.
capture: --shot=s3_open_lane --stage=hell_explainer --pov=runner --bots=3 --shimmer=0 --look=social --rifle=projectile --seed=20261017
tape: how_it_started_hell_v1
expect: hit Runner_1 5.75-5.95; out Runner_1 +0.0-0.3; shove Runner_2 10.15-10.35; in_frame Runner_2 10.6-10.75; out Runner_2 10.6-10.75; alive Runner_3; lens_clear; lens_cover <= 0.5
seconds: 1.85
in: 9.6
motion: 0.011
refilm: v1

## script v1
captions: stack
captions_size: 96
captions_plain: M1 M3
captions_reset: M3 end
game: 1.0
pad: 0.2
| line | clip | in | len | fit | speed | text | card |
| M1 | ../how_it_started/cuts/01_v1.mp4 | 0 | 2.45 | beat 2.45 | | how it started | |
| M2 | ../how_it_started/cuts/02_v1.mp4 | 0 | 2.25 | beat 2.25 | | | |
| M3 | cuts/03_v1.mp4 | 0 | 2 | beat 2 | | how it's going | |
| M4 | cuts/04_v1.mp4 | 0 | 1.85 | beat 1.85 | | | |
| end | title | | 1.75 | | | beta signup in bio | |

## 5
said: v2 of ## 3 (Ryan on v1: "you seriously just used the footage from short 10? really? ... yeah, what im saying is go stage something for it and give it a try, honestly the how its going isnt super impressive"): hell_going, the sniper at the 306 deg window over the S5 lava platforms: three hop the lake, the hand drops the lead at the top of his leap (3.60 s), flicks onto the next man and drops him in the air too (4.07 s), both fall into the lava; then rides the last man hopping on. 2.0 s from 3.1, game speed 1.0.
capture: --shot=lava_parkour --stage=hell_going --pov=guard --bots=3 --shimmer=0 --look=social --seed=20261017
tape: how_it_started_hell_v2
hud: crosshair
expect: hit Runner_1 3.5-3.7; in_frame Runner_1 +0.0-0.05; hit Runner_2 +0.4-0.55; in_frame Runner_2 +0.4-0.55; alive Runner_3; lens_clear; lens_cover <= 0.5
seconds: 2
in: 3.1
motion: 0.012
refilm: v2

## 6
said: v2 of ## 4 (Ryan on v1, as ## 5): the SAME tape down the last hopper's eyes: he lands, leaps; the lead is shot out of the air ahead of him (3.60 s), the man right in front is shot mid-leap (4.07 s) and drops into the lava under him; he lands and hops on. 1.85 s from 3.1.
capture: --shot=lava_parkour --stage=hell_going --pov=runner --bots=3 --shimmer=0 --look=social --seed=20261017
tape: how_it_started_hell_v2
expect: hit Runner_1 3.5-3.7; in_frame Runner_1 +0.0-0.05; hit Runner_2 +0.4-0.55; in_frame Runner_2 +0.4-0.55; alive Runner_3; lens_clear; lens_cover <= 0.5
seconds: 1.85
in: 3.1
refilm: v2

## script v2
from: v1
notes: you seriously just used the footage from short 10? really? ... yeah, what im saying is go stage something for it and give it a try, honestly the how its going isnt super impressive
captions: stack
captions_size: 96
captions_plain: M1 M3
captions_reset: M3 end
game: 1.0
pad: 0.2
| line | clip | in | len | fit | speed | text | card |
| M1 | ../how_it_started/cuts/01_v1.mp4 | 0 | 2.45 | beat 2.45 | | how it started | |
| M2 | ../how_it_started/cuts/02_v1.mp4 | 0 | 2.25 | beat 2.25 | | | |
| M3 | cuts/05_v2.mp4 | 0.2 | 1.5 | beat 1.5 | | how it's going | |
| M4 | cuts/06_v2.mp4 | 0.3 | 1.55 | beat 1.55 | | | |
| end | title | | 1.75 | | | beta signup in bio | |

## 7
said: v3 of ## 5 (Ryan on v2: "when theres shoving and platforming, it doesnt read as the same reall at all"; ruling: a shot-for-shot twin of ## 1): pill_twin in hell: the guard at the 62 deg window scoped to fov 28, three abreast on lanes r 48/50/54 at 8 m/s over the S1 deck (the clear rock-free lanes), the outer man held to 1.0 s; the hand on the middle man from 0.9 drops him at 2.05 44.4 m off dead centre (pill 2.07, 44.5 m), holds on him to 2.6. 2.45 s from 0.6, as ## 1 plays.
capture: --shot=s3_open_lane --stage=pill_twin --pov=guard --bots=3 --shimmer=0 --look=social --seed=20261017 --set=window=62;eye_r=5.6;lanes=48,50,54;look=26
tape: how_it_started_hell_v3
hud: crosshair
expect: hit Runner_2 1.95-2.15; in_frame Runner_2 +0.0-0.05; alive Runner_3; lens_clear; lens_cover <= 0.5
seconds: 2.6
in: 0.6
motion: 0.012
refilm: v3

## 8
said: v3 of ## 6 (as ## 7): the SAME tape down the held outer man's eyes at fov 70: he goes at 1.0, head eased right onto the mate, who drops at 2.05 7.8 m off, 9.9 deg right, in frame (pill 2.07, 9 deg right). 2.25 s from 1.0, as ## 2 plays.
capture: --shot=s3_open_lane --stage=pill_twin --pov=runner --bots=3 --shimmer=0 --look=social --seed=20261017 --set=window=62;eye_r=5.6;lanes=48,50,54;look=26
tape: how_it_started_hell_v3
expect: hit Runner_2 1.95-2.15; in_frame Runner_2 +0.0-0.05; alive Runner_3; lens_clear; lens_cover <= 0.5
seconds: 2.4
in: 1.0
refilm: v3

## script v3
from: v2
notes: yeah same thing with that one, when its just notrmal stuff, it doesnt read as all that amazing compared to what it used to be, but when theres shoving and platforming, it doesnt read as the same reall at all. what are the others like? how can we do this?
alright, go ahead, try making that for both 11 and 12
notes: you seriously just used the footage from short 10? really? ... yeah, what im saying is go stage something for it and give it a try, honestly the how its going isnt super impressive
captions: stack
captions_size: 96
captions_plain: M1 M3
captions_reset: M3 end
game: 1.0
pad: 0.2
| line | clip | in | len | fit | speed | text | card |
| M1 | ../how_it_started/cuts/01_v1.mp4 | 0 | 2.45 | beat 2.45 | | how it started | |
| M2 | ../how_it_started/cuts/02_v1.mp4 | 0 | 2.25 | beat 2.25 | | | |
| M3 | cuts/07_v3.mp4 | 0 | 2.45 | beat 2.45 | | how it's going | |
| M4 | cuts/08_v3.mp4 | 0 | 2.25 | beat 2.25 | | | |
| end | title | | 1.75 | | | beta signup in bio | |
