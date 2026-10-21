# start_minigame
kind: short

## 1
said: pov of a runner in the tower shoving the sniper and the cinematic shot that plays after, in hell; on n1: "for 9, shot one, should only be the shove and the cinematic, not the going into the portal at all." The cut opens in the tower 0.53 s before the shove (no portal) and runs the kill beat to the seat change.
capture: --shot=s3_open_lane --stage=finale --pov=runner --bots=3 --shimmer=0 --seed=20261012 --set=lead=6.0;stand=3.0;pace=0.32;beat=2.0
expect: shove Runner_0 3.48-3.78; arrive Runner_1 2.0-2.25; tower_out Runner_0 +1.9-2.1; alive Runner_1; lens_clear; lens_cover <= 0.5
seconds: 2.5
in: 3.1
refilm: v1,v4

## 2
said: runner pov, looking over at the tower while hes shooting, then look forward and start doing the lava parkour section
capture: --shot=s3_open_lane --stage=parkour_sniped --pov=runner --bots=3 --shimmer=0 --look=social --rifle=projectile --seed=20261017 --set=look_to=4.4;misses=1.9,3.0,7.4;drop_at=8.6;hold_to=11.6
tape: start_minigame_v4
expect: hop1 Runner_1 4.5-4.7; hop2 Runner_1 +0.7-0.9; alive Runner_1; lens_clear; lens_cover <= 0.5
seconds: 6.4
in: 1
refilm: v1,v4

## 3
said: pov of the sniper sniping at the runner from the previous shot
capture: --shot=s3_open_lane --stage=parkour_sniped --pov=guard --bots=3 --shimmer=0 --look=social --rifle=projectile --seed=20261017 --set=look_to=4.4;misses=1.9,3.0;guard_deg=340;finish=341.5;finish_pace=0.6;drop_at=13.6;hold_to=16
tape: start_minigame_v9_guard
hud: crosshair
expect: hit Runner_1 13.85-14.05; in_frame Runner_1 +0.0-0.05; hop8 Runner_1 10.25-10.45; finish Runner_1 11.1-11.7; lens_clear; lens_cover <= 0.5
seconds: 4.6
in: 10.8
motion: 0.012
refilm: v1,v2,v4,v7,v8,v9

## 4
said: pov of race in forest
capture: --shot=s3_open_lane --stage=forest_race --map=forest --pov=runner --bots=3 --shimmer=0 --look=social --seed=20261017
expect: race_start 0-0.5; lens_clear; lens_cover <= 0.5
seconds: 19.5
in: 1
refilm: v1,v4

## 5
said: bust shot of runner in hell idle animating
capture: --shot=s1_cave --stage=hell_idle_bust --bots=1 --look=social --shimmer=0 --seed=20261017
expect: idle Runner_1 0.6-0.9; alive Runner_1; lens_clear; lens_cover <= 0.5
seconds: 3
in: 1.2
motion: 0.005
refilm: v1,v2

## 6
said: Shot of starting shove tower minigame in hell; on n1: "why is the last shot not from the perspective of a player?"; on n2: "change the minigame so instead of everyone facing away, everyone starts closer to the edge facing in ... then record that instead". Runner_2's eyes in the brawl on the new spawn (all four ringed 1 m in from the edge, facing the middle): he watches Runner_0 throw Runner_1 out (shove 2.47, out 3.42), shoves Runner_3 out (3.67, out 4.62), is shoved by Runner_0 (4.00), shoves Runner_0 (5.20) and throws him out (6.73, out 7.68); last one standing, he takes the seat (9.20) and drops a runner as the sniper (14.57, fire_at 5.3 so the shot is the last action). Mac smoke 20261017; cover cap 0.55: Runner_0 fills 0.52 of the lens for 0.12 s as the POV lines up the 6.73 shove.
capture: --shot=s3_open_lane --stage=tower_brawl --pov=runner --bots=3 --shimmer=0 --look=social --seed=20261017 --set=watch=1;turn_at=1.0;fire_at=5.3
tape: start_minigame_v7_brawl
shoved: ok
expect: brawl_start 0.0-0.1; shove Runner_1 2.37-2.57; brawl_out Runner_1 3.3-3.55; shove Runner_2 3.57-3.77; brawl_out Runner_3 4.5-4.75; brawl_won Runner_2 7.55-7.8; hit Runner_1 14.4-14.6; lens_cover <= 0.55
seconds: 14.65
in: 0.3
motion: 0.012
refilm: v1,v2,v3,v4,v5,v6,v7

## 7
said: second shot of the race in forest: a different event of the same race, its finish. A fixed high lens behind the finish portal (345 deg) looks back down the open stretch; the pack comes down it, the first man runs into the portal and takes the tower (race_won 28.52 s), the two behind him 1.5 and 3 m back, and the lane empties as the round starts. Ryan on v6: "the running in the forest is too long, and we need to break it up with a second shot. dealers choice"; on v9 another runner's eyes was "the exact same footage with the fucking guys moved around"; on v10 the reverse dolly on the lane "showing the front side of the same boring footage does not fix it". Probe (probe_ring --los --map=forest, eye 351.5:52.5:7.5): the lane r 50-51 open 312-340 deg, the canopy wall hides 296-308, the portal 342.
capture: --shot=s3_open_lane --stage=forest_race_finish --map=forest --bots=3 --shimmer=0 --look=social --seed=20261017
expect: race_start 0-0.5; race_won Runner_2 28.2-28.9; lens_clear; lens_cover <= 0.5
seconds: 5.0
in: 25.0
refilm: v7,v10,v11,v12

## script v1
pad: 0.2
| line | clip | in | len | fit | speed | text | card |
| L1 | cuts/01_v1.mp4 | 1.5 | 3.4 | wait | | Heres how i fixed the worst part about my game | |
| L2 | cuts/02_v1.mp4 | 0 | 6.4 | line | | In my game, youre either the sniper in the gaurd tower, or youre running an obsticle course to become the sniper. | |
| L3 | cuts/03_v1.mp4 | 0.214 | 4.386 | line | | but this has a problem, whos the sniper first? i wanted it to be earned | |
| L4 | cuts/04_v1.mp4 | 0 | 19.5 | line | | so, i implemented a race, every player does the course with no sniper, and the first one to complete it gets to be the sniper. this, was the worst part of my game. it wasnt fun, everyone was the same speed, and it took to long | |
| L5 | cuts/05_v1.mp4 | 0 | 3 | line | | so how did i fix it? | |
| L6 | cuts/06_v1.mp4 | 0 | 20 | line | | instead of everyone running to the tower, everyone starts in the tower, and the way you get to be the sniper, is to be the last one standing in it. so now, instead of a long drawn out boring race, its a fast, chaotic, brawl to see who goes first | |
| end | title | | 1.75 | | | beta signup in bio | |

