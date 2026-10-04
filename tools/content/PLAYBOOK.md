# The short: start to finish

One agent runs the short; one agent per shot underneath it. Ryan directs in
his own words; the brief records them. Four a week means nothing is
rediscovered: every rule below was paid for on the first short (shove,
2026-09-15). Timings measured on the PC are in brackets.

## 0. Before anything

- [ ] `git checkout -b work-<short> main`; `tools/content/sync.sh` puts the
      branch on `C:\dev\verify` (never `C:\dev\panopticon` except via git).
      Never run Godot windowed on the Mac. Do not touch sounds.
- [ ] Brief at `tools/content/projects/<short>.md`: header, then one `## n`
      per shot with Ryan's words on `said:`, then the `## script` table.
- [ ] `tools/content/serve.sh <short>`; the dailies URL goes to Ryan once.

## 1. The script and the shot list

- [ ] Write the voice lines first. `voice.sh <short>` speaks them (edge-tts,
      per-line wavs, word timings) so every slot has a length before a frame
      is filmed. Picture follows voice, never voice picture.
- [ ] One row per line in the script table: line, clip, in, len, fit, speed,
      text. Show Ryan the table with a one-line description per clip and the
      seconds; that is the format he reads ("align the clip with the piece
      of the script").
- [ ] External footage: `fetch.sh --find WORD` to locate the moment in the
      captions, then `--from/--to`. Credit lines land in `SOURCES.md`. Prefer
      clean gameplay, no facecam; try `--cc-search` first.

## 2. Filming a shot (one agent each)

Every shot is staged by numbers. Read `tools/capture/stages/README.md`.

- [ ] Portrait native: 1080x1920, never landscape then cropped. The lens
      composes for the height; a Camera3D fov is the vertical one.
- [ ] No HUD on any shot. A guard POV keeps the crosshair and nothing else
      (`hud: crosshair`).
- [ ] Camera framing is geometry and numbers -- `ring_point(deg, r, h)`, a
      look point, a fov -- written in the brief. Never "use the other
      shot's framing"; that instruction was given ten times and still got
      the wrong shot. Copy the numbers.
- [ ] Probe before placing: `probe_ring.gd --clear` for pad- and trap-free
      deck, `--los` for what the tower sees. Bodies on a demon pad get
      launched; bodies near the rim fall in.
- [ ] Nothing spawns in frame: cast at 0.6 s, cut in at 0.9-1.8 s, and every
      body that will be in the shot is placed and moving before the cut.
- [ ] Runners closer together than feels right for a scope pan (10 m, one
      beat each), and the guard must hit. The tower is a dial: dead until
      the beat, then `set_trigger`; the hand (`guard_hand.gd`) for a POV.
- [ ] Every POV must look like a human playing: `human` on, glances with
      overshoot and settle, a shuffle, a look back, a flinch on the hit;
      never a constant-rate turn.
- [ ] Two beats in one place (6+7: crouched, a runner sniped, then the shove
      out of cover) are ONE continuous take, one camera, no cut.
- [ ] No still frames. When the action ends, the clip ends; cut to the next.
- [ ] Group action gets per-body seeded timing (`seed_with`), never one
      cadence. A beat on a word is an `until` step at a number.
- [ ] Smoke headless on the Mac first (`run_clip.gd -- --stage=... `, read
      the `[event]` lines), then `shot.sh <short> <n>` on the PC. A take is
      20-90 s of Godot plus the gate; a fixed lens on a still body measures
      0.002-0.01 motion by nature -- set `motion:`/`freeze:` in the brief
      rather than argue with the gate, and say so in the entry.
- [ ] Show each shot to Ryan (dailies page) before it goes into the cut.
      Fix what he says on that shot only. Keep the take's log and gate in
      `notes\`; the takes themselves are deleted on promotion.

## 3. The cut

- [ ] `assemble.sh <short>` (fresh ~2.5 min for a minute of cut; a caption,
      music or voice change ~10 s from the segment cache). Read the timing
      table it prints: every trim, hold and wait is there.
- [ ] Shove-style beats: ~2.8 s on screen at 0.75x, the window centred on
      the hit (`at=T len=2.1 speed=0.75`, `wait`).
- [ ] An external clip with its own sound is an audio window aligned to the
      ONSET of the sound, not its peak (measure it: the scream started at
      26.46 s, the peak was a second later), a gap after the line, the
      music ducked, a 1 s beat of music only before the next line.
- [ ] Music bed -16 dB was "maybe 20% quieter" -> -18. Fades 1.0 in, 1.5 out.
- [ ] Captions: pop-in word captions, 2-3 words, current word highlighted,
      at 0.72 of the height. They burn in a separate pass; the first build
      of the captioned picture is cached (was 30 min in-graph, now ~2).
- [ ] `dailies.sh <short>`; Ryan reviews by clip id. Change one row, re-run.
- [ ] Voice: Ryan records over the TTS timing; drop his wavs in as
      `voice\<line>.wav` and re-assemble.

## 4. Done

- [ ] `final\<short>.mp4` delivered; `SOURCES.md` complete; brief committed
      with the script table as cut. Promote: takes and scratch worktrees
      are gone (`shot.sh` does it), `cuts\_cache` may stay.
- [ ] Add what this short taught to this file. One paragraph, no essay.

## The folder on the PC

`content\<short>\{final,cuts,voice,notes,stages,frames,external,scripts,takes}`
-- one folder per piece of content, split by what a file is. `final\` is what
Ryan sees; `notes\` is why.

## Measured (2026-09-15)

Godot take 20-90 s (a 6-8 s clip at 60 fps, 11% of real time); shot gate
~10 s; assemble first build 156 s (segments 81, captions 66, mux 3), rebuild
after a caption/music/voice change 10 s; the old v6 retime rebuilt everything
in 3.5 min; the first in-graph caption burn took 30 min and deadlocked once;
dailies page 7 s; edge-tts 12 lines ~1 min; a yt-dlp section download ~20 s.

## Measured (2026-09-21, projectile rough v1)

A comment-reply short is picture-poor: 42.5 s of voice over five clips that
hold 36.7 s at 1x, so the cut is 7.1 s short before a frame is placed. Count
that first, from `voice.sh`, and decide where the shortfall is paid -- holding
a frame is not one of the options, so a short clip plays slow (a `fill` speed
in the script table works it out per line) and only the bed under the first two
lines is worth a hand-set rate, because both lines share it. Two things came
out of that and are now in `assemble.py`: a clip cell may name several parts
(`a.mp4,b.mp4`, each `path@in:len`) so a line that outlasts its clip runs into
the next one instead of freezing, and `in: cont` picks the bed up where the
line before it stopped, which is what lets a card come up over picture that is
already playing with no cut. Placing a beat on a word is arithmetic, not taste:
the hit at source 5.97 s under "that" at 1.79 s into the line fixes the
in-point at 4.18 s, and when that leaves less clip than line, the tail of the
same clip is a second part at a `fill` rate -- the action lands on the word and
the line still ends on live action. Two costs are real and worth saying out
loud: that in-point trims the miss off the front, and warzone/fortnite at
0.77x and 0.64x are visibly slow. Also: the word captions had a bug, not a
style -- a chunk hung on 0.08 s past its last word and drew on top of the next
chunk, garbled, four frames at a time; a chunk's tail now stops at the next
chunk's first word. Game audio under the voice is `game: 0.25` and is
tempo-matched with `atempo`, so a gunshot still lands with the frame that fired
it on a slowed clip. Timings: edge-tts 6 lines 22 s, first assemble 100 s
(segments 35, captions 37, audio+mux 21, 720p copy in that), re-cut after the
caption fix 67 s with every segment cached.

## Never slow a clip down
Ryan, 2026-09-22, on a cut with clips at 0.4x–0.8x: "never slow down clips its looks terrible." A slowed clip repeats frames and stutters. A line that outruns its picture gets MORE picture (the next take, the alternate, the next clip), then a hold on live action for the last fraction of a second; never a rate under 1x, never a freeze. Game audio is off in every clip: voice and the music bed only.

## Refilming a trailer (measured 2026-10-04, reveal trailer v18)

One procedure, two film modes. Every shot is a `## N` entry in `projects/<project>.md` with a
`capture:` line and a tape; one command refilms it exactly.

### The fast way (rough cuts, the default)

```
cd ~/Documents/olympus/pano-trailer                 # branch work-trailer-reveal
git merge main                                      # today's game into the trailer branch
# set `tag: rough_vNN` (and the delivery line) in tools/content/projects/trailer_reveal.md, commit
tools/content/sync.sh                               # branch -> C:\dev\verify, imported (about 9 s)
for id in 1 2 6 7 8 11 13 14; do tools/content/shot.sh trailer_reveal $id; done    # about 30 s a shot
tools/content/assemble.sh trailer_reveal --tag rough_vNN                             # about 1 min
tools/content/dailies.sh trailer_reveal                                              # the page
scp "panopticon-pc:C:/Users/ddd/Desktop/panopticon-renders/content/trailer_reveal/final/rough_vNN*.mp4" \
    ~/Desktop/panopticon-renders/trailer_reveal/
```

Shots by map (reveal trailer): hell `1 2 6 7 8 11 13 14`, forest `4 5 9a 9b`, marble `5b 10a 10b 12`.
Refilm only the map that changed. Eight hell shots and the cut: about five minutes.

What it does: the game plays the shot at real speed in a borderless 1920x1080 window at 0,0 and
ffmpeg records that part of the screen (`lib.sh pc_rough`: ddagrab, lossless RGB utvideo). The take
opens on white frames; the last white frame is the take's t=0. Page: http://127.0.0.1:8765/final/index.html
(`tools/content/serve.sh trailer_reveal` if it is down).

### The final way

`tools/content/shot.sh <project> <n> --movie`: Godot's Movie Maker writing PNG frames, packed into a
lossless take; frame by frame, exact to the frame, about 80 s for a 5 s shot (30 s in rough mode). Use it for the final trailer only (Ryan, 2026-10-04). Real-time takes run about 0.1 s behind it.

### Nothing is compressed twice

Take (lossless RGB) -> cut `cuts\NN.mp4` (lossless RGB H.264) -> edit segments (lossless RGB) ->
`final\<tag>.mp4` (lossless RGB, the master). `final\<tag>_view.mp4` is ONE near-lossless 4:4:4 encode
of the master for the browser (Chrome plays both; Safari and QuickTime play neither). Never add a
lossy step between the take and the master, and never deliver 4:2:0 from this pipeline: red on black
(hell) turns to fuzz.

### Rules learned the hard way

- Film the game as it is: no exposure, ambient or fill lift in a stage script. (Hell stages once set
  exposure 3.8 and ambient 3.6; the trailer looked blown out.) Forest and marble shots still carry
  `--look=social`; remove it when Ryan asks for them refilmed.
- The PC's saved game settings are windowed 1280x720. `GameSettings.window_held` (set by `run_clip.gd`)
  keeps them off a capture window. Without it the take is a corner of the screen and every cut starts
  about 2 s early.
- `sync.sh` re-imports the .glb files when the import hook changed; a changed hook alone does not.
- A screen recording records whatever is on top: Ryan leaves the PC alone while the windows are up.
  His editor may stay open. Never kill a process the pipeline did not start.
- Before telling Ryan a cut is ready, compare it to the previous cut at one frame per second
  (`ffmpeg -i X.mp4 -vf "fps=1,scale=240:135,tile=15x3" -frames:v 1 sheet.png`): same shot in every
  cell, game filling the frame. No other checks unless he asks.
- No builder for a refilm. It is the six commands above.
