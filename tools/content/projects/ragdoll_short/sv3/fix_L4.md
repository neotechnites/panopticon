## 57
said: a sniper pov, missing shots, then cut to the runner pov near the end, and he watches the person in front of him get shot -- v23 L4, the sniper half (Ryan on v22: "like holy shit use s2"): hell_explainer follow, one tape with the runner half; the scope puts a round by the lead (lands 2.83) and one by the back man (4.23); the cut ends 5.0, before the lead runs behind the 066 lip rock
capture: --shot=s3_open_lane --stage=hell_explainer --pov=guard --bots=3 --shimmer=0 --look=social --rifle=projectile --seed=20261017 --set=start=31,22,0;follow=4.5;pace=0.5;follow_pace=0.535;miss_lead=2.4;miss_mid=3.8;drop_at=8.67;hold_to=11;pull_up=-0.1;watch=2.0;watch_h=1.0
tape: ragdoll_short_L4_v23
hud: crosshair
expect: hit MapBaseS1Collision 2.73-2.93; alive Runner_1; alive Runner_3; lens_clear; lens_cover <= 0.5
seconds: 3.4
in: 1.6
motion: 0.012

## 58
said: a sniper pov, missing shots, then cut to the runner pov near the end, and he watches the person in front of him get shot -- v23 L4, the runner half: the SAME tape from the man who starts 4.5 m behind the lead and gains to 1.8 m; the lead in front of him is shot on S2 (9.03, 84.9 deg r 48.7, in his frame) on "Ragdolls", he pulls up and watches him ragdoll
capture: --shot=s3_open_lane --stage=hell_explainer --pov=runner --bots=3 --shimmer=0 --look=social --rifle=projectile --seed=20261017 --set=start=31,22,0;follow=4.5;pace=0.5;follow_pace=0.535;miss_lead=2.4;miss_mid=3.8;drop_at=8.67;hold_to=11;pull_up=-0.1;watch=2.0;watch_h=1.0
tape: ragdoll_short_L4_v23
expect: hit Runner_1 8.93-9.13; in_frame Runner_1 +0.0-0.05; alive Runner_3; lens_clear; lens_cover <= 0.5
seconds: 6.2
in: 4.4
motion: 0.004

cut: cuts/04_v23.mp4 (PC content\ragdoll_short\cuts, 9.50 s) = 04a_v23 (## 57) from 0.10 s (the scope is up at 0.10) to 3.40, then 04b_v23 (## 58) from 0 to 6.20. The hit lands at 7.93 s in the cut ("Ragdolls" starts 8.04 in the L4 voice), he tumbles through the word and lies in frame to 9.50.
table row (v23): | L4 | cuts/04_v23.mp4 | 0 | 9.5 | wait | | Luckily my solution actually came from you guys, in an earlier short when i asked for suggestions, this guy gave me the exact solution to my problem? Ragdolls | cards/L4_card0.png w=940 y=0.2 in=0.05 out=0.2 from=this to=Ragdolls+0.6 | | |
frames: 0-3.3 the guard's scope from the 62 deg window on three runners crossing S1 into S2, two rounds land by the pack (0.9, 2.3 s), no hit; 3.3 cut to the back runner's eyes, the lead 4 m ahead closing to 2 m, the S2 lava river opening on the right; 7.93 the lead is shot on S2 (84.9 deg), ragdolls forward and lies in frame while the POV stands and watches.
stage: tools/capture/stages/hell_explainer.gd (new dials follow, follow_pace, pov_r, pull_up, watch_h; defaults keep every approved entry). tape: tools/content/projects/ragdoll_short/tapes/ragdoll_short_L4_v23.json (filmed at e2fc72e2, after c86f4ad4).
