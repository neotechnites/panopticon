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
said: L5 "these are pretty janky..." -- Ryan: "replace the gameplay of the hitting shots montage to be in the forest": part 1, the trailer's forest pack (F2) from the guard's scope at the 45 deg window, the victim dropped in the trunk gap (squeeze 3.55 s)
# forest_hunt (scope_hunt's live brains on the forest) came back blind: its windows and kill stretch are map 1's.
capture: --map=forest --shot=pack_lead --stage=trailer_forest_pack --pov=guard --bots=3 --seed=20261012 --shimmer=0
hud: crosshair
in: 1.5
seconds: 3.4

## 7
said: L5 part 2: the same pack stage at the 92 deg window (zone 2, trailer 5g's args), a second runner dropped (squeeze 3.15 s)
capture: --map=forest --shot=pack_lead --stage=trailer_forest_pack --pov=guard --bots=3 --seed=20261012 --shimmer=0 --set=lift=1;fire=3.15;zone=2
hud: crosshair
in: 1.2
seconds: 3.4

## 6
said: L6 "Now when you shove someone, they also ragdoll." -- Ryan: "run that exactly how it was and just fix the eye thing": v6_06_pit5's stage, args and seed, the tower eye on the POV runner (run_clip's own POV eye tracking)
capture: --shot=s3_open_lane --stage=rs_pitshove --pov=runner --bots=4 --seed=7 --shimmer=0
in: 0.6
seconds: 5.2

## 8
said: L7+L8 -- Ryan on v7: "the last shot shows the gaurd clipping into the map after being chucked, and shouldnt": v6_07_s1b refilmed (rs_live, s3_open_lane, seed 2 (seed 1 with 3 runners: all three shot before the tower), riding Runner_1, who takes the tower with seed 2) on the current build, 3 runners + the guard
capture: --shot=s3_open_lane --stage=rs_live --pov=runner --bots=3 --seed=2 --shimmer=0 --set=ride=Runner_1
in: 0
seconds: 50
refilm: v10

## 9
said: L5 -- Ryan: "replace the gameplay of the hitting shots montage to be in the forest": a plain bot match on the forest, the shipped bot guard's scope, 3 runners
capture: --map=forest --shot=s3_open_lane --stage=rs_live --pov=guard --bots=3 --seed=7 --shimmer=0 --set=lift=1
hud: crosshair
in: 0
seconds: 45
refilm: v10

## 10
said: L5 -- Ryan on v7: "replace the gameplay of the hitting shots montage to be in the forest": the haters stage (forest, not a trailer stage) down the guard's scope, 3 runners; the leader dropped ~1.9 s, the shover ~7.4 s in the take
capture: --map=forest --shot=s3_open_lane --stage=haters --pov=guard --bots=3 --seed=20261012 --shimmer=0
hud: crosshair
in: 1.6
seconds: 8.2

## 11
said: L5 -- Ryan on v7: "replace the gameplay of the hitting shots montage to be in the forest": haters_hell's scope kill ported to the forest (haters_forest), guard scope, 3 runners each dropped in turn, no runner near the portal
capture: --map=forest --shot=s3_open_lane --stage=haters_forest --pov=guard --bots=3 --seed=20261012 --shimmer=0
hud: crosshair
in: 0.6
seconds: 9.0

## 12
said: L4 -- v7's own tower take (04_tower_runner_shot_momentum: rs_tower, s3_open_lane, seed 20260930, 2 bots, default dials) refilmed with a 5.7 s longer lead-in (wait 1.4->7.1, start 1.2->6.9) so it fills from the hard cut after "not an animator"; hit ~9.7 s in the take, 8.68 s into the cut; unscoped (scope=0) as v7's take; the still room before the runner enters is v7's, so motion 0.01, freeze 2
capture: --shot=s3_open_lane --stage=rs_tower --pov=guard --bots=2 --seed=20260930 --shimmer=0 --set=wait=7.1;start=6.9;scope=0
hud: crosshair
motion: 0.01
freeze: 2
in: 1.0
seconds: 10.6

## 13
said: L5 -- Ryan on v7: "replace the gameplay of the hitting shots montage to be in the forest": forest_window, the guard at the 32 deg window, 3 runners dropped in turn on the stretch the tower can see (41-60 deg by probe_ring --los)
capture: --map=forest --shot=s3_open_lane --stage=forest_window --pov=guard --bots=3 --seed=20261012 --shimmer=0
hud: crosshair
in: 1.0
seconds: 9.0

## 14
said: L5 -- Ryan on v7: "replace the gameplay of the hitting shots montage to be in the forest": forest_window (shot 13) at a much tighter scope (fov 10) so each runner fills a good part of the scope as it drops
capture: --map=forest --shot=s3_open_lane --stage=forest_window --pov=guard --bots=3 --seed=20261012 --shimmer=0 --set=scope_fov=10
hud: crosshair
in: 1.0
seconds: 9.0

## 15
said: L5 -- Ryan on v7: "replace the gameplay of the hitting shots montage to be in the forest": the forest sniper's kills seen from the runner side (forest_pov_kills): a runner POV on the open stretch (41-60 deg), two close beside and ahead dropped in turn by the guard at the 32 deg window (3 bots is the cap)
capture: --map=forest --shot=s3_open_lane --stage=forest_pov_kills --pov=runner --bots=3 --seed=20261012 --shimmer=0
in: 0.8
seconds: 10

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


## script v11
# Built from v7 (ragdoll_short_rough_v7.mp4), not v8: L1-L3 are v7's own picture and sound to L4's start (12.72 s).
# L4 the tower refilm alone after "not an animator" (hit 8.68 s into cuts/04 on "Ragdolls" 8.108 s), L5 the forest
# guard scope (cut 10), L6 the pit shove with the eye on the POV (cut 06), L7+L8 the finale refilm (08_v10, shove 40.1 s).
voice: en-US-AndrewNeural +5%
pad: 0.25
game: 1
captions: pop
captions_font: Impact
captions_size: 76
captions_y: 0.72
| line | clip | in | len | fit | speed | text | card |
| V7 | ragdoll_short_rough_v7.mp4@0:12.7167 |  |  | beat 12.7167 |  |  |  |
| L4 | cuts/04.mp4@0.572 |  |  | line |  | Luckily my solution actually came from you guys, in an earlier short when i asked for suggestions, this guy gave me the exact solution to my problem. Ragdolls | cards/L4_card0.png w=940 y=0.2 |
| L5 | cuts/10.mp4@0 |  |  | line |  | these are pretty janky, but im keeping it that way, because it doesnt effect gameplay, and i think makes it more entertaining |  |
| L6 | cuts/06.mp4@0 |  |  | line |  | Once i had this, i wanted to use it more. Now when you shove someone, they also ragdoll. |  |
| L7 | cuts/08_v10.mp4 | 37.0 |  | line |  | And when you reach the tower, you can shove the guard out, and watch them go flying into the pit. |  |
| L8 | cuts/08_v10.mp4 | cont |  | line |  | Let me know what else I should add in the comments |  |

## script v12
notes: ragdoll is ok i think, the last shot shows the gaurd clipping into the map after being chucked, and shouldnt. also this sint youre fault, bur we now have a forest map we should be using for some gameplay clips. lets replace the gameplay of the hitting shots montage to be in the forest. also, we should cut after "not an animator" and then the shot of the person getting shoved off and ragdolling, is geniunely, a perfect shot, with the execption that the eye isnt looking at the pov player, and needs to be. so please run that exactly how it was and just fix the eye thing.
# Built from v7 (ragdoll_short_rough_v7.mp4), not v8: L1-L3 are v7's own picture and sound to L4's start (12.72 s).
# L4 the tower refilm alone after "not an animator" (hit 8.68 s into cuts/04 on "Ragdolls" 8.108 s), L5 the forest
# guard scope (cut 10), L6 the pit shove with the eye on the POV (cut 06), L7+L8 the finale refilm (08_v10, shove 40.1 s).
voice: en-US-AndrewNeural +5%
pad: 0.25
game: 1
captions: pop
captions_font: Impact
captions_size: 76
captions_y: 0.72
| line | clip | in | len | fit | speed | text | card |
| V7 | ragdoll_short_rough_v7.mp4@0:12.7167 |  |  | beat 12.7167 |  |  |  |
| L4 | cuts/04.mp4@0.572 |  |  | line |  | Luckily my solution actually came from you guys, in an earlier short when i asked for suggestions, this guy gave me the exact solution to my problem. Ragdolls | cards/L4_card0.png w=940 y=0.2 from=this to=Ragdolls+0.6 |
| L5 | cuts/11.mp4@0 |  |  | line |  | these are pretty janky, but im keeping it that way, because it doesnt effect gameplay, and i think makes it more entertaining |  |
| L6 | cuts/06.mp4@0 |  |  | line |  | Once i had this, i wanted to use it more. Now when you shove someone, they also ragdoll. |  |
| L7 | cuts/08_v10.mp4 | 37.0 |  | line |  | And when you reach the tower, you can shove the guard out, and watch them go flying into the pit. |  |
| L8 | cuts/08_v10.mp4 | cont |  | line |  | Let me know what else I should add in the comments |  |

## script v13
from: v12
# v12's rows; L4 = v7's own tower take refilmed with a longer lead-in (cut 12), L5 = forest_window at scope fov 10 (cut 14).
notes: ragdoll is ok i think, the last shot shows the gaurd clipping into the map after being chucked, and shouldnt. also this sint youre fault, bur we now have a forest map we should be using for some gameplay clips. lets replace the gameplay of the hitting shots montage to be in the forest. also, we should cut after "not an animator" and then the shot of the person getting shoved off and ragdolling, is geniunely, a perfect shot, with the execption that the eye isnt looking at the pov player, and needs to be. so please run that exactly how it was and just fix the eye thing.
# Built from v7 (ragdoll_short_rough_v7.mp4), not v8: L1-L3 are v7's own picture and sound to L4's start (12.72 s).
# L4 the tower refilm alone after "not an animator" (hit 8.68 s into cuts/04 on "Ragdolls" 8.108 s), L5 the forest
# guard scope (cut 10), L6 the pit shove with the eye on the POV (cut 06), L7+L8 the finale refilm (08_v10, shove 40.1 s).
voice: en-US-AndrewNeural +5%
pad: 0.25
game: 1
captions: pop
captions_font: Impact
captions_size: 76
captions_y: 0.72
| line | clip | in | len | fit | speed | text | card |
| V7 | ragdoll_short_rough_v7.mp4@0:12.7167 |  |  | beat 12.7167 |  |  |  |
| L4 | cuts/12.mp4@0.572 |  |  | line |  | Luckily my solution actually came from you guys, in an earlier short when i asked for suggestions, this guy gave me the exact solution to my problem. Ragdolls | cards/L4_card0.png w=940 y=0.2 from=this to=Ragdolls+0.6 |
| L5 | cuts/14.mp4@0 |  |  | line |  | these are pretty janky, but im keeping it that way, because it doesnt effect gameplay, and i think makes it more entertaining |  |
| L6 | cuts/06.mp4@0 |  |  | line |  | Once i had this, i wanted to use it more. Now when you shove someone, they also ragdoll. |  |
| L7 | cuts/08_v10.mp4 | 37.0 |  | line |  | And when you reach the tower, you can shove the guard out, and watch them go flying into the pit. |  |
| L8 | cuts/08_v10.mp4 | cont |  | line |  | Let me know what else I should add in the comments |  |
## script v14
from: v12
# v12's rows; L4 = v7's own tower take refilmed with a longer lead-in (cut 12), L5 = forest_window at scope fov 10 (cut 14).
notes: ragdoll is ok i think, the last shot shows the gaurd clipping into the map after being chucked, and shouldnt. also this sint youre fault, bur we now have a forest map we should be using for some gameplay clips. lets replace the gameplay of the hitting shots montage to be in the forest. also, we should cut after "not an animator" and then the shot of the person getting shoved off and ragdolling, is geniunely, a perfect shot, with the execption that the eye isnt looking at the pov player, and needs to be. so please run that exactly how it was and just fix the eye thing.
# Built from v7 (ragdoll_short_rough_v7.mp4), not v8: L1-L3 are v7's own picture and sound to L4's start (12.72 s).
# L4 the tower refilm alone after "not an animator" (hit 8.68 s into cuts/04 on "Ragdolls" 8.108 s), L5 the forest
# guard scope (cut 10), L6 the pit shove with the eye on the POV (cut 06), L7+L8 the finale refilm (08_v10, shove 40.1 s).
voice: en-US-AndrewNeural +5%
pad: 0.25
game: 1
captions: pop
captions_font: Impact
captions_size: 76
captions_y: 0.72
| line | clip | in | len | fit | speed | text | card |
| V7 | ragdoll_short_rough_v7.mp4@0:12.7167 |  |  | beat 12.7167 |  |  |  |
| L4 | cuts/12.mp4@0.572 |  |  | line |  | Luckily my solution actually came from you guys, in an earlier short when i asked for suggestions, this guy gave me the exact solution to my problem. Ragdolls | cards/L4_card0.png w=940 y=0.2 from=this to=Ragdolls+0.6 |
| L5 | cuts/14.mp4@0.9:3.0,cuts/14.mp4@5.6 |  |  | line |  | these are pretty janky, but im keeping it that way, because it doesnt effect gameplay, and i think makes it more entertaining |  |
| L6 | cuts/06.mp4@0 |  |  | line |  | Once i had this, i wanted to use it more. Now when you shove someone, they also ragdoll. |  |
| L7 | cuts/08_v10.mp4 | 37.0 |  | line |  | And when you reach the tower, you can shove the guard out, and watch them go flying into the pit. |  |
| L8 | cuts/08_v10.mp4 | cont |  | line |  | Let me know what else I should add in the comments |  |
## script v15
from: v12
# v12's rows; L4 = v7's own tower take refilmed with a longer lead-in (cut 12), L5 = forest_window at scope fov 10 (cut 14).
# v15: v14's rows; L5 = the forest kills from the runner side (cut 15).
notes: ragdoll is ok i think, the last shot shows the gaurd clipping into the map after being chucked, and shouldnt. also this sint youre fault, bur we now have a forest map we should be using for some gameplay clips. lets replace the gameplay of the hitting shots montage to be in the forest. also, we should cut after "not an animator" and then the shot of the person getting shoved off and ragdolling, is geniunely, a perfect shot, with the execption that the eye isnt looking at the pov player, and needs to be. so please run that exactly how it was and just fix the eye thing.
# Built from v7 (ragdoll_short_rough_v7.mp4), not v8: L1-L3 are v7's own picture and sound to L4's start (12.72 s).
# L4 the tower refilm alone after "not an animator" (hit 8.68 s into cuts/04 on "Ragdolls" 8.108 s), L5 the forest
# guard scope (cut 10), L6 the pit shove with the eye on the POV (cut 06), L7+L8 the finale refilm (08_v10, shove 40.1 s).
voice: en-US-AndrewNeural +5%
pad: 0.25
game: 1
captions: pop
captions_font: Impact
captions_size: 76
captions_y: 0.72
| line | clip | in | len | fit | speed | text | card |
| V7 | ragdoll_short_rough_v7.mp4@0:12.7167 |  |  | beat 12.7167 |  |  |  |
| L4 | cuts/12.mp4@0.572 |  |  | line |  | Luckily my solution actually came from you guys, in an earlier short when i asked for suggestions, this guy gave me the exact solution to my problem. Ragdolls | cards/L4_card0.png w=940 y=0.2 from=this to=Ragdolls+0.6 |
| L5 | cuts/15.mp4@0 |  |  | line |  | these are pretty janky, but im keeping it that way, because it doesnt effect gameplay, and i think makes it more entertaining |  |
| L6 | cuts/06.mp4@0 |  |  | line |  | Once i had this, i wanted to use it more. Now when you shove someone, they also ragdoll. |  |
| L7 | cuts/08_v10.mp4 | 37.0 |  | line |  | And when you reach the tower, you can shove the guard out, and watch them go flying into the pit. |  |
| L8 | cuts/08_v10.mp4 | cont |  | line |  | Let me know what else I should add in the comments |  |

## script v16
from: v14
notes: ok, go fix ragdoll and get me a version that neess only my voiceover, and the comment. yes totally fine to use the old footage
# v16 = v14's own frames (final/master/v14.mkv: B1 = L1-L4 with the placeholder card, B6 = L6) with two lines changed:
# L5 = v7's hell montage (v6's kills g4 j78 h40 g12 g10; forest timed out: shots 16-18 unreadable), L7+L8 = shot 19:
# the corridor and portal, the finale cinematic's shove at 37.42 s (no particles), the flat throw cut at 38.80 s before
# the guard drops through the pit floor (38.93-39.1 s), L8 the next rider on the ring from 42.0 s (after his bump into a rock at 40.6-41.9 s).
# Card swap: B1 carries v14's baked placeholder (w=940 y=0.2, 'this' to 'Ragdolls'+0.6 = 17.90-21.42 s); a real card
# at w=940 y=0.2 that is at least as tall covers it on the same slide (assemble card on a split L4 beat).
notes: ragdoll is ok i think, the last shot shows the gaurd clipping into the map after being chucked, and shouldnt. also this sint youre fault, bur we now have a forest map we should be using for some gameplay clips. lets replace the gameplay of the hitting shots montage to be in the forest. also, we should cut after "not an animator" and then the shot of the person getting shoved off and ragdolling, is geniunely, a perfect shot, with the execption that the eye isnt looking at the pov player, and needs to be. so please run that exactly how it was and just fix the eye thing.
# Built from v7 (ragdoll_short_rough_v7.mp4), not v8: L1-L3 are v7's own picture and sound to L4's start (12.72 s).
# L4 the tower refilm alone after "not an animator" (hit 8.68 s into cuts/04 on "Ragdolls" 8.108 s), L5 the forest
# guard scope (cut 10), L6 the pit shove with the eye on the POV (cut 06), L7+L8 the finale refilm (08_v10, shove 40.1 s).
voice: en-US-AndrewNeural +5%
pad: 0.25
game: 1
captions: pop
captions_font: Impact
captions_size: 76
captions_y: 0.72
| line | clip | in | len | fit | speed | text | card |
| B1 | final/master/v14.mkv@0:21.7333 |  |  | beat 21.7333 |  |  |  |
| L5 | v7_05_g4.mp4@1.53:1.30,v7_05_j78.mp4@10.70:1.25,v7_05_h40.mp4@5.76:1.30,v7_05_g12.mp4@12.41:1.25,v7_05_g10.mp4@7.95:1.30 |  |  | line |  | these are pretty janky, but im keeping it that way, because it doesnt effect gameplay, and i think makes it more entertaining |  |
| B6 | final/master/v14.mkv@28.05:4.9 |  |  | beat 4.9 |  |  |  |
| L7 | cuts/19.mp4 | 33.85 |  | line |  | And when you reach the tower, you can shove the guard out, and watch them go flying into the pit. |  |
| L8 | cuts/19.mp4@42.0 |  |  | line |  | Let me know what else I should add in the comments |  |

## 16
said: L5 -- Ryan: "lets replace the gameplay of the hitting shots montage to be in the forest"; "fast clips of the sniper hitting shots"; "dont last long enough for you to see the ragdoll, and every single one is an ariel snipe"; "none of the snipes have projectiles. they need to": a plain forest bot match down the shipped guard's scope, 3 runners; probe_ring --los (forest, eye 28.9): open at r 50-54 on 4, 12, 24-36, 44-48, 60, 72, 80-84, 96, 116, 124, 140-144, 152, 160, 176, 188, 196, 204, 212-216, 224-232, 240, 248-252, 264, 272, 288, 296-300, 316, 324-328, 336, 344-356 deg (canopy between). Taped kills: 0.95 s Runner_3 at 15.7 deg, 19.47 s Runner_1 at 230.8 deg
capture: --map=forest --shot=s3_open_lane --stage=rs_live --pov=guard --bots=3 --seed=11 --shimmer=0 --set=lift=1
tape: forest_kills_11
hud: crosshair
in: 0
seconds: 21.5
motion: 0.005

## 17
said: L5, the same ask: the same forest match on seed 89; taped kills 3.92 s Runner_3 at 50.8 deg, 20.13 s Runner_1 at 209.5 deg
capture: --map=forest --shot=s3_open_lane --stage=rs_live --pov=guard --bots=3 --seed=89 --shimmer=0 --set=lift=1
tape: forest_kills_89
hud: crosshair
in: 0
seconds: 22
motion: 0.005

