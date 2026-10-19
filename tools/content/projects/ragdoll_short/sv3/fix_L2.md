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

## L2 (v26 -> v27)
said: Ryan on v26: "the death animation, in the gray space, is still fucking shit, becuase the model is blood red like they are in he.l. you already did this one successfully i have no idea what youre problem is."
cause: the map's baked LightmapGI (lava red) still lit the dynamic body in the void, plus the character fit's red fill light and emission-ambient material dressing; v20's void was no better (orange). Removed in death_void.gd: LightmapGI freed, CharacterFill freed, authored materials at white albedo, no emission, sun white, linear no mipmaps, reapplied after the death handler.
capture: --shot=s3_open_lane --stage=death_void --bots=1 --seed=20261017 --shimmer=0 --set=dist=5.5;look_h=1.38 (brief ## 72)
cut: content\ragdoll_short\cuts\02_v27h.mp4 (3.6 s); table row: | M2 | cuts/02_v27h.mp4 | 0 | 3.6 | beat 3.6 | | | | | external/scared.gif 1.2 2.0 end |
frames: pale skin, white shirt, navy jeans in neutral grey light; proof ~/Desktop/panopticon-renders/_work/proofs/short4_void/void_v20_vs_v27.png

## M2 (v28 -> v29)
said: Ryan on v28: "still the compelte wrong clip. make it from scratch, all its supposed to be is a screen capture of me playing the animation in the godot editor, and then, that face slowly fading in, it should not fade in on top of the character. it should play out, exactly as it doesn in v14, but it should be the most recent model"
reference: v14's M2 (ragdoll_short_v14.mp4 3.433-6.633 s = 3.2 s): he stands 0.95 s, the Death clip (0.67 s) drops him onto hands and knees, he lies at y 980-1480; scared.gif 900 wide in a box x 90-990 y 477-977 (centre y 0.379) fades in from 2.25 s over 0.95 s; the cut ends as the fade completes. No editor chrome in v14's frame: a plain grey viewport.
build: shorts-v3 @ 48cca155 (main c86f4ad4 merged: today's prisoner2.glb, Ryan's albedo, flat normals), no ref:.
method: a real Godot 4.7.2 editor screen capture (editor/take.sh -> editor.ps1 on the PC): a throwaway worktree C:\dev\worktrees\ragdoll_editor at the synced sha, scrubbed before any frame (tools/, tests/, docs/, addons/, .claude, every *.md incl. CLAUDE.md, *.blend, *.txt, *.sh, *.py, *.ps1; [editor_plugins] dropped; the path listing checked against the banned tokens: SCRUB OK, 1232 paths); characters/death_editor.tscn (prisoner2.glb, a grey floor, one sun with shadows, a neutral grey sky, msaa 4x in the copy's project.godot) and a @tool autoload frame.gd (window 2560x1440 borderless, FileSystem dock scoped to res://characters/, inspector hidden, toasts hidden, View Grid / View Origin / View Gizmos off, nothing selected, the editor camera held at eye (0, 2.1, 4.1) looking at (0, 0.70, 0) fov 40, the prisoner's surfaces linear no mipmaps as v26/v27). The editor opened in the console session (scheduled task), ddagrab recorded the whole screen 9 s at 60 fps (utvideo); res://go.on 4 s in made frame.gd call AnimationPlayer.play("Death") (fall at 3.90 s of the take).
cut: the central 9:16 slice of the 3D viewport (718x1276 at 1062,117 of the 2560x1440 screen; the viewport was 2269x1276 at 287,117), lanczos to 1080x1920, in at the fall minus 0.95 s, 3.6 s: content\ragdoll_short\cuts\02_v29.mp4. Frame extents: standing y 276-1400 (v14 270-1340), lying y 1036-1528 (v14 980-1480), below the gif box.
table row: | M2 | cuts/02_v29.mp4 | 0 | 3.2 | beat 3.2 | | | | | external/scared.gif 2.25 0.95 end w=900 y=0.379 |  (assemble.py gif_fade grew w= and y=; default unchanged: full width, centred)
interpretation: v14's frame shows no editor UI, so the cut is the viewport slice as v14 was; the full-screen take (proofs/short4_editor/v29/screen_fall.png) is the editor itself, Scene dock, FileSystem dock and bottom panel in view.
proofs: ~/Desktop/panopticon-renders/_work/proofs/short4_editor/v29/ (take.json, listing.txt, cut_tile.png, screen_in.png, screen_fall.png)

## M2 (v29 -> v30)
v30 = v29 with M2 only: in 0.95 (the standing second dropped), len 2.25, beat 2.25, scared.gif fade from 1.30 s over 0.95 s, ending on full fade; opens on the fall as v14 does (task #630).
