# The short: brief to Mac in one command

The head writes the brief from Ryan's script and spawns ONE agent per short. That agent
runs fixed commands; it never writes its own cutter, never re-decides a row Ryan gave no
note on. A second agent only when a new stage or tape has to be authored.

## The commands

```
tools/content/short.sh <project> [--tag vN] [--final]   # the whole version, delivered
tools/content/version.sh <project> <newtag>             # vN+1 = copy of vN's table
```

`short.sh` does, in order, timing each stage:
1. `sync.sh` puts this branch on `C:\dev\verify` and imports it (never `C:\dev\panopticon`).
2. `voice.sh --tag vN` when the table has voice lines: Andrew +5%, preflighted.
3. `shot.sh` for every shot the table plays whose cut is missing, or whose entry says
   `refilm: vN`. Each shot is one real-time take.
4. `assemble.sh --tag vN` cuts the table.
5. Copies `final\vN.mp4` to `~/Desktop/panopticon-renders/content/shorts/<project>/<project>_vN.mp4`.

A failure anywhere stops the run and says why. Fix the row; run it again: finished cuts
and cached segments are reused.

## The brief (`tools/content/projects/<project>.md`)

```
# <project>
kind: short
aspect: 9:16

## 1
said: Ryan's words for the shot, verbatim
capture: --shot=lava_parkour --stage=polish_lava --bots=1   # run_clip.gd args
tape: <name>          # optional: a recorded take (tape.sh), the same shot every time
seconds: 6            # cut length; in: 1.2 = seconds into the take it starts
motion: 0.005         # gate floor for a fixed lens on slow motion (say why)
refilm: v3            # refilm this shot when building v3 (the cut becomes cuts/01_v3.mp4)

## script v1
captions: stack       # pop | stack | none
music: voice/bed.mp3
| line | clip | in | len | fit | speed | text | card |
| l1 | cuts/01.mp4 | 0 | | line | | I added waviness to my lava. | |
| b1 | cuts/01.mp4 | cont | | beat 1.5 | | this lava looks like rocks | |
```

Shot `## n` films to `cuts/NN.mp4`; the table plays it by that path. Field reference:
the header of `shot.sh` (shot entries) and `pc/assemble.py` (table, header keys).

## Versions

- `version.sh <project> v2` appends `## script v2`, a copy of the newest table. Edit only
  the rows Ryan noted. Every other row hits the segment cache and is frame-identical.
- A refilm never overwrites: the new cut is `cuts/NN_v2.mp4` and only v2's table is
  repointed to it. `shot.sh` refuses a cut name any earlier tag's `cuts\<tag>_used.txt` lists.
- Voice lines are re-spoken only when their text changed.

## Filming

- Rough (every draft): real time. Portrait is 810x1440 borderless at 0,0 on the PC's
  2560x1440 screen, recorded by ddagrab, scaled to 1080x1920 at the cut. One take; a
  failed gate prints motion/freeze and stops. No retries, no fallback.
- Final (`short.sh --final`, or `shot.sh --movie`): Movie Maker, native 1080x1920, every
  shot refilmed to `cuts/NN_vN_final.mp4`. Only the final draft does this.
- Nothing ever falls back to Movie Maker. A rough take that cannot fit the screen fails.
- Portrait is composed for portrait: Camera3D fov is vertical; nothing is cropped.
- No HUD on any shot; a guard POV keeps the crosshair (`hud: crosshair`).
- Framing is numbers in the brief (ring point, look point, fov), never "like shot 3".
- Nothing spawns in frame; no still frames; when the action ends, the clip ends.
- Gameplay should look human: tapes of bot matches with player_feel, not robotic stages.

## The cut (assemble.py)

- The voice sets each slot; the picture is trimmed to it. A picture shorter than its
  line FAILS: `l3 needs +0.40 s of picture`. Nothing is held, frozen or slowed
  (Ryan: "never slow down clips its looks terrible"). Speed below 1 fails.
- Fits: `line`, `trim`, `nohold`, `wait`, `window`, `beat S`. `fill` speed trims only.
- Captions: `pop` word by word under the voice; `stack` each row's text as a quote in
  quote marks, from its row's start to the end, one slot each in `captions_band`
  (default 0.55-0.92 of the height), never overlapping; `none`.
- Cards have their own band: a card that overlaps the caption band fails the cut.
- Lossless all the way to `final\master\<tag>.mkv`; `final\<tag>.mp4` is one H.264
  4:2:0 encode (what Ryan's Mac plays cleanly).

## The PC

- One lock for sync, capture and assemble: `C:\dev\locks\screen\owner.json`
  {owner, pid, host, token, expires}, renewed every 30 s, dead after 120 s. Waiters queue
  by ticket in `C:\dev\locks\queue` and also wait while the `heavy` lease is held or any
  ffmpeg or scripted Godot is running. Never kill a process you did not start.
- Everything runs at below-normal priority.
- The take is a screen recording: Ryan leaves the PC alone while a window is up.
- `GameSettings.window_held` keeps saved video settings off a capture window.

## The folder on the PC

`content\<project>\`: `final\` (delivered), `cuts\` (shot cuts, `_cache\`, timing,
`<tag>_used.txt`), `voice\`, `notes\` (brief, gate and take log per shot), `takes\`
(raw takes; deleted once cut; a failed take stays for a look).

## Measured (2026-10-12, smoke: one 6 s portrait shot, one voice line, one beat)

sync 12 s (57 s when the import hook changed), voice 7 s (preflight plus one line),
shot 50 s (Godot 26 s real time incl. 9 s load, gate 2 s, render 11 s), assemble 37 s,
deliver 6 s. End to end 117 s.

## Before telling Ryan a cut is ready

Compare it with the previous cut at 1 fps
(`ffmpeg -i X.mp4 -vf "fps=1,scale=240:-2,tile=15x3" -frames:v 1 sheet.png`): same shot
in every cell, game filling the frame. No other checks unless he asks.
