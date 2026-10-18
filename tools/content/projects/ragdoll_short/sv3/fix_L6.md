# L6 fix for v23 (task #630)

Head: append these as the next two ## entries of projects/ragdoll_short.md (filmed as temp entries 161 and 162) and repoint L6 in ## script v23 to the joined cut (06a_v23 [0.0167-2.3167] + 06b_v23 [0.0167-2.5667], 4.85 s = v22's L6 slot).

## 161
said: L6 (v23, Ryan on v22: "theres a sub one second clip of a bunch of player shoving each other, doesnt show ragdolling, looks like shit"): a bunch of runners shoving each other with the ragdoll, other pov shots of a "real game" where the runners are getting shoved -- the third-person half: shove_flop, a 3-runner hell round on the clear S3-S4 deck (pads and traps off, 4 players with the guard); Runner_2 runs Runner_1 down and shoves him up the lane (1.52 s, 194.2 deg r 51.9); he goes limp in the air and tumbles (the shipped 16/7 shove and flop), lands (2.18), gets up and runs on; a side dolly on the deck 3.5 m outboard, 1.5 m up (fov 62), the pit, tower and eye behind, rides the pair, then him, his whole body in the 9:16 frame from the shove to +1.9 s
capture: --shot=s3_open_lane --stage=shove_flop --bots=3 --seed=20261017 --shimmer=0 --set=pack=3;from=186
tape: rs_flop_side
expect: shove Runner_2 1.45-1.6; in_frame Runner_1 +0.0-0.05; held_in_frame Runner_1 +1.8-2.0; alive Runner_1; lens_clear; lens_cover <= 0.5
seconds: 2.6
in: 0.95
frames: 0.0-0.5 the shover closes on him from behind, both running left to right, the pit, tower and eye behind; 0.57 the shove; 0.7-1.7 he is limp in the air, body flat and tumbling past the pit-side rocks; 1.8 lands, gets up; 1.9-2.3 runs on.
cut: content\ragdoll_short\cuts\06a_v23.mp4 (2.6 s, PC take 161_t1, motion 0.1307, freeze 0)

## 162
said: L6 (v23), the runner-POV half: a bunch of runners shoving each other with the ragdoll, other pov shots of a "real game" where the runners are getting shoved -- shove_flop down the shover's eyes, a 3-runner hell round further back on the same deck; the POV runs Runner_1 down and shoves him straight up the lane (1.52 s, 189.2 deg r 51.9; the POV's own arms push out), the eyes stay on him as he flies limp and tumbles ahead, lands (2.18) sprawled, gets up and runs off; in frame from the shove to +1.9 s
capture: --shot=s3_open_lane --stage=shove_flop --pov=runner --bots=3 --seed=20261017 --shimmer=0 --set=pack=3;from=181
tape: rs_flop_pov
expect: shove Runner_2 1.45-1.6; in_frame Runner_1 +0.0-0.05; held_in_frame Runner_1 +1.8-2.0; alive Runner_1; lens_clear; lens_cover <= 0.5
seconds: 2.8
in: 0.9
frames: 0.0-0.6 running up behind him on the lava-cracked deck, he grows in frame; 0.62 the shove (arms out); 0.7-1.2 he flies limp ahead; 1.2-1.7 sprawled, tumbling on the ground; 1.7-2.0 gets up; 2.0-2.55 runs off up the lane, small.
cut: content\ragdoll_short\cuts\06b_v23.mp4 (2.8 s, PC take 162_t1, motion 0.1322, freeze 0)

joined: content\ragdoll_short\cuts\06_v23.mp4 (4.85 s, 291 frames, lossless libx264rgb): 0-2.3 = 161 (shove 0.55 on "this", flop through "wanted to use it more"), 2.3-4.85 = 162 (cut on "Now", shove 2.9 on "shove", limp and sprawled through "someone, they also", up on "ragdoll").

## script v23 row
| L6 | cuts/06_v23.mp4 | 0 | 4.85 | line | | Once i had this, i wanted to use it more. Now when you shove someone, they also ragdoll. | | | |
