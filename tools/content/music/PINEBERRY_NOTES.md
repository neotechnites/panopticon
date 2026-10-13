# Pineberry Rush: trailer music notes (2026-10-13)

Source: Mejer, *Pineberry Rush* (licensed). Master + stems in `~/Documents/Panopticon/Music/Mejer/Pineberry Rush/`
(`01. Pineberry Rush.wav`, `PineberryRushDrums/Bass/Melody.wav`, all 85.5 s, sample-aligned; the melody stem matches the mix exactly in the intro).

## The grid
- **174 BPM, 4/4.** Beat 0.34483 s, bar 1.37931 s. Bar lines sit at n x 1.37931 s from the file start (no offset): in Audacity set 174 and don't move the tracks.
- The 0.3483 s beat (172.3 BPM) used for trailer cuts v28-v49 was wrong; it drifts ~0.4 s by the end. Cuts timed to it may sit slightly off the beat.
- Bars below are counted from 0 (bar n starts at n x 1.37931 s). The drop is **bar 14** (19.310 s, bass onset). 8-bar phrases from the drop start at bars 14, 22, 30, 38, 46.

## Song structure
| song time | what |
|---|---|
| 0-7 s | melody build (the hook) |
| 7-10.4 s | melody fades out |
| 10.4-17.9 s | drums creep in quietly |
| 17.93-19.31 s (bar 13) | the loud drum bar (4 beats) |
| 19.31 s (bar 14) | the drop: everything in |
| 63.45 s (bar 46) | the song itself drops the bass; outro, melody + quiet drums |

## Ryan's rulings (2026-10-13)
- The title hit stays on the drop.
- **End:** everything but the melody falls off on a phrase start, **bar 46** (mid-phrase bar 42 felt wrong). After it, **17 beats** of melody alone under the end card (9 was too short), fading over the last 2.5 s.
- The intro is chosen later from the might-use takes. The bass-only intro didn't work. Half the melody works if it's the **second half** of the phrase.
- Length: ~61 s with the 32-beat intro is fine for an announcement trailer (Derek Lieu: fill with as much content as you have, no more). If too long, cut 32 beats from the end: drop back to the melody on bar 38 instead of 46 (~50 s).
- Ryan cuts the final music by hand (Audacity 4 at 174 BPM, Music workspace, snap to beats).

## Might-use takes (`~/Desktop/panopticon-renders/trailer_reveal/music/might_use/`)
| file | intro | drop (s into file) | end |
|---|---|---|---|
| bed_v50_start_plus5beats_fade4 | the song from 11.008 s: 24 beats of quiet drums, 4 s fade-in | 8.3 | bar 42, 9 beats |
| bed_v50_start_plus1beat_fade4 | the song from 9.629 s: 28 beats, 4 s fade-in | 9.7 | bar 42, 9 beats |
| bed_melody32beats_straight_drop | melody stem bars 30-37 (32 beats), no drum bar | 11.03 | bar 42, 9 beats |
| bed_melody28_drums4_drop | melody bars 30-36 (28 beats), then the drum bar replaces the melody | 11.03 | bar 42, 9 beats |
| bed_melody28_drums4withmelody_drop | as above, but the drum bar plays with melody bar 37 | 11.03 | bar 42, 9 beats |
| bed_melody28_drums4withmelody_drop_tailbar46 | as above | 11.03 | **bar 46**, 9 beats |
| bed_melody28_drums4withmelody_drop_tailbar46_17beats | as above | 11.03 | **bar 46, 17 beats** (61.0 s total) |
| bed_melody12_drums4withmelody_drop_tailbar46_17beats | melody bars 34-36 (second half of the phrase, 12 beats) + drum bar with melody | 5.52 | bar 46, 17 beats (55.5 s; the drop lands where v42's title already is) |
Also in `music/` (not marked): `bed_drums24_ongrid_drop_tailbar46_17beats.wav`, the song from the bar 8 downbeat (24 beats of drum lead-in, no fade, on the grid), drop at 8.28 s, 58.3 s.

## Footage the 61 s version needs (vs v42, 46.15 s)
- before the title: 11.03 s (now 5.70), **+5.33 s**
- gameplay after the drop to bar 46: ends at 49.86 s (now 43.03), **+6.83 s**
- end card, 17 beats: 5.86 s (now 3.12), **+2.75 s**
With the 16-beat intro (melody12 + drums4) no extra opening footage is needed (55.5 s total).

## Tools
- `tools/content/music/pineberry_bed.py` builds beds (v43-v50). Run `python3 pineberry_bed.py <stem dir> <picture length> <out> [song start s] [fade-in s]`. The might-use takes came from one-off variants of it with the same bar arithmetic.
- Trailer picture: v42 (`rough_v42`) is the current cut. v43-v50 are music auditions on v42's picture.
