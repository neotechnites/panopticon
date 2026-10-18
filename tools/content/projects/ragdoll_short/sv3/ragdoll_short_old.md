# ragdoll_short_old
kind: short
aspect: 9:16
# ragdoll_short's old-build shots (L2 v24 at 3a8cefd3, L3 v23 at 0fe0c9ec), filmed through shot.sh under their own project name so the
# PC checkout is C:\dev\worktrees\content_ragdoll_short_old; the cuts are copied to content\ragdoll_short\cuts\.

## 2
said: shot of the animation in a grey space jsut playing, with a slow fade in of an image i will provide https://media.tenor.com/17aPeH713cYAAAAM/scared.gif -- Ryan on v23: "seriously is the fucking random ass fucking orange box in the death animation a joke?" -- death_void at 3a8cefd3 (2026-10-05, the last commit before the death ragdoll 06bdee8f): the prisoner2 model alone in a grey void (a shadow-only floor, the sun), the lens 5.5 m off, 1.0 m up, fov 40, looking at 1.38 m so he lies in the frame's bottom quarter, clear of the full-width gif band (34-66% of the height); he faces 35 deg off it; at 1.6 s he plays that build's Death clip once and lies there
capture: --shot=s3_open_lane --stage=death_void --bots=1 --seed=20261017 --shimmer=0 --dist=5.5 --look_h=1.38
ref: ragdoll-old-era-3a8cefd3
expect: death Runner_1 1.5-1.7; lens_clear
seconds: 3.6
in: 1.2
motion: 0.002
freeze: waive

## 3
said: slow zoom out shot of the old hell map -- Ryan on v22: "if my art didnt make it clear, it should be an older build of the game to show the even worse art" -- hell_pullback at 0fe0c9ec (2026-09-11): the old hell ring (map_base.glb, lava tiles, the old tower) during a live 3-runner match; the lens opens close on the tower (deg 0, r 14, 6 m up, fov 45) and pulls straight back and up over 8 s to deg 0, r 36, 34 m up, fov 70, the pit, deck and far side coming into frame
capture: --shot=pit_orbit --stage=hell_pullback --bots=3 --seed=20261017 --shimmer=0
ref: ragdoll-old-era-0fe0c9ec
expect: pullback start 0.9-1.1; pullback end 8.9-9.1; lens_clear; lens_cover <= 0.5
seconds: 8.2
in: 1.0
motion: 0.01
