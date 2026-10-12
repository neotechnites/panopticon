"""Parse Ryan's script md, the way he writes it, into spec.json (deterministic; his words are never rewritten).
Forms: `L1 "text" {note}` (note may follow on the next lines, or as `-> note`), `M1 {note}`, devlog `text<TAB/4 spaces>shot`, `## N` + `said:` blocks."""
import hashlib, json, os, re, sys

HEADER_KEYS = ("kind", "music", "captions", "base", "cutoff", "voice", "tag", "aspect")
FLAG_RES = [("refilm", re.compile(r"\brefilm\b", re.I)), ("look_override", re.compile(r"\blook[_ -]?override\b", re.I)),
            ("freeze_waive", re.compile(r"\bfreeze:?\s*waive\b", re.I)), ("keep_audio", re.compile(r"\bkeep[_ -]audio\b|\bwith (its|their) own audio\b", re.I)),
            ("letterbox", re.compile(r"\bletterbox", re.I))]
ID_RE = re.compile(r"^\s*([LlMm])(\d+)([a-z]?)\b[.:)]?\s*(.*)$")
PAUSE_RE = re.compile(r"\((?:pause|beat)(?:[ :]*([\d.]+)\s*s?)?\)", re.I)
QUOTES = {"“": '"', "”": '"', "‘": "'", "’": "'"}
SEP_RE = re.compile(r"\t+| {3,}")


def _norm_quotes(s):
    for a, b in QUOTES.items():
        if a in ('“', '”'): s = s.replace(a, b)
    return s


def _pauses(text):
    """Strip (pause)/(pause 1.5s) markers; keep where they were."""
    out, pauses, last = [], [], 0
    for m in PAUSE_RE.finditer(text):
        out.append(text[last:m.start()]); last = m.end()
        at = len("".join(out).rstrip())
        pauses.append({"at_char": at, "seconds": float(m.group(1)) if m.group(1) else None})
    out.append(text[last:])
    clean = re.sub(r"\s{2,}", " ", "".join(out)).strip()
    return clean, pauses


def _flags(note):
    return [f for f, r in FLAG_RES if r.search(note or "")]


def _header(lines, warnings):
    h = {}
    for ln in lines:
        m = re.match(r"^([a-z_]+):\s*(.*?)\s*$", ln)
        if not m or m.group(1) not in HEADER_KEYS or m.group(1) in h: continue
        k, v = m.group(1), re.sub(r"\s+#.*$", "", m.group(2)).strip()
        h[k] = v
    raw_voice = h.get("voice")
    if raw_voice is not None:
        lv = raw_voice.lower()
        h["voice_raw"] = raw_voice
        h["voice"] = "none" if lv.startswith(("no", "none")) else "ryan" if lv.startswith("ryan") else "andrew"
    if h.get("kind") and h["kind"] not in ("short", "devlog", "trailer"):
        warnings.append("header kind %r unknown; using short" % h["kind"]); h["kind"] = "short"
    if h.get("captions") and h["captions"] not in ("pop", "stack", "none"):
        warnings.append("header captions %r unknown; using pop" % h["captions"]); h["captions"] = "pop"
    for k in ("music", "base", "cutoff", "tag"):
        if k in h and h[k].lower() in ("", "none", "no", "-"): h[k] = None
    return h


def _take_braces(s, warnings, lineno):
    """Pull every {note} out of s. Returns (rest, [notes], open_note_or_None). A brace left open continues."""
    notes, rest, i = [], [], 0
    while True:
        a = s.find("{", i)
        if a < 0:
            rest.append(s[i:]); return "".join(rest), notes, None
        rest.append(s[i:a])
        b = s.find("}", a + 1)
        if b < 0:
            return "".join(rest), notes, s[a + 1:]
        notes.append(s[a + 1:b].strip()); i = b + 1


