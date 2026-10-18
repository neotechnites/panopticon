"""shots.json + stages.json + words.json -> the brief's `## n` entries (haters_final format) and its `## script <tag>` table.

    python -m sv3.plan shots.json --stages stages.json --words words.json --brief tools/content/projects/<name>.md --tag vN
"""
import argparse
import json
import os
import re
import sys

PAD = 0.2           # assemble's default `pad:` after each voice line
CARD = "beta signup in bio"


class Refused(Exception):
    pass


def fmt(v):
    """A dial value as the capture line writes it."""
    if isinstance(v, (list, tuple)):
        return ",".join(fmt(x) for x in v)
    if isinstance(v, float):
        return ("%.3f" % v).rstrip("0").rstrip(".")
    return str(v)


def with_dials(capture, pov, dials):
    """The approved capture line with --pov set and its --set= dials replaced by the chosen values (new dials last)."""
    words = capture.split()
    sets, order, at = {}, [], None
    for i, w in enumerate(words):
        if w.startswith("--set="):
            at = i
            for kv in w[6:].split(";"):
                k, _, v = kv.partition("=")
                sets[k] = v
                order.append(k)
    for k, v in (dials or {}).items():
        if k not in sets:
            order.append(k)
        sets[k] = fmt(v)
    cell = "--set=" + ";".join("%s=%s" % (k, sets[k]) for k in order)
    if at is not None:
        words[at] = cell
    elif sets:
        words.append(cell)
    if pov:
        words = [("--pov=%s" % pov) if w.startswith("--pov=") else w for w in words]
        if not any(w.startswith("--pov=") for w in words):
            words.append("--pov=%s" % pov)
    return " ".join(words)


def norm(w):
    return re.sub(r"[^\w']", "", w).lower()


def said(shot, words):
    """The row's text: his recorded words (words.json `text`) where they differ from the script, so captions match."""
    text = (shot.get("text") or "").strip()
    heard = ((words.get(shot["id"]) or {}).get("text") or "").strip() if text else ""
    return heard if heard and [norm(w) for w in heard.split()] != [norm(w) for w in text.split() if norm(w)] else text


def approved_entry(stages, shot):
    st = stages.get(shot["stage"])
    if not st:
        raise Refused("%s: stage %s is not in stages.json" % (shot["id"], shot["stage"]))
    want = shot.get("approved") or {}
    for e in st["approved"]:
        if e["project"] == want.get("project") and int(e["entry"]) == int(want.get("entry", -1)):
            return e
    raise Refused("%s: %s ## %s is not an approved entry of %s" % (shot["id"], want.get("project"), want.get("entry"), shot["stage"]))


def clip_in(shot, e, words):
    """Tape seconds the row starts: tick - (word_start - line_start), clamped >= the entry's in:."""
    beat = shot.get("beat")
    if not beat:
        return float(e["in"])
    tick = (e.get("ticks") or {}).get(beat["tick"])
    if tick is None:
        raise Refused("%s: %s ## %s has no %s tick" % (shot["id"], e["project"], e["entry"], beat["tick"]))
    ws = words[shot["id"]]["words"]
    hit = next((w for w in ws if norm(w["word"]) == norm(beat["word"])), None)
    if hit is None:
        raise Refused("%s: beat word %r is not in the spoken line" % (shot["id"], beat["word"]))
    line_start = 0.0            # the wav (lead trimmed) starts with the row's slot
    return max(float(e["in"]), tick - (hit["t"] - line_start))


