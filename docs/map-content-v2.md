# map-content-v2.md (mapping agent report, 2026-10-17)

7a0ca6d1 Restructure: point every reference at the new homes
8683062c projectile shot 2: a ten-second second take to sit under the rest of the line
7bc13dcd Map 1: undo the editor's accidental nudge of MapBase (it broke every match); playbook: never slow a clip
81b18d96 Content: agent_brief.sh builds shorts-agent instructions from the notes ledger
6a6aba33 Content: per-project notes ledger; version.sh bases on Ryan's latest notes
bb88d17f Content rule 8: short.sh --plan lists every shot (reuse / film / NO STAGE / REFUSED) and exits, non-zero on NO STAGE or REFUSED
ce37d7a8 Content rule 7: every short films in its own PC checkout (C:\dev\worktrees\content_<project>); the lock covers only capture and assemble
ceaaff3c Content rule 6: a rough take never films Movie Maker; shot.sh and run_clip refuse it
749cf2b2 Content rule 5: delivery never overwrites; assemble, short.sh and a shot's file: refuse an existing final or Mac copy
c6f57f54 Content rule 4: captions appear instantly (no fade or scale pop); stack fills from the top of the frame
5c3b24be Content rule 3: at most 4 players; shot.sh refuses a capture over --bots=3 (stage plugin counts included)
6ed7fd72 Content rule 2: trailer footage is trailer_reveal's alone; shot.sh and assemble.py refuse it elsewhere
a46c7c7b Content rule 1: version.sh requires --from <the tag Ryan watched>; short.sh never makes a version
892bd6ff assemble.py: captions_plain and captions_reset from work-haters-v2
fcfebeb7 short.sh: hold the PC lock from sync to assemble so parallel shorts never share C:\dev\verify
3203777c Content v2: PLAYBOOK rewritten to the short.sh flow; smoke brief removed
4089a1f0 Content v2: real-time portrait rough, one take, PC lock, no hold or slow, stack captions, pinned Andrew voice, short.sh and version.sh
8291f16a Content v2: port the trailer capture pipeline (tools/content, tools/capture) onto main by path
1c1
< r"""Speak every line of a brief's ## script table with a Microsoft neural voice.
---
> r"""Speak a brief's script lines as en-US-AndrewNeural +5% through the pinned edge-tts endpoint.
5c5,6
<     python voice.py <project dir> <brief.md> [--force]
---
>     python voice.py --check                                  # preflight only
>     python voice.py <project dir> <brief.md> [tag] [--force]
7,18c8,12
< For each row with text: voice\<line>.mp3 from edge-tts (the voice and rate from
< the script header's `voice:` line, default en-US-AndrewNeural +5%), then
< voice\<line>.wav -- 48 kHz stereo with the leading and trailing silence trimmed
< so a line's length is its spoken length -- and its word boundaries, converted
< to the trimmed wav's timebase, merged into voice\words.json:
< 
<     {"l0": {"file": ..., "dur": 2.78, "lead_trimmed": 0.15,
<             "words": [{"word": "I", "t": -0.04, "dur": 0.11}, ...]}, ...}
< 
< A line is only regenerated when its text, voice or rate changed: the hash of
< those is kept in voice\<line>.txt, so a one-word edit to line 7 re-speaks line 7
< and nothing else. --force re-speaks everything.
---
> The voice, rate and endpoint are constants: no brief, header or flag changes them and
> no other engine exists. A preflight synth runs first; any failure stops with
> "VOICE FAILED: <why>". Per row with text (not a beat): voice\<line>.wav, 48 kHz
> stereo, silence trimmed, and its word timings (wav timebase) in voice\words.json.
> A line is re-spoken only when its text changed (hash in voice\<line>.txt).
26a21
> import tempfile
30a26,30
> VOICE = "en-US-AndrewNeural"
> RATE = "+5%"
> ENDPOINT = "wss://api.msedgeservices.com/tts/cognitiveservices/websocket/v1"
> EDGE_TTS_VERSION = "7.2.8"
> CHECK_TEXT = "Panopticon voice check."
35a36,40
> class VoiceFailed(SystemExit):
>     def __init__(self, why):
>         super().__init__("VOICE FAILED: %s" % why)
10c10
<     | line | clip | in | len | fit | speed | text | card |
---
>     | line | clip | in | len | fit | speed | text | card | grade |
22c22
<                  one holds its last frame
---
>                  one FAILS the cut: "l3 needs +0.40 s of picture"
24d23
<          slow    as line, but a short clip is slowed to fill it
27c26
<                  next line waits for the picture (held if the voice is longer)
---
>                  next line waits for the picture (a longer voice fails, as line)
35,40c34,38
<   speed  playback rate for the window (0.75 slows it); blank is 1. One value
<          covers every clip part; a comma list is one per part; `fill` on the
<          last part is the rate that makes it span exactly what is left of the
<          slot -- slowed when its source is short, trimmed when it is long,
<          never frozen and never fast-forwarded.
<   card   a still that slides in over the picture with no cut:
---
>   speed  playback rate, 1 or faster (below 1 fails: nothing is slowed); blank is 1.
>          One value covers every part, a comma list is one per part; `fill` on the
>          last part trims it to what is left of the slot (short source fails).
>   card   a still that slides in over the picture with no cut, in its own band:
>          a card that overlaps the caption band fails the cut.
47,48c45,47
< A fit compares the clip's seconds ON SCREEN (source / speed) with the slot, so
< a slowed clip is measured as what it plays, not as what it holds.
---
>   grade  a grade named in the script header, applied to this line's picture only:
>          `grade_hell: lift 2.6 3` scales RGB by 1 + (2.6 - 1) * (1 - max)^3 --
>          shadows and mids up, hue and saturation kept, black and white fixed.
49a49,55
> Captions: pop = word by word under the voice; stack = each row's text as a quote
> ("..."), shown from the row's start to the end of the cut, each in its own slot of
> the band, top down, never overlapping (a band too full fails); none = no captions.
> Both appear and go instantly: no fade, scale, slide or alpha ramp. Stack fills from the top of the frame.
> 
> A fit compares the clip's seconds ON SCREEN (source / speed) with the slot.
> 
51,54c57,62
< pad: 0.2  captions: pop|none  captions_font: Impact  captions_size: 64
< captions_y: 0.72 (fraction of the height)  game: 0.25 (each take's own sound
< under the voice, linear, tempo-matched to a slowed picture; 0 or absent is
< silent)  copy_720: yes (also write final\<tag>_720.mp4).
---
> pad: 0.2  captions: pop|stack|none  captions_font: Impact  captions_size: 64 (stack 52)
> captions_y: 0.72 (pop, fraction of the height)  captions_band: 0.06 0.55 (stack; top <= 0.1)
> captions_plain: l4 l5 (stack rows shown without quote marks)  captions_reset: l3 (stack: at that
> row's start every earlier quote ends and the slots restart at the top of the band)
> size: 1920x1080 (default 1080x1920)  game: 0.25 (each take's own sound under the
> voice, linear, tempo-matched to the picture; 0 or absent is silent)  copy_720: yes (also write final\<tag>_720.mp4).
79a88,93
> # Every segment is lossless RGB, decoded by its source's own tags: the edit adds no generation.
> # final\\<tag>.mp4 is one H.264 4:2:0 encode of the lossless master (final\\master\\<tag>.mkv).
> TO_709 = "format=rgb24"
> TAIL = ",format=rgb24"
> LOSSLESS = ["-c:v", "libx264rgb", "-preset", "veryfast", "-qp", "0"]