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
said: "cover" -- someone doing that to another person: a runner crouched behind the pocket rock at 196 deg is shoved up the lane out from behind it by another runner, and the tower's line to them opens up (it fires). Ryan on the first cut: "just a shot that misses, then another shot that hits, with them crouching" -- so now the shove stands them up, and the tower's one shot, once they have landed upright in the open, is the kill
capture: --stage=shovecover --shot=pocket_cover --bots=2 --look=social --audio=near --track=victim
file: 01_cover
in: 0.9
seconds: 3.6
frame: 1.9
motion: 0.007    # a fixed lens on two small bodies against dark rock: 0.007-0.013 by nature (freeze 0); the flight and the tracer are the motion
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

## script
# The v6 cut (2026-09-15), as Ryan signed it off: the voice leads, the picture
# follows it. Timing measured on the PC: voice-first slots, shove clips 2.8 s at
# 0.75x, the Game Grumps audio window aligned to the scream's onset (not its
# peak), music -16 dB then "maybe 20% quieter" -> -18.
voice: en-US-AndrewNeural +5%
music: voice/windmill_isle_day.mp3
music_db: -18
music_fade: 1.0 1.5
pad: 0.2
captions: pop
captions_font: Impact
captions_size: 64
captions_y: 0.72
| line | clip | in | len | fit | speed | text |
| l0 | final/f10_lava_parkour.mp4 | | | line | | I added this to my game, and it got ten times better. |
| l1 | final/f02_pack_sniped_pov.mp4 | | | nohold | | Sure, a bunch of your friends all running next to each other, trying to get to the end without being sniped first, is fun. |
| l2 | final/f03_guard_alone.mp4 | | | line | | But it felt like everybody was playing a different race. |
| l3 | final/f04_pov_shove.mp4 | | | line | | What I needed was something to tie the players to each other while they were doing this. |
| l4a | external/gamegrumps_starsteal_wide.mp4 | | | window onset=26.46 end=31.1 gap=0.15 hold=1.0 | | I wanted my game to foster the type of competitive spirit of a Mario Party. Which, just like in that game, means sabotage. |
| l4b | external/fallguys_grab_gameplay.mp4 | | | slow | | I was inspired by the grab mechanic in Fall Guys. At how simple it was, but how much of a nuisance it is to have someone doing it to you. |
| l5 | final/f06_cover_both.mp4 | 0 | 3.6 | line | | But for a game where staying still behind cover is necessary, |
| l6 | final/f06_cover_both.mp4 | 3.6 | | line | | the better move is a shove. |
| l7 | final/f08_melee.mp4 | | | line | | Now players can all shove each other around. And it's very annoying, and very satisfying to do to someone else. |
| l8 | final/01_cover.mp4 | at=1.4 | 2.1 | wait | 0.75 | Shove them out from cover. |
| l9 | final/02_edge.mp4 | at=1.4 | 2.1 | wait | 0.75 | Shove them off the edge. |
| l10 | final/03_lava.mp4 | at=1.5 | 2.1 | wait | 0.75 | Shove them into lava. |
| l11 | final/04_pov_ledge_b.mp4 | | | line | | It's all fun and games, til you're the one getting shoved. |