def _split_text(body, warnings, lineno):
    """`"voice text" trailing` -> (text, trailing). Unquoted text runs to the end (braces already removed)."""
    body = body.strip()
    if body.startswith('"'):
        e = body.find('"', 1)
        if e < 0:
            warnings.append("line %d: unclosed quote" % lineno); return body[1:].strip(), ""
        return body[1:e].strip(), body[e + 1:].strip()
    return body.strip().strip('"').strip(), ""


def parse_tagged(src_lines, warnings):
    """`L1 "text" {note}` form. Notes may sit on following lines in braces or after `->`."""
    out, cur, open_note = [], None, None
    in_quote = None
    for n, raw in enumerate(src_lines, 1):
        ln = _norm_quotes(raw.rstrip("\n"))
        if open_note is not None:  # inside a brace that spans lines
            if not ln.strip() or (ID_RE.match(ln) and re.search(r'["{]', ln)):  # stray: brace never closed
                warnings.append("line %d: unclosed {" % cur["src_line"]); cur["notes"].append(open_note.strip()); open_note = None
            else:
                b = ln.find("}")
                if b < 0: open_note += " " + ln.strip(); continue
                cur["notes"].append((open_note + " " + ln[:b]).strip()); open_note = None
                ln = ln[b + 1:]
                if not ln.strip(): continue
        if in_quote is not None:  # a quoted voice line that spans lines
            e = ln.find('"')
            if e < 0: in_quote += " " + ln.strip(); continue
            cur["text"] = (in_quote + " " + ln[:e]).strip(); in_quote = None
            ln = ln[e + 1:]
        m = ID_RE.match(ln)
        if m and (m.group(4).lstrip().startswith(('"', "{", "(")) or m.group(4).strip() == "" or "{" in m.group(4)):
            cur = {"id": m.group(1).upper() + m.group(2) + m.group(3), "notes": [], "text": "", "src_line": n}
            out.append(cur)
            body = m.group(4)
            rest, notes, op = _take_braces(body, warnings, n)
            cur["notes"] += notes
            if op is not None: open_note = op.strip()
            r = rest.strip()
            if r.startswith('"') and r.count('"') == 1:
                in_quote = r[1:].strip(); continue
            text, trail = _split_text(rest, warnings, n)
            cur["text"] = text
            if trail.startswith("->"): cur["notes"].append(trail[2:].strip())
            continue
        if cur is None: continue
        s = ln.strip()
        if not s:
            continue
        if s.startswith("{"):
            rest, notes, op = _take_braces(s, warnings, n)
            cur["notes"] += notes
            if op is not None: open_note = op.strip()
            continue
        if s.startswith("->"):
            cur["notes"].append(s[2:].strip()); continue
        if s.startswith("#") or re.match(r"^[a-z_]+:\s", s) or s.startswith("|"):
            cur = None  # free notes, tables and headers end a line's continuation
    if open_note is not None and cur is not None:
        warnings.append("line %d: unclosed {" % cur["src_line"]); cur["notes"].append(open_note.strip())
    return out


def parse_tabbed(src_lines, warnings):
    """Devlog form: `voice text<TAB or 3+ spaces>shot`; a line that starts with whitespace is shot only."""
    out, nl, nm = [], 0, 0
    for n, raw in enumerate(src_lines, 1):
        ln = _norm_quotes(raw.rstrip("\n"))
        if not ln.strip() or ln.lstrip().startswith("#"): continue
        if ln[:1] in (" ", "\t"):
            nm += 1
            out.append({"id": "M%d" % nm, "text": "", "notes": [ln.strip()], "src_line": n, "auto_id": True}); continue
        parts = SEP_RE.split(ln, 1)
        text = parts[0].strip(); note = parts[1].strip() if len(parts) > 1 else ""
        rest, notes, op = _take_braces(text, warnings, n)
        if notes: text = rest.strip()
        if not note and not notes: warnings.append("line %d: no shot note" % n)
        nl += 1
        out.append({"id": "L%d" % nl, "text": text, "notes": notes + ([note] if note else []), "src_line": n, "auto_id": True})
    return out


