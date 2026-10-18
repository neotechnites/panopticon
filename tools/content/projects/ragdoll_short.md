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
