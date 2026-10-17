"""Ryan's raw script -> spec.json [{id, text, note, beat, same_take_as, direction}]. His text and notes are copied byte-for-byte.

    python -m sv3.script <script.md> --out spec.json [--block last] [--section "Short 9"]

A `{note}` closes a line: the text gathered since the previous note (or paragraph break) is that
line's voice. `{note}` with no text, or text that is only a `(pause ...)` direction, is a beat (M id).
A note saying "same shot" continues the previous capture (same_take_as). `--block last` takes the
last chunk of a file whose drafts are separated by 3+ blank lines; `--section` picks a `# header`.
A section with no `{note}` at all is a direction: each paragraph becomes a beat whose note is the text.
"""
import argparse
import json
import re
import sys

PAUSE_RE = re.compile(r"^\(\s*(short\s+)?pause\b[^)]*\)\s*$", re.I)
SAME_RE = re.compile(r"\bsame\s+(shot|take|clip|match)\b", re.I)


def select(raw, block=None, section=None):
    if section:
        parts = re.split(r"(?m)^(?=# )", raw)
        hits = [p for p in parts if p.startswith("# ") and section.lower() in p.splitlines()[0].lower()]
        if not hits:
            raise SystemExit("section not found: %s" % section)
        raw = "\n".join(hits[0].splitlines()[1:])
    if block == "last":
        chunks = [c for c in re.split(r"\n[ \t]*\n[ \t]*\n[ \t]*\n+", raw) if c.strip()]
        raw = chunks[-1]
    # markdown `# header` lines and `key: value` header lines (kind:, voice:, music:) are labels, never voice
    hdr = re.compile(r"^(kind|voice|music|captions|aspect|format|base|cutoff):\s", re.I)
    return "\n".join(l for l in raw.splitlines() if not l.startswith("# ") and not hdr.match(l))


def parse(raw):
    lines, buf = [], []
    has_notes = "{" in raw

    def flush(note):
        text = " ".join(t for t in buf if t)
        buf.clear()
        direction = text if PAUSE_RE.match(text or "") else None
        beat = direction is not None or not text.strip()
        if beat and not note and not text.strip():
            return
        n = len(lines) + 1
        prev = lines[-1]["id"] if lines else None
        entry = {"id": ("M%d" if beat else "L%d") % n, "text": "" if beat else text, "note": note, "beat": beat,
                 "same_take_as": prev if (note and SAME_RE.search(note) and prev) else None}
        if direction:
            entry["direction"] = direction
        lines.append(entry)

    if not has_notes:
        for para in re.split(r"\n\s*\n", raw):
            para = " ".join(p.strip() for p in para.splitlines() if p.strip())
            if para:
                lines.append({"id": "M%d" % (len(lines) + 1), "text": "", "note": para, "beat": True,
                              "same_take_as": None, "direction": "no voice: a direction, not a line"})
        return lines

    i, n = 0, len(raw)
    cur = ""
    while i < n:
        ch = raw[i]
        if ch == "{":
            j = raw.find("}", i)
            note = raw[i + 1:(j if j >= 0 else n)]
            if j < 0:
                note = note.rstrip()
            i = (j + 1) if j >= 0 else n
            buf.append(cur.strip())
            cur = ""
            flush(note)
            continue
        if ch == "\n":
            if cur.strip():
                buf.append(cur.strip())
            cur = ""
            # a blank line ends a paragraph: voice text with no note is kept as a note-less line
            if re.match(r"[ \t]*\n", raw[i + 1:i + 40]) and buf:
                flush("")
            i += 1
            continue
        cur += ch
        i += 1
    if cur.strip():
        buf.append(cur.strip())
    if buf:
        flush("")
    return lines


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("script")
    ap.add_argument("--out")
    ap.add_argument("--block", choices=["last"])
    ap.add_argument("--section")
    a = ap.parse_args(argv)
    raw = select(open(a.script, encoding="utf-8").read(), a.block, a.section)
    spec = parse(raw)
    out = json.dumps(spec, indent=1, ensure_ascii=False)
    if a.out:
        open(a.out, "w", encoding="utf-8").write(out + "\n")
    for e in spec:
        print("%-3s %s%s  {%s}" % (e["id"], "[beat] " if e["beat"] else "", e["text"][:70], e["note"][:80]
                                    + (" <same_take_as %s>" % e["same_take_as"] if e["same_take_as"] else "")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