def parse_blocks(src_lines, warnings, voiced):
    """Older brief form: `## N` blocks with said:/caption:."""
    out, cur = [], None
    for n, raw in enumerate(src_lines, 1):
        ln = raw.rstrip("\n")
        m = re.match(r"^##\s+(\w+)\s*$", ln)
        if m:
            k = m.group(1)
            if not re.match(r"^\d+[a-z]?$", k): cur = None; continue
            cur = {"id": ("L" if voiced else "M") + k, "text": "", "notes": [], "src_line": n, "auto_id": True}
            out.append(cur); continue
        if cur is None: continue
        kv = re.match(r"^(said|caption|text|cut):\s*(.*)$", ln)
        if kv:
            if kv.group(1) == "said": cur["notes"].append(kv.group(2).strip())
            elif kv.group(1) == "cut": cur["notes"].append("cut: " + kv.group(2).strip())
            elif kv.group(1) == "text": cur["text"] = kv.group(2).strip().strip('"')
            else: cur.setdefault("captions", []).append(kv.group(2).strip())
    return out


def parse(path):
    src = open(path, encoding="utf-8").read()
    lines = src.splitlines()
    warnings = []
    name = os.path.splitext(os.path.basename(path))[0]
    m = re.match(r"^#\s+(\S+)\s*$", lines[0]) if lines else None
    if m and re.match(r"^[\w-]+$", m.group(1)): name = m.group(1)
    header = _header(lines, warnings)
    tagged = [l for l in lines if ID_RE.match(l) and re.search(r"[\"{]|“", l)]
    if tagged:
        raw = parse_tagged(lines, warnings); form = "tagged"
    elif any(re.match(r"^##\s+\d+\s*$", l) for l in lines):
        raw = parse_blocks(lines, warnings, header.get("voice") not in ("none",)); form = "blocks"
    else:
        body = lines[1:] if lines and lines[0].startswith("#") else lines
        raw = parse_tabbed(body, warnings); form = "tabbed"
        for r in raw: r["src_line"] += 1 if lines and lines[0].startswith("#") else 0
    seen, rows = {}, []
    for r in raw:
        rid = r["id"]
        if rid in seen:
            k = 0
            while True:
                k += 1; alt = rid + "abcdefghijklmnopqrstuvwxyz"[k - 1] if not rid[-1].isalpha() else rid[:-1] + chr(ord(rid[-1]) + k)
                if alt not in seen: break
            warnings.append("line %d: duplicate id %s renamed %s" % (r["src_line"], rid, alt)); rid = alt
        seen[rid] = 1
        text, pauses = _pauses(r["text"])
        note = " | ".join(x for x in r["notes"] if x)
        row = {"id": rid, "kind": "music" if rid.startswith("M") or not text else "line", "text": text, "note": note,
               "pauses": pauses, "flags": _flags(note), "src_line": r["src_line"]}
        if r.get("auto_id"): row["auto_id"] = True
        if r.get("captions"): row["captions"] = r["captions"]
        if not note: warnings.append("%s (line %d): no shot note" % (rid, r["src_line"]))
        rows.append(row)
    header.setdefault("kind", "devlog" if form == "tabbed" else "short")
    header.setdefault("captions", "pop" if header["kind"] == "short" else "none")
    return {"name": name, "src": os.path.abspath(path), "src_sha1": hashlib.sha1(src.encode()).hexdigest(),
            "form": form, "header": header, "lines": rows, "warnings": warnings}


def main(argv=None):
    argv = argv if argv is not None else sys.argv[1:]
    if not argv: raise SystemExit("usage: spec.py <spec.md> [out.json]")
    s = parse(argv[0])
    out = argv[1] if len(argv) > 1 else None
    txt = json.dumps(s, indent=1, ensure_ascii=False)
    if out: open(out, "w", encoding="utf-8").write(txt + "\n")
    else: print(txt)
    for w in s["warnings"]: print("spec: " + w, file=sys.stderr)


if __name__ == "__main__":
    main()
