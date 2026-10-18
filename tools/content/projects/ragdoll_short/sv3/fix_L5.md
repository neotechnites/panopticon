# fix_L5 (task #630, v23): L5 "these are pretty janky..." refilmed in the forest, three successful visible ragdolls, no shoves.
# Capture brief (shot.sh/tape.sh read it by path): sv3/fix_L5_brief/ragdoll_short.md ## 57. Stage tools/capture/stages/forest_ragdolls.gd.

## 57
said: clip montage of the sniper hitting people dead in hell, and if we can, get one that freaks out and break the players model and go flying -- Ryan 10-12: "lets replace the gameplay of the hitting shots montage to be in the forest"; Ryan 10-17: "didnt i say it has to be in the forest?"; on v22: "in the forest shots, you do not see a single successful ragdoll, and a fucking player shoaves another one for no reason" -- forest_ragdolls: a fixed ground lens on the forest lane (59 deg r 50.2, 1.5 m up, fov 40) looking back up it at 52.3 deg r 51.9, the 54 deg rock outside the frame; three runners come down the lane one after another and the guard at the 32 deg window drops each with a projectile round 8.1-8.3 m off the lens (hits 3.08, 4.92, 6.86); each goes limp and tumbles toward the lens, lying 6.0-6.4 m off it, clear ray every 0.25 s of the 1.5 s after; no shoves (bot shoves off). Mac smoke: as listed.
capture: --map=forest --shot=s3_open_lane --stage=forest_ragdolls --bots=3 --rifle=projectile --shimmer=0 --look=social --seed=20261017
tape: forest_ragdolls_v23c
expect: hit Runner_1 3.0-3.2; in_frame Runner_1 +0.0-0.05; hit Runner_2 +1.75-1.95; in_frame Runner_2 +1.75-1.95; hit Runner_3 +3.7-3.9; in_frame Runner_3 +3.7-3.9; lens_clear; lens_cover <= 0.5
seconds: 7.8
in: 1.2
motion: 0.005
refilm: v23

cut: cuts/05_v23.mp4 (PC content\ragdoll_short\cuts, 7.8 s, 1080x1920; PC take hits 3.07, 4.90, 6.85 = cut 1.87, 3.70, 5.65)
frames: one continuous fixed lens, the forest lane. Cut 1.0-1.9: teal runner jogs down the lane toward the lens; 1.87 the round drops him, he buckles, arms out, and tumbles forward onto his face, limp, legs kicked up (1.9-3.0), and lies there. 2.9-3.7: green runner runs down past him; 3.70 dropped, folds and pitches over onto the teal body (a pile). 4.4-5.6: blue runner comes down; 5.65 dropped mid-stride, legs splayed, flops onto the pile, a leg left sticking up (5.7-7.4). No shoves, no HUD. 7.6 on: a ghost of the first man re-enters (the game's catch-and-swap): keep out.
table row (L5, replaces v22's 54/55 parts): | L5 | cuts/05_v23.mp4@1.0:6.45 | | | line | | these are pretty janky, but im keeping it that way, because it doesnt effect gameplay, and i think makes it more entertaining | | | |
# 1.0-7.45 is one continuous take holding all three kills (no jump cut needed: each kill flows into the next); 'line' trims the tail to the voice. A voice longer than 6.45 s needs picture: do not run past 7.45 (the ghost).
# Interpreted: "if we can ... go flying" not forced (v22's fling=1400 threw the body out of frame, which is what Ryan called no successful ragdoll); no glitch flail occurred in this take.
