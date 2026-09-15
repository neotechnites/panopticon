# Content pipeline: shorts and devlogs, one direction at a time

Ryan directs shot by shot; the brief is the running record of what he said, and
each command works on one shot or one assembly. Nothing is inferred: a shot
exists because he asked for it, in his words.

```
tools/content/sync.sh                    # this branch -> C:\dev\verify (once per code change)
tools/content/shot.sh <project> <n>      # capture + gate + render shot n on the PC
tools/content/assemble.sh <project>      # shots in order -> timeline.mp4, beats.txt, voice_gap.txt (+ Resolve project)
tools/content/render.sh <project> [--still]   # aspect, captions, voice -> final.mp4
tools/content/voice.sh <project> <wav> [n]    # lay Ryan's recording at shot n's gap, re-render
```

## Where it lands on the PC

Every project is one folder, `C:\Users\ddd\Desktop\panopticon-renders\content\<project>\`,
split by what a file is (helpers in `lib.sh`: `project_dir`, `pc_layout`,
`pc_promote`, `pc_worktrees_clean`):

```
content\<project>\
  final\     delivered clips only: <file>.mp4 from a shot's file: line, final.mp4
             (or final__speak-at-<t>s-for-<g>s.mp4); superseded versions in final\alt\
  cuts\      the edit: NN.mp4 shot masters (NN_before/NN_after/NN_pair.txt for a
             pair), timeline.mp4, beats.txt, list.txt, slates\, rough cuts and timing
  voice\     voice_NN.wav recordings, voice_gap.txt, TTS scratch (sapi\ for SAPI)
  notes\     brief.md, caption_NN.txt, NN.gate.txt + NN.take.log for the take that
             was cut, and any .md / probe / import notes written while directing
  stages\    the stage .gd scripts written for the shots
  frames\    pulled frames: NN.png stills, sheet.png, final_still.png, contact strips
  scripts\   resolve_project.lua and any one-off .ps1 (stitch, tts, retime)
  takes\     raw NN_tK.avi + .log + .txt while a shot is being captured; transient
```

`takes\` is transient: when a shot is cut, `shot.sh` moves the chosen take's gate
report and log to `notes\NN.gate.txt` / `notes\NN.take.log`, deletes every take
of that shot (failed takes are not kept), and removes `takes\` once it is empty.
It also unregisters and deletes any git worktree (`work_<shot>` scratch copies of
the repo) left under `panopticon-renders`, from both `C:\dev\panopticon` and
`C:\dev\verify`. Nothing else is written outside these folders; `--still` and
`sheet.sh` pull one frame each to the Mac. The old `content\shorts\`,
`content\devlogs\` and `clips\<project>\` folders are the pre-2026-09-15 layout.

## The brief: `tools/content/projects/<project>.md`

Append-only. One `## n` entry per shot, in order, each carrying Ryan's exact
words on its `said:` line. The other lines are the translation of those words
into a capture; change them, never the words.

```
# guard_cant_hit
kind: short              # short | devlog
format: crazy-clip       # crazy-clip | i-added-x | b-roll | devlog
aspect: 9:16             # 9:16 | 16:9   (frame: crop | letterbox, for 9:16)
voice: no                # yes | no

## 1
said: first shot is the guard from his own scope emptying the rifle at one guy who just keeps strafing
capture: --pov=guard --stage=missstreak --shot=s3_open_lane --bots=1 --look=social --audio=near
seconds: 8               # the cut
caption: bro would not die   # lower third for this shot only; omit for none
gap: 0                   # silent seconds appended for voice-over (game audio muted)
```

Per-shot lines: `capture:` (run_clip args: `--shot`, `--pov`, `--stage`,
`--bots`, `--seed`, `--delay`, `--look`, `--audio`) or `still:` (shot.gd args:
`--scene --pos --look`, held for `hold:` seconds); `seconds:`; `in:` (seconds
into the take the cut starts); `gap:`; `caption:`; `at: <git ref>` for a
before/after pair (the same capture at that ref and at the branch, back to back);
`ref: <git ref>` to film that one shot at another ref with the capture tools it
has (the worktree comes back to the branch afterwards); `takes:` and `motion:`
to override the gate for that shot.

Rules baked in: no hook text, no title cards. A caption is the one line a player
would type. A 9:16 short is FILMED 9:16 -- the viewport is 1080x1920 and every
lens composes for a phone (the action in the middle of the height); nothing is
captured landscape and cropped. No HUD on any shot unless the capture says
`--hud=on`. A devlog (`kind: devlog`) gets 16:9, a 1.5 s working slate before
each shot naming it, and a Resolve project when Resolve is installed.

## The take gate

Each take is measured on the PC: `motion` is the share of pixels that change
between samples 0.1 s apart (gate: >= 0.02), `freeze` counts stretches frozen
for >= 0.75 s (gate: 0). A failing take is retried with the next seed (default 2
takes; a pinned `--seed` is never retried); the best is kept and the report says
so. A guard scope or a crouched POV sits at 0.005-0.015 by nature: set
`motion:` on that shot rather than arguing with the gate.

## Stages (`--stage=`)

`firefight`, `chainrun` (as before), and the forced beats: `shovecatch` (a
prisoner on the S2 chain shoves the runner mid-jump into the lava),
`ghostcatch` (the same, by a ghost: a real catch), `missstreak` (a sloppy guard
empties the rifle at a weaving runner on the S3 deck), `decoy` (the runner
throws a hologram out from behind the S3 pillar; the guard shoots it),
`padflight` (the S3 demon pad, then the bot's own brain), `lavadeath` (a runner
hops off the S4 ledge). Shot paths for them: `s2_gap`, `s3_open_lane`,
`s3_pillar`, `pad_flight`, `s4_edge`. `--pov=runner` rides the staged body.

## Voice-over

`gap: N` on a shot mutes the game audio for its last N seconds. While no
recording is in, the final is named `final__speak-at-<t>s-for-<g>s.mp4` and
`voice_gap.txt` lists every gap. Record, then `voice.sh <project> <wav>`; the
wav is mixed at the gap and the final becomes `final.mp4`.

## DaVinci Resolve

Not installed on the PC as of 2026-09-14 (winget has no package; the free
installer needs Blackmagic's registration form). A ready download script with a
signed URL was left at `C:\Users\ddd\Downloads\bmd_dl.ps1` -- run it once, then
the installer in `C:\Users\ddd\Downloads\resolve\unz`. With `Resolve.exe`
present, `assemble.sh` also builds a project through
`tools/content/resolve_project.lua` (fuscript, no Python needed): one video track
per shot, a marker per shot, placeholder Text+ titles, a muted narration track.
Until then the edit is `timeline.mp4` + `beats.txt`.
