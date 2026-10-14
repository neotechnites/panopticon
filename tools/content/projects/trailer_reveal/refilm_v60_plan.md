# Reveal trailer v60: the Movie Maker refilm of rough_v59_beats (task #295), plan and results

Branch `trailer-v37` (worktree ~/Documents/olympus/pano-trailer-v37). Prep only: nothing was filmed, the PC screen was not touched
(the PC was only read over ssh: old take logs, a few frames of old cuts; its temp files are removed).

## Launch (Ryan, when he goes to bed)

    ~/Documents/olympus/pano-trailer-v37/tools/content/refilm_v60.sh

Mac smoke of all 16 entries first (a miss stops before the PC), then sync, 16 Movie Maker shots (about 106 game seconds, about an hour),
align each new cut to v59, build, copy to `~/Desktop/panopticon-renders/trailer_reveal/rough_v60_beats.mp4`. Resumable
(`v60_work/filmed.txt`); `refilm_v60.sh edit` rebuilds from filmed cuts, `refilm_v60.sh smoke` only the Mac gate. The PC must be left alone while it runs
(Movie Maker opens windows). Audio is v59's, copied untouched. Cards (331-661, 2317-2647) are v59's frames.

## 1. The shot list (v59, in order)

Source = what v59 was cut from (found by matching every v59 frame to every old cut and take on the PC). Frames are v59 output frames.
"Entry" is the new brief entry (`trailer_reveal.md`, between `# v60 refilm begin/end`); the stage and tape are the old shot's, untouched.
`in`/`seconds` give 1.0 s before and 0.75 s after what v59 shows. Impact frames are the beats v59 holds.

| v59 out | shot | entry: stage / tape | v59 source (old) | game s used | impact that must keep its frame |
|---|---|---|---|---|---|
| 0-164 | cold open, guard | 1r: trailer_open_pre / open_pre (branch v52-open-b merged) | v52_B2 take 425-462, then cuts/01 83-239, tail past the cut | 7.15-9.90 | hit 9.10 (open t 3.60), squeeze tick 524; one 4-frame skip at 38 removed |
| 165-330 | cold open, runner | 2r: trailer_open / open | cuts/02 115-278 | 2.82-5.58 | hit 3.60 |
| 331-661 | title, ONLINE | v59 frames | | | drop 331, card 497 |
| 662-787 | forest runner | 4tr: trailer_forest_sprint / forest_thread | cuts/04t 41-166 | 1.48-3.58 | none |
| 788-912 | forest scope | 5gr: trailer_forest_pack / forest_pack | cuts/05g 106-230 | 2.67-4.75 | fire 3.15 (819), hit 3.55 |
| 913-995 | marble scope | 5hr: trailer_marble_track / marble_hit | cuts/05h 64-145 | 2.87-4.25 | hit 2.97 (919) |
| 996-1063 | beach scope | 20: trailer_beach_track (no tape, deterministic) | take beach_k_t2 623-690 (real time) | 2.67-3.80 | fire 2.62 = 996, hit 3.15 |
| 1064-1129 | hell runner behind rock | 6r: trailer_duel2 / duel | cuts/06 94-161 | 2.57-3.67 | cut 1064 |
| 1130-1207 | hell scope | 7r: same | cuts/07 147-225 | 3.45-4.75 | ground hit 4.25 |
| 1208-1323 | hell runner | 8r: same | cuts/08 9-123 | 5.65-7.55 | cut to beach 1324 |
| 1324-1448 | beach run | 21: trailer_beach_run (no tape) | take beach_run_t2 557-653 + 679-706 | 1.47-3.55 | cut 1324 |
| 1449-1592 | forest shover | 9agr: trailer_forest_pit / forest_pit | cuts/09ag 0-96, 102-143 | 1.04-3.42 | shove 2.93 = 1572 |
| 1593-1716 | falling victim | 9bgr: same, pov=victim | cuts/09bg 1-124 | 2.98-5.04 | cut 1593 |
| 1717-1851 | marble runner | 10ar: trailer_marble_column / marble_column | cuts/10a 0-132 | 1.75-4.00 | shove 3.00 = 1802 |
| 1852-2009 | marble scope | 10br: same, pov=guard | cuts/10b 0-157 (Movie) | 2.75-5.38 | hit 4.97 = 1986 |
| 2010-2093 | portal run, first half | 22: NEW trailer_beach_portal | (v59: marble 12s 0-83) | 0.77-2.17 | none |
| 2094-2316 | portal run, hop, shove | 12sr: trailer_finale_marble / finale_fp | cuts/12s 82-306 (Movie) | 2.17-5.92 | portal arrive 3.60, shove 4.48 = 2234 |

Alignment (`refilm_v60.py edit`): Movie Maker takes of the same tape are frame exact, so the two old Movie shots (10b, 12s) and the new ones land exactly. The old
real-time takes carried 3-12 frames of lag, so for those the tool matches the new cut to v59's frames around the impact (+-24 frames) and moves the new footage
to that offset. It prints the offset and a confidence per segment (`v60_work/rough_v60_beats_edit.md`); a weak match keeps game time and says so.
Self-test (stand-in takes cut from v59 with clocks off by 4 frames): every offset recovered, the rebuilt picture differs from v59 by 0.13 grey levels.

Hell shots (open, 6, 7, 8) get the trailer's hell grade `lift 2.6 3` at the edit, as v26-v52 did; the take itself is ungraded.

## 2. Merge

