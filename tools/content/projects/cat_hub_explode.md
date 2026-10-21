# cat_hub_explode
kind: short
aspect: 9:16
voice: no

## 1
said: Ryan (2026-10-21, task #688): "ok now get a clip in the hub, of a player who spawns in, grabs a cat, pets it like 4 times over the course of a second, waits half a second, then throws it, the video ends when the explosion does". POV from HubSpawns/Spawn1 (32.82, 0.25, -3.45, facing -x), walk 10.9 m straight to Cat6 (19.70, 0.35, -3.47, dead ahead), shove = pick it up, E x4 over 1.0 s (hearts), 0.5 s, shove = throw at -x; HubCat explodes 0.5 s later in frame; the cut runs from the spawn to the blast's last frame. Game audio kept; no captions, music or card.
capture: --shot=s3_open_lane --stage=cat_hub_explode --bots=1 --seed=20261021
expect: pickup Cat6 2.2-2.6; pet n1 +0.15-0.3; pet n4 +1.15-1.3; throw Cat6 +1.6-1.8; explode in_frame +2.1-2.4; boom_end Cat6 +3.1-3.5; pet hearts_in_frame1; lens_cover <= 0.5
seconds: 5.05
in: 0.6
file: cat_hub_explode

## 2
said: Ryan (task #688, n1 notes): "press e to pet cat should use an icon for the e key ... slightly below the corsshair ... and it hsould be in the clip"; "and refilm the cat clip in the forest"; "and dont have it toss the cat right in front of it, after it pets, have it look over and slighty up into the pit to throw it". ## 1's beats on forest: Runner_1 from its match start (8.6 deg r 53.88), a cat.tscn spawned at cast (2.3 deg r 49.50; probed: walk floor 23.00 the whole 5.2 m, pit lip slopes from 3.0 m inward and drops past 4.5 m), grab, E x4 over 1.0 s (hearts, keycap prompt under the crosshair), then a 56 deg eased turn toward the axis with the eyes 8 deg up inside the 0.5 s, throw; the blast is over the pit (r 44.5), in frame; the cut ends on its last frame.
capture: --shot=s3_open_lane --stage=cat_hub_explode --map=forest --pov=runner --bots=1 --shimmer=0 --seed=20261021 --set=side=-1;ahead=6
expect: pickup Cat1 1.6-1.9; pet prompt; pet n1 +0.15-0.3; pet n4 +1.15-1.3; throw Cat1 +1.6-1.8; explode in_frame +2.1-2.4; boom_end Cat1 +3.2-3.4; pet hearts_in_frame1; alive Runner_1; lens_cover <= 0.5
seconds: 4.39
in: 0.65
file: cat_forest_explode

## 3
said: Ryan (task #688): "start a version of the clip where it has more breathing room, the walk up to the cat is the same, but we look at it for .5 seconds longer, we pick it up, wait half a second, pet it 6 times, spread across 2 seconds, look over into the pit, wait half a second, pet it twice more over .5 seconds, then throw it and it plays out the same". ## 2 with look_extra 0.5, lead 0.5, 6 pets over 2.0 s, the turn to the pit (measured off the body when the pets end, 0.4 s), 0.5 s, 2 pets over 0.5 s, throw 0.3 s after; blast over the pit (r 43.7), in frame; the cut ends on its last frame.
capture: --shot=s3_open_lane --stage=cat_hub_explode --map=forest --pov=runner --bots=1 --shimmer=0 --seed=20261021 --set=side=-1;ahead=6;look_extra=0.5;lead=0.5;pets=6;span=2.0;pets2=2;span2=0.5;gap2=0.5;turn_s=0.4;wait2=0.25
expect: pickup Cat1 2.1-2.4; pet prompt; pet n1 +0.45-0.6; pet n6 +2.45-2.6; pet n8 +3.85-4.0; throw Cat1 +4.15-4.3; explode in_frame +4.65-4.85; boom_end Cat1 +5.7-5.9; alive Runner_1; lens_cover <= 0.5
seconds: 7.39
in: 0.65
file: cat_forest_explode_long
