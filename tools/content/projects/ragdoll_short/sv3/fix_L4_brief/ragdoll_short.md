# ragdoll_short
kind: short
aspect: 9:16
voice: yes
# fix_L4 capture brief (task #630, v24): shot.sh/tape.sh read this file by path; its basename keeps the PC folder content\ragdoll_short.

## 66
said: a sniper pov, missing shots, then cut to the runner pov near the end, and he watches the person in front of him get shot -- v24 L4, the sniper half (Ryan on v23: "when i say ragdolls, he just drops, he doesnt get shot"): hell_explainer follow on S2, one tape with ## 67; the scope puts a round by the lead (lands 2.78) and one by the middle man (4.20); the cut ends 5.0, before the lead runs behind the 066 lip rock
capture: --shot=s3_open_lane --stage=hell_explainer --pov=guard --bots=3 --shimmer=0 --look=social --rifle=projectile --seed=20261017 --set=start=31,22,0;follow=4.5;pace=0.5;follow_pace=0.535;pov_r=48.9;fling=550;carry=0.3;watch_limp=1;miss_lead=2.4;miss_mid=3.8;drop_at=8.67;hold_to=11;pull_up=-0.1;watch=2.0;watch_h=1.0
tape: ragdoll_short_L4_v24
hud: crosshair
expect: hit MapBaseS1Collision 2.68-2.88; alive Runner_1; alive Runner_3; lens_clear; lens_cover <= 0.5
seconds: 3.4
in: 1.6
motion: 0.012

## 67
said: a sniper pov, missing shots, then cut to the runner pov near the end, and he watches the person in front of him get shot -- v24 L4, the runner half (Ryan on v23: "when i say ragdolls, he just drops, he doesnt get shot"): the SAME tape from the man 4.5 m behind the lead on r 48.9, gaining to 1.85 m (lens to chest) by the hit, the lead 11 deg right of centre, his chest 15 deg under the eye line; the round comes in from the tower side (frame right, its tracer and streak) and hits him on S2 (9.03, 85.2 deg r 48.7); his death ragdoll takes the round at 550 (shipped 70) and keeps 0.3 of his run, so it throws him 1.3 m sideways across the frame into the r 50.0 S2 ridge in 0.15 s (-18 deg left at +0.2 s); the POV pulls up and his watch rides the limp body (watch_limp), which slides down the rock 2.0-3.2 m off the lens. Mac smoke: as listed.
capture: --shot=s3_open_lane --stage=hell_explainer --pov=runner --bots=3 --shimmer=0 --look=social --rifle=projectile --seed=20261017 --set=start=31,22,0;follow=4.5;pace=0.5;follow_pace=0.535;pov_r=48.9;fling=550;carry=0.3;watch_limp=1;miss_lead=2.4;miss_mid=3.8;drop_at=8.67;hold_to=11;pull_up=-0.1;watch=2.0;watch_h=1.0
tape: ragdoll_short_L4_v24
expect: hit Runner_1 8.93-9.13; in_frame Runner_1 +0.0-0.05; alive Runner_3; lens_clear; lens_cover <= 0.5
seconds: 6.2
in: 4.4
motion: 0.004