`origin/main` (fe55ef9f, the eye @tool; main's character model, body lighting and first-person shove arms were already in the branch from the 20:21 merge) merged: 2871ef05.
Also brought in because the v59 opening and the new tools need them: `v52-open-b` (trailer_open_pre stage + open_pre tape, capture clock dials; one conflict in
`lava_light_wave.gd`, resolved to main's game-time clock plus the capture override), and `expect.py` + the shot.sh gate from `work-haters-v2` (decision 374).

## 3. Ryan's six items: cause and fix

1. **Lag in the marble sniper shot.** v59 913-995 (cuts/05h, a real-time screen take) holds one frame for 13 frames (930-942) and repeats 917: the take hitched
   while the round was in flight. Fix: Movie Maker is frame exact; 5hr is filmed that way. Cause confirmed by the repeated frames, not by guess.
2. **Random cut in the beach run.** v59 1421 jumps 25 take frames (653 to 679): the 28-frame extension added in v55 was taken from the wrong offset of the same take. Fix: shot 21 is
   one continuous take and the segment is 125 consecutive frames, no splice (the take itself is smooth through 654-678).
3. **Forest shot flickers.** The shot after the beach run is the forest shover (1449-1592). Its first 17 frames were spliced onto the rest from a second copy of the take: at 1466-1467 the
   picture drops from 37 to 31 grey for two frames and stays about 3 lower after (the cut itself is smooth there), and 1546-1550 is five held frames followed by a 5-frame skip.
   Fix: 9agr is one take read from its first frame, one source, nothing joined.
4. **Portal run first half on the beach (new).** Beach portal = `StartEnd/Portal` at 300 deg, r 68.5 (the jetty tip; lane runs bearing 60 to 300, the same way as the run). New stage
   `trailer_beach_portal.gd` plays the marble run's own steps (hold 0.2, three lanes, the 0.45 s glance) from 30.45 m out at the same pace. Headless numbers, metres to the portal:

   | t | 0.73 | 1.23 | 1.73 | 2.23 | 2.73 | 3.23 |
   |---|---|---|---|---|---|---|
   | marble | 30.41 | 27.00 | 21.71 | 16.27 | 10.78 | 5.35 |
   | beach | 30.46 | 26.92 | 21.57 | 16.18 | 10.71 | 5.28 |

   Both arrive at 3.58-3.60 s. The edit cuts beach to marble at game 2.17 s (v59 2094), 16.2 m out on both: same speed, same heading, same glance phase, one run to one portal.
   Interpretation: "first half" = the first 84 of the run's 168 frames before the hop. Needs Ryan's eye: the look of the cut (sand to marble).
5. **Weird cuts after the portal hop.** In the take (cuts/12s, frame exact) there are four breaks: the hop is a game teleport, a hard cut at take 168 (v59 2178); the two frames after it are held
   duplicates (169-170); at the shove the shover's view sits still for 10 frames (233-242) until the game's finale camera cuts to the thrown guard at 243 (the finale's own 0.35 s delay, `FinaleView.cut_delay`);
   then the cinematic. Movie Maker does not remove these. Fixed by the edit: the two held frames are dropped (the run starts two frames earlier to keep the shove on 2234).
   Left as the game does it: the teleport cut and the cut to the cinematic. Interpretation: Ryan means those two plus the held frames. Needs Ryan: if he wants either cut changed, it is a game change (finale camera), not a trailer one.
6. **"The sniper stay[s]".** Confirmed as the rifle left floating. Headless probe at the kill beat: the guard's body is frozen at the window (velocity 0) and his rifle is a child of that body's head (`Runner_0/Head`), still at (-3.4, 28.65, 4.7)
   0.5 s later, while the ragdoll flies out at 32 m/s. v59's frames 2238-2252 show the rifle and a small standing figure at the window after the guard is gone. Fix (stage only, no game code):
   `trailer_finale_marble.gd` re-parents the rifle to the nearest ragdoll part at the kill beat; the probe shows it then flies out with the pelvis (-9.2, 28.2, 9.9 at 4.73 s; -20.7, 25.4, 20.2 at 5.23 s). Needs Ryan's eye on the cut: the rifle rides the ragdoll rigidly.

Movie Maker alone fixes 1, 2 and the stutter parts of 3 and 5; 4 and 6 and the hop's dropped frames are stage or edit changes.

## 4. Mac smoke (expect-gated, headless, same seed and tape as the PC take)

`refilm_v60.sh smoke`, and every entry again through shot.sh's own gate: all 16 pass their `expect:` lines. Each entry's events also match the old PC take's log to a frame
(2r 6/6, 5gr 6/6, 5hr 5/5, 20 6/6, 6r-8r 3/3, 9agr, 9bgr 5/5, 10br 10/10, 12sr 3/3); beach run positions identical to the old log.
One difference, expected: the old 10a take (10:05) was filmed before marble_column was re-taped at 10:23; the tape differs only for the victim and guard from tick 283 (4.72 s), after the 4.0 s the edit uses.
Hell open (1r) hit 9.10 s (3.60 + 5.5 s lead-in), beach portal arrival 3.58 s, finale arrival 3.60 and shove 4.48.

## 5. Left undone / needs Ryan

- Nothing is filmed; the first look at v60 is Ryan's. The new model, the rifle carry and the beach-to-marble cut are unseen.
- Beach shots 20, 21, 22 have no tape (the stages drive deterministic steps; the smoke reproduces the old PC log to the digit). Taping them is a follow-up.
- The forest shover keeps v59's 17 lead-in frames; the new take starts at game 0.03 s so more lead-in exists for a later edit.
- The v59 end-card and title are v59's pixels, re-encoded once more at the final encode (crf 14, as v59).
