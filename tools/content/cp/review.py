"""G14: Gemini judges every script line of the delivered cut against its shot note -> review.json.
Any defect fails the line with a precise reason and a fix action (reshoot | recut | revoice)."""
import argparse
import json
import os
import re
import sys
from concurrent.futures import ThreadPoolExecutor

from . import gemini

FPS = 2            # brief: 2 fps over the whole cut
REASK_FPS = 8      # design (e): a failing line is re-asked once on its own window
REASK_PAD_S = 0.5
FAST_FPS = 10      # coordinator: physical defects need 8-10 fps on a clipped window, not 2
FAST = re.compile(r"\b(fall|falls|falling|fly|flying|flies|throw|thrown|throws|shove|shoves|shoved|ragdoll\w*|"
                  r"pit|hit|hits|shot|shoots|jump\w*|wall|tumbl\w*|knock\w*|death|dies|launch\w*)\b", re.I)
VOICE_REF = os.path.join(os.path.dirname(__file__), "ref", "voice_andrew.mp3")  # the approved narrator
CLIP_SWEEP = ("camera_inside_geometry",)  # its own call: a focused question finds clipping a long list misses
SWEEP = ("desktop_or_os_ui", "editor_ui_or_files", "text_overlap", "frozen_or_looping",
         "slowed_motion", "letterboxed_or_cropped")

# defect -> what the orchestrator does to that one line
DEFECTS = {
    "camera_inside_geometry": ("reshoot", "the camera clips into geometry: a large flat-shaded rock, wall or terrain "
                               "surface pressed right up against the lens, covering a corner or edge of the frame, "
                               "often with a hard straight edge cutting across the view; a surface seen from the "
                               "inside; or the view passing through a solid rock, wall, tree, prop or character"),
    "character_clipping": ("reshoot", "a character's body (a ragdoll, a thrown or falling guard, a shoved prisoner) "
                           "sinks into or passes through a wall, floor, rock or another body"),
    "desktop_or_os_ui": ("recut", "any Windows/macOS desktop, taskbar, wallpaper, window frame, cursor or OS dialog"),
    "editor_ui_or_files": ("reshoot", "agent or tooling files are readable on screen: CLAUDE.md, any .md file, .claude, "
                           "AGENTS, 'agent', 'AI', tools/ or addons/ folders, terminal text. An editor view or code "
                           "card the NOTE asks for is fine; a plain grey background or test map is not editor UI"),
    "text_overlap": ("recut", "two pieces of TEXT share screen space at the same time: a caption over a card, a caption "
                     "over in-game text or HUD text, or cards over each other. A caption over the game picture is "
                     "normal and NOT a defect"),
    "event_off_word": ("recut", "the BEAT event (hit, shove, death...) does not happen on its word: it lands visibly "
                       "before or after the word is spoken"),
    "robot_voice": ("revoice", "the narration sounds robotic or broken: a different, more synthetic engine than the "
                    "reference narrator, or garbled, stretched, spelled-out or mispronounced words, or glitches. A "
                    "voice that sounds like the reference narrator is NOT a defect"),
    "voice_mismatch": ("revoice", "the words heard differ from the VOICE text (missing, extra or different words); "
                       "case, punctuation and the script's spelling do not count"),
    "frozen_or_looping": ("recut", "the picture freezes, holds a still frame, or visibly repeats/loops"),
    "slowed_motion": ("recut", "footage plays in slow motion or sped up: people, particles or the camera move "
                      "slower or faster than real game speed"),
    "cut_mid_action": ("recut", "the shot cuts away in the middle of the action the note asks for, too fast to read"),
    "letterboxed_or_cropped": ("recut", "black bars, a landscape clip shown inside a portrait frame on a blurred or "
                               "plain background, a small picture inside the frame, or the subject cropped off. The game's own sniper-scope "
                               "circle is HUD, not cropping"),
    "wrong_camera_position": ("reshoot", "the camera is not where the note implies (e.g. a sniper POV must be on the "
                              "tower platform looking down; a runner POV on the ground among runners)"),
    "text_content_or_style": ("recut", "on-screen text is wrong against the spec: a word that differs from what is "
                              "said or from the OVERLAY text, a quote shown without its quotation marks, or captions too "
                              "small to read on a phone, or much smaller or in a different style or place than the CAPTIONS spec. Pop captions "
                              "showing a few words at a time in sync with the voice are correct, not missing words"),
    "wrong_pov": ("reshoot", "the camera point of view is not the one the note asks for"),
    "wrong_map": ("reshoot", "the place shown is not the one the note asks for"),
    "wrong_event": ("reshoot", "what happens on screen is not what the note asks for"),
    "robotic_motion": ("reshoot", "players or the camera move like a bot: rigid straight lines, snapping turns, "
                       "no human jitter, people standing still to be shot"),
    "too_dark_or_blown_out": ("reshoot", "the picture is much darker or brighter than a normal game frame; detail lost"),
}
FAIL_DEFECTS = set(DEFECTS)

