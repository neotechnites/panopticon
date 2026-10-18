## L2 (v22's M2, shot 44 -> v23 cut 02_v23)
said: shot of the animation in a grey space jsut playing, with a slow fade in of an image i will provide https://media.tenor.com/17aPeH713cYAAAAM/scared.gif -- Ryan on v22: "when you show the death animation in a grey void, why the fuck is the character rendered how it is in game???"; "if my art didnt make it clear, it should be an older build of the game to show the even worse art"
build: ragdoll-old-era-0fe0c9ec (0fe0c9ec, 2026-09-11, "runner: authored Jump, Death and Aim clips": the first Death clip, 24 days before the ragdoll 06bdee8f; c4943a47 is the pill greybox with no character or Death clip, so not used). The branch adds only tools/capture/run_clip.gd + lens_probe.gd.
stage: death_void (era run_clip): the old 544-tri runner.glb in its shipped unshaded orange, alone in a grey void (no map, a shadow-only floor, the sun); lens 4.6 m off, 1.0 m up, fov 40; he faces 35 deg off it; at 1.62 s the old Death clip plays once (about 0.8 s) and he lies there
capture: --shot=s3_open_lane --stage=death_void --bots=1 --seed=20261017 --shimmer=0
ref: ragdoll-old-era-0fe0c9ec
tape: none (one prisoner, no brain: the same take every run)
expect: death Runner_1 1.5-1.7; lens_clear
seconds: 3.6
in: 1.2
motion: 0.002
freeze: waive
brief: tools/content/projects/ragdoll_short/sv3/ragdoll_short_old.md ## 2 (shot.sh under its own name; PC checkout C:\dev\worktrees\content_ragdoll_short_old, removed)
cut: content\ragdoll_short\cuts\02_v23.mp4 (3.60 s, 1080x1920; Mac copy at sv3/cuts/02_v23.mp4); Mac smoke death 1.62; PC take: death 1.62, gate waived (orange and the grey are the same luma, so the motion gate reads 0.0000)
table row (v22's M2, scared.gif fade kept): | M2 | cuts/02_v23.mp4 | 0 | 3.6 | beat 3.6 | | | | | external/scared.gif 1.2 2.0 end |
frames: 0.0-0.4 he stands square-on, a flat orange silhouette on flat grey (no shading, as the old build drew a runner); 0.4-1.1 the old Death clip: he pitches forward and to the side, catches himself on stiff arms and flattens onto his front; 1.1-3.6 he lies still, the gif fades in over this