def build(shots, stages, words, name, tag, base_n):
    """(entries, table rows) for the brief."""
    root = {}
    for s in shots:
        r = s.get("same_take_as")
        root[s["id"]] = root.get(r, r) if r else s["id"]
    groups = {}
    for s in shots:
        groups.setdefault(root[s["id"]], []).append(s["id"])
    shared = [r for r, g in groups.items() if len(g) > 1]
    entries, rows, cards, n, ends, cut_of, entry_of_cut = [], [], [], base_n, {}, {}, {}
    for i, s in enumerate(shots):
        if s.get("card"):
            cards.append(s["card"])
        if not s.get("stage"):
            continue
        e = approved_entry(stages, s)
        same = next((t for t in shots[:i] if t["id"] in cut_of and root[t["id"]] == root[s["id"]] and t.get("pov") == s.get("pov")
                     and t.get("dials") == s.get("dials") and t.get("approved") == s.get("approved")), None)
        if same is not None:   # the same eyes continuing the same take: one cut file, no second take, no cut on screen
            k = entry_of_cut[cut_of[same["id"]]]
            entries[k] = entries[k].replace("\nsaid: ", "\nsaid: ", 1).replace("\ncapture: ", " / %s\ncapture: " % s["note"], 1)
            cut = cut_of[same["id"]]
            cut_of[s["id"]] = cut
            text = said(s, words)
            at = ends[same["id"]] if same["id"] in ends else float(e["in"])
            cell_in = at - float(e["in"])
            length = float(e["seconds"]) - cell_in
            if s["id"] not in words:
                raise Refused("%s: no voice in words.json" % s["id"])
            need = float(words[s["id"]]["dur"]) + PAD
            if length + 1e-6 < need:
                raise Refused("%s needs %.2f s of picture (voice + pad) but %s has %.2f s from %.2f (decision 356)" % (s["id"], need, cut, length, cell_in))
            ends[s["id"]] = at + need
            rows.append("| %s | %s | %s | %s | line | | %s | |" % (s["id"], cut, fmt(cell_in), fmt(length), text.replace("|", "/")))
            continue
        n += 1
        ent = ["## %d" % n, "said: %s" % s["note"], "capture: %s" % with_dials(e["capture"], s.get("pov"), s.get("dials"))]
        if root[s["id"]] in shared and e.get("tape"):   # an era (ref:) stage has no tape: its match is the ref's own
            ent.append("tape: %s_%s" % (name, tag) if len(shared) == 1 else "tape: %s_%s_%s" % (name, tag, root[s["id"]].lower()))
        if s.get("pov") == "guard":
            ent.append("hud: crosshair")
        if e.get("expect"):
            ent.append("expect: %s" % e["expect"])
        ent += ["seconds: %s" % fmt(float(e["seconds"])), "in: %s" % fmt(float(e["in"]))]
        if e.get("motion") not in (None, ""):   # the approved take's motion floor for shot.sh's gate
            ent.append("motion: %s" % e["motion"])
        if e.get("ref"):                         # an era stage: shot.sh smokes and films it at that ref
            ent.append("ref: %s" % e["ref"])
        ent.append("refilm: %s" % tag)
        entries.append("\n".join(ent))
        cut = "cuts/%02d_%s.mp4" % (n, tag)
        cut_of[s["id"]] = cut
        entry_of_cut[cut] = len(entries) - 1
        text = said(s, words)
        at = clip_in(s, e, words) if text else float(e["in"])
        prev = shots[i - 1] if i else None
        if prev is not None and s.get("same_take_as") and root[s["id"]] == root.get(prev["id"]) and prev["id"] in ends:
            at = ends[prev["id"]]                     # one take, one shot: the next line continues where this one ends
        cell_in = at - float(e["in"])                        # the cut starts at the entry's in:
        length = float(e["seconds"]) - cell_in               # picture left in the cut
        if not text:
            rows.append("| %s | %s | %s | | beat %s | | | |" % (s["id"], cut, fmt(cell_in), fmt(length)))
            continue
        if s["id"] not in words:
            raise Refused("%s: no voice in words.json" % s["id"])
        need = float(words[s["id"]]["dur"]) + PAD
        if length + 1e-6 < need:
            raise Refused("%s needs %.2f s of picture (voice + pad) but %s has %.2f s from %.2f (decision 356)" % (
                s["id"], need, cut, length, cell_in))
        ends[s["id"]] = at + need                            # tape seconds this line's picture ends (fit line = voice + pad)
        rows.append("| %s | %s | %s | %s | line | | %s | |" % (s["id"], cut, fmt(cell_in), fmt(length), text.replace("|", "/")))
    if cards:
        c = cards[-1]
        rows.append("| end | title | | %s | | | %s | |" % (fmt(float(c.get("seconds") or 1.0)), c.get("text") or CARD))
    return entries, rows


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("shots")
    ap.add_argument("--stages", required=True)
    ap.add_argument("--words", required=True)
    ap.add_argument("--brief", required=True)
    ap.add_argument("--tag", required=True)
    a = ap.parse_args(argv)
    shots = json.load(open(a.shots, encoding="utf-8"))
    stages = json.load(open(a.stages, encoding="utf-8"))["stages"]
    words = json.load(open(a.words, encoding="utf-8"))
    text = open(a.brief, encoding="utf-8").read()
    if re.search(r"(?m)^## script %s\s*$" % re.escape(a.tag), text):
        print("PLAN REFUSED: %s already has ## script %s" % (a.brief, a.tag))
        return 2
    base = max([int(m) for m in re.findall(r"(?m)^## (\d+)[a-z]*\s*$", text)] or [0])
    name = os.path.basename(a.brief)[:-3]
    try:
        entries, rows = build(shots, stages, words, name, a.tag, base)
    except Refused as why:
        print("PLAN REFUSED: %s" % why)
        return 2
    voiceless = not any((s.get("text") or "").strip() for s in shots)
    # No voice: no words to caption; the takes' own sound is the mix.
    table = ["## script %s" % a.tag] + (["captions: none", "game: 1.0"] if voiceless else []) + ["pad: %s" % fmt(PAD), "| line | clip | in | len | fit | speed | text | card |"] + rows
    out = text.rstrip("\n") + "\n\n" + "\n\n".join(entries + ["\n".join(table)]) + "\n"
    with open(a.brief, "w", encoding="utf-8") as f:
        f.write(out)
    print("\n".join(table))
    return 0


if __name__ == "__main__":
    sys.exit(main())