## 18
said: L5, the same ask: the same forest match on seed 97; taped kills 9.25 s Runner_2 at 102.1 deg, 32.33 s Runner_2 at 9.5 deg
capture: --map=forest --shot=s3_open_lane --stage=rs_live --pov=guard --bots=3 --seed=97 --shimmer=0 --set=lift=1
tape: forest_kills_97
hud: crosshair
in: 0
seconds: 34
motion: 0.005

## 19
said: L7+L8 -- the shove on the guard hidden (v12 diff: "the shove is hidden by orange portal particles"); Ryan: "the gaurd flys off and through the walls of the map, which he shouldnt do"; "the last shot shows the gaurd clipping into the map after being chucked, and shouldnt": shot 8's match (rs_live, seed 2, riding Runner_1, 3 runners + the guard) with the rider's lens widened to fov 100 inside the tower (tower_fov), so the guard is whole in frame when he is shoved; real time, untaped (the tape replayed a different match): headless, Runner_1 takes the tower at 42.80 s
capture: --shot=s3_open_lane --stage=rs_live --pov=runner --bots=3 --seed=2 --shimmer=0 --set=ride=Runner_1;tower_fov=100
in: 0
seconds: 48
refilm: v19

## 20
said: L6 -- Ryan: "when i say "shove someone" the pov runner shoves a person in front of them off into the pit"; "the eye isnt looking at the pov player, and needs to be"; no camera clipping into models: shot 6's rim shove at the 4-player cap (pack=3: the victim, the POV, one ahead + the guard), the shove from 1.8 m (shove_gap 1.3, shover_r 50.2) so his head stays out of the lens, a longer run-down (from 13, back 8.5) so the walk-up covers "once I had this I wanted to use it more"; taped: shove 4.20 s at 49.2 deg r 48.8, 42 deg off the lane, in the pit 6.28 s
capture: --shot=s3_open_lane --stage=rs_pitshove --pov=runner --bots=3 --seed=7 --shimmer=0 --set=pack=3;shove_gap=1.3;turn_gap=2.6;shover_r=50.2;from=13;back=8.5
tape: pit_shove_3
in: 0
seconds: 8


## 21
said: L6, the same ask as 20; shot 20's POV ran on into the 52-54 deg rock (r 50.5) after the shove, the lens inside it at 31.9 s of v17: the run-on lane pulled in to r 48.0 (after_r); taped, the shove unchanged (4.20 s, 49.2 deg, 1.78 m, in the pit 6.28 s)
capture: --shot=s3_open_lane --stage=rs_pitshove --pov=runner --bots=3 --seed=7 --shimmer=0 --set=pack=3;shove_gap=1.3;turn_gap=2.6;shover_r=50.2;from=13;back=8.5;after_r=48.0
tape: pit_shove_3b
in: 0
seconds: 8


## 22
said: L6, the same ask as 20; after the shove shots 20 and 21 ran on into the rim wall (walled from 62 deg, r 47-47.3) with the eyes on the pit, the lens against it: he stops at 57 deg (after_to, he halts at 58.4) and watches the fall; taped, the shove unchanged (4.20 s, 49.2 deg, 1.78 m, in the pit 6.28 s)
capture: --shot=s3_open_lane --stage=rs_pitshove --pov=runner --bots=3 --seed=7 --shimmer=0 --set=pack=3;shove_gap=1.3;turn_gap=2.6;shover_r=50.2;from=13;back=8.5;after_to=57
tape: pit_shove_3c
in: 0
seconds: 8
refilm: v19

## 23
said: L5 -- Ryan: "didnt i say it has to be in the forest?"; "lets replace the gameplay of the hitting shots montage to be in the forest"; "fast clips of the sniper hitting shots"; "dont last long enough for you to see the ragdoll, and every single one is an ariel snipe"; "none of the snipes have projectiles. they need to": shot 16's taped forest match (seed 11) seen from the ground, not the scope: rs_live spectate=1 puts the lens 10-21 m from the runner the guard aims at, on a spot with a clear ray to his chest and feet (the forest's trunks were what hid every scope kill), outside him with the tower behind, and holds on the body 1.8 s after a hit; taped kills 0.95 s Runner_3 at 15.7 deg, 19.47 s Runner_1 at 230.8 deg
capture: --map=forest --shot=s3_open_lane --stage=rs_live --bots=3 --seed=11 --shimmer=0 --set=lift=1;spectate=1
tape: forest_kills_11
in: 0
seconds: 21.5

## 24
said: L5 -- Ryan: "didnt i say it has to be in the forest?"; "lets replace the gameplay of the hitting shots montage to be in the forest"; "fast clips of the sniper hitting shots"; "dont last long enough for you to see the ragdoll, and every single one is an ariel snipe"; "none of the snipes have projectiles. they need to": shot 17's taped forest match (seed 89) seen from the ground, not the scope: rs_live spectate=1 puts the lens 10-21 m from the runner the guard aims at, on a spot with a clear ray to his chest and feet (the forest's trunks were what hid every scope kill), outside him with the tower behind, and holds on the body 1.8 s after a hit; taped kills 3.92 s Runner_3 at 50.8 deg, 20.13 s Runner_1 at 209.5 deg
capture: --map=forest --shot=s3_open_lane --stage=rs_live --bots=3 --seed=89 --shimmer=0 --set=lift=1;spectate=1
tape: forest_kills_89
in: 0
seconds: 22

## 25
said: L5 -- Ryan: "didnt i say it has to be in the forest?"; "lets replace the gameplay of the hitting shots montage to be in the forest"; "fast clips of the sniper hitting shots"; "dont last long enough for you to see the ragdoll, and every single one is an ariel snipe"; "none of the snipes have projectiles. they need to": shot 18's taped forest match (seed 97) seen from the ground, not the scope: rs_live spectate=1 puts the lens 10-21 m from the runner the guard aims at, on a spot with a clear ray to his chest and feet (the forest's trunks were what hid every scope kill), outside him with the tower behind, and holds on the body 1.8 s after a hit; taped kills 9.25 s Runner_2 at 102.1 deg, 32.33 s Runner_2 at 9.5 deg
capture: --map=forest --shot=s3_open_lane --stage=rs_live --bots=3 --seed=97 --shimmer=0 --set=lift=1;spectate=1
tape: forest_kills_97
in: 0
seconds: 34

## 26
said: L5, the same ask as 23 ("didnt i say it has to be in the forest?"): the ground lens now also needs him in sight along his run for the next 1.6 s (3 of 4 points), so the round and the fall stay clear of the trunks; taped forest match seed 17, kills 7.43 s Runner_2 at 82.5 deg, 28.27 s Runner_3 at 341.7 deg
capture: --map=forest --shot=s3_open_lane --stage=rs_live --bots=3 --seed=17 --shimmer=0 --set=lift=1;spectate=1
tape: forest_spec_17
in: 0
seconds: 30

## 27
said: L5, the same ask as 23 ("didnt i say it has to be in the forest?"): the ground lens now also needs him in sight along his run for the next 1.6 s (3 of 4 points), so the round and the fall stay clear of the trunks; taped forest match seed 31, kills 12.45 s Runner_3 at 152.9 deg, 35.38 s Runner_0 at 10.5 deg
capture: --map=forest --shot=s3_open_lane --stage=rs_live --bots=3 --seed=31 --shimmer=0 --set=lift=1;spectate=1
tape: forest_spec_31
in: 0
seconds: 37.5
refilm: v19

## 28
said: L5, the same ask as 23 ("didnt i say it has to be in the forest?"): the ground lens now also needs him in sight along his run for the next 1.6 s (3 of 4 points), so the round and the fall stay clear of the trunks; taped forest match seed 23, kills 4.48 s Runner_3 at 57.7 deg, 43.67 s Runner_3 at 143.2 deg
capture: --map=forest --shot=s3_open_lane --stage=rs_live --bots=3 --seed=23 --shimmer=0 --set=lift=1;spectate=1
tape: forest_spec_23
in: 0
seconds: 45.5

## 29
said: L5, the same ask as 23 ("didnt i say it has to be in the forest?"): the ground lens now also needs him in sight along his run for the next 1.6 s (3 of 4 points), so the round and the fall stay clear of the trunks; taped forest match seed 89, kills 3.92 s, 20.13 s (shot 24 again)
capture: --map=forest --shot=s3_open_lane --stage=rs_live --bots=3 --seed=89 --shimmer=0 --set=lift=1;spectate=1
tape: forest_kills_89
in: 0
seconds: 22
refilm: v19

## 30
said: L5, the same ask as 23 ("didnt i say it has to be in the forest?"): the ground lens now also needs him in sight along his run for the next 1.6 s (3 of 4 points), so the round and the fall stay clear of the trunks; taped forest match seed 97, kills 9.25 s, 32.33 s (shot 25 again)
capture: --map=forest --shot=s3_open_lane --stage=rs_live --bots=3 --seed=97 --shimmer=0 --set=lift=1;spectate=1
tape: forest_kills_97
in: 0
seconds: 34

## 31
said: L5, the same ask as 23 ("didnt i say it has to be in the forest?"): the ground lens, and on a hit it takes the body that was hit as its subject (shot 30 lost the fall to a re-pick); taped forest match seed 53, kill 15.85 s Runner_3
capture: --map=forest --shot=s3_open_lane --stage=rs_live --bots=3 --seed=53 --shimmer=0 --set=lift=1;spectate=1
tape: forest_spec_53
in: 0
seconds: 18

## 32
said: L5, the same ask as 23 ("didnt i say it has to be in the forest?"): the ground lens, and on a hit it takes the body that was hit as its subject (shot 30 lost the fall to a re-pick); taped forest match seed 71, kill 16.82 s Runner_3
capture: --map=forest --shot=s3_open_lane --stage=rs_live --bots=3 --seed=71 --shimmer=0 --set=lift=1;spectate=1
tape: forest_spec_71
in: 0
seconds: 19

## 33
said: L5, the same ask as 23 ("didnt i say it has to be in the forest?"): the ground lens, and on a hit it takes the body that was hit as its subject (shot 30 lost the fall to a re-pick); taped forest match seed 37, kill 22.52 s Runner_3
capture: --map=forest --shot=s3_open_lane --stage=rs_live --bots=3 --seed=37 --shimmer=0 --set=lift=1;spectate=1
tape: forest_spec_37
in: 0
seconds: 25

## 34
said: L5, the same ask as 23 ("didnt i say it has to be in the forest?"): the ground lens, and on a hit it takes the body that was hit as its subject (shot 30 lost the fall to a re-pick); taped forest match seed 97, kill 9.25 s Runner_2 (shot 30 again)
capture: --map=forest --shot=s3_open_lane --stage=rs_live --bots=3 --seed=97 --shimmer=0 --set=lift=1;spectate=1
tape: forest_kills_97
in: 0
seconds: 11.5

