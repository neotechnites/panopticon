# ragdoll_short
kind: short
aspect: 9:16
voice: yes
# fix_L5 capture brief (task #630, v23): shot.sh/tape.sh read this file by path; its basename keeps the PC folder content\ragdoll_short.

## 57
said: clip montage of the sniper hitting people dead in hell, and if we can, get one that freaks out and break the players model and go flying -- Ryan 10-12: "lets replace the gameplay of the hitting shots montage to be in the forest"; Ryan 10-17: "didnt i say it has to be in the forest?"; on v22: "in the forest shots, you do not see a single successful ragdoll, and a fucking player shoaves another one for no reason" -- forest_ragdolls: a ground lens on the forest lane (59 deg r 51, 1.5 m up, fov 50) looking back up it; three runners come down the lane one after another and the guard at the 32 deg window drops each with a projectile round 4-5 m off the lens (hits 2.79, 4.79, 6.80); each goes limp and tumbles toward the lens, lying 2.5-3.5 m off it, clear ray every 0.25 s of the 1.5 s after; no shoves (bot shoves off). Mac smoke: as listed.
capture: --map=forest --shot=s3_open_lane --stage=forest_ragdolls --bots=3 --rifle=projectile --shimmer=0 --look=social --seed=20261017
tape: forest_ragdolls_v23
expect: hit Runner_1 2.7-2.9; in_frame Runner_1 +0.0-0.05; hit Runner_2 +1.9-2.1; in_frame Runner_2 +1.9-2.1; hit Runner_3 +3.9-4.1; in_frame Runner_3 +3.9-4.1; lens_clear; lens_cover <= 0.5
seconds: 7.8
in: 1.2