## script v2
from: v1
notes: Agent frame check of v1 (task #601, not Ryan's notes; v1 was not shown to him): L1 the kill-beat camera loses the guard for the last 0.8 s; L3 the scope holds 2 s on empty lava after the drop; L5 the bust cuts off the top of his head; L6 the PC brawl ran untaped and diverged from the smoke (an empty room before the seat).
pad: 0.2
| line | clip | in | len | fit | speed | text | card |
| L1 | cuts/01_v1.mp4 | 1.3 | 2.7 | wait | | Heres how i fixed the worst part about my game | |
| L2 | cuts/02_v1.mp4 | 0 | 6.4 | line | | In my game, youre either the sniper in the gaurd tower, or youre running an obsticle course to become the sniper. | |
| L3 | cuts/03_v2.mp4 | 0.2 | 4.4 | line | | but this has a problem, whos the sniper first? i wanted it to be earned | |
| L4 | cuts/04_v1.mp4 | 0 | 19.5 | line | | so, i implemented a race, every player does the course with no sniper, and the first one to complete it gets to be the sniper. this, was the worst part of my game. it wasnt fun, everyone was the same speed, and it took to long | |
| L5 | cuts/05_v2.mp4 | 0 | 3 | line | | so how did i fix it? | |
| L6 | cuts/06_v2.mp4 | 0 | 15.5 | line | | instead of everyone running to the tower, everyone starts in the tower, and the way you get to be the sniper, is to be the last one standing in it. so now, instead of a long drawn out boring race, its a fast, chaotic, brawl to see who goes first | |
| end | title | | 1.75 | | | beta signup in bio | |

## script v3
from: v2
notes: Agent frame check of v2 (task #601, not Ryan's notes; v2 was not shown to him): L6 the last one standing runs out of frame for 1.4 s before he is seated (the room reads empty).
notes: Agent frame check of v1 (task #601, not Ryan's notes; v1 was not shown to him): L1 the kill-beat camera loses the guard for the last 0.8 s; L3 the scope holds 2 s on empty lava after the drop; L5 the bust cuts off the top of his head; L6 the PC brawl ran untaped and diverged from the smoke (an empty room before the seat).
pad: 0.2
| line | clip | in | len | fit | speed | text | card |
| L1 | cuts/01_v1.mp4 | 1.3 | 2.7 | wait | | Heres how i fixed the worst part about my game | |
| L2 | cuts/02_v1.mp4 | 0 | 6.4 | line | | In my game, youre either the sniper in the gaurd tower, or youre running an obsticle course to become the sniper. | |
| L3 | cuts/03_v2.mp4 | 0.2 | 4.4 | line | | but this has a problem, whos the sniper first? i wanted it to be earned | |
| L4 | cuts/04_v1.mp4 | 0 | 19.5 | line | | so, i implemented a race, every player does the course with no sniper, and the first one to complete it gets to be the sniper. this, was the worst part of my game. it wasnt fun, everyone was the same speed, and it took to long | |
| L5 | cuts/05_v2.mp4 | 0 | 3 | line | | so how did i fix it? | |
| L6 | cuts/06_v3.mp4 | 0 | 15.5 | line | | instead of everyone running to the tower, everyone starts in the tower, and the way you get to be the sniper, is to be the last one standing in it. so now, instead of a long drawn out boring race, its a fast, chaotic, brawl to see who goes first | |
| end | title | | 1.75 | | | beta signup in bio | |

## script v4
from: v3
notes: Ryan on n1 (v3, task #601): "for 9, shot one, should only be the shove and the cinematic, not the going into the portal at all. the next two shots are fine, the shot of the player can just be removed. then, why is the last shot not from the perspective of a player? and also, why do the player charactes look like that in game? we made such a detailed model, what the fuck is going on? is the branch youre on not useing the most up to date game?"
notes: Agent frame check of v2 (task #601, not Ryan's notes; v2 was not shown to him): L6 the last one standing runs out of frame for 1.4 s before he is seated (the room reads empty).
notes: Agent frame check of v1 (task #601, not Ryan's notes; v1 was not shown to him): L1 the kill-beat camera loses the guard for the last 0.8 s; L3 the scope holds 2 s on empty lava after the drop; L5 the bust cuts off the top of his head; L6 the PC brawl ran untaped and diverged from the smoke (an empty room before the seat).
pad: 0.2
| line | clip | in | len | fit | speed | text | card |
| L1 | cuts/01_v4.mp4 | 0 | 2.5 | wait | | Heres how i fixed the worst part about my game | |
| L2 | cuts/02_v4.mp4 | 0 | 6.4 | line | | In my game, youre either the sniper in the gaurd tower, or youre running an obsticle course to become the sniper. | |
| L3 | cuts/03_v4.mp4 | 0.2 | 4.4 | line | | but this has a problem, whos the sniper first? i wanted it to be earned | |
| L4 | cuts/04_v4.mp4 | 0 | 19.5 | line | | so, i implemented a race, every player does the course with no sniper, and the first one to complete it gets to be the sniper. this, was the worst part of my game. it wasnt fun, everyone was the same speed, and it took to long | |
| L5 | cuts/04_v4.mp4 | cont | | line | | so how did i fix it? | |
| L6 | cuts/06_v4.mp4 | 0 | 14.65 | line | | instead of everyone running to the tower, everyone starts in the tower, and the way you get to be the sniper, is to be the last one standing in it. so now, instead of a long drawn out boring race, its a fast, chaotic, brawl to see who goes first | |
| end | title | | 1.75 | | | beta signup in bio | |

## script v5
from: v4
notes: Ryan on n2 (v4, task #601): "for the shove one, the gameplay of the shove minigame is super weird because of the way the bots behave, and its unclear thats whats happening. change the minigame so instead of everyone facing away, everyone starts closer to the edge facing in. that can be an actual gameplay change. then record that instead"
notes: Ryan on n1 (v3, task #601): "for 9, shot one, should only be the shove and the cinematic, not the going into the portal at all. the next two shots are fine, the shot of the player can just be removed. then, why is the last shot not from the perspective of a player? and also, why do the player charactes look like that in game? we made such a detailed model, what the fuck is going on? is the branch youre on not useing the most up to date game?"
notes: Agent frame check of v2 (task #601, not Ryan's notes; v2 was not shown to him): L6 the last one standing runs out of frame for 1.4 s before he is seated (the room reads empty).
notes: Agent frame check of v1 (task #601, not Ryan's notes; v1 was not shown to him): L1 the kill-beat camera loses the guard for the last 0.8 s; L3 the scope holds 2 s on empty lava after the drop; L5 the bust cuts off the top of his head; L6 the PC brawl ran untaped and diverged from the smoke (an empty room before the seat).
pad: 0.2
| line | clip | in | len | fit | speed | text | card |
| L1 | cuts/01_v4.mp4 | 0 | 2.5 | wait | | Heres how i fixed the worst part about my game | |
| L2 | cuts/02_v4.mp4 | 0 | 6.4 | line | | In my game, youre either the sniper in the gaurd tower, or youre running an obsticle course to become the sniper. | |
| L3 | cuts/03_v4.mp4 | 0.2 | 4.4 | line | | but this has a problem, whos the sniper first? i wanted it to be earned | |
| L4 | cuts/04_v4.mp4 | 0 | 19.5 | line | | so, i implemented a race, every player does the course with no sniper, and the first one to complete it gets to be the sniper. this, was the worst part of my game. it wasnt fun, everyone was the same speed, and it took to long | |
| L5 | cuts/04_v4.mp4 | cont | | line | | so how did i fix it? | |
| L6 | cuts/06_v5.mp4 | 0 | 14.65 | line | | instead of everyone running to the tower, everyone starts in the tower, and the way you get to be the sniper, is to be the last one standing in it. so now, instead of a long drawn out boring race, its a fast, chaotic, brawl to see who goes first | |
| end | title | | 1.75 | | | beta signup in bio | |

## script v6
from: v5
notes: Ryan on short 9 (v5, task #601): "short 9 is good, with the one acception that at the end, the very very end, the sniper sits looing at nothing for like a second"
notes: Ryan on n2 (v4, task #601): "for the shove one, the gameplay of the shove minigame is super weird because of the way the bots behave, and its unclear thats whats happening. change the minigame so instead of everyone facing away, everyone starts closer to the edge facing in. that can be an actual gameplay change. then record that instead"
notes: Ryan on n1 (v3, task #601): "for 9, shot one, should only be the shove and the cinematic, not the going into the portal at all. the next two shots are fine, the shot of the player can just be removed. then, why is the last shot not from the perspective of a player? and also, why do the player charactes look like that in game? we made such a detailed model, what the fuck is going on? is the branch youre on not useing the most up to date game?"
notes: Agent frame check of v2 (task #601, not Ryan's notes; v2 was not shown to him): L6 the last one standing runs out of frame for 1.4 s before he is seated (the room reads empty).
notes: Agent frame check of v1 (task #601, not Ryan's notes; v1 was not shown to him): L1 the kill-beat camera loses the guard for the last 0.8 s; L3 the scope holds 2 s on empty lava after the drop; L5 the bust cuts off the top of his head; L6 the PC brawl ran untaped and diverged from the smoke (an empty room before the seat).
pad: 0.2
| line | clip | in | len | fit | speed | text | card |
| L1 | cuts/01_v4.mp4 | 0 | 2.5 | wait | | Heres how i fixed the worst part about my game | |
| L2 | cuts/02_v4.mp4 | 0 | 6.4 | line | | In my game, youre either the sniper in the gaurd tower, or youre running an obsticle course to become the sniper. | |
| L3 | cuts/03_v4.mp4 | 0.2 | 4.4 | line | | but this has a problem, whos the sniper first? i wanted it to be earned | |
| L4 | cuts/04_v4.mp4 | 0 | 19.5 | line | | so, i implemented a race, every player does the course with no sniper, and the first one to complete it gets to be the sniper. this, was the worst part of my game. it wasnt fun, everyone was the same speed, and it took to long | |
| L5 | cuts/04_v4.mp4 | cont | | line | | so how did i fix it? | |
| L6 | cuts/06_v6.mp4 | 0 | 14.65 | line | | instead of everyone running to the tower, everyone starts in the tower, and the way you get to be the sniper, is to be the last one standing in it. so now, instead of a long drawn out boring race, its a fast, chaotic, brawl to see who goes first | |
| end | title | | 1.75 | | | beta signup in bio | |

## script v7
from: v6
notes: Ryan on short 9 (v6, task #601): "for the minigame short, two things, one the host of the running in the forest is too long, and we need to break it up with a second shot. dealers choice. tow, the sniper keeps trcaking, but theyre not standing where a sniper would stand, and when they do shoot its through the column of the tower. the death animation, in the gray space, is still fucking shit, becuase the model is blood red like they are in he.l. you already did this one successfully i have no idea what youre problem is. other than that its good."
notes: Ryan on short 9 (v5, task #601): "short 9 is good, with the one acception that at the end, the very very end, the sniper sits looing at nothing for like a second"
notes: Ryan on n2 (v4, task #601): "for the shove one, the gameplay of the shove minigame is super weird because of the way the bots behave, and its unclear thats whats happening. change the minigame so instead of everyone facing away, everyone starts closer to the edge facing in. that can be an actual gameplay change. then record that instead"
notes: Ryan on n1 (v3, task #601): "for 9, shot one, should only be the shove and the cinematic, not the going into the portal at all. the next two shots are fine, the shot of the player can just be removed. then, why is the last shot not from the perspective of a player? and also, why do the player charactes look like that in game? we made such a detailed model, what the fuck is going on? is the branch youre on not useing the most up to date game?"
notes: Agent frame check of v2 (task #601, not Ryan's notes; v2 was not shown to him): L6 the last one standing runs out of frame for 1.4 s before he is seated (the room reads empty).
notes: Agent frame check of v1 (task #601, not Ryan's notes; v1 was not shown to him): L1 the kill-beat camera loses the guard for the last 0.8 s; L3 the scope holds 2 s on empty lava after the drop; L5 the bust cuts off the top of his head; L6 the PC brawl ran untaped and diverged from the smoke (an empty room before the seat).
pad: 0.2
| line | clip | in | len | fit | speed | text | card |
| L1 | cuts/01_v4.mp4 | 0 | 2.5 | wait | | Heres how i fixed the worst part about my game | |
| L2 | cuts/02_v4.mp4 | 0 | 6.4 | line | | In my game, youre either the sniper in the gaurd tower, or youre running an obsticle course to become the sniper. | |
| L3 | cuts/03_v7.mp4@0:1.9,cuts/03_v7.mp4@2.6:1.0,cuts/03_v7.mp4@4.25:1.6 | 0 | | line | | but this has a problem, whos the sniper first? i wanted it to be earned | |
| L4 | cuts/04_v4.mp4@0:6.4,cuts/07_v7.mp4 | 0 | | line | | so, i implemented a race, every player does the course with no sniper, and the first one to complete it gets to be the sniper. this, was the worst part of my game. it wasnt fun, everyone was the same speed, and it took to long | |
| L5 | cuts/04_v4.mp4@0:6.4,cuts/07_v7.mp4 | cont | | line | | so how did i fix it? | |
| L6 | cuts/06_v7.mp4 | 0 | 14.65 | line | | instead of everyone running to the tower, everyone starts in the tower, and the way you get to be the sniper, is to be the last one standing in it. so now, instead of a long drawn out boring race, its a fast, chaotic, brawl to see who goes first | |
| end | title | | 1.75 | | | beta signup in bio | |

## script v8
from: v7
notes: Head frame check of v7 (task #601, not Ryan's notes; v7 was not shown to him): L3 a tower jamb/column edge stands in the right side of the scope for the first ~1.2 s; no tower column or jamb may be inside the scope circle at any frame of the row.
notes: Ryan on short 9 (v6, task #601): "for the minigame short, two things, one the host of the running in the forest is too long, and we need to break it up with a second shot. dealers choice. tow, the sniper keeps trcaking, but theyre not standing where a sniper would stand, and when they do shoot its through the column of the tower. the death animation, in the gray space, is still fucking shit, becuase the model is blood red like they are in he.l. you already did this one successfully i have no idea what youre problem is. other than that its good."
notes: Ryan on short 9 (v5, task #601): "short 9 is good, with the one acception that at the end, the very very end, the sniper sits looing at nothing for like a second"
notes: Ryan on n2 (v4, task #601): "for the shove one, the gameplay of the shove minigame is super weird because of the way the bots behave, and its unclear thats whats happening. change the minigame so instead of everyone facing away, everyone starts closer to the edge facing in. that can be an actual gameplay change. then record that instead"
notes: Ryan on n1 (v3, task #601): "for 9, shot one, should only be the shove and the cinematic, not the going into the portal at all. the next two shots are fine, the shot of the player can just be removed. then, why is the last shot not from the perspective of a player? and also, why do the player charactes look like that in game? we made such a detailed model, what the fuck is going on? is the branch youre on not useing the most up to date game?"
notes: Agent frame check of v2 (task #601, not Ryan's notes; v2 was not shown to him): L6 the last one standing runs out of frame for 1.4 s before he is seated (the room reads empty).
notes: Agent frame check of v1 (task #601, not Ryan's notes; v1 was not shown to him): L1 the kill-beat camera loses the guard for the last 0.8 s; L3 the scope holds 2 s on empty lava after the drop; L5 the bust cuts off the top of his head; L6 the PC brawl ran untaped and diverged from the smoke (an empty room before the seat).
pad: 0.2
| line | clip | in | len | fit | speed | text | card |
| L1 | cuts/01_v4.mp4 | 0 | 2.5 | wait | | Heres how i fixed the worst part about my game | |
| L2 | cuts/02_v4.mp4 | 0 | 6.4 | line | | In my game, youre either the sniper in the gaurd tower, or youre running an obsticle course to become the sniper. | |
| L3 | cuts/03_v8.mp4@0.65:1.8,cuts/03_v8.mp4@4.8:1.7,cuts/03_v8.mp4@9.1:0.75,cuts/03_v8.mp4@10.35:0.35 | 0 | | line | | but this has a problem, whos the sniper first? i wanted it to be earned | |
| L4 | cuts/04_v4.mp4@0:6.4,cuts/07_v7.mp4 | 0 | | line | | so, i implemented a race, every player does the course with no sniper, and the first one to complete it gets to be the sniper. this, was the worst part of my game. it wasnt fun, everyone was the same speed, and it took to long | |
| L5 | cuts/04_v4.mp4@0:6.4,cuts/07_v7.mp4 | cont | | line | | so how did i fix it? | |
| L6 | cuts/06_v7.mp4 | 0 | 14.65 | line | | instead of everyone running to the tower, everyone starts in the tower, and the way you get to be the sniper, is to be the last one standing in it. so now, instead of a long drawn out boring race, its a fast, chaotic, brawl to see who goes first | |
| end | title | | 1.75 | | | beta signup in bio | |

## script v9
from: v8
notes: Head frame check of v8 (task #601, not Ryan's notes; v8 was not shown to him): L3 the scope zoomed to 0.09 from the 295 window, the circle a wall of lava texture with a tiny runner at the bottom; not a sniper shot. v9: L3 at the shipped zoom from the 340 window, the runner off the last platform and at the finish, no column in the circle.
notes: Head frame check of v7 (task #601, not Ryan's notes; v7 was not shown to him): L3 a tower jamb/column edge stands in the right side of the scope for the first ~1.2 s; no tower column or jamb may be inside the scope circle at any frame of the row.
notes: Ryan on short 9 (v6, task #601): "for the minigame short, two things, one the host of the running in the forest is too long, and we need to break it up with a second shot. dealers choice. tow, the sniper keeps trcaking, but theyre not standing where a sniper would stand, and when they do shoot its through the column of the tower. the death animation, in the gray space, is still fucking shit, becuase the model is blood red like they are in he.l. you already did this one successfully i have no idea what youre problem is. other than that its good."
notes: Ryan on short 9 (v5, task #601): "short 9 is good, with the one acception that at the end, the very very end, the sniper sits looing at nothing for like a second"
notes: Ryan on n2 (v4, task #601): "for the shove one, the gameplay of the shove minigame is super weird because of the way the bots behave, and its unclear thats whats happening. change the minigame so instead of everyone facing away, everyone starts closer to the edge facing in. that can be an actual gameplay change. then record that instead"
notes: Ryan on n1 (v3, task #601): "for 9, shot one, should only be the shove and the cinematic, not the going into the portal at all. the next two shots are fine, the shot of the player can just be removed. then, why is the last shot not from the perspective of a player? and also, why do the player charactes look like that in game? we made such a detailed model, what the fuck is going on? is the branch youre on not useing the most up to date game?"
notes: Agent frame check of v2 (task #601, not Ryan's notes; v2 was not shown to him): L6 the last one standing runs out of frame for 1.4 s before he is seated (the room reads empty).
notes: Agent frame check of v1 (task #601, not Ryan's notes; v1 was not shown to him): L1 the kill-beat camera loses the guard for the last 0.8 s; L3 the scope holds 2 s on empty lava after the drop; L5 the bust cuts off the top of his head; L6 the PC brawl ran untaped and diverged from the smoke (an empty room before the seat).
pad: 0.2
| line | clip | in | len | fit | speed | text | card |
| L1 | cuts/01_v4.mp4 | 0 | 2.5 | wait | | Heres how i fixed the worst part about my game | |
| L2 | cuts/02_v4.mp4 | 0 | 6.4 | line | | In my game, youre either the sniper in the gaurd tower, or youre running an obsticle course to become the sniper. | |
| L3 | cuts/03_v9.mp4 | 0 | | line | | but this has a problem, whos the sniper first? i wanted it to be earned | |
| L4 | cuts/04_v4.mp4@0:6.4,cuts/07_v7.mp4 | 0 | | line | | so, i implemented a race, every player does the course with no sniper, and the first one to complete it gets to be the sniper. this, was the worst part of my game. it wasnt fun, everyone was the same speed, and it took to long | |
| L5 | cuts/04_v4.mp4@0:6.4,cuts/07_v7.mp4 | cont | | line | | so how did i fix it? | |
| L6 | cuts/06_v7.mp4 | 0 | 14.65 | line | | instead of everyone running to the tower, everyone starts in the tower, and the way you get to be the sniper, is to be the last one standing in it. so now, instead of a long drawn out boring race, its a fast, chaotic, brawl to see who goes first | |
| end | title | | 1.75 | | | beta signup in bio | |

## script v10
from: v9
notes: Ryan on short 9 (v9, task #601): "for short 9. why the hell did anything change prior to the forest run. and for the fucking too boring forest section, you just added a fucking cut with the exact same footage with the fucking guys moved around? is that  fucking joke? this isnt a fucking pipeline issue what the fuck is wrong with you? and holy fuck, youre example of the bad death animation is now useing the fucking physics. literally just use, for only this one clip, the one i liked from the previous versions. other than that ists good. short 11 is good"
notes: Head frame check of v8 (task #601, not Ryan's notes; v8 was not shown to him): L3 the scope zoomed to 0.09 from the 295 window, the circle a wall of lava texture with a tiny runner at the bottom; not a sniper shot. v9: L3 at the shipped zoom from the 340 window, the runner off the last platform and at the finish, no column in the circle.
notes: Head frame check of v7 (task #601, not Ryan's notes; v7 was not shown to him): L3 a tower jamb/column edge stands in the right side of the scope for the first ~1.2 s; no tower column or jamb may be inside the scope circle at any frame of the row.
notes: Ryan on short 9 (v6, task #601): "for the minigame short, two things, one the host of the running in the forest is too long, and we need to break it up with a second shot. dealers choice. tow, the sniper keeps trcaking, but theyre not standing where a sniper would stand, and when they do shoot its through the column of the tower. the death animation, in the gray space, is still fucking shit, becuase the model is blood red like they are in he.l. you already did this one successfully i have no idea what youre problem is. other than that its good."
notes: Ryan on short 9 (v5, task #601): "short 9 is good, with the one acception that at the end, the very very end, the sniper sits looing at nothing for like a second"
notes: Ryan on n2 (v4, task #601): "for the shove one, the gameplay of the shove minigame is super weird because of the way the bots behave, and its unclear thats whats happening. change the minigame so instead of everyone facing away, everyone starts closer to the edge facing in. that can be an actual gameplay change. then record that instead"
notes: Ryan on n1 (v3, task #601): "for 9, shot one, should only be the shove and the cinematic, not the going into the portal at all. the next two shots are fine, the shot of the player can just be removed. then, why is the last shot not from the perspective of a player? and also, why do the player charactes look like that in game? we made such a detailed model, what the fuck is going on? is the branch youre on not useing the most up to date game?"
notes: Agent frame check of v2 (task #601, not Ryan's notes; v2 was not shown to him): L6 the last one standing runs out of frame for 1.4 s before he is seated (the room reads empty).
notes: Agent frame check of v1 (task #601, not Ryan's notes; v1 was not shown to him): L1 the kill-beat camera loses the guard for the last 0.8 s; L3 the scope holds 2 s on empty lava after the drop; L5 the bust cuts off the top of his head; L6 the PC brawl ran untaped and diverged from the smoke (an empty room before the seat).
pad: 0.2
| line | clip | in | len | fit | speed | text | card |
| L1 | cuts/01_v4.mp4 | 0 | 2.5 | wait | | Heres how i fixed the worst part about my game | |
| L2 | cuts/02_v4.mp4 | 0 | 6.4 | line | | In my game, youre either the sniper in the gaurd tower, or youre running an obsticle course to become the sniper. | |
| L3 | cuts/03_v4.mp4 | 0.2 | 4.4 | line | | but this has a problem, whos the sniper first? i wanted it to be earned | |
| L4 | cuts/04_v4.mp4@0:6.4,cuts/07_v10.mp4@0:5.0,cuts/04_v4.mp4@11.4 | 0 | | line | | so, i implemented a race, every player does the course with no sniper, and the first one to complete it gets to be the sniper. this, was the worst part of my game. it wasnt fun, everyone was the same speed, and it took to long | |
| L5 | cuts/04_v4.mp4@0:6.4,cuts/07_v10.mp4@0:5.0,cuts/04_v4.mp4@11.4 | cont | | line | | so how did i fix it? | |
| L6 | cuts/06_v7.mp4 | 0 | 14.65 | line | | instead of everyone running to the tower, everyone starts in the tower, and the way you get to be the sniper, is to be the last one standing in it. so now, instead of a long drawn out boring race, its a fast, chaotic, brawl to see who goes first | |
| end | title | | 1.75 | | | beta signup in bio | |

## script v11
from: v10
notes: Ryan on short 9 (v10, task #601): "that death animation you used is not the one i ever signed off on. showing the front side of the same boring footage does not fix it"
notes: Ryan on short 9 (v9, task #601): "for short 9. why the hell did anything change prior to the forest run. and for the fucking too boring forest section, you just added a fucking cut with the exact same footage with the fucking guys moved around? is that  fucking joke? this isnt a fucking pipeline issue what the fuck is wrong with you? and holy fuck, youre example of the bad death animation is now useing the fucking physics. literally just use, for only this one clip, the one i liked from the previous versions. other than that ists good. short 11 is good"
notes: Head frame check of v8 (task #601, not Ryan's notes; v8 was not shown to him): L3 the scope zoomed to 0.09 from the 295 window, the circle a wall of lava texture with a tiny runner at the bottom; not a sniper shot. v9: L3 at the shipped zoom from the 340 window, the runner off the last platform and at the finish, no column in the circle.
notes: Head frame check of v7 (task #601, not Ryan's notes; v7 was not shown to him): L3 a tower jamb/column edge stands in the right side of the scope for the first ~1.2 s; no tower column or jamb may be inside the scope circle at any frame of the row.
notes: Ryan on short 9 (v6, task #601): "for the minigame short, two things, one the host of the running in the forest is too long, and we need to break it up with a second shot. dealers choice. tow, the sniper keeps trcaking, but theyre not standing where a sniper would stand, and when they do shoot its through the column of the tower. the death animation, in the gray space, is still fucking shit, becuase the model is blood red like they are in he.l. you already did this one successfully i have no idea what youre problem is. other than that its good."
notes: Ryan on short 9 (v5, task #601): "short 9 is good, with the one acception that at the end, the very very end, the sniper sits looing at nothing for like a second"
notes: Ryan on n2 (v4, task #601): "for the shove one, the gameplay of the shove minigame is super weird because of the way the bots behave, and its unclear thats whats happening. change the minigame so instead of everyone facing away, everyone starts closer to the edge facing in. that can be an actual gameplay change. then record that instead"
notes: Ryan on n1 (v3, task #601): "for 9, shot one, should only be the shove and the cinematic, not the going into the portal at all. the next two shots are fine, the shot of the player can just be removed. then, why is the last shot not from the perspective of a player? and also, why do the player charactes look like that in game? we made such a detailed model, what the fuck is going on? is the branch youre on not useing the most up to date game?"
notes: Agent frame check of v2 (task #601, not Ryan's notes; v2 was not shown to him): L6 the last one standing runs out of frame for 1.4 s before he is seated (the room reads empty).
notes: Agent frame check of v1 (task #601, not Ryan's notes; v1 was not shown to him): L1 the kill-beat camera loses the guard for the last 0.8 s; L3 the scope holds 2 s on empty lava after the drop; L5 the bust cuts off the top of his head; L6 the PC brawl ran untaped and diverged from the smoke (an empty room before the seat).
pad: 0.2
| line | clip | in | len | fit | speed | text | card |
| L1 | cuts/01_v4.mp4 | 0 | 2.5 | wait | | Heres how i fixed the worst part about my game | |
| L2 | cuts/02_v4.mp4 | 0 | 6.4 | line | | In my game, youre either the sniper in the gaurd tower, or youre running an obsticle course to become the sniper. | |
| L3 | cuts/03_v4.mp4 | 0.2 | 4.4 | line | | but this has a problem, whos the sniper first? i wanted it to be earned | |
| L4 | cuts/04_v4.mp4@0:6.4,cuts/07_v11.mp4@0:5.0,cuts/04_v4.mp4@11.4 | 0 | | line | | so, i implemented a race, every player does the course with no sniper, and the first one to complete it gets to be the sniper. this, was the worst part of my game. it wasnt fun, everyone was the same speed, and it took to long | |
| L5 | cuts/04_v4.mp4@0:6.4,cuts/07_v11.mp4@0:5.0,cuts/04_v4.mp4@11.4 | cont | | line | | so how did i fix it? | |
| L6 | cuts/06_v7.mp4 | 0 | 14.65 | line | | instead of everyone running to the tower, everyone starts in the tower, and the way you get to be the sniper, is to be the last one standing in it. so now, instead of a long drawn out boring race, its a fast, chaotic, brawl to see who goes first | |
| end | title | | 1.75 | | | beta signup in bio | |

## script v12
from: v11
notes: Head 5 fps check of v11 (task #601, not Ryan's notes; v11 was not shown to him): the L4 insert's first ~3 s is an empty lane with the portal in the foreground and nothing moving; the runners appear tiny near the end. v12: the insert's in-point moves later in the same take so the pack is coming down the lane from its first frame.
notes: Ryan on short 9 (v10, task #601): "that death animation you used is not the one i ever signed off on. showing the front side of the same boring footage does not fix it"
notes: Ryan on short 9 (v9, task #601): "for short 9. why the hell did anything change prior to the forest run. and for the fucking too boring forest section, you just added a fucking cut with the exact same footage with the fucking guys moved around? is that  fucking joke? this isnt a fucking pipeline issue what the fuck is wrong with you? and holy fuck, youre example of the bad death animation is now useing the fucking physics. literally just use, for only this one clip, the one i liked from the previous versions. other than that ists good. short 11 is good"
notes: Head frame check of v8 (task #601, not Ryan's notes; v8 was not shown to him): L3 the scope zoomed to 0.09 from the 295 window, the circle a wall of lava texture with a tiny runner at the bottom; not a sniper shot. v9: L3 at the shipped zoom from the 340 window, the runner off the last platform and at the finish, no column in the circle.
notes: Head frame check of v7 (task #601, not Ryan's notes; v7 was not shown to him): L3 a tower jamb/column edge stands in the right side of the scope for the first ~1.2 s; no tower column or jamb may be inside the scope circle at any frame of the row.
notes: Ryan on short 9 (v6, task #601): "for the minigame short, two things, one the host of the running in the forest is too long, and we need to break it up with a second shot. dealers choice. tow, the sniper keeps trcaking, but theyre not standing where a sniper would stand, and when they do shoot its through the column of the tower. the death animation, in the gray space, is still fucking shit, becuase the model is blood red like they are in he.l. you already did this one successfully i have no idea what youre problem is. other than that its good."
notes: Ryan on short 9 (v5, task #601): "short 9 is good, with the one acception that at the end, the very very end, the sniper sits looing at nothing for like a second"
notes: Ryan on n2 (v4, task #601): "for the shove one, the gameplay of the shove minigame is super weird because of the way the bots behave, and its unclear thats whats happening. change the minigame so instead of everyone facing away, everyone starts closer to the edge facing in. that can be an actual gameplay change. then record that instead"
notes: Ryan on n1 (v3, task #601): "for 9, shot one, should only be the shove and the cinematic, not the going into the portal at all. the next two shots are fine, the shot of the player can just be removed. then, why is the last shot not from the perspective of a player? and also, why do the player charactes look like that in game? we made such a detailed model, what the fuck is going on? is the branch youre on not useing the most up to date game?"
notes: Agent frame check of v2 (task #601, not Ryan's notes; v2 was not shown to him): L6 the last one standing runs out of frame for 1.4 s before he is seated (the room reads empty).
notes: Agent frame check of v1 (task #601, not Ryan's notes; v1 was not shown to him): L1 the kill-beat camera loses the guard for the last 0.8 s; L3 the scope holds 2 s on empty lava after the drop; L5 the bust cuts off the top of his head; L6 the PC brawl ran untaped and diverged from the smoke (an empty room before the seat).
pad: 0.2
| line | clip | in | len | fit | speed | text | card |
| L1 | cuts/01_v4.mp4 | 0 | 2.5 | wait | | Heres how i fixed the worst part about my game | |
| L2 | cuts/02_v4.mp4 | 0 | 6.4 | line | | In my game, youre either the sniper in the gaurd tower, or youre running an obsticle course to become the sniper. | |
| L3 | cuts/03_v4.mp4 | 0.2 | 4.4 | line | | but this has a problem, whos the sniper first? i wanted it to be earned | |
| L4 | cuts/04_v4.mp4@0:6.4,cuts/07_v12.mp4@0:5.0,cuts/04_v4.mp4@11.4 | 0 | | line | | so, i implemented a race, every player does the course with no sniper, and the first one to complete it gets to be the sniper. this, was the worst part of my game. it wasnt fun, everyone was the same speed, and it took to long | |
| L5 | cuts/04_v4.mp4@0:6.4,cuts/07_v12.mp4@0:5.0,cuts/04_v4.mp4@11.4 | cont | | line | | so how did i fix it? | |
| L6 | cuts/06_v7.mp4 | 0 | 14.65 | line | | instead of everyone running to the tower, everyone starts in the tower, and the way you get to be the sniper, is to be the last one standing in it. so now, instead of a long drawn out boring race, its a fast, chaotic, brawl to see who goes first | |
| end | title | | 1.75 | | | beta signup in bio | |

## script v13
from: v11
notes: Ryan on short 9 (v11, task #601): "very impressed"; his recorded voice (short_13.aup4) replaces the TTS, the end card is beta_link.wav (0.98 s).
notes: Ryan on short 9 (v10, task #601): "that death animation you used is not the one i ever signed off on. showing the front side of the same boring footage does not fix it"
notes: Ryan on short 9 (v9, task #601): "for short 9. why the hell did anything change prior to the forest run. and for the fucking too boring forest section, you just added a fucking cut with the exact same footage with the fucking guys moved around? is that  fucking joke? this isnt a fucking pipeline issue what the fuck is wrong with you? and holy fuck, youre example of the bad death animation is now useing the fucking physics. literally just use, for only this one clip, the one i liked from the previous versions. other than that ists good. short 11 is good"
notes: Head frame check of v8 (task #601, not Ryan's notes; v8 was not shown to him): L3 the scope zoomed to 0.09 from the 295 window, the circle a wall of lava texture with a tiny runner at the bottom; not a sniper shot. v9: L3 at the shipped zoom from the 340 window, the runner off the last platform and at the finish, no column in the circle.
notes: Head frame check of v7 (task #601, not Ryan's notes; v7 was not shown to him): L3 a tower jamb/column edge stands in the right side of the scope for the first ~1.2 s; no tower column or jamb may be inside the scope circle at any frame of the row.
notes: Ryan on short 9 (v6, task #601): "for the minigame short, two things, one the host of the running in the forest is too long, and we need to break it up with a second shot. dealers choice. tow, the sniper keeps trcaking, but theyre not standing where a sniper would stand, and when they do shoot its through the column of the tower. the death animation, in the gray space, is still fucking shit, becuase the model is blood red like they are in he.l. you already did this one successfully i have no idea what youre problem is. other than that its good."
notes: Ryan on short 9 (v5, task #601): "short 9 is good, with the one acception that at the end, the very very end, the sniper sits looing at nothing for like a second"
notes: Ryan on n2 (v4, task #601): "for the shove one, the gameplay of the shove minigame is super weird because of the way the bots behave, and its unclear thats whats happening. change the minigame so instead of everyone facing away, everyone starts closer to the edge facing in. that can be an actual gameplay change. then record that instead"
notes: Ryan on n1 (v3, task #601): "for 9, shot one, should only be the shove and the cinematic, not the going into the portal at all. the next two shots are fine, the shot of the player can just be removed. then, why is the last shot not from the perspective of a player? and also, why do the player charactes look like that in game? we made such a detailed model, what the fuck is going on? is the branch youre on not useing the most up to date game?"
notes: Agent frame check of v2 (task #601, not Ryan's notes; v2 was not shown to him): L6 the last one standing runs out of frame for 1.4 s before he is seated (the room reads empty).
notes: Agent frame check of v1 (task #601, not Ryan's notes; v1 was not shown to him): L1 the kill-beat camera loses the guard for the last 0.8 s; L3 the scope holds 2 s on empty lava after the drop; L5 the bust cuts off the top of his head; L6 the PC brawl ran untaped and diverged from the smoke (an empty room before the seat).
pad: 0.2
| line | clip | in | len | fit | speed | text | card |
| L1 | cuts/01_v4.mp4 | 0 | 2.5 | wait | | Heres how i fixed the worst part about my game | |
| L2 | cuts/02_v4.mp4 | 0 | 6.4 | line | | In my game, youre either the sniper in the gaurd tower, or youre running an obsticle course to become the sniper. | |
| L3 | cuts/03_v4.mp4 | 0.2 | 4.4 | line | | but this has a problem, whos the sniper first? i wanted it to be earned | |
| L4 | cuts/04_v4.mp4@0:6.4,cuts/07_v11.mp4@0:5.0,cuts/04_v4.mp4@11.4 | 0 | | line | | so, i implemented a race, every player does the course with no sniper, and the first one to complete it gets to be the sniper. this, was the worst part of my game. it wasnt fun, everyone was the same speed, and it took to long | |
| L5 | cuts/04_v4.mp4@0:6.4,cuts/07_v11.mp4@0:5.0,cuts/04_v4.mp4@11.4 | cont | | line | | so how did i fix it? | |
| L6 | cuts/06_v7.mp4@0:14.65,cuts/03_v4.mp4@0.2:2.0 | 0 | | line | | instead of everyone running to the tower, everyone starts in the tower, and the way you get to be the sniper, is to be the last one standing in it. so now, instead of a long drawn out boring race, its a fast, chaotic, brawl to see who goes first. and the last one standing gets the rifle | |
| end | title | | | line | | beta link in bio | beta signup in bio |

## script v14
from: v13
notes: Ryan (19:46, on start_minigame_final_ttig/youtube, task #601): "when i say everyone in minigame, its volume goes to fuckign zero." Ryan (19:52): "no, dont just fix that little thing, figure out why the fuck that happened and do the audio mixing properly". Ryan (19:56): "weve fucking done this before ... dont we have a full fucking short pipeline". Cause: vo.py duck_breaths gain-ducked by whisper word times, and whisper put "everyone" (~28.4 s) late. v14 (TikTok/IG) = v13; v15 (YouTube) = v13 with the YouTube end card line; voice re-run through vo.py with the energy-gated breath duck and --outro per platform.
notes: Ryan on short 9 (v11, task #601): "very impressed"; his recorded voice (short_13.aup4) replaces the TTS, the end card is beta_link.wav (0.98 s).
notes: Ryan on short 9 (v10, task #601): "that death animation you used is not the one i ever signed off on. showing the front side of the same boring footage does not fix it"
notes: Ryan on short 9 (v9, task #601): "for short 9. why the hell did anything change prior to the forest run. and for the fucking too boring forest section, you just added a fucking cut with the exact same footage with the fucking guys moved around? is that  fucking joke? this isnt a fucking pipeline issue what the fuck is wrong with you? and holy fuck, youre example of the bad death animation is now useing the fucking physics. literally just use, for only this one clip, the one i liked from the previous versions. other than that ists good. short 11 is good"
notes: Head frame check of v8 (task #601, not Ryan's notes; v8 was not shown to him): L3 the scope zoomed to 0.09 from the 295 window, the circle a wall of lava texture with a tiny runner at the bottom; not a sniper shot. v9: L3 at the shipped zoom from the 340 window, the runner off the last platform and at the finish, no column in the circle.
notes: Head frame check of v7 (task #601, not Ryan's notes; v7 was not shown to him): L3 a tower jamb/column edge stands in the right side of the scope for the first ~1.2 s; no tower column or jamb may be inside the scope circle at any frame of the row.
notes: Ryan on short 9 (v6, task #601): "for the minigame short, two things, one the host of the running in the forest is too long, and we need to break it up with a second shot. dealers choice. tow, the sniper keeps trcaking, but theyre not standing where a sniper would stand, and when they do shoot its through the column of the tower. the death animation, in the gray space, is still fucking shit, becuase the model is blood red like they are in he.l. you already did this one successfully i have no idea what youre problem is. other than that its good."
notes: Ryan on short 9 (v5, task #601): "short 9 is good, with the one acception that at the end, the very very end, the sniper sits looing at nothing for like a second"
notes: Ryan on n2 (v4, task #601): "for the shove one, the gameplay of the shove minigame is super weird because of the way the bots behave, and its unclear thats whats happening. change the minigame so instead of everyone facing away, everyone starts closer to the edge facing in. that can be an actual gameplay change. then record that instead"
notes: Ryan on n1 (v3, task #601): "for 9, shot one, should only be the shove and the cinematic, not the going into the portal at all. the next two shots are fine, the shot of the player can just be removed. then, why is the last shot not from the perspective of a player? and also, why do the player charactes look like that in game? we made such a detailed model, what the fuck is going on? is the branch youre on not useing the most up to date game?"
notes: Agent frame check of v2 (task #601, not Ryan's notes; v2 was not shown to him): L6 the last one standing runs out of frame for 1.4 s before he is seated (the room reads empty).
notes: Agent frame check of v1 (task #601, not Ryan's notes; v1 was not shown to him): L1 the kill-beat camera loses the guard for the last 0.8 s; L3 the scope holds 2 s on empty lava after the drop; L5 the bust cuts off the top of his head; L6 the PC brawl ran untaped and diverged from the smoke (an empty room before the seat).
pad: 0.2
| line | clip | in | len | fit | speed | text | card |
| L1 | cuts/01_v4.mp4 | 0 | 2.5 | wait | | Heres how i fixed the worst part about my game | |
| L2 | cuts/02_v4.mp4 | 0 | 6.4 | line | | In my game, youre either the sniper in the gaurd tower, or youre running an obsticle course to become the sniper. | |
| L3 | cuts/03_v4.mp4 | 0.2 | 4.4 | line | | but this has a problem, whos the sniper first? i wanted it to be earned | |
| L4 | cuts/04_v4.mp4@0:6.4,cuts/07_v11.mp4@0:5.0,cuts/04_v4.mp4@11.4 | 0 | | line | | so, i implemented a race, every player does the course with no sniper, and the first one to complete it gets to be the sniper. this, was the worst part of my game. it wasnt fun, everyone was the same speed, and it took to long | |
| L5 | cuts/04_v4.mp4@0:6.4,cuts/07_v11.mp4@0:5.0,cuts/04_v4.mp4@11.4 | cont | | line | | so how did i fix it? | |
| L6 | cuts/06_v7.mp4@0:14.65,cuts/03_v4.mp4@0.2:2.0 | 0 | | line | | instead of everyone running to the tower, everyone starts in the tower, and the way you get to be the sniper, is to be the last one standing in it. so now, instead of a long drawn out boring race, its a fast, chaotic, brawl to see who goes first. and the last one standing gets the rifle | |
| end | title | | | line | | beta link in bio | beta signup in bio |

## script v15
from: v13
notes: Ryan (19:46, on start_minigame_final_ttig/youtube, task #601): "when i say everyone in minigame, its volume goes to fuckign zero." Ryan (19:52): "no, dont just fix that little thing, figure out why the fuck that happened and do the audio mixing properly". Ryan (19:56): "weve fucking done this before ... dont we have a full fucking short pipeline". Cause: vo.py duck_breaths gain-ducked by whisper word times, and whisper put "everyone" (~28.4 s) late. v14 (TikTok/IG) = v13; v15 (YouTube) = v13 with the YouTube end card line; voice re-run through vo.py with the energy-gated breath duck and --outro per platform.
notes: Ryan on short 9 (v11, task #601): "very impressed"; his recorded voice (short_13.aup4) replaces the TTS, the end card is beta_link.wav (0.98 s).
notes: Ryan on short 9 (v10, task #601): "that death animation you used is not the one i ever signed off on. showing the front side of the same boring footage does not fix it"
notes: Ryan on short 9 (v9, task #601): "for short 9. why the hell did anything change prior to the forest run. and for the fucking too boring forest section, you just added a fucking cut with the exact same footage with the fucking guys moved around? is that  fucking joke? this isnt a fucking pipeline issue what the fuck is wrong with you? and holy fuck, youre example of the bad death animation is now useing the fucking physics. literally just use, for only this one clip, the one i liked from the previous versions. other than that ists good. short 11 is good"
notes: Head frame check of v8 (task #601, not Ryan's notes; v8 was not shown to him): L3 the scope zoomed to 0.09 from the 295 window, the circle a wall of lava texture with a tiny runner at the bottom; not a sniper shot. v9: L3 at the shipped zoom from the 340 window, the runner off the last platform and at the finish, no column in the circle.
notes: Head frame check of v7 (task #601, not Ryan's notes; v7 was not shown to him): L3 a tower jamb/column edge stands in the right side of the scope for the first ~1.2 s; no tower column or jamb may be inside the scope circle at any frame of the row.
notes: Ryan on short 9 (v6, task #601): "for the minigame short, two things, one the host of the running in the forest is too long, and we need to break it up with a second shot. dealers choice. tow, the sniper keeps trcaking, but theyre not standing where a sniper would stand, and when they do shoot its through the column of the tower. the death animation, in the gray space, is still fucking shit, becuase the model is blood red like they are in he.l. you already did this one successfully i have no idea what youre problem is. other than that its good."
notes: Ryan on short 9 (v5, task #601): "short 9 is good, with the one acception that at the end, the very very end, the sniper sits looing at nothing for like a second"
notes: Ryan on n2 (v4, task #601): "for the shove one, the gameplay of the shove minigame is super weird because of the way the bots behave, and its unclear thats whats happening. change the minigame so instead of everyone facing away, everyone starts closer to the edge facing in. that can be an actual gameplay change. then record that instead"
notes: Ryan on n1 (v3, task #601): "for 9, shot one, should only be the shove and the cinematic, not the going into the portal at all. the next two shots are fine, the shot of the player can just be removed. then, why is the last shot not from the perspective of a player? and also, why do the player charactes look like that in game? we made such a detailed model, what the fuck is going on? is the branch youre on not useing the most up to date game?"
notes: Agent frame check of v2 (task #601, not Ryan's notes; v2 was not shown to him): L6 the last one standing runs out of frame for 1.4 s before he is seated (the room reads empty).
notes: Agent frame check of v1 (task #601, not Ryan's notes; v1 was not shown to him): L1 the kill-beat camera loses the guard for the last 0.8 s; L3 the scope holds 2 s on empty lava after the drop; L5 the bust cuts off the top of his head; L6 the PC brawl ran untaped and diverged from the smoke (an empty room before the seat).
pad: 0.2
| line | clip | in | len | fit | speed | text | card |
| L1 | cuts/01_v4.mp4 | 0 | 2.5 | wait | | Heres how i fixed the worst part about my game | |
| L2 | cuts/02_v4.mp4 | 0 | 6.4 | line | | In my game, youre either the sniper in the gaurd tower, or youre running an obsticle course to become the sniper. | |
| L3 | cuts/03_v4.mp4 | 0.2 | 4.4 | line | | but this has a problem, whos the sniper first? i wanted it to be earned | |
| L4 | cuts/04_v4.mp4@0:6.4,cuts/07_v11.mp4@0:5.0,cuts/04_v4.mp4@11.4 | 0 | | line | | so, i implemented a race, every player does the course with no sniper, and the first one to complete it gets to be the sniper. this, was the worst part of my game. it wasnt fun, everyone was the same speed, and it took to long | |
| L5 | cuts/04_v4.mp4@0:6.4,cuts/07_v11.mp4@0:5.0,cuts/04_v4.mp4@11.4 | cont | | line | | so how did i fix it? | |
| L6 | cuts/06_v7.mp4@0:14.65,cuts/03_v4.mp4@0.2:2.0 | 0 | | line | | instead of everyone running to the tower, everyone starts in the tower, and the way you get to be the sniper, is to be the last one standing in it. so now, instead of a long drawn out boring race, its a fast, chaotic, brawl to see who goes first. and the last one standing gets the rifle | |
| end | title | | | line | | beta sign up on my channel | beta signup on my channel |