## 35
said: L5 (head on v17, Ryan's notes): kill 2 "small and far" and kill 4's lens through a trunk replaced; not "the same yellow gy" twice: the ground lens at 11 m (spec_d), held still through the fall (no re-pick at the hit); kill chosen by the headless log (lens on the victim, clear ray, not the pink runner): seed 17, 7.43 s Runner_2 (teal), lens 6.9 m, clear
capture: --map=forest --shot=s3_open_lane --stage=rs_live --bots=3 --seed=17 --shimmer=0 --set=lift=1;spectate=1;spec_d=11
tape: forest_near_17
in: 0
seconds: 10

## 36
said: L5 (head on v17, Ryan's notes): kill 2 "small and far" and kill 4's lens through a trunk replaced; not "the same yellow gy" twice: the ground lens at 11 m (spec_d), held still through the fall (no re-pick at the hit); kill chosen by the headless log (lens on the victim, clear ray, not the pink runner): seed 71, 39.32 s Runner_2 (teal), lens 7.1 m, clear
capture: --map=forest --shot=s3_open_lane --stage=rs_live --bots=3 --seed=71 --shimmer=0 --set=lift=1;spectate=1;spec_d=11
tape: forest_near_71
in: 0
seconds: 42

## 37
said: L5 (head on v17, Ryan's notes): kill 2 "small and far" and kill 4's lens through a trunk replaced; not "the same yellow gy" twice: the ground lens at 11 m (spec_d), held still through the fall (no re-pick at the hit); kill chosen by the headless log (lens on the victim, clear ray, not the pink runner): seed 103, 1.22 s Runner_2 (teal), lens 5.8 m, clear
capture: --map=forest --shot=s3_open_lane --stage=rs_live --bots=3 --seed=103 --shimmer=0 --set=lift=1;spectate=1;spec_d=11
tape: forest_near_103
in: 0
seconds: 3.5
refilm: v19

## 38
said: L5 (head on v18: kill 2's lens jumped and the fall was lost): the ground lens at 11 m, still through the fall; chosen by the headless log (STAGE_DEBUG): lens on the victim at the hit 9.6 m, clear, and the ragdoll in clear sight every tick of the 1.3 s after; seed 211, 32.25 s Runner_2 (not the pink runner)
capture: --map=forest --shot=s3_open_lane --stage=rs_live --bots=3 --seed=211 --shimmer=0 --set=lift=1;spectate=1;spec_d=11
tape: forest_near_211
in: 0
seconds: 34.5

## script v17
from: v16
# v17 L5 = forest kills from the ground (Ryan: "didnt i say it has to be in the forest?"): shots 27, 34, 29, 33, rs_live spectate.
# v17 = v16 with L6 refilmed (shot 22, head review of v16; 20 and 21 ran the lens into the rim wall): the shove on "shove", the victim 1.8 m off the lens, the eye on the POV.
notes: ok, go fix ragdoll and get me a version that neess only my voiceover, and the comment. yes totally fine to use the old footage
# v16 = v14's own frames (final/master/v14.mkv: B1 = L1-L4 with the placeholder card, B6 = L6) with two lines changed:
# L5 = v7's hell montage (v6's kills g4 j78 h40 g12 g10; forest timed out: shots 16-18 unreadable), L7+L8 = shot 19:
# the corridor and portal, the finale cinematic's shove at 37.42 s (no particles), the flat throw cut at 38.80 s before
# the guard drops through the pit floor (38.93-39.1 s), L8 the next rider on the ring from 42.0 s (after his bump into a rock at 40.6-41.9 s).
# Card swap: B1 carries v14's baked placeholder (w=940 y=0.2, 'this' to 'Ragdolls'+0.6 = 17.90-21.42 s); a real card
# at w=940 y=0.2 that is at least as tall covers it on the same slide (assemble card on a split L4 beat).
notes: ragdoll is ok i think, the last shot shows the gaurd clipping into the map after being chucked, and shouldnt. also this sint youre fault, bur we now have a forest map we should be using for some gameplay clips. lets replace the gameplay of the hitting shots montage to be in the forest. also, we should cut after "not an animator" and then the shot of the person getting shoved off and ragdolling, is geniunely, a perfect shot, with the execption that the eye isnt looking at the pov player, and needs to be. so please run that exactly how it was and just fix the eye thing.
# Built from v7 (ragdoll_short_rough_v7.mp4), not v8: L1-L3 are v7's own picture and sound to L4's start (12.72 s).
# L4 the tower refilm alone after "not an animator" (hit 8.68 s into cuts/04 on "Ragdolls" 8.108 s), L5 the forest
# guard scope (cut 10), L6 the pit shove with the eye on the POV (cut 06), L7+L8 the finale refilm (08_v10, shove 40.1 s).
voice: en-US-AndrewNeural +5%
pad: 0.25
game: 1
captions: pop
captions_font: Impact
captions_size: 76
captions_y: 0.72
| line | clip | in | len | fit | speed | text | card |
| B1 | final/master/v14.mkv@0:21.7333 |  |  | beat 21.7333 |  |  |  |
| L5 | cuts/27.mp4@12.55:1.75,cuts/34.mp4@10.0:1.5,cuts/29.mp4@4.0:1.45,cuts/33.mp4@22.65:1.65 |  |  | line |  | these are pretty janky, but im keeping it that way, because it doesnt effect gameplay, and i think makes it more entertaining |  |
| L6 | cuts/22.mp4 | 1.61 |  | line |  | Once i had this, i wanted to use it more. Now when you shove someone, they also ragdoll. |  |
| L7 | cuts/19.mp4 | 33.85 |  | line |  | And when you reach the tower, you can shove the guard out, and watch them go flying into the pit. |  |
| L8 | cuts/19.mp4@42.0 |  |  | line |  | Let me know what else I should add in the comments |  |

## script v18
from: v17
# v18 (head on v17): L5 kill 2 = shot 38 (teal, the lens still), kill 4 = shot 37 (green) cut before his legs reach the lens; L6 0.2 s
# later (shove still inside "shove") and ends 0.4 s after the body drops; L7 starts there, 0.7 s earlier in its take (before 33.15 s
# the rider's lens is inside rocks), so every L7/L8 frame from 32.95 s on is v17's.
# v17 L5 = forest kills from the ground (Ryan: "didnt i say it has to be in the forest?"): shots 27, 34, 29, 33, rs_live spectate.
# v17 = v16 with L6 refilmed (shot 22, head review of v16; 20 and 21 ran the lens into the rim wall): the shove on "shove", the victim 1.8 m off the lens, the eye on the POV.
notes: ok, go fix ragdoll and get me a version that neess only my voiceover, and the comment. yes totally fine to use the old footage
# v16 = v14's own frames (final/master/v14.mkv: B1 = L1-L4 with the placeholder card, B6 = L6) with two lines changed:
# L5 = v7's hell montage (v6's kills g4 j78 h40 g12 g10; forest timed out: shots 16-18 unreadable), L7+L8 = shot 19:
# the corridor and portal, the finale cinematic's shove at 37.42 s (no particles), the flat throw cut at 38.80 s before
# the guard drops through the pit floor (38.93-39.1 s), L8 the next rider on the ring from 42.0 s (after his bump into a rock at 40.6-41.9 s).
# Card swap: B1 carries v14's baked placeholder (w=940 y=0.2, 'this' to 'Ragdolls'+0.6 = 17.90-21.42 s); a real card
# at w=940 y=0.2 that is at least as tall covers it on the same slide (assemble card on a split L4 beat).
notes: ragdoll is ok i think, the last shot shows the gaurd clipping into the map after being chucked, and shouldnt. also this sint youre fault, bur we now have a forest map we should be using for some gameplay clips. lets replace the gameplay of the hitting shots montage to be in the forest. also, we should cut after "not an animator" and then the shot of the person getting shoved off and ragdolling, is geniunely, a perfect shot, with the execption that the eye isnt looking at the pov player, and needs to be. so please run that exactly how it was and just fix the eye thing.
# Built from v7 (ragdoll_short_rough_v7.mp4), not v8: L1-L3 are v7's own picture and sound to L4's start (12.72 s).
# L4 the tower refilm alone after "not an animator" (hit 8.68 s into cuts/04 on "Ragdolls" 8.108 s), L5 the forest
# guard scope (cut 10), L6 the pit shove with the eye on the POV (cut 06), L7+L8 the finale refilm (08_v10, shove 40.1 s).
voice: en-US-AndrewNeural +5%
pad: 0.25
game: 1
captions: pop
captions_font: Impact
captions_size: 76
captions_y: 0.72
| line | clip | in | len | fit | speed | text | card |
| B1 | final/master/v14.mkv@0:21.7333 |  |  | beat 21.7333 |  |  |  |
| L5 | cuts/27.mp4@12.5:1.85,cuts/38.mp4@31.85:1.75,cuts/29.mp4@3.9:1.55,cuts/37.mp4@0.75:1.3 |  |  | line |  | these are pretty janky, but im keeping it that way, because it doesnt effect gameplay, and i think makes it more entertaining |  |
| L6 | cuts/22.mp4@1.41:4.2 |  |  | nohold |  | Once i had this, i wanted to use it more. Now when you shove someone, they also ragdoll. |  |
| L7 | cuts/19.mp4 | 33.15 |  | line |  | And when you reach the tower, you can shove the guard out, and watch them go flying into the pit. |  |
| L8 | cuts/19.mp4@42.0 |  |  | line |  | Let me know what else I should add in the comments |  |

## 39
said: L4 -- Ryan: "we need to change shot 4, to instead be a sniper pov, missing shots, then cut to the runner pov near the end, and he watches the person in front of him get shot": the runner POV half: pack_sniped down the back runner's eyes with a pack of three (4 players), the one a step ahead and to his right dropped at 3.01 s (Mac smoke: hit Runner_2 at 164.4 deg r 53.0, the tracer from the tower)
capture: --shot=pack_lead --stage=pack_sniped --pov=runner --bots=3 --shimmer=0 --set=pack=3;pov_index=2;victim_index=1;pov_back=1.4
in: 0
seconds: 7
refilm: v19

## 40
said: L1 "The death animation in my game was really bad." -- Ryan: "start form scratch", every clip filmed new: the guard's scope on hell, 3 runners (4 players), two misses then a hit at the line's end; rs_snipe old=1 plays the pre-ragdoll Death clip on the kill (filmed fresh on this build instead of an old-commit checkout: the stage's own switch, no ref: needed); start 1.0 so the hit lands ~5.65 s in the take, held through the old death animation for M2
capture: --shot=s3_open_lane --stage=rs_snipe --pov=guard --bots=3 --seed=20261017 --shimmer=0 --set=old=1;plan=0m,1m,2h;start=1.0
hud: crosshair
motion: 0.005
freeze: 1
in: 2.6
seconds: 6.5

## 41
said: L3 "...I'm a programmer, not an animator" -- "slow zoom out shot of the old hell map": the pit_orbit lens over hell during a live 3-runner bot match (rs_live; rs_snipe is guard-POV only); the orbit is the nearest shipped pull-back lens, no zoom-out path exists
capture: --shot=pit_orbit --stage=rs_live --bots=3 --seed=20261017 --shimmer=0
in: 1.0
seconds: 8

## 42
said: L4 -- Ryan: "a sniper pov, missing shots, then cut to the runner pov near the end": the sniper half, the guard's scope on hell missing four shots at three runners (rs_snipe plan of misses, nobody dropped), then shot 39's runner POV
capture: --shot=s3_open_lane --stage=rs_snipe --pov=guard --bots=3 --seed=20261017 --shimmer=0 --set=plan=0m,1m,2m,0m
hud: crosshair
motion: 0.005
freeze: 1
in: 1.0
seconds: 7.5

## script v19
from: v14
# v19 from scratch, EVERY CLIP FILMED NEW (Ryan: "start form scratch"; "SO WHAT THE FUCK IS NOT CLEAR ABOUT START FROM FUCKING SCRATCH"):
# L1 = shot 40 (scope, hell, misses then the old Death clip on the hit at the line's end), M2 = the same take held through the
#   old death animation (the scared.gif fade is not in this cut: no gif in the project folder, no fade in the cutter).
# L3 = shot 41 (pit_orbit over hell, old Death clips), hard cut on "animator". L4 = shot 42's scope misses 6.7 s, then shot 39
#   refilmed from 1.2 s: the hit 1.81 s in lands ~0.4 s after "Ragdolls"; the placeholder card slams on at "this guy".
# L5 = forest kills 27, 37, 29 refilmed from their tapes; L6 = shot 22 refilmed; L7 = shot 19 refilmed from 33.2 s. No L8.
notes: i want you, to start form scratch, on all for of these
voice: en-US-AndrewNeural +5%
pad: 0.25
game: 1
captions: pop
captions_font: Impact
captions_size: 76
captions_y: 0.72
| line | clip | in | len | fit | speed | text | card |
| L1 | cuts/40.mp4 | 2.6 |  | line |  | The death animation in my game was really bad. |  |
| M2 | cuts/40.mp4 | cont |  | beat 1.35 |  |  |  |
| L3 | cuts/41.mp4 | 1.0 |  | line |  | Yeaeeeeeeeh I needed something better, but if my art didnt make it clear, I'm a programmer, not an animator |  |
| L4 | cuts/42.mp4@1.0:6.7,cuts/39_v19.mp4@1.2:3.6 |  |  | wait |  | Luckily my solution actually came from you guys, in an earlier short when i asked for suggestions, this guy gave me the exact solution to my problem. Ragdolls | cards/L4_card0.png w=940 y=0.2 in=0.05 out=0.2 from=this to=Ragdolls+0.6 |
| L5 | cuts/27_v19.mp4@11.85:2.65,cuts/37_v19.mp4@0.6833:1.4167,cuts/29_v19.mp4@3.25:2.25 |  |  | line |  | these are pretty janky, but im keeping it that way, because it doesnt effect gameplay, and i think makes it more entertaining |  |
| L6 | cuts/22_v19.mp4@1.21:4.25 |  |  | nohold |  | Once i had this, i wanted to use it more. Now when you shove someone, they also ragdoll. |  |
| L7 | cuts/19_v19.mp4 | 33.2 |  | line |  | And when you reach the tower, you can shove the guard out, and watch them go flying into the pit. |  |

## 43
said: pov of the sniper shooting at some runners and missing, hell map, right at the end, they hit one, and we cut a little after the animation plays out -- rs_snipe (stages#9): two misses (2.25, 3.95), then the hit (5.65) plays the old Death clip, held 1.75 s
capture: --shot=s3_open_lane --stage=rs_snipe --pov=guard --bots=3 --seed=20261017 --shimmer=0 --set=old=1;plan=0m,1m,2h;start=1.0
hud: crosshair
expect: hit Runner_3 5.55-5.75; lens_clear; lens_cover <= 0.5
seconds: 5
in: 2.6
motion: 0.005
freeze: 1
refilm: v20

## 44
said: shot of the animation in a grey space jsut playing, with a slow fade in of an image i will provide https://media.tenor.com/17aPeH713cYAAAAM/scared.gif -- death_void (stages#10): the old Death clip (ragdoll off) on one prisoner alone in a grey void; scared.gif fades in over it in the cut (gif_fade)
capture: --shot=s3_open_lane --stage=death_void --bots=1 --seed=20261017 --shimmer=0
expect: death Runner_1 1.5-1.7; lens_clear
seconds: 3.6
in: 1.2
motion: 0.002
freeze: waive
refilm: v20

## 45
said: slow zoom out shot of the old hell map -- the hell ring, map 1 (the old map: the forest is the new one), as it ships; hell_pullback (stages#11) cranes up and back over it during a live 3-runner match
capture: --shot=pit_orbit --stage=hell_pullback --bots=3 --seed=20261017 --shimmer=0
expect: pullback start 0.9-1.1; pullback end 8.9-9.1; lens_clear; lens_cover <= 0.5
seconds: 8.2
in: 1
refilm: v20

## 46
said: a sniper pov, missing shots, then cut to the runner pov near the end, and he watches the person in front of him get shot -- the sniper half (stages#12): hell_explainer's scope through its two misses (2.43, 3.80); the line then cuts to ## 50, the back runner's POV of the same staged match, near the end as the lead in front of him is shot (6.27)
capture: --shot=s3_open_lane --stage=hell_explainer --pov=guard --bots=3 --shimmer=0 --look=social --rifle=projectile --seed=20261017 --set=start=31,22,4.8;drop_at=5.9
hud: crosshair
expect: hit Runner_1 6.17-6.37; in_frame Runner_1 +0.0-0.05; lens_clear; lens_cover <= 0.5
seconds: 4.6
in: 1
motion: 0.012
refilm: v20

## 47
said: clip montage of the sniper hitting people dead in hell, and if we can, get one that freaks out and break the players model and go flying -- Ryan 10-12: "lets replace the gameplay of the hitting shots montage to be in the forest"; Ryan 10-17: "didnt i say it has to be in the forest?" -- forest_going's scope (stages#14), the lead's ragdoll flung (fling=1400) on the first kill (2.30), the middle man after (3.70); the montage goes on to ## 51's two tight-scope forest kills
capture: --shot=s3_open_lane --stage=forest_going --map=forest --pov=guard --bots=3 --shimmer=0 --look=social --seed=20261017 --set=fling=1400
hud: crosshair
expect: hit Runner_1 2.2-2.4; in_frame Runner_1 +0.0-0.05; hit Runner_2 +1.3-1.5; in_frame Runner_2 +1.3-1.5; alive Runner_3; lens_clear; lens_cover <= 0.5
seconds: 6.5
in: 1.2
motion: 0.012
refilm: v20

## 48
said: a bunch of runners shoving each other with the ragdoll, other pov shots of a "real game" where the runners are getting shoved -- the melee scrap (stages#16), three runners shoving each other; the line then cuts to ## 52, a runner POV in a real round shoving a man into the pit
capture: --shot=s3_melee --stage=melee --bots=3 --seed=20261017 --shimmer=0 --set=count=3
expect: shove Runner_2 1.4-1.55; shove Runner_3 +0.5-0.65; lens_clear; lens_cover <= 0.5
seconds: 5.9
in: 2.2
refilm: v20

## 49
said: pov runner makes it through the portal, shoves, and the usual cinematic shot -- finale (stages#18): the run into the portal, the arrival (2.13), the shove (3.63), the shipped 2.0 s kill-beat cinematic
capture: --shot=s3_open_lane --stage=finale --pov=runner --bots=3 --shimmer=0 --seed=20261012 --set=lead=6.0;stand=3.0;pace=0.32;beat=2.0
expect: shove Runner_0 3.48-3.78; arrive Runner_1 2.0-2.25; tower_out Runner_0 +1.9-2.1; alive Runner_1; lens_clear; lens_cover <= 0.5
seconds: 6.5
in: 0.9
refilm: v20


## 50
said: a sniper pov, missing shots, then cut to the runner pov near the end, and he watches the person in front of him get shot -- the runner half (stages#13): ## 46's staged match (same seed and dials, untaped: the PC stays free for shorts 10 and 11) from the back runner's eyes; the second round lands by the pack (3.80) and the lead, in front of him, drops in his frame (6.27) on "Ragdolls"
capture: --shot=s3_open_lane --stage=hell_explainer --pov=runner --bots=3 --shimmer=0 --look=social --rifle=projectile --seed=20261017 --set=start=31,22,4.8;drop_at=5.9
expect: hit Runner_1 6.17-6.37; in_frame Runner_1 +0.0-0.05; lens_clear; lens_cover <= 0.5
seconds: 4.5
in: 2.6
motion: 0.011
refilm: v20

## 51
said: clip montage of the sniper hitting people dead in hell, and if we can, get one that freaks out and break the players model and go flying -- Ryan 10-12: "lets replace the gameplay of the hitting shots montage to be in the forest"; Ryan 10-17: "didnt i say it has to be in the forest?" -- the montage's other kills (stages#15): forest_window at the tight scope (fov 10), Runner_1 dropped at 2.60, Runner_3 at 7.80
capture: --map=forest --shot=s3_open_lane --stage=forest_window --pov=guard --bots=3 --seed=20261012 --shimmer=0 --set=scope_fov=10
hud: crosshair
expect: hit Runner_1 2.5-2.7; hit Runner_3 +5.1-5.3; lens_clear; lens_cover <= 0.5
seconds: 9.0
in: 1.0
motion: 0.005
refilm: v20

## 52
said: a bunch of runners shoving each other with the ragdoll, other pov shots of a "real game" where the runners are getting shoved -- the "real game" POV (stages#17): rs_pitshove, the POV runner shoves the man on the inside over the rim (4.20) on "shove", he lands in the pit (6.28)
capture: --shot=s3_open_lane --stage=rs_pitshove --pov=runner --bots=3 --seed=7 --shimmer=0 --set=pack=3;shove_gap=1.3;turn_gap=2.6;shover_r=50.2;from=13;back=8.5;after_to=57
expect: shove Runner_2 4.1-4.3; out Runner_1 +2.0-2.2; lens_clear; lens_cover <= 0.5
seconds: 6.4
in: 1.0
refilm: v20


## 53
said: slow zoom out shot of the old hell map -- the hell ring, map 1 (the old map: the forest is the new one), as it ships; hell_pullback (stages#11) refilmed after the frame check of v20's first cut (shot 45's crane read as a push toward the tower): the lens opens close on the tower and pulls straight back and up the shaft over 8 s, the tower shrinking as the pit, the deck and the far gallery come into frame, during a live 3-runner match
capture: --shot=pit_orbit --stage=hell_pullback --bots=3 --seed=20261017 --shimmer=0
expect: pullback start 0.9-1.1; pullback end 8.9-9.1; lens_clear; lens_cover <= 0.5
seconds: 8.2
in: 1.0
motion: 0.01
refilm: v21

## 54
said: clip montage of the sniper hitting people dead in hell, and if we can, get one that freaks out and break the players model and go flying -- Ryan 10-12: "lets replace the gameplay of the hitting shots montage to be in the forest"; Ryan 10-17: "didnt i say it has to be in the forest?" -- shot 47 at the tight scope (scope_fov=10; shot 47's 24 deg scope left the men too small to read): forest_going, the lead's ragdoll flung (fling=1400) on the first kill (2.30), the middle man after (3.70), both in frame
capture: --shot=s3_open_lane --stage=forest_going --map=forest --pov=guard --bots=3 --shimmer=0 --look=social --seed=20261017 --set=fling=1400;scope_fov=10
hud: crosshair
expect: hit Runner_1 2.2-2.4; in_frame Runner_1 +0.0-0.05; hit Runner_2 +1.3-1.5; in_frame Runner_2 +1.3-1.5; alive Runner_3; lens_clear; lens_cover <= 0.5
seconds: 4.0
in: 1.2
motion: 0.012
refilm: v21

## 55
said: clip montage of the sniper hitting people dead in hell, and if we can, get one that freaks out and break the players model and go flying -- Ryan 10-12: "lets replace the gameplay of the hitting shots montage to be in the forest"; Ryan 10-17: "didnt i say it has to be in the forest?" -- the montage's other forest kills (ragdoll_short#10, haters down the guard's scope, in place of shot 51 whose kills were behind trunks): the leader dropped (2.40), the shover throws a man into the ravine (5.03, impulse 18 up 6: he goes flying, the scope follows), the shover dropped (6.50)
capture: --map=forest --shot=s3_open_lane --stage=haters --pov=guard --bots=3 --seed=20261012 --shimmer=0
hud: crosshair
expect: hit Runner_3 2.3-2.5; shove Runner_1 +2.55-2.75; hit Runner_1 +4.0-4.2; lens_clear; lens_cover <= 0.5
seconds: 6.6
in: 1.0
motion: 0.012
refilm: v21

## 56
said: a sniper pov, missing shots, then cut to the runner pov near the end, and he watches the person in front of him get shot -- the runner half (ragdoll_short#39, pack_sniped, in place of shot 50 whose lead dropped outside the portrait frame): down the back runner's eyes in a pack of three (4 players), the one a step ahead and to his right dropped by the tower (3.02), and he runs on watching him ragdoll through "Ragdolls"
capture: --shot=pack_lead --stage=pack_sniped --pov=runner --bots=3 --shimmer=0 --seed=20261017 --set=pack=3;pov_index=2;victim_index=1;pov_back=1.4
expect: hit Runner_2 2.92-3.12; lens_clear; lens_cover <= 0.5
seconds: 5.0
in: 1.0
refilm: v21

## script v20
# short3 plan's table, rows composed by hand where a line needs more than one shot (task #630, short 4 from scratch):
# L1 the second miss and the hit with the old Death clip just after "bad", held 1.75 s past the hit; M2 the grey void
# death, scared.gif fading in from 1.2 s over 2.0 s (the beat ends with the fade); L3 the crane-out; L4 the scope's two
# misses (46), then the back runner (50) as the lead ahead drops on "Ragdolls", the placeholder comment card at "this guy";
# L5 forest: the flung lead and the middle man (47), then two tight-scope drops (51); L6 the 3-runner scrap (48), then the
# POV's pit shove on "shove" (52); L7 the portal, the shove and the 2.0 s kill-beat cinematic (49). "htis" spoken "this".
pad: 0.2
| line | clip | in | len | fit | speed | text | card | grade | gif_fade |
| L1 | cuts/43_v20.mp4 | 0.3 | 4.5 | wait | | The death animation in my game was really bad. | | | |
| M2 | cuts/44_v20.mp4 | 0 | 3.6 | beat 3.6 | | | | | external/scared.gif 1.2 2.0 end |
| L3 | cuts/45_v20.mp4 | 1.5 | 6.7 | line | | Yeaeeeeeeeh I needed something better, but if my art didnt make it clear, I'm a programmer, not an animator | | | |
| L4 | cuts/46_v20.mp4@0:4.6,cuts/50_v20.mp4@0 | | | line | | Luckily my solution actually came from you guys, in an earlier short when i asked for suggestions, this guy gave me the exact solution to my problem? Ragdolls | cards/L4_card0.png w=940 y=0.2 in=0.05 out=0.2 from=this to=Ragdolls+0.6 | | |
| L5 | cuts/47_v20.mp4@0.5:2.9,cuts/51_v20.mp4@0.9:1.7,cuts/51_v20.mp4@6.2 | | | line | | these are pretty janky, but im keeping it that way, because it doesnt effect gameplay, and i think makes it more entertaining | | | |
| L6 | cuts/48_v20.mp4@1.1:1.6,cuts/52_v20.mp4@2.05 | | | line | | Once i had this, i wanted to use it more. Now when you shove someone, they also ragdoll. | | | |
| L7 | cuts/49_v20.mp4 | 0.4 | | line | | And when you reach the tower, you can shove the guard out, and watch them go flying into the pit. | | | |
| end | title | | 1.75 | | | beta signup in bio | | | |

## script v21
# v21 = v20 after its frame check (never shown to Ryan): L3, L4's runner half and L5 refilmed; v20's table, rows composed by hand where a line needs more than one shot (task #630, short 4 from scratch):
# L1 the second miss and the hit with the old Death clip just after "bad", held 1.75 s past the hit; M2 the grey void
# death, scared.gif fading in from 1.2 s over 2.0 s (the beat ends with the fade); L3 the crane-out; L4 the scope's two
# misses (46), then the back runner (50) as the lead ahead drops on "Ragdolls", the placeholder comment card at "this guy";
# L5 forest: the flung lead and the middle man (54), the haters scope's drop, ravine throw and drop (55); frame check: L3 = 53 (45 read as a push in), L4 runner = 56 (50's lead left the frame); L6 the 3-runner scrap (48), then the
# POV's pit shove on "shove" (52); L7 the portal, the shove and the 2.0 s kill-beat cinematic (49). "htis" spoken "this".
pad: 0.2
| line | clip | in | len | fit | speed | text | card | grade | gif_fade |
| L1 | cuts/43_v20.mp4 | 0.3 | 4.5 | wait | | The death animation in my game was really bad. | | | |
| M2 | cuts/44_v20.mp4 | 0 | 3.6 | beat 3.6 | | | | | external/scared.gif 1.2 2.0 end |
| L3 | cuts/53_v21.mp4 | 1.5 | 6.7 | line | | Yeaeeeeeeeh I needed something better, but if my art didnt make it clear, I'm a programmer, not an animator | | | |
| L4 | cuts/46_v20.mp4@0:4.6,cuts/56_v21.mp4@0 | | | line | | Luckily my solution actually came from you guys, in an earlier short when i asked for suggestions, this guy gave me the exact solution to my problem? Ragdolls | cards/L4_card0.png w=940 y=0.2 in=0.05 out=0.2 from=this to=Ragdolls+0.6 | | |
| L5 | cuts/54_v21.mp4@0.6:2.4,cuts/55_v21.mp4@0.8:1.2,cuts/55_v21.mp4@3.7 | | | line | | these are pretty janky, but im keeping it that way, because it doesnt effect gameplay, and i think makes it more entertaining | | | |
| L6 | cuts/48_v20.mp4@1.1:1.6,cuts/52_v20.mp4@2.05 | | | line | | Once i had this, i wanted to use it more. Now when you shove someone, they also ragdoll. | | | |
| L7 | cuts/49_v20.mp4 | 0.4 | | line | | And when you reach the tower, you can shove the guard out, and watch them go flying into the pit. | | | |
| end | title | | 1.75 | | | beta signup in bio | | | |

## script v22
# v22 = v21 with L5's haters part ending before the guard's re-seat (the HUD's tower banner showed for 0.15 s at v21's 28.85 s); v21 = v20 after its frame check (never shown to Ryan): L3, L4's runner half and L5 refilmed; v20's table, rows composed by hand where a line needs more than one shot (task #630, short 4 from scratch):
# L1 the second miss and the hit with the old Death clip just after "bad", held 1.75 s past the hit; M2 the grey void
# death, scared.gif fading in from 1.2 s over 2.0 s (the beat ends with the fade); L3 the crane-out; L4 the scope's two
# misses (46), then the back runner (50) as the lead ahead drops on "Ragdolls", the placeholder comment card at "this guy";
# L5 forest: the flung lead and the middle man (54), the haters scope's drop, ravine throw and drop (55); frame check: L3 = 53 (45 read as a push in), L4 runner = 56 (50's lead left the frame); L6 the 3-runner scrap (48), then the
# POV's pit shove on "shove" (52); L7 the portal, the shove and the 2.0 s kill-beat cinematic (49). "htis" spoken "this".
pad: 0.2
| line | clip | in | len | fit | speed | text | card | grade | gif_fade |
| L1 | cuts/43_v20.mp4 | 0.3 | 4.5 | wait | | The death animation in my game was really bad. | | | |
| M2 | cuts/44_v20.mp4 | 0 | 3.6 | beat 3.6 | | | | | external/scared.gif 1.2 2.0 end |
| L3 | cuts/53_v21.mp4 | 1.5 | 6.7 | line | | Yeaeeeeeeeh I needed something better, but if my art didnt make it clear, I'm a programmer, not an animator | | | |
| L4 | cuts/46_v20.mp4@0:4.6,cuts/56_v21.mp4@0 | | | line | | Luckily my solution actually came from you guys, in an earlier short when i asked for suggestions, this guy gave me the exact solution to my problem? Ragdolls | cards/L4_card0.png w=940 y=0.2 in=0.05 out=0.2 from=this to=Ragdolls+0.6 | | |
| L5 | cuts/54_v21.mp4@0.35:2.72,cuts/55_v21.mp4@0.8:1.2,cuts/55_v21.mp4@3.7:2.4 | | | line | | these are pretty janky, but im keeping it that way, because it doesnt effect gameplay, and i think makes it more entertaining | | | |
| L6 | cuts/48_v20.mp4@1.1:1.6,cuts/52_v20.mp4@2.05 | | | line | | Once i had this, i wanted to use it more. Now when you shove someone, they also ragdoll. | | | |
| L7 | cuts/49_v20.mp4 | 0.4 | | line | | And when you reach the tower, you can shove the guard out, and watch them go flying into the pit. | | | |
| end | title | | 1.75 | | | beta signup in bio | | | |

## 57
said: pov of the sniper shooting at some runners and missing, hell map, right at the end, they hit one, and we cut a little after the animation plays out -- v23 L1: ## 43 retaped on the current build (v22's L1 was filmed on the old branch state, old characters); rs_snipe: two misses (2.25, 3.95), then the hit (5.65) plays the old Death clip, held 1.75 s
capture: --shot=s3_open_lane --stage=rs_snipe --pov=guard --bots=3 --seed=20261017 --shimmer=0 --set=old=1;plan=0m,1m,2h;start=1.0
hud: crosshair
expect: hit Runner_3 5.55-5.75; lens_clear; lens_cover <= 0.5
seconds: 5
in: 2.6
motion: 0.005
freeze: 1
refilm: v23

## 58
# v23 L2 (fix_L2.md), filmed as cuts/02_v23.mp4
said: shot of the animation in a grey space jsut playing, with a slow fade in of an image i will provide https://media.tenor.com/17aPeH713cYAAAAM/scared.gif -- Ryan on v22: "when you show the death animation in a grey void, why the fuck is the character rendered how it is in game???"; "if my art didnt make it clear, it should be an older build of the game to show the even worse art"
build: ragdoll-old-era-0fe0c9ec (0fe0c9ec, 2026-09-11, "runner: authored Jump, Death and Aim clips": the first Death clip, 24 days before the ragdoll 06bdee8f; c4943a47 is the pill greybox with no character or Death clip, so not used). The branch adds only tools/capture/run_clip.gd + lens_probe.gd.
stage: death_void (era run_clip): the old 544-tri runner.glb in its shipped unshaded orange, alone in a grey void (no map, a shadow-only floor, the sun); lens 4.6 m off, 1.0 m up, fov 40; he faces 35 deg off it; at 1.62 s the old Death clip plays once (about 0.8 s) and he lies there
capture: --shot=s3_open_lane --stage=death_void --bots=1 --seed=20261017 --shimmer=0
ref: ragdoll-old-era-0fe0c9ec
tape: none (one prisoner, no brain: the same take every run)
expect: death Runner_1 1.5-1.7; lens_clear
seconds: 3.6
in: 1.2
motion: 0.002
freeze: waive
brief: tools/content/projects/ragdoll_short/sv3/ragdoll_short_old.md ## 2 (shot.sh under its own name; PC checkout C:\dev\worktrees\content_ragdoll_short_old, removed)
cut: content\ragdoll_short\cuts\02_v23.mp4 (3.60 s, 1080x1920; Mac copy at sv3/cuts/02_v23.mp4); Mac smoke death 1.62; PC take: death 1.62, gate waived (orange and the grey are the same luma, so the motion gate reads 0.0000)
frames: 0.0-0.4 he stands square-on, a flat orange silhouette on flat grey (no shading, as the old build drew a runner); 0.4-1.1 the old Death clip: he pitches forward and to the side, catches himself on stiff arms and flattens onto his front; 1.1-3.6 he lies still, the gif fades in over this

## 59
# v23 L3 (fix_L3.md), filmed as cuts/03_v23.mp4
said: slow zoom out shot of the old hell map -- Ryan on v22: "if my art didnt make it clear, it should be an older build of the game to show the even worse art"
build: ragdoll-old-era-0fe0c9ec (0fe0c9ec, 2026-09-11, the same build as L2): the old hell ring (map_base.glb deck annulus, lava tiles, spires, torches, the old rock tower with the floating eye), its own shipped dark red lighting
stage: hell_pullback (era run_clip, v22's numbers): a live 3-runner bot match (prisoner_count pinned 3 in memory; the human body parked and hidden; no HUD); the lens opens close on the tower (deg 0, r 14, 6 m up, fov 45) and pulls straight back and up over 8 s (1.0-9.0) to deg 0, r 36, 34 m up, fov 70
capture: --shot=pit_orbit --stage=hell_pullback --bots=3 --seed=20261017 --shimmer=0
ref: ragdoll-old-era-0fe0c9ec
tape: none (the lens is scripted; the bots are only background)
expect: pullback start 0.9-1.1; pullback end 8.9-9.1; lens_clear; lens_cover <= 0.5
seconds: 8.2
in: 1.0
motion: 0.01
brief: tools/content/projects/ragdoll_short/sv3/ragdoll_short_old.md ## 3
cut: content\ragdoll_short\cuts\03_v23.mp4 (8.20 s, 1080x1920; Mac copy at sv3/cuts/03_v23.mp4); Mac smoke pullback 1.00/9.00, lens near 1.50 cover 0.00 throughout; PC take motion 0.0129, freeze 0 (two earlier takes failed: this build pushed the PC's saved window settings over the capture window; the era run_clip now builds the settings store without that)
frames: 0.0-1.5 close on the old tower chamber's square openings (flat red-lit boxes, checker-dark interior); 1.5-4.0 the lens rises and backs off, the chamber drops down the frame and the floating red eye rises into view over the tower top; 4.0-8.2 the whole old tower and eye shrink in the middle of the frame, the dark ring wall with its torch flames and spires around it; the runners stay off frame (as in v22's crane)

## 60
# v23 L4 sniper half (fix_L4 ## 57), cuts/04a_v23.mp4
said: a sniper pov, missing shots, then cut to the runner pov near the end, and he watches the person in front of him get shot -- v23 L4, the sniper half (Ryan on v22: "like holy shit use s2"): hell_explainer follow, one tape with the runner half; the scope puts a round by the lead (lands 2.83) and one by the back man (4.23); the cut ends 5.0, before the lead runs behind the 066 lip rock
capture: --shot=s3_open_lane --stage=hell_explainer --pov=guard --bots=3 --shimmer=0 --look=social --rifle=projectile --seed=20261017 --set=start=31,22,0;follow=4.5;pace=0.5;follow_pace=0.535;miss_lead=2.4;miss_mid=3.8;drop_at=8.67;hold_to=11;pull_up=-0.1;watch=2.0;watch_h=1.0
tape: ragdoll_short_L4_v23
hud: crosshair
expect: hit MapBaseS1Collision 2.73-2.93; alive Runner_1; alive Runner_3; lens_clear; lens_cover <= 0.5
seconds: 3.4
in: 1.6
motion: 0.012

## 61
# v23 L4 runner half (fix_L4 ## 58), cuts/04b_v23.mp4; joined cuts/04_v23.mp4
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

## 62
# v23 L5 (fix_L5 ## 57), cuts/05_v23.mp4
said: clip montage of the sniper hitting people dead in hell, and if we can, get one that freaks out and break the players model and go flying -- Ryan 10-12: "lets replace the gameplay of the hitting shots montage to be in the forest"; Ryan 10-17: "didnt i say it has to be in the forest?"; on v22: "in the forest shots, you do not see a single successful ragdoll, and a fucking player shoaves another one for no reason" -- forest_ragdolls: a fixed ground lens on the forest lane (59 deg r 50.2, 1.5 m up, fov 40) looking back up it at 52.3 deg r 51.9, the 54 deg rock outside the frame; three runners come down the lane one after another and the guard at the 32 deg window drops each with a projectile round 8.1-8.3 m off the lens (hits 3.08, 4.92, 6.86); each goes limp and tumbles toward the lens, lying 6.0-6.4 m off it, clear ray every 0.25 s of the 1.5 s after; no shoves (bot shoves off). Mac smoke: as listed.
capture: --map=forest --shot=s3_open_lane --stage=forest_ragdolls --bots=3 --rifle=projectile --shimmer=0 --look=social --seed=20261017
tape: forest_ragdolls_v23c
expect: hit Runner_1 3.0-3.2; in_frame Runner_1 +0.0-0.05; hit Runner_2 +1.75-1.95; in_frame Runner_2 +1.75-1.95; hit Runner_3 +3.7-3.9; in_frame Runner_3 +3.7-3.9; lens_clear; lens_cover <= 0.5
seconds: 7.8
in: 1.2
motion: 0.005

cut: cuts/05_v23.mp4 (PC content\ragdoll_short\cuts, 7.8 s, 1080x1920; PC take hits 3.07, 4.90, 6.85 = cut 1.87, 3.70, 5.65)
frames: one continuous fixed lens, the forest lane. Cut 1.0-1.9: teal runner jogs down the lane toward the lens; 1.87 the round drops him, he buckles, arms out, and tumbles forward onto his face, limp, legs kicked up (1.9-3.0), and lies there. 2.9-3.7: green runner runs down past him; 3.70 dropped, folds and pitches over onto the teal body (a pile). 4.4-5.6: blue runner comes down; 5.65 dropped mid-stride, legs splayed, flops onto the pile, a leg left sticking up (5.7-7.4). No shoves, no HUD. 7.6 on: a ghost of the first man re-enters (the game's catch-and-swap): keep out.
table row (L5, replaces v22's 54/55 parts): | L5 | cuts/05_v23.mp4@1.0:6.45 | | | line | | these are pretty janky, but im keeping it that way, because it doesnt effect gameplay, and i think makes it more entertaining | | | |

## 63
# v23 L6 third-person half (fix_L6 ## 161), cuts/06a_v23.mp4
said: L6 (v23, Ryan on v22: "theres a sub one second clip of a bunch of player shoving each other, doesnt show ragdolling, looks like shit"): a bunch of runners shoving each other with the ragdoll, other pov shots of a "real game" where the runners are getting shoved -- the third-person half: shove_flop, a 3-runner hell round on the clear S3-S4 deck (pads and traps off, 4 players with the guard); Runner_2 runs Runner_1 down and shoves him up the lane (1.52 s, 194.2 deg r 51.9); he goes limp in the air and tumbles (the shipped 16/7 shove and flop), lands (2.18), gets up and runs on; a side dolly on the deck 3.5 m outboard, 1.5 m up (fov 62), the pit, tower and eye behind, rides the pair, then him, his whole body in the 9:16 frame from the shove to +1.9 s
capture: --shot=s3_open_lane --stage=shove_flop --bots=3 --seed=20261017 --shimmer=0 --set=pack=3;from=186
tape: rs_flop_side
expect: shove Runner_2 1.45-1.6; in_frame Runner_1 +0.0-0.05; held_in_frame Runner_1 +1.8-2.0; alive Runner_1; lens_clear; lens_cover <= 0.5
seconds: 2.6
in: 0.95
frames: 0.0-0.5 the shover closes on him from behind, both running left to right, the pit, tower and eye behind; 0.57 the shove; 0.7-1.7 he is limp in the air, body flat and tumbling past the pit-side rocks; 1.8 lands, gets up; 1.9-2.3 runs on.
cut: content\ragdoll_short\cuts\06a_v23.mp4 (2.6 s, PC take 161_t1, motion 0.1307, freeze 0)

## 64
# v23 L6 POV half (fix_L6 ## 162), cuts/06b_v23.mp4; joined cuts/06_v23.mp4
said: L6 (v23), the runner-POV half: a bunch of runners shoving each other with the ragdoll, other pov shots of a "real game" where the runners are getting shoved -- shove_flop down the shover's eyes, a 3-runner hell round further back on the same deck; the POV runs Runner_1 down and shoves him straight up the lane (1.52 s, 189.2 deg r 51.9; the POV's own arms push out), the eyes stay on him as he flies limp and tumbles ahead, lands (2.18) sprawled, gets up and runs off; in frame from the shove to +1.9 s
capture: --shot=s3_open_lane --stage=shove_flop --pov=runner --bots=3 --seed=20261017 --shimmer=0 --set=pack=3;from=181
tape: rs_flop_pov
expect: shove Runner_2 1.45-1.6; in_frame Runner_1 +0.0-0.05; held_in_frame Runner_1 +1.8-2.0; alive Runner_1; lens_clear; lens_cover <= 0.5
seconds: 2.8
in: 0.9
frames: 0.0-0.6 running up behind him on the lava-cracked deck, he grows in frame; 0.62 the shove (arms out); 0.7-1.2 he flies limp ahead; 1.2-1.7 sprawled, tumbling on the ground; 1.7-2.0 gets up; 2.0-2.55 runs off up the lane, small.
cut: content\ragdoll_short\cuts\06b_v23.mp4 (2.8 s, PC take 162_t1, motion 0.1322, freeze 0)

joined: content\ragdoll_short\cuts\06_v23.mp4 (4.85 s, 291 frames, lossless libx264rgb): 0-2.3 = 161 (shove 0.55 on "this", flop through "wanted to use it more"), 2.3-4.85 = 162 (cut on "Now", shove 2.9 on "shove", limp and sprawled through "someone, they also", up on "ragdoll").

## 65
# v23 L7 (fix_L7 ## 57), cuts/07_v23.mp4
said: L7 (v23, Ryan on v22: "the gaurd clips into the fucking pit wall lke we specifcally specified not to. and then cuts to a sniper pov for no fucking reason"): pov runner makes it through the portal, shoves, and the usual cinematic shot -- finale: the run into the portal, the arrival (2.13), the walk up and the shove (3.67), and the game's kill-beat cinematic held 3.2 s so the cut ends on it, never back on the POV in the tower. The guard posted 4.5 m out (at his window) and the throw at shove_impulse 11.5 (the finale doubles it): Mac trace clears the window sill (no tower contact) and he drops into the pit 30+ m out, 11+ m short of the pit wall (r 46.3) when the cut ends; at the shipped 16 he hit the wall at 1.6 s, below 11 the sill caught him.
capture: --shot=s3_open_lane --stage=finale --pov=runner --bots=3 --shimmer=0 --seed=20261012 --set=lead=6.0;stand=4.5;pace=0.45;beat=3.2;throw=11.5
tape: finale_l7_v23
expect: shove Runner_0 3.52-3.82; arrive Runner_1 2.0-2.25; tower_out Runner_0 +3.1-3.3; alive Runner_1; lens_clear; lens_cover <= 0.5
seconds: 5.4
in: 1.3
frames: cut 0.0-0.6 the run into the portal; 0.83 through; 0.9-2.3 the tower room, the guard posted at the far window, the POV walks up (he grows in frame); 2.37 the shove (the POV's arms out); 2.5-5.4 the game's kill-beat cinematic: he leaves through the window clean (no tower contact), drops down the pit in front of the far lava falls, the lava sea rising under him; the cut ends on him still falling, 11+ m off the pit wall. No POV/sniper frame after the shove (the beat ends at take 6.87, the cut at 6.7).
cut: content\ragdoll_short\cuts\07_v23.mp4 (5.4 s, PC take 07_v23, motion 0.2046, freeze 0)

## script v23
from: v22
notes: for when i say if my art didnt make it clear, it should be an older build of the game to show the even worse art. when you show the death animation in a grey void, why the fuck is the character rendered how it is in game??? and why the fucking hell, woudl you choose, for the moment when i say ragdolls and youre supposed to watch someone get shot, for that to be on the bounce pad section of the map? like holy shit use s2. then, in the forest shots, you do not see a single successful ragdoll, and a fucking player shoaves another one for no reason. then theres a sub one second clip of a bunch of player shoving each other, doesnt show ragdolling, looks like shit. the gaurd clips into the fucking pit wall lke we specifcally specified not to. and then cuts to a sniper pov for no fucking reason. is all of this clear? do you know how to fix it all? frankly i will say it is much much better for a first draft than we had been getting, but not good enough still
# v23 = v22 with Ryan's notes: L1 = 57 (## 43 retaped on the current build); M2 = 02_v23, L3 = 03_v23 (the 0fe0c9ec old build:
# old runner, old Death clip, old hell ring); L4 = 04_v23 (scope misses, then the back runner as the lead is shot on S2);
# L5 = 05_v23 (forest, three visible ragdolls, no shoves); L6 = 06_v23 (two shove-and-flop halves); L7 = 07_v23 (clean throw, ends on the beat).
# was: v22 = v21 with L5's haters part ending before the guard's re-seat (the HUD's tower banner showed for 0.15 s at v21's 28.85 s); v21 = v20 after its frame check (never shown to Ryan): L3, L4's runner half and L5 refilmed; v20's table, rows composed by hand where a line needs more than one shot (task #630, short 4 from scratch):
# L1 the second miss and the hit with the old Death clip just after "bad", held 1.75 s past the hit; M2 the grey void
# death, scared.gif fading in from 1.2 s over 2.0 s (the beat ends with the fade); L3 the crane-out; L4 the scope's two
# misses (46), then the back runner (50) as the lead ahead drops on "Ragdolls", the placeholder comment card at "this guy";
# L5 forest: the flung lead and the middle man (54), the haters scope's drop, ravine throw and drop (55); frame check: L3 = 53 (45 read as a push in), L4 runner = 56 (50's lead left the frame); L6 the 3-runner scrap (48), then the
# POV's pit shove on "shove" (52); L7 the portal, the shove and the 2.0 s kill-beat cinematic (49). "htis" spoken "this".
pad: 0.2
| line | clip | in | len | fit | speed | text | card | grade | gif_fade |
| L1 | cuts/57_v23.mp4 | 0.3 | 4.5 | wait | | The death animation in my game was really bad. | | | |
| M2 | cuts/02_v23.mp4 | 0 | 3.6 | beat 3.6 | | | | | external/scared.gif 1.2 2.0 end |
| L3 | cuts/03_v23.mp4 | 1.5 | 6.7 | line | | Yeaeeeeeeeh I needed something better, but if my art didnt make it clear, I'm a programmer, not an animator | | | |
| L4 | cuts/04_v23.mp4 | 0 | 9.5 | wait | | Luckily my solution actually came from you guys, in an earlier short when i asked for suggestions, this guy gave me the exact solution to my problem? Ragdolls | cards/L4_card0.png w=940 y=0.2 in=0.05 out=0.2 from=this to=Ragdolls+0.6 | | |
| L5 | cuts/05_v23.mp4@1.0:6.45 | | | line | | these are pretty janky, but im keeping it that way, because it doesnt effect gameplay, and i think makes it more entertaining | | | |
| L6 | cuts/06_v23.mp4 | 0 | 4.85 | line | | Once i had this, i wanted to use it more. Now when you shove someone, they also ragdoll. | | | |
| L7 | cuts/07_v23.mp4 | 0 | | line | | And when you reach the tower, you can shove the guard out, and watch them go flying into the pit. | | | |
| end | title | | 1.75 | | | beta signup in bio | | | |

## 66
# v24 L2 (fix_L2.md), filmed as cuts/02_v24.mp4
said: shot of the animation in a grey space jsut playing, with a slow fade in of an image i will provide https://media.tenor.com/17aPeH713cYAAAAM/scared.gif -- Ryan on v23: "seriously is the fucking random ass fucking orange box in the death animation a joke?"
build: ragdoll-old-era-3a8cefd3 (f49c03c3 on 3a8cefd3, 2026-10-05, "Forest green: shade 30% darker": the parent of 06bdee8f "Death ragdoll", so the last commit with the authored Death clip and no ragdoll; the runner is prisoner2.glb, the modelled prisoner). v23's 0fe0c9ec drew the 544-tri runner as an orange box. The branch adds only tools/capture/run_clip.gd (death_void only) + lens_probe.gd.
stage: death_void: the prisoner alone in a grey void (no map, a shadow-only floor, the sun); lens 5.5 m off, 1.0 m up, fov 40, looking at 1.38 m so he lies in the bottom quarter, below the full-width scared.gif band (y 655-1265 of 1920); he faces 35 deg off it; at 1.62 s that build's Death clip plays once and he lies there
capture: --shot=s3_open_lane --stage=death_void --bots=1 --seed=20261017 --shimmer=0 --dist=5.5 --look_h=1.38
ref: ragdoll-old-era-3a8cefd3
tape: none (one prisoner, no brain: the same take every run)
expect: death Runner_1 1.5-1.7; lens_clear
seconds: 3.6
in: 1.2
motion: 0.002
freeze: waive
brief: tools/content/projects/ragdoll_short/sv3/ragdoll_short_old.md ## 2 (shot.sh --name 02_v24 under its own name; PC checkout C:\dev\worktrees\content_ragdoll_short_old)
cut: content\ragdoll_short\cuts\02_v24.mp4 (3.60 s, 1080x1920; Mac copy at sv3/cuts/02_v24.mp4); Mac smoke death 1.62; PC take: death 1.62, motion 0.0081, gate waived by the brief
table row (v23's M2 repointed, scared.gif fade kept): | M2 | cuts/02_v24.mp4 | 0 | 3.6 | beat 3.6 | | | | | external/scared.gif 1.2 2.0 end |
frames: 0.0-0.4 the prisoner stands, white shirt, jeans, bare skin, head tipped up; 0.4-1.0 the Death clip: he buckles at the waist and pitches forward onto his hands and knees, face down; 1.0-3.6 he lies still in that heap at y 1440-1830, the gif fades in above him from 1.2 s

## 67
# v24 L4 sniper half (fix_L4 ## 66), cuts/04a_v24m
said: a sniper pov, missing shots, then cut to the runner pov near the end, and he watches the person in front of him get shot -- v24 L4, the sniper half (Ryan on v23: "when i say ragdolls, he just drops, he doesnt get shot"): hell_explainer follow on S2, one tape with ## 67; the scope puts a round by the lead (lands 2.78) and one by the middle man (4.20); the cut ends 5.0, before the lead runs behind the 066 lip rock
capture: --shot=s3_open_lane --stage=hell_explainer --pov=guard --bots=3 --shimmer=0 --look=social --rifle=projectile --seed=20261017 --set=start=31,22,0;follow=4.5;pace=0.5;follow_pace=0.535;pov_r=48.9;fling=550;carry=0.3;watch_limp=1;miss_lead=2.4;miss_mid=3.8;drop_at=8.67;hold_to=11;pull_up=-0.1;watch=2.0;watch_h=1.0
tape: ragdoll_short_L4_v24
hud: crosshair
expect: hit MapBaseS1Collision 2.68-2.88; alive Runner_1; alive Runner_3; lens_clear; lens_cover <= 0.5
seconds: 3.4
in: 1.6
motion: 0.012

## 68
# v24 L4 runner half (fix_L4 ## 67), cuts/04b_v24m; joined cuts/04_v24.mp4
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

## 69
# v24 L6 POV half (fix_L6 ## 166), cuts/06b_v24.mp4; joined cuts/06_v24.mp4
said: L6 (v24, Ryan on v23: "the shove off into the pit changed to a shove just generically, and it looks bad. should be a shove into the pit."): a bunch of runners shoving each other with the ragdoll, other pov shots of a "real game" where the runners are getting shoved -- the runner-POV half: rs_pitshove (## 52's numbers) on the fixed ragdoll (f0b18e2c), the POV runner (Runner_2) runs down the man on the inside and shoves him over the rim into the pit (4.20 s, 49.2 deg r 48.8), stops at 57 deg and watches him fall (in the pit 6.28)
capture: --shot=s3_open_lane --stage=rs_pitshove --pov=runner --bots=3 --seed=7 --shimmer=0 --set=pack=3;shove_gap=1.3;turn_gap=2.6;shover_r=50.2;from=13;back=8.5;after_to=57
tape: rs_pitshove_v24
expect: shove Runner_2 4.1-4.3; out Runner_1 +2.0-2.2; lens_clear; lens_cover <= 0.5
seconds: 6.4
in: 1.0
frames: 0.0-2.9 running down the rim lane behind him, the pit on the right; 2.95 the POV's arms shove him; 3.0-3.4 he flies limp off the rim over the pit; 3.4-3.8 falls past the tower base into the lava; 3.8-6.4 the POV holds on the pit, tower and eye.
cut: content\ragdoll_short\cuts\06b_v24.mp4 (6.4 s, PC take 166_t1, motion 0.0473, freeze 0)
refilm: v35 (Ryan 20:50: "it has sone lag"): two rough takes still froze 4-23 frames mid-run; filmed --movie as cuts\06b_v35m.mp4 (Movie Maker, 1080x1920, motion 0.0464, no frozen frame in 0-4.7 s)

joined: content\ragdoll_short\cuts\06_v24.mp4 (4.85 s, 291 frames, lossless libx264rgb; Mac copy sv3/cuts/06_v24.mp4) = 06a_v23 (## 63, the third-person shove-and-flop) [0.0167-1.8167] + 06b_v24 [2.75-5.80]: 0-1.8 the side shove and flop (shove 0.55, limp in the air, lands), 1.8 cut to the POV on the lane, 3.0 the shove on "shove", 3.0-4.0 he flies off the rim and falls into the pit through "someone, they also", 4.0-4.85 the pit, tower and eye on "ragdoll".

## 70
# v24 L7 (fix_L7 ## 167), cuts/07_v24.mp4
said: L7 (v24, Ryan on v23: "when the gaurd is hoved, they freak out"): pov runner makes it through the portal, shoves, and the usual cinematic shot -- finale with fix_L7 v23's numbers on the fixed ragdoll: the run into the portal, the arrival (2.13), the walk up and the shove (3.67), the kill-beat cinematic held 3.2 s so the cut ends on it; the guard flips over the window sill and tumbles out as one limp body, spread out, down into the pit short of the pit wall
capture: --shot=s3_open_lane --stage=finale --pov=runner --bots=3 --shimmer=0 --seed=20261012 --set=lead=6.0;stand=4.5;pace=0.45;beat=3.2;throw=11.5
tape: finale_l7_v24
expect: shove Runner_0 3.52-3.82; arrive Runner_1 2.0-2.25; tower_out Runner_0 +3.1-3.3; alive Runner_1; lens_clear; lens_cover <= 0.5
seconds: 5.4
in: 1.3
frames: cut 0.0-0.8 the run into the portal; 0.9-2.3 the tower room, the guard at the far window, the POV walks up; ~2.45 the shove (the POV's arms out); 2.6-5.4 the game's kill-beat cinematic: he goes over the sill legs-up, turns flat and tumbles slowly spread-eagle down past the far lava falls onto the lava sea; the cut ends on him still falling, no POV/sniper frame after the shove.
cut: content\ragdoll_short\cuts\07_v24.mp4 (5.4 s, PC take 167_t1, motion 0.2019, freeze 0; Mac copy sv3/cuts/07_v24.mp4)

## 71
# v26 M2 (fix_L2 v25 -> v26), cuts/02_v26.mp4
said: Ryan on v25: "the death animation on the grey background is using a weird fucking model of the character. the old in game one with a bunch of filters on it" -- death_void on today's build: today's prisoner2 playing the authored Death clip (ragdoll off), materials sampled linear with no mipmaps at full texture size, plainly lit in the grey void; framing as 02_v24 (lens 5.5 m, 1.0 m up, fov 40, look_h 1.38)
capture: --shot=s3_open_lane --stage=death_void --bots=1 --seed=20261017 --shimmer=0 --set=dist=5.5;look_h=1.38
expect: death Runner_1 1.5-1.7; lens_clear
seconds: 3.6
in: 1.2
motion: 0.002
freeze: waive

## 72
# v27 M2 (fix_L2 v26 -> v27), cuts/02_v27h.mp4
said: Ryan on v26: "the death animation, in the gray space, is still fucking shit, becuase the model is blood red like they are in hell" -- death_void with the map's character fit undone on him (authored materials, no red fill, white sun, grey ambient): his own skin, shirt and jeans; framing as 02_v26
capture: --shot=s3_open_lane --stage=death_void --bots=1 --seed=20261017 --shimmer=0 --set=dist=5.5;look_h=1.38
expect: death Runner_1 1.5-1.7; lens_clear
seconds: 3.6
in: 1.2
motion: 0.002
freeze: waive

## script v24
from: v23
notes: seriously is the fucking random ass fucking orange box in the death animation a joke? when i say ragdolls, he just drops, he doesnt get shot. when the gaurd is hoved, they freak out, and the shove off into the pit changed to a shove just generically, and it looks bad. should be a shove into the pit. for the shove one, the gameplay of the shove minigame is super weird because of the way the bots behave, and its unclear thats whats happening. change the minigame so instead of everyone facing away, everyone starts closer to the edge facing in. that can be an actual gameplay change. then record that instead
notes: for when i say if my art didnt make it clear, it should be an older build of the game to show the even worse art. when you show the death animation in a grey void, why the fuck is the character rendered how it is in game??? and why the fucking hell, woudl you choose, for the moment when i say ragdolls and youre supposed to watch someone get shot, for that to be on the bounce pad section of the map? like holy shit use s2. then, in the forest shots, you do not see a single successful ragdoll, and a fucking player shoaves another one for no reason. then theres a sub one second clip of a bunch of player shoving each other, doesnt show ragdolling, looks like shit. the gaurd clips into the fucking pit wall lke we specifcally specified not to. and then cuts to a sniper pov for no fucking reason. is all of this clear? do you know how to fix it all? frankly i will say it is much much better for a first draft than we had been getting, but not good enough still
# v24 = v23 with Ryan's notes: M2 = 02_v24 (3a8cefd3: the modelled prisoner and its Death clip, no box); L4 = 04_v24 (the lead visibly shot and
# thrown on S2, the report and impact in the take's sound, game: 2 = the take's own level under the voice); L6 = 06_v24 (the flop, then the POV shove into the pit); L7 = 07_v24 (fixed ragdoll, one tumble).
# was: v23 = v22 with Ryan's notes: L1 = 57 (## 43 retaped on the current build); M2 = 02_v23, L3 = 03_v23 (the 0fe0c9ec old build:
# old runner, old Death clip, old hell ring); L4 = 04_v23 (scope misses, then the back runner as the lead is shot on S2);
# L5 = 05_v23 (forest, three visible ragdolls, no shoves); L6 = 06_v23 (two shove-and-flop halves); L7 = 07_v23 (clean throw, ends on the beat).
# was: v22 = v21 with L5's haters part ending before the guard's re-seat (the HUD's tower banner showed for 0.15 s at v21's 28.85 s); v21 = v20 after its frame check (never shown to Ryan): L3, L4's runner half and L5 refilmed; v20's table, rows composed by hand where a line needs more than one shot (task #630, short 4 from scratch):
# L1 the second miss and the hit with the old Death clip just after "bad", held 1.75 s past the hit; M2 the grey void
# death, scared.gif fading in from 1.2 s over 2.0 s (the beat ends with the fade); L3 the crane-out; L4 the scope's two
# misses (46), then the back runner (50) as the lead ahead drops on "Ragdolls", the placeholder comment card at "this guy";
# L5 forest: the flung lead and the middle man (54), the haters scope's drop, ravine throw and drop (55); frame check: L3 = 53 (45 read as a push in), L4 runner = 56 (50's lead left the frame); L6 the 3-runner scrap (48), then the
# POV's pit shove on "shove" (52); L7 the portal, the shove and the 2.0 s kill-beat cinematic (49). "htis" spoken "this".
pad: 0.2
game: 2
| line | clip | in | len | fit | speed | text | card | grade | gif_fade |
| L1 | cuts/57_v23.mp4 | 0.3 | 4.5 | wait | | The death animation in my game was really bad. | | | |
| M2 | cuts/02_v24.mp4 | 0 | 3.6 | beat 3.6 | | | | | external/scared.gif 1.2 2.0 end |
| L3 | cuts/03_v23.mp4 | 1.5 | 6.7 | line | | Yeaeeeeeeeh I needed something better, but if my art didnt make it clear, I'm a programmer, not an animator | | | |
| L4 | cuts/04_v24.mp4 | 0 | 9.5 | wait | | Luckily my solution actually came from you guys, in an earlier short when i asked for suggestions, this guy gave me the exact solution to my problem? Ragdolls | cards/L4_card0.png w=940 y=0.2 in=0.05 out=0.2 from=this to=Ragdolls+0.6 | | |
| L5 | cuts/05_v23.mp4@1.0:6.45 | | | line | | these are pretty janky, but im keeping it that way, because it doesnt effect gameplay, and i think makes it more entertaining | | | |
| L6 | cuts/06_v24.mp4 | 0 | 4.85 | line | | Once i had this, i wanted to use it more. Now when you shove someone, they also ragdoll. | | | |
| L7 | cuts/07_v24.mp4 | 0 | | line | | And when you reach the tower, you can shove the guard out, and watch them go flying into the pit. | | | |
| end | title | | 1.75 | | | beta signup in bio | | | |

## script v25
from: v24
notes: seriously is the fucking random ass fucking orange box in the death animation a joke? when i say ragdolls, he just drops, he doesnt get shot. when the gaurd is hoved, they freak out, and the shove off into the pit changed to a shove just generically, and it looks bad. should be a shove into the pit. for the shove one, the gameplay of the shove minigame is super weird because of the way the bots behave, and its unclear thats whats happening. change the minigame so instead of everyone facing away, everyone starts closer to the edge facing in. that can be an actual gameplay change. then record that instead
notes: for when i say if my art didnt make it clear, it should be an older build of the game to show the even worse art. when you show the death animation in a grey void, why the fuck is the character rendered how it is in game??? and why the fucking hell, woudl you choose, for the moment when i say ragdolls and youre supposed to watch someone get shot, for that to be on the bounce pad section of the map? like holy shit use s2. then, in the forest shots, you do not see a single successful ragdoll, and a fucking player shoaves another one for no reason. then theres a sub one second clip of a bunch of player shoving each other, doesnt show ragdolling, looks like shit. the gaurd clips into the fucking pit wall lke we specifcally specified not to. and then cuts to a sniper pov for no fucking reason. is all of this clear? do you know how to fix it all? frankly i will say it is much much better for a first draft than we had been getting, but not good enough still
# v25 = v24 with L6 only: the POV pit shove alone (06b_v24, shove on "shove", the fall and the empty pit under the rest); the generic deck shove cut (task #630).
# was: v24 = v23 with Ryan's notes: M2 = 02_v24 (3a8cefd3: the modelled prisoner and its Death clip, no box); L4 = 04_v24 (the lead visibly shot and
# thrown on S2, the report and impact in the take's sound, game: 2 = the take's own level under the voice); L6 = 06_v24 (the flop, then the POV shove into the pit); L7 = 07_v24 (fixed ragdoll, one tumble).
# was: v23 = v22 with Ryan's notes: L1 = 57 (## 43 retaped on the current build); M2 = 02_v23, L3 = 03_v23 (the 0fe0c9ec old build:
# old runner, old Death clip, old hell ring); L4 = 04_v23 (scope misses, then the back runner as the lead is shot on S2);
# L5 = 05_v23 (forest, three visible ragdolls, no shoves); L6 = 06_v23 (two shove-and-flop halves); L7 = 07_v23 (clean throw, ends on the beat).
# was: v22 = v21 with L5's haters part ending before the guard's re-seat (the HUD's tower banner showed for 0.15 s at v21's 28.85 s); v21 = v20 after its frame check (never shown to Ryan): L3, L4's runner half and L5 refilmed; v20's table, rows composed by hand where a line needs more than one shot (task #630, short 4 from scratch):
# L1 the second miss and the hit with the old Death clip just after "bad", held 1.75 s past the hit; M2 the grey void
# death, scared.gif fading in from 1.2 s over 2.0 s (the beat ends with the fade); L3 the crane-out; L4 the scope's two
# misses (46), then the back runner (50) as the lead ahead drops on "Ragdolls", the placeholder comment card at "this guy";
# L5 forest: the flung lead and the middle man (54), the haters scope's drop, ravine throw and drop (55); frame check: L3 = 53 (45 read as a push in), L4 runner = 56 (50's lead left the frame); L6 the 3-runner scrap (48), then the
# POV's pit shove on "shove" (52); L7 the portal, the shove and the 2.0 s kill-beat cinematic (49). "htis" spoken "this".
pad: 0.2
game: 2
| line | clip | in | len | fit | speed | text | card | grade | gif_fade |
| L1 | cuts/57_v23.mp4 | 0.3 | 4.5 | wait | | The death animation in my game was really bad. | | | |
| M2 | cuts/02_v24.mp4 | 0 | 3.6 | beat 3.6 | | | | | external/scared.gif 1.2 2.0 end |
| L3 | cuts/03_v23.mp4 | 1.5 | 6.7 | line | | Yeaeeeeeeeh I needed something better, but if my art didnt make it clear, I'm a programmer, not an animator | | | |
| L4 | cuts/04_v24.mp4 | 0 | 9.5 | wait | | Luckily my solution actually came from you guys, in an earlier short when i asked for suggestions, this guy gave me the exact solution to my problem? Ragdolls | cards/L4_card0.png w=940 y=0.2 in=0.05 out=0.2 from=this to=Ragdolls+0.6 | | |
| L5 | cuts/05_v23.mp4@1.0:6.45 | | | line | | these are pretty janky, but im keeping it that way, because it doesnt effect gameplay, and i think makes it more entertaining | | | |
| L6 | cuts/06b_v24.mp4 | 1.25 | 4.85 | line | | Once i had this, i wanted to use it more. Now when you shove someone, they also ragdoll. | | | |
| L7 | cuts/07_v24.mp4 | 0 | | line | | And when you reach the tower, you can shove the guard out, and watch them go flying into the pit. | | | |
| end | title | | 1.75 | | | beta signup in bio | | | |

## script v26
from: v25
notes: holy fuck. seriously on the ragdoll? the death animation on the grey background is using a weird fucking model of the character. the onld in game one with a bunch of filters on it. it looks like the version of the character your supposed to see from 100 ft away when it gets low rezed. everything else is good. short 12 is good, 11 is still doesnt read right. short 9 is good, with the one acception that at the end, the very very end, the sniper sits looing at nothing for like a second
notes: seriously is the fucking random ass fucking orange box in the death animation a joke? when i say ragdolls, he just drops, he doesnt get shot. when the gaurd is hoved, they freak out, and the shove off into the pit changed to a shove just generically, and it looks bad. should be a shove into the pit. for the shove one, the gameplay of the shove minigame is super weird because of the way the bots behave, and its unclear thats whats happening. change the minigame so instead of everyone facing away, everyone starts closer to the edge facing in. that can be an actual gameplay change. then record that instead
notes: for when i say if my art didnt make it clear, it should be an older build of the game to show the even worse art. when you show the death animation in a grey void, why the fuck is the character rendered how it is in game??? and why the fucking hell, woudl you choose, for the moment when i say ragdolls and youre supposed to watch someone get shot, for that to be on the bounce pad section of the map? like holy shit use s2. then, in the forest shots, you do not see a single successful ragdoll, and a fucking player shoaves another one for no reason. then theres a sub one second clip of a bunch of player shoving each other, doesnt show ragdolling, looks like shit. the gaurd clips into the fucking pit wall lke we specifcally specified not to. and then cuts to a sniper pov for no fucking reason. is all of this clear? do you know how to fix it all? frankly i will say it is much much better for a first draft than we had been getting, but not good enough still
# v26 = v25 with M2 only: 02_v26, today's prisoner and its Death clip, crisp textures (task #630).
# was: v25 = v24 with L6 only: the POV pit shove alone (06b_v24, shove on "shove", the fall and the empty pit under the rest); the generic deck shove cut (task #630).
# was: v24 = v23 with Ryan's notes: M2 = 02_v24 (3a8cefd3: the modelled prisoner and its Death clip, no box); L4 = 04_v24 (the lead visibly shot and
# thrown on S2, the report and impact in the take's sound, game: 2 = the take's own level under the voice); L6 = 06_v24 (the flop, then the POV shove into the pit); L7 = 07_v24 (fixed ragdoll, one tumble).
# was: v23 = v22 with Ryan's notes: L1 = 57 (## 43 retaped on the current build); M2 = 02_v23, L3 = 03_v23 (the 0fe0c9ec old build:
# old runner, old Death clip, old hell ring); L4 = 04_v23 (scope misses, then the back runner as the lead is shot on S2);
# L5 = 05_v23 (forest, three visible ragdolls, no shoves); L6 = 06_v23 (two shove-and-flop halves); L7 = 07_v23 (clean throw, ends on the beat).
# was: v22 = v21 with L5's haters part ending before the guard's re-seat (the HUD's tower banner showed for 0.15 s at v21's 28.85 s); v21 = v20 after its frame check (never shown to Ryan): L3, L4's runner half and L5 refilmed; v20's table, rows composed by hand where a line needs more than one shot (task #630, short 4 from scratch):
# L1 the second miss and the hit with the old Death clip just after "bad", held 1.75 s past the hit; M2 the grey void
# death, scared.gif fading in from 1.2 s over 2.0 s (the beat ends with the fade); L3 the crane-out; L4 the scope's two
# misses (46), then the back runner (50) as the lead ahead drops on "Ragdolls", the placeholder comment card at "this guy";
# L5 forest: the flung lead and the middle man (54), the haters scope's drop, ravine throw and drop (55); frame check: L3 = 53 (45 read as a push in), L4 runner = 56 (50's lead left the frame); L6 the 3-runner scrap (48), then the
# POV's pit shove on "shove" (52); L7 the portal, the shove and the 2.0 s kill-beat cinematic (49). "htis" spoken "this".
pad: 0.2
game: 2
| line | clip | in | len | fit | speed | text | card | grade | gif_fade |
| L1 | cuts/57_v23.mp4 | 0.3 | 4.5 | wait | | The death animation in my game was really bad. | | | |
| M2 | cuts/02_v26.mp4 | 0 | 3.6 | beat 3.6 | | | | | external/scared.gif 1.2 2.0 end |
| L3 | cuts/03_v23.mp4 | 1.5 | 6.7 | line | | Yeaeeeeeeeh I needed something better, but if my art didnt make it clear, I'm a programmer, not an animator | | | |
| L4 | cuts/04_v24.mp4 | 0 | 9.5 | wait | | Luckily my solution actually came from you guys, in an earlier short when i asked for suggestions, this guy gave me the exact solution to my problem? Ragdolls | cards/L4_card0.png w=940 y=0.2 in=0.05 out=0.2 from=this to=Ragdolls+0.6 | | |
| L5 | cuts/05_v23.mp4@1.0:6.45 | | | line | | these are pretty janky, but im keeping it that way, because it doesnt effect gameplay, and i think makes it more entertaining | | | |
| L6 | cuts/06b_v24.mp4 | 1.25 | 4.85 | line | | Once i had this, i wanted to use it more. Now when you shove someone, they also ragdoll. | | | |
| L7 | cuts/07_v24.mp4 | 0 | | line | | And when you reach the tower, you can shove the guard out, and watch them go flying into the pit. | | | |
| end | title | | 1.75 | | | beta signup in bio | | | |

## script v27
from: v26
notes: for the minigame short, two things, one the host of the running in the forest is too long, and we need to break it up with a second shot. dealers choice. tow, the sniper keeps trcaking, but theyre not standing where a sniper would stand, and when they do shoot its through the column of the tower. the death animation, in the gray space, is still fucking shit, becuase the model is blood red like they are in he.l. you already did this one successfully i have no idea what youre problem is. other than that its good. what about short 11 and 12?
notes: holy fuck. seriously on the ragdoll? the death animation on the grey background is using a weird fucking model of the character. the onld in game one with a bunch of filters on it. it looks like the version of the character your supposed to see from 100 ft away when it gets low rezed. everything else is good. short 12 is good, 11 is still doesnt read right. short 9 is good, with the one acception that at the end, the very very end, the sniper sits looing at nothing for like a second
notes: seriously is the fucking random ass fucking orange box in the death animation a joke? when i say ragdolls, he just drops, he doesnt get shot. when the gaurd is hoved, they freak out, and the shove off into the pit changed to a shove just generically, and it looks bad. should be a shove into the pit. for the shove one, the gameplay of the shove minigame is super weird because of the way the bots behave, and its unclear thats whats happening. change the minigame so instead of everyone facing away, everyone starts closer to the edge facing in. that can be an actual gameplay change. then record that instead
notes: for when i say if my art didnt make it clear, it should be an older build of the game to show the even worse art. when you show the death animation in a grey void, why the fuck is the character rendered how it is in game??? and why the fucking hell, woudl you choose, for the moment when i say ragdolls and youre supposed to watch someone get shot, for that to be on the bounce pad section of the map? like holy shit use s2. then, in the forest shots, you do not see a single successful ragdoll, and a fucking player shoaves another one for no reason. then theres a sub one second clip of a bunch of player shoving each other, doesnt show ragdolling, looks like shit. the gaurd clips into the fucking pit wall lke we specifcally specified not to. and then cuts to a sniper pov for no fucking reason. is all of this clear? do you know how to fix it all? frankly i will say it is much much better for a first draft than we had been getting, but not good enough still
# v27 = v26 with M2 only: 02_v27, the void prisoner in his own colours, the map's fit undone (task #630).
# was: v26 = v25 with M2 only: 02_v26, today's prisoner and its Death clip, crisp textures (task #630).
# was: v25 = v24 with L6 only: the POV pit shove alone (06b_v24, shove on "shove", the fall and the empty pit under the rest); the generic deck shove cut (task #630).
# was: v24 = v23 with Ryan's notes: M2 = 02_v24 (3a8cefd3: the modelled prisoner and its Death clip, no box); L4 = 04_v24 (the lead visibly shot and
# thrown on S2, the report and impact in the take's sound, game: 2 = the take's own level under the voice); L6 = 06_v24 (the flop, then the POV shove into the pit); L7 = 07_v24 (fixed ragdoll, one tumble).
# was: v23 = v22 with Ryan's notes: L1 = 57 (## 43 retaped on the current build); M2 = 02_v23, L3 = 03_v23 (the 0fe0c9ec old build:
# old runner, old Death clip, old hell ring); L4 = 04_v23 (scope misses, then the back runner as the lead is shot on S2);
# L5 = 05_v23 (forest, three visible ragdolls, no shoves); L6 = 06_v23 (two shove-and-flop halves); L7 = 07_v23 (clean throw, ends on the beat).
# was: v22 = v21 with L5's haters part ending before the guard's re-seat (the HUD's tower banner showed for 0.15 s at v21's 28.85 s); v21 = v20 after its frame check (never shown to Ryan): L3, L4's runner half and L5 refilmed; v20's table, rows composed by hand where a line needs more than one shot (task #630, short 4 from scratch):
# L1 the second miss and the hit with the old Death clip just after "bad", held 1.75 s past the hit; M2 the grey void
# death, scared.gif fading in from 1.2 s over 2.0 s (the beat ends with the fade); L3 the crane-out; L4 the scope's two
# misses (46), then the back runner (50) as the lead ahead drops on "Ragdolls", the placeholder comment card at "this guy";
# L5 forest: the flung lead and the middle man (54), the haters scope's drop, ravine throw and drop (55); frame check: L3 = 53 (45 read as a push in), L4 runner = 56 (50's lead left the frame); L6 the 3-runner scrap (48), then the
# POV's pit shove on "shove" (52); L7 the portal, the shove and the 2.0 s kill-beat cinematic (49). "htis" spoken "this".
pad: 0.2
game: 2
| line | clip | in | len | fit | speed | text | card | grade | gif_fade |
| L1 | cuts/57_v23.mp4 | 0.3 | 4.5 | wait | | The death animation in my game was really bad. | | | |
| M2 | cuts/02_v27h.mp4 | 0 | 3.6 | beat 3.6 | | | | | external/scared.gif 1.2 2.0 end |
| L3 | cuts/03_v23.mp4 | 1.5 | 6.7 | line | | Yeaeeeeeeeh I needed something better, but if my art didnt make it clear, I'm a programmer, not an animator | | | |
| L4 | cuts/04_v24.mp4 | 0 | 9.5 | wait | | Luckily my solution actually came from you guys, in an earlier short when i asked for suggestions, this guy gave me the exact solution to my problem? Ragdolls | cards/L4_card0.png w=940 y=0.2 in=0.05 out=0.2 from=this to=Ragdolls+0.6 | | |
| L5 | cuts/05_v23.mp4@1.0:6.45 | | | line | | these are pretty janky, but im keeping it that way, because it doesnt effect gameplay, and i think makes it more entertaining | | | |
| L6 | cuts/06b_v24.mp4 | 1.25 | 4.85 | line | | Once i had this, i wanted to use it more. Now when you shove someone, they also ragdoll. | | | |
| L7 | cuts/07_v24.mp4 | 0 | | line | | And when you reach the tower, you can shove the guard out, and watch them go flying into the pit. | | | |
| end | title | | 1.75 | | | beta signup in bio | | | |

## script v28
from: v27
notes: for short 9. why the hell did anything change prior to the forest run. and for the fucking too boring forest section, you just added a fucking cut with the exact same footage with the fucking guys moved around? is that  fucking joke? this isnt a fucking pipeline issue what the fuck is wrong with you? and holy fuck, youre example of the bad death animation is now useing the fucking physics. literally just use, for only this one clip, the one i liked from the previous versions. other than that ists good. short 11 is good
notes: for the minigame short, two things, one the host of the running in the forest is too long, and we need to break it up with a second shot. dealers choice. tow, the sniper keeps trcaking, but theyre not standing where a sniper would stand, and when they do shoot its through the column of the tower. the death animation, in the gray space, is still fucking shit, becuase the model is blood red like they are in he.l. you already did this one successfully i have no idea what youre problem is. other than that its good. what about short 11 and 12?
notes: holy fuck. seriously on the ragdoll? the death animation on the grey background is using a weird fucking model of the character. the onld in game one with a bunch of filters on it. it looks like the version of the character your supposed to see from 100 ft away when it gets low rezed. everything else is good. short 12 is good, 11 is still doesnt read right. short 9 is good, with the one acception that at the end, the very very end, the sniper sits looing at nothing for like a second
notes: seriously is the fucking random ass fucking orange box in the death animation a joke? when i say ragdolls, he just drops, he doesnt get shot. when the gaurd is hoved, they freak out, and the shove off into the pit changed to a shove just generically, and it looks bad. should be a shove into the pit. for the shove one, the gameplay of the shove minigame is super weird because of the way the bots behave, and its unclear thats whats happening. change the minigame so instead of everyone facing away, everyone starts closer to the edge facing in. that can be an actual gameplay change. then record that instead
notes: for when i say if my art didnt make it clear, it should be an older build of the game to show the even worse art. when you show the death animation in a grey void, why the fuck is the character rendered how it is in game??? and why the fucking hell, woudl you choose, for the moment when i say ragdolls and youre supposed to watch someone get shot, for that to be on the bounce pad section of the map? like holy shit use s2. then, in the forest shots, you do not see a single successful ragdoll, and a fucking player shoaves another one for no reason. then theres a sub one second clip of a bunch of player shoving each other, doesnt show ragdolling, looks like shit. the gaurd clips into the fucking pit wall lke we specifcally specified not to. and then cuts to a sniper pov for no fucking reason. is all of this clear? do you know how to fix it all? frankly i will say it is much much better for a first draft than we had been getting, but not good enough still
# v28 = v27 with M2 only: v8's own M2 (rough_v8/lines/M2.mkv, the authored Death clip, scared.gif already on it, no gif_fade row), 2.45 s (task #630).
# was: v27 = v26 with M2 only: 02_v27, the void prisoner in his own colours, the map's fit undone (task #630).
# was: v26 = v25 with M2 only: 02_v26, today's prisoner and its Death clip, crisp textures (task #630).
# was: v25 = v24 with L6 only: the POV pit shove alone (06b_v24, shove on "shove", the fall and the empty pit under the rest); the generic deck shove cut (task #630).
# was: v24 = v23 with Ryan's notes: M2 = 02_v24 (3a8cefd3: the modelled prisoner and its Death clip, no box); L4 = 04_v24 (the lead visibly shot and
# thrown on S2, the report and impact in the take's sound, game: 2 = the take's own level under the voice); L6 = 06_v24 (the flop, then the POV shove into the pit); L7 = 07_v24 (fixed ragdoll, one tumble).
# was: v23 = v22 with Ryan's notes: L1 = 57 (## 43 retaped on the current build); M2 = 02_v23, L3 = 03_v23 (the 0fe0c9ec old build:
# old runner, old Death clip, old hell ring); L4 = 04_v23 (scope misses, then the back runner as the lead is shot on S2);
# L5 = 05_v23 (forest, three visible ragdolls, no shoves); L6 = 06_v23 (two shove-and-flop halves); L7 = 07_v23 (clean throw, ends on the beat).
# was: v22 = v21 with L5's haters part ending before the guard's re-seat (the HUD's tower banner showed for 0.15 s at v21's 28.85 s); v21 = v20 after its frame check (never shown to Ryan): L3, L4's runner half and L5 refilmed; v20's table, rows composed by hand where a line needs more than one shot (task #630, short 4 from scratch):
# L1 the second miss and the hit with the old Death clip just after "bad", held 1.75 s past the hit; M2 the grey void
# death, scared.gif fading in from 1.2 s over 2.0 s (the beat ends with the fade); L3 the crane-out; L4 the scope's two
# misses (46), then the back runner (50) as the lead ahead drops on "Ragdolls", the placeholder comment card at "this guy";
# L5 forest: the flung lead and the middle man (54), the haters scope's drop, ravine throw and drop (55); frame check: L3 = 53 (45 read as a push in), L4 runner = 56 (50's lead left the frame); L6 the 3-runner scrap (48), then the
# POV's pit shove on "shove" (52); L7 the portal, the shove and the 2.0 s kill-beat cinematic (49). "htis" spoken "this".
pad: 0.2
game: 2
| line | clip | in | len | fit | speed | text | card | grade | gif_fade |
| L1 | cuts/57_v23.mp4 | 0.3 | 4.5 | wait | | The death animation in my game was really bad. | | | |
| M2 | rough_v8/lines/M2.mkv | 0 | 2.45 | beat 2.45 | | | | | |
| L3 | cuts/03_v23.mp4 | 1.5 | 6.7 | line | | Yeaeeeeeeeh I needed something better, but if my art didnt make it clear, I'm a programmer, not an animator | | | |
| L4 | cuts/04_v24.mp4 | 0 | 9.5 | wait | | Luckily my solution actually came from you guys, in an earlier short when i asked for suggestions, this guy gave me the exact solution to my problem? Ragdolls | cards/L4_card0.png w=940 y=0.2 in=0.05 out=0.2 from=this to=Ragdolls+0.6 | | |
| L5 | cuts/05_v23.mp4@1.0:6.45 | | | line | | these are pretty janky, but im keeping it that way, because it doesnt effect gameplay, and i think makes it more entertaining | | | |
| L6 | cuts/06b_v24.mp4 | 1.25 | 4.85 | line | | Once i had this, i wanted to use it more. Now when you shove someone, they also ragdoll. | | | |
| L7 | cuts/07_v24.mp4 | 0 | | line | | And when you reach the tower, you can shove the guard out, and watch them go flying into the pit. | | | |
| end | title | | 1.75 | | | beta signup in bio | | | |

## script v29
from: v28
notes: still the compelte wrong clip. make it from scratch, all its supposed to be is a screen capture of me playing the animation in the godot editor, and then, that face slowly fading in, it should not fade in on top of the character. it should play out, exactly as it doesn in v14, but it should be the most recent model
notes: for short 9. why the hell did anything change prior to the forest run. and for the fucking too boring forest section, you just added a fucking cut with the exact same footage with the fucking guys moved around? is that  fucking joke? this isnt a fucking pipeline issue what the fuck is wrong with you? and holy fuck, youre example of the bad death animation is now useing the fucking physics. literally just use, for only this one clip, the one i liked from the previous versions. other than that ists good. short 11 is good
notes: for the minigame short, two things, one the host of the running in the forest is too long, and we need to break it up with a second shot. dealers choice. tow, the sniper keeps trcaking, but theyre not standing where a sniper would stand, and when they do shoot its through the column of the tower. the death animation, in the gray space, is still fucking shit, becuase the model is blood red like they are in he.l. you already did this one successfully i have no idea what youre problem is. other than that its good. what about short 11 and 12?
notes: holy fuck. seriously on the ragdoll? the death animation on the grey background is using a weird fucking model of the character. the onld in game one with a bunch of filters on it. it looks like the version of the character your supposed to see from 100 ft away when it gets low rezed. everything else is good. short 12 is good, 11 is still doesnt read right. short 9 is good, with the one acception that at the end, the very very end, the sniper sits looing at nothing for like a second
notes: seriously is the fucking random ass fucking orange box in the death animation a joke? when i say ragdolls, he just drops, he doesnt get shot. when the gaurd is hoved, they freak out, and the shove off into the pit changed to a shove just generically, and it looks bad. should be a shove into the pit. for the shove one, the gameplay of the shove minigame is super weird because of the way the bots behave, and its unclear thats whats happening. change the minigame so instead of everyone facing away, everyone starts closer to the edge facing in. that can be an actual gameplay change. then record that instead
notes: for when i say if my art didnt make it clear, it should be an older build of the game to show the even worse art. when you show the death animation in a grey void, why the fuck is the character rendered how it is in game??? and why the fucking hell, woudl you choose, for the moment when i say ragdolls and youre supposed to watch someone get shot, for that to be on the bounce pad section of the map? like holy shit use s2. then, in the forest shots, you do not see a single successful ragdoll, and a fucking player shoaves another one for no reason. then theres a sub one second clip of a bunch of player shoving each other, doesnt show ragdolling, looks like shit. the gaurd clips into the fucking pit wall lke we specifcally specified not to. and then cuts to a sniper pov for no fucking reason. is all of this clear? do you know how to fix it all? frankly i will say it is much much better for a first draft than we had been getting, but not good enough still
# v29 = v28 with M2 only: 02_v29, a real Godot-editor screen capture (scrubbed copy, decision 362; editor/take.sh) of today's prisoner2.glb
# playing its Death clip, cut as v14's M2 beat for beat: 3.2 s, the fall at 0.95 s, scared.gif 900 wide at y 0.379 (above him, never on him)
# fading in from 2.25 s over 0.95 s, the beat ending with the fade (task #630).
# was: v28 = v27 with M2 only: v8's own M2 (rough_v8/lines/M2.mkv, the authored Death clip, scared.gif already on it, no gif_fade row), 2.45 s (task #630).
# was: v27 = v26 with M2 only: 02_v27, the void prisoner in his own colours, the map's fit undone (task #630).
# was: v26 = v25 with M2 only: 02_v26, today's prisoner and its Death clip, crisp textures (task #630).
# was: v25 = v24 with L6 only: the POV pit shove alone (06b_v24, shove on "shove", the fall and the empty pit under the rest); the generic deck shove cut (task #630).
# was: v24 = v23 with Ryan's notes: M2 = 02_v24 (3a8cefd3: the modelled prisoner and its Death clip, no box); L4 = 04_v24 (the lead visibly shot and
# thrown on S2, the report and impact in the take's sound, game: 2 = the take's own level under the voice); L6 = 06_v24 (the flop, then the POV shove into the pit); L7 = 07_v24 (fixed ragdoll, one tumble).
# was: v23 = v22 with Ryan's notes: L1 = 57 (## 43 retaped on the current build); M2 = 02_v23, L3 = 03_v23 (the 0fe0c9ec old build:
# old runner, old Death clip, old hell ring); L4 = 04_v23 (scope misses, then the back runner as the lead is shot on S2);
# L5 = 05_v23 (forest, three visible ragdolls, no shoves); L6 = 06_v23 (two shove-and-flop halves); L7 = 07_v23 (clean throw, ends on the beat).
# was: v22 = v21 with L5's haters part ending before the guard's re-seat (the HUD's tower banner showed for 0.15 s at v21's 28.85 s); v21 = v20 after its frame check (never shown to Ryan): L3, L4's runner half and L5 refilmed; v20's table, rows composed by hand where a line needs more than one shot (task #630, short 4 from scratch):
# L1 the second miss and the hit with the old Death clip just after "bad", held 1.75 s past the hit; M2 the grey void
# death, scared.gif fading in from 1.2 s over 2.0 s (the beat ends with the fade); L3 the crane-out; L4 the scope's two
# misses (46), then the back runner (50) as the lead ahead drops on "Ragdolls", the placeholder comment card at "this guy";
# L5 forest: the flung lead and the middle man (54), the haters scope's drop, ravine throw and drop (55); frame check: L3 = 53 (45 read as a push in), L4 runner = 56 (50's lead left the frame); L6 the 3-runner scrap (48), then the
# POV's pit shove on "shove" (52); L7 the portal, the shove and the 2.0 s kill-beat cinematic (49). "htis" spoken "this".
pad: 0.2
game: 2
| line | clip | in | len | fit | speed | text | card | grade | gif_fade |
| L1 | cuts/57_v23.mp4 | 0.3 | 4.5 | wait | | The death animation in my game was really bad. | | | |
| M2 | cuts/02_v29.mp4 | 0 | 3.2 | beat 3.2 | | | | | external/scared.gif 2.25 0.95 end w=900 y=0.379 |
| L3 | cuts/03_v23.mp4 | 1.5 | 6.7 | line | | Yeaeeeeeeeh I needed something better, but if my art didnt make it clear, I'm a programmer, not an animator | | | |
| L4 | cuts/04_v24.mp4 | 0 | 9.5 | wait | | Luckily my solution actually came from you guys, in an earlier short when i asked for suggestions, this guy gave me the exact solution to my problem? Ragdolls | cards/L4_card0.png w=940 y=0.2 in=0.05 out=0.2 from=this to=Ragdolls+0.6 | | |
| L5 | cuts/05_v23.mp4@1.0:6.45 | | | line | | these are pretty janky, but im keeping it that way, because it doesnt effect gameplay, and i think makes it more entertaining | | | |
| L6 | cuts/06b_v24.mp4 | 1.25 | 4.85 | line | | Once i had this, i wanted to use it more. Now when you shove someone, they also ragdoll. | | | |
| L7 | cuts/07_v24.mp4 | 0 | | line | | And when you reach the tower, you can shove the guard out, and watch them go flying into the pit. | | | |
| end | title | | 1.75 | | | beta signup in bio | | | |

## script v30
from: v29
notes: still the compelte wrong clip. make it from scratch, all its supposed to be is a screen capture of me playing the animation in the godot editor, and then, that face slowly fading in, it should not fade in on top of the character. it should play out, exactly as it doesn in v14, but it should be the most recent model
notes: still the compelte wrong clip. make it from scratch, all its supposed to be is a screen capture of me playing the animation in the godot editor, and then, that face slowly fading in, it should not fade in on top of the character. it should play out, exactly as it doesn in v14, but it should be the most recent model
notes: for short 9. why the hell did anything change prior to the forest run. and for the fucking too boring forest section, you just added a fucking cut with the exact same footage with the fucking guys moved around? is that  fucking joke? this isnt a fucking pipeline issue what the fuck is wrong with you? and holy fuck, youre example of the bad death animation is now useing the fucking physics. literally just use, for only this one clip, the one i liked from the previous versions. other than that ists good. short 11 is good
notes: for the minigame short, two things, one the host of the running in the forest is too long, and we need to break it up with a second shot. dealers choice. tow, the sniper keeps trcaking, but theyre not standing where a sniper would stand, and when they do shoot its through the column of the tower. the death animation, in the gray space, is still fucking shit, becuase the model is blood red like they are in he.l. you already did this one successfully i have no idea what youre problem is. other than that its good. what about short 11 and 12?
notes: holy fuck. seriously on the ragdoll? the death animation on the grey background is using a weird fucking model of the character. the onld in game one with a bunch of filters on it. it looks like the version of the character your supposed to see from 100 ft away when it gets low rezed. everything else is good. short 12 is good, 11 is still doesnt read right. short 9 is good, with the one acception that at the end, the very very end, the sniper sits looing at nothing for like a second
notes: seriously is the fucking random ass fucking orange box in the death animation a joke? when i say ragdolls, he just drops, he doesnt get shot. when the gaurd is hoved, they freak out, and the shove off into the pit changed to a shove just generically, and it looks bad. should be a shove into the pit. for the shove one, the gameplay of the shove minigame is super weird because of the way the bots behave, and its unclear thats whats happening. change the minigame so instead of everyone facing away, everyone starts closer to the edge facing in. that can be an actual gameplay change. then record that instead
notes: for when i say if my art didnt make it clear, it should be an older build of the game to show the even worse art. when you show the death animation in a grey void, why the fuck is the character rendered how it is in game??? and why the fucking hell, woudl you choose, for the moment when i say ragdolls and youre supposed to watch someone get shot, for that to be on the bounce pad section of the map? like holy shit use s2. then, in the forest shots, you do not see a single successful ragdoll, and a fucking player shoaves another one for no reason. then theres a sub one second clip of a bunch of player shoving each other, doesnt show ragdolling, looks like shit. the gaurd clips into the fucking pit wall lke we specifcally specified not to. and then cuts to a sniper pov for no fucking reason. is all of this clear? do you know how to fix it all? frankly i will say it is much much better for a first draft than we had been getting, but not good enough still
# v29 = v28 with M2 only: 02_v29, a real Godot-editor screen capture (scrubbed copy, decision 362; editor/take.sh) of today's prisoner2.glb
# playing its Death clip, cut as v14's M2 beat for beat: 3.2 s, the fall at 0.95 s, scared.gif 900 wide at y 0.379 (above him, never on him)
# fading in from 2.25 s over 0.95 s, the beat ending with the fade (task #630).
# was: v28 = v27 with M2 only: v8's own M2 (rough_v8/lines/M2.mkv, the authored Death clip, scared.gif already on it, no gif_fade row), 2.45 s (task #630).
# was: v27 = v26 with M2 only: 02_v27, the void prisoner in his own colours, the map's fit undone (task #630).
# was: v26 = v25 with M2 only: 02_v26, today's prisoner and its Death clip, crisp textures (task #630).
# was: v25 = v24 with L6 only: the POV pit shove alone (06b_v24, shove on "shove", the fall and the empty pit under the rest); the generic deck shove cut (task #630).
# was: v24 = v23 with Ryan's notes: M2 = 02_v24 (3a8cefd3: the modelled prisoner and its Death clip, no box); L4 = 04_v24 (the lead visibly shot and
# thrown on S2, the report and impact in the take's sound, game: 2 = the take's own level under the voice); L6 = 06_v24 (the flop, then the POV shove into the pit); L7 = 07_v24 (fixed ragdoll, one tumble).
# was: v23 = v22 with Ryan's notes: L1 = 57 (## 43 retaped on the current build); M2 = 02_v23, L3 = 03_v23 (the 0fe0c9ec old build:
# old runner, old Death clip, old hell ring); L4 = 04_v23 (scope misses, then the back runner as the lead is shot on S2);
# L5 = 05_v23 (forest, three visible ragdolls, no shoves); L6 = 06_v23 (two shove-and-flop halves); L7 = 07_v23 (clean throw, ends on the beat).
# was: v22 = v21 with L5's haters part ending before the guard's re-seat (the HUD's tower banner showed for 0.15 s at v21's 28.85 s); v21 = v20 after its frame check (never shown to Ryan): L3, L4's runner half and L5 refilmed; v20's table, rows composed by hand where a line needs more than one shot (task #630, short 4 from scratch):
# L1 the second miss and the hit with the old Death clip just after "bad", held 1.75 s past the hit; M2 the grey void
# death, scared.gif fading in from 1.2 s over 2.0 s (the beat ends with the fade); L3 the crane-out; L4 the scope's two
# misses (46), then the back runner (50) as the lead ahead drops on "Ragdolls", the placeholder comment card at "this guy";
# L5 forest: the flung lead and the middle man (54), the haters scope's drop, ravine throw and drop (55); frame check: L3 = 53 (45 read as a push in), L4 runner = 56 (50's lead left the frame); L6 the 3-runner scrap (48), then the
# POV's pit shove on "shove" (52); L7 the portal, the shove and the 2.0 s kill-beat cinematic (49). "htis" spoken "this".
pad: 0.2
game: 2
| line | clip | in | len | fit | speed | text | card | grade | gif_fade |
| L1 | cuts/57_v23.mp4 | 0.3 | 4.5 | wait | | The death animation in my game was really bad. | | | |
| M2 | cuts/02_v29.mp4 | 0.95 | 2.25 | beat 2.25 | | | | | external/scared.gif 1.30 0.95 end w=900 y=0.379 |
| L3 | cuts/03_v23.mp4 | 1.5 | 6.7 | line | | Yeaeeeeeeeh I needed something better, but if my art didnt make it clear, I'm a programmer, not an animator | | | |
| L4 | cuts/04_v24.mp4 | 0 | 9.5 | wait | | Luckily my solution actually came from you guys, in an earlier short when i asked for suggestions, this guy gave me the exact solution to my problem? Ragdolls | cards/L4_card0.png w=940 y=0.2 in=0.05 out=0.2 from=this to=Ragdolls+0.6 | | |
| L5 | cuts/05_v23.mp4@1.0:6.45 | | | line | | these are pretty janky, but im keeping it that way, because it doesnt effect gameplay, and i think makes it more entertaining | | | |
| L6 | cuts/06b_v24.mp4 | 1.25 | 4.85 | line | | Once i had this, i wanted to use it more. Now when you shove someone, they also ragdoll. | | | |
| L7 | cuts/07_v24.mp4 | 0 | | line | | And when you reach the tower, you can shove the guard out, and watch them go flying into the pit. | | | |
| end | title | | 1.75 | | | beta signup in bio | | | |

## script v31
from: v30
notes: Ryan's own recorded voice (short_13.aup4, ragdoll lines) replaces the TTS; the closing comments line is gone; the 0.98 s beta card is appended after assembly (task #630).
# v29 = v28 with M2 only: 02_v29, a real Godot-editor screen capture (scrubbed copy, decision 362; editor/take.sh) of today's prisoner2.glb
# playing its Death clip, cut as v14's M2 beat for beat: 3.2 s, the fall at 0.95 s, scared.gif 900 wide at y 0.379 (above him, never on him)
# fading in from 2.25 s over 0.95 s, the beat ending with the fade (task #630).
# was: v28 = v27 with M2 only: v8's own M2 (rough_v8/lines/M2.mkv, the authored Death clip, scared.gif already on it, no gif_fade row), 2.45 s (task #630).
# was: v27 = v26 with M2 only: 02_v27, the void prisoner in his own colours, the map's fit undone (task #630).
# was: v26 = v25 with M2 only: 02_v26, today's prisoner and its Death clip, crisp textures (task #630).
# was: v25 = v24 with L6 only: the POV pit shove alone (06b_v24, shove on "shove", the fall and the empty pit under the rest); the generic deck shove cut (task #630).
# was: v24 = v23 with Ryan's notes: M2 = 02_v24 (3a8cefd3: the modelled prisoner and its Death clip, no box); L4 = 04_v24 (the lead visibly shot and
# thrown on S2, the report and impact in the take's sound, game: 2 = the take's own level under the voice); L6 = 06_v24 (the flop, then the POV shove into the pit); L7 = 07_v24 (fixed ragdoll, one tumble).
# was: v23 = v22 with Ryan's notes: L1 = 57 (## 43 retaped on the current build); M2 = 02_v23, L3 = 03_v23 (the 0fe0c9ec old build:
# old runner, old Death clip, old hell ring); L4 = 04_v23 (scope misses, then the back runner as the lead is shot on S2);
# L5 = 05_v23 (forest, three visible ragdolls, no shoves); L6 = 06_v23 (two shove-and-flop halves); L7 = 07_v23 (clean throw, ends on the beat).
# was: v22 = v21 with L5's haters part ending before the guard's re-seat (the HUD's tower banner showed for 0.15 s at v21's 28.85 s); v21 = v20 after its frame check (never shown to Ryan): L3, L4's runner half and L5 refilmed; v20's table, rows composed by hand where a line needs more than one shot (task #630, short 4 from scratch):
# L1 the second miss and the hit with the old Death clip just after "bad", held 1.75 s past the hit; M2 the grey void
# death, scared.gif fading in from 1.2 s over 2.0 s (the beat ends with the fade); L3 the crane-out; L4 the scope's two
# misses (46), then the back runner (50) as the lead ahead drops on "Ragdolls", the placeholder comment card at "this guy";
# L5 forest: the flung lead and the middle man (54), the haters scope's drop, ravine throw and drop (55); frame check: L3 = 53 (45 read as a push in), L4 runner = 56 (50's lead left the frame); L6 the 3-runner scrap (48), then the
# POV's pit shove on "shove" (52); L7 the portal, the shove and the 2.0 s kill-beat cinematic (49). "htis" spoken "this".
pad: 0.2
game: 2
| line | clip | in | len | fit | speed | text | card | grade | gif_fade |
| L1 | cuts/57_v23.mp4 | 0.3 | 4.5 | wait | | The death animation in my game was really bad. | | | |
| M2 | cuts/02_v29.mp4 | 0.95 | 2.25 | beat 2.25 | | | | | external/scared.gif 1.30 0.95 end w=900 y=0.379 |
| L3 | cuts/03_v23.mp4 | 1.5 | 6.7 | line | | Yeaeeeeeeeh I needed something better, but if my art didnt make it clear, I'm a programmer, not an animator | | | |
| L4 | cuts/04_v24.mp4 | 0 | 9.5 | wait | | Luckily my solution actually came from you guys, in an earlier short when i asked for suggestions, this guy gave me the exact solution to my problem? Ragdolls | cards/L4_card0.png w=940 y=0.2 in=0.05 out=0.2 from=this to=Ragdolls+0.6 | | |
| L5 | cuts/05_v23.mp4@1.0:6.45 | | | line | | these are pretty janky, but im keeping it that way, because it doesnt effect gameplay, and i think makes it more entertaining | | | |
| L6 | cuts/06b_v24.mp4 | 1.05 | 5.3 | line | | Once i had this, i wanted to use it more. Now when you shove someone, they also ragdoll. | | | |
| L7 | cuts/07_v24.mp4 | 0 | | line | | And when you reach the tower, you can shove the guard out, and watch them go flying into the pit. | | | |

## script v32
from: v31
notes: Ryan's own recorded voice (short_13.aup4, ragdoll lines) replaces the TTS; the closing comments line is gone; the 0.98 s beta card is appended after assembly (task #630).
# v29 = v28 with M2 only: 02_v29, a real Godot-editor screen capture (scrubbed copy, decision 362; editor/take.sh) of today's prisoner2.glb
# playing its Death clip, cut as v14's M2 beat for beat: 3.2 s, the fall at 0.95 s, scared.gif 900 wide at y 0.379 (above him, never on him)
# fading in from 2.25 s over 0.95 s, the beat ending with the fade (task #630).
# was: v28 = v27 with M2 only: v8's own M2 (rough_v8/lines/M2.mkv, the authored Death clip, scared.gif already on it, no gif_fade row), 2.45 s (task #630).
# was: v27 = v26 with M2 only: 02_v27, the void prisoner in his own colours, the map's fit undone (task #630).
# was: v26 = v25 with M2 only: 02_v26, today's prisoner and its Death clip, crisp textures (task #630).
# was: v25 = v24 with L6 only: the POV pit shove alone (06b_v24, shove on "shove", the fall and the empty pit under the rest); the generic deck shove cut (task #630).
# was: v24 = v23 with Ryan's notes: M2 = 02_v24 (3a8cefd3: the modelled prisoner and its Death clip, no box); L4 = 04_v24 (the lead visibly shot and
# thrown on S2, the report and impact in the take's sound, game: 2 = the take's own level under the voice); L6 = 06_v24 (the flop, then the POV shove into the pit); L7 = 07_v24 (fixed ragdoll, one tumble).
# was: v23 = v22 with Ryan's notes: L1 = 57 (## 43 retaped on the current build); M2 = 02_v23, L3 = 03_v23 (the 0fe0c9ec old build:
# old runner, old Death clip, old hell ring); L4 = 04_v23 (scope misses, then the back runner as the lead is shot on S2);
# L5 = 05_v23 (forest, three visible ragdolls, no shoves); L6 = 06_v23 (two shove-and-flop halves); L7 = 07_v23 (clean throw, ends on the beat).
# was: v22 = v21 with L5's haters part ending before the guard's re-seat (the HUD's tower banner showed for 0.15 s at v21's 28.85 s); v21 = v20 after its frame check (never shown to Ryan): L3, L4's runner half and L5 refilmed; v20's table, rows composed by hand where a line needs more than one shot (task #630, short 4 from scratch):
# L1 the second miss and the hit with the old Death clip just after "bad", held 1.75 s past the hit; M2 the grey void
# death, scared.gif fading in from 1.2 s over 2.0 s (the beat ends with the fade); L3 the crane-out; L4 the scope's two
# misses (46), then the back runner (50) as the lead ahead drops on "Ragdolls", the placeholder comment card at "this guy";
# L5 forest: the flung lead and the middle man (54), the haters scope's drop, ravine throw and drop (55); frame check: L3 = 53 (45 read as a push in), L4 runner = 56 (50's lead left the frame); L6 the 3-runner scrap (48), then the
# POV's pit shove on "shove" (52); L7 the portal, the shove and the 2.0 s kill-beat cinematic (49). "htis" spoken "this".
pad: 0.2
game: 2
| line | clip | in | len | fit | speed | text | card | grade | gif_fade |
| L1 | cuts/57_v23.mp4 | 0.3 | 4.5 | wait | | The death animation in my game was really bad. | | | |
| M2 | cuts/02_v29.mp4 | 0.95 | 2.25 | beat 2.25 | | | | | external/scared.gif 1.30 0.95 end w=900 y=0.379 |
| L3 | cuts/03_v23.mp4 | 1.5 | 6.7 | line | | Yeaeeeeeeeh I needed something better, but if my art didnt make it clear, I'm a programmer, not an animator | | | |
| L4 | cuts/04_v24.mp4 | 0 | 9.5 | wait | | Luckily my solution actually came from you guys, in an earlier short when i asked for suggestions, this guy gave me the exact solution to my problem? Ragdolls | cards/L4_card0.png w=940 y=0.2 in=0.05 out=0.2 from=this to=Ragdolls+0.6 | | |
| L5 | cuts/05_v23.mp4@1.0:6.45 | | | line | | these are pretty janky, but im keeping it that way, because it doesnt effect gameplay, and i think makes it more entertaining | | | |
| L6 | cuts/06b_v24.mp4 | 1.05 | 5.3 | line | | Once i had this, i wanted to use it more. Now when you shove someone, they also ragdoll. | | | |
| L7 | cuts/07_v24.mp4 | 0 | | line | | And when you reach the tower, you can shove the guard out, and watch them go flying into the pit. | | | |

## script v33
from: v32
notes: Ryan (20:11, on ragdoll_short_final_ttig/youtube, task #630): "the yeah is cut into the first line. the audio mixing on the whole thing is actually just a joke. so go fix that". Ryan (19:52): "no, dont just fix that little thing, figure out why the fuck that happened and do the audio mixing properly". Ryan (19:56): "weve fucking done this before ... dont we have a full fucking short pipeline". Ryan (earlier): "i just got that voice clip, use it on short 4 and 13 and creat a youtube and tt/insta version." v33 (TikTok/IG) and v34 (YouTube): v32 plus the voiced end card row (beta_link.wav / beta_link_youtube.wav through vo.py --outro); voice re-run through vo.py with the energy-gated breath duck.
notes: Ryan's own recorded voice (short_13.aup4, ragdoll lines) replaces the TTS; the closing comments line is gone; the 0.98 s beta card is appended after assembly (task #630).
# v29 = v28 with M2 only: 02_v29, a real Godot-editor screen capture (scrubbed copy, decision 362; editor/take.sh) of today's prisoner2.glb
# playing its Death clip, cut as v14's M2 beat for beat: 3.2 s, the fall at 0.95 s, scared.gif 900 wide at y 0.379 (above him, never on him)
# fading in from 2.25 s over 0.95 s, the beat ending with the fade (task #630).
# was: v28 = v27 with M2 only: v8's own M2 (rough_v8/lines/M2.mkv, the authored Death clip, scared.gif already on it, no gif_fade row), 2.45 s (task #630).
# was: v27 = v26 with M2 only: 02_v27, the void prisoner in his own colours, the map's fit undone (task #630).
# was: v26 = v25 with M2 only: 02_v26, today's prisoner and its Death clip, crisp textures (task #630).
# was: v25 = v24 with L6 only: the POV pit shove alone (06b_v24, shove on "shove", the fall and the empty pit under the rest); the generic deck shove cut (task #630).
# was: v24 = v23 with Ryan's notes: M2 = 02_v24 (3a8cefd3: the modelled prisoner and its Death clip, no box); L4 = 04_v24 (the lead visibly shot and
# thrown on S2, the report and impact in the take's sound, game: 2 = the take's own level under the voice); L6 = 06_v24 (the flop, then the POV shove into the pit); L7 = 07_v24 (fixed ragdoll, one tumble).
# was: v23 = v22 with Ryan's notes: L1 = 57 (## 43 retaped on the current build); M2 = 02_v23, L3 = 03_v23 (the 0fe0c9ec old build:
# old runner, old Death clip, old hell ring); L4 = 04_v23 (scope misses, then the back runner as the lead is shot on S2);
# L5 = 05_v23 (forest, three visible ragdolls, no shoves); L6 = 06_v23 (two shove-and-flop halves); L7 = 07_v23 (clean throw, ends on the beat).
# was: v22 = v21 with L5's haters part ending before the guard's re-seat (the HUD's tower banner showed for 0.15 s at v21's 28.85 s); v21 = v20 after its frame check (never shown to Ryan): L3, L4's runner half and L5 refilmed; v20's table, rows composed by hand where a line needs more than one shot (task #630, short 4 from scratch):
# L1 the second miss and the hit with the old Death clip just after "bad", held 1.75 s past the hit; M2 the grey void
# death, scared.gif fading in from 1.2 s over 2.0 s (the beat ends with the fade); L3 the crane-out; L4 the scope's two
# misses (46), then the back runner (50) as the lead ahead drops on "Ragdolls", the placeholder comment card at "this guy";
# L5 forest: the flung lead and the middle man (54), the haters scope's drop, ravine throw and drop (55); frame check: L3 = 53 (45 read as a push in), L4 runner = 56 (50's lead left the frame); L6 the 3-runner scrap (48), then the
# POV's pit shove on "shove" (52); L7 the portal, the shove and the 2.0 s kill-beat cinematic (49). "htis" spoken "this".
pad: 0.2
game: 2
| line | clip | in | len | fit | speed | text | card | grade | gif_fade |
| L1 | cuts/57_v23.mp4 | 0.3 | 4.5 | wait | | The death animation in my game was really bad. | | | |
| M2 | cuts/02_v29.mp4 | 0.95 | 2.25 | beat 2.25 | | | | | external/scared.gif 1.30 0.95 end w=900 y=0.379 |
| L3 | cuts/03_v23.mp4 | 1.5 | 6.7 | line | | Yeaeeeeeeeh I needed something better, but if my art didnt make it clear, I'm a programmer, not an animator | | | |
| L4 | cuts/04_v24.mp4 | 0 | 9.5 | wait | | Luckily my solution actually came from you guys, in an earlier short when i asked for suggestions, this guy gave me the exact solution to my problem? Ragdolls | cards/L4_card0.png w=940 y=0.2 in=0.05 out=0.2 from=this to=Ragdolls+0.6 | | |
| L5 | cuts/05_v23.mp4@1.0:6.45 | | | line | | these are pretty janky, but im keeping it that way, because it doesnt effect gameplay, and i think makes it more entertaining | | | |
| L6 | cuts/06b_v24.mp4 | 1.05 | 5.3 | line | | Once i had this, i wanted to use it more. Now when you shove someone, they also ragdoll. | | | |
| L7 | cuts/07_v24.mp4 | 0 | | line | | And when you reach the tower, you can shove the guard out, and watch them go flying into the pit. | | | |
| end | title | | | line | | beta link in bio | beta signup in bio | | |

## script v34
from: v32
notes: Ryan (20:11, on ragdoll_short_final_ttig/youtube, task #630): "the yeah is cut into the first line. the audio mixing on the whole thing is actually just a joke. so go fix that". Ryan (19:52): "no, dont just fix that little thing, figure out why the fuck that happened and do the audio mixing properly". Ryan (19:56): "weve fucking done this before ... dont we have a full fucking short pipeline". Ryan (earlier): "i just got that voice clip, use it on short 4 and 13 and creat a youtube and tt/insta version." v33 (TikTok/IG) and v34 (YouTube): v32 plus the voiced end card row (beta_link.wav / beta_link_youtube.wav through vo.py --outro); voice re-run through vo.py with the energy-gated breath duck.
notes: Ryan's own recorded voice (short_13.aup4, ragdoll lines) replaces the TTS; the closing comments line is gone; the 0.98 s beta card is appended after assembly (task #630).
# v29 = v28 with M2 only: 02_v29, a real Godot-editor screen capture (scrubbed copy, decision 362; editor/take.sh) of today's prisoner2.glb
# playing its Death clip, cut as v14's M2 beat for beat: 3.2 s, the fall at 0.95 s, scared.gif 900 wide at y 0.379 (above him, never on him)
# fading in from 2.25 s over 0.95 s, the beat ending with the fade (task #630).
# was: v28 = v27 with M2 only: v8's own M2 (rough_v8/lines/M2.mkv, the authored Death clip, scared.gif already on it, no gif_fade row), 2.45 s (task #630).
# was: v27 = v26 with M2 only: 02_v27, the void prisoner in his own colours, the map's fit undone (task #630).
# was: v26 = v25 with M2 only: 02_v26, today's prisoner and its Death clip, crisp textures (task #630).
# was: v25 = v24 with L6 only: the POV pit shove alone (06b_v24, shove on "shove", the fall and the empty pit under the rest); the generic deck shove cut (task #630).
# was: v24 = v23 with Ryan's notes: M2 = 02_v24 (3a8cefd3: the modelled prisoner and its Death clip, no box); L4 = 04_v24 (the lead visibly shot and
# thrown on S2, the report and impact in the take's sound, game: 2 = the take's own level under the voice); L6 = 06_v24 (the flop, then the POV shove into the pit); L7 = 07_v24 (fixed ragdoll, one tumble).
# was: v23 = v22 with Ryan's notes: L1 = 57 (## 43 retaped on the current build); M2 = 02_v23, L3 = 03_v23 (the 0fe0c9ec old build:
# old runner, old Death clip, old hell ring); L4 = 04_v23 (scope misses, then the back runner as the lead is shot on S2);
# L5 = 05_v23 (forest, three visible ragdolls, no shoves); L6 = 06_v23 (two shove-and-flop halves); L7 = 07_v23 (clean throw, ends on the beat).
# was: v22 = v21 with L5's haters part ending before the guard's re-seat (the HUD's tower banner showed for 0.15 s at v21's 28.85 s); v21 = v20 after its frame check (never shown to Ryan): L3, L4's runner half and L5 refilmed; v20's table, rows composed by hand where a line needs more than one shot (task #630, short 4 from scratch):
# L1 the second miss and the hit with the old Death clip just after "bad", held 1.75 s past the hit; M2 the grey void
# death, scared.gif fading in from 1.2 s over 2.0 s (the beat ends with the fade); L3 the crane-out; L4 the scope's two
# misses (46), then the back runner (50) as the lead ahead drops on "Ragdolls", the placeholder comment card at "this guy";
# L5 forest: the flung lead and the middle man (54), the haters scope's drop, ravine throw and drop (55); frame check: L3 = 53 (45 read as a push in), L4 runner = 56 (50's lead left the frame); L6 the 3-runner scrap (48), then the
# POV's pit shove on "shove" (52); L7 the portal, the shove and the 2.0 s kill-beat cinematic (49). "htis" spoken "this".
pad: 0.2
game: 2
| line | clip | in | len | fit | speed | text | card | grade | gif_fade |
| L1 | cuts/57_v23.mp4 | 0.3 | 4.5 | wait | | The death animation in my game was really bad. | | | |
| M2 | cuts/02_v29.mp4 | 0.95 | 2.25 | beat 2.25 | | | | | external/scared.gif 1.30 0.95 end w=900 y=0.379 |
| L3 | cuts/03_v23.mp4 | 1.5 | 6.7 | line | | Yeaeeeeeeeh I needed something better, but if my art didnt make it clear, I'm a programmer, not an animator | | | |
| L4 | cuts/04_v24.mp4 | 0 | 9.5 | wait | | Luckily my solution actually came from you guys, in an earlier short when i asked for suggestions, this guy gave me the exact solution to my problem? Ragdolls | cards/L4_card0.png w=940 y=0.2 in=0.05 out=0.2 from=this to=Ragdolls+0.6 | | |
| L5 | cuts/05_v23.mp4@1.0:6.45 | | | line | | these are pretty janky, but im keeping it that way, because it doesnt effect gameplay, and i think makes it more entertaining | | | |
| L6 | cuts/06b_v24.mp4 | 1.05 | 5.3 | line | | Once i had this, i wanted to use it more. Now when you shove someone, they also ragdoll. | | | |
| L7 | cuts/07_v24.mp4 | 0 | | line | | And when you reach the tower, you can shove the guard out, and watch them go flying into the pit. | | | |
| end | title | | | line | | beta sign up on my channel | beta signup on my channel | | |

## script v35
from: v34
notes: Ryan (20:50, on v33/v34 and v14/v15, tasks #630/#601): "ok, ragdolls audio is good. on the "once i had this" clip, it needs to be reshot because it has sone lag. also remove all sound effects, only my voice and future music. minigame is good, just al ittle more space between "sniper" and "this" say add half a second. once those are done we can pick music"
notes: Ryan (20:11, on ragdoll_short_final_ttig/youtube, task #630): "the yeah is cut into the first line. the audio mixing on the whole thing is actually just a joke. so go fix that". Ryan (19:52): "no, dont just fix that little thing, figure out why the fuck that happened and do the audio mixing properly". Ryan (19:56): "weve fucking done this before ... dont we have a full fucking short pipeline". Ryan (earlier): "i just got that voice clip, use it on short 4 and 13 and creat a youtube and tt/insta version." v33 (TikTok/IG) and v34 (YouTube): v32 plus the voiced end card row (beta_link.wav / beta_link_youtube.wav through vo.py --outro); voice re-run through vo.py with the energy-gated breath duck.
notes: Ryan's own recorded voice (short_13.aup4, ragdoll lines) replaces the TTS; the closing comments line is gone; the 0.98 s beta card is appended after assembly (task #630).
# v29 = v28 with M2 only: 02_v29, a real Godot-editor screen capture (scrubbed copy, decision 362; editor/take.sh) of today's prisoner2.glb
# playing its Death clip, cut as v14's M2 beat for beat: 3.2 s, the fall at 0.95 s, scared.gif 900 wide at y 0.379 (above him, never on him)
# fading in from 2.25 s over 0.95 s, the beat ending with the fade (task #630).
# was: v28 = v27 with M2 only: v8's own M2 (rough_v8/lines/M2.mkv, the authored Death clip, scared.gif already on it, no gif_fade row), 2.45 s (task #630).
# was: v27 = v26 with M2 only: 02_v27, the void prisoner in his own colours, the map's fit undone (task #630).
# was: v26 = v25 with M2 only: 02_v26, today's prisoner and its Death clip, crisp textures (task #630).
# was: v25 = v24 with L6 only: the POV pit shove alone (06b_v24, shove on "shove", the fall and the empty pit under the rest); the generic deck shove cut (task #630).
# was: v24 = v23 with Ryan's notes: M2 = 02_v24 (3a8cefd3: the modelled prisoner and its Death clip, no box); L4 = 04_v24 (the lead visibly shot and
# thrown on S2, the report and impact in the take's sound, game: 2 = the take's own level under the voice); L6 = 06_v24 (the flop, then the POV shove into the pit); L7 = 07_v24 (fixed ragdoll, one tumble).
# was: v23 = v22 with Ryan's notes: L1 = 57 (## 43 retaped on the current build); M2 = 02_v23, L3 = 03_v23 (the 0fe0c9ec old build:
# old runner, old Death clip, old hell ring); L4 = 04_v23 (scope misses, then the back runner as the lead is shot on S2);
# L5 = 05_v23 (forest, three visible ragdolls, no shoves); L6 = 06_v23 (two shove-and-flop halves); L7 = 07_v23 (clean throw, ends on the beat).
# was: v22 = v21 with L5's haters part ending before the guard's re-seat (the HUD's tower banner showed for 0.15 s at v21's 28.85 s); v21 = v20 after its frame check (never shown to Ryan): L3, L4's runner half and L5 refilmed; v20's table, rows composed by hand where a line needs more than one shot (task #630, short 4 from scratch):
# L1 the second miss and the hit with the old Death clip just after "bad", held 1.75 s past the hit; M2 the grey void
# death, scared.gif fading in from 1.2 s over 2.0 s (the beat ends with the fade); L3 the crane-out; L4 the scope's two
# misses (46), then the back runner (50) as the lead ahead drops on "Ragdolls", the placeholder comment card at "this guy";
# L5 forest: the flung lead and the middle man (54), the haters scope's drop, ravine throw and drop (55); frame check: L3 = 53 (45 read as a push in), L4 runner = 56 (50's lead left the frame); L6 the 3-runner scrap (48), then the
# POV's pit shove on "shove" (52); L7 the portal, the shove and the 2.0 s kill-beat cinematic (49). "htis" spoken "this".
pad: 0.2
| line | clip | in | len | fit | speed | text | card | grade | gif_fade |
| L1 | cuts/57_v23.mp4 | 0.3 | 4.5 | wait | | The death animation in my game was really bad. | | | |
| M2 | cuts/02_v29.mp4 | 0.95 | 2.25 | beat 2.25 | | | | | external/scared.gif 1.30 0.95 end w=900 y=0.379 |
| L3 | cuts/03_v23.mp4 | 1.5 | 6.7 | line | | Yeaeeeeeeeh I needed something better, but if my art didnt make it clear, I'm a programmer, not an animator | | | |
| L4 | cuts/04_v24.mp4 | 0 | 9.5 | wait | | Luckily my solution actually came from you guys, in an earlier short when i asked for suggestions, this guy gave me the exact solution to my problem? Ragdolls | cards/L4_card0.png w=940 y=0.2 in=0.05 out=0.2 from=this to=Ragdolls+0.6 | | |
| L5 | cuts/05_v23.mp4@1.0:6.45 | | | line | | these are pretty janky, but im keeping it that way, because it doesnt effect gameplay, and i think makes it more entertaining | | | |
| L6 | cuts/06b_v35m.mp4 | 1.05 | 5.3 | line | | Once i had this, i wanted to use it more. Now when you shove someone, they also ragdoll. | | | |
| L7 | cuts/07_v24.mp4 | 0 | | line | | And when you reach the tower, you can shove the guard out, and watch them go flying into the pit. | | | |
| end | title | | | line | | beta sign up on my channel | beta signup on my channel | | |

## script v36
from: v34
notes: Ryan (20:50, on v33/v34 and v14/v15, tasks #630/#601): "ok, ragdolls audio is good. on the "once i had this" clip, it needs to be reshot because it has sone lag. also remove all sound effects, only my voice and future music. minigame is good, just al ittle more space between "sniper" and "this" say add half a second. once those are done we can pick music"
notes: Ryan (20:11, on ragdoll_short_final_ttig/youtube, task #630): "the yeah is cut into the first line. the audio mixing on the whole thing is actually just a joke. so go fix that". Ryan (19:52): "no, dont just fix that little thing, figure out why the fuck that happened and do the audio mixing properly". Ryan (19:56): "weve fucking done this before ... dont we have a full fucking short pipeline". Ryan (earlier): "i just got that voice clip, use it on short 4 and 13 and creat a youtube and tt/insta version." v33 (TikTok/IG) and v34 (YouTube): v32 plus the voiced end card row (beta_link.wav / beta_link_youtube.wav through vo.py --outro); voice re-run through vo.py with the energy-gated breath duck.
notes: Ryan's own recorded voice (short_13.aup4, ragdoll lines) replaces the TTS; the closing comments line is gone; the 0.98 s beta card is appended after assembly (task #630).
# v29 = v28 with M2 only: 02_v29, a real Godot-editor screen capture (scrubbed copy, decision 362; editor/take.sh) of today's prisoner2.glb
# playing its Death clip, cut as v14's M2 beat for beat: 3.2 s, the fall at 0.95 s, scared.gif 900 wide at y 0.379 (above him, never on him)
# fading in from 2.25 s over 0.95 s, the beat ending with the fade (task #630).
# was: v28 = v27 with M2 only: v8's own M2 (rough_v8/lines/M2.mkv, the authored Death clip, scared.gif already on it, no gif_fade row), 2.45 s (task #630).
# was: v27 = v26 with M2 only: 02_v27, the void prisoner in his own colours, the map's fit undone (task #630).
# was: v26 = v25 with M2 only: 02_v26, today's prisoner and its Death clip, crisp textures (task #630).
# was: v25 = v24 with L6 only: the POV pit shove alone (06b_v24, shove on "shove", the fall and the empty pit under the rest); the generic deck shove cut (task #630).
# was: v24 = v23 with Ryan's notes: M2 = 02_v24 (3a8cefd3: the modelled prisoner and its Death clip, no box); L4 = 04_v24 (the lead visibly shot and
# thrown on S2, the report and impact in the take's sound, game: 2 = the take's own level under the voice); L6 = 06_v24 (the flop, then the POV shove into the pit); L7 = 07_v24 (fixed ragdoll, one tumble).
# was: v23 = v22 with Ryan's notes: L1 = 57 (## 43 retaped on the current build); M2 = 02_v23, L3 = 03_v23 (the 0fe0c9ec old build:
# old runner, old Death clip, old hell ring); L4 = 04_v23 (scope misses, then the back runner as the lead is shot on S2);
# L5 = 05_v23 (forest, three visible ragdolls, no shoves); L6 = 06_v23 (two shove-and-flop halves); L7 = 07_v23 (clean throw, ends on the beat).
# was: v22 = v21 with L5's haters part ending before the guard's re-seat (the HUD's tower banner showed for 0.15 s at v21's 28.85 s); v21 = v20 after its frame check (never shown to Ryan): L3, L4's runner half and L5 refilmed; v20's table, rows composed by hand where a line needs more than one shot (task #630, short 4 from scratch):
# L1 the second miss and the hit with the old Death clip just after "bad", held 1.75 s past the hit; M2 the grey void
# death, scared.gif fading in from 1.2 s over 2.0 s (the beat ends with the fade); L3 the crane-out; L4 the scope's two
# misses (46), then the back runner (50) as the lead ahead drops on "Ragdolls", the placeholder comment card at "this guy";
# L5 forest: the flung lead and the middle man (54), the haters scope's drop, ravine throw and drop (55); frame check: L3 = 53 (45 read as a push in), L4 runner = 56 (50's lead left the frame); L6 the 3-runner scrap (48), then the
# POV's pit shove on "shove" (52); L7 the portal, the shove and the 2.0 s kill-beat cinematic (49). "htis" spoken "this".
pad: 0.2
| line | clip | in | len | fit | speed | text | card | grade | gif_fade |
| L1 | cuts/57_v23.mp4 | 0.3 | 4.5 | wait | | The death animation in my game was really bad. | | | |
| M2 | cuts/02_v29.mp4 | 0.95 | 2.25 | beat 2.25 | | | | | external/scared.gif 1.30 0.95 end w=900 y=0.379 |
| L3 | cuts/03_v23.mp4 | 1.5 | 6.7 | line | | Yeaeeeeeeeh I needed something better, but if my art didnt make it clear, I'm a programmer, not an animator | | | |
| L4 | cuts/04_v24.mp4 | 0 | 9.5 | wait | | Luckily my solution actually came from you guys, in an earlier short when i asked for suggestions, this guy gave me the exact solution to my problem? Ragdolls | cards/L4_card0.png w=940 y=0.2 in=0.05 out=0.2 from=this to=Ragdolls+0.6 | | |
| L5 | cuts/05_v23.mp4@1.0:6.45 | | | line | | these are pretty janky, but im keeping it that way, because it doesnt effect gameplay, and i think makes it more entertaining | | | |
| L6 | cuts/06b_v35m.mp4 | 1.05 | 5.3 | line | | Once i had this, i wanted to use it more. Now when you shove someone, they also ragdoll. | | | |
| L7 | cuts/07_v24.mp4 | 0 | | line | | And when you reach the tower, you can shove the guard out, and watch them go flying into the pit. | | | |
| end | title | | | line | | beta link in bio | beta signup in bio | | |
