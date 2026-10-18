# L6 fix for v24 (task #630)

Head: append these as the next ## entries of projects/ragdoll_short.md (filmed as temp entry 166) and repoint L6 in ## script v24 to the joined cut. Ryan on v23: "the shove off into the pit changed to a shove just generically, and it looks bad. should be a shove into the pit."

## 166
said: L6 (v24, Ryan on v23: "the shove off into the pit changed to a shove just generically, and it looks bad. should be a shove into the pit."): a bunch of runners shoving each other with the ragdoll, other pov shots of a "real game" where the runners are getting shoved -- the runner-POV half: rs_pitshove (## 52's numbers) on the fixed ragdoll (f0b18e2c), the POV runner (Runner_2) runs down the man on the inside and shoves him over the rim into the pit (4.20 s, 49.2 deg r 48.8), stops at 57 deg and watches him fall (in the pit 6.28)
capture: --shot=s3_open_lane --stage=rs_pitshove --pov=runner --bots=3 --seed=7 --shimmer=0 --set=pack=3;shove_gap=1.3;turn_gap=2.6;shover_r=50.2;from=13;back=8.5;after_to=57
tape: rs_pitshove_v24
expect: shove Runner_2 4.1-4.3; out Runner_1 +2.0-2.2; lens_clear; lens_cover <= 0.5
seconds: 6.4
in: 1.0
frames: 0.0-2.9 running down the rim lane behind him, the pit on the right; 2.95 the POV's arms shove him; 3.0-3.4 he flies limp off the rim over the pit; 3.4-3.8 falls past the tower base into the lava; 3.8-6.4 the POV holds on the pit, tower and eye.
cut: content\ragdoll_short\cuts\06b_v24.mp4 (6.4 s, PC take 166_t1, motion 0.0473, freeze 0)

joined: content\ragdoll_short\cuts\06_v24.mp4 (4.85 s, 291 frames, lossless libx264rgb; Mac copy sv3/cuts/06_v24.mp4) = 06a_v23 (## 63, the third-person shove-and-flop) [0.0167-1.8167] + 06b_v24 [2.75-5.80]: 0-1.8 the side shove and flop (shove 0.55, limp in the air, lands), 1.8 cut to the POV on the lane, 3.0 the shove on "shove", 3.0-4.0 he flies off the rim and falls into the pit through "someone, they also", 4.0-4.85 the pit, tower and eye on "ragdoll".

## script v24 row
| L6 | cuts/06_v24.mp4 | 0 | 4.85 | line | | Once i had this, i wanted to use it more. Now when you shove someone, they also ragdoll. | | | |
