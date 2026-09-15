# shove
kind: short
format: i-added-x
aspect: 9:16
voice: yes
ryan: for the parts where im saying cover, lava and edge, clips of someone doing those things to another person. for the last part, first person perspective of getting shoved off the ledge.
shots: the four beats Ryan named, runner on runner, plus a hook frame; the [mine] lines are the translation of his words into captures, not his words
delivery: each shot is also written on its own as content\shove\final\<file>.mp4, 1080x1920, no text, no HUD on any shot (Ryan: "no HUD elements on any perspective shot"); the ~50 s cut is Ryan's, over his voice

## 1
said: [mine] hook, for the first frame: the best single shove landing, the victim flying into the lava (the same beat as shot 4, cut tight on the hit)
capture: --stage=shovecatch --shot=s2_gap --bots=2 --look=social --audio=near --track=victim
file: 00_hook
in: 3.65
seconds: 3
frame: 0.3
gap: 0

## 2
said: "cover" -- someone doing that to another person: a runner crouched behind the pocket rock at 196 deg is shoved up the lane out from behind it by another runner, and the tower's line to them opens up (it fires)
capture: --stage=shovecover --shot=pocket_cover --bots=2 --look=social --audio=near --track=victim
file: 01_cover
in: 0.9
seconds: 4
frame: 1.4
motion: 0.01     # a fixed lens on two small bodies against dark rock: 0.009-0.013 by nature (freeze 0); the flight and the tracer are the motion
gap: 0

## 3
said: "edge" -- a runner stood at the pit rim on the S3 deck is shoved over it from behind by another runner and falls out of frame
capture: --stage=shoveedge --shot=rim_edge --bots=2 --look=social --audio=near --track=victim
file: 02_edge
in: 1.2
seconds: 3.8
frame: 1.6
motion: 0.002    # a fixed lens, the run-up and the flight both down its own axis: 0.002 by nature (freeze 0)
gap: 0

## 4
said: "lava" -- Ryan on the chain take: "use the other lava sections that are wider, this is pretty janky" -- so the S5 lava lake: a runner on the lip of the bank is shoved from behind out over the open lake and dies in the lava in front of the lens
capture: --stage=shovelake --shot=lake_bank --bots=2 --look=social --audio=near --track=victim
file: 03_lava
in: 0.9
seconds: 3.4
frame: 1.5
gap: 0

## 5
said: "for the last part, first person perspective of getting shoved off the ledge" -- the victim's own eyes, no HUD: stood at the pit rim looking out over it, shoved from behind, over the edge and falling, held until the death
capture: --pov=runner --stage=shoveedge --shot=rim_edge --bots=2 --look=social --audio=near
file: 04_pov_ledge
in: 0.8
seconds: 4.4
frame: 2.4
gap: 0

## 6
said: Ryan on shot 5: "that works, so keep it, but if you can have the player look back and then get shoved off the edge so we can see what's happening, that would be better" -- the same POV, a look back over the shoulder as the shover comes in, the shove landing as they turn back, then over the edge to the death
capture: --pov=runner --stage=shoveedge_look --shot=rim_edge --bots=2 --look=social --audio=near
file: 04_pov_ledge_b
in: 0.8
seconds: 4.6
frame: 1.6
gap: 0
note: v1 (scripted, linear turns) kept as 04_pov_ledge_b_v1.mp4; Ryan: "make it look more like a human playing and make it less rigid" -- this take is played through the driver's human layer (mouse drift, flick-and-settle turns, a wavering walk, a shuffle at the rim) and the shove whips the camera with the game's own FxCameraKick