_LINE = {"type": "object", "properties": {
    "id": {"type": "string"},
    "start": {"type": "number"}, "end": {"type": "number"},
    "heard": {"type": "string"}, "seen": {"type": "string"},
    "matches_note": {"type": "string", "enum": ["yes", "partly", "no"]},
    "defects": {"type": "array", "items": {"type": "string"}},
    "why": {"type": "string"}},
    "required": ["id", "start", "end", "heard", "seen", "matches_note", "defects", "why"],
    "propertyOrdering": ["id", "start", "end", "heard", "seen", "matches_note", "defects", "why"]}
SCHEMA = {"type": "object", "properties": {
    "lines": {"type": "array", "items": _LINE},
    "overall_defects": {"type": "array", "items": {"type": "object", "properties": {
        "t": {"type": "number"}, "defect": {"type": "string"}, "why": {"type": "string"}},
        "required": ["t", "defect", "why"]}}},
    "required": ["lines", "overall_defects"], "propertyOrdering": ["lines", "overall_defects"]}


def _fmt(t):
    return "?" if t is None else f"{t:.2f}"


def windows(plan, edl):
    """Line windows in the final from edl.json; None where the edl has none (Gemini then locates the line)."""
    w = {}
    for l in (edl or {}).get("lines", []):
        if l.get("start") is not None and l.get("dur") is not None:
            w[l["id"]] = (float(l["start"]), float(l["start"]) + float(l["dur"]))
    beats = {l["id"]: l.get("beats", []) for l in (edl or {}).get("lines", [])}
    return w, beats


def prompt(plan, win, beats, only=None):
    w, h = plan.get("aspect", [1080, 1920])
    out = [
        "You are checking a video edit against its shot list. Judge only what is visible and audible. Be strict: "
        "a defect you can see or hear must be reported, even if brief.",
        f"Output size: {w}x{h} {'portrait' if h > w else 'landscape'}. The game is a low-poly N64-style "
        "first-person game; its low-poly look is NOT a defect.",
        "For EACH line below, watch its window [start, end] (if the window is ?, find it by the VOICE words or the "
        "note and report the start and end you found) and report:",
        "- heard: the words spoken in the window, verbatim",
        "- seen: what is on screen, concretely (camera POV, place, who moves, what happens, any text and where)",
        "- matches_note: yes | partly | no, judged strictly against the NOTE",
        "- defects: zero or more of these ids, or other:<short text>:",
    ]
    out += [f"    {k}: {v[1]}" for k, v in DEFECTS.items()]
    out.append("- why: one precise sentence naming the moment (seconds) and what is wrong, if anything is.")
    out.append("Check the camera POSITION each note implies, not just the POV kind. Check every on-screen text "
               "against the spec: exact words, quotation marks on quotes, caption size and style.")
    cap = plan.get("captions")
    style = plan.get("caption_style") or {}
    if cap and cap != "none":
        desc = {"pop": "word-by-word pop captions, bold and large, centred, "
                "lower third, a few words at a time in sync with the voice", "stack": "stacked persistent quotes, each with its "
                "quotation marks"}.get(cap, cap)
        extra = ", ".join(f"{k}={v}" for k, v in style.items())
        out.append(f"CAPTIONS spec: {desc}{'; ' + extra if extra else ''}; caption words are the VOICE words.")
    out.append("Lines:")
    for l in plan["lines"]:
        if only and l["id"] not in only:
            continue
        s, e = win.get(l["id"], (None, None))
        voice = f'"{l["text"]}"' if l.get("text") else "(no voice)"
        row = f'{l["id"]} [{_fmt(s)}-{_fmt(e)}] VOICE: {voice} NOTE: {{{l.get("note", "")}}}'
        for b in beats.get(l["id"]) or l.get("beats") or []:
            at = f' at {b["t_word"]:.2f}' if b.get("t_word") is not None else ""
            row += f' BEAT: {b.get("event", "event")} lands on "{b["word"]}"{at}'
        for o in l.get("overlays") or []:
            row += f' OVERLAY: {o.get("kind")} {o.get("handle", "")} text exactly: "{o.get("text", "")}" ({o.get("in")} to {o.get("out")})'
        out.append(row)
    out.append("Then overall_defects: anything between lines, at cuts, at the head or the tail (t = seconds).")
    return "\n".join(out)


