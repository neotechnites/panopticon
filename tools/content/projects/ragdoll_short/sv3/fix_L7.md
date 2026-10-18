# L7 fix for v23 (task #630)

Head: append this as the next ## entry of projects/ragdoll_short.md (filmed as temp entry 57) and repoint L7 in ## script v23.

## 57
said: L7 (v23, Ryan on v22: "the gaurd clips into the fucking pit wall lke we specifcally specified not to. and then cuts to a sniper pov for no fucking reason"): pov runner makes it through the portal, shoves, and the usual cinematic shot -- finale: the run into the portal, the arrival (2.13), the walk up and the shove (3.67), and the game's kill-beat cinematic held 3.2 s so the cut ends on it, never back on the POV in the tower. The guard posted 4.5 m out (at his window) and the throw at shove_impulse 11.5 (the finale doubles it): Mac trace clears the window sill (no tower contact) and he drops into the pit 30+ m out, 11+ m short of the pit wall (r 46.3) when the cut ends; at the shipped 16 he hit the wall at 1.6 s, below 11 the sill caught him.
capture: --shot=s3_open_lane --stage=finale --pov=runner --bots=3 --shimmer=0 --seed=20261012 --set=lead=6.0;stand=4.5;pace=0.45;beat=3.2;throw=11.5
tape: finale_l7_v23
expect: shove Runner_0 3.52-3.82; arrive Runner_1 2.0-2.25; tower_out Runner_0 +3.1-3.3; alive Runner_1; lens_clear; lens_cover <= 0.5
seconds: 5.4
in: 1.3
frames: cut 0.0-0.6 the run into the portal; 0.83 through; 0.9-2.3 the tower room, the guard posted at the far window, the POV walks up (he grows in frame); 2.37 the shove (the POV's arms out); 2.5-5.4 the game's kill-beat cinematic: he leaves through the window clean (no tower contact), drops down the pit in front of the far lava falls, the lava sea rising under him; the cut ends on him still falling, 11+ m off the pit wall. No POV/sniper frame after the shove (the beat ends at take 6.87, the cut at 6.7).
cut: content\ragdoll_short\cuts\07_v23.mp4 (5.4 s, PC take 07_v23, motion 0.2046, freeze 0)

## script v23 row
| L7 | cuts/07_v23.mp4 | 0 | | line | | And when you reach the tower, you can shove the guard out, and watch them go flying into the pit. | | | |
