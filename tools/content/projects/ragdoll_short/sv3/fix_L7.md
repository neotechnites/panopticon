# L7 fix for v24 (task #630)

Head: append this as the next ## entry of projects/ragdoll_short.md (filmed as temp entry 167) and repoint L7 in ## script v24. Ryan on v23: "when the gaurd is hoved, they freak out".

Cause, fixed in the game (f0b18e2c, scripts/player/death_ragdoll.gd + prisoner_avatar.gd): thrown flat at 23 m/s, the guard's legs catch the window sill (r 6.84, top ~27.7 m); the Godot solver let that hit tear the joints up to 3.45 m apart and every part spun at the 15 rad/s cap for ~1 s (the flail). Now: joint projection puts a torn part back on its joint, and each part's spin is held within 6 rad/s of the whole body's spin, so the body tumbles over the sill as one; a limp body also drops the rifle-hold pose. Mac trace, same tape: limb spin against the body 12.4 -> 2.5 rad/s (first 1.2 s), worst joint gap 3.45 -> 0.15 m; he leaves through the window and is at r ~27 when the beat ends, 19 m short of the pit wall.

## 167
said: L7 (v24, Ryan on v23: "when the gaurd is hoved, they freak out"): pov runner makes it through the portal, shoves, and the usual cinematic shot -- finale with fix_L7 v23's numbers on the fixed ragdoll: the run into the portal, the arrival (2.13), the walk up and the shove (3.67), the kill-beat cinematic held 3.2 s so the cut ends on it; the guard flips over the window sill and tumbles out as one limp body, spread out, down into the pit short of the pit wall
capture: --shot=s3_open_lane --stage=finale --pov=runner --bots=3 --shimmer=0 --seed=20261012 --set=lead=6.0;stand=4.5;pace=0.45;beat=3.2;throw=11.5
tape: finale_l7_v24
expect: shove Runner_0 3.52-3.82; arrive Runner_1 2.0-2.25; tower_out Runner_0 +3.1-3.3; alive Runner_1; lens_clear; lens_cover <= 0.5
seconds: 5.4
in: 1.3
frames: cut 0.0-0.8 the run into the portal; 0.9-2.3 the tower room, the guard at the far window, the POV walks up; ~2.45 the shove (the POV's arms out); 2.6-5.4 the game's kill-beat cinematic: he goes over the sill legs-up, turns flat and tumbles slowly spread-eagle down past the far lava falls onto the lava sea; the cut ends on him still falling, no POV/sniper frame after the shove.
cut: content\ragdoll_short\cuts\07_v24.mp4 (5.4 s, PC take 167_t1, motion 0.2019, freeze 0; Mac copy sv3/cuts/07_v24.mp4)

## script v24 row
| L7 | cuts/07_v24.mp4 | 0 | | line | | And when you reach the tower, you can shove the guard out, and watch them go flying into the pit. | | | |