def verdict(line):
    """(pass, defects that fail, action). `partly` passes; `no` or any listed defect fails."""
    bad = [d for d in line.get("defects", []) if d.split(":")[0] in FAIL_DEFECTS]
    if line.get("matches_note") == "no" and not bad:
        bad = ["wrong_event"]
    if not bad:
        return True, [], None
    actions = [DEFECTS[d.split(":")[0]][0] for d in bad]
    action = next(a for a in ("reshoot", "revoice", "recut") if a in actions)
    return False, bad, action


def reason(line, bad):
    """`L7 [26.10-30.70] camera_inside_geometry at 27.50s: <what>; wrong_event: <why>`."""
    head = f'{line["id"]} [{_fmt(line.get("start"))}-{_fmt(line.get("end"))}] '
    timed, plain = [], []
    for d in bad:
        c = next((c for c in line.get("claims", []) if c.split(" ")[0].split(":")[0] == d and " at " in c), None)
        timed.append(c) if c else plain.append(d)
    if plain:
        timed.append(f'{",".join(plain)}: {line.get("why", "").strip()}')
    return head + "; ".join(timed)


def times(line):
    """Seconds named in a failing line's claims, for the orchestrator to cut around or reshoot."""
    return sorted({float(m) for c in line.get("claims", []) for m in re.findall(r" at (\d+(?:\.\d+)?)s", c)})


SWEEP_SCHEMA = {"type": "object", "properties": {"moments": {"type": "array", "items": {"type": "object",
    "properties": {"at": {"type": "string", "description": "timestamp MM:SS.s"},
                   "defect": {"type": "string", "enum": list(SWEEP + CLIP_SWEEP)},
                   "why": {"type": "string"}}, "required": ["at", "defect", "why"]}}}, "required": ["moments"]}


def _secs(at):
    """'MM:SS.s' (or 'SS.s') -> seconds; Gemini reads time as MM:SS more reliably than as a float."""
    try:
        parts = [float(x) for x in str(at).strip().split(":")]
    except ValueError:
        return None
    t = 0.0
    for x in parts:
        t = t * 60 + x
    return t
CONFIRM_SCHEMA = {"type": "object", "properties": {"confirmed": {"type": "array", "items": {"type": "string"}},
    "heard": {"type": "string"}, "seen": {"type": "string"},
    "matches_note": {"type": "string", "enum": ["yes", "partly", "no"]}, "why": {"type": "string"}},
    "required": ["confirmed", "heard", "seen", "matches_note", "why"]}


def sweep_prompt(kinds):
    return ("This is game footage from a low-poly first-person game. Watch the whole video frame by frame and list "
            "EVERY moment (at = timestamp MM:SS.s) showing one of these defects. List nothing if there are none.\n" +
            "\n".join(f"  {k}: {DEFECTS[k][1]}" for k in kinds))


def confirm_prompt(line, claims):
    voice = f'"{line["text"]}"' if line.get("text") else "(no voice)"
    return (f'This is the window of line {line["id"]} of an edit. VOICE: {voice} NOTE: {{{line.get("note", "")}}}\n'
            "A first look reported these defects:\n" + "\n".join(f"  {c}" for c in claims) +
            "\nLook closely at each reported moment. Anything the NOTE itself asks for is not a defect. Return in `confirmed` the ids of the defects that are really "
            "there (ids only, from: " + ", ".join(DEFECTS) + "), plus heard, seen, matches_note against the NOTE, "
            "and why (one precise sentence with seconds).\nDefinitions:\n" +
            "\n".join(f"  {k}: {v[1]}" for k, v in DEFECTS.items()))


