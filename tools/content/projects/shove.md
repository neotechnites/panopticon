# shove
kind: short
format: i-added-x
aspect: 9:16
voice: yes
ryan: for the parts where im saying cover, lava and edge, clips of someone doing those things to another person. for the last part, first person perspective of getting shoved off the ledge.
shots: the four beats Ryan named, runner on runner, plus a hook frame; the [mine] lines are the translation of his words into captures, not his words
delivery: each shot is also written on its own as clips\shove\<file>.mp4, 1080x1920, no text, HUD only on the POV shot; the ~50 s cut is Ryan's, over his voice

## 1
said: [mine] hook, for the first frame: the best single shove landing, the victim flying into the lava (the same beat as shot 4, cut tight on the hit)
capture: --stage=shovecatch --shot=s2_gap --bots=2 --look=social --audio=near --track=victim
file: 00_hook
in: 3.4
seconds: 3
frame: 0.6
gap: 0

## 2
said: "cover" -- someone doing that to another person: a runner crouched behind the pocket rock at 196 deg is shoved up the lane out from behind it by another runner, and the tower's line to them opens up (it fires)
capture: --stage=shovecover --shot=pocket_cover --bots=2 --look=social --audio=near --track=victim
file: 01_cover
in: 0.9
seconds: 4
frame: 1.4
gap: 0

## 3
said: "edge" -- a runner stood at the pit rim on the S3 deck is shoved over it from behind by another runner and falls out of frame
capture: --stage=shoveedge --shot=rim_edge --bots=2 --look=social --audio=near --track=victim
file: 02_edge
in: 1.2
seconds: 3.8
frame: 1.6
gap: 0

## 4
said: "lava" -- a runner mid-jump on the S2 boulder chain is shoved into the lava by the runner waiting on the next landing; the lava takes them
capture: --stage=shovecatch --shot=s2_gap --bots=2 --look=social --audio=near --track=victim
file: 03_lava
in: 3.0
seconds: 4
frame: 1.0
gap: 0

## 5
said: "for the last part, first person perspective of getting shoved off the ledge" -- the victim's own eyes, HUD on: stood at the pit rim looking out over it, shoved from behind, over the edge and falling, held until the death
capture: --pov=runner --stage=shoveedge --shot=rim_edge --bots=2 --look=social --audio=near
file: 04_pov_ledge
in: 0.8
seconds: 4.4
frame: 2.4
gap: 0
