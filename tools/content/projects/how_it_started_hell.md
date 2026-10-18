# how_it_started_hell
kind: short

## 1
said: how it started, pills: sniper perspective. how_it_started's ## 1 take as v2 plays it (Ryan: "leave the pill runner clip exactly as it is"): not filmed here, the table plays ../how_it_started/cuts/01_v1.mp4.

## 2
said: how it started, pills: runners perspective. how_it_started's ## 2 take as v2 plays it: not filmed here, the table plays ../how_it_started/cuts/02_v1.mp4.

## 3
said: vs how its going, cut to hell: sniper perspective (Ryan: "make a second variant, with the second half in hell instead of the forest"). stages ## 1, the hell_explainer guard POV: 2.0 s from 4.85, the hand settles on the lead and drops him (5.86 s), holding where he falls.
capture: --shot=s3_open_lane --stage=hell_explainer --pov=guard --bots=3 --shimmer=0 --look=social --rifle=projectile --seed=20261017
tape: how_it_started_hell_v1
hud: crosshair
expect: hit Runner_1 5.75-5.95; in_frame Runner_1 +0.0-0.05; out Runner_1 +0.0-0.3; lens_clear; lens_cover <= 0.5
seconds: 2
in: 4.85
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