def fast_prompt(line):
    return (f'Line {line["id"]} of a game edit, NOTE: {{{line.get("note", "")}}}. Watch every frame of this window. '
            "List EVERY moment (at = timestamp MM:SS.s in the full video) where a character's body or the camera "
            "clips into or passes through map geometry (wall, floor, rock, tower, pit edge) or where two bodies "
            "interpenetrate, including after a throw, fall or shove. List nothing if none.\n"
            f"  camera_inside_geometry: {DEFECTS['camera_inside_geometry'][1]}\n"
            f"  character_clipping: {DEFECTS['character_clipping'][1]}")


FAST_SCHEMA = {"type": "object", "properties": {"moments": {"type": "array", "items": {"type": "object",
    "properties": {"at": {"type": "string"}, "defect": {"type": "string",
                   "enum": ["camera_inside_geometry", "character_clipping"]}, "why": {"type": "string"}},
    "required": ["at", "defect", "why"]}}}, "required": ["moments"]}


def is_fast(line):
    """Beats with fast action (a beat, or a fall/throw/shove/hit/wall in the note) get a 10 fps clip check."""
    return bool(line.get("beats")) or bool(FAST.search(line.get("note", "")))


def _line_at(lines, t):
    return next((l for l in lines if l.get("start") is not None and l["start"] - 0.05 <= t < l["end"]), None)


