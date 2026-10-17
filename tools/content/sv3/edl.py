"""Append the `## script vN` table assemble.py cuts from: one row per script line, clips `path@in:len` at speed 1 (blank),
fit from the search, text = Ryan's line verbatim, cards at words, gif_fade for an image beat, a 1 s `title` end card.

    python -m sv3.edl edl.json shots.json spec.json --brief tools/content/projects/<name>.md --tag vN [--words words.json] [--pad 0.25]
Refuses: a line whose picture is shorter than its voice + pad (no freeze), any speed below 1 (never written), a missing line.
"""
import argparse
import json
import os
import sys

HEADER = """voice: en-US-AndrewNeural +5%
pad: {pad}
game: 1
captions: stack
captions_font: Impact
captions_size: 52
captions_band: 0.06 0.55
| line | clip | in | len | fit | speed | text | card |
"""


def clip_cell(entries):
    parts = []
    for e in entries:
        for p in e.get("parts") or [e]:
            parts.append("%s@%.3f:%.3f" % (p["file"], p["in"], p["len"]))
    return ",".join(parts)


def card_cell(shots, spec_line, entries):
    cells = []
    for s in shots:
        for o in s.get("overlays") or []:
            if o["kind"] == "comment_card":
                word = o["at"].split(":", 1)[1] if ":" in o["at"] else o["at"]
                last = spec_line["text"].split()[-1].strip(".,?!\"'") if spec_line["text"] else word
                cells.append("cards/%s_card0.png w=940 y=0.2 in=0.05 out=0.2 from=%s to=%s+0.6" % (spec_line["id"], word.split()[0], last))
            elif o["kind"] == "gif_fade":
                at = o["at"].split(":", 1)[1] if ":" in o["at"] else "0"
                cells.append("gif_fade external/%s %s %.1f" % (os.path.basename(o.get("url", "image.gif")).split("?")[0], at, o.get("seconds", 1.5)))
    return " ".join(cells)


def rows_for(edl, shots, spec, words, pad):
    rows, problems = [], []
    by_line = {}
    for e in edl:
        by_line.setdefault(e["line"], []).append(e)
    for line in spec:
        entries = by_line.get(line["id"], [])
        lshots = [s for s in shots if s["line"] == line["id"]]
        if lshots and all(x["source"] in ("card", "black") for x in lshots):
            rows.append("| %s | | | | title %.2f | | %s | |" % (line["id"], sum(e["len"] for e in entries) or 1.0, line["text"]))
            continue
        if not entries or not all(e.get("file") for e in entries):
            problems.append("%s has no picture in edl.json" % line["id"])
            continue
        total = sum(e["len"] for e in entries)
        if line["beat"]:
            fit = "beat %.2f" % total
        else:
            w = words.get(line["id"]) if words else None
            if w and total + 1e-6 < w["dur"] + pad:
                problems.append("%s picture %.2f s is shorter than its voice + pad %.2f s" % (line["id"], total, w["dur"] + pad))
            fit = "wait" if any(e.get("fit") == "wait" for e in entries) else "line"
        rows.append("| %s | %s |  |  | %s |  | %s | %s |" % (line["id"], clip_cell(entries), fit, line["text"], card_cell(lshots, line, entries)))
    rows.append("| T | | | | title 1.0 | | beta link in bio | |")
    return rows, problems


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("edl")
    ap.add_argument("shots")
    ap.add_argument("spec")
    ap.add_argument("--brief", required=True)
    ap.add_argument("--tag", required=True)
    ap.add_argument("--words", required=True)
    ap.add_argument("--pad", type=float, default=0.25)
    a = ap.parse_args(argv)
    edl, shots, spec = (json.load(open(p)) for p in (a.edl, a.shots, a.spec))
    words = json.load(open(a.words))
    rows, problems = rows_for(edl, shots, spec, words, a.pad)
    if problems:
        print("EDL REFUSED:\n  " + "\n  ".join(problems))
        return 2
    table = "\n## script %s\n" % a.tag + HEADER.format(pad=a.pad) + "\n".join(rows) + "\n"
    with open(a.brief, "a", encoding="utf-8") as f:
        f.write(table)
    print(table)
    return 0


if __name__ == "__main__":
    sys.exit(main())
