# sv3 stage-path contract (task #603, DESIGN §10/§10.1). Four agents, four files, one interface.

## stages.json  (written by sv3/catalogue.py to tools/content/sv3/stages.json; STAGES.md is its readable twin)
{"stages": {"<stage>": {"map": "hell|forest|marble", "shot": "<--shot value>", "povs": ["guard","runner"],
   "dials": {"<name>": <default>}, "for_shorts": true,            # false for trailer_* (decision 370)
   "approved": [{"project": "haters_final", "entry": 1, "said": "<verbatim>", "capture": "<line verbatim>",
                 "tape": "<name>|null", "expect": "<clauses verbatim>", "seconds": 9.3, "in": 1.0,
                 "ticks": {"hit": 7.78, "shove": null, "out": null, "go": null}}]}},
 "uncatalogued": ["<stage with no approved entry>", ...]}
A stage is choosable only if for_shorts and approved is non-empty.

## shots.json  (written by sv3/translate.py from spec.json + stages.json)
[{"id": "L1", "line": 1, "text": "<voice line verbatim>", "note": "<note verbatim>",
  "stage": "<stage>|null", "pov": "guard|runner|null", "dials": {"<name>": <value>},   # only catalogued dials
  "approved": {"project": "...", "entry": n},            # the approved entry the capture line comes from
  "same_take_as": "<id>|null",                            # second POV of the same tape
  "beat": {"tick": "hit|shove|out|go", "word": "<word in text>"} | null,   # the event lands on this word
  "card": {"text": "beta link in bio", "seconds": 1.0} | null,
  "needs_stage": false, "why": null}]
translate exits 2 when any shot has needs_stage true, printing those ids + notes.

## plan.py  (reads shots.json, stages.json, words.json; writes INTO tools/content/projects/<name>.md)
Appends `## n` entries exactly in haters_final.md's format (said:/capture:/tape:/expect:/seconds:/in:/refilm: <tag>;
hud: crosshair when pov=guard), capture = approved capture line with `--set=` dials replaced by the chosen values,
tape: <name>_<tag> shared by same_take_as shots, expect/seconds/in copied from the approved entry.
Then `## script <tag>` table (| line | clip | in | len | fit | speed | text | card |): clip in = tick - (word_start -
line_start) from words.json, clamped >= the entry's in:; len >= the voice line (decision 356) else exit 2 naming the
line; a final card row 1.0 s "beta link in bio" when shots.json has one.

## short3.sh  (steps, each timed into timing.json)
seams, script, translate, plan, voice (voice.sh), words (pull words.json), short.sh <name> --tag <tag> [--mac-only
stops after short.sh's Mac smokes and never takes the PC lock], pull, frames (ffmpeg -vf fps=1 -> WORK/frames/%03d.png),
review (sv3.review, advisory, non-blocking), deliver. No capture/search/--intent step anywhere.