def review(video, plan, edl=None, out=None, model=gemini.PRO, reask=True, voice_ref=VOICE_REF, geometry=None,
           log=print):
    """Whole-cut pass, focused sweeps, 10 fps clip checks on fast lines, then one confirming re-ask per failing line.
    `geometry` = {line: [final-time s]} from run_clip [clip] events: the primary clipping check, never re-asked."""
    win, beats = windows(plan, edl)
    ids = [l["id"] for l in plan["lines"]]
    by_id = {l["id"]: l for l in plan["lines"]}
    with gemini.Video(video) as v:
        refs = ()
        ref_note = ""
        if voice_ref:
            ref = gemini.Video(voice_ref).__enter__()
            refs = (("REFERENCE: the approved narrator voice (audio only):", ref),)
            ref_note = "\nThe REFERENCE audio above is the approved narrator voice; judge robot_voice against it."
        try:
            with ThreadPoolExecutor(3) as ex:
                fr = ex.submit(v.json, prompt(plan, win, beats) + ref_note, SCHEMA, model=model, fps=FPS, refs=refs)
                fs = [ex.submit(v.json, sweep_prompt(k), SWEEP_SCHEMA, model=model, fps=FPS)
                      for k in (CLIP_SWEEP, SWEEP)]
                r = fr.result()
                sw = {"moments": [m for f in fs for m in f.result().get("moments", [])]}
            got = {l["id"].upper(): l for l in r.get("lines", [])}
            lines = []
            for lid in ids:
                g = dict(got.get(lid.upper()) or {"id": lid, "heard": "", "seen": "", "matches_note": "no",
                                                  "defects": ["other:line not found in the cut"], "why": "not reported"})
                g["id"] = lid
                if lid in win:
                    g["start"], g["end"] = win[lid]
                g["claims"] = [f'{d}: {g.get("why", "")}' for d in g.get("defects", [])]
                lines.append(g)
            for m in sw.get("moments", []):
                m["t"] = _secs(m["at"])
                l = None if m["t"] is None else _line_at(lines, m["t"])
                if l is None:
                    continue
                if m["defect"] not in l["defects"]:
                    l["defects"].append(m["defect"])
                l["claims"].append(f'{m["defect"]} at {m["t"]:.2f}s: {m["why"]}')
            fast = [g for g in lines if g.get("start") is not None and is_fast(by_id[g["id"]])]
            with ThreadPoolExecutor(4) as ex:
                futs = {g["id"]: ex.submit(v.json, fast_prompt(by_id[g["id"]]), FAST_SCHEMA, model=model,
                                           fps=FAST_FPS, start=max(0.0, g["start"] - 0.25), end=g["end"] + 0.25)
                        for g in fast}
                for g in fast:
                    for m in futs[g["id"]].result().get("moments", []):
                        t = _secs(m["at"])
                        if t is None:
                            continue
                        if t < g["start"] - 0.5:  # answered relative to the clipped window
                            t += g["start"]
                        if not g["start"] - 0.5 <= t <= g["end"] + 0.5:
                            continue  # a timestamp outside the window it watched is a misread
                        g.setdefault("hard", []).append(m["defect"])
                        g["claims"].append(f'{m["defect"]} at {t:.2f}s ({FAST_FPS} fps): {m["why"]}')
            for g in lines:
                for t in (geometry or {}).get(g["id"], []):
                    g.setdefault("hard", []).append("camera_inside_geometry")
                    g["claims"].append(f"camera_inside_geometry at {t:.2f}s: run_clip [clip] event (camera sphere hit geometry)")
            for g in lines:
                lid = g["id"]
                for d in g.get("hard", []):
                    if d not in g["defects"]:
                        g["defects"].append(d)
                ok, bad, action = verdict(g)
                if not ok and reask and g.get("start") is not None:
                    s, e = max(0.0, g["start"] - REASK_PAD_S), g["end"] + REASK_PAD_S
                    log(f"review: {lid} failed ({','.join(bad)}), confirming on [{s:.2f}-{e:.2f}] at {REASK_FPS} fps")
                    c = v.json(confirm_prompt(by_id[lid], g["claims"]) + ref_note, CONFIRM_SCHEMA, model=model,
                               fps=REASK_FPS, start=s, end=e, refs=refs)
                    conf = [d for d in c.get("confirmed", []) if d.split(":")[0] in FAIL_DEFECTS]
                    conf += [d for d in g.get("hard", []) if d not in conf]  # 10 fps and run_clip finds stand
                    g.update({"heard": c["heard"] or g["heard"], "seen": c["seen"] or g["seen"],
                              "matches_note": c["matches_note"], "first_look": g["defects"], "defects": conf,
                              "why": c["why"] or g.get("why", "")})
                    ok, bad, action = verdict(g)
                    g["reask"] = "passed" if ok else "confirmed"
                g["pass"] = ok
                g["action"] = action
                g["reason"] = "" if ok else reason(g, bad)
                if ok and g.get("matches_note") == "partly":
                    g["note"] = f'{lid} partly: {g.get("why", "")}'
        finally:
            for _, ref in refs:
                ref.__exit__(None, None, None)
    overall = [f'{_fmt(o.get("t"))}s {o.get("defect")}: {o.get("why", "")}' for o in r.get("overall_defects", [])
               if o.get("defect") and o["defect"].lower() not in ("none", "no defects")]
    failed = [l for l in lines if not l["pass"]]
    res = {"model": model, "fps": FPS, "video": os.path.abspath(video), "lines": lines,
           "overall_defects": overall, "failed": [l["id"] for l in failed],
           "fix": [{"id": l["id"], "action": l["action"], "reason": l["reason"],
                    "window": [l.get("start"), l.get("end")], "at": times(l)} for l in failed],
           "pass": not failed}
    if out:
        with open(out, "w") as f:
            json.dump(res, f, indent=1)
    return res


def gate(res):
    """G14 result from a review.json dict."""
    if res["pass"]:
        n = sum(1 for l in res["lines"] if l.get("matches_note") == "partly")
        return True, f"all {len(res['lines'])} lines match their notes" + (f" ({n} partly)" if n else "")
    return False, " | ".join(l["reason"] for l in res["lines"] if not l["pass"])


def main(argv=None):
    ap = argparse.ArgumentParser(prog="content review")
    ap.add_argument("video")
    ap.add_argument("--plan", required=True, help="plan.json (lines with text and note)")
    ap.add_argument("--edl", help="edl.json: line windows in the final")
    ap.add_argument("--out", help="review.json path")
    ap.add_argument("--model", default=gemini.PRO)
    a = ap.parse_args(argv)
    plan = json.load(open(a.plan))
    edl = json.load(open(a.edl)) if a.edl else None
    res = review(a.video, plan, edl, out=a.out, model=a.model)
    for l in res["lines"]:
        print(("PASS " if l["pass"] else "FAIL ") + (l["reason"] or f'{l["id"]} {l["matches_note"]}: {l["seen"][:110]}'))
    for o in res["overall_defects"]:
        print("overall " + o)
    ok, why = gate(res)
    print(("G14 PASS: " if ok else "G14 FAIL: ") + why)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
