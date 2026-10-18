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
said: a sniper pov, missing shots, then cut to the runner pov near the end, and he watches the person in front of him get shot -- v24 L4, the runner half (Ryan on v23: "when i say ragdolls, he just drops, he doesnt get shot"): the SAME tape from the man 4.5 m behind the lead on r 48.9, gaining to 1.85 m (lens to chest) by the hit, the lead 11 deg right of centre, chest 15 deg under the eye line; the rifle report (8.68) and the round's impact (9.03, 85.2 deg r 48.7) are in the take's sound; his death ragdoll takes the round at 550 (shipped 70) and keeps 0.3 of his run, so it throws him 1.3 m sideways, feet off the deck, across the frame into the r 50.0 S2 ridge in 0.15 s; the POV pulls up and his watch rides the limp body (watch_limp) as it slides down the rock 2.0-3.2 m off the lens. Mac smoke: as listed.
capture: --shot=s3_open_lane --stage=hell_explainer --pov=runner --bots=3 --shimmer=0 --look=social --rifle=projectile --seed=20261017 --set=start=31,22,0;follow=4.5;pace=0.5;follow_pace=0.535;pov_r=48.9;fling=550;carry=0.3;watch_limp=1;miss_lead=2.4;miss_mid=3.8;drop_at=8.67;hold_to=11;pull_up=-0.1;watch=2.0;watch_h=1.0
tape: ragdoll_short_L4_v24
expect: hit Runner_1 8.93-9.13; in_frame Runner_1 +0.0-0.05; alive Runner_3; lens_clear; lens_cover <= 0.5
seconds: 6.2
in: 4.4
motion: 0.004

cut: cuts/04_v24.mp4 (PC content\ragdoll_short\cuts and sv3/cuts/04_v24.mp4, 9.50 s, 1080x1920 lossless libx264rgb + AAC game sound) = 04a_v24m (## 66, Movie Maker) from 0.10 s (scope up at 0.07) to 3.40, then 04b_v24m (## 67, Movie Maker) from 0 to 6.20. Filmed with --movie because rough (ddagrab) takes carry no sound and the note needs the shot heard. The report lands at 7.58 s in the cut, the impact and throw at 7.93 ("Ragdolls" starts 8.04 in the L4 voice), he lies against the ridge in frame to 9.50.
table row (v24): | L4 | cuts/04_v24.mp4 | 0 | 9.5 | wait | | Luckily my solution actually came from you guys, in an earlier short when i asked for suggestions, this guy gave me the exact solution to my problem? Ragdolls | cards/L4_card0.png w=940 y=0.2 in=0.05 out=0.2 from=this to=Ragdolls+0.6 | | |
game: the table needs a game: header (assemble.py game_vol) above 0 for the take's sound to be heard under the voice.
stage: tools/capture/stages/hell_explainer.gd (new dials fling, carry, follow_right, watch_limp; defaults keep every approved entry). tape: tools/content/projects/ragdoll_short/tapes/ragdoll_short_L4_v24.json. Capture brief: sv3/fix_L4_brief/ragdoll_short.md.
