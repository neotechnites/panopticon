# ragdoll_short
kind: short
aspect: 9:16
voice: yes
ryan: on v7: "ragdoll is ok i think, the last shot shows the gaurd clipping into the map after being chucked, and shouldnt. also this sint youre fault, bur we now have a forest map we should be using for some gameplay clips. lets replace the gameplay of the hitting shots montage to be in the forest. also, we should cut after "not an animator" and then the shot of the person getting shoved off and ragdolling, is geniunely, a perfect shot, with the execption that the eye isnt looking at the pov player, and needs to be. so please run that exactly how it was and just fix the eye thing."
# Sources outside cuts\ are the v6/v8 files at the root of content\ragdoll_short\ (filmed before pipeline v2).
# voice\ holds v8's own wavs (rough_v8\voice, Andrew +5%), seeded so nothing is re-spoken.

## 4
said: L4 "...this guy gave me the exact solution to my problem. Ragdolls" -- the guard's scope on the far ring, round onto the runner in the tower room, the point-blank hit on "Ragdolls"; v9 cuts straight to it after "not an animator", so the take has 8.1 s of lead-in before the hit (look=7.5, wait=7.3; hit 9.68 s in the v8 trial take)
capture: --shot=s3_open_lane --stage=rs_tower --pov=guard --bots=2 --seed=20261012 --shimmer=0 --set=cross=1;look=7.5;wait=7.3
hud: crosshair
in: 1.0
seconds: 10.6

## 5
said: L5 "these are pretty janky..." -- Ryan: "replace the gameplay of the hitting shots montage to be in the forest": guard scope over seven live-brain runners on the forest lap, tracer rounds, the hits ragdolling them
capture: --shot=s3_open_lane --stage=forest_hunt --pov=guard --bots=7 --seed=20261012 --shimmer=0 --set=lift=0
hud: crosshair
in: 1.5
seconds: 6.8

## 6
said: L6 "Now when you shove someone, they also ragdoll." -- Ryan: "run that exactly how it was and just fix the eye thing": v6_06_pit5's stage, args and seed, the tower eye on the POV runner (run_clip's own POV eye tracking)
capture: --shot=s3_open_lane --stage=rs_pitshove --pov=runner --bots=4 --seed=7 --shimmer=0
in: 0.6
seconds: 5.2

## script v8
# v8 as delivered (cp.render, rough_v8\edl.json): voice + 0.25 s per line, frame-snapped.
# M2 plays rough_v8\lines\M2.mkv, v8's own picture with the gif already on it (no gif overlay in the cut).
# L4: v6_05_s4 5.1 s, then 04_tower at 0: its hit (3.0 s) lands on "Ragdolls" (8.108 s into the line).
voice: en-US-AndrewNeural +5%
pad: 0.25
captions: pop
captions_font: Impact
captions_size: 76
captions_y: 0.72
| line | clip | in | len | fit | speed | text | card |
| L1 | v6_01_s13.mp4@4.0 |  |  | line |  | The death animation in my game was really bad. |  |
| M2 | rough_v8/lines/M2.mkv@0:2.45 |  |  | beat 2.45 |  |  |  |
| L3 | 03_old_hell_zoomout.mp4@4.15 |  |  | line |  | Yeaeeeeeeeh I needed something better, but if my art didnt make it clear, I'm a programmer, not an animator |  |
| L4 | v6_05_s4.mp4@24.0:5.1,04_tower_runner_shot_momentum.mp4@0 |  |  | line |  | Luckily my solution actually came from you guys, in an earlier short when i asked for suggestions, this guy gave me the exact solution to my problem. Ragdolls | cards/L4_card0.png w=940 y=0.2 |
| L5 | v6_05_s7.mp4@13.0 |  |  | line |  | these are pretty janky, but im keeping it that way, because it doesnt effect gameplay, and i think makes it more entertaining |  |
| L6 | v8_06_pit_eye.mp4@0.6 |  |  | line |  | Once i had this, i wanted to use it more. Now when you shove someone, they also ragdoll. |  |
| L7 | v6_07_s1b.mp4@31.35 |  |  | line |  | And when you reach the tower, you can shove the guard out, and watch them go flying into the pit. |  |
| L8 | v6_07_s1b.mp4@36.3167:0.7833,v6_05_s12.mp4@4.0 |  |  | line |  | Let me know what else I should add in the comments |  |

## script v9
# Ryan's v7 notes: L4 is the refilmed tower take alone (a hard cut after "not an animator"), its hit on
# "Ragdolls"; L5 is the forest montage; L6 the same pit shove with the eye on the POV. The rest is v8.
voice: en-US-AndrewNeural +5%
pad: 0.25
captions: pop
captions_font: Impact
captions_size: 76
captions_y: 0.72
| line | clip | in | len | fit | speed | text | card |
| L1 | v6_01_s13.mp4@4.0 |  |  | line |  | The death animation in my game was really bad. |  |
| M2 | rough_v8/lines/M2.mkv@0:2.45 |  |  | beat 2.45 |  |  |  |
| L3 | 03_old_hell_zoomout.mp4@4.15 |  |  | line |  | Yeaeeeeeeeh I needed something better, but if my art didnt make it clear, I'm a programmer, not an animator |  |
| L4 | cuts/04.mp4@0.57 |  |  | line |  | Luckily my solution actually came from you guys, in an earlier short when i asked for suggestions, this guy gave me the exact solution to my problem. Ragdolls | cards/L4_card0.png w=940 y=0.2 |
| L5 | cuts/05.mp4@0 |  |  | line |  | these are pretty janky, but im keeping it that way, because it doesnt effect gameplay, and i think makes it more entertaining |  |
| L6 | cuts/06.mp4@0 |  |  | line |  | Once i had this, i wanted to use it more. Now when you shove someone, they also ragdoll. |  |
| L7 | v6_07_s1b.mp4@31.35 |  |  | line |  | And when you reach the tower, you can shove the guard out, and watch them go flying into the pit. |  |
| L8 | v6_07_s1b.mp4@36.3167:0.7833,v6_05_s12.mp4@4.0 |  |  | line |  | Let me know what else I should add in the comments |  |
