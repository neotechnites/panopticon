# Content pipeline: shorts and devlogs, one direction at a time

Ryan directs shot by shot; the brief is the running record of what he said, and
each command works on one shot or one assembly. Nothing is inferred: a shot
exists because he asked for it, in his words.

```
tools/content/sync.sh                    # this branch -> C:\dev\verify (once per code change)
tools/content/shot.sh <project> <n>      # capture + gate + render shot n on the PC
tools/content/fetch.sh <project> <url> <name> [--find WORD | --from T --to T]   # external footage, credited
tools/content/voice.sh <project>         # speak every ## script line (edge-tts), voice\words.json
tools/content/assemble.sh <project> [--tag NAME]   # voice-first cut from the ## script table -> final\<tag>.mp4
tools/content/dailies.sh <project>       # poster frames + final\index.html for review
tools/content/serve.sh <project>         # the PC folder in this Mac's browser (loopback + ssh tunnel)
tools/content/assemble.sh <project>      # (no ## script) shots in order -> timeline.mp4, beats.txt, voice_gap.txt
tools/content/render.sh <project> [--still]   # (no ## script) aspect, captions, voice -> final.mp4
tools/content/voice.sh <project> <wav> [n]    # (no ## script) lay Ryan's recording at shot n's gap, re-render
```

The per-short process, start to finish, is `tools/content/PLAYBOOK.md`.

## The script table: `## script` in the brief

The cut is written as a table under `## script`: one row per voice line, the
clip it plays over, and how the picture fits the line. The VOICE decides every
slot's length; the picture is trimmed, held, slowed or waited for to match --
"picture follows voice, not voice picture". Header lines above the table set the
voice, the music and the captions. The shove brief (`projects/shove.md`) is the
worked example; `pc/assemble.py`'s docstring is the reference.

```
## script
voice: en-US-AndrewNeural +5%       # edge-tts voice and rate (voice.sh)
music: voice/windmill_isle_day.mp3  # under the project folder; music_db: -18; music_fade: 1.0 1.5
pad: 0.2                            # seconds after each line before the next
captions: pop                       # pop | none; captions_font: Impact; captions_size: 64; captions_y: 0.72
| line | clip | in | len | fit | speed | text |
| l0 | final/f10_lava_parkour.mp4 | | | line | | I added this to my game, ... |
| l8 | final/01_cover.mp4 | at=1.4 | 2.1 | wait | 0.75 | Shove them out from cover. |
| l4a | external/gamegrumps_starsteal_wide.mp4 | | | window onset=26.46 end=31.1 gap=0.15 hold=1.0 | | ... sabotage. |
```

`in` is source seconds (or `at=T`: the `len` window centred on T -- a shove at
1.4 s: `at=1.4 len=2.1 speed=0.75` is 2.8 s on screen). `fit`: `line` (trim a
longer clip, hold a shorter one's last frame), `trim`, `slow` (slow to fill),
`nohold` (the clip ends the slot; leftover voice carries into the next line),
`wait` (the slot is the picture's; the next line waits), `window onset= end=
gap= hold=` (an external clip's own sound after the line + gap, music ducked
0.3 s before and back 0.5 s after, then `hold` s of music only -- align `onset`
to where the sound STARTS, not its peak), `beat S` (no voice, S seconds over
the music). Landscape sources get a blurred letterbox fill. Output:
`final\<tag>.mp4`, `cuts\<tag>_timing.txt` (the table with every trim, hold
and window, printed), `cuts\<tag>_lines.json`. Segments are cached in
`cuts\_cache\` by source and numbers: a caption, music or voice change re-cuts
in ~10 s; a fresh 58 s cut is ~2.5 min. The captions burn in their own pass
(in-graph burning deadlocked ffmpeg).

## Where it lands on the PC

Every project is one folder, `C:\Users\ddd\Desktop\panopticon-renders\content\<project>\`,
split by what a file is (helpers in `lib.sh`: `project_dir`, `pc_layout`,
`pc_promote`, `pc_worktrees_clean`):

```
content\<project>\
  final\     delivered clips only: <file>.mp4 from a shot's file: line, <tag>.mp4 cuts,
             index.html + thumbs\ (dailies); superseded versions in final\alt\
  cuts\      the edit: <tag>_timing.txt and <tag>_lines.json per cut, _cache\ (rendered
             segments, reused), _work\; NN.mp4 masters, timeline.mp4, beats.txt for gap briefs
  voice\     <line>.wav + <line>.txt per script line, words.json (word times), the music bed;
             voice_NN.wav recordings and voice_gap.txt for gap-based briefs
  notes\     brief.md, caption_NN.txt, NN.gate.txt + NN.take.log for the take that
             was cut, and any .md / probe / import notes written while directing
  stages\    the stage .gd scripts written for the shots
  frames\    pulled frames: NN.png stills, sheet.png, final_still.png, contact strips
  external\  fetched footage: <name>.mp4 cuts, SOURCES.md (credits), src\ (full downloads)
  scripts\   the pc\*.py pushed by voice/assemble/dailies/fetch, resolve_project.lua
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
