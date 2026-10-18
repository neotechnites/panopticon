## L2 (v23 cut 02_v23 -> v24 cut 02_v24)
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

## L2 (v25 -> v26)
said: Ryan on v25: "the death animation on the grey background is using a weird fucking model of the character. the onld in game one with a bunch of filters on it. it looks like the version of the character your supposed to see from 100 ft away when it gets low rezed." (v22: "why the fuck is the character rendered how it is in game???")
build: today's (shorts-v3 @ 757d4511 + ee5d03f5): current prisoner2.glb with Ryan's albedo, no ref: (v24/v25's 3a8cefd3 dropped). Interpretation: "filters" = mipmapped/default sampling, so every surface of his is set to linear, no mipmaps, full 512 px texture.
stage: death_void: same void, floor and sun; new dials crisp (1) and look_h; the Death clip plays once on the current avatar at 1.62 s (ragdoll off); lens 5.5 m off, 1.0 m up, fov 40, look_h 1.38; he faces 35 deg off it
capture: --shot=s3_open_lane --stage=death_void --bots=1 --seed=20261017 --shimmer=0 --set=dist=5.5;look_h=1.38
tape: none
expect: death Runner_1 1.5-1.7; lens_clear
seconds: 3.6
in: 1.2
motion: 0.002
freeze: waive
brief: tools/content/projects/ragdoll_short.md ## 71 (shot.sh ragdoll_short 71 --name 02_v26)
cut: content\ragdoll_short\cuts\02_v26.mp4 (3.60 s; PC take: death 1.62, motion 0.0098, gate waived)
table row: | M2 | cuts/02_v26.mp4 | 0 | 3.6 | beat 3.6 | | | | | external/scared.gif 1.2 2.0 end |
